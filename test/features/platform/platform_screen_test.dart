import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/errors.dart';
import 'package:pasala/core/format.dart';
import 'package:pasala/core/theme/app_theme.dart';
import 'package:pasala/core/theme/theme_toggle_button.dart';
import 'package:pasala/data/models/subscription.dart';
import 'package:pasala/data/repositories/platform_repository.dart';
import 'package:pasala/features/platform/platform_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_platform_source.dart';

final _resortA = ResortSummary(
  propertyId: 'p1',
  name: 'Resort A',
  status: 'active',
  ownerEmails: const ['ownera@x.com'],
  createdAt: DateTime(2024, 1, 1),
  bookings30d: 5,
  revenue30d: 12000,
  bookings365d: 60,
  revenue365d: 140000,
);

final _resortB = ResortSummary(
  propertyId: 'p2',
  name: 'Resort B',
  status: 'suspended',
  ownerEmails: const ['ownerb@x.com'],
  createdAt: DateTime(2024, 2, 1),
  bookings30d: 0,
  revenue30d: 0,
  bookings365d: 10,
  revenue365d: 20000,
);

final _resortC = ResortSummary(
  propertyId: 'p3',
  name: 'Resort C',
  status: 'archived',
  ownerEmails: const ['ownerc@x.com'],
  createdAt: DateTime(2024, 3, 1),
  bookings30d: 0,
  revenue30d: 0,
  bookings365d: 0,
  revenue365d: 0,
);

Widget _appFor(FakePlatformSource repo, {ThemeMode themeMode = ThemeMode.light}) =>
    ProviderScope(
      overrides: [platformSourceProvider.overrideWithValue(repo)],
      child: MaterialApp(
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        themeMode: themeMode,
        home: const PlatformScreen(),
      ),
    );

