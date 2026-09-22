import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/data/models/reservation.dart';
import 'package:pasala/features/booking/booking_screen.dart';

void main() {
  final today = DateTime(2026, 8, 1);

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

  group('rangeHasUnavailableDay', () {
    test('an all-available range is not flagged', () {
      expect(
        rangeHasUnavailableDay(
          from: DateTime(2026, 8, 10),
          to: DateTime(2026, 8, 12),
          reservations: const [],
          today: today,
        ),
        isFalse,
      );
    });

    test('a booked night strictly inside the range is flagged', () {
      final reservations = [
        res(start: '2026-08-11T14:00', end: '2026-08-13T11:00'),
      ];
      expect(
        rangeHasUnavailableDay(
          from: DateTime(2026, 8, 10),
          to: DateTime(2026, 8, 12),
          reservations: reservations,
          today: today,
        ),
        isTrue,
      );
    });

    test('a blocked night inside the range is flagged', () {
      final reservations = [
        res(
          start: '2026-08-11T00:00',
          end: '2026-08-12T00:00',
          kind: ReservationKind.block,
        ),
      ];
      expect(
        rangeHasUnavailableDay(
          from: DateTime(2026, 8, 10),
          to: DateTime(2026, 8, 12),
          reservations: reservations,
          today: today,
        ),
        isTrue,
      );
    });

    test('another customer\'s hold inside the range is flagged', () {
      final reservations = [
        res(
          start: '2026-08-11T00:00',
          end: '2026-08-12T00:00',
          status: ReservationStatus.hold,
        ),
      ];
      expect(
        rangeHasUnavailableDay(
          from: DateTime(2026, 8, 10),
          to: DateTime(2026, 8, 12),
          reservations: reservations,
          today: today,
        ),
        isTrue,
      );
    });

    test('the checkout day itself is excluded -- a stay ending exactly on '
        '`to` does not flag the range', () {
      final reservations = [
        res(start: '2026-08-08T14:00', end: '2026-08-10T11:00'),
      ];
      expect(
        rangeHasUnavailableDay(
          from: DateTime(2026, 8, 10),
          to: DateTime(2026, 8, 12),
          reservations: reservations,
          today: today,
        ),
        isFalse,
      );
    });

    test('a single-night range only checks the one night', () {
      final reservations = [
        res(start: '2026-08-10T14:00', end: '2026-08-11T11:00'),
      ];
      expect(
        rangeHasUnavailableDay(
          from: DateTime(2026, 8, 10),
          to: DateTime(2026, 8, 11),
          reservations: reservations,
          today: today,
        ),
        isTrue,
      );
    });
  });
}
