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
}
