import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/errors.dart';
import 'package:pasala/data/models/ical_feed.dart';
import 'package:pasala/data/repositories/ical_repository.dart';
import 'package:pasala/data/repositories/ical_sync_runner.dart';
import 'package:pasala/features/ota/feed_sync_status.dart';
import 'package:pasala/features/ota/ical_screen.dart';

import '../../support/fake_ical_source.dart';

final _now = DateTime.utc(2027, 1, 10, 12, 0);

void main() {
  /// [wait] is how the Sync now runner waits between calls; by default it
  /// returns at once.
  Future<void> pump(
    WidgetTester tester,
    FakeIcalSource source, {
    String unitId = 'u1',
    SyncWait? wait,
  }) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        icalSourceProvider.overrideWithValue(source),
        icalSyncRunnerProvider.overrideWithValue(
          IcalSyncRunner(source, wait: wait ?? (_) async {}),
        ),
      ],
      child: MaterialApp(home: IcalScreen(unitId: unitId, clock: () => _now)),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('shows the export URL built from the fake token', (tester) async {
    await pump(tester, FakeIcalSource()..token = 'abc123');

    expect(
      find.text(
        'https://fake.supabase.test/functions/v1/ical-export/abc123.ics',
      ),
      findsOneWidget,
    );
  });

  testWidgets('copying the export URL puts it on the clipboard', (tester) async {
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        calls.add(call);
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    await pump(tester, FakeIcalSource()..token = 'copytoken');

    await tester.tap(find.byKey(const Key('ical-copy-url')));
    await tester.pumpAndSettle();

    final clipboardCall = calls.firstWhere(
      (c) => c.method == 'Clipboard.setData',
    );
    expect(clipboardCall.arguments['text'], contains('/copytoken.ics'));
    expect(find.text('Export URL copied'), findsOneWidget);
  });

  testWidgets('rotating the token asks for confirmation, then refreshes the '
      'URL shown', (tester) async {
    final source = FakeIcalSource()..token = 'old-token';
    await pump(tester, source);

    expect(find.textContaining('/old-token.ics'), findsOneWidget);

    await tester.tap(find.byKey(const Key('ical-rotate-token')));
    await tester.pumpAndSettle();

    // Confirmation dialog is shown, nothing rotated yet.
    expect(find.text('Rotate export token?'), findsOneWidget);
    expect(source.rotated, isFalse);

    await tester.tap(find.text('Rotate'));
    await tester.pumpAndSettle();

    expect(source.rotated, isTrue);
    expect(find.textContaining('/rotated-token.ics'), findsOneWidget);
  });

  testWidgets('cancelling the rotate dialog leaves the token unchanged', (
    tester,
  ) async {
    final source = FakeIcalSource()..token = 'stays-the-same';
    await pump(tester, source);

    await tester.tap(find.byKey(const Key('ical-rotate-token')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(source.rotated, isFalse);
    expect(find.textContaining('/stays-the-same.ics'), findsOneWidget);
  });

  testWidgets('no import feeds yet shows a message, not an error', (
    tester,
  ) async {
    await pump(tester, FakeIcalSource());

    expect(find.text('No import feeds yet -- add one below.'), findsOneWidget);
  });

  testWidgets('a feed with no sync history shows "Never synced"', (
    tester,
  ) async {
    await pump(tester, FakeIcalSource()..rows = [icalFeed()]);

    expect(find.byKey(const Key('ical-feed-title')), findsOneWidget);
    expect(find.text('Never synced'), findsOneWidget);
  });

  testWidgets('an ok feed shows when it last synced and how many events',
      (tester) async {
    await pump(
      tester,
      FakeIcalSource()
        ..rows = [
          icalFeed(
            lastSyncedAt: _now.subtract(const Duration(minutes: 5)),
            lastStatus: FeedSyncStatus.ok,
            lastEventCount: 3,
          ),
        ],
    );

    expect(find.text('Last sync 5 min ago · 3 events'), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsNothing);
    expect(find.byIcon(Icons.warning_amber_outlined), findsNothing);
  });

  testWidgets('skipped events show as a warning with an icon', (tester) async {
    const note =
        '1 event(s) conflicted with an existing booking and were skipped';
    await pump(
      tester,
      FakeIcalSource()
        ..rows = [
          icalFeed(
            lastSyncedAt: _now.subtract(const Duration(minutes: 5)),
            lastStatus: FeedSyncStatus.ok,
            lastEventCount: 1,
            lastError: note,
          ),
        ],
    );

    expect(find.text('Last sync 5 min ago · 1 event'), findsOneWidget);
    expect(find.text(note), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_outlined), findsOneWidget);
  });

  testWidgets('a failing feed shows the error in red with an icon, a hint and '
      'the last good sync', (tester) async {
    await pump(
      tester,
      FakeIcalSource()
        ..rows = [
          icalFeed(
            lastSyncedAt: _now.subtract(const Duration(minutes: 5)),
            lastStatus: FeedSyncStatus.error,
            lastError: 'HTTP 404',
            lastOkAt: _now.subtract(const Duration(days: 2)),
            lastEventCount: 3,
          ),
        ],
    );

    final error = find.text('Sync failed 5 min ago: HTTP 404');
    expect(error, findsOneWidget);
    final context = tester.element(error);
    expect(tester.widget<Text>(error).style?.color,
        Theme.of(context).colorScheme.error);
    expect(find.text(hintRelink), findsOneWidget);
    expect(find.text('Last good sync 2 days ago'), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsNWidgets(2));
  });

  testWidgets('a feed the 15-minute job has not reached for over an hour is '
      'flagged', (tester) async {
    await pump(
      tester,
      FakeIcalSource()
        ..rows = [
          icalFeed(
            lastSyncedAt: _now.subtract(const Duration(hours: 3)),
            lastStatus: FeedSyncStatus.ok,
            lastEventCount: 2,
          ),
        ],
    );

    expect(find.text('Last sync 3 h ago · 2 events'), findsOneWidget);
    expect(find.text(staleWarning), findsOneWidget);
  });

  testWidgets('Sync now waits for a fresh result, reports it and reloads the '
      'feeds', (tester) async {
    final source = FakeIcalSource()
      ..rows = [icalFeed()]
      ..syncScript = [
        const IcalSyncResult(status: 'ok', events: 1),
        const IcalSyncResult(status: 'ok', events: 3),
      ];
    await pump(tester, source);
    final loadsBefore = source.feedsCalls;

    await tester.tap(find.widgetWithText(TextButton, 'Sync now'));
    await tester.pumpAndSettle();

    expect(source.syncCalls, ['f1', 'f1']);
    expect(find.text('Synced -- 3 events'), findsOneWidget);
    expect(source.feedsCalls, greaterThan(loadsBefore));
  });

  testWidgets('while syncing, a spinner replaces Sync now', (tester) async {
    final gate = Completer<void>();
    final source = FakeIcalSource()..rows = [icalFeed()];
    await pump(tester, source, wait: (_) => gate.future);

    await tester.tap(find.byKey(const Key('ical-sync-feed')));
    await tester.pump();

    expect(find.byKey(const Key('ical-syncing')), findsOneWidget);
    expect(find.text('Syncing…'), findsOneWidget);
    expect(find.byKey(const Key('ical-sync-feed')), findsNothing);
    expect(
      tester
          .widget<TextButton>(find.byKey(const Key('ical-remove-feed')))
          .onPressed,
      isNull,
    );

    gate.complete();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ical-sync-feed')), findsOneWidget);
  });

  testWidgets('conflicts from Sync now are reported, not silently dropped', (
    tester,
  ) async {
    final source = FakeIcalSource()
      ..rows = [icalFeed()]
      ..syncResult =
          const IcalSyncResult(status: 'ok', events: 3, conflicts: 1);
    await pump(tester, source);

    await tester.tap(find.byKey(const Key('ical-sync-feed')));
    await tester.pumpAndSettle();

    expect(find.text('Synced -- 3 events, 1 conflict skipped'), findsOneWidget);
  });

  testWidgets('a sync error is shown, not swallowed', (tester) async {
    final source = FakeIcalSource()
      ..rows = [icalFeed()]
      ..syncResult = const IcalSyncResult(status: 'error', error: 'HTTP 503');
    await pump(tester, source);

    await tester.tap(find.byKey(const Key('ical-sync-feed')));
    await tester.pumpAndSettle();

    expect(find.text('Sync failed: HTTP 503'), findsOneWidget);
  });

  testWidgets('a sync that is still running when the runner gives up says so',
      (tester) async {
    final source = FakeIcalSource()
      ..rows = [icalFeed()]
      ..syncResult = const IcalSyncResult(status: 'pending');
    await pump(tester, source);

    await tester.tap(find.byKey(const Key('ical-sync-feed')));
    await tester.pumpAndSettle();

    expect(find.text('Still syncing -- the result will show here shortly.'),
        findsOneWidget);
    expect(source.syncCalls, hasLength(8));
  });

  testWidgets('a refused Sync (no access) goes through FailureView copy',
      (tester) async {
    final source = FakeIcalSource()
      ..rows = [icalFeed()]
      ..syncError = const NotPermitted();
    await pump(tester, source);

    await tester.tap(find.byKey(const Key('ical-sync-feed')));
    await tester.pumpAndSettle();

    expect(find.text('You do not have access to do that.'), findsOneWidget);
    expect(find.byKey(const Key('ical-sync-feed')), findsOneWidget);
  });

  testWidgets('removing a feed calls removeFeed and drops it from the list', (
    tester,
  ) async {
    final source = FakeIcalSource()..rows = [icalFeed(id: 'gone')];
    await pump(tester, source);

    expect(find.byKey(const Key('ical-feed-title')), findsOneWidget);

    await tester.tap(find.byKey(const Key('ical-remove-feed')));
    await tester.pumpAndSettle();

    expect(source.removed, ['gone']);
    expect(find.byKey(const Key('ical-feed-title')), findsNothing);
  });

  testWidgets('the Add feed button is disabled until a URL is entered', (
    tester,
  ) async {
    await pump(tester, FakeIcalSource());

    final button =
        tester.widget<FilledButton>(find.byKey(const Key('ical-add-feed')));
    expect(button.onPressed, isNull);

    await tester.enterText(
      find.byKey(const Key('ical-feed-url')),
      'https://www.booking.com/ical/2.ics',
    );
    await tester.pump();

    final enabledButton =
        tester.widget<FilledButton>(find.byKey(const Key('ical-add-feed')));
    expect(enabledButton.onPressed, isNotNull);
  });

  testWidgets('adding a feed calls addFeed with the entered URL and label', (
    tester,
  ) async {
    final source = FakeIcalSource();
    await pump(tester, source, unitId: 'unit-7');

    await tester.enterText(
      find.byKey(const Key('ical-feed-url')),
      'https://www.booking.com/ical/2.ics',
    );
    await tester.enterText(
      find.byKey(const Key('ical-feed-label')),
      'Booking.com',
    );
    await tester.tap(find.byKey(const Key('ical-add-feed')));
    await tester.pumpAndSettle();

    expect(source.added, ['https://www.booking.com/ical/2.ics']);
    expect(find.text('Booking.com'), findsOneWidget);
  });

  testWidgets('a feed removed while Sync now runs says so and reloads the '
      'list', (tester) async {
    final source = FakeIcalSource()
      ..rows = [icalFeed()]
      ..syncError = const NotFound();
    await pump(tester, source);
    final loadsBefore = source.feedsCalls;

    await tester.tap(find.byKey(const Key('ical-sync-feed')));
    await tester.pumpAndSettle();

    expect(find.text('That item no longer exists.'), findsOneWidget);
    expect(source.feedsCalls, greaterThan(loadsBefore));
  });

  testWidgets('a link that is not http(s) or webcal is refused by the form',
      (tester) async {
    await pump(tester, FakeIcalSource());

    await tester.enterText(
      find.byKey(const Key('ical-feed-url')),
      'airbnb.com/calendar/ical/1.ics',
    );
    await tester.pump();

    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('ical-add-feed')))
          .onPressed,
      isNull,
    );
    expect(
      find.text('Paste the calendar link (starts with https:// or webcal://).'),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const Key('ical-feed-url')),
      'webcal://www.airbnb.com/calendar/ical/1.ics',
    );
    await tester.pump();

    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('ical-add-feed')))
          .onPressed,
      isNotNull,
    );
    expect(
      find.text('Paste the calendar link (starts with https:// or webcal://).'),
      findsNothing,
    );
  });

  testWidgets('a feed the server refuses (P0039) shows why', (tester) async {
    final source = FakeIcalSource()
      ..addError = const FeedUrlRejected(FeedUrlRejected.duplicate);
    await pump(tester, source);

    await tester.enterText(
      find.byKey(const Key('ical-feed-url')),
      'https://www.airbnb.com/calendar/ical/1.ics',
    );
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('ical-add-feed')));
    await tester.tap(find.byKey(const Key('ical-add-feed')));
    await tester.pumpAndSettle();

    expect(find.text('This calendar is already added to this unit.'),
        findsOneWidget);
    expect(source.added, isEmpty);
  });

  testWidgets('a failing feed fits a 360 px phone without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await pump(
      tester,
      FakeIcalSource()
        ..rows = [
          icalFeed(
            label: 'Airbnb -- Cottage by the long lake',
            url: 'https://www.airbnb.com/calendar/ical/12345678901234567890.ics'
                '?s=0123456789abcdef0123456789abcdef',
            lastSyncedAt: _now.subtract(const Duration(hours: 2)),
            lastStatus: FeedSyncStatus.error,
            lastError: 'not a calendar: the link did not return iCal data',
          ),
        ],
    );

    expect(tester.takeException(), isNull);
    expect(find.widgetWithText(TextButton, 'Sync now'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Remove'), findsOneWidget);
  });

  testWidgets('an export-token repository error goes through FailureView, '
      'not a raw exception', (tester) async {
    final source = FakeIcalSource();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        icalSourceProvider.overrideWithValue(source),
        icalExportTokenProvider('u1').overrideWith(
          (ref) => Future<String>.error(Exception('boom')),
        ),
      ],
      child: const MaterialApp(home: IcalScreen(unitId: 'u1')),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Something went wrong.'), findsOneWidget);
  });
}
