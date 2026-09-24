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
}
