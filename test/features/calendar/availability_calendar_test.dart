import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/errors.dart';
import 'package:pasala/data/models/reservation.dart';
import 'package:pasala/data/repositories/booking_repository.dart';
import 'package:pasala/features/calendar/availability_calendar.dart';
import 'package:pasala/features/calendar/providers.dart';

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

  // --- I2: the error branch must never render raw server text -------------
  //
  // Reproduced before the fix: `error is BookingFailure ? error.message :
  // ...` showed `UnknownFailure`'s message verbatim, and UnknownFailure IS a
  // BookingFailure -- so a permission error like "permission denied for
  // table reservations" reached the customer's screen. The fix routes
  // through FailureView.messageFor, which intercepts UnknownFailure and
  // falls back to a generic message; this test pins that the table name
  // never appears.
  //
  // The error is injected at `unitCalendarSourceProvider` -- the seam
  // `unitReservationsProvider`'s own `CalendarRefreshController` is built
  // on (see `test/features/calendar/providers_test.dart`'s `_FakeCalendarSource`
  // for the same convention) -- rather than overriding
  // `unitReservationsProvider` itself, so this exercises the REAL
  // provider/controller wiring the widget actually watches, not a
  // hand-rolled substitute for it.
  //
  // `ProviderContainer(retry: (_, _) => null, ...)` disables Riverpod's own
  // default retry-with-backoff behaviour for this container: without it,
  // `unitReservationsProvider`'s StreamProvider intercepts the stream error
  // and schedules an automatic retry (up to 10 attempts, exponential
  // backoff) instead of surfacing a terminal `AsyncError` -- during which
  // `AsyncValue.isLoading` is ALSO true (a "retrying" loading state), so the
  // widget's own loading branch (checked first) would win and show only a
  // spinner, never reaching the code under test at all. Disabling retry
  // makes the very first error terminal, which is what this test needs to
  // observe.
  testWidgets(
      'a permission-denied error never shows the raw table name on the '
      'calendar', (tester) async {
    const rawServerText = 'permission denied for table reservations';

    final container = ProviderContainer(
      retry: (retryCount, error) => null,
      overrides: [
        unitCalendarSourceProvider.overrideWithValue(
          _ErrorCalendarSource(const UnknownFailure(rawServerText)),
        ),
      ],
    );

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: AvailabilityCalendar(unitId: 'u1', month: today),
        ),
      ),
    ));
    await tester.pump();

    expect(find.textContaining('reservations'), findsNothing);
    expect(find.textContaining('permission denied'), findsNothing);

    // Dispose the widget tree (cancelling CalendarRefreshController's
    // Timer.periodic via its onDispose) and the container BEFORE the test
    // ends -- flutter_test's own teardown asserts no timer is left pending,
    // and `addTearDown` runs too late in that sequence to satisfy it.
    await tester.pumpWidget(const SizedBox());
    container.dispose();
  });
}

/// A [UnitCalendarSource] whose realtime stream and fallback fetch both
/// fail with [error] -- everything `CalendarRefreshController` might
/// surface to `unitReservationsProvider` errors, so the widget's error
/// branch is reached regardless of which path (realtime or poll) wins.
class _ErrorCalendarSource implements UnitCalendarSource {
  const _ErrorCalendarSource(this.error);

  final Object error;

  @override
  Stream<List<Reservation>> watchUnit(String unitId) =>
      Stream<List<Reservation>>.error(error);

  @override
  Future<List<Reservation>> fetchUnit(String unitId) => Future.error(error);
}
