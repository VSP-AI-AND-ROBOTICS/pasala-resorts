import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/current_resort.dart';
import 'package:pasala/data/models/outbox_message.dart';
import 'package:pasala/data/models/resort_membership.dart';
import 'package:pasala/data/repositories/outbox_repository.dart';
import 'package:pasala/features/outbox/outbox_screen.dart';

import '../../support/fake_outbox_source.dart';

const _resort =
    ResortMembership(propertyId: 'p1', resortName: 'Pasala', role: ResortRole.admin);

class _FixedResort extends CurrentResort {
  @override
  ResortMembership? build() => _resort;
}

OutboxMessage _row({
  String id = 'm1',
  OutboxChannel channel = OutboxChannel.email,
  String recipient = 'guest@example.com',
  String template = 'booking_confirmation',
  OutboxStatus status = OutboxStatus.pending,
  String? lastError,
}) =>
    OutboxMessage(
      id: id,
      reservationId: 'r1',
      channel: channel,
      recipient: recipient,
      template: template,
      status: status,
      attempts: 0,
      lastError: lastError,
      createdAt: DateTime.utc(2026, 8, 1, 10, 30),
    );

void main() {
  Future<void> pump(WidgetTester tester, FakeOutboxSource source) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        outboxSourceProvider.overrideWithValue(source),
        currentResortProvider.overrideWith(_FixedResort.new),
      ],
      child: const MaterialApp(home: OutboxScreen()),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'the "no delivery provider" banner is always visible, even with '
      'nothing queued', (tester) async {
    await pump(tester, FakeOutboxSource());

    expect(find.byKey(const Key('no-provider-banner')), findsOneWidget);
    expect(
      find.text(
        'No delivery provider is configured. Messages are queued but '
        'not sent.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('the banner has no close/dismiss control', (tester) async {
    await pump(
      tester,
      FakeOutboxSource()..rows = [_row()],
    );

    final bannerFinder = find.byKey(const Key('no-provider-banner'));
    expect(bannerFinder, findsOneWidget);
    expect(
      find.descendant(
        of: bannerFinder,
        matching: find.byIcon(Icons.close),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: bannerFinder,
        matching: find.byType(IconButton),
      ),
      findsNothing,
    );
  });

  testWidgets('an empty queue shows an EmptyState, not an error', (
    tester,
  ) async {
    await pump(tester, FakeOutboxSource());

    expect(find.text('Nothing queued yet'), findsOneWidget);
  });

  testWidgets('messages are grouped into sections by status', (tester) async {
    final source = FakeOutboxSource()
      ..rows = [
        _row(id: 'm1', status: OutboxStatus.pending),
        _row(id: 'm2', status: OutboxStatus.pending, template: 'cancellation'),
        _row(
          id: 'm3',
          status: OutboxStatus.skipped,
          channel: OutboxChannel.sms,
          recipient: 'no phone on file',
          lastError: 'cannot deliver via sms: customer u1 has no phone '
              'number on file',
        ),
      ];

    await pump(tester, source);

    expect(find.text('Pending (2)'), findsOneWidget);
    expect(find.text('Skipped (1)'), findsOneWidget);
    expect(find.text('Failed (0)'), findsNothing);
    expect(find.text('no phone on file'), findsOneWidget);
  });

  testWidgets('a row shows its channel, recipient and template', (
    tester,
  ) async {
    final source = FakeOutboxSource()
      ..rows = [
        _row(
          recipient: 'priya@example.com',
          template: 'booking_confirmation',
          channel: OutboxChannel.email,
        ),
      ];
    await pump(tester, source);

    expect(find.text('priya@example.com'), findsOneWidget);
    expect(find.textContaining('booking_confirmation'), findsOneWidget);
    expect(find.textContaining('Email'), findsOneWidget);
    // Review Focus #1: the screen must pass the current resort's id
    // through to the repository, not rely on RLS alone.
    expect(source.listedPropertyIds, everyElement('p1'));
  });

  testWidgets('a skipped row surfaces its last_error', (tester) async {
    await pump(
      tester,
      FakeOutboxSource()
        ..rows = [
          _row(
            status: OutboxStatus.skipped,
            channel: OutboxChannel.sms,
            recipient: 'no phone on file',
            lastError:
                'cannot deliver via sms: customer u1 has no phone number '
                'on file',
          ),
        ],
    );

    expect(
      find.text(
        'cannot deliver via sms: customer u1 has no phone number on file',
      ),
      findsOneWidget,
    );
  });

  // I7: no test in this file ever constructed an `OutboxStatus.sent` row --
  // yet `_statusOrder` lists it and `_GroupedList` would happily render a
  // "Sent (N)" section for one, right alongside the permanent "No delivery
  // provider is configured ... not sent" banner. Nothing in this phase can
  // write `status = 'sent'` today (see the migration header on
  // `public.outbox` -- there is no INSERT/UPDATE grant that would let any
  // client set it), so this can't happen against the real database yet --
  // but that is exactly why this path was never exercised, and exactly
  // where a future change (e.g. some new "hide the banner once something
  // sent" shortcut) could land unnoticed. This pins the current, correct
  // behaviour: even with a sent row in view, the banner is unconditional
  // and the screen never claims delivery is now working.
  testWidgets(
      'a sent row groups under its own section but never suppresses the '
      '"not sent" banner', (tester) async {
    await pump(
      tester,
      FakeOutboxSource()
        ..rows = [
          _row(id: 'm1', status: OutboxStatus.sent, template: 'cancellation'),
        ],
    );

    expect(find.text('Sent (1)'), findsOneWidget);
    expect(
      find.byKey(const Key('no-provider-banner')),
      findsOneWidget,
      reason: 'the banner is a permanent, structural fact about this phase '
          '-- a sent row existing at all must never suppress or reword it',
    );
    expect(
      find.text(
        'No delivery provider is configured. Messages are queued but '
        'not sent.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('a repository error goes through FailureView, not a raw '
      'exception', (tester) async {
    await pump(tester, FakeOutboxSource()..error = Exception('boom'));

    expect(find.text('Something went wrong.'), findsOneWidget);
    // The banner must still show even when the query underneath fails --
    // it is a fact about the product, not a status derived from the query.
    expect(find.byKey(const Key('no-provider-banner')), findsOneWidget);
  });
}
