import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/data/models/subscription.dart';
import 'package:pasala/features/platform/resort_filter.dart';

import '../../support/fake_platform_source.dart';

void main() {
  final a = resortSummary(
      propertyId: 'p1',
      name: 'Resort A',
      ownerEmails: const ['ownera@x.com'],
      plan: resortPlan(tier: SubscriptionTier.pro));
  final b = resortSummary(
      propertyId: 'p2',
      name: 'Resort B',
      ownerEmails: const ['ownerb@x.com', 'co@x.com'],
      plan: resortPlan(tier: SubscriptionTier.starter));
  final none = resortSummary(
      propertyId: 'p3', name: 'Hill Stay', ownerEmails: const []);
  final all = [a, b, none];

  test('an empty or blank query with All tiers keeps everything, in order',
      () {
    expect(filterResorts(all), all);
    expect(filterResorts(all, query: '   '), all);
  });

  test('the query ignores case and surrounding spaces', () {
    expect(filterResorts(all, query: '  RESORT a '), [a]);
  });

  test('the query matches any owner email', () {
    expect(filterResorts(all, query: 'CO@X'), [b]);
  });

  test('a tier hides other tiers and resorts with no plan', () {
    expect(filterResorts(all, tier: SubscriptionTier.pro), [a]);
    expect(filterResorts(all, tier: SubscriptionTier.enterprise), isEmpty);
  });

  test('the query and the tier combine', () {
    expect(
        filterResorts(all, query: 'resort', tier: SubscriptionTier.starter),
        [b]);
  });
}
