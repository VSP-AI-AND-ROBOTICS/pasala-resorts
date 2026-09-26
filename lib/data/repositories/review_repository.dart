import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors.dart';
import '../../core/supabase_client.dart';
import '../models/review.dart';

class ReviewRepository {
  ReviewRepository(this._db);
  final SupabaseClient _db;

  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } catch (e) {
      throw mapPostgrestError(e);
    }
  }

  Future<void> submit({
    required String reservationId,
    required int farmhouseRating,
    required int cleanlinessRating,
    required int foodRating,
    required int serviceRating,
    required int activitiesRating,
    required int overallRating,
    String feedback = '',
  }) =>
      _guard(() async {
        final uid = _db.auth.currentUser?.id;
        if (uid == null) throw const NotPermitted();
        await _db.from('reviews').insert(
              Review(
                id: '',
                reservationId: reservationId,
                customerId: uid,
                farmhouseRating: farmhouseRating,
                cleanlinessRating: cleanlinessRating,
                foodRating: foodRating,
                serviceRating: serviceRating,
                activitiesRating: activitiesRating,
                overallRating: overallRating,
                feedback: feedback,
              ).toInsert(),
            );
      });

  Future<Review?> forReservation(String reservationId) => _guard(() async {
        final row = await _db
            .from('reviews')
            .select()
            .eq('reservation_id', reservationId)
            .maybeSingle();
        return row == null ? null : Review.fromJson(row);
      });

  /// One resort's reviews, newest first. `reviews_read`
  /// (0044_resort_policies.sql) shows reviews of active resorts to every
  /// signed-in user, since reviews are social proof shown on the property
  /// page -- so the resort filter here is what keeps each resort's pages to
  /// its own reviews. Each row carries its own `author_name`, so no
  /// `profiles` embed is needed (guest profiles are not readable across
  /// resorts). Backs the admin dashboard's Guest Experience card and
  /// `/admin/reviews` (current resort), and the property page's reviews
  /// section and `/property/:id/reviews` (that property).
  Future<List<Review>> forProperty(String propertyId) => _guard(() async {
        final rows = await _db
            .from('reviews')
            .select()
            .eq('property_id', propertyId)
            .order('created_at', ascending: false);
        return rows.map(Review.fromJson).toList();
      });
}

final reviewRepositoryProvider = Provider<ReviewRepository>(
  (ref) => ReviewRepository(ref.watch(supabaseProvider)),
);

final reviewForReservationProvider = FutureProvider.family<Review?, String>(
  (ref, reservationId) =>
      ref.watch(reviewRepositoryProvider).forReservation(reservationId),
  // Screens show their own Retry button; don't also auto-retry (Riverpod 3
  // retries non-Error throws by default).
  retry: (retryCount, error) => null,
);

final propertyReviewsProvider = FutureProvider.family<List<Review>, String>(
  (ref, propertyId) =>
      ref.watch(reviewRepositoryProvider).forProperty(propertyId),
  // Screens show their own Retry button; don't also auto-retry (Riverpod 3
  // retries non-Error throws by default).
  retry: (retryCount, error) => null,
);
