import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/errors.dart';
import 'package:pasala/data/models/subscription.dart';
import 'package:pasala/data/repositories/platform_repository.dart';
import 'package:pasala/features/platform/platform_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_platform_source.dart';

/// Opens Plan prices from the console, the way the admin does.
Future<void> _openFromConsole(
    WidgetTester tester, FakePlatformSource source) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [platformSourceProvider.overrideWithValue(source)],
    child: const MaterialApp(home: PlatformScreen()),
  ));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('plan-prices-btn')));
  await tester.pumpAndSettle();
}

String _field(WidgetTester tester, String key) =>
    tester.widget<TextField>(find.byKey(Key(key))).controller!.text;

Future<void> _save(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('plan-prices-save')));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('shows the current monthly price of each plan', (tester) async {
    final source = FakePlatformSource()..store = [resortSummary()];
    await _openFromConsole(tester, source);

    expect(_field(tester, 'plan-price-starter'), '2999');
    expect(_field(tester, 'plan-price-pro'), '7999');
    expect(_field(tester, 'plan-price-enterprise'), '19999');
  });

  testWidgets('Save sends only the prices that changed and refreshes MRR',
      (tester) async {
    final source = FakePlatformSource()..store = [resortSummary()];
    await _openFromConsole(tester, source);
    expect(source.totalsCalls, 1);

    await tester.enterText(find.byKey(const Key('plan-price-pro')), '8999');
    await _save(tester);

    expect(source.priceCalls, [(SubscriptionTier.pro, 8999)]);
    expect(find.byType(AlertDialog), findsNothing);
    expect(source.totalsCalls, 2);
  });

  testWidgets('a negative or non-numeric price is refused and nothing is saved',
      (tester) async {
    final source = FakePlatformSource()..store = [resortSummary()];
    await _openFromConsole(tester, source);

    for (final price in ['-5', 'abc', '']) {
      await tester.enterText(find.byKey(const Key('plan-price-pro')), price);
      await _save(tester);
      expect(find.text('Enter a monthly price of 0 or more for every plan.'),
          findsOneWidget,
          reason: 'price "$price"');
    }
    expect(source.priceCalls, isEmpty);
  });

  testWidgets('a server refusal shows its message and keeps the dialog',
      (tester) async {
    final source = FakePlatformSource()
      ..store = [resortSummary()]
      ..priceError =
          const InvalidState('Enter a monthly price from 0 to 1,00,00,000.');
    await _openFromConsole(tester, source);

    await tester.enterText(
        find.byKey(const Key('plan-price-starter')), '99999999');
    await _save(tester);

    expect(find.text('Enter a monthly price from 0 to 1,00,00,000.'),
        findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget);
  });

  testWidgets("shows each plan's Razorpay plan id and saves only the changes",
      (tester) async {
    final source = FakePlatformSource()
      ..store = [resortSummary()]
      ..planList = [
        for (final p in defaultPlans)
          SubscriptionPlan(
            tier: p.tier,
            name: p.name,
            monthlyPriceInr: p.monthlyPriceInr,
            sortOrder: p.sortOrder,
            razorpayPlanId: p.tier == SubscriptionTier.starter
                ? 'plan_StarterMon001'
                : null,
          ),
      ];
    await _openFromConsole(tester, source);

    expect(_field(tester, 'plan-razorpay-starter'), 'plan_StarterMon001');
    expect(_field(tester, 'plan-razorpay-pro'), '');

    await tester.ensureVisible(find.byKey(const Key('plan-razorpay-starter')));
    await tester.enterText(find.byKey(const Key('plan-razorpay-starter')), '');
    await tester.ensureVisible(find.byKey(const Key('plan-razorpay-pro')));
    await tester.enterText(
        find.byKey(const Key('plan-razorpay-pro')), ' plan_ProMonthly0001 ');
    await _save(tester);

    expect(source.priceCalls, isEmpty);
    expect(source.planIdCalls, [
      (SubscriptionTier.starter, null),
      (SubscriptionTier.pro, 'plan_ProMonthly0001'),
    ]);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('a malformed Razorpay plan id is refused and nothing is saved',
      (tester) async {
    final source = FakePlatformSource()..store = [resortSummary()];
    await _openFromConsole(tester, source);

    await tester.ensureVisible(find.byKey(const Key('plan-razorpay-pro')));
    await tester.enterText(find.byKey(const Key('plan-razorpay-pro')), 'pro-monthly');
    await _save(tester);

    expect(
        find.text(
            'A Razorpay plan id looks like plan_ followed by letters and digits.'),
        findsOneWidget);
    expect(source.planIdCalls, isEmpty);
    expect(source.priceCalls, isEmpty);
    expect(find.byType(AlertDialog), findsOneWidget);
  });

  testWidgets('a refused plan id shows the server message', (tester) async {
    final source = FakePlatformSource()
      ..store = [resortSummary()]
      ..planIdError = const InvalidState(
          'That Razorpay plan id is already used by another plan.');
    await _openFromConsole(tester, source);

    await tester.ensureVisible(find.byKey(const Key('plan-razorpay-pro')));
    await tester.enterText(
        find.byKey(const Key('plan-razorpay-pro')), 'plan_ProMonthly0001');
    await _save(tester);

    expect(find.text('That Razorpay plan id is already used by another plan.'),
        findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget);
  });
}
