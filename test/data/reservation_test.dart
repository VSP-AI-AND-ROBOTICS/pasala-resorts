import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/data/models/reservation.dart';

void main() {
  Map<String, dynamic> json(String status, String? holdExpiry) => {
        'id': 'c1',
        'unit_id': 'b1',
        'period': '["2026-08-03 08:30:00+00","2026-08-04 05:30:00+00")',
        'kind': 'booking',
        'status': status,
        'customer_id': 'u1',
        'guests': 4,
        'quote': null,
        'hold_expires_at': holdExpiry,
        'block_reason': null,
      };

  test('parses a tstzrange into start and end', () {
    final r = Reservation.fromJson(json('confirmed', null));
    expect(r.start, DateTime.parse('2026-08-03 08:30:00Z'));
    expect(r.end, DateTime.parse('2026-08-04 05:30:00Z'));
    expect(r.status, ReservationStatus.confirmed);
  });

  test('an unexpired hold reports remaining time', () {
    final expiry = DateTime.now().toUtc().add(const Duration(minutes: 10));
    final r = Reservation.fromJson(json('hold', expiry.toIso8601String()));
    expect(r.isHold, isTrue);
    expect(r.holdRemaining!.inMinutes, closeTo(9, 1));
  });

  test('an expired hold reports zero remaining', () {
    final expiry = DateTime.now().toUtc().subtract(const Duration(minutes: 1));
    final r = Reservation.fromJson(json('hold', expiry.toIso8601String()));
    expect(r.holdRemaining, Duration.zero);
  });
}
