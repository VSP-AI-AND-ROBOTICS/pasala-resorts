import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/data/models/reservation.dart';
import 'package:pasala/features/staff/today_screen.dart';

Reservation _res(
  String id, {
  required DateTime start,
  required DateTime end,
  ReservationStatus status = ReservationStatus.confirmed,
  ReservationKind kind = ReservationKind.booking,
}) =>
    Reservation(
      id: id,
      unitId: 'u1',
      start: start,
      end: end,
      kind: kind,
      status: status,
    );

void main() {
  final today = DateTime(2026, 9, 7);

  group('partitionToday', () {
    test('a confirmed stay starting today is an arrival', () {
      final r = _res('a', start: DateTime(2026, 9, 7), end: DateTime(2026, 9, 9));
      final result = partitionToday([r], today);
      expect(result.arrivals.map((x) => x.id), ['a']);
      expect(result.departures, isEmpty);
      expect(result.staying, isEmpty);
    });

    test('a confirmed stay ending today is a departure', () {
      final r = _res('a', start: DateTime(2026, 9, 5), end: DateTime(2026, 9, 7));
      final result = partitionToday([r], today);
      expect(result.departures.map((x) => x.id), ['a']);
    });

    test('a confirmed stay spanning today (neither edge) is staying', () {
      final r = _res('a', start: DateTime(2026, 9, 5), end: DateTime(2026, 9, 9));
      final result = partitionToday([r], today);
      expect(result.staying.map((x) => x.id), ['a']);
    });

    // I8: a checked-in guest previously vanished from every section of this
    // screen for the rest of their stay -- only `confirmed` was ever
    // handled, so the instant a guest checked in, staff lost all visibility
    // into who was actually on the property. Reproduced live: a staff
    // member's Today screen showed nothing even with a guest in-house.
    test('a checked-in guest staying past today shows in In house', () {
      final r = _res(
        'a',
        start: DateTime(2026, 9, 5),
        end: DateTime(2026, 9, 9),
        status: ReservationStatus.checkedIn,
      );
      final result = partitionToday([r], today);
      expect(result.staying.map((x) => x.id), ['a']);
      expect(result.arrivals, isEmpty);
      expect(result.departures, isEmpty);
    });

    test('a checked-in guest who arrived today and stays longer is still '
        'In house, not Arrivals', () {
      final r = _res(
        'a',
        start: DateTime(2026, 9, 7),
        end: DateTime(2026, 9, 9),
        status: ReservationStatus.checkedIn,
      );
      final result = partitionToday([r], today);
      expect(result.staying.map((x) => x.id), ['a']);
      expect(result.arrivals, isEmpty);
    });

    test('a checked-in guest whose stay ends today is a departure, not '
        'In house', () {
      final r = _res(
        'a',
        start: DateTime(2026, 9, 5),
        end: DateTime(2026, 9, 7),
        status: ReservationStatus.checkedIn,
      );
      final result = partitionToday([r], today);
      expect(result.departures.map((x) => x.id), ['a']);
      expect(result.staying, isEmpty);
    });

    test('a checked-out guest never appears, even if their stay window '
        'still overlaps today', () {
      final r = _res(
        'a',
        start: DateTime(2026, 9, 5),
        end: DateTime(2026, 9, 9),
        status: ReservationStatus.checkedOut,
      );
      final result = partitionToday([r], today);
      expect(result.arrivals, isEmpty);
      expect(result.departures, isEmpty);
      expect(result.staying, isEmpty);
    });

    test('a hold or pending-payment reservation never appears', () {
      final hold = _res(
        'h',
        start: DateTime(2026, 9, 7),
        end: DateTime(2026, 9, 9),
        status: ReservationStatus.hold,
      );
      final pending = _res(
        'p',
        start: DateTime(2026, 9, 7),
        end: DateTime(2026, 9, 9),
        status: ReservationStatus.pendingPayment,
      );
      final result = partitionToday([hold, pending], today);
      expect(result.arrivals, isEmpty);
      expect(result.departures, isEmpty);
      expect(result.staying, isEmpty);
    });

    test('a block is never guest activity, regardless of status', () {
      final block = _res(
        'b',
        start: DateTime(2026, 9, 7),
        end: DateTime(2026, 9, 9),
        kind: ReservationKind.block,
      );
      final result = partitionToday([block], today);
      expect(result.arrivals, isEmpty);
      expect(result.departures, isEmpty);
      expect(result.staying, isEmpty);
    });

    test('a same-day confirmed slot booking is an arrival only', () {
      final r = _res('a', start: DateTime(2026, 9, 7), end: DateTime(2026, 9, 7));
      final result = partitionToday([r], today);
      expect(result.arrivals.map((x) => x.id), ['a']);
      expect(result.departures, isEmpty);
      expect(result.staying, isEmpty);
    });
  });
}
