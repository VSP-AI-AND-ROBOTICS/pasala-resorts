import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/data/models/subscription.dart';

ResortPlan _plan({
  SubscriptionTier tier = SubscriptionTier.pro,
  SubscriptionStatus status = SubscriptionStatus.active,
  DateTime? trialEndsOn,
  DateTime? paidThrough,
  bool lapsed = false,
}) => ResortPlan(
  tier: tier,
  name: tier.label,
  status: status,
  trialEndsOn: trialEndsOn,
  paidThrough: paidThrough,
  lapsed: lapsed,
  monthlyPriceInr: 7999,
);

void main() {
  group('tiers and statuses', () {
    test('every tier round-trips through its database label', () {
      for (final tier in SubscriptionTier.values) {
        expect(subscriptionTierFromDb(subscriptionTierToDb(tier)), tier);
      }
    });

    test('every status round-trips through its database label', () {
      for (final status in SubscriptionStatus.values) {
        expect(
          subscriptionStatusFromDb(subscriptionStatusToDb(status)),
          status,
        );
      }
    });

    test('unknown labels are rejected, not defaulted', () {
      expect(() => subscriptionTierFromDb('free'), throwsArgumentError);
      expect(() => subscriptionStatusFromDb('lapsed'), throwsArgumentError);
    });

    test('labels', () {
      expect(SubscriptionTier.values.map((t) => t.label).toList(), [
        'Starter',
        'Pro',
        'Enterprise',
      ]);
      expect(SubscriptionStatus.values.map((s) => s.label).toList(), [
        'Trial',
        'Active',
        'Cancelled',
      ]);
    });
  });

  group('ResortPlan.fromRow', () {
    test('parses the plan columns of a platform_resorts row', () {
      final plan = ResortPlan.fromRow(const {
        'plan_tier': 'pro',
        'plan_name': 'Pro',
        'plan_status': 'active',
        'trial_ends_on': null,
        'paid_through': '2026-10-31',
        'lapsed': false,
        'monthly_price_inr': 7999,
        'plan_notes': 'Invoice 12',
      })!;

      expect(plan.tier, SubscriptionTier.pro);
      expect(plan.name, 'Pro');
      expect(plan.status, SubscriptionStatus.active);
      expect(plan.trialEndsOn, isNull);
      expect(plan.paidThrough, DateTime(2026, 10, 31));
      expect(plan.lapsed, isFalse);
      expect(plan.monthlyPriceInr, 7999);
      expect(plan.notes, 'Invoice 12');
    });

    test('parses a lapsed trial', () {
      final plan = ResortPlan.fromRow(const {
        'plan_tier': 'starter',
        'plan_name': 'Starter',
        'plan_status': 'trial',
        'trial_ends_on': '2026-09-24',
        'paid_through': null,
        'lapsed': true,
        'monthly_price_inr': 2999,
        'plan_notes': null,
      })!;

      expect(plan.status, SubscriptionStatus.trial);
      expect(plan.trialEndsOn, DateTime(2026, 9, 24));
      expect(plan.lapsed, isTrue);
    });

    test('a row with no plan_tier has no plan', () {
      expect(
        ResortPlan.fromRow(const {
          'plan_tier': null,
          'plan_name': null,
          'plan_status': null,
          'lapsed': false,
        }),
        isNull,
      );
    });

    test('a price sent as text still parses', () {
      final plan = ResortPlan.fromRow(const {
        'plan_tier': 'starter',
        'plan_name': 'Starter',
        'plan_status': 'active',
        'lapsed': false,
        'monthly_price_inr': '2999.00',
      })!;
      expect(plan.monthlyPriceInr, 2999);
    });
  });

  test('SubscriptionPlan.fromJson reads a subscription_plans row', () {
    final plan = SubscriptionPlan.fromJson(const {
      'tier': 'enterprise',
      'name': 'Enterprise',
      'monthly_price_inr': 19999,
      'sort_order': 3,
    });
    expect(plan.tier, SubscriptionTier.enterprise);
    expect(plan.name, 'Enterprise');
    expect(plan.monthlyPriceInr, 19999);
    expect(plan.sortOrder, 3);
  });

  test('PlatformTotals.fromJson reads a platform_summary row', () {
    final totals = PlatformTotals.fromJson(const {
      'subscribed_count': 21,
      'active_count': 19,
      'trial_count': 2,
      'mrr_inr': 123456.5,
    });
    expect(totals.subscribed, 21);
    expect(totals.active, 19);
    expect(totals.trials, 2);
    expect(totals.mrrInr, 123456.5);
  });

  group('planStatusLine', () {
    test('a live trial', () {
      expect(
        planStatusLine(
          _plan(
            status: SubscriptionStatus.trial,
            trialEndsOn: DateTime(2026, 10, 24),
          ),
        ),
        'Trial until 24 Oct 2026',
      );
    });

    test('a lapsed trial', () {
      expect(
        planStatusLine(
          _plan(
            status: SubscriptionStatus.trial,
            trialEndsOn: DateTime(2026, 10, 24),
            lapsed: true,
          ),
        ),
        'Lapsed: trial ended 24 Oct 2026',
      );
    });

    test('paid until a date, including the date itself', () {
      expect(
        planStatusLine(_plan(paidThrough: DateTime(2026, 10, 31))),
        'Paid until 31 Oct 2026',
      );
    });

    test('a lapsed paid plan', () {
      expect(
        planStatusLine(_plan(paidThrough: DateTime(2026, 9, 30), lapsed: true)),
        'Lapsed: paid until 30 Sep 2026',
      );
    });

    test('paid with no end date', () {
      expect(planStatusLine(_plan()), 'Paid, no end date');
    });

    test('cancelled, whatever the dates', () {
      expect(
        planStatusLine(
          _plan(
            status: SubscriptionStatus.cancelled,
            paidThrough: DateTime(2026, 9, 30),
          ),
        ),
        'Cancelled',
      );
    });
  });

  test('dateToDb sends only the calendar day', () {
    expect(dateToDb(DateTime(2026, 10, 5, 23, 59)), '2026-10-05');
    expect(dateToDb(DateTime.utc(2026, 1, 9)), '2026-01-09');
  });
}
