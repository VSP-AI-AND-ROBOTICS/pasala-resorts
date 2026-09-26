import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pasala/core/errors.dart';
import 'package:pasala/data/models/billing.dart';
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

  // E2E-shaped bug: a screen embedding [ResortCard] inside the router's
  // ShellRoute would have its context resolve to the shell navigator while
  // showDialog puts the confirm dialog on the root one. The dialog's
  // buttons must pop the dialog, not the page (mirrors
  // lib/features/admin/tasks_screen.dart's ShellRoute regression test).
  testWidgets(
      'confirming Suspend inside a ShellRoute closes the dialog, not the page',
      (tester) async {
    final source = FakePlatformSource();
    var changed = 0;
    final resort = resortSummary(plan: resortPlan());
    final router = GoRouter(
      initialLocation: '/platform',
      routes: [
        ShellRoute(
          builder: (_, _, child) => Scaffold(body: child),
          routes: [
            GoRoute(path: '/', builder: (_, _) => const Text('Home')),
            GoRoute(
              path: '/platform',
              builder: (_, _) => Scaffold(
                body: SingleChildScrollView(
                  child: ResortCard(resort: resort, onChanged: () => changed++),
                ),
              ),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(ProviderScope(
      overrides: [platformSourceProvider.overrideWithValue(source)],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pumpAndSettle();

    // Cancel first: the dialog closes and the page stays.
    await tester.tap(find.byKey(const Key('resort-status-btn-p1')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(ResortCard), findsOneWidget);
    expect(source.statusCalls, isEmpty);

    await tester.tap(find.byKey(const Key('resort-status-btn-p1')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Suspend'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(ResortCard), findsOneWidget);
    expect(source.statusCalls, [('p1', 'suspended')]);
    expect(changed, 1);
  });

  testWidgets('shows the auto-pay state and the last payment', (tester) async {
    final source = FakePlatformSource()
      ..billingList = [
        PlatformBilling(
          propertyId: 'p1',
          status: GatewayStatus.active,
          tier: SubscriptionTier.pro,
          lastPaymentAt: DateTime(2026, 10, 1),
          lastPaymentInr: 7999,
        ),
      ];
    await _pump(tester, source, resortSummary(plan: resortPlan()));

    expect(find.text('Auto-pay: On · Last payment ₹7,999 on 1 Oct 2026'),
        findsOneWidget);
  });

  testWidgets('a halted auto-pay with no payment yet says so', (tester) async {
    final source = FakePlatformSource()
      ..billingList = [
        const PlatformBilling(propertyId: 'p1', status: GatewayStatus.halted),
      ];
    await _pump(tester, source, resortSummary(plan: resortPlan()));

    expect(find.text('Auto-pay: Stopped after failed payments'), findsOneWidget);
  });

  testWidgets('no billing line for a resort that never had auto-pay',
      (tester) async {
    final source = FakePlatformSource()
      ..billingList = [
        const PlatformBilling(propertyId: 'p2', status: GatewayStatus.active),
      ];
    await _pump(tester, source, resortSummary(plan: resortPlan()));

    expect(find.byKey(const Key('resort-billing-p1')), findsNothing);
  });

  testWidgets('a billing load error leaves the card as it was',
      (tester) async {
    final source = FakePlatformSource()..billingError = const NetworkFailure();
    await tester.pumpWidget(ProviderScope(
      retry: (_, _) => null,
      overrides: [platformSourceProvider.overrideWithValue(source)],
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ResortCard(
                resort: resortSummary(plan: resortPlan()), onChanged: () {}),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('resort-billing-p1')), findsNothing);
    expect(find.widgetWithText(TextButton, 'Change plan'), findsOneWidget);
  });


  testWidgets('a pending resort waits for review: no status or plan actions',
      (tester) async {
    await _pump(
        tester,
        FakePlatformSource(),
        resortSummary(
            status: 'pending',
            plan: resortPlan(tier: SubscriptionTier.starter)));

    expect(find.text('Pending review'), findsOneWidget);
    expect(find.byKey(const Key('resort-status-btn-p1')), findsNothing);
    expect(find.byKey(const Key('resort-plan-btn-p1')), findsNothing);
    expect(find.text('Waiting for review: see Pending review above.'),
        findsOneWidget);
  });
}
