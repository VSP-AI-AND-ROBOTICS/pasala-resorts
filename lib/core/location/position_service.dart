import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'geo_point.dart';
import 'location_service.dart';

/// The device's position as a coordinate. The browse screen uses it for
/// the Distance sort and card distances, and the owner's Map location
/// screen uses it for "Use my current location". Abstract, so tests
/// override [positionServiceProvider] with `FakePositionService` instead
/// of touching geolocator.
abstract class PositionService {
  /// The guest's position, already rounded with [GeoPoint.coarse], from a
  /// low-accuracy fix that is cached for 24 h. Null when it cannot be
  /// resolved (permission denied, location off, no platform support).
  /// Never throws.
  Future<GeoPoint?> approximatePosition();

  /// A fresh high-accuracy fix, never cached, or null. Never throws. Only
  /// the owner's Map location screen asks for it.
  Future<GeoPoint?> precisePosition();
}

/// No position at all: what a place-only [LocationService] (e.g. a test
/// fake) provides.
class NoPositionService implements PositionService {
  const NoPositionService();

  @override
  Future<GeoPoint?> approximatePosition() async => null;

  @override
  Future<GeoPoint?> precisePosition() async => null;
}

/// The same object as [locationServiceProvider] when it can also give
/// positions (the real `DeviceLocationService`), so the badge and the
/// Distance sort share one device fix and one permission prompt.
/// Otherwise [NoPositionService].
final positionServiceProvider = Provider<PositionService>((ref) {
  final location = ref.watch(locationServiceProvider);
  return switch (location) {
    final PositionService position => position,
    _ => const NoPositionService(),
  };
});

/// The guest's coarse position for the browse screen. Not `autoDispose`,
/// the same as `currentPlaceProvider`: `LocationBadge`'s "Set location"
/// invalidates both.
final currentPositionProvider = FutureProvider<GeoPoint?>(
  (ref) => ref.watch(positionServiceProvider).approximatePosition(),
  // Screens show their own Retry button; don't also auto-retry (Riverpod 3
  // retries non-Error throws by default).
  retry: (retryCount, error) => null,
);
