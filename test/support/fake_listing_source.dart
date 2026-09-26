import 'dart:async';

import 'package:pasala/data/models/listing.dart';
import 'package:pasala/data/models/subscription.dart';
import 'package:pasala/data/repositories/listing_repository.dart';

final allSetupSteps = SetupStep.values.toSet();

/// A checklist for tests: [done] lists the finished steps.
ListingSetup listingSetup({
  String status = 'pending',
  DateTime? submittedAt,
  Set<SetupStep> done = const {},
}) => ListingSetup(
  propertyStatus: status,
  submittedAt: submittedAt,
  done: {for (final s in SetupStep.values) s: done.contains(s)},
);

/// An application for tests, still being set up unless told otherwise.
ListingApplication listingApplication({
  String propertyId = 'r1',
  String name = 'Green Acres',
  String city = 'Nashik',
  SubscriptionTier tier = SubscriptionTier.starter,
  String propertyStatus = 'pending',
  DateTime? submittedAt,
  ListingDecision? decision,
  String? rejectionReason,
}) => ListingApplication(
  propertyId: propertyId,
  name: name,
  city: city,
  tier: tier,
  propertyStatus: propertyStatus,
  createdAt: DateTime.utc(2026, 9, 19, 10),
  submittedAt: submittedAt,
  decision: decision,
  decidedAt: decision == null ? null : DateTime.utc(2026, 9, 24, 10),
  rejectionReason: rejectionReason,
);

/// A console row for tests: complete checklist unless [done] says
/// otherwise, not submitted unless [submittedAt] is given.
PendingListing pendingListing({
  String propertyId = 'r1',
  String name = 'Green Acres',
  String city = 'Nashik',
  String applicantEmail = 'asha@example.com',
  String? applicantName = 'Asha Applicant',
  SubscriptionTier tier = SubscriptionTier.pro,
  DateTime? submittedAt,
  Set<SetupStep>? done,
}) => PendingListing(
  propertyId: propertyId,
  name: name,
  city: city,
  address: '12 Vineyard Road, Nashik',
  contactPhone: '+919876543210',
  description: 'Vineyard cottages with a pool and a view.',
  applicantEmail: applicantEmail,
  applicantName: applicantName,
  tier: tier,
  createdAt: DateTime.utc(2026, 9, 19, 10),
  submittedAt: submittedAt,
  setup: {
    for (final s in SetupStep.values) s: (done ?? allSetupSteps).contains(s),
  },
);

/// In-memory [ListingSource]. Set [applications] / [setup] for what the
/// server would return, an `...Error` to make that call throw, and read
/// the call logs. While [applyGate] is set, `apply` waits for it, so a
/// test can tap twice during one call.
class FakeListingSource implements ListingSource {
  List<ListingApplication> applications = [];
  ListingSetup setup = listingSetup();
  String appliedId = 'new-resort';
  Completer<void>? applyGate;
  Object? applyError;
  Object? applicationsError;
  Object? setupError;
  Object? submitError;

  final List<ListingInput> applyCalls = [];
  final List<String> setupCalls = [];
  final List<String> submitCalls = [];
  int applicationsCalls = 0;

  @override
  Future<String> apply(ListingInput input) async {
    applyCalls.add(input);
    if (applyGate != null) await applyGate!.future;
    if (applyError != null) throw applyError!;
    return appliedId;
  }

  @override
  Future<List<ListingApplication>> myApplications() async {
    applicationsCalls++;
    if (applicationsError != null) throw applicationsError!;
    return applications;
  }

  @override
  Future<ListingSetup> setupStatus(String propertyId) async {
    setupCalls.add(propertyId);
    if (setupError != null) throw setupError!;
    return setup;
  }

  @override
  Future<void> submitForReview(String propertyId) async {
    submitCalls.add(propertyId);
    if (submitError != null) throw submitError!;
    setup = ListingSetup(
      propertyStatus: setup.propertyStatus,
      done: setup.done,
      submittedAt: DateTime.utc(2026, 9, 25, 12),
    );
  }
}

/// In-memory [ListingReviewSource]. A decision removes the row from
/// [pending], so a refetch shows it gone.
class FakeListingReviewSource implements ListingReviewSource {
  List<PendingListing> pending = [];
  Object? pendingError;
  Object? approveError;
  Object? rejectError;

  final List<String> approveCalls = [];
  final List<(String, String)> rejectCalls = [];
  int pendingCalls = 0;

  @override
  Future<List<PendingListing>> pendingListings() async {
    pendingCalls++;
    if (pendingError != null) throw pendingError!;
    return pending;
  }

  @override
  Future<void> approve(String propertyId) async {
    approveCalls.add(propertyId);
    if (approveError != null) throw approveError!;
    pending = [
      for (final p in pending)
        if (p.propertyId != propertyId) p,
    ];
  }

  @override
  Future<void> reject(String propertyId, String reason) async {
    rejectCalls.add((propertyId, reason));
    if (rejectError != null) throw rejectError!;
    pending = [
      for (final p in pending)
        if (p.propertyId != propertyId) p,
    ];
  }
}
