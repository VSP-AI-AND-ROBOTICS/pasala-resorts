import 'dart:convert';

import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'geo_point.dart';
import 'location_cache.dart';
import 'location_service.dart';
import 'nominatim.dart';
import 'place_label.dart';
import 'position_service.dart';

/// The real [LocationService] and [PositionService]. It checks and
/// requests the device permission, takes a position fix, and
/// reverse-geocodes it against OpenStreetMap's Nominatim.
///
/// The label and a coarse position are each cached for
/// [LocationCache.validFor], so a returning guest is not asked again on
/// every app open. Only a coarse ([GeoPoint.coarse]) position is ever
/// sent to this app's backend, for distance sorting. The exact
/// coordinate goes only to Nominatim, to resolve a city name.
class DeviceLocationService implements LocationService, PositionService {
  DeviceLocationService({required Future<SharedPreferences> prefs, http.Client? client})
    : _prefsFuture = prefs,
      _client = client ?? http.Client();

  final Future<SharedPreferences> _prefsFuture;
  final http.Client _client;

  /// The low-accuracy fix in flight, shared by [currentPlace] and
  /// [approximatePosition]. The browse screen asks for both at once, and
  /// without sharing a cold start would request the permission twice.
  Future<Position?>? _lowFix;

  static const _reverseUrl = 'https://nominatim.openstreetmap.org/reverse';

  @override
  Future<PlaceLabel?> currentPlace() async {
    // Wrapped end-to-end, not just around the geolocator/http calls:
    // `_prefsFuture` and `cache.write` are fallible too, and must degrade
    // to "unresolved" like a denied permission, never an uncaught error.
    try {
      final prefs = await _prefsFuture;
      final cache = LocationCache(prefs);

      final cached = cache.read();
      if (cached != null) return cached;

      final position = await _sharedLowFix();
      if (position == null) return null;
      final resolved =
          await _reverseGeocode(position.latitude, position.longitude);
      if (resolved != null) await cache.write(resolved);
      return resolved;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<GeoPoint?> approximatePosition() async {
    try {
      final prefs = await _prefsFuture;
      final cache = LocationCache(prefs);

      final cached = cache.readPoint();
      if (cached != null) return cached;

      final position = await _sharedLowFix();
      if (position == null) return null;
      final point = GeoPoint(position.latitude, position.longitude).coarse();
      await cache.writePoint(point);
      return point;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<GeoPoint?> precisePosition() async {
    try {
      final position = await _fix(LocationAccuracy.high);
      return position == null
          ? null
          : GeoPoint(position.latitude, position.longitude);
    } catch (_) {
      return null;
    }
  }

  Future<Position?> _sharedLowFix() => _lowFix ??=
      _fix(LocationAccuracy.low).whenComplete(() => _lowFix = null);

  Future<Position?> _fix(LocationAccuracy accuracy) async {
    if (!await _hasPermission()) return null;
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(accuracy: accuracy),
      );
    } catch (_) {
      // Location services off, a platform error, or a timed-out fix --
      // none of these should crash a caller, just leave it unresolved.
      return null;
    }
  }

  Future<bool> _hasPermission() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      return permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always;
    } catch (_) {
      // No host platform implementation (e.g. web without the geolocator
      // web plugin registered, or a test harness with no platform channel)
      // -- treat exactly like a denial rather than crashing.
      return false;
    }
  }

  Future<PlaceLabel?> _reverseGeocode(double lat, double lon) async {
    final uri = Uri.parse(_reverseUrl).replace(
      queryParameters: {
        'format': 'jsonv2',
        'zoom': '10',
        'lat': '$lat',
        'lon': '$lon',
      },
    );

    try {
      final response = await _client.get(
        uri,
        // Nominatim's usage policy requires an identifying User-Agent for
        // every request.
        headers: const {'User-Agent': 'ResortHub/1.0 (guest browse hero)'},
      );
      if (response.statusCode != 200) return null;
      final body = jsonDecode(response.body);
      if (body is! Map<String, dynamic>) return null;
      return parseNominatimReverse(body);
    } catch (_) {
      // A network failure must never surface as an error state on the
      // badge -- just leave the location unresolved.
      return null;
    }
  }
}
