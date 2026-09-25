import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/current_resort.dart';
import 'package:pasala/core/errors.dart';
import 'package:pasala/data/models/property.dart';
import 'package:pasala/data/models/resort_membership.dart';
import 'package:pasala/data/models/subscription.dart';
import 'package:pasala/data/repositories/billing_repository.dart';
import 'package:pasala/data/repositories/subscription_repository.dart';
import 'package:pasala/features/browse/providers.dart';
import 'package:pasala/features/owner/location_settings_screen.dart';
import 'package:pasala/features/owner/owner_settings_screen.dart';

import '../../support/fake_billing_source.dart';
import '../../support/fake_platform_source.dart';
import '../../support/fake_resort_plan_source.dart';

const _resort = ResortMembership(
    propertyId: 'p1', resortName: 'Pasala Farm House', role: ResortRole.owner);

const _property = Property(
  id: 'p1',
  name: 'Pasala Farm House',
  slug: 'pasala-farm-house',
  description: null,
  address: null,
  images: [],
  amenities: [],
  checkInTime: '14:00',
  checkOutTime: '11:00',
  isActive: true,
);

/// Pins the current resort, mirroring `_FixedResort` in
/// `team_screen_test.dart`.
class _FixedResort extends CurrentResort {
  _FixedResort(this._value);
  final ResortMembership? _value;
  @override
  ResortMembership? build() => _value;
}

Future<void> _pump(
  WidgetTester tester,
  FakeResortPlanSource source, {
  FakeBillingSource? billing,
  Property property = _property,
}) async {
  await tester.pumpWidget(ProviderScope(
    // retry: null -- without it Riverpod 3 keeps retrying a failed
    // provider and the error state never settles.
    retry: (_, _) => null,
    overrides: [
      currentResortProvider.overrideWith(() => _FixedResort(_resort)),
      propertyProvider.overrideWith((ref, id) async => property),
      resortPlanSourceProvider.overrideWithValue(source),
      billingSourceProvider.overrideWithValue(billing ?? FakeBillingSource()),
    ],
    child: const MaterialApp(home: OwnerSettingsScreen()),
  ));
  await tester.pumpAndSettle();
}

Finder _inPlanTile(String text) => find.descendant(
    of: find.byKey(const Key('owner-plan-tile')), matching: find.text(text));

void main() {
  testWidgets("shows the current resort's plan, read-only", (tester) async {
    final source = FakeResortPlanSource()
      ..plan = resortPlan(
          tier: SubscriptionTier.pro, paidThrough: DateTime(2026, 10, 31));
    await _pump(tester, source);

    expect(_inPlanTile('Plan: Pro'), findsOneWidget);
    expect(_inPlanTile('Paid until 31 Oct 2026'), findsOneWidget);
    expect(source.calls, ['p1']);
    final tile = tester.widget<ListTile>(find.descendant(
        of: find.byKey(const Key('owner-plan-tile')),
        matching: find.byType(ListTile)));
    expect(tile.onTap, isNull);
  });

  testWidgets('a lapsed trial says so', (tester) async {
    final source = FakeResortPlanSource()
      ..plan = resortPlan(
          tier: SubscriptionTier.starter,
          status: SubscriptionStatus.trial,
          trialEndsOn: DateTime(2026, 9, 24),
          lapsed: true);
    await _pump(tester, source);

    expect(_inPlanTile('Plan: Starter'), findsOneWidget);
    expect(_inPlanTile('Lapsed: trial ended 24 Sep 2026'), findsOneWidget);
  });

  testWidgets('a resort with no plan says it is not set up', (tester) async {
    await _pump(tester, FakeResortPlanSource());

    expect(_inPlanTile('Plan: not set up'), findsOneWidget);
    expect(_inPlanTile('Contact ResortHub to choose a plan'), findsOneWidget);
  });

  testWidgets('a plan that fails to load does not break Settings',
      (tester) async {
    final source = FakeResortPlanSource()..error = const NetworkFailure();
    await _pump(tester, source);

    expect(_inPlanTile('Could not load your plan'), findsOneWidget);
    expect(find.text('Farmhouse information'), findsOneWidget);
  });

  testWidgets('the auto-pay card sits under the plan tile when configured',
      (tester) async {
    final source = FakeResortPlanSource()
      ..plan = resortPlan(
          tier: SubscriptionTier.pro, paidThrough: DateTime(2026, 10, 31));
    await _pump(tester, source,
        billing: FakeBillingSource()..availabilityValue = billablePlans);

    expect(find.byKey(const Key('owner-billing-card')), findsOneWidget);
    expect(
        tester.getTopLeft(find.byKey(const Key('owner-billing-card'))).dy,
        greaterThan(
            tester.getTopLeft(find.byKey(const Key('owner-plan-tile'))).dy));
  });

  testWidgets('without Razorpay the Settings screen is unchanged',
      (tester) async {
    await _pump(tester, FakeResortPlanSource()..plan = resortPlan());

    expect(find.byKey(const Key('owner-billing-card')), findsNothing);
    expect(find.text('Farmhouse information'), findsOneWidget);
  });

  testWidgets('Photos opens the photo screen', (tester) async {
    await _pump(tester, FakeResortPlanSource());

    await tester.tap(find.text('Photos'));
    await tester.pumpAndSettle();

    expect(find.text('No photos yet'), findsOneWidget);
    expect(find.text('Add photo'), findsOneWidget);
  });

  testWidgets('Map location says when the resort has no coordinates',
      (tester) async {
    await _pump(tester, FakeResortPlanSource());

    expect(find.text('Map location'), findsOneWidget);
    expect(find.text('Not set. Guests will not see how far away you are.'),
        findsOneWidget);
  });

  testWidgets('Map location shows the saved coordinates and opens the editor',
      (tester) async {
    const located = Property(
      id: 'p1',
      name: 'Pasala Farm House',
      slug: 'pasala-farm-house',
      description: null,
      address: null,
      images: [],
      amenities: [],
      checkInTime: '14:00',
      checkOutTime: '11:00',
      isActive: true,
      latitude: 17.385044,
      longitude: 78.486671,
    );
    await _pump(tester, FakeResortPlanSource(), property: located);

    expect(find.text('17.3850, 78.4867'), findsOneWidget);

    await tester.tap(find.text('Map location'));
    await tester.pumpAndSettle();

    expect(find.byType(LocationSettingsScreen), findsOneWidget);
    expect(find.text('Use my current location'), findsOneWidget);
  });
}
