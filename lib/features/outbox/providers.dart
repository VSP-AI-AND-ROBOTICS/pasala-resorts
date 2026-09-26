import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/channel_delivery.dart';
import '../../data/models/outbox_message.dart';
import '../../data/repositories/outbox_repository.dart';

/// Every outbox row the signed-in member may see at the current resort
/// (RLS `outbox_read`). Keyed by property id so switching resorts never
/// shows another resort's cached queue. Backs [OutboxScreen].
final outboxMessagesProvider = FutureProvider.family<List<OutboxMessage>, String>(
  (ref, propertyId) => ref.watch(outboxSourceProvider).messages(propertyId),
);

/// Each channel's delivery mode and when the sender last ran
/// (`outbox_delivery_status`), for the Outbox screen's status panel. Keyed
/// by property id like [outboxMessagesProvider].
final outboxDeliveryStatusProvider =
    FutureProvider.family<List<ChannelDelivery>, String>(
  (ref, propertyId) =>
      ref.watch(outboxSourceProvider).deliveryStatus(propertyId),
);
