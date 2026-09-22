import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors.dart';
import '../../core/supabase_client.dart';
import '../models/outbox_message.dart';

/// The slice of [OutboxRepository] that [OutboxScreen] needs. Extracted as
/// its own interface, mirroring [ReportRepository]'s peers in
/// `booking_repository.dart`, so tests can override just this provider
/// with a fake instead of needing a real `SupabaseClient`.
abstract class OutboxSource {
  Future<List<OutboxMessage>> messages();
}

/// Reads `public.outbox`, staff-gated by RLS (`outbox_read`) -- a customer
/// never reaches this repository because the router already refuses
/// `/admin/*` for anyone but an admin, but even a forged request still
/// returns zero rows under RLS rather than an error, mapped through
/// [mapPostgrestError] like everywhere else this app touches Postgrest.
///
/// There is no write method here at all: `public.outbox` has no insert/
/// update/delete grant to `authenticated`, not even for staff -- the
/// SECURITY DEFINER trigger in migration 0017 is the only writer, and
/// nothing in this phase ever marks a row `sent`.
class OutboxRepository implements OutboxSource {
  OutboxRepository(this._db);
  final SupabaseClient _db;

  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } catch (e) {
      throw mapPostgrestError(e);
    }
  }

  @override
  Future<List<OutboxMessage>> messages() => _guard(() async {
        final rows = await _db
            .from('outbox')
            .select()
            .order('created_at', ascending: false);
        return rows.map(OutboxMessage.fromJson).toList();
      });
}

final outboxRepositoryProvider = Provider<OutboxRepository>(
  (ref) => OutboxRepository(ref.watch(supabaseProvider)),
);

/// [OutboxSource] seam around [outboxRepositoryProvider], mirroring
/// [refundSourceProvider] in `booking_repository.dart`: [OutboxScreen] only
/// ever calls `messages`, so tests can override just this provider with a
/// fake.
final outboxSourceProvider = Provider<OutboxSource>(
  (ref) => ref.watch(outboxRepositoryProvider),
);
