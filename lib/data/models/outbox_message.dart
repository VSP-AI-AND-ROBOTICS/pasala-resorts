/// The three delivery channels `public.outbox_channel` knows about. None of
/// them have a configured provider yet -- see [OutboxStatus].
enum OutboxChannel { email, sms, whatsapp }

/// `public.outbox_status`. `sent` is a real future state -- the column
/// exists for the sender service this phase does not build -- but nothing
/// server-side ever writes it yet: every row this app can produce is
/// `pending` (deliverable, queued) or `skipped` (no address/number on file,
/// recorded rather than silently dropped). `failed` is likewise reserved
/// for a future sender's retry bookkeeping.
enum OutboxStatus { pending, sent, failed, skipped }

OutboxChannel _channelFromDb(String raw) => OutboxChannel.values.byName(raw);

OutboxStatus _statusFromDb(String raw) => OutboxStatus.values.byName(raw);

/// One row of `public.outbox`: a single queued (or skipped) notification
/// for one reservation, on one channel. Never carries a `sent` status in
/// practice -- see [OutboxStatus] -- because there is no delivery provider
/// configured for this phase.
class OutboxMessage {
  const OutboxMessage({
    required this.id,
    required this.reservationId,
    required this.channel,
    required this.recipient,
    required this.template,
    required this.status,
    required this.attempts,
    required this.createdAt,
    this.subject,
    this.body,
    this.lastError,
    this.sentAt,
  });

  final String id;
  final String reservationId;
  final OutboxChannel channel;

  /// The address/number a real sender would deliver to, OR -- when
  /// [status] is [OutboxStatus.skipped] -- a short human-readable reason
  /// (e.g. `"no phone on file"`) rather than an empty string. `public.
  /// outbox`'s own `outbox_recipient_not_empty` constraint guarantees this
  /// is never blank.
  final String recipient;

  final String template;
  final String? subject;
  final String? body;
  final OutboxStatus status;
  final int attempts;
  final String? lastError;
  final DateTime createdAt;
  final DateTime? sentAt;

  factory OutboxMessage.fromJson(Map<String, dynamic> json) => OutboxMessage(
        id: json['id'] as String,
        reservationId: json['reservation_id'] as String,
        channel: _channelFromDb(json['channel'] as String),
        recipient: json['recipient'] as String,
        template: json['template'] as String,
        subject: json['subject'] as String?,
        body: json['body'] as String?,
        status: _statusFromDb(json['status'] as String),
        attempts: (json['attempts'] as num?)?.toInt() ?? 0,
        lastError: json['last_error'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String).toUtc(),
        sentAt: json['sent_at'] == null
            ? null
            : DateTime.parse(json['sent_at'] as String).toUtc(),
      );
}
