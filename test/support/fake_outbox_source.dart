import 'package:pasala/data/models/channel_delivery.dart';
import 'package:pasala/data/models/outbox_message.dart';
import 'package:pasala/data/repositories/outbox_repository.dart';

/// In-memory [OutboxSource]. Set [rows]/[statuses] for what the server
/// would return and an `...Error` to make that call throw; read the call
/// logs to assert what a screen asked for.
class FakeOutboxSource implements OutboxSource {
  List<OutboxMessage> rows = [];
  List<ChannelDelivery> statuses = [];
  Object? error;
  Object? statusError;
  Object? retryError;

  final List<String> listedPropertyIds = [];
  final List<String> statusPropertyIds = [];
  final List<String> retried = [];

  @override
  Future<List<OutboxMessage>> messages(String propertyId) async {
    listedPropertyIds.add(propertyId);
    if (error != null) throw error!;
    return rows;
  }

  @override
  Future<List<ChannelDelivery>> deliveryStatus(String propertyId) async {
    statusPropertyIds.add(propertyId);
    if (statusError != null) throw statusError!;
    return statuses;
  }

  @override
  Future<void> retry(String messageId) async {
    retried.add(messageId);
    if (retryError != null) throw retryError!;
  }
}
