import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/data/models/subscription.dart';
import 'package:pasala/data/repositories/platform_repository.dart';
import 'package:pasala/features/platform/resort_card.dart';

import '../../support/fake_platform_source.dart';

Future<void> _pump(
  WidgetTester tester,
  FakePlatformSource source,
  ResortSummary resort, {
  VoidCallback? onChanged,
}) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [platformSourceProvider.overrideWithValue(source)],
    child: MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ResortCard(resort: resort, onChanged: onChanged ?? () {}),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a paid plan shows its tier and its paid-until date',
      (tester) async {
    await _pump(
        tester,
        FakePlatformSource(),
        resortSummary(
            plan: resortPlan(
                tier: SubscriptionTier.pro,
                paidThrough: DateTime(2026, 10, 31))));

    expect(
        find.descendant(
            of: find.byKey(const Key('resort-tier-p1')),
            matching: find.text('Pro')),
        findsOneWidget);
    expect(find.text('Paid until 31 Oct 2026'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Change plan'), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
  });

  testWidgets('a lapsed plan says Lapsed, with an icon, in the error colour',
      (tester) async {
    await _pump(
        tester,
        FakePlatformSource(),
        resortSummary(
            plan: resortPlan(
                paidThrough: DateTime(2026, 9, 30), lapsed: true)));

    final line = find.text('Lapsed: paid until 30 Sep 2026');
    expect(line, findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    final error =
        Theme.of(tester.element(find.byType(ResortCard))).colorScheme.error;
    expect(tester.widget<Text>(line).style?.color, error);
  });

  testWidgets('a resort with no plan shows No plan and offers Set plan',
      (tester) async {
    await _pump(tester, FakePlatformSource(), resortSummary());

    expect(
        find.descendant(
            of: find.byKey(const Key('resort-tier-p1')),
            matching: find.text('No plan')),
        findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Set plan'), findsOneWidget);
  });

  testWidgets('an archived resort offers neither a plan nor a status action',
      (tester) async {
    await _pump(
        tester,
        FakePlatformSource(),
        resortSummary(
            propertyId: 'p3', status: 'archived', plan: resortPlan()));

    expect(find.byKey(const Key('resort-plan-btn-p3')), findsNothing);
    expect(find.byKey(const Key('resort-status-btn-p3')), findsNothing);
  });

  testWidgets('saving the Change plan dialog calls onChanged once',
      (tester) async {
    final source = FakePlatformSource();
    var changed = 0;
    await _pump(tester, source, resortSummary(plan: resortPlan()),
        onChanged: () => changed++);

    await tester.tap(find.byKey(const Key('resort-plan-btn-p1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('plan-save')));
    await tester.pumpAndSettle();

    expect(source.subscriptionCalls, hasLength(1));
    expect(changed, 1);
  });

  testWidgets('cancelling the dialog changes nothing', (tester) async {
    final source = FakePlatformSource();
    var changed = 0;
    await _pump(tester, source, resortSummary(plan: resortPlan()),
        onChanged: () => changed++);

    await tester.tap(find.byKey(const Key('resort-plan-btn-p1')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(source.subscriptionCalls, isEmpty);
    expect(changed, 0);
  });
}
