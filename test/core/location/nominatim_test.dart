import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/location/nominatim.dart';
import 'package:pasala/core/location/place_label.dart';

void main() {
  group('parseNominatimReverse', () {
    test('uses address.city when present', () {
      final json = {
        'address': {
          'city': 'Bengaluru',
          'town': 'Should not be used',
          'country': 'India',
        },
      };
      expect(
        parseNominatimReverse(json),
        const PlaceLabel(locality: 'Bengaluru', country: 'India'),
      );
    });

    test('falls back to town when city is absent', () {
      final json = {
        'address': {'town': 'Coorg', 'country': 'India'},
      };
      expect(
        parseNominatimReverse(json),
        const PlaceLabel(locality: 'Coorg', country: 'India'),
      );
    });

    test('falls back to village when city and town are absent', () {
      final json = {
        'address': {'village': 'Pasala', 'country': 'India'},
      };
      expect(
        parseNominatimReverse(json),
        const PlaceLabel(locality: 'Pasala', country: 'India'),
      );
    });

    test('falls back to county, then state, for rural coordinates', () {
      final withCounty = {
        'address': {'county': 'Kodagu', 'country': 'India'},
      };
      expect(
        parseNominatimReverse(withCounty),
        const PlaceLabel(locality: 'Kodagu', country: 'India'),
      );

      final withState = {
        'address': {'state': 'Karnataka', 'country': 'India'},
      };
      expect(
        parseNominatimReverse(withState),
        const PlaceLabel(locality: 'Karnataka', country: 'India'),
      );
    });

    test('returns null when the response has no address block', () {
      expect(parseNominatimReverse({'error': 'Unable to geocode'}), isNull);
    });

    test('returns null when no locality field is usable', () {
      final json = {
        'address': {'country': 'India'},
      };
      expect(parseNominatimReverse(json), isNull);
    });

    test('returns null when the country is missing', () {
      final json = {
        'address': {'city': 'Bengaluru'},
      };
      expect(parseNominatimReverse(json), isNull);
    });
  });
}
