import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors.dart';
import '../../core/supabase_client.dart';
import '../models/activity.dart';

class ActivityRepository {
  ActivityRepository(this._db);
  final SupabaseClient _db;

  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } catch (e) {
      throw mapPostgrestError(e);
    }
  }

  Future<List<Activity>> catalog(String propertyId) => _guard(() async {
        final rows = await _db
            .from('activities')
            .select()
            .eq('property_id', propertyId)
            .eq('is_available', true)
            .order('name');
        return rows.map((e) => Activity.fromJson(e)).toList();
      });

  /// `p_start_time` is `HH:mm` -- the server column is `time`, which
  /// accepts that format directly.
  Future<ActivityBooking> bookActivity({
    required String reservationId,
    required String activityId,
    required DateTime bookingDate,
    required String startTime,
    required int people,
  }) =>
      _guard(() async {
        final d = bookingDate;
        final iso = '${d.year.toString().padLeft(4, '0')}-'
            '${d.month.toString().padLeft(2, '0')}-'
            '${d.day.toString().padLeft(2, '0')}';
        final row = await _db.rpc('book_activity', params: {
          'p_reservation_id': reservationId,
          'p_activity_id': activityId,
          'p_booking_date': iso,
          'p_start_time': startTime,
          'p_people': people,
        });
        return ActivityBooking.fromJson(row as Map<String, dynamic>);
      });

  Future<List<ActivityBooking>> myBookings(String reservationId) => _guard(() async {
        final rows = await _db
            .from('activity_bookings')
            .select('*, activities(name)')
            .eq('reservation_id', reservationId)
            .order('booking_date');
        return rows.map((e) => ActivityBooking.fromJson(e)).toList();
      });

  Future<void> cancelBooking(String bookingId) => _guard(() async {
        await _db
            .from('activity_bookings')
            .update({'status': 'cancelled'}).eq('id', bookingId);
      });
}

final activityRepositoryProvider = Provider<ActivityRepository>(
  (ref) => ActivityRepository(ref.watch(supabaseProvider)),
);

final activityCatalogProvider = FutureProvider.family<List<Activity>, String>(
  (ref, propertyId) => ref.watch(activityRepositoryProvider).catalog(propertyId),
);

final myActivityBookingsProvider =
    FutureProvider.family<List<ActivityBooking>, String>(
  (ref, reservationId) =>
      ref.watch(activityRepositoryProvider).myBookings(reservationId),
);
