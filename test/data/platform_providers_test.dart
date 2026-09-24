import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/data/models/subscription.dart';
import 'package:pasala/data/repositories/platform_repository.dart';
import 'package:pasala/data/repositories/subscription_repository.dart';

import '../support/fake_platform_source.dart';
import '../support/fake_resort_plan_source.dart';

Map<String, dynamic> _row(Map<String, dynamic> plan) => {
  'property_id': 'p1',
  'name': 'Resort A',
  'status': 'active',
  'owner_emails': ['ownera@x.com'],
  'created_at': '2026-01-01T00:00:00+00:00',
  'bookings_30d': 1,
  'revenue_30d': 100,
  'bookings_365d': 2,
  'revenue_365d': 200,
  ...plan,
};

void main() {
  group('ResortSummary.fromJson', () {
    test('reads the plan columns', () {
      final summary = ResortSummary.fromJson(
        _row({
          'plan_tier': 'enterprise',
          'plan_name': 'Enterprise',
          'plan_status': 'active',
          'trial_ends_on': null,
          'paid_through': null,
          'lapsed': false,
          'monthly_price_inr': 19999,
          'plan_notes': null,
        }),
      );

      expect(summary.plan!.tier, SubscriptionTier.enterprise);
      expect(summary.plan!.paidThrough, isNull);
      expect(summary.bookings30d, 1);
    });

    test('a resort with no subscription row has no plan', () {
      final summary = ResortSummary.fromJson(
        _row({
          'plan_tier': null,
          'plan_name': null,
          'plan_status': null,
          'trial_ends_on': null,
          'paid_through': null,
          'lapsed': false,
          'monthly_price_inr': null,
          'plan_notes': null,
        }),
      );

      expect(summary.plan, isNull);
    });
  });

  test('platformTotalsProvider reads the totals through the seam', () async {
    final source = FakePlatformSource()
      ..totalsValue = const PlatformTotals(
        subscribed: 3,
        active: 2,
        trials: 1,
        mrrInr: 7999,
      );
    final container = ProviderContainer(
      overrides: [platformSourceProvider.overrideWithValue(source)],
    );
    addTearDown(container.dispose);

    final totals = await container.read(platformTotalsProvider.future);

    expect(totals.subscribed, 3);
    expect(totals.mrrInr, 7999);
    expect(source.totalsCalls, 1);
  });

  test('subscriptionPlansProvider lists the plans through the seam', () async {
    final source = FakePlatformSource();
    final container = ProviderContainer(
      overrides: [platformSourceProvider.overrideWithValue(source)],
    );
    addTearDown(container.dispose);

    final plans = await container.read(subscriptionPlansProvider.future);

    expect(plans.map((p) => p.tier).toList(), SubscriptionTier.values);
    expect(source.plansCalls, 1);
  });

  test(
    'resortPlanProvider asks for the plan of the resort it is keyed by',
    () async {
      final source = FakeResortPlanSource()
        ..plan = resortPlan(tier: SubscriptionTier.pro);
      final container = ProviderContainer(
        overrides: [resortPlanSourceProvider.overrideWithValue(source)],
      );
      addTearDown(container.dispose);
      final sub = container.listen(resortPlanProvider('p1'), (_, _) {});
      addTearDown(sub.close);

      final plan = await container.read(resortPlanProvider('p1').future);

      expect(plan!.tier, SubscriptionTier.pro);
      expect(source.calls, ['p1']);
    },
  );

  test('resortPlanProvider gives null for a resort with no plan', () async {
    final source = FakeResortPlanSource();
    final container = ProviderContainer(
      overrides: [resortPlanSourceProvider.overrideWithValue(source)],
    );
    addTearDown(container.dispose);
    final sub = container.listen(resortPlanProvider('p2'), (_, _) {});
    addTearDown(sub.close);

    expect(await container.read(resortPlanProvider('p2').future), isNull);
    expect(source.calls, ['p2']);
  });
}
