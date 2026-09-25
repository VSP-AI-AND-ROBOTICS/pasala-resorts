import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/errors.dart';
import 'package:pasala/data/models/billing.dart';
import 'package:pasala/data/models/subscription.dart';
import 'package:pasala/data/repositories/billing_repository.dart';
import 'package:pasala/data/repositories/subscription_repository.dart';
import 'package:pasala/features/owner/manage_subscription_sheet.dart';
import 'package:pasala/features/owner/subscription_billing_card.dart';

import '../../support/fake_billing_source.dart';
import '../../support/fake_platform_source.dart';
import '../../support/fake_resort_plan_source.dart';

/// Pumps the card for resort p1 (a Starter trial by default) and returns
/// the links the card asked to open.
Future<List<Uri>> _pump(
  WidgetTester tester,
  FakeBillingSource billing, {
  bool opens = true,
}) async {
  final opened = <Uri>[];
  final plans = FakeResortPlanSource()
    ..plan = resortPlan(
        tier: SubscriptionTier.starter,
        status: SubscriptionStatus.trial,
        trialEndsOn: DateTime(2026, 10, 5));
  await tester.pumpWidget(ProviderScope(
    retry: (_, _) => null,
    overrides: [
      billingSourceProvider.overrideWithValue(billing),
      resortPlanSourceProvider.overrideWithValue(plans),
      billingLinkOpenerProvider.overrideWithValue((uri) async {
        opened.add(uri);
        return opens;
      }),
    ],
    child: const MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: SubscriptionBillingCard(propertyId: 'p1'),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return opened;
}

FakeBillingSource _configured({ResortBilling? billing}) => FakeBillingSource()
  ..availabilityValue = billablePlans
  ..billingValue = billing;

Future<void> _openSheet(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('billing-manage-btn')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders nothing when auto-pay is not configured',
      (tester) async {
    final billing = FakeBillingSource();
    await _pump(tester, billing);

    expect(find.byKey(const Key('owner-billing-card')), findsNothing);
    expect(billing.availabilityCalls, ['p1']);
    expect(billing.billingCalls, isEmpty);
  });

  testWidgets('renders nothing when no plan has a Razorpay plan id',
      (tester) async {
    await _pump(tester,
        FakeBillingSource()..availabilityValue = const BillingAvailability(configured: true));

    expect(find.byKey(const Key('owner-billing-card')), findsNothing);
  });

  testWidgets('with no auto-pay yet: the state and the button', (tester) async {
    await _pump(tester, _configured());

    expect(find.text('Auto-pay'), findsOneWidget);
    expect(find.text('No auto-pay set up'), findsOneWidget);
    expect(find.byKey(const Key('billing-last-payment')), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Pay / manage subscription'),
        findsOneWidget);
  });

  testWidgets('shows the auto-pay state and the last payment', (tester) async {
    await _pump(tester, _configured(billing: resortBilling()));

    expect(find.text('Auto-pay on · next charge 1 Nov 2026'), findsOneWidget);
    expect(find.text('Last payment ₹7,999 on 1 Oct 2026'), findsOneWidget);
  });

  testWidgets('a billing load error keeps the button', (tester) async {
    await _pump(tester, _configured()..billingError = const NetworkFailure());

    expect(find.text('Could not load auto-pay'), findsOneWidget);
    expect(find.byKey(const Key('billing-manage-btn')), findsOneWidget);
  });

  testWidgets('Refresh asks the server again', (tester) async {
    final billing = _configured();
    await _pump(tester, billing);
    expect(billing.billingCalls, ['p1']);

    await tester.tap(find.byKey(const Key('billing-refresh')));
    await tester.pumpAndSettle();

    expect(billing.billingCalls, ['p1', 'p1']);
  });

  testWidgets(
      'the sheet lists the billable plans with prices, preselects the current '
      'plan, and has no cancel without auto-pay', (tester) async {
    await _pump(tester, _configured());
    await _openSheet(tester);

    expect(find.text('₹2,999 / month'), findsOneWidget);
    expect(find.text('₹7,999 / month'), findsOneWidget);
    expect(
        find.descendant(
            of: find.byKey(const Key('billing-tier-starter')),
            matching: find.byIcon(Icons.radio_button_checked)),
        findsOneWidget);
    expect(find.byKey(const Key('billing-cancel')), findsNothing);
    expect(find.text('No payments yet'), findsOneWidget);
  });

  testWidgets('Continue subscribes to the chosen plan and opens Razorpay',
      (tester) async {
    final billing = _configured();
    final opened = await _pump(tester, billing);
    await _openSheet(tester);

    await tester.tap(find.byKey(const Key('billing-tier-pro')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('billing-continue')));
    await tester.pumpAndSettle();

    expect(billing.subscribeCalls, [('p1', SubscriptionTier.pro)]);
    expect(opened, [Uri.parse('https://rzp.io/i/test')]);
    expect(find.text('Continue to payment'), findsNothing);
    expect(find.text('Finish the payment on the Razorpay page, then tap Refresh.'),
        findsOneWidget);
    expect(billing.billingCalls, ['p1', 'p1']);
  });

  testWidgets('auto-pay already on for that plan: a note, no link',
      (tester) async {
    final billing = _configured(billing: resortBilling())
      ..subscribeResult = const SubscribeResult(
        action: SubscribeAction.unchanged,
        subscriptionId: 'sub_Current000001',
        shortUrl: 'https://rzp.io/i/current',
        status: GatewayStatus.active,
      );
    final opened = await _pump(tester, billing);
    await _openSheet(tester);

    await tester.tap(find.byKey(const Key('billing-continue')));
    await tester.pumpAndSettle();

    expect(billing.subscribeCalls, [('p1', SubscriptionTier.pro)]);
    expect(opened, isEmpty);
    expect(find.text('Auto-pay is already on for Pro.'), findsOneWidget);
  });

  testWidgets('a refusal stays in the sheet with its message', (tester) async {
    await _pump(tester, _configured()..subscribeError = const BillingUnavailable());
    await _openSheet(tester);

    await tester.tap(find.byKey(const Key('billing-continue')));
    await tester.pumpAndSettle();

    expect(
        find.text(
            "Online payment isn't set up for this plan yet. Contact ResortHub."),
        findsOneWidget);
    expect(find.byKey(const Key('billing-continue')), findsOneWidget);
  });

  testWidgets('a link that cannot be opened is reported', (tester) async {
    await _pump(tester, _configured(), opens: false);
    await _openSheet(tester);

    await tester.tap(find.byKey(const Key('billing-continue')));
    await tester.pumpAndSettle();

    expect(find.text('Could not open https://rzp.io/i/test'), findsOneWidget);
  });

  testWidgets('a second tap while subscribing makes no second call',
      (tester) async {
    final billing = _configured()..hold = Completer<void>();
    await _pump(tester, billing);
    await _openSheet(tester);

    await tester.tap(find.byKey(const Key('billing-continue')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('billing-continue')),
        warnIfMissed: false);
    await tester.pump();
    expect(billing.subscribeCalls, hasLength(1));

    billing.hold!.complete();
    await tester.pumpAndSettle();
    expect(billing.subscribeCalls, hasLength(1));
  });

  testWidgets('Cancel auto-pay asks first, then ends auto-pay with the period',
      (tester) async {
    final billing = _configured(billing: resortBilling());
    await _pump(tester, billing);
    await _openSheet(tester);

    await tester.tap(find.byKey(const Key('billing-cancel')));
    await tester.pumpAndSettle();
    expect(find.text('Cancel auto-pay?'), findsOneWidget);
    await tester.tap(find.text('Keep auto-pay'));
    await tester.pumpAndSettle();
    expect(billing.cancelCalls, isEmpty);

    await tester.tap(find.byKey(const Key('billing-cancel')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('billing-cancel-confirm')));
    await tester.pumpAndSettle();

    expect(billing.cancelCalls, ['p1']);
    expect(find.text('Auto-pay will end with the current period.'),
        findsOneWidget);
  });

  testWidgets('no Cancel auto-pay when it is already ending', (tester) async {
    await _pump(tester,
        _configured(billing: resortBilling(cancelAtCycleEnd: true)));
    await _openSheet(tester);

    expect(find.byKey(const Key('billing-cancel')), findsNothing);
  });

  testWidgets('the sheet lists the payments', (tester) async {
    await _pump(tester, _configured()..invoiceList = [subscriptionInvoice()]);
    await _openSheet(tester);

    expect(find.text('1 Oct 2026 · Pro'), findsOneWidget);
    expect(find.text('₹7,999'), findsOneWidget);
  });
}
