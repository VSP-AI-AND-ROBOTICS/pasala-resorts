import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/data/models/channel_delivery.dart';
import 'package:pasala/data/models/outbox_message.dart';
import 'package:pasala/features/outbox/delivery_status_panel.dart';

final _now = DateTime.utc(2026, 9, 25, 5, 0);

Future<void> _pump(
  WidgetTester tester,
  AsyncValue<List<ChannelDelivery>> status,
) =>
    tester.pumpWidget(MaterialApp(
      home: Scaffold(body: DeliveryStatusPanel(status: status, now: _now)),
    ));

List<ChannelDelivery> _rows({required Duration ago}) => [
      ChannelDelivery(
        channel: OutboxChannel.email,
        mode: DeliveryMode.live,
        provider: 'resend',
        lastRunAt: _now.subtract(ago),
      ),
      ChannelDelivery(
        channel: OutboxChannel.sms,
        mode: DeliveryMode.dryRun,
        provider: 'msg91',
        detail: 'MSG91_AUTH_KEY is not set',
        lastRunAt: _now.subtract(ago),
      ),
      const ChannelDelivery(
        channel: OutboxChannel.whatsapp,
        mode: DeliveryMode.unavailable,
      ),
    ];

void main() {
  group('deliveryLine', () {
    test('live names the provider', () {
      expect(
        deliveryLine(const ChannelDelivery(
            channel: OutboxChannel.email, mode: DeliveryMode.live, provider: 'resend')),
        'Email: sending via Resend',
      );
      expect(
        deliveryLine(const ChannelDelivery(
            channel: OutboxChannel.sms, mode: DeliveryMode.live, provider: 'msg91')),
        'SMS: sending via MSG91',
      );
    });

    test('dry run, unavailable and not running', () {
      expect(
        deliveryLine(const ChannelDelivery(
            channel: OutboxChannel.sms, mode: DeliveryMode.dryRun)),
        'SMS: dry run, nothing is sent',
      );
      expect(
        deliveryLine(const ChannelDelivery(
            channel: OutboxChannel.whatsapp, mode: DeliveryMode.unavailable)),
        'WhatsApp: not connected, messages stay queued',
      );
      expect(
        deliveryLine(const ChannelDelivery(
            channel: OutboxChannel.email, mode: DeliveryMode.notRunning)),
        'Email: waiting for the sender to run',
      );
    });

    test('an unknown or missing provider still reads well', () {
      expect(providerLabel('twilio'), 'twilio');
      expect(providerLabel(''), 'the provider');
      expect(providerLabel(null), 'the provider');
    });
  });

  test('sinceLabel buckets minutes, hours and days', () {
    expect(sinceLabel(_now.subtract(const Duration(seconds: 30)), _now), 'just now');
    expect(sinceLabel(_now.subtract(const Duration(minutes: 3)), _now), '3 min ago');
    expect(sinceLabel(_now.subtract(const Duration(minutes: 59)), _now), '59 min ago');
    expect(sinceLabel(_now.subtract(const Duration(hours: 2)), _now), '2 h ago');
    expect(sinceLabel(_now.subtract(const Duration(days: 1)), _now), '1 day ago');
    expect(sinceLabel(_now.subtract(const Duration(days: 3)), _now), '3 days ago');
  });

  test('runLine: never ran, fresh, the 10-minute edge, and stale', () {
    expect(runLine(null, _now),
        'The sender has not run yet. Pending messages wait until it does.');
    expect(runLine(_now.subtract(const Duration(minutes: 3)), _now),
        'Last checked 3 min ago.');
    expect(runLine(_now.subtract(const Duration(minutes: 10)), _now),
        'Last checked 10 min ago.');
    expect(runLine(_now.subtract(const Duration(minutes: 11)), _now),
        'The sender last ran 11 min ago. Pending messages are waiting.');
    expect(runLine(_now.subtract(const Duration(hours: 2)), _now),
        'The sender last ran 2 h ago. Pending messages are waiting.');
    expect(senderLooksStopped(null, _now), isTrue);
    expect(senderLooksStopped(_now.subtract(const Duration(minutes: 10)), _now), isFalse);
  });

  test('lastRunOf picks the latest run and ignores channels that never ran', () {
    final older = _now.subtract(const Duration(minutes: 9));
    final newer = _now.subtract(const Duration(minutes: 2));
    expect(
      lastRunOf([
        ChannelDelivery(channel: OutboxChannel.email, mode: DeliveryMode.live, lastRunAt: older),
        ChannelDelivery(channel: OutboxChannel.sms, mode: DeliveryMode.live, lastRunAt: newer),
        const ChannelDelivery(channel: OutboxChannel.whatsapp, mode: DeliveryMode.unavailable),
      ]),
      newer,
    );
    expect(lastRunOf(const []), isNull);
  });

  testWidgets('renders a line per channel, and the dry-run reason under SMS only',
      (tester) async {
    await _pump(tester, AsyncData(_rows(ago: const Duration(minutes: 3))));

    expect(find.byKey(const Key('delivery-status-panel')), findsOneWidget);
    expect(find.text('Email: sending via Resend'), findsOneWidget);
    expect(find.text('SMS: dry run, nothing is sent'), findsOneWidget);
    expect(find.text('MSG91_AUTH_KEY is not set'), findsOneWidget);
    expect(find.text('WhatsApp: not connected, messages stay queued'), findsOneWidget);
    expect(find.text('Last checked 3 min ago.'), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_outlined), findsNothing);
  });

  testWidgets('a stale sender shows the warning line and icon', (tester) async {
    await _pump(tester, AsyncData(_rows(ago: const Duration(hours: 2))));

    expect(find.text('The sender last ran 2 h ago. Pending messages are waiting.'),
        findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('delivery-run-line')),
        matching: find.byIcon(Icons.warning_amber_outlined),
      ),
      findsOneWidget,
    );
  });

  testWidgets('a sender that never ran warns too', (tester) async {
    await _pump(tester, const AsyncData(<ChannelDelivery>[]));

    expect(find.text('The sender has not run yet. Pending messages wait until it does.'),
        findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_outlined), findsOneWidget);
  });

  testWidgets('loading shows a thin progress bar', (tester) async {
    await _pump(tester, const AsyncLoading<List<ChannelDelivery>>());
    await tester.pump();

    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('an error says the status is unavailable', (tester) async {
    await _pump(
      tester,
      AsyncError<List<ChannelDelivery>>(Exception('boom'), StackTrace.empty),
    );

    expect(find.text('Delivery status is unavailable right now.'), findsOneWidget);
  });
}
