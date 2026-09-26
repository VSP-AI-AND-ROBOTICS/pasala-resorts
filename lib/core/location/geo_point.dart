/// A latitude/longitude pair in decimal degrees: the shape of
/// `properties.lat`/`lng` and of a device position fix.
class GeoPoint {
  const GeoPoint(this.latitude, this.longitude);

  final double latitude;
  final double longitude;

  /// Within the ranges the `properties_lat_range` / `properties_lng_range`
  /// checks (0060_guest_search.sql) accept. NaN is never valid.
  bool get isValid =>
      latitude >= -90 &&
      latitude <= 90 &&
      longitude >= -180 &&
      longitude <= 180;

  /// Rounded to 2 decimal places, about 1 km. This is the only precision
  /// at which the guest's own position is cached or sent to this app's
  /// backend (spec decision 15).
  GeoPoint coarse() => GeoPoint(_round2(latitude), _round2(longitude));

  static double _round2(double value) => (value * 100).roundToDouble() / 100;

  @override
  bool operator ==(Object other) =>
      other is GeoPoint &&
      other.latitude == latitude &&
      other.longitude == longitude;

  @override
  int get hashCode => Object.hash(latitude, longitude);

  @override
  String toString() => 'GeoPoint($latitude, $longitude)';
}
