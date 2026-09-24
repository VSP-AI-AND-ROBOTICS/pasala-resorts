import 'place_label.dart';

/// Parses a Nominatim `/reverse?format=jsonv2` response body (already
/// JSON-decoded) into a [PlaceLabel].
///
/// Prefers `address.city`, falling back through `town` -> `village` ->
/// `county` -> `state` -- Nominatim's own recommended chain, since many
/// rural coordinates (a farm resort, not a city) carry no `city` field at
/// all. Returns null for a response with no address block, no usable
/// locality field, or no `country` -- an out-of-coverage coordinate or a
/// malformed body must never crash the badge, just leave it unresolved.
PlaceLabel? parseNominatimReverse(Map<String, dynamic> json) {
  final address = json['address'];
  if (address is! Map) return null;

  final locality =
      address['city'] ??
      address['town'] ??
      address['village'] ??
      address['county'] ??
      address['state'];
  final country = address['country'];
  if (locality is! String || locality.isEmpty) return null;
  if (country is! String || country.isEmpty) return null;

  return PlaceLabel(locality: locality, country: country);
}
