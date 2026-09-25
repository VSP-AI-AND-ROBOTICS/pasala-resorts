import '../../core/location/geo_point.dart';

class Property {
  const Property({
    required this.id,
    required this.name,
    required this.slug,
    required this.description,
    required this.address,
    required this.images,
    required this.amenities,
    required this.checkInTime,
    required this.checkOutTime,
    required this.isActive,
    this.advancePct = 100,
    this.taxPct = 0,
    this.gstin,
    this.minNights,
    this.maxNights,
    this.paymentDisplayMethods = const [],
    this.gatewayDisplayName,
    this.fnbTaxPct = 0,
    this.spaTaxPct = 0,
    this.latitude,
    this.longitude,
  });

  final String id;
  final String name;
  final String slug;
  final String? description;
  final String? address;
  final List<String> images;
  final List<String> amenities;
  final String checkInTime;
  final String checkOutTime;
  final bool isActive;

  /// Everything below is read-only via [Property] itself -- the Owner
  /// Settings screens write these through
  /// `CatalogRepository.updateSettings`, a narrow targeted update, NOT
  /// through [toInsert]/`upsertProperty` (which `PropertyFormScreen` uses
  /// for name/slug/description/address/amenities/check-in-out/active only).
  /// Keeping them out of [toInsert] means the Farmhouse Information screen
  /// needs no change at all to keep working.
  final num advancePct;
  final num taxPct;
  final String? gstin;
  final int? minNights;
  final int? maxNights;
  final List<String> paymentDisplayMethods;
  final String? gatewayDisplayName;

  /// Food & drink and spa & activities GST rates (`0053_food_spa_tax.sql`),
  /// 0 to 28. Unlike [taxPct], which is added on top of the room price,
  /// these are already inside menu and activity prices; each order and sale
  /// stores the rate it was made at. Written by the Taxes screen through
  /// `CatalogRepository.updateSettings`.
  final num fnbTaxPct;
  final num spaTaxPct;

  /// `properties.lat`/`lng`: the resort's map position. The owner sets it
  /// on the Map location screen through `CatalogRepository.updateSettings`,
  /// and it is not part of [toInsert]. The table requires both or neither
  /// (0060_guest_search.sql).
  final double? latitude;
  final double? longitude;

  GeoPoint? get location => latitude != null && longitude != null
      ? GeoPoint(latitude!, longitude!)
      : null;

  /// Postgres `time` columns round-trip as `HH:mm:ss` (e.g. `14:00:00`), but
  /// every writer in this app -- `showTimePicker` via [PropertyFormScreen],
  /// and the `HH:mm` defaults below -- only ever produces `HH:mm`. Normalising
  /// on read here means [checkInTime]/[checkOutTime] are always `HH:mm`
  /// regardless of which format the row came back in, so display code (e.g.
  /// [PropertyCard]) never has to care, and re-editing a property round-trips
  /// without drift: write `HH:mm` -> Postgres stores `HH:mm:00` -> next read
  /// truncates right back to the same `HH:mm`.
  static String normalizeTime(String raw) =>
      raw.length >= 5 ? raw.substring(0, 5) : raw;

  factory Property.fromJson(Map<String, dynamic> json) => Property(
        id: json['id'] as String,
        name: json['name'] as String,
        slug: json['slug'] as String,
        description: json['description'] as String?,
        address: json['address'] as String?,
        images: (json['images'] as List<dynamic>? ?? []).cast<String>(),
        amenities: (json['amenities'] as List<dynamic>? ?? []).cast<String>(),
        checkInTime: normalizeTime(json['check_in_time'] as String? ?? '14:00'),
        checkOutTime:
            normalizeTime(json['check_out_time'] as String? ?? '11:00'),
        isActive: json['is_active'] as bool? ?? true,
        advancePct: (json['advance_pct'] as num?) ?? 100,
        taxPct: (json['tax_pct'] as num?) ?? 0,
        gstin: json['gstin'] as String?,
        minNights: (json['min_nights'] as num?)?.toInt(),
        maxNights: (json['max_nights'] as num?)?.toInt(),
        paymentDisplayMethods:
            (json['payment_display_methods'] as List<dynamic>? ?? [])
                .cast<String>(),
        gatewayDisplayName: json['gateway_display_name'] as String?,
        fnbTaxPct: (json['fnb_tax_pct'] as num?) ?? 0,
        spaTaxPct: (json['spa_tax_pct'] as num?) ?? 0,
        latitude: (json['lat'] as num?)?.toDouble(),
        longitude: (json['lng'] as num?)?.toDouble(),
      );

  Map<String, dynamic> toInsert() => {
        'name': name,
        'slug': slug,
        'description': description,
        'address': address,
        'images': images,
        'amenities': amenities,
        'check_in_time': checkInTime,
        'check_out_time': checkOutTime,
        'is_active': isActive,
      };
}
