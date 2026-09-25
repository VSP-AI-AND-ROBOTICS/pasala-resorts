import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors.dart';
import '../../core/supabase_client.dart';
import '../models/listing.dart';
import '../models/subscription.dart';

/// What an applicant and a pending resort's owner need
/// (0059_resort_self_listing.sql). Tests override [listingSourceProvider]
/// with `FakeListingSource` (test/support/fake_listing_source.dart).
abstract class ListingSource {
  /// Creates the pending resort and returns its id. P0040
  /// ([ListingBlocked]) when the user already has an open application.
  Future<String> apply(ListingInput input);

  /// The signed-in user's applications, newest first, decided ones too.
  Future<List<ListingApplication>> myApplications();

  /// The checklist of [propertyId] (owner or admin; P0020 otherwise).
  Future<ListingSetup> setupStatus(String propertyId);

  /// Owner only. P0040 when the checklist is not complete.
  Future<void> submitForReview(String propertyId);
}

/// What the platform console needs. Tests override
/// [listingReviewSourceProvider] with `FakeListingReviewSource`.
abstract class ListingReviewSource {
  /// Undecided applications, submitted ones first.
  Future<List<PendingListing>> pendingListings();

  Future<void> approve(String propertyId);

  Future<void> reject(String propertyId, String reason);
}

class ListingRepository implements ListingSource, ListingReviewSource {
  ListingRepository(this._db);
  final SupabaseClient _db;

  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } catch (e) {
      throw mapPostgrestError(e);
    }
  }

  @override
  Future<String> apply(ListingInput input) => _guard(() async {
    final id = await _db.rpc(
      'apply_for_listing',
      params: {
        'p_name': input.name.trim(),
        'p_city': input.city.trim(),
        'p_address': input.address.trim(),
        'p_contact_phone': input.contactPhone.trim(),
        'p_description': input.description.trim(),
        'p_tier': subscriptionTierToDb(input.tier),
      },
    );
    return id as String;
  });

  @override
  Future<List<ListingApplication>> myApplications() => _guard(() async {
    final rows = await _db.rpc('my_listing_applications') as List<dynamic>;
    return rows
        .map((e) => ListingApplication.fromJson(e as Map<String, dynamic>))
        .toList();
  });

  @override
  Future<ListingSetup> setupStatus(String propertyId) => _guard(() async {
    final rows =
        await _db.rpc(
              'listing_setup_status',
              params: {'p_property': propertyId},
            )
            as List<dynamic>;
    if (rows.isEmpty) throw const NotFound();
    return ListingSetup.fromJson(rows.first as Map<String, dynamic>);
  });

  @override
  Future<void> submitForReview(String propertyId) => _guard(() async {
    await _db.rpc(
      'submit_listing_for_review',
      params: {'p_property': propertyId},
    );
  });

  @override
  Future<List<PendingListing>> pendingListings() => _guard(() async {
    final rows =
        await _db.rpc('platform_listing_applications') as List<dynamic>;
    return rows
        .map((e) => PendingListing.fromJson(e as Map<String, dynamic>))
        .toList();
  });

  @override
  Future<void> approve(String propertyId) => _guard(() async {
    await _db.rpc('approve_listing', params: {'p_property': propertyId});
  });

  @override
  Future<void> reject(String propertyId, String reason) => _guard(() async {
    await _db.rpc(
      'reject_listing',
      params: {'p_property': propertyId, 'p_reason': reason.trim()},
    );
  });
}

final listingRepositoryProvider = Provider<ListingRepository>(
  (ref) => ListingRepository(ref.watch(supabaseProvider)),
);

final listingSourceProvider = Provider<ListingSource>(
  (ref) => ref.watch(listingRepositoryProvider),
);

final listingReviewSourceProvider = Provider<ListingReviewSource>(
  (ref) => ref.watch(listingRepositoryProvider),
);

/// `autoDispose`: the "List your resort" page refetches on every visit, so
/// a decision made meanwhile shows up.
final myListingApplicationsProvider =
    FutureProvider.autoDispose<List<ListingApplication>>(
      (ref) => ref.watch(listingSourceProvider).myApplications(),
    );

/// Keyed by property id so switching resort never shows another resort's
/// checklist.
final listingSetupProvider = FutureProvider.autoDispose
    .family<ListingSetup, String>(
      (ref, propertyId) =>
          ref.watch(listingSourceProvider).setupStatus(propertyId),
    );

final pendingListingsProvider = FutureProvider<List<PendingListing>>(
  (ref) => ref.watch(listingReviewSourceProvider).pendingListings(),
);
