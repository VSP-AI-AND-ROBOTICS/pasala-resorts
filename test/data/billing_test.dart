import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/data/models/billing.dart';
import 'package:pasala/data/models/subscription.dart';

void main() {
  group('GatewayStatus', () {
    test('every Razorpay state is read, and unknown text is rejected', () {
      for (final s in GatewayStatus.values) {
        expect(gatewayStatusFromDb(s.name), s);
      }
      expect(() => gatewayStatusFromDb('lapsed'), throwsArgumentError);
    });

    test('labels for the console', () {
      expect(GatewayStatus.active.label, 'On');
      expect(GatewayStatus.created.label, 'Waiting for authorisation');
      expect(GatewayStatus.halted.label, 'Stopped after failed payments');
    });
  });

  group('ResortBilling.fromRow', () {
    test('reads my_resort_billing', () {
      final b = ResortBilling.fromRow({
        'billing_status': 'active',
        'billing_tier': 'pro',
        'short_url': 'https://rzp.io/i/abc',
        'cancel_at_cycle_end': false,
        'current_end': '2026-11-01T00:00:00+05:30',
        'last_payment_at': '2026-10-01T09:30:00+00:00',
        'last_payment_inr': 7999,
      });
      expect(b.status, GatewayStatus.active);
      expect(b.tier, SubscriptionTier.pro);
      expect(b.shortUrl, 'https://rzp.io/i/abc');
      expect(b.currentEnd!.toUtc(), DateTime.utc(2026, 10, 31, 18, 30));
      expect(b.lastPaymentAt!.toUtc(), DateTime.utc(2026, 10, 1, 9, 30));
      expect(b.lastPaymentInr, 7999);
      expect(b.canCancel, isTrue);
    });

    test('a resort with only past payments has no status', () {
      final b = ResortBilling.fromRow({
        'billing_status': null,
        'billing_tier': null,
        'short_url': null,
        'cancel_at_cycle_end': null,
        'current_end': null,
        'last_payment_at': '2026-10-01T09:30:00+00:00',
        'last_payment_inr': '2999.00',
      });
      expect(b.status, isNull);
      expect(b.cancelAtCycleEnd, isFalse);
      expect(b.lastPaymentInr, 2999);
      expect(b.canCancel, isFalse);
    });

    test('a pending cancel cannot be cancelled again', () {
      const b = ResortBilling(
        status: GatewayStatus.active,
        cancelAtCycleEnd: true,
      );
      expect(b.canCancel, isFalse);
    });
  });

  test('PlatformBilling.fromRow reads platform_billing', () {
    final b = PlatformBilling.fromRow({
      'property_id': 'p1',
      'billing_status': 'halted',
      'billing_tier': 'starter',
      'last_payment_at': null,
      'last_payment_inr': null,
    });
    expect(b.propertyId, 'p1');
    expect(b.status, GatewayStatus.halted);
    expect(b.tier, SubscriptionTier.starter);
    expect(b.lastPaymentInr, isNull);
  });

  test('SubscriptionInvoice.fromJson reads a subscription_invoices row', () {
    final i = SubscriptionInvoice.fromJson({
      'id': 'i1',
      'tier': 'pro',
      'amount_inr': 7999,
      'paid_at': '2026-10-01T09:30:00+00:00',
      'period_start': '2026-10-01',
      'period_end': '2026-10-31',
    });
    expect(i.tier, SubscriptionTier.pro);
    expect(i.amountInr, 7999);
    expect(i.periodStart, DateTime(2026, 10, 1));
    expect(i.periodEnd, DateTime(2026, 10, 31));
  });

  group('BillingAvailability.fromJson', () {
    test('not configured', () {
      final a = BillingAvailability.fromJson({'configured': false});
      expect(a.configured, isFalse);
      expect(a.canPay, isFalse);
    });

    test('configured, with the billable plans in order', () {
      final a = BillingAvailability.fromJson({
        'configured': true,
        'plans': [
          {'tier': 'starter', 'name': 'Starter', 'monthly_price_inr': 2999},
          {'tier': 'pro', 'name': 'Pro', 'monthly_price_inr': '7999.00'},
        ],
      });
      expect(a.canPay, isTrue);
      expect(a.plans.map((p) => p.tier), [
        SubscriptionTier.starter,
        SubscriptionTier.pro,
      ]);
      expect(a.plans[1].monthlyPriceInr, 7999);
      expect(a.plans[1].sortOrder, 2);
    });

    test('configured but no tier has a plan id: nothing to pay', () {
      final a = BillingAvailability.fromJson({'configured': true, 'plans': []});
      expect(a.configured, isTrue);
      expect(a.canPay, isFalse);
    });
  });

  test('SubscribeResult.fromJson and cancelActionFromWire', () {
    final r = SubscribeResult.fromJson({
      'configured': true,
      'action': 'reused',
      'subscription_id': 'sub_Abc123456789',
      'short_url': 'https://rzp.io/i/abc',
      'status': 'created',
    });
    expect(r.action, SubscribeAction.reused);
    expect(r.shortUrl, 'https://rzp.io/i/abc');
    expect(r.status, GatewayStatus.created);
    expect(r.warning, isNull);
    expect(
      cancelActionFromWire('cancel_scheduled'),
      CancelAction.cancelScheduled,
    );
    expect(cancelActionFromWire('cancelled'), CancelAction.cancelled);
    expect(cancelActionFromWire('none'), CancelAction.none);
    expect(() => cancelActionFromWire('later'), throwsArgumentError);
  });

  group('billingStatusLine', () {
    test('every state reads as words', () {
      String line(GatewayStatus? s, {bool cancel = false, DateTime? end}) =>
          billingStatusLine(
            ResortBilling(status: s, cancelAtCycleEnd: cancel, currentEnd: end),
          );
      final nov1 = DateTime(2026, 11, 1);
      expect(line(null), 'No auto-pay set up');
      expect(
        line(GatewayStatus.created),
        'Waiting for you to authorise auto-pay',
      );
      expect(
        line(GatewayStatus.authenticated),
        'Auto-pay authorised · first charge when your current period ends',
      );
      expect(
        line(GatewayStatus.active, end: nov1),
        'Auto-pay on · next charge 1 Nov 2026',
      );
      expect(line(GatewayStatus.active), 'Auto-pay on');
      expect(
        line(GatewayStatus.active, cancel: true, end: nov1),
        'Auto-pay ends on 1 Nov 2026',
      );
      expect(
        line(GatewayStatus.active, cancel: true),
        'Auto-pay ends with this period',
      );
      expect(
        line(GatewayStatus.pending),
        'A payment failed · Razorpay is retrying',
      );
      expect(
        line(GatewayStatus.halted),
        'Auto-pay stopped after failed payments',
      );
      expect(line(GatewayStatus.cancelled), 'Auto-pay cancelled');
      expect(line(GatewayStatus.completed), 'Auto-pay finished');
      expect(line(GatewayStatus.expired), 'The auto-pay link expired');
      expect(line(GatewayStatus.paused), 'Auto-pay paused');
    });

    test('lastPaymentLine needs both an amount and a date', () {
      expect(
        lastPaymentLine(7999, DateTime(2026, 10, 1)),
        'Last payment ₹7,999 on 1 Oct 2026',
      );
      expect(lastPaymentLine(null, DateTime(2026, 10, 1)), isNull);
      expect(lastPaymentLine(7999, null), isNull);
    });
  });

  test('SubscriptionPlan reads its Razorpay plan id', () {
    final plan = SubscriptionPlan.fromJson({
      'tier': 'pro',
      'name': 'Pro',
      'monthly_price_inr': 7999,
      'sort_order': 2,
      'razorpay_plan_id': 'plan_ProMonthly0001',
    });
    expect(plan.razorpayPlanId, 'plan_ProMonthly0001');
    expect(
      SubscriptionPlan.fromJson({
        'tier': 'pro',
        'name': 'Pro',
        'monthly_price_inr': 7999,
        'sort_order': 2,
      }).razorpayPlanId,
      isNull,
    );
  });
}
