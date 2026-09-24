import 'dart:convert';

import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'location_cache.dart';
import 'location_service.dart';
import 'nominatim.dart';
import 'place_label.dart';

/// The real [LocationService]: a device permission check/request, a
/// low-accuracy position fix, and a reverse-geocode lookup against
/// OpenStreetMap's Nominatim -- with the label cached for
/// [LocationCache.validFor] so a returning guest isn't asked again on
/// every app open. Sends nothing to this app's own backend; the
/// coordinate goes to Nominatim only, and only to resolve a city name.
class DeviceLocationService implements LocationService {
  DeviceLocationService({required Future<SharedPreferences> prefs, http.Client? client})
    : _prefsFuture = prefs,
      _client = client ?? http.Client();

  final Future<SharedPreferences> _prefsFuture;
  final http.Client _client;

  static const _reverseUrl = 'https://nominatim.openstreetmap.org/reverse';

  @override
  Future<PlaceLabel?> currentPlace() async {
    // Wrapped end-to-end, not just around the geolocator/http calls below:
    // `_prefsFuture` and `cache.write` are also fallible (see
    // `core/current_resort.dart`'s own "wrap every shared_preferences
    // access" rule) and must degrade to the same "unresolved" outcome as a
    // denied permission or a network failure, never an uncaught error that
    // reaches `currentPlaceProvider` as an `AsyncError` the badge has no
    // dedicated state for.
    try {
      final prefs = await _prefsFuture;
      final cache = LocationCache(prefs);

      final cached = cache.read();
      if (cached != null) return cached;

      final resolved = await _resolve();
      if (resolved != null) await cache.write(resolved);
      return resolved;
    } catch (_) {
      return null;
    }
  }

  Future<PlaceLabel?> _resolve() async {
    if (!await _hasPermission()) return null;

    final Position position;
    try {
      position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
        ),
      );
    } catch (_) {
      // Location services off, a platform error, or a timed-out fix --
      // none of these should crash the badge, just leave it unresolved.
      return null;
    }

    return _reverseGeocode(position.latitude, position.longitude);
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
      // A network failure (offline, DNS, timeout, ClientException on web)
      // must never surface as an error state on the badge -- just leave
      // the location unresolved so the "Set location" chip shows instead.
      return null;
    }
  }
}
