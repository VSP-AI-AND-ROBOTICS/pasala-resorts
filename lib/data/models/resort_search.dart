import 'package:flutter/foundation.dart';

import '../../core/location/geo_point.dart';
import 'property.dart';

/// The browse screen's sort options, in menu order.
enum ResortSort { recommended, distance, priceLow, rating }

extension ResortSortX on ResortSort {
  /// The `p_sort` value `search_resorts` expects.
  String get dbValue => switch (this) {
    ResortSort.recommended => 'recommended',
    ResortSort.distance => 'distance',
    ResortSort.priceLow => 'price',
    ResortSort.rating => 'rating',
  };

  String get label => switch (this) {
    ResortSort.recommended => 'Recommended',
    ResortSort.distance => 'Distance',
    ResortSort.priceLow => 'Price: low to high',
    ResortSort.rating => 'Rating',
  };
}

/// One call to `search_resorts`. Value-equal, so it can key
/// `resortSearchProvider`: rebuilding the browse screen with the same
/// filters reuses the same search instead of starting a new one.
@immutable
class ResortSearchQuery {
  const ResortSearchQuery({
    this.text = '',
    this.sort = ResortSort.recommended,
    this.amenities = const [],
    this.origin,
  });

  /// Every active resort, recommended order, no position: the source of
  /// the amenity chips.
  static const all = ResortSearchQuery();

  final String text;
  final ResortSort sort;
  final List<String> amenities;

  /// The guest's position, already rounded by the caller.
  final GeoPoint? origin;

  /// A search term or an amenity is narrowing the list. A sort alone never
  /// hides a resort.
  bool get hasFilters => text.trim().isNotEmpty || amenities.isNotEmpty;

  Map<String, dynamic> toParams() {
    final trimmed = text.trim();
    return {
      'p_query': trimmed.isEmpty ? null : trimmed,
      'p_lat': origin?.latitude,
      'p_lng': origin?.longitude,
      'p_sort': sort.dbValue,
      'p_amenities': amenities.isEmpty ? null : amenities,
    };
  }

  @override
  bool operator ==(Object other) =>
      other is ResortSearchQuery &&
      other.text == text &&
      other.sort == sort &&
      listEquals(other.amenities, amenities) &&
      other.origin == origin;

  @override
  int get hashCode =>
      Object.hash(text, sort, Object.hashAll(amenities), origin);
}

/// One `search_resorts` row: the resort's card fields plus what search
/// adds. [distanceKm] is null without a position or without coordinates.
/// [minPrice] is null for a resort with no nightly rate. [avgRating] is
/// null when [reviewCount] is 0.
class ResortSearchResult {
  const ResortSearchResult({
    required this.property,
    this.distanceKm,
    this.minPrice,
    this.avgRating,
    this.reviewCount = 0,
  });

  final Property property;
  final double? distanceKm;
  final num? minPrice;
  final double? avgRating;
  final int reviewCount;

  factory ResortSearchResult.fromJson(Map<String, dynamic> json) =>
      ResortSearchResult(
        property: Property.fromJson(json),
        distanceKm: (json['distance_km'] as num?)?.toDouble(),
        minPrice: json['min_price'] as num?,
        avgRating: (json['avg_rating'] as num?)?.toDouble(),
        reviewCount: (json['review_count'] as num?)?.toInt() ?? 0,
      );
}

/// A card's distance: `< 1 km` below one kilometre, whole kilometres
/// above it. The origin is only accurate to about 1 km (it is coarse), so
/// decimals would promise more than we know.
String distanceLabel(double km) => km < 1 ? '< 1 km' : '${km.round()} km';
