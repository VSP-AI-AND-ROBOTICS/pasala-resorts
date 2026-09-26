/// How the last collected response of a feed went (`ical_feeds.last_status`,
/// 0058). [error] is a feed-level failure -- an HTTP error, a timeout, a
/// failed fetch, or a page that is not a calendar. Conflicts and unreadable
/// events are still [ok], with their note in `last_error`.
enum FeedSyncStatus { ok, error }

/// Null for a feed that has never synced (or any label this build does not
/// know).
FeedSyncStatus? feedSyncStatusFromDb(String? value) => switch (value) {
  'ok' => FeedSyncStatus.ok,
  'error' => FeedSyncStatus.error,
  _ => null,
};

/// One row of `public.ical_feeds`: a subscription this unit imports
/// occupancy FROM (e.g. an Airbnb or Booking.com calendar URL), with the
/// sync bookkeeping the OTA screen shows. `last_error` is shown verbatim
/// when present, never hidden or softened.
class IcalFeed {
  const IcalFeed({
    required this.id,
    required this.unitId,
    required this.url,
    required this.isActive,
    this.label,
    this.lastSyncedAt,
    this.lastError,
    this.lastStatus,
    this.lastEventCount,
    this.lastOkAt,
  });

  final String id;
  final String unitId;
  final String url;
  final String? label;
  final bool isActive;

  /// When the data of the last collected response was fetched.
  final DateTime? lastSyncedAt;

  /// The feed-level error when [lastStatus] is [FeedSyncStatus.error];
  /// otherwise a note about skipped events, or null.
  final String? lastError;
  final FeedSyncStatus? lastStatus;

  /// Events read from the feed on the last successful sync.
  final int? lastEventCount;

  /// When the last successful sync's data was fetched.
  final DateTime? lastOkAt;

  factory IcalFeed.fromJson(Map<String, dynamic> json) => IcalFeed(
        id: json['id'] as String,
        unitId: json['unit_id'] as String,
        url: json['url'] as String,
        label: json['label'] as String?,
        isActive: json['is_active'] as bool? ?? true,
        lastSyncedAt: _utc(json['last_synced_at']),
        lastError: json['last_error'] as String?,
        lastStatus: feedSyncStatusFromDb(json['last_status'] as String?),
        lastEventCount: (json['last_event_count'] as num?)?.toInt(),
        lastOkAt: _utc(json['last_ok_at']),
      );
}

DateTime? _utc(Object? value) =>
    value == null ? null : DateTime.parse(value as String).toUtc();
