import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/location/geo_point.dart';
import 'package:pasala/data/models/property.dart';

void main() {
  group('Property.fromJson time normalization', () {
    test('truncates a Postgres HH:mm:ss time down to HH:mm', () {
      final property = Property.fromJson(const {
        'id': 'p1',
        'name': 'Pasala Riverside',
        'slug': 'riverside',
        'images': [],
        'amenities': [],
        'check_in_time': '14:00:00',
        'check_out_time': '11:00:00',
      });

      expect(property.checkInTime, '14:00');
      expect(property.checkOutTime, '11:00');
    });

    test('leaves an already-HH:mm time untouched', () {
      expect(Property.normalizeTime('09:30'), '09:30');
    });

    test('round-trips: HH:mm written, HH:mm:ss read back, HH:mm normalized',
        () {
      // Simulates the write -> Postgres storage -> read cycle: the form
      // writes "09:30", Postgres's `time` column stores/returns it with
      // seconds, and normalizeTime must land back on the exact string that
      // was written so a re-opened edit form and showTimePicker never drift.
      const written = '09:30';
      const readBack = '$written:00';
      expect(Property.normalizeTime(readBack), written);
    });
  });

  group('Property.fromJson tax rates', () {
    test('reads the food and spa rates', () {
      final property = Property.fromJson(const {
        'id': 'p1',
        'name': 'Pasala',
        'slug': 'pasala',
        'images': [],
        'amenities': [],
        'tax_pct': 12,
        'fnb_tax_pct': 5,
        'spa_tax_pct': 18.5,
      });

      expect(property.taxPct, 12);
      expect(property.fnbTaxPct, 5);
      expect(property.spaTaxPct, 18.5);
    });

    test('a row without the food and spa keys reads them as 0', () {
      final property = Property.fromJson(const {
        'id': 'p1',
        'name': 'Pasala',
        'slug': 'pasala',
        'images': [],
        'amenities': [],
      });

      expect(property.fnbTaxPct, 0);
      expect(property.spaTaxPct, 0);
    });
  });

  group('Property coordinates', () {
    test('reads lat/lng into latitude, longitude and location', () {
      final property = Property.fromJson(const {
        'id': 'p1',
        'name': 'Pasala Riverside',
        'slug': 'riverside',
        'lat': 17.385044,
        'lng': 78.486671,
      });

      expect(property.latitude, 17.385044);
      expect(property.longitude, 78.486671);
      expect(property.location, const GeoPoint(17.385044, 78.486671));
    });

    test('location is null when the resort has no coordinates', () {
      final property = Property.fromJson(const {
        'id': 'p1',
        'name': 'Pasala Riverside',
        'slug': 'riverside',
      });

      expect(property.latitude, isNull);
      expect(property.location, isNull);
    });

    test('toInsert never writes the coordinates (Map location owns them)', () {
      const property = Property(
        id: 'p1',
        name: 'Pasala Riverside',
        slug: 'riverside',
        description: null,
        address: null,
        images: [],
        amenities: [],
        checkInTime: '14:00',
        checkOutTime: '11:00',
        isActive: true,
        latitude: 17.3,
        longitude: 78.4,
      );

      expect(property.toInsert().containsKey('lat'), isFalse);
      expect(property.toInsert().containsKey('lng'), isFalse);
    });
  });
}
