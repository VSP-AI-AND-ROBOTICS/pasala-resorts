import 'package:flutter_test/flutter_test.dart';
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
}
