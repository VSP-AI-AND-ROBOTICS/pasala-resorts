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

        // `.order()` defaults to descending (a postgrest-dart gotcha, not a
        // Postgres one) -- `ascending: true` is required here, not
        // decorative, or this resolves to the LATEST matching reservation
        // instead of the soonest one this method's own doc comment promises.
        final checkedIn = await _db
            .from('reservations')
            .select()
            .eq('customer_id', uid)
            .eq('kind', 'booking')
            .eq('status', 'checked_in')
            .order('period', ascending: true)
            .limit(1)
            .maybeSingle();
        if (checkedIn != null) return Reservation.fromJson(checkedIn);

        final confirmed = await _db
            .from('reservations')
            .select()
            .eq('customer_id', uid)
            .eq('kind', 'booking')
            .eq('status', 'confirmed')
            .order('period', ascending: true)
            .limit(1)
            .maybeSingle();
        return confirmed == null ? null : Reservation.fromJson(confirmed);
      });

  /// The customer's own most recently checked-out stay, if any -- backs
  /// "My Stay"'s post-checkout review prompt. `currentStay()` never
  /// surfaces a `checked_out` reservation (there's nothing left to manage
  /// in-stay once it's over), so this is a separate, deliberately narrow
  /// query rather than widening that one's meaning.
  Future<Reservation?> mostRecentCheckedOut() => _guard(() async {
        final uid = _db.auth.currentUser?.id;
        if (uid == null) throw const NotPermitted();
        final row = await _db
            .from('reservations')
            .select()
            .eq('customer_id', uid)
            .eq('kind', 'booking')
            .eq('status', 'checked_out')
            .order('period', ascending: false)
            .limit(1)
            .maybeSingle();
        return row == null ? null : Reservation.fromJson(row);
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

  /// Today's confirmed arrivals -- reception's Check-In queue, soonest
  /// arrival first (`ascending: true` -- see the comment on `currentStay`).
  Future<List<Reservation>> todaysArrivals() => _guard(() async {
        final rows = await _db
            .from('reservations')
            .select()
            .eq('kind', 'booking')
            .eq('status', 'confirmed')
            .order('period', ascending: true);
        return rows.map(Reservation.fromJson).toList();
      });

  /// Every guest currently on-site -- reception's Check-Out queue, soonest
  /// -arrived guest first.
  Future<List<Reservation>> checkedIn() => _guard(() async {
        final rows = await _db
            .from('reservations')
            .select()
            .eq('kind', 'booking')
            .eq('status', 'checked_in')
            .order('period', ascending: true);
        return rows.map(Reservation.fromJson).toList();
      });
}

final stayRepositoryProvider = Provider<StayRepository>(
  (ref) => StayRepository(ref.watch(supabaseProvider)),
);

final currentStayProvider = FutureProvider<Reservation?>(
  (ref) => ref.watch(stayRepositoryProvider).currentStay(),
);

final mostRecentCheckedOutProvider = FutureProvider<Reservation?>(
  (ref) => ref.watch(stayRepositoryProvider).mostRecentCheckedOut(),
);

final currentChargesProvider = FutureProvider.family<CurrentCharges, String>(
  (ref, reservationId) =>
      ref.watch(stayRepositoryProvider).currentCharges(reservationId),
);

final todaysArrivalsProvider = FutureProvider<List<Reservation>>(
  (ref) => ref.watch(stayRepositoryProvider).todaysArrivals(),
);

/// `autoDispose` -- unlike this file's other providers, the mutation that
/// invalidates this one (`checkout_booking`) happens on a *different*,
/// separately-pushed screen (`CheckoutScreen`). A plain `FutureProvider`
/// would keep serving its last cached list to whichever admin next opens
/// `/admin/check-out`, however they got there, if that push's route was
/// ever left via anything other than popping straight back to this list
/// (e.g. jumping to Dashboard from the nav rail mid-flow, which never lets
/// `ReceptionCheckoutScreen`'s own post-push invalidate run). `autoDispose`
/// means a fresh instance -- and therefore a fresh query -- is created the
/// next time anything watches it, regardless of navigation path.
final checkedInProvider = FutureProvider.autoDispose<List<Reservation>>(
  (ref) => ref.watch(stayRepositoryProvider).checkedIn(),
);
