import 'package:pasala/data/models/property.dart';
import 'package:pasala/data/models/resort_search.dart';
import 'package:pasala/data/repositories/resort_search_repository.dart';

/// In-memory [ResortSearchSource].
/// - [results]: what every search returns. [respond] computes the answer
///   per query instead (see [respondLikeServer]).
/// - [error]: when set, every search throws it.
/// - [hold]: when set, each search waits for it before answering.
/// - [calls]: every query a screen asked for, in order.
class FakeResortSearchSource implements ResortSearchSource {
  List<ResortSearchResult> results = [];
  List<ResortSearchResult> Function(ResortSearchQuery query)? respond;
  Object? error;
  Future<void>? hold;
  final List<ResortSearchQuery> calls = [];

  @override
  Future<List<ResortSearchResult>> search(ResortSearchQuery query) async {
    calls.add(query);
    final gate = hold;
    if (gate != null) await gate;
    if (error != null) throw error!;
    return respond?.call(query) ?? results;
  }
}

/// A [FakeResortSearchSource.respond] that narrows [all] the way
/// `search_resorts` does:
/// - every word must appear in the name, address, description or
///   amenities
/// - every requested amenity must be present
/// - comparison is case-insensitive
///
/// It keeps [all]'s order. Sorting is the server's job, and pgTAP tests
/// it.
List<ResortSearchResult> Function(ResortSearchQuery) respondLikeServer(
  List<ResortSearchResult> all,
) => (query) {
  final words = query.text
      .trim()
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty);
  final wanted = query.amenities
      .map((a) => a.trim().toLowerCase())
      .where((a) => a.isNotEmpty);
  return all.where((r) {
    final p = r.property;
    final haystack = [
      p.name,
      p.address ?? '',
      p.description ?? '',
      p.amenities.join(' '),
    ].join(' ').toLowerCase();
    final have = p.amenities.map((a) => a.toLowerCase()).toSet();
    return words.every(haystack.contains) && wanted.every(have.contains);
  }).toList();
};

/// A search row with defaults. Override only what a test is about.
ResortSearchResult searchResult({
  String id = 'r1',
  String name = 'Lakeview Retreat',
  String? description,
  String? address,
  List<String> images = const [],
  List<String> amenities = const [],
  double? distanceKm,
  num? minPrice,
  double? avgRating,
  int reviewCount = 0,
}) => ResortSearchResult(
  property: Property(
    id: id,
    name: name,
    slug: id,
    description: description,
    address: address,
    images: images,
    amenities: amenities,
    checkInTime: '14:00',
    checkOutTime: '11:00',
    isActive: true,
  ),
  distanceKm: distanceKm,
  minPrice: minPrice,
  avgRating: avgRating,
  reviewCount: reviewCount,
);
