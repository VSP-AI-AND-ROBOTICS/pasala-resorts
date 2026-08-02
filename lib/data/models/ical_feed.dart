/// One row of `public.ical_feeds`: a subscription this unit imports
/// occupancy FROM (e.g. an Airbnb or Booking.com calendar URL). Carries
/// only the sync bookkeeping the admin OTA screen shows -- `last_error` is
/// shown verbatim when present, never hidden or softened, so a failing
/// feed reads as failing.
class IcalFeed {
  const IcalFeed({
    required this.id,
    required this.unitId,
    required this.url,
    required this.isActive,
    this.label,
    this.lastSyncedAt,
    this.lastError,
  });

  final String id;
  final String unitId;
  final String url;
  final String? label;
  final bool isActive;
  final DateTime? lastSyncedAt;
  final String? lastError;

  factory IcalFeed.fromJson(Map<String, dynamic> json) => IcalFeed(
        id: json['id'] as String,
        unitId: json['unit_id'] as String,
        url: json['url'] as String,
        label: json['label'] as String?,
        isActive: json['is_active'] as bool? ?? true,
        lastSyncedAt: json['last_synced_at'] == null
            ? null
            : DateTime.parse(json['last_synced_at'] as String).toUtc(),
        lastError: json['last_error'] as String?,
      );
}
