import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/data/models/outbox_message.dart';

void main() {
  test('parses a pending row', () {
    final message = OutboxMessage.fromJson(const {
      'id': 'm1',
      'reservation_id': 'r1',
      'channel': 'email',
      'recipient': 'guest@example.com',
      'template': 'booking_confirmation',
      'subject': 'Your stay is confirmed',
      'body': 'Hi Guest, ...',
      'status': 'pending',
      'attempts': 0,
      'last_error': null,
      'created_at': '2026-08-01T10:00:00Z',
      'sent_at': null,
    });

    expect(message.channel, OutboxChannel.email);
    expect(message.status, OutboxStatus.pending);
    expect(message.recipient, 'guest@example.com');
    expect(message.sentAt, isNull);
  });

  test('parses a skipped row -- recipient carries the reason, not empty',
      () {
    final message = OutboxMessage.fromJson(const {
      'id': 'm2',
      'reservation_id': 'r2',
      'channel': 'sms',
      'recipient': 'no phone on file',
      'template': 'booking_confirmation_sms',
      'subject': null,
      'body': null,
      'status': 'skipped',
      'attempts': 0,
      'last_error':
          'cannot deliver via sms: customer u1 has no phone number on file',
      'created_at': '2026-08-01T10:00:00Z',
      'sent_at': null,
    });

    expect(message.channel, OutboxChannel.sms);
    expect(message.status, OutboxStatus.skipped);
    expect(message.recipient, isNotEmpty);
    expect(message.lastError, isNotNull);
  });

  test('a null attempts count defaults to zero, never a crash', () {
    final message = OutboxMessage.fromJson(const {
      'id': 'm3',
      'reservation_id': 'r3',
      'channel': 'whatsapp',
      'recipient': '+919876543210',
      'template': 'cancellation_whatsapp',
      'status': 'pending',
      'attempts': null,
      'created_at': '2026-08-01T10:00:00Z',
    });

    expect(message.attempts, 0);
  });

  test('parses a dry_run row and the retry timestamps', () {
    final message = OutboxMessage.fromJson(const {
      'id': 'm4',
      'reservation_id': 'r4',
      'channel': 'sms',
      'recipient': '+919876543210',
      'template': 'booking_confirmation_sms',
      'status': 'dry_run',
      'attempts': 1,
      'last_error': 'Dry run: MSG91_AUTH_KEY is not set',
      'created_at': '2026-08-01T10:00:00Z',
      'next_attempt_at': '2026-08-01T10:05:00Z',
      'last_attempt_at': '2026-08-01T10:00:30Z',
    });

    expect(message.status, OutboxStatus.dryRun);
    expect(message.nextAttemptAt, DateTime.utc(2026, 8, 1, 10, 5));
    expect(message.lastAttemptAt, DateTime.utc(2026, 8, 1, 10, 0, 30));
  });

  test('rows without retry timestamps parse them as null', () {
    final message = OutboxMessage.fromJson(const {
      'id': 'm5',
      'reservation_id': 'r5',
      'channel': 'email',
      'recipient': 'guest@example.com',
      'template': 'booking_confirmation',
      'status': 'pending',
      'attempts': 0,
      'created_at': '2026-08-01T10:00:00Z',
    });

    expect(message.nextAttemptAt, isNull);
    expect(message.lastAttemptAt, isNull);
  });

  test('every database status maps, and an unknown one is rejected', () {
    expect(outboxStatusFromDb('pending'), OutboxStatus.pending);
    expect(outboxStatusFromDb('sent'), OutboxStatus.sent);
    expect(outboxStatusFromDb('failed'), OutboxStatus.failed);
    expect(outboxStatusFromDb('skipped'), OutboxStatus.skipped);
    expect(outboxStatusFromDb('dry_run'), OutboxStatus.dryRun);
    expect(() => outboxStatusFromDb('queued'), throwsArgumentError);
  });

  test('the attempt limit mirrors the database', () {
    expect(outboxMaxAttempts, 5);
  });
}
