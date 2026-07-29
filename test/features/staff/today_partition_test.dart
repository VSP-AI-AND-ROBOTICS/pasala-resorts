import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/data/models/reservation.dart';
import 'package:pasala/features/staff/today_screen.dart';

void main() {
  Reservation res(String start, String end,
          {ReservationStatus status = ReservationStatus.confirmed,
          ReservationKind kind = ReservationKind.booking}) =>
      Reservation(
        id: '$start-$end',
        unitId: 'b1',
        start: DateTime.parse(start),
        end: DateTime.parse(end),
        kind: kind,
        status: status,
      );

  final today = DateTime(2026, 8, 4);

  test('a stay starting today is an arrival', () {
    final p = partitionToday(
        [res('2026-08-04T14:00', '2026-08-06T11:00')], today);
    expect(p.arrivals, hasLength(1));
    expect(p.departures, isEmpty);
  });

  test('a stay ending today is a departure', () {
    final p = partitionToday(
        [res('2026-08-02T14:00', '2026-08-04T11:00')], today);
    expect(p.departures, hasLength(1));
    expect(p.arrivals, isEmpty);
  });

  test('a stay spanning today is staying', () {
    final p = partitionToday(
        [res('2026-08-02T14:00', '2026-08-06T11:00')], today);
    expect(p.staying, hasLength(1));
  });

  test('cancelled stays and admin blocks are excluded', () {
    final p = partitionToday([
      res('2026-08-04T14:00', '2026-08-06T11:00',
          status: ReservationStatus.cancelled),
      res('2026-08-04T14:00', '2026-08-06T11:00',
          kind: ReservationKind.block),
    ], today);
    expect(p.arrivals, isEmpty);
    expect(p.staying, isEmpty);
  });

  // --- Coverage beyond the brief ---

  test(
      'a same-day slot booking (start and end both today) counts as an '
      'arrival only -- not a departure and not staying', () {
    final p = partitionToday(
        [res('2026-08-04T09:00', '2026-08-04T18:00')], today);
    expect(p.arrivals, hasLength(1));
    expect(p.departures, isEmpty);
    expect(p.staying, isEmpty);
  });

  test('a hold is excluded from arrivals, departures, and staying', () {
    final p = partitionToday([
      res('2026-08-04T14:00', '2026-08-06T11:00',
          status: ReservationStatus.hold),
      res('2026-08-02T14:00', '2026-08-04T11:00',
          status: ReservationStatus.hold),
      res('2026-08-02T14:00', '2026-08-06T11:00',
          status: ReservationStatus.hold),
    ], today);
    expect(p.arrivals, isEmpty);
    expect(p.departures, isEmpty);
    expect(p.staying, isEmpty);
  });
}
