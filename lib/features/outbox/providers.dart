import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/outbox_message.dart';
import '../../data/repositories/outbox_repository.dart';

/// Every outbox row the signed-in staff member may see (RLS scopes this to
/// staff-or-above only -- see `outbox_read` in migration 0017; a customer
/// gets zero rows, not an error). Backs [OutboxScreen].
final outboxMessagesProvider = FutureProvider<List<OutboxMessage>>(
  (ref) => ref.watch(outboxSourceProvider).messages(),
);
