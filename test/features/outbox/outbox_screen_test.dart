import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:pasala/core/current_resort.dart';
import 'package:pasala/core/errors.dart';
import 'package:pasala/data/models/channel_delivery.dart';
import 'package:pasala/data/models/outbox_message.dart';
import 'package:pasala/data/models/resort_membership.dart';
import 'package:pasala/data/repositories/outbox_repository.dart';
import 'package:pasala/features/outbox/outbox_screen.dart';

import '../../support/fake_outbox_source.dart';

final _now = DateTime.utc(2026, 9, 25, 5, 0);

class _FixedResort extends CurrentResort {
  _FixedResort(this.role);
  final ResortRole role;

  @override
  ResortMembership? build() =>
      ResortMembership(propertyId: 'p1', resortName: 'Pasala', role: role);
}

OutboxMessage _row({
  String id = 'm1',
  OutboxChannel channel = OutboxChannel.email,
  String recipient = 'guest@example.com',
  String template = 'booking_confirmation',
  OutboxStatus status = OutboxStatus.pending,
  int attempts = 0,
  String? lastError,
  DateTime? nextAttemptAt,
  DateTime? sentAt,
}) =>
    OutboxMessage(
      id: id,
      reservationId: 'r1',
      channel: channel,
      recipient: recipient,
      template: template,
      status: status,
      attempts: attempts,
      lastError: lastError,
      nextAttemptAt: nextAttemptAt,
      sentAt: sentAt,
      createdAt: DateTime.utc(2026, 8, 1, 10, 30),
    );

Future<void> _pump(
  WidgetTester tester,
  FakeOutboxSource source, {
  ResortRole role = ResortRole.admin,
}) async {
  tester.view.physicalSize = const Size(1200, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(
    // A fresh scope per pump: some tests pump again with another role.
    key: UniqueKey(),
    retry: (_, _) => null,
    overrides: [
      outboxSourceProvider.overrideWithValue(source),
      currentResortProvider.overrideWith(() => _FixedResort(role)),
    ],
    child: MaterialApp(home: OutboxScreen(clock: () => _now)),
  ));
  await tester.pumpAndSettle();
}

List<OutboxMessage> _oneOfEach() => [
      _row(id: 's', status: OutboxStatus.sent, attempts: 1,
          sentAt: DateTime.utc(2026, 8, 1, 10, 31)),
      _row(id: 'k', status: OutboxStatus.skipped, channel: OutboxChannel.sms,
          recipient: 'no phone on file', lastError: 'cannot deliver via sms'),
      _row(id: 'd', status: OutboxStatus.dryRun, attempts: 1,
          lastError: 'Dry run: RESEND_API_KEY is not set'),
      _row(id: 'f', status: OutboxStatus.failed, attempts: 5,
          lastError: 'resend 503: busy'),
      _row(id: 'p', status: OutboxStatus.pending),
    ];

