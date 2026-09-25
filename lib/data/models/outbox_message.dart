/// The delivery channels `public.outbox_channel` knows about. Email and SMS
/// are sent by the `outbox-dispatch` Edge Function; WhatsApp rows are only
/// queued (see docs/email-and-sms-delivery.md).
enum OutboxChannel { email, sms, whatsapp }

/// `public.outbox_status`:
/// - [pending]: waiting for the sender, or waiting to retry.
/// - [sent]: the provider accepted it.
/// - [failed]: a permanent error, or the last allowed attempt failed.
/// - [skipped]: never sendable (no address on file, channel turned off).
/// - [dryRun] (`dry_run`): handled while the channel's provider key was not
///   set, so nothing was sent.
enum OutboxStatus { pending, sent, failed, skipped, dryRun }

/// The sender gives up after this many attempts. Mirrors
/// `complete_outbox_message` in 0056_email_sms_delivery.sql.
const outboxMaxAttempts = 5;

OutboxChannel _channelFromDb(String raw) => OutboxChannel.values.byName(raw);

/// Unknown status text is rejected, not defaulted -- a silent fallback
/// would hide a new server status the app does not know how to show.
OutboxStatus outboxStatusFromDb(String raw) => switch (raw) {
      'pending' => OutboxStatus.pending,
      'sent' => OutboxStatus.sent,
      'failed' => OutboxStatus.failed,
      'skipped' => OutboxStatus.skipped,
      'dry_run' => OutboxStatus.dryRun,
      _ => throw ArgumentError('Unknown outbox status: $raw'),
    };

DateTime? _timeOrNull(Object? raw) =>
    raw == null ? null : DateTime.parse(raw as String).toUtc();

/// One row of `public.outbox`: a single notification for one reservation,
/// on one channel.
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
    this.nextAttemptAt,
    this.lastAttemptAt,
  });

  final String id;

  /// The reservation a guest message is about; null for a platform message
  /// to a resort owner (the listing emails of 0059_resort_self_listing.sql).
  final String? reservationId;
  final OutboxChannel channel;

  /// The address/number the sender delivers to, OR -- when [status] is
  /// [OutboxStatus.skipped] for a missing contact -- a short readable
  /// reason (e.g. `"no phone on file"`). `outbox_recipient_not_empty`
  /// guarantees this is never blank.
  final String recipient;

  final String template;
  final String? subject;
  final String? body;
  final OutboxStatus status;
  final int attempts;

  /// The provider's refusal, the retry reason, the skip reason, or -- on a
  /// [OutboxStatus.dryRun] row -- why it was a dry run.
  final String? lastError;
  final DateTime createdAt;
  final DateTime? sentAt;

  /// When the row is next due. While a run holds the row this is the end
  /// of its 5-minute lease; after a failed attempt it is the retry time.
  final DateTime? nextAttemptAt;
  final DateTime? lastAttemptAt;

  factory OutboxMessage.fromJson(Map<String, dynamic> json) => OutboxMessage(
        id: json['id'] as String,
        reservationId: json['reservation_id'] as String?,
        channel: _channelFromDb(json['channel'] as String),
        recipient: json['recipient'] as String,
        template: json['template'] as String,
        subject: json['subject'] as String?,
        body: json['body'] as String?,
        status: outboxStatusFromDb(json['status'] as String),
        attempts: (json['attempts'] as num?)?.toInt() ?? 0,
        lastError: json['last_error'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String).toUtc(),
        sentAt: _timeOrNull(json['sent_at']),
        nextAttemptAt: _timeOrNull(json['next_attempt_at']),
        lastAttemptAt: _timeOrNull(json['last_attempt_at']),
      );
}
