import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/location/geo_point.dart';
import 'package:pasala/core/location/location_cache.dart';
import 'package:pasala/core/location/place_label.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const label = PlaceLabel(locality: 'Bengaluru', country: 'India');

  test('read() returns null when nothing has been cached yet', () async {
    SharedPreferences.setMockInitialValues({});
    final cache = LocationCache(
      await SharedPreferences.getInstance(),
      clock: () => DateTime(2026, 1, 1, 12),
    );

    expect(cache.read(), isNull);
  });

  test('write() then read() returns the same label within 24h', () async {
    SharedPreferences.setMockInitialValues({});
    var now = DateTime(2026, 1, 1, 12, 0);
    final cache = LocationCache(
      await SharedPreferences.getInstance(),
      clock: () => now,
    );

    await cache.write(label);
    now = now.add(const Duration(hours: 23, minutes: 59));

    expect(cache.read(), label);
  });

  test('read() returns null once the cached label is 24h old', () async {
    SharedPreferences.setMockInitialValues({});
    var now = DateTime(2026, 1, 1, 12, 0);
    final cache = LocationCache(
      await SharedPreferences.getInstance(),
      clock: () => now,
    );

    await cache.write(label);
    now = now.add(const Duration(hours: 24, minutes: 1));

    expect(cache.read(), isNull);
  });

  test('a fresh LocationCache reads a label an earlier instance wrote', () async {
    SharedPreferences.setMockInitialValues({});
    final writer = LocationCache(
      await SharedPreferences.getInstance(),
      clock: () => DateTime(2026, 1, 1, 12),
    );
    await writer.write(label);

    final reader = LocationCache(
      await SharedPreferences.getInstance(),
      clock: () => DateTime(2026, 1, 1, 13),
    );

    expect(reader.read(), label);
  });

  group('position', () {
    test('readPoint() is null when no point has been cached', () async {
      SharedPreferences.setMockInitialValues({});
      final cache = LocationCache(await SharedPreferences.getInstance());

      expect(cache.readPoint(), isNull);
    });

    test('writePoint() stores only the coarse point, and readPoint() returns '
        'it within 24h', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      var now = DateTime(2026, 1, 1, 12);
      final cache = LocationCache(prefs, clock: () => now);

      await cache.writePoint(const GeoPoint(17.38512, 78.48671));
      now = now.add(const Duration(hours: 23, minutes: 59));

      expect(cache.readPoint(), const GeoPoint(17.39, 78.49));
      expect(prefs.getDouble('location_cache_lat'), 17.39);
      expect(prefs.getDouble('location_cache_lng'), 78.49);
    });

    test('readPoint() is null once the point is 24h old', () async {
      SharedPreferences.setMockInitialValues({});
      var now = DateTime(2026, 1, 1, 12);
      final cache =
          LocationCache(await SharedPreferences.getInstance(), clock: () => now);

      await cache.writePoint(const GeoPoint(17.39, 78.49));
      now = now.add(const Duration(hours: 24, minutes: 1));

      expect(cache.readPoint(), isNull);
    });

    test('the place and the point expire independently', () async {
      SharedPreferences.setMockInitialValues({});
      var now = DateTime(2026, 1, 1, 12);
      final cache =
          LocationCache(await SharedPreferences.getInstance(), clock: () => now);

      await cache.write(label);
      now = now.add(const Duration(hours: 23));
      await cache.writePoint(const GeoPoint(17.39, 78.49));
      now = now.add(const Duration(hours: 2));

      expect(cache.read(), isNull);
      expect(cache.readPoint(), const GeoPoint(17.39, 78.49));
    });
  });
}
