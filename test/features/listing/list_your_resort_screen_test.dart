import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pasala/core/current_resort.dart';
import 'package:pasala/core/errors.dart';
import 'package:pasala/data/models/app_user.dart';
import 'package:pasala/data/models/listing.dart';
import 'package:pasala/data/models/resort_membership.dart';
import 'package:pasala/data/models/subscription.dart';
import 'package:pasala/data/repositories/auth_repository.dart';
import 'package:pasala/data/repositories/listing_repository.dart';
import 'package:pasala/data/repositories/platform_repository.dart';
import 'package:pasala/features/listing/list_your_resort_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_listing_source.dart';
import '../../support/fake_platform_source.dart';

class _NoResort extends CurrentResort {
  @override
  ResortMembership? build() => null;
}

const _customer = AppUser(id: 'c1', email: 'asha@example.com');

Future<void> _pump(
  WidgetTester tester,
  FakeListingSource source, {
  Object? plansError,
}) async {
  tester.view.physicalSize = const Size(900, 2200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final router = GoRouter(
    initialLocation: '/list-your-resort',
    routes: [
      GoRoute(
        path: '/list-your-resort',
        builder: (_, _) => const ListYourResortScreen(),
      ),
      GoRoute(path: '/owner', builder: (_, _) => const Text('Owner hub')),
    ],
  );
  await tester.pumpWidget(ProviderScope(
    retry: (_, _) => null,
    overrides: [
      listingSourceProvider.overrideWithValue(source),
      subscriptionPlansProvider.overrideWith((ref) async {
        if (plansError != null) throw plansError;
        return defaultPlans;
      }),
      currentUserProvider.overrideWith((ref) => Stream.value(_customer)),
      currentResortProvider.overrideWith(_NoResort.new),
    ],
    child: MaterialApp.router(routerConfig: router),
  ));
  await tester.pumpAndSettle();
}

Future<void> _fillValidForm(WidgetTester tester) async {
  await tester.enterText(find.byKey(const Key('listing-name')), ' Green Acres ');
  await tester.enterText(find.byKey(const Key('listing-city')), 'Nashik');
  await tester.enterText(
      find.byKey(const Key('listing-address')), '12 Vineyard Road, Nashik');
  await tester.enterText(
      find.byKey(const Key('listing-phone')), '+91 98765 43210');
  await tester.enterText(find.byKey(const Key('listing-description')),
      'Vineyard cottages with a pool and a view.');
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('with no application it shows the form and the plan price',
      (tester) async {
    await _pump(tester, FakeListingSource());

    expect(find.text('Resort name'), findsOneWidget);
    expect(find.text('Contact phone'), findsOneWidget);
    expect(find.text('Starter — ₹2,999/month'), findsOneWidget);
    expect(find.text('30-day free trial. No payment needed now.'),
        findsOneWidget);
    expect(find.text('Earlier applications'), findsNothing);
  });

  testWidgets('if the prices fail to load, the plan still shows its name',
      (tester) async {
    await _pump(tester, FakeListingSource(), plansError: const NetworkFailure());

    expect(find.text('Starter'), findsOneWidget);
  });

  testWidgets('an empty form shows every rule and sends nothing',
      (tester) async {
    final source = FakeListingSource();
    await _pump(tester, source);

    await tester.tap(find.byKey(const Key('listing-submit')));
    await tester.pumpAndSettle();

    expect(find.text('Enter the resort name (2 to 80 characters).'),
        findsOneWidget);
    expect(find.text('Enter the city (2 to 60 characters).'), findsOneWidget);
    expect(find.text('Enter the full address (5 to 300 characters).'),
        findsOneWidget);
    expect(find.text('Enter a contact phone number, e.g. +91 98765 43210.'),
        findsOneWidget);
    expect(find.text('Describe the resort in 20 to 500 characters.'),
        findsOneWidget);
    expect(source.applyCalls, isEmpty);
  });

  testWidgets('a valid form applies with the chosen plan and opens the owner hub',
      (tester) async {
    final source = FakeListingSource();
    await _pump(tester, source);

    await _fillValidForm(tester);
    await tester.tap(find.byKey(const Key('listing-tier')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pro — ₹7,999/month').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('listing-submit')));
    await tester.pumpAndSettle();

    final input = source.applyCalls.single;
    expect(input.name, ' Green Acres ');
    expect(input.contactPhone, '+91 98765 43210');
    expect(input.tier, SubscriptionTier.pro);
    expect(find.text('Owner hub'), findsOneWidget);
  });

  testWidgets('a double tap sends one application', (tester) async {
    final source = FakeListingSource()..applyGate = Completer<void>();
    await _pump(tester, source);

    await _fillValidForm(tester);
    await tester.tap(find.byKey(const Key('listing-submit')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('listing-submit')));
    await tester.pump();

    expect(source.applyCalls, hasLength(1));
    source.applyGate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Owner hub'), findsOneWidget);
  });

  testWidgets('a refusal from the server is shown as written', (tester) async {
    final source = FakeListingSource()
      ..applyError =
          const ListingBlocked('You already have a resort waiting for review.');
    await _pump(tester, source);

    await _fillValidForm(tester);
    await tester.tap(find.byKey(const Key('listing-submit')));
    await tester.pumpAndSettle();

    expect(find.text('You already have a resort waiting for review.'),
        findsOneWidget);
    expect(find.byKey(const Key('listing-name')), findsOneWidget);
  });

  testWidgets('an open application replaces the form with Continue setup',
      (tester) async {
    final source = FakeListingSource()
      ..applications = [
        listingApplication(submittedAt: DateTime.utc(2026, 9, 20, 12)),
      ];
    await _pump(tester, source);

    expect(find.byKey(const Key('listing-open')), findsOneWidget);
    expect(find.text('Waiting for review since 20 Sep 2026'), findsOneWidget);
    expect(find.byKey(const Key('listing-name')), findsNothing);

    await tester.tap(find.byKey(const Key('listing-continue')));
    await tester.pumpAndSettle();

    expect(find.text('Owner hub'), findsOneWidget);
  });

  testWidgets('a rejected application shows its reason above a fresh form',
      (tester) async {
    final source = FakeListingSource()
      ..applications = [
        listingApplication(
          propertyId: 'old',
          propertyStatus: 'archived',
          decision: ListingDecision.rejected,
          rejectionReason: 'Photos do not match the address.',
        ),
      ];
    await _pump(tester, source);

    expect(find.text('Earlier applications'), findsOneWidget);
    expect(find.text('Not approved: Photos do not match the address.'),
        findsOneWidget);
    expect(find.byKey(const Key('listing-name')), findsOneWidget);
  });

  testWidgets('a failed load offers Retry', (tester) async {
    final source = FakeListingSource()..applicationsError = const NetworkFailure();
    await _pump(tester, source);

    expect(find.text('Cannot reach the server. Check your connection.'),
        findsOneWidget);
    source.applicationsError = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('listing-name')), findsOneWidget);
  });
}