void main() {
  testWidgets("shows each channel's delivery mode and when the sender last ran",
      (tester) async {
    final ran = _now.subtract(const Duration(minutes: 3));
    final source = FakeOutboxSource()
      ..statuses = [
        ChannelDelivery(channel: OutboxChannel.email, mode: DeliveryMode.live,
            provider: 'resend', lastRunAt: ran),
        ChannelDelivery(channel: OutboxChannel.sms, mode: DeliveryMode.dryRun,
            provider: 'msg91', detail: 'MSG91_AUTH_KEY is not set', lastRunAt: ran),
        const ChannelDelivery(channel: OutboxChannel.whatsapp,
            mode: DeliveryMode.unavailable),
      ];
    await _pump(tester, source);

    expect(find.text('Email: sending via Resend'), findsOneWidget);
    expect(find.text('SMS: dry run, nothing is sent'), findsOneWidget);
    expect(find.text('MSG91_AUTH_KEY is not set'), findsOneWidget);
    expect(find.text('WhatsApp: not connected, messages stay queued'), findsOneWidget);
    expect(find.text('Last checked 3 min ago.'), findsOneWidget);
    expect(source.statusPropertyIds, everyElement('p1'));
    expect(source.listedPropertyIds, everyElement('p1'));
  });

  testWidgets('the old "no delivery provider" banner is gone', (tester) async {
    await _pump(tester, FakeOutboxSource()..rows = [_row()]);

    expect(find.byKey(const Key('no-provider-banner')), findsNothing);
    expect(find.textContaining('No delivery provider'), findsNothing);
  });

  testWidgets('an empty queue shows an EmptyState and the never-ran warning',
      (tester) async {
    await _pump(tester, FakeOutboxSource());

    expect(find.text('Nothing queued yet'), findsOneWidget);
    expect(find.text('The sender has not run yet. Pending messages wait until it does.'),
        findsOneWidget);
  });

  testWidgets('sections run Pending, Failed, Dry run, Skipped, Sent',
      (tester) async {
    await _pump(tester, FakeOutboxSource()..rows = _oneOfEach());

    const headers = ['Pending (1)', 'Failed (1)', 'Dry run (1)', 'Skipped (1)', 'Sent (1)'];
    final ys = [for (final h in headers) tester.getTopLeft(find.text(h)).dy];
    expect(ys, orderedEquals([...ys]..sort()));
  });

  testWidgets('rows show their retry, failure or sent line', (tester) async {
    final next = DateTime.utc(2026, 8, 1, 10, 34);
    final sentAt = DateTime.utc(2026, 8, 1, 10, 31);
    await _pump(
      tester,
      FakeOutboxSource()
        ..rows = [
          _row(id: 'p', attempts: 2, lastError: 'resend 503: busy', nextAttemptAt: next),
          _row(id: 'f', status: OutboxStatus.failed, attempts: 5, lastError: 'resend 422: bad to'),
          _row(id: 's', status: OutboxStatus.sent, attempts: 1, sentAt: sentAt),
          _row(id: 'q'),
        ],
    );

    expect(
      find.text('Attempt 2 of 5 failed · next try '
          '${DateFormat('HH:mm').format(next.toLocal())}'),
      findsOneWidget,
    );
    expect(find.text('Failed after 5 attempts'), findsOneWidget);
    expect(
      find.text('Sent ${DateFormat('d MMM yyyy, HH:mm').format(sentAt.toLocal())}'),
      findsOneWidget,
    );
    expect(find.textContaining('Attempt 0'), findsNothing);
  });

  test('attemptLine: nothing while the first attempt is in flight; singular for one', () {
    expect(attemptLine(_row(attempts: 1)), isNull);
    expect(attemptLine(_row(status: OutboxStatus.failed, attempts: 1)),
        'Failed after 1 attempt');
    expect(attemptLine(_row(status: OutboxStatus.skipped)), isNull);
    expect(attemptLine(_row(status: OutboxStatus.dryRun, attempts: 1)), isNull);
  });

  testWidgets('a dry-run reason is muted; a failure is in the error colour',
      (tester) async {
    await _pump(tester, FakeOutboxSource()..rows = _oneOfEach());

    final scheme = Theme.of(tester.element(find.byType(OutboxScreen))).colorScheme;
    expect(
      tester.widget<Text>(find.text('Dry run: RESEND_API_KEY is not set')).style?.color,
      scheme.onSurfaceVariant,
    );
    expect(tester.widget<Text>(find.text('resend 503: busy')).style?.color, scheme.error);
  });

  testWidgets('owners and admins get Send again on failed and dry-run rows only',
      (tester) async {
    for (final role in [ResortRole.owner, ResortRole.admin]) {
      await _pump(tester, FakeOutboxSource()..rows = _oneOfEach(), role: role);

      expect(find.byKey(const Key('outbox-send-again-f')), findsOneWidget, reason: '$role');
      expect(find.byKey(const Key('outbox-send-again-d')), findsOneWidget, reason: '$role');
      for (final id in ['p', 'k', 's']) {
        expect(find.byKey(Key('outbox-send-again-$id')), findsNothing, reason: '$role $id');
      }
    }
  });

  testWidgets('staff and accountants see no Send again', (tester) async {
    for (final role in [ResortRole.staff, ResortRole.accountant]) {
      await _pump(tester, FakeOutboxSource()..rows = _oneOfEach(), role: role);

      expect(find.text('Send again'), findsNothing, reason: '$role');
    }
  });

  testWidgets('Send again retries the row, confirms, and reloads the list',
      (tester) async {
    final source = FakeOutboxSource()..rows = _oneOfEach();
    await _pump(tester, source);

    await tester.tap(find.byKey(const Key('outbox-send-again-f')));
    await tester.pumpAndSettle();

    expect(source.retried, ['f']);
    expect(find.text('Queued to send again.'), findsOneWidget);
    expect(source.listedPropertyIds.length, 2);
  });

  testWidgets('a refused Send again shows the readable reason', (tester) async {
    final source = FakeOutboxSource()
      ..rows = _oneOfEach()
      ..retryError = const NotRetryable();
    await _pump(tester, source);

    await tester.tap(find.byKey(const Key('outbox-send-again-d')));
    await tester.pumpAndSettle();

    expect(find.text('Only failed or dry-run messages can be sent again.'), findsOneWidget);
  });

  testWidgets('a status error does not hide the queue', (tester) async {
    await _pump(
      tester,
      FakeOutboxSource()
        ..rows = [_row(recipient: 'priya@example.com')]
        ..statusError = Exception('boom'),
    );

    expect(find.text('Delivery status is unavailable right now.'), findsOneWidget);
    expect(find.text('priya@example.com'), findsOneWidget);
  });

  testWidgets('a queue error goes through FailureView and keeps the panel',
      (tester) async {
    await _pump(tester, FakeOutboxSource()..error = Exception('boom'));

    expect(find.text('Something went wrong.'), findsOneWidget);
    expect(find.byKey(const Key('delivery-status-panel')), findsOneWidget);
  });

  testWidgets('Refresh reloads both the status and the queue', (tester) async {
    final source = FakeOutboxSource()..rows = [_row()];
    await _pump(tester, source);

    await tester.tap(find.byKey(const Key('outbox-refresh')));
    await tester.pumpAndSettle();

    expect(source.listedPropertyIds.length, 2);
    expect(source.statusPropertyIds.length, 2);
  });

  testWidgets('pull to refresh reloads the queue', (tester) async {
    final source = FakeOutboxSource()..rows = [_row()];
    await _pump(tester, source);

    await tester.fling(find.byType(ListView), const Offset(0, 1200), 1000);
    await tester.pumpAndSettle();

    expect(source.listedPropertyIds.length, 2);
  });
}
