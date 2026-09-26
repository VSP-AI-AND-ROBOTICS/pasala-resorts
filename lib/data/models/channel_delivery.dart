import 'outbox_message.dart';

/// How one channel is being delivered, from `outbox_delivery_status`
/// (0056_email_sms_delivery.sql).
enum DeliveryMode {
  /// The provider key is set and the sender sends.
  live,

  /// The sender runs but the provider key is not set: rows are marked
  /// dry run and nothing is sent.
  dryRun,

  /// There is no sender for this channel at all (WhatsApp).
  unavailable,

  /// The sender has never reported a run.
  notRunning,
}

/// Unknown mode text is rejected, not defaulted.
DeliveryMode deliveryModeFromDb(String raw) => switch (raw) {
      'live' => DeliveryMode.live,
      'dry_run' => DeliveryMode.dryRun,
      'unavailable' => DeliveryMode.unavailable,
      'not_running' => DeliveryMode.notRunning,
      _ => throw ArgumentError('Unknown delivery mode: $raw'),
    };

/// One row of `outbox_delivery_status`.
class ChannelDelivery {
  const ChannelDelivery({
    required this.channel,
    required this.mode,
    this.provider,
    this.detail,
    this.lastRunAt,
  });

  final OutboxChannel channel;
  final DeliveryMode mode;

  /// `resend` or `msg91` once the sender has run; null otherwise.
  final String? provider;

  /// Why a channel is a dry run, e.g. `RESEND_API_KEY is not set`.
  final String? detail;

  /// When the sender last reported this channel; null if it never has.
  final DateTime? lastRunAt;

  factory ChannelDelivery.fromJson(Map<String, dynamic> json) => ChannelDelivery(
        channel: OutboxChannel.values.byName(json['channel'] as String),
        mode: deliveryModeFromDb(json['mode'] as String),
        provider: json['provider'] as String?,
        detail: json['detail'] as String?,
        lastRunAt: json['last_run_at'] == null
            ? null
            : DateTime.parse(json['last_run_at'] as String).toUtc(),
      );
}
