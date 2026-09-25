import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/errors.dart';
import 'package:pasala/data/models/listing.dart';
import 'package:pasala/data/models/subscription.dart';
import 'package:pasala/data/repositories/listing_repository.dart';
import 'package:pasala/features/platform/pending_listings.dart';

import '../../support/fake_listing_source.dart';

Future<int Function()> _pump(
  WidgetTester tester,
  FakeListingReviewSource source,
  PendingListing listing,
) async {
  tester.view.physicalSize = const Size(900, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  var changed = 0;
  await tester.pumpWidget(ProviderScope(
    overrides: [listingReviewSourceProvider.overrideWithValue(source)],
    child: MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: PendingListingCard(
            listing: listing,
            onChanged: () => changed++,
          ),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return () => changed;
}

final _submitted = DateTime.utc(2026, 9, 20, 12);

void main() {
  testWidgets('shows the applicant, the contact details and the checklist',
      (tester) async {
    await _pump(
        tester,
        FakeListingReviewSource(),
        pendingListing(
            submittedAt: _submitted,
            done: {SetupStep.photos, SetupStep.units}));

    expect(find.text('Green Acres'), findsOneWidget);
    expect(find.text('Asha Applicant · asha@example.com'), findsOneWidget);
    expect(find.text('+919876543210'), findsOneWidget);
    expect(find.text('Submitted 20 Sep 2026'), findsOneWidget);
    expect(
        find.descendant(
            of: find.byKey(const Key('pending-step-r1-photos')),
            matching: find.byIcon(Icons.check)),
        findsOneWidget);
    expect(
        find.descendant(
            of: find.byKey(const Key('pending-step-r1-tax')),
            matching: find.byIcon(Icons.close)),
        findsOneWidget);
  });

  testWidgets('Approve is off until the application is submitted and complete',
      (tester) async {
    await _pump(tester, FakeListingReviewSource(), pendingListing());

    expect(find.text('Setting up — not submitted yet'), findsOneWidget);
    expect(
        tester
            .widget<ButtonStyleButton>(find.byKey(const Key('approve-r1')))
            .onPressed,
        isNull);
  });

  testWidgets('an incomplete checklist cannot be approved either',
      (tester) async {
    await _pump(tester, FakeListingReviewSource(),
        pendingListing(submittedAt: _submitted, done: {SetupStep.photos}));

    expect(
        tester
            .widget<ButtonStyleButton>(find.byKey(const Key('approve-r1')))
            .onPressed,
        isNull);
  });

  testWidgets('Approve asks first, then approves', (tester) async {
    final source = FakeListingReviewSource();
    final changed =
        await _pump(tester, source, pendingListing(submittedAt: _submitted));

    await tester.tap(find.byKey(const Key('approve-r1')));
    await tester.pumpAndSettle();
    expect(find.text('Approve Green Acres?'), findsOneWidget);
    expect(find.text('It goes live for guests now.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('approve-confirm')));
    await tester.pumpAndSettle();

    expect(source.approveCalls, ['r1']);
    expect(changed(), 1);
  });

  testWidgets('Cancel in the approve dialog does nothing', (tester) async {
    final source = FakeListingReviewSource();
    final changed =
        await _pump(tester, source, pendingListing(submittedAt: _submitted));

    await tester.tap(find.byKey(const Key('approve-r1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(source.approveCalls, isEmpty);
    expect(changed(), 0);
  });

  testWidgets('a refused approval is shown as written', (tester) async {
    final source = FakeListingReviewSource()
      ..approveError =
          const ListingBlocked('The setup checklist is no longer complete.');
    final changed =
        await _pump(tester, source, pendingListing(submittedAt: _submitted));

    await tester.tap(find.byKey(const Key('approve-r1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('approve-confirm')));
    await tester.pumpAndSettle();

    expect(find.text('The setup checklist is no longer complete.'),
        findsOneWidget);
    expect(changed(), 0);
  });

  testWidgets('Reject needs a reason and sends it trimmed', (tester) async {
    final source = FakeListingReviewSource();
    final changed = await _pump(tester, source, pendingListing());

    await tester.tap(find.byKey(const Key('reject-r1')));
    await tester.pumpAndSettle();
    expect(find.text('Reject Green Acres?'), findsOneWidget);

    await tester.tap(find.byKey(const Key('reject-confirm')));
    await tester.pumpAndSettle();
    expect(find.text('Give the owner a reason (5 to 500 characters).'),
        findsOneWidget);
    expect(source.rejectCalls, isEmpty);

    await tester.enterText(find.byKey(const Key('reject-reason')),
        '  Photos do not match the address.  ');
    await tester.tap(find.byKey(const Key('reject-confirm')));
    await tester.pumpAndSettle();

    expect(source.rejectCalls, [('r1', 'Photos do not match the address.')]);
    expect(changed(), 1);
    expect(find.text('Reject Green Acres?'), findsNothing);
  });

  test('filterPendingListings matches name, city and applicant email', () {
    final pending = [
      pendingListing(propertyId: 'r1'),
      pendingListing(
          propertyId: 'r2',
          name: 'Hill View',
          city: 'Pune',
          applicantEmail: 'ravi@example.com',
          tier: SubscriptionTier.starter),
    ];

    List<String> ids(List<PendingListing> l) =>
        l.map((p) => p.propertyId).toList();
    expect(ids(filterPendingListings(pending, query: '  PUNE ')), ['r2']);
    expect(ids(filterPendingListings(pending, query: 'asha@')), ['r1']);
    expect(ids(filterPendingListings(pending, query: 'green')), ['r1']);
    expect(ids(filterPendingListings(pending, tier: SubscriptionTier.starter)),
        ['r2']);
    expect(ids(filterPendingListings(pending)), ['r1', 'r2']);
  });
}
