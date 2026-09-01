import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors.dart';
import '../../core/supabase_client.dart';
import '../models/current_charges.dart';
import '../models/reservation.dart';

class StayRepository {
  StayRepository(this._db);
  final SupabaseClient _db;

  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } catch (e) {
      throw mapPostgrestError(e);
    }
  }

  /// The stay the "My Stay" hub should land on: a `checked_in` reservation
  /// if there is one (the guest is on-site right now), otherwise the
  /// soonest-upcoming `confirmed` one (a guest may start ordering/booking
  /// before arrival). `null` means no active or upcoming stay to show.
  Future<Reservation?> currentStay() => _guard(() async {
        final uid = _db.auth.currentUser?.id;
        if (uid == null) throw const NotPermitted();

        final checkedIn = await _db
            .from('reservations')
            .select()
            .eq('customer_id', uid)
            .eq('kind', 'booking')
            .eq('status', 'checked_in')
            .order('period')
            .limit(1)
            .maybeSingle();
        if (checkedIn != null) return Reservation.fromJson(checkedIn);

        final confirmed = await _db
            .from('reservations')
            .select()
            .eq('customer_id', uid)
            .eq('kind', 'booking')
            .eq('status', 'confirmed')
            .order('period')
            .limit(1)
            .maybeSingle();
        return confirmed == null ? null : Reservation.fromJson(confirmed);
      });

  Future<Reservation> checkIn(String reservationId) => _guard(() async {
        final row = await _db.rpc('check_in_booking', params: {
          'p_reservation_id': reservationId,
        });
        return Reservation.fromJson(row as Map<String, dynamic>);
      });

  Future<CurrentCharges> currentCharges(String reservationId) => _guard(() async {
        final json = await _db.rpc('current_charges', params: {
          'p_reservation_id': reservationId,
        });
        return CurrentCharges.fromJson(json as Map<String, dynamic>);
      });

  Future<Reservation> checkout({
    required String reservationId,
    required String paymentRef,
    required num amount,
  }) =>
      _guard(() async {
        final row = await _db.rpc('checkout_booking', params: {
          'p_reservation_id': reservationId,
          'p_payment_ref': paymentRef,
          'p_amount': amount,
        });
        return Reservation.fromJson(row as Map<String, dynamic>);
      });

  /// Today's confirmed arrivals -- reception's Check-In queue.
  Future<List<Reservation>> todaysArrivals() => _guard(() async {
        final rows = await _db
            .from('reservations')
            .select()
            .eq('kind', 'booking')
            .eq('status', 'confirmed')
            .order('period');
        return rows.map(Reservation.fromJson).toList();
      });
}

final stayRepositoryProvider = Provider<StayRepository>(
  (ref) => StayRepository(ref.watch(supabaseProvider)),
);

final currentStayProvider = FutureProvider<Reservation?>(
  (ref) => ref.watch(stayRepositoryProvider).currentStay(),
);

final currentChargesProvider = FutureProvider.family<CurrentCharges, String>(
  (ref, reservationId) =>
      ref.watch(stayRepositoryProvider).currentCharges(reservationId),
);

final todaysArrivalsProvider = FutureProvider<List<Reservation>>(
  (ref) => ref.watch(stayRepositoryProvider).todaysArrivals(),
);
