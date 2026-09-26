import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors.dart';
import '../../core/supabase_client.dart';
import '../models/channel_delivery.dart';
import '../models/outbox_message.dart';

/// The slice of [OutboxRepository] that [OutboxScreen] needs. Tests
/// override [outboxSourceProvider] with `FakeOutboxSource`
/// (test/support/fake_outbox_source.dart) instead of a real client.
abstract class OutboxSource {
  Future<List<OutboxMessage>> messages(String propertyId);

  /// One row per channel (email, sms, whatsapp), from
  /// `outbox_delivery_status`.
  Future<List<ChannelDelivery>> deliveryStatus(String propertyId);

  /// Puts a failed or dry-run message back in the queue
  /// (`retry_outbox_message`). Owner/admin only, enforced server-side.
  Future<void> retry(String messageId);
}

/// Reads `public.outbox` (RLS `outbox_read`: staff and above at the
/// resort) and calls the two app-facing functions from
/// 0056_email_sms_delivery.sql. Clients still cannot write `outbox`
/// directly: only definer functions change a row, and only the
/// `outbox-dispatch` Edge Function (as service_role) marks one sent.
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
  Future<List<OutboxMessage>> messages(String propertyId) => _guard(() async {
        final rows = await _db
            .from('outbox')
            .select()
            .eq('property_id', propertyId)
            .order('created_at', ascending: false);
        return rows.map(OutboxMessage.fromJson).toList();
      });

  @override
  Future<List<ChannelDelivery>> deliveryStatus(String propertyId) =>
      _guard(() async {
        final rows = await _db.rpc(
          'outbox_delivery_status',
          params: {'p_property': propertyId},
        ) as List<dynamic>;
        return rows
            .map((e) => ChannelDelivery.fromJson(e as Map<String, dynamic>))
            .toList();
      });

  @override
  Future<void> retry(String messageId) => _guard(() async {
        await _db.rpc('retry_outbox_message', params: {'p_message': messageId});
      });
}

final outboxRepositoryProvider = Provider<OutboxRepository>(
  (ref) => OutboxRepository(ref.watch(supabaseProvider)),
);

/// [OutboxSource] seam around [outboxRepositoryProvider], so tests can
/// override just this provider with a fake.
final outboxSourceProvider = Provider<OutboxSource>(
  (ref) => ref.watch(outboxRepositoryProvider),
);
