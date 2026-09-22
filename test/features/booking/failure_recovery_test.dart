import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/errors.dart';
import 'package:pasala/data/models/quote.dart';
import 'package:pasala/data/models/reservation.dart';
import 'package:pasala/features/booking/booking_screen.dart';

void main() {
  final from = DateTime(2026, 8, 3);
  final to = DateTime(2026, 8, 5);

  final quote = Quote.fromJson(const {
    'currency': 'INR',
    'guests': 2,
    'lines': [
      {'date': '2026-08-03', 'label': 'Weekend rate', 'amount': 5000,
       'extra_guests': 0, 'extra_guest_amount': 0},
    ],
    'subtotal': 5000,
    'cleaning_fee': 500,
    'total': 5500,
  });

  final hold = Reservation(
    id: 'r1',
    unitId: 'u1',
    start: DateTime.utc(2026, 8, 3, 8, 30),
    end: DateTime.utc(2026, 8, 5, 5, 30),
    kind: ReservationKind.booking,
    status: ReservationStatus.hold,
    holdExpiresAt: DateTime.now().toUtc().add(const Duration(minutes: 10)),
  );

  HoldSelection selectionWith({Reservation? hold, Quote? quote}) =>
      HoldSelection(hold: hold, quote: quote, from: from, to: to);

  group('recoverSelection', () {
    test('UnitUnavailable clears the hold, the quote, and the selected end date', () {
      final next = recoverSelection(
          const UnitUnavailable(), selectionWith(hold: hold, quote: quote));

      expect(next.hold, isNull);
      expect(next.quote, isNull);
      expect(next.from, from, reason: 'the start date survives');
      expect(next.to, isNull, reason: 'the end date must be cleared so the '
          'calendar forces a fresh, non-conflicting pick');
    });

    test('HoldExpired clears the hold and quote but KEEPS both dates', () {
      final next = recoverSelection(
          const HoldExpired(), selectionWith(hold: hold, quote: quote));

      expect(next.hold, isNull);
      expect(next.quote, isNull);
      expect(next.from, from);
      expect(next.to, to, reason: 'dates are kept on hold expiry so the '
          'customer can retry without re-picking');
    });

    test('QuoteStale clears the quote (forcing a re-fetch) and keeps dates', () {
      final next = recoverSelection(
          const QuoteStale('price changed to 6000'),
          selectionWith(hold: hold, quote: quote));

      expect(next.quote, isNull);
      expect(next.hold, isNull);
      expect(next.from, from);
      expect(next.to, to);
    });

    test('an unrelated failure (e.g. NotPermitted) leaves the selection untouched', () {
      final current = selectionWith(hold: hold, quote: quote);
      final next = recoverSelection(const NotPermitted(), current);

      expect(next.hold, same(hold));
      expect(next.quote, same(quote));
      expect(next.from, from);
      expect(next.to, to);
    });

    test('NetworkFailure leaves the selection untouched', () {
      final current = selectionWith(hold: hold, quote: quote);
      final next = recoverSelection(const NetworkFailure(), current);

      expect(next.hold, same(hold));
      expect(next.quote, same(quote));
    });
  });
}
