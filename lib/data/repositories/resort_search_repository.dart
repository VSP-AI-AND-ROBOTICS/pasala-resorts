import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors.dart';
import '../../core/supabase_client.dart';
import '../models/resort_search.dart';

/// What the browse screen needs from search. Tests override
/// [resortSearchSourceProvider] with `FakeResortSearchSource`
/// (test/support/fake_resort_search_source.dart).
abstract class ResortSearchSource {
  Future<List<ResortSearchResult>> search(ResortSearchQuery query);
}

/// Backs search with `search_resorts` (0060_guest_search.sql). Anon may
/// call it, so this works signed out. A bad input comes back as P0041,
/// which [mapPostgrestError] turns into `InvalidSearch`.
class ResortSearchRepository implements ResortSearchSource {
  ResortSearchRepository(this._db);
  final SupabaseClient _db;

  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } catch (e) {
      throw mapPostgrestError(e);
    }
  }

  @override
  Future<List<ResortSearchResult>> search(ResortSearchQuery query) =>
      _guard(() async {
        final rows =
            await _db.rpc('search_resorts', params: query.toParams())
                as List<dynamic>;
        return rows
            .map((e) => ResortSearchResult.fromJson(e as Map<String, dynamic>))
            .toList();
      });
}

final resortSearchRepositoryProvider = Provider<ResortSearchRepository>(
  (ref) => ResortSearchRepository(ref.watch(supabaseProvider)),
);

/// The [ResortSearchSource] seam every screen calls through.
final resortSearchSourceProvider = Provider<ResortSearchSource>(
  (ref) => ref.watch(resortSearchRepositoryProvider),
);

/// One search, keyed by its query. `autoDispose`: a guest typing leaves a
/// trail of abandoned queries, and each is dropped once no widget watches
/// it.
final resortSearchProvider = FutureProvider.autoDispose
    .family<List<ResortSearchResult>, ResortSearchQuery>(
      (ref, query) => ref.watch(resortSearchSourceProvider).search(query),
      // Screens show their own Retry button; don't also auto-retry (Riverpod 3
      // retries non-Error throws by default).
      retry: (retryCount, error) => null,
    );
