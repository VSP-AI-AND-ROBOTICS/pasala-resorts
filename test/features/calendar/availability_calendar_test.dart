import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/data/models/reservation.dart';
import 'package:pasala/features/calendar/availability_calendar.dart';

void main() {
  Reservation res({
    required String start,
    required String end,
    ReservationKind kind = ReservationKind.booking,
    ReservationStatus status = ReservationStatus.confirmed,
  }) =>
      Reservation(
        id: 'r',
        unitId: 'u',
        start: DateTime.parse(start),
        end: DateTime.parse(end),
        kind: kind,
        status: status,
      );

  final today = DateTime(2026, 8, 1);

  test('a day inside a confirmed booking is booked', () {
    final list = [res(start: '2026-08-03T14:00', end: '2026-08-05T11:00')];
    expect(statusFor(DateTime(2026, 8, 4), list, today: today),
        DayStatus.booked);
  });

  test('the checkout day is available again', () {
    final list = [res(start: '2026-08-03T14:00', end: '2026-08-05T11:00')];
    expect(statusFor(DateTime(2026, 8, 5), list, today: today),
        DayStatus.available);
  });

  test('an admin block renders as blocked, not booked', () {
    final list = [
      res(start: '2026-08-10T14:00', end: '2026-08-12T11:00',
          kind: ReservationKind.block)
    ];
    expect(statusFor(DateTime(2026, 8, 11), list, today: today),
        DayStatus.blocked);
  });

  test('an active hold renders as pending', () {
    final list = [
      res(start: '2026-08-20T14:00', end: '2026-08-21T11:00',
          status: ReservationStatus.hold)
    ];
    expect(statusFor(DateTime(2026, 8, 20), list, today: today),
        DayStatus.pending);
  });

  test('a cancelled reservation does not mark the day', () {
    final list = [
      res(start: '2026-08-03T14:00', end: '2026-08-05T11:00',
          status: ReservationStatus.cancelled)
    ];
    expect(statusFor(DateTime(2026, 8, 4), list, today: today),
        DayStatus.available);
  });

  test('a day before today is past', () {
    expect(statusFor(DateTime(2026, 7, 31), const [], today: today),
        DayStatus.past);
  });

  // --- Coverage beyond the brief: statusFor is the single place day
  // colouring is decided, so its edge cases matter more than the widget's.

  test('booked outranks a competing hold on the same day', () {
    final list = [
      res(start: '2026-08-03T14:00', end: '2026-08-05T11:00'),
      res(
          start: '2026-08-04T10:00',
          end: '2026-08-04T18:00',
          status: ReservationStatus.hold),
    ];
    expect(statusFor(DateTime(2026, 8, 4), list, today: today),
        DayStatus.booked);
  });

  test('booked outranks a competing hold regardless of list order', () {
    final list = [
      res(
          start: '2026-08-04T10:00',
          end: '2026-08-04T18:00',
          status: ReservationStatus.hold),
      res(start: '2026-08-03T14:00', end: '2026-08-05T11:00'),
    ];
    expect(statusFor(DateTime(2026, 8, 4), list, today: today),
        DayStatus.booked);
  });

  test('a block outranks a competing hold on the same day', () {
    final list = [
      res(
          start: '2026-08-10T14:00',
          end: '2026-08-12T11:00',
          kind: ReservationKind.block),
      res(
          start: '2026-08-11T09:00',
          end: '2026-08-11T20:00',
          status: ReservationStatus.hold),
    ];
    expect(statusFor(DateTime(2026, 8, 11), list, today: today),
        DayStatus.blocked);
  });

  test('a block outranks a competing hold regardless of list order', () {
    final list = [
      res(
          start: '2026-08-11T09:00',
          end: '2026-08-11T20:00',
          status: ReservationStatus.hold),
      res(
          start: '2026-08-10T14:00',
          end: '2026-08-12T11:00',
          kind: ReservationKind.block),
    ];
    expect(statusFor(DateTime(2026, 8, 11), list, today: today),
        DayStatus.blocked);
  });

  test('the check-in day of a stay is booked, not available', () {
    final list = [res(start: '2026-08-03T14:00', end: '2026-08-05T11:00')];
    expect(statusFor(DateTime(2026, 8, 3), list, today: today),
        DayStatus.booked);
  });

  test(
      'a stay entirely in the past is reported as past, not booked, '
      'because the past check runs before the reservation is ever '
      'inspected', () {
    final list = [res(start: '2026-07-10T14:00', end: '2026-07-12T11:00')];
    expect(statusFor(DateTime(2026, 7, 11), list, today: today),
        DayStatus.past);
  });

  test(
      'a same-day 09:00-18:00 day-slot booking stays booked all day '
      '(never eligible for the checkout-freeing rule, since it never '
      'starts on an earlier day)', () {
    final list = [res(start: '2026-08-15T09:00', end: '2026-08-15T18:00')];
    expect(statusFor(DateTime(2026, 8, 15), list, today: today),
        DayStatus.booked);
  });

  test(
      'a stay that started the day before and ends at 18:00 today is '
      'NOT freed by the checkout rule — 18:00 fails the noon cutoff, so '
      'the day correctly stays booked', () {
    final list = [res(start: '2026-08-14T18:00', end: '2026-08-15T18:00')];
    expect(statusFor(DateTime(2026, 8, 15), list, today: today),
        DayStatus.booked);
  });
}
