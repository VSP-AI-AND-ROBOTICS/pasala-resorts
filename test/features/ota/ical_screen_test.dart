import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/data/models/ical_feed.dart';
import 'package:pasala/data/repositories/ical_repository.dart';
import 'package:pasala/features/ota/ical_screen.dart';

/// In-memory stand-in for [IcalRepository], mirroring `FakeOutboxSource`.
/// Never touches [Env] -- [exportUrl] returns a fixed test string, which is
/// the whole reason [IcalSource.exportUrl] exists as an overridable method
/// rather than a free function reaching into `Env.supabaseAnonKey`
/// (`flutter test` runs with no `--dart-define`, so that getter would
/// assert/crash the instant a widget under test tried to build the real
/// URL).
class FakeIcalSource implements IcalSource {
  List<IcalFeed> rows = [];
  String token = 'faketoken123';
  Object? feedsError;
  IcalSyncResult syncResult = const IcalSyncResult(status: 'ok', conflicts: 0);
  final added = <String>[];
  final removed = <String>[];
  bool rotated = false;

  @override
  Future<List<IcalFeed>> feeds(String unitId) async {
    if (feedsError != null) throw feedsError!;
    return rows;
  }

  @override
  Future<void> addFeed({
    required String unitId,
    required String url,
    String? label,
  }) async {
    added.add(url);
    rows = [
      ...rows,
      IcalFeed(
        id: 'new-${rows.length}',
        unitId: unitId,
        url: url,
        label: label,
        isActive: true,
      ),
    ];
  }

  @override
  Future<void> removeFeed(String feedId) async {
    removed.add(feedId);
    rows = rows.where((f) => f.id != feedId).toList();
  }

  @override
  Future<IcalSyncResult> syncFeed(String feedId) async => syncResult;

  @override
  Future<String> exportToken(String unitId) async => token;

  @override
  Future<String> rotateExportToken(String unitId) async {
    rotated = true;
    token = 'rotated-token';
    return token;
  }

  @override
  String exportUrl(String token) =>
      'https://fake.supabase.test/rest/v1/rpc/ical_export_public'
      '?token=$token&apikey=fake-anon-key';
}

IcalFeed _feed({
  String id = 'f1',
  String unitId = 'u1',
  String url = 'https://www.airbnb.com/calendar/ical/1.ics',
  String? label = 'Airbnb',
  DateTime? lastSyncedAt,
  String? lastError,
}) =>
    IcalFeed(
      id: id,
      unitId: unitId,
      url: url,
      label: label,
      isActive: true,
      lastSyncedAt: lastSyncedAt,
      lastError: lastError,
    );

void main() {
  Future<void> pump(WidgetTester tester, FakeIcalSource source,
      {String unitId = 'u1'}) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [icalSourceProvider.overrideWithValue(source)],
      child: MaterialApp(home: IcalScreen(unitId: unitId)),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('shows the export URL built from the fake token', (tester) async {
    await pump(tester, FakeIcalSource()..token = 'abc123');

    expect(
      find.text(
        'https://fake.supabase.test/rest/v1/rpc/ical_export_public'
        '?token=abc123&apikey=fake-anon-key',
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
    expect(clipboardCall.arguments['text'], contains('token=copytoken'));
    expect(find.text('Export URL copied'), findsOneWidget);
  });

  testWidgets('rotating the token asks for confirmation, then refreshes the '
      'URL shown', (tester) async {
    final source = FakeIcalSource()..token = 'old-token';
    await pump(tester, source);

    expect(find.textContaining('token=old-token'), findsOneWidget);

    await tester.tap(find.byKey(const Key('ical-rotate-token')));
    await tester.pumpAndSettle();

    // Confirmation dialog is shown, nothing rotated yet.
    expect(find.text('Rotate export token?'), findsOneWidget);
    expect(source.rotated, isFalse);

    await tester.tap(find.text('Rotate'));
    await tester.pumpAndSettle();

    expect(source.rotated, isTrue);
    expect(find.textContaining('token=rotated-token'), findsOneWidget);
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
    expect(find.textContaining('token=stays-the-same'), findsOneWidget);
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
    await pump(tester, FakeIcalSource()..rows = [_feed()]);

    expect(find.byKey(const Key('ical-feed-title')), findsOneWidget);
    expect(find.text('Never synced'), findsOneWidget);
  });

  testWidgets('a feed with a last_error shows it honestly', (tester) async {
    await pump(
      tester,
      FakeIcalSource()
        ..rows = [
          _feed(
            lastSyncedAt: DateTime.utc(2026, 8, 1, 10, 0),
            lastError: 'HTTP 503',
          ),
        ],
    );

    expect(find.textContaining('Last synced'), findsOneWidget);
    expect(find.text('HTTP 503'), findsOneWidget);
  });

  testWidgets('pressing Sync calls syncFeed and shows the outcome', (
    tester,
  ) async {
    final source = FakeIcalSource()
      ..rows = [_feed()]
      ..syncResult = const IcalSyncResult(status: 'ok', conflicts: 0);
    await pump(tester, source);

    await tester.tap(find.byKey(const Key('ical-sync-feed')));
    await tester.pumpAndSettle();

    expect(find.text('Synced -- no conflicts'), findsOneWidget);
  });

  testWidgets('a conflict during sync is reported, not silently dropped', (
    tester,
  ) async {
    final source = FakeIcalSource()
      ..rows = [_feed()]
      ..syncResult = const IcalSyncResult(status: 'ok', conflicts: 2);
    await pump(tester, source);

    await tester.tap(find.byKey(const Key('ical-sync-feed')));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Synced -- 2 event(s) conflicted with an existing booking and '
        'were skipped',
      ),
      findsOneWidget,
    );
  });

  testWidgets('a sync error from the RPC is shown, not swallowed', (
    tester,
  ) async {
    final source = FakeIcalSource()
      ..rows = [_feed()]
      ..syncResult = const IcalSyncResult(status: 'error', error: 'HTTP 503');
    await pump(tester, source);

    await tester.tap(find.byKey(const Key('ical-sync-feed')));
    await tester.pumpAndSettle();

    expect(find.text('HTTP 503'), findsOneWidget);
  });

  testWidgets('removing a feed calls removeFeed and drops it from the list', (
    tester,
  ) async {
    final source = FakeIcalSource()..rows = [_feed(id: 'gone')];
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
