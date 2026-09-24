import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'device_location_service.dart';
import 'place_label.dart';

/// Resolves the guest's current place (city + country) for the browse
/// hero's location badge. Abstract so widget tests can override
/// [locationServiceProvider] with a fake instead of touching the OS
/// location permission dialog, geolocator, or the network.
abstract class LocationService {
  /// The signed-in device's current place, or null when it cannot be
  /// resolved (permission denied, location services off, or a network/
  /// geocoding failure). Never throws -- every failure mode is a null
  /// result so the badge can fall back to its "Set location" chip.
  Future<PlaceLabel?> currentPlace();
}

/// The real implementation: geolocator permission + a low-accuracy fix,
/// reverse-geocoded via OpenStreetMap Nominatim, cached for 24h in
/// `shared_preferences`. Built once per app run and reused, matching every
/// other repository/service provider in `lib/data/repositories/`.
final locationServiceProvider = Provider<LocationService>((ref) {
  return DeviceLocationService(
    prefs: SharedPreferences.getInstance(),
    client: http.Client(),
  );
});

/// The browse hero's resolved place, via whatever [locationServiceProvider]
/// currently is (the real [DeviceLocationService], or a fake override in
/// tests). Not `autoDispose`: `LocationBadge`'s "Set location" chip retries
/// with `ref.invalidate(currentPlaceProvider)` rather than a fresh
/// subscription, so the in-flight request survives the badge being briefly
/// unmounted (e.g. a scroll that rebuilds the hero).
final currentPlaceProvider = FutureProvider<PlaceLabel?>((ref) {
  return ref.watch(locationServiceProvider).currentPlace();
});
