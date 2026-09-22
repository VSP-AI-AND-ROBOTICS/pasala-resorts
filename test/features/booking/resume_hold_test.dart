import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/data/models/reservation.dart';
import 'package:pasala/features/booking/booking_screen.dart';

/// Coverage for [shouldShowResumeHold], the dead-end fix: a hold survives a
/// declined payment by design, but without this affordance the customer has
/// no way back to `Pay and confirm` for the dates they are still holding.
void main() {
  Reservation hold({
    ReservationStatus status = ReservationStatus.hold,
  }) =>
      Reservation(
        id: 'r1',
        unitId: 'unit-1',
        start: DateTime.utc(2026, 8, 10),
        end: DateTime.utc(2026, 8, 12),
        kind: ReservationKind.booking,
        status: status,
      );

  group('shouldShowResumeHold (pure)', () {
    test('no hold at all -> hidden, regardless of a nonsense remaining value',
        () {
      expect(
        shouldShowResumeHold(hold: null, remaining: const Duration(minutes: 5)),
        isFalse,
      );
    });

    test('live hold with time remaining -> shown', () {
      expect(
        shouldShowResumeHold(
          hold: hold(),
          remaining: const Duration(minutes: 3, seconds: 12),
        ),
        isTrue,
        reason: 'this is exactly the retry-after-decline state: the hold '
            'survived, the customer needs a way back to payment',
      );
    });

    test('live hold but expired (remaining == Duration.zero) -> hidden', () {
      expect(
        shouldShowResumeHold(hold: hold(), remaining: Duration.zero),
        isFalse,
      );
    });

    test('live hold but remaining is null (no expiry info) -> hidden', () {
      expect(
        shouldShowResumeHold(hold: hold(), remaining: null),
        isFalse,
      );
    });

    test('live hold but remaining went negative -> hidden', () {
      expect(
        shouldShowResumeHold(
          hold: hold(),
          remaining: const Duration(seconds: -1),
        ),
        isFalse,
      );
    });

    test('hold present but already confirmed -> hidden even with time left',
        () {
      expect(
        shouldShowResumeHold(
          hold: hold(status: ReservationStatus.confirmed),
          remaining: const Duration(minutes: 1),
        ),
        isFalse,
        reason: 'a confirmed reservation is not a live hold to resume '
            'payment on, even if stale local state still carries a '
            'positive remaining duration',
      );
    });

    test('hold present but already cancelled -> hidden even with time left',
        () {
      expect(
        shouldShowResumeHold(
          hold: hold(status: ReservationStatus.cancelled),
          remaining: const Duration(minutes: 1),
        ),
        isFalse,
      );
    });
  });
}