/// A surface tall enough that every card in these tests is built.
void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('renders two resorts from a fake', (tester) async {
    final repo = FakePlatformSource()..store = [_resortA, _resortB];
    await tester.pumpWidget(_appFor(repo));
    await tester.pumpAndSettle();

    expect(find.text('Resort A'), findsOneWidget);
    expect(find.text('Resort B'), findsOneWidget);
    expect(find.textContaining('ownera@x.com'), findsOneWidget);
    expect(find.textContaining('ownerb@x.com'), findsOneWidget);
    expect(find.textContaining(formatInr(12000)), findsOneWidget);
  });

  testWidgets('tapping Suspend then confirming calls setStatus(id, suspended)', (
    tester,
  ) async {
    final repo = FakePlatformSource()..store = [_resortA, _resortB];
    await tester.pumpWidget(_appFor(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('resort-status-btn-p1')));
    await tester.pumpAndSettle();

    // Confirmation dialog is up; confirm it.
    await tester.tap(find.widgetWithText(FilledButton, 'Suspend'));
    await tester.pumpAndSettle();

    expect(repo.statusCalls, [('p1', 'suspended')]);
  });

  testWidgets('creating a resort calls createResort and refreshes the list', (
    tester,
  ) async {
    // Plan check note (Task 4): with the totals row and filter bar now
    // above the list, the third card falls outside the default test
    // viewport's cache extent and never gets built. Needs the same tall
    // surface as the Task 4 console tests.
    _tall(tester);
    final repo = FakePlatformSource()..store = [_resortA, _resortB];
    await tester.pumpWidget(_appFor(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const Key('new-resort-name')), 'Resort E');
    await tester.enterText(
        find.byKey(const Key('new-resort-owner-email')), 'owner@x.com');
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pumpAndSettle();

    expect(repo.createCalls,
        [('Resort E', 'owner@x.com', SubscriptionTier.starter, 30)]);
    expect(find.text('Resort E'), findsOneWidget);
  });

  testWidgets('a suspended resort offers Reactivate, which sets it active',
      (tester) async {
    final repo = FakePlatformSource()..store = [_resortB];
    await tester.pumpWidget(_appFor(repo));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(OutlinedButton, 'Reactivate'), findsOneWidget);
    await tester.tap(find.byKey(const Key('resort-status-btn-p2')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Reactivate'));
    await tester.pumpAndSettle();

    expect(repo.statusCalls, [('p2', 'active')]);
  });

  // Final review F3: an archived resort is not active, so it must not offer
  // "Suspend" as if it were; it shows its status and no action at all.
  testWidgets('an archived resort shows its status and no status action',
      (tester) async {
    final repo = FakePlatformSource()..store = [_resortC];
    await tester.pumpWidget(_appFor(repo));
    await tester.pumpAndSettle();

    expect(find.text('Archived'), findsOneWidget);
    expect(find.byKey(const Key('resort-status-btn-p3')), findsNothing);
    expect(find.text('Suspend'), findsNothing);
    expect(find.text('Reactivate'), findsNothing);
  });

  testWidgets('shows the theme toggle in the platform app bar', (
    tester,
  ) async {
    final repo = FakePlatformSource()..store = [_resortA];
    await tester.pumpWidget(_appFor(repo));
    await tester.pumpAndSettle();

    expect(find.byType(ThemeToggleButton), findsOneWidget);
  });

  testWidgets('renders in ThemeMode.dark without throwing', (tester) async {
    final repo = FakePlatformSource()..store = [_resortA, _resortB, _resortC];
    await tester.pumpWidget(_appFor(repo, themeMode: ThemeMode.dark));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Resort A'), findsOneWidget);
  });

  group('cards, search and tier filter', () {
    final paidPro = resortSummary(
        propertyId: 'p1',
        name: 'Resort A',
        ownerEmails: const ['ownera@x.com'],
        plan: resortPlan(tier: SubscriptionTier.pro));
    final trialStarter = resortSummary(
        propertyId: 'p2',
        name: 'Resort B',
        ownerEmails: const ['ownerb@x.com'],
        plan: resortPlan(
            tier: SubscriptionTier.starter,
            status: SubscriptionStatus.trial,
            trialEndsOn: DateTime(2026, 10, 24)));
    final noPlan = resortSummary(
        propertyId: 'p3', name: 'Hill Stay', ownerEmails: const ['hill@x.com']);

    Finder inCard(String key, String text) => find.descendant(
        of: find.byKey(Key(key)), matching: find.text(text));

    testWidgets('the cards show the platform totals', (tester) async {
      _tall(tester);
      final repo = FakePlatformSource()
        ..store = [paidPro]
        ..totalsValue = const PlatformTotals(
            subscribed: 21, active: 19, trials: 2, mrrInr: 123456);
      await tester.pumpWidget(_appFor(repo));
      await tester.pumpAndSettle();

      expect(inCard('total-subscribed', 'Subscribed resorts'), findsOneWidget);
      expect(inCard('total-subscribed', '21'), findsOneWidget);
      expect(inCard('total-active', 'Active subscriptions'), findsOneWidget);
      expect(inCard('total-active', '19'), findsOneWidget);
      expect(inCard('total-active', 'incl. 2 trials'), findsOneWidget);
      expect(inCard('total-mrr', 'MRR'), findsOneWidget);
      expect(inCard('total-mrr', formatInr(123456)), findsOneWidget);
    });

    testWidgets('one trial reads "incl. 1 trial"', (tester) async {
      final repo = FakePlatformSource()
        ..store = [paidPro]
        ..totalsValue = const PlatformTotals(
            subscribed: 1, active: 1, trials: 1, mrrInr: 0);
      await tester.pumpWidget(_appFor(repo));
      await tester.pumpAndSettle();

      expect(inCard('total-active', 'incl. 1 trial'), findsOneWidget);
    });

    testWidgets(
        'search matches names and owner emails, ignoring case and spaces',
        (tester) async {
      _tall(tester);
      final repo = FakePlatformSource()..store = [paidPro, trialStarter, noPlan];
      await tester.pumpWidget(_appFor(repo));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const Key('resort-search')), '  RESORT a ');
      await tester.pumpAndSettle();
      expect(find.text('Resort A'), findsOneWidget);
      expect(find.text('Resort B'), findsNothing);
      expect(find.text('Hill Stay'), findsNothing);

      await tester.enterText(find.byKey(const Key('resort-search')), 'hill@');
      await tester.pumpAndSettle();
      expect(find.text('Hill Stay'), findsOneWidget);
      expect(find.text('Resort A'), findsNothing);
    });

    testWidgets('the tier dropdown narrows the list and All tiers restores it',
        (tester) async {
      _tall(tester);
      final repo = FakePlatformSource()..store = [paidPro, trialStarter, noPlan];
      await tester.pumpWidget(_appFor(repo));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('tier-filter')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pro').last);
      await tester.pumpAndSettle();
      expect(find.text('Resort A'), findsOneWidget);
      expect(find.text('Resort B'), findsNothing);
      expect(find.text('Hill Stay'), findsNothing);

      await tester.tap(find.byKey(const Key('tier-filter')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('All tiers').last);
      await tester.pumpAndSettle();
      expect(find.text('Resort A'), findsOneWidget);
      expect(find.text('Resort B'), findsOneWidget);
      expect(find.text('Hill Stay'), findsOneWidget);
    });

    testWidgets('a search that matches nothing says so', (tester) async {
      final repo = FakePlatformSource()..store = [paidPro];
      await tester.pumpWidget(_appFor(repo));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('resort-search')), 'zzz');
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('no-matching-resorts')), findsOneWidget);
      expect(find.text('No resorts match your search.'), findsOneWidget);
    });

    testWidgets('a status change refreshes the cards as well as the list',
        (tester) async {
      final repo = FakePlatformSource()..store = [paidPro];
      await tester.pumpWidget(_appFor(repo));
      await tester.pumpAndSettle();
      expect(repo.totalsCalls, 1);

      await tester.tap(find.byKey(const Key('resort-status-btn-p1')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Suspend'));
      await tester.pumpAndSettle();

      expect(repo.totalsCalls, 2);
    });

    testWidgets('failed totals offer a retry and keep the list',
        (tester) async {
      final repo = FakePlatformSource()
        ..store = [paidPro]
        ..totalsError = const NetworkFailure();
      // retry: null -- without it Riverpod 3 keeps retrying the failed
      // provider and the error never settles.
      await tester.pumpWidget(ProviderScope(
        retry: (_, _) => null,
        overrides: [platformSourceProvider.overrideWithValue(repo)],
        child: const MaterialApp(home: PlatformScreen()),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Resort A'), findsOneWidget);
      expect(find.byKey(const Key('totals-retry')), findsOneWidget);

      repo.totalsError = null;
      await tester.tap(find.byKey(const Key('totals-retry')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('totals-retry')), findsNothing);
      expect(repo.totalsCalls, 2);
    });
  });
}
