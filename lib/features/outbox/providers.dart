import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/outbox_message.dart';
import '../../data/repositories/outbox_repository.dart';

/// Every outbox row the signed-in staff member may see at the current
/// resort (RLS scopes this to staff-or-above only -- see `outbox_read` in
/// migration 0017; a customer gets zero rows, not an error). Keyed by
/// property id so switching resorts never shows another resort's cached
/// queue. Backs [OutboxScreen].
final outboxMessagesProvider = FutureProvider.family<List<OutboxMessage>, String>(
  (ref, propertyId) => ref.watch(outboxSourceProvider).messages(propertyId),
);
