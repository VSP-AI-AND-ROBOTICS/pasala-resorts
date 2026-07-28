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

class BookingRepository {
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

  Stream<List<Reservation>> watchUnit(String unitId) => _db
      .from('reservations')
      .stream(primaryKey: ['id'])
      .eq('unit_id', unitId)
      .map((rows) => rows.map(Reservation.fromJson).toList())
      .handleError((Object e) => throw mapPostgrestError(e));
}

final bookingRepositoryProvider = Provider<BookingRepository>(
  (ref) => BookingRepository(ref.watch(supabaseProvider)),
);
