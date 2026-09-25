import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/location/geo_point.dart';

void main() {
  test('coarse() rounds both coordinates to 2 decimal places', () {
    expect(
      const GeoPoint(17.38512, 78.48671).coarse(),
      const GeoPoint(17.39, 78.49),
    );
    expect(
      const GeoPoint(-12.344, -45.678).coarse(),
      const GeoPoint(-12.34, -45.68),
    );
  });

  test('isValid accepts the table ranges and refuses anything outside', () {
    expect(const GeoPoint(90, 180).isValid, isTrue);
    expect(const GeoPoint(-90, -180).isValid, isTrue);
    expect(const GeoPoint(90.01, 0).isValid, isFalse);
    expect(const GeoPoint(0, -180.5).isValid, isFalse);
    expect(const GeoPoint(double.nan, 0).isValid, isFalse);
  });

  test('two points with the same coordinates are equal', () {
    expect(const GeoPoint(1, 2), const GeoPoint(1, 2));
    expect(const GeoPoint(1, 2).hashCode, const GeoPoint(1, 2).hashCode);
    expect(const GeoPoint(1, 2), isNot(const GeoPoint(2, 1)));
  });
}
