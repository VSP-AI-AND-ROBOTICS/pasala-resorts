import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/env.dart';
import '../../core/errors.dart';
import '../../core/supabase_client.dart';
import '../models/ical_feed.dart';

/// One `ical_poll_feed` outcome, as returned by the RPC: `status` is one
/// of `requested` (a fetch was fired; pg_net is asynchronous, see 0018),
/// `pending` (still waiting on a fetch fired earlier), `ok` (a response was
/// collected and processed -- the counts describe its events) or `error`
/// (the fetch or the feed itself failed -- `error` carries why). Never
/// thrown -- a failing feed is what the OTA screen exists to show.
class IcalSyncResult {
  const IcalSyncResult({
    required this.status,
    this.error,
    this.events,
    this.created,
    this.updated,
    this.unchanged,
    this.conflicts,
    this.echoes,
    this.failed,
  });

  final String status;
  final String? error;

  /// Events read from the feed (cancelled ones excluded).
  final int? events;
  final int? created;
  final int? updated;
  final int? unchanged;

  /// Events that overlap a booking here and were skipped.
  final int? conflicts;

  /// Events that only repeat our own bookings back (0058) -- not a problem.
  final int? echoes;

  /// Events that could not be read or imported.
  final int? failed;

  /// A response was collected (`ok` or `error`), as opposed to a fetch
  /// still being on its way (`requested`, `pending`).
  bool get isFinal => status == 'ok' || status == 'error';

  factory IcalSyncResult.fromJson(Map<String, dynamic> json) => IcalSyncResult(
        status: json['status'] as String,
        error: json['error'] as String?,
        events: (json['events'] as num?)?.toInt(),
        created: (json['created'] as num?)?.toInt(),
        updated: (json['updated'] as num?)?.toInt(),
        unchanged: (json['unchanged'] as num?)?.toInt(),
        conflicts: (json['conflicts'] as num?)?.toInt(),
        echoes: (json['echoes'] as num?)?.toInt(),
        failed: (json['failed'] as num?)?.toInt(),
      );
}

/// The slice of [IcalRepository] `IcalScreen` needs. Extracted as its own
/// interface, mirroring [OutboxSource]/[ReportRepository]'s peers, so tests
/// can override it with a fake instead of a real [SupabaseClient].
abstract class IcalSource {
  Future<List<IcalFeed>> feeds(String unitId);
  Future<void> addFeed({required String unitId, required String url, String? label});
  Future<void> removeFeed(String feedId);
  Future<IcalSyncResult> syncFeed(String feedId);
  Future<String> exportToken(String unitId);
  Future<String> rotateExportToken(String unitId);

  /// The actual URL an OTA fetches for [token]. Kept on this interface
  /// (rather than a free function reaching into [Env] directly) so a
  /// widget test's fake can return a fixed string without ever touching
  /// [Env.supabaseAnonKey] -- which deliberately asserts/crashes when no
  /// `--dart-define=SUPABASE_ANON_KEY=...` was passed, exactly the case
  /// under a plain `flutter test` run.
  String exportUrl(String token);
}

/// Reads/writes `public.ical_feeds` (admin-only RLS -- `ical_feeds_admin`),
/// drives `ical_poll_feed` for the Sync button, and reads/rotates the
/// per-unit export token from `public.ical_export_tokens` (also
/// admin-only -- see migration 0018's header for why that token is its
/// own table rather than a column on `units`, which is publicly readable).
class IcalRepository implements IcalSource {
  IcalRepository(this._db);
  final SupabaseClient _db;

  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } catch (e) {
      throw mapPostgrestError(e);
    }
  }

  @override
  Future<List<IcalFeed>> feeds(String unitId) => _guard(() async {
        final rows = await _db
            .from('ical_feeds')
            .select()
            .eq('unit_id', unitId)
            .order('created_at', ascending: true);
        return rows.map(IcalFeed.fromJson).toList();
      });

  @override
  Future<void> addFeed({
    required String unitId,
    required String url,
    String? label,
  }) =>
      _guard(() async {
        await _db.from('ical_feeds').insert({
          'unit_id': unitId,
          'url': url,
          'label': label,
        });
      });

  @override
  Future<void> removeFeed(String feedId) =>
      _guard(() => _db.from('ical_feeds').delete().eq('id', feedId));

  @override
  Future<IcalSyncResult> syncFeed(String feedId) => _guard(() async {
        final json = await _db.rpc('ical_poll_feed', params: {
          'p_feed_id': feedId,
        });
        return IcalSyncResult.fromJson(json as Map<String, dynamic>);
      });

  @override
  Future<String> exportToken(String unitId) => _guard(() async {
        final row = await _db
            .from('ical_export_tokens')
            .select('token')
            .eq('unit_id', unitId)
            .maybeSingle();
        // Every unit gets a token row the moment it exists (a DB trigger --
        // see migration 0018), so this should always be found; rotating
        // on the rare miss (e.g. a unit created before the backfill ran
        // in a differently-ordered deploy) is a harmless fallback rather
        // than a dead end for the admin.
        if (row == null) return rotateExportToken(unitId);
        return row['token'] as String;
      });

  @override
  Future<String> rotateExportToken(String unitId) => _guard(() async {
        final token = await _db.rpc('rotate_ical_token', params: {
          'p_unit_id': unitId,
        });
        return token as String;
      });

  // PostgREST's GET-for-RPC convention (any `stable`/`immutable` function
  // -- `ical_export_public` is `stable` -- can be called with GET, not
  // just POST) with the token and this app's own public anon key as query
  // parameters. The anon key is not a secret (it already ships inside
  // this app's build), and Supabase's gateway accepts `apikey` as a query
  // parameter on GET the same as it does as a header -- required here
  // because Airbnb/Booking.com fetch a plain URL with no custom headers
  // at all, so there is nowhere else to put it.
  @override
  String exportUrl(String token) =>
      '${Env.supabaseUrl}/rest/v1/rpc/ical_export_public'
      '?token=$token&apikey=${Env.supabaseAnonKey}';
}

final icalRepositoryProvider = Provider<IcalRepository>(
  (ref) => IcalRepository(ref.watch(supabaseProvider)),
);

/// [IcalSource] seam around [icalRepositoryProvider], mirroring
/// [outboxSourceProvider]: [IcalScreen] only ever calls this, so tests can
/// override just this provider with a fake.
final icalSourceProvider = Provider<IcalSource>(
  (ref) => ref.watch(icalRepositoryProvider),
);
