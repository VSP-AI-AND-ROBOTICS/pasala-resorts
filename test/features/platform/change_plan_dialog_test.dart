import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/errors.dart';
import 'package:pasala/data/models/subscription.dart';
import 'package:pasala/data/repositories/platform_repository.dart';
import 'package:pasala/features/platform/change_plan_dialog.dart';

import '../../support/fake_platform_source.dart';

final _paid = resortSummary(
  propertyId: 'p1',
  plan: resortPlan(
    tier: SubscriptionTier.pro,
    paidThrough: DateTime(2026, 10, 31),
    notes: 'Invoice 12',
  ),
);

Future<void> _open(
  WidgetTester tester,
  FakePlatformSource source,
  ResortSummary resort, {
  DateTime? today,
}) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [platformSourceProvider.overrideWithValue(source)],
    child: MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => showDialog<bool>(
                context: context,
                builder: (_) => ChangePlanDialog(resort: resort, today: today),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Future<void> _save(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('plan-save')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('opens on the current plan and saves it as it is',
      (tester) async {
    final source = FakePlatformSource();
    await _open(tester, source, _paid);

    expect(find.text('Paid until'), findsOneWidget);
    expect(find.text('31 Oct 2026'), findsOneWidget);
    await _save(tester);

    expect(source.subscriptionCalls, [
      (
        propertyId: 'p1',
        tier: SubscriptionTier.pro,
        status: SubscriptionStatus.active,
        trialEndsOn: null,
        paidThrough: DateTime(2026, 10, 31),
        notes: 'Invoice 12',
      ),
    ]);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('switching to Trial needs an end date before it saves',
      (tester) async {
    final source = FakePlatformSource();
    await _open(tester, source, _paid);

    await tester.tap(find.byKey(const Key('plan-tier')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enterprise').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Trial'));
    await tester.pumpAndSettle();

    expect(find.text('Trial ends'), findsOneWidget);
    expect(find.text('No end date'), findsOneWidget);
    await _save(tester);
    expect(find.text('Pick the date the trial ends.'), findsOneWidget);
    expect(source.subscriptionCalls, isEmpty);

    await tester.tap(find.byKey(const Key('plan-date')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Switch to input'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '11/15/2026');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('15 Nov 2026'), findsOneWidget);
    await _save(tester);

    expect(source.subscriptionCalls, [
      (
        propertyId: 'p1',
        tier: SubscriptionTier.enterprise,
        status: SubscriptionStatus.trial,
        trialEndsOn: DateTime(2026, 11, 15),
        paidThrough: null,
        notes: 'Invoice 12',
      ),
    ]);
  });

  testWidgets('a resort with no plan starts from a 30-day Starter trial',
      (tester) async {
    final source = FakePlatformSource();
    await _open(tester, source, resortSummary(propertyId: 'p9'),
        today: DateTime(2026, 9, 25));

    expect(find.text('25 Oct 2026'), findsOneWidget);
    await _save(tester);

    expect(source.subscriptionCalls, [
      (
        propertyId: 'p9',
        tier: SubscriptionTier.starter,
        status: SubscriptionStatus.trial,
        trialEndsOn: DateTime(2026, 10, 25),
        paidThrough: null,
        notes: null,
      ),
    ]);
  });

  testWidgets('clearing the paid-until date saves no end date',
      (tester) async {
    final source = FakePlatformSource();
    await _open(tester, source, _paid);

    await tester.tap(find.byKey(const Key('plan-date-clear')));
    await tester.pumpAndSettle();
    expect(find.text('No end date'), findsOneWidget);
    await _save(tester);

    expect(source.subscriptionCalls.single.paidThrough, isNull);
    expect(source.subscriptionCalls.single.status, SubscriptionStatus.active);
  });

  testWidgets('blank notes are sent as null', (tester) async {
    final source = FakePlatformSource();
    await _open(tester, source, _paid);

    await tester.enterText(find.byKey(const Key('plan-notes')), '   ');
    await _save(tester);

    expect(source.subscriptionCalls.single.notes, isNull);
  });

  testWidgets('a server refusal shows its message and keeps the dialog open',
      (tester) async {
    final source = FakePlatformSource()
      ..subscriptionError = const InvalidState('A trial needs an end date.');
    await _open(tester, source, _paid);

    await _save(tester);

    expect(find.text('A trial needs an end date.'), findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget);
  });
}
