import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/location/geo_point.dart';
import 'package:pasala/data/models/resort_search.dart';

void main() {
  group('ResortSearchResult.fromJson', () {
    test('parses a full search_resorts row', () {
      final result = ResortSearchResult.fromJson(const <String, dynamic>{
        'id': 'r1',
        'name': 'Lakeview Retreat',
        'slug': 'lakeview',
        'description': 'Quiet lakeside cottages',
        'address': 'Gandipet Road, Hyderabad',
        'images': ['https://example.com/l.jpg'],
        'amenities': ['Pool', 'Wi-Fi'],
        'check_in_time': '14:00:00',
        'check_out_time': '11:00:00',
        'is_active': true,
        'lat': 17.385,
        'lng': 78.4867,
        'distance_km': 12.3,
        'min_price': 4000.00,
        'avg_rating': 4.5,
        'review_count': 2,
      });

      expect(result.property.id, 'r1');
      expect(result.property.name, 'Lakeview Retreat');
      expect(result.property.checkInTime, '14:00');
      expect(result.property.location, const GeoPoint(17.385, 78.4867));
      expect(result.distanceKm, 12.3);
      expect(result.minPrice, 4000);
      expect(result.avgRating, 4.5);
      expect(result.reviewCount, 2);
    });

    test('a row without distance, price or reviews parses to nulls and 0', () {
      final result = ResortSearchResult.fromJson(const <String, dynamic>{
        'id': 'r2',
        'name': 'Day Only Park',
        'slug': 'day-only',
        'images': [],
        'amenities': [],
        'lat': null,
        'lng': null,
        'distance_km': null,
        'min_price': null,
        'avg_rating': null,
        'review_count': 0,
      });

      expect(result.distanceKm, isNull);
      expect(result.minPrice, isNull);
      expect(result.avgRating, isNull);
      expect(result.reviewCount, 0);
      expect(result.property.location, isNull);
    });

    test('a whole-number distance arrives as an int and still parses', () {
      final result = ResortSearchResult.fromJson(const <String, dynamic>{
        'id': 'r3',
        'name': 'X',
        'slug': 'x',
        'distance_km': 12,
        'avg_rating': 5,
      });

      expect(result.distanceKm, 12.0);
      expect(result.avgRating, 5.0);
    });
  });

  group('ResortSearchQuery', () {
    test('the unfiltered query sends nulls and the recommended sort', () {
      expect(ResortSearchQuery.all.toParams(), {
        'p_query': null,
        'p_lat': null,
        'p_lng': null,
        'p_sort': 'recommended',
        'p_amenities': null,
      });
    });

    test('trims the text and sends every set field', () {
      const query = ResortSearchQuery(
        text: '  lake view ',
        sort: ResortSort.priceLow,
        amenities: ['Pool'],
        origin: GeoPoint(17.39, 78.49),
      );

      expect(query.toParams(), {
        'p_query': 'lake view',
        'p_lat': 17.39,
        'p_lng': 78.49,
        'p_sort': 'price',
        'p_amenities': ['Pool'],
      });
    });

    test('blank text sends a null query', () {
      expect(
        const ResortSearchQuery(text: '   ').toParams()['p_query'],
        isNull,
      );
    });

    test('hasFilters is true for text or an amenity, not for a sort alone', () {
      expect(const ResortSearchQuery(text: '  ').hasFilters, isFalse);
      expect(const ResortSearchQuery(text: 'lake').hasFilters, isTrue);
      expect(const ResortSearchQuery(amenities: ['Pool']).hasFilters, isTrue);
      expect(
        const ResortSearchQuery(sort: ResortSort.rating).hasFilters,
        isFalse,
      );
    });

    test(
      'two queries with equal fields are equal, even with separate lists',
      () {
        final a = ResortSearchQuery(text: 'lake', amenities: List.of(['Pool']));
        final b = ResortSearchQuery(text: 'lake', amenities: List.of(['Pool']));

        expect(a, b);
        expect(a.hashCode, b.hashCode);
        expect(
          a,
          isNot(ResortSearchQuery(text: 'lake', amenities: List.of(['Spa']))),
        );
        expect(
          const ResortSearchQuery(origin: GeoPoint(1, 2)),
          isNot(const ResortSearchQuery(origin: GeoPoint(2, 1))),
        );
      },
    );
  });

  test('ResortSort maps to the server values and the screen labels', () {
    expect(ResortSort.values.map((s) => s.dbValue), [
      'recommended',
      'distance',
      'price',
      'rating',
    ]);
    expect(ResortSort.values.map((s) => s.label), [
      'Recommended',
      'Distance',
      'Price: low to high',
      'Rating',
    ]);
  });

  test('distanceLabel rounds to whole kilometres, with "< 1 km" below one', () {
    expect(distanceLabel(0.4), '< 1 km');
    expect(distanceLabel(1.0), '1 km');
    expect(distanceLabel(12.3), '12 km');
    expect(distanceLabel(455.3), '455 km');
  });
}
