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

  /// Every review, newest first -- `reviews_read`'s `is_staff_or_above()`
  /// branch already grants this to admin/staff, so no new RLS is needed.
  /// Backs the admin dashboard's Guest Experience card (average rating,
  /// latest review) and the standalone Reviews screen.
  Future<List<Review>> all() => _guard(() async {
        final rows = await _db
            .from('reviews')
            .select()
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
);

final allReviewsProvider = FutureProvider<List<Review>>(
  (ref) => ref.watch(reviewRepositoryProvider).all(),
);
