import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/data/models/channel_delivery.dart';
import 'package:pasala/data/models/outbox_message.dart';

void main() {
  test('parses a live channel with its run time', () {
    final d = ChannelDelivery.fromJson(const {
      'channel': 'email',
      'mode': 'live',
      'provider': 'resend',
      'detail': null,
      'last_run_at': '2026-09-25T04:30:00Z',
    });

    expect(d.channel, OutboxChannel.email);
    expect(d.mode, DeliveryMode.live);
    expect(d.provider, 'resend');
    expect(d.detail, isNull);
    expect(d.lastRunAt, DateTime.utc(2026, 9, 25, 4, 30));
  });

  test('parses a dry-run channel with its reason', () {
    final d = ChannelDelivery.fromJson(const {
      'channel': 'sms',
      'mode': 'dry_run',
      'provider': 'msg91',
      'detail': 'MSG91_AUTH_KEY is not set',
      'last_run_at': '2026-09-25T04:30:00Z',
    });

    expect(d.mode, DeliveryMode.dryRun);
    expect(d.detail, 'MSG91_AUTH_KEY is not set');
  });

  test('a channel that never ran has no provider and no run time', () {
    final d = ChannelDelivery.fromJson(const {
      'channel': 'whatsapp',
      'mode': 'unavailable',
      'provider': null,
      'detail': null,
      'last_run_at': null,
    });

    expect(d.mode, DeliveryMode.unavailable);
    expect(d.provider, isNull);
    expect(d.lastRunAt, isNull);
  });

  test('every mode maps, and an unknown one is rejected', () {
    expect(deliveryModeFromDb('live'), DeliveryMode.live);
    expect(deliveryModeFromDb('dry_run'), DeliveryMode.dryRun);
    expect(deliveryModeFromDb('unavailable'), DeliveryMode.unavailable);
    expect(deliveryModeFromDb('not_running'), DeliveryMode.notRunning);
    expect(() => deliveryModeFromDb('paused'), throwsArgumentError);
  });
}
