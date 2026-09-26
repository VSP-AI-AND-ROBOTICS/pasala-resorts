import 'package:pasala/data/models/ical_feed.dart';
import 'package:pasala/data/repositories/ical_repository.dart';

/// In-memory [IcalSource] for widget and unit tests. Never touches `Env`:
/// [exportUrl] returns a fixed test string (`flutter test` runs with no
/// `--dart-define`, so the real URL builder would assert).
class FakeIcalSource implements IcalSource {
  List<IcalFeed> rows = [];
  String token = 'faketoken123';
  Object? feedsError;
  Object? addError;
  Object? syncError;

  /// What successive [syncFeed] calls return, in order; the last entry
  /// repeats once the list runs out.
  List<IcalSyncResult> syncScript = [
    const IcalSyncResult(status: 'ok', events: 0, conflicts: 0),
  ];

  /// Shorthand for a script whose every call returns [result].
  set syncResult(IcalSyncResult result) => syncScript = [result];

  int feedsCalls = 0;
  final syncCalls = <String>[];
  final added = <String>[];
  final removed = <String>[];
  bool rotated = false;

  @override
  Future<List<IcalFeed>> feeds(String unitId) async {
    feedsCalls++;
    if (feedsError != null) throw feedsError!;
    return rows;
  }

  @override
  Future<void> addFeed({
    required String unitId,
    required String url,
    String? label,
  }) async {
    if (addError != null) throw addError!;
    added.add(url);
    rows = [
      ...rows,
      IcalFeed(
        id: 'new-${rows.length}',
        unitId: unitId,
        url: url,
        label: label,
        isActive: true,
      ),
    ];
  }

  @override
  Future<void> removeFeed(String feedId) async {
    removed.add(feedId);
    rows = rows.where((f) => f.id != feedId).toList();
  }

  @override
  Future<IcalSyncResult> syncFeed(String feedId) async {
    syncCalls.add(feedId);
    if (syncError != null) throw syncError!;
    final i = syncCalls.length - 1;
    return i < syncScript.length ? syncScript[i] : syncScript.last;
  }

  @override
  Future<String> exportToken(String unitId) async => token;

  @override
  Future<String> rotateExportToken(String unitId) async {
    rotated = true;
    token = 'rotated-token';
    return token;
  }

  @override
  String exportUrl(String token) =>
      'https://fake.supabase.test/functions/v1/ical-export/$token.ics';
}

/// An [IcalFeed] with test defaults.
IcalFeed icalFeed({
  String id = 'f1',
  String unitId = 'u1',
  String url = 'https://www.airbnb.com/calendar/ical/1.ics',
  String? label = 'Airbnb',
  bool isActive = true,
  DateTime? lastSyncedAt,
  String? lastError,
  FeedSyncStatus? lastStatus,
  int? lastEventCount,
  DateTime? lastOkAt,
}) => IcalFeed(
  id: id,
  unitId: unitId,
  url: url,
  label: label,
  isActive: isActive,
  lastSyncedAt: lastSyncedAt,
  lastError: lastError,
  lastStatus: lastStatus,
  lastEventCount: lastEventCount,
  lastOkAt: lastOkAt,
);
