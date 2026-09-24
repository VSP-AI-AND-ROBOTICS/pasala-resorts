/// A coarse place label -- city/town plus country -- resolved from the
/// device's approximate position via reverse geocoding (see
/// `LocationService`). Deliberately nothing more precise than a locality:
/// the badge that displays this never needs, and this app never sends to
/// its own backend, an exact coordinate.
class PlaceLabel {
  const PlaceLabel({required this.locality, required this.country});

  final String locality;
  final String country;

  @override
  String toString() => '$locality, $country';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PlaceLabel &&
          other.locality == locality &&
          other.country == country);

  @override
  int get hashCode => Object.hash(locality, country);
}
