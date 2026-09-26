import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/location/geo_point.dart';
import 'package:pasala/core/location/location_service.dart';
import 'package:pasala/core/location/place_label.dart';
import 'package:pasala/core/location/position_service.dart';

class _PlaceOnly implements LocationService {
  @override
  Future<PlaceLabel?> currentPlace() async => null;
}

class _PlaceAndPosition implements LocationService, PositionService {
  @override
  Future<PlaceLabel?> currentPlace() async => null;

  @override
  Future<GeoPoint?> approximatePosition() async => const GeoPoint(17.39, 78.49);

  @override
  Future<GeoPoint?> precisePosition() async =>
      const GeoPoint(17.385044, 78.486671);
}

void main() {
  test('falls back to NoPositionService when the location service only '
      'resolves places', () async {
    final container = ProviderContainer(
      overrides: [locationServiceProvider.overrideWithValue(_PlaceOnly())],
    );
    addTearDown(container.dispose);

    expect(container.read(positionServiceProvider), isA<NoPositionService>());
    expect(await container.read(currentPositionProvider.future), isNull);
  });

  test(
    'uses the location service itself when it also gives positions',
    () async {
      final service = _PlaceAndPosition();
      final container = ProviderContainer(
        overrides: [locationServiceProvider.overrideWithValue(service)],
      );
      addTearDown(container.dispose);

      expect(container.read(positionServiceProvider), same(service));
      expect(
        await container.read(currentPositionProvider.future),
        const GeoPoint(17.39, 78.49),
      );
    },
  );
}
