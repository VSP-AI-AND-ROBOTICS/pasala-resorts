import 'package:flutter/material.dart' show DateTimeRange;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors.dart';
import '../../core/supabase_client.dart';
import '../models/availability.dart';
import '../models/quote.dart';
import '../models/reservation.dart';

String _d(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// The slice of [BookingRepository] that the calendar's realtime/poll
/// fallback (`CalendarRefreshController`, wired up in
/// `features/calendar/providers.dart`) actually needs. Extracted as its own
/// interface so `unitReservationsProvider` can be tested against a fake
/// implementation that never touches Supabase -- see
/// `test/features/calendar/providers_test.dart`.
abstract class UnitCalendarSource {
  Stream<List<Reservation>> watchUnit(String unitId);
  Future<List<Reservation>> fetchUnit(String unitId);
}

/// The slice of [BookingRepository] that `BookingScreen` needs to run the
/// quote/hold/pay lifecycle. Extracted as its own interface, mirroring
/// [UnitCalendarSource], so `bookingActionsProvider` can be overridden with a
/// fake in tests that never touches Supabase -- see
/// `test/features/booking/hold_lifecycle_test.dart`. This is what makes the
/// release-or-reuse hold logic testable: without this seam, exercising
/// `create_hold`/`cancel_booking` ordering would require a real
/// `SupabaseClient`.
abstract class BookingActions {
  Future<Quote> quote({
    required String unitId,
    required DateTime from,
    required DateTime to,
    required int guests,
    String? slotTypeId,
  });

  Future<Reservation> createHold({
    required String unitId,
    required DateTime from,
    required DateTime to,
    required int guests,
    String? slotTypeId,
    num? expectedTotal,
  });

  Future<Reservation> confirm({
    required String reservationId,
    required String paymentRef,
    required num amount,
  });

  Future<Reservation> cancel({
    required String reservationId,
    required String reason,
  });
}

/// The slice of [BookingRepository] that `BlockDatesScreen` (Task 20) needs.
/// Extracted as its own interface, mirroring [UnitCalendarSource] and
/// [BookingActions], so `test/features/admin/block_selection_test.dart` can
/// override `blockDatesActionProvider` with a fake instead of needing a real
/// `SupabaseClient`. Kept separate from [BookingActions] rather than added to
/// it: several existing fakes (`_FakeBookingActions`,
/// `_ThrowingCancelActions`, `_FakeCancelActions`) already `implements
/// BookingActions` for the customer booking flow, and none of them have any
/// business modelling `blockDates` -- folding it in would force every one of
/// them to grow a throwaway override for a method their scenarios never call.
abstract class BlockDatesAction {
  Future<List<Reservation>> blockDates({
    required String unitId,
    required List<DateTimeRange> ranges,
    required String reason,
  });
}

class BookingRepository
    implements UnitCalendarSource, BookingActions, BlockDatesAction {
  BookingRepository(this._db);
  final SupabaseClient _db;

  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } catch (e) {
      throw mapPostgrestError(e);
    }
  }

  Future<List<UnitAvailability>> search({
    String? propertyId,
    required DateTime from,
    required DateTime to,
    int guests = 1,
    String? slotTypeId,
  }) =>
      _guard(() async {
        final rows = await _db.rpc('search_availability', params: {
          'p_property_id': propertyId,
          'p_from': _d(from),
          'p_to': _d(to),
          'p_guests': guests,
          'p_slot_type_id': slotTypeId,
        }) as List<dynamic>;
        return rows
            .map((e) => UnitAvailability.fromJson(e as Map<String, dynamic>))
            .toList();
      });

  @override
  Future<Quote> quote({
    required String unitId,
    required DateTime from,
    required DateTime to,
    required int guests,
    String? slotTypeId,
  }) =>
      _guard(() async {
        final period = await _db.rpc('build_period', params: {
          'p_unit_id': unitId,
          'p_from': _d(from),
          'p_to': _d(to),
          'p_slot_type_id': slotTypeId,
        });
        final json = await _db.rpc('get_quote', params: {
          'p_unit_id': unitId,
          'p_period': period,
          'p_guests': guests,
          'p_slot_type_id': slotTypeId,
        });
        return Quote.fromJson(json as Map<String, dynamic>);
      });

  @override
  Future<Reservation> createHold({
    required String unitId,
    required DateTime from,
    required DateTime to,
    required int guests,
    String? slotTypeId,
    num? expectedTotal,
  }) =>
      _guard(() async {
        final row = await _db.rpc('create_hold', params: {
          'p_unit_id': unitId,
          'p_from': _d(from),
          'p_to': _d(to),
          'p_guests': guests,
          'p_slot_type_id': slotTypeId,
          'p_expected_total': expectedTotal,
        });
        return Reservation.fromJson(row as Map<String, dynamic>);
      });

  @override
  Future<Reservation> confirm({
    required String reservationId,
    required String paymentRef,
    required num amount,
  }) =>
      _guard(() async {
        final row = await _db.rpc('confirm_booking', params: {
          'p_reservation_id': reservationId,
          'p_payment_ref': paymentRef,
          'p_amount': amount,
        });
        return Reservation.fromJson(row as Map<String, dynamic>);
      });

  /// Fetches one reservation by id. Used by the confirmation screen, which
  /// only has the id from the `/booking/:id` route after `confirm` redirects.
  Future<Reservation> reservation(String id) => _guard(() async {
        final row =
            await _db.from('reservations').select().eq('id', id).single();
        return Reservation.fromJson(row);
      });

  @override
  Future<Reservation> cancel({
    required String reservationId,
    required String reason,
  }) =>
      _guard(() async {
        final row = await _db.rpc('cancel_booking', params: {
          'p_reservation_id': reservationId,
          'p_reason': reason,
        });
        return Reservation.fromJson(row as Map<String, dynamic>);
      });

  @override
  Future<List<Reservation>> blockDates({
    required String unitId,
    required List<DateTimeRange> ranges,
    required String reason,
  }) =>
      _guard(() async {
        final rows = await _db.rpc('block_dates', params: {
          'p_unit_id': unitId,
          // daterange is [), so the upper bound is the day after the last
          // blocked date.
          'p_ranges': ranges
              .map((r) => '[${_d(r.start)},${_d(r.end.add(const Duration(days: 1)))})')
              .toList(),
          'p_reason': reason,
        }) as List<dynamic>;
        return rows
            .map((e) => Reservation.fromJson(e as Map<String, dynamic>))
            .toList();
      });

  Future<List<Reservation>> myBookings() => _guard(() async {
        final uid = _db.auth.currentUser?.id;
        if (uid == null) throw const NotPermitted();
        final rows = await _db
            .from('reservations')
            .select()
            .eq('customer_id', uid)
            .order('period', ascending: false);
        return rows.map(Reservation.fromJson).toList();
      });

  Future<List<Reservation>> allBookings({DateTime? from, DateTime? to}) =>
      _guard(() async {
        final rows =
            await _db.from('reservations').select().order('period');
        return rows
            .map(Reservation.fromJson)
            .where((r) =>
                (from == null || r.end.isAfter(from)) &&
                (to == null || r.start.isBefore(to)))
            .toList();
      });

  @override
  Stream<List<Reservation>> watchUnit(String unitId) => _db
      .from('unit_calendar_events')
      .stream(primaryKey: ['reservation_id'])
      .eq('unit_id', unitId)
      .map((rows) => rows.map(Reservation.fromCalendarEvent).toList())
      .handleError((Object e) => throw mapPostgrestError(e));

  /// One-shot snapshot of a unit's calendar mirror, equivalent to what
  /// [watchUnit] shows initially. Used as the periodic fallback poll so the
  /// calendar cannot stay stale forever if the realtime websocket silently
  /// drops (see [CalendarRefreshController]).
  @override
  Future<List<Reservation>> fetchUnit(String unitId) => _guard(() async {
        final rows = await _db
            .from('unit_calendar_events')
            .select()
            .eq('unit_id', unitId);
        return rows.map(Reservation.fromCalendarEvent).toList();
      });
}

final bookingRepositoryProvider = Provider<BookingRepository>(
  (ref) => BookingRepository(ref.watch(supabaseProvider)),
);

/// [BookingActions] seam around [bookingRepositoryProvider], mirroring
/// [unitCalendarSourceProvider] in `features/calendar/providers.dart`:
/// `BookingScreen` only ever calls `quote`/`createHold`/`confirm`/`cancel`,
/// so tests can override just this provider with a fake instead of needing a
/// real `SupabaseClient`.
final bookingActionsProvider = Provider<BookingActions>(
  (ref) => ref.watch(bookingRepositoryProvider),
);

/// [BlockDatesAction] seam around [bookingRepositoryProvider], mirroring
/// [bookingActionsProvider]: `BlockDatesScreen` only ever calls
/// `blockDates`, so tests can override just this provider with a fake.
final blockDatesActionProvider = Provider<BlockDatesAction>(
  (ref) => ref.watch(bookingRepositoryProvider),
);
