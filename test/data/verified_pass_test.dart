import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/data/models/reservation.dart';
import 'package:pasala/data/models/verified_pass.dart';

void main() {
  test('fromJson reads the booking, its resort and its unit name', () {
    final pass = VerifiedPass.fromJson({
      'id': 'res-1',
      'unit_id': 'u1',
      'property_id': 'p1',
      'period': '["2026-09-26 08:30:00+00","2026-09-28 05:30:00+00")',
      'kind': 'booking',
      'status': 'confirmed',
      'customer_id': 'c1',
      'guests': 2,
      'quote': null,
      'profiles': {'full_name': 'Ravi Kumar', 'phone': '9000000001'},
      'unit_name': 'Cottage 1',
    });

    expect(pass.reservation.id, 'res-1');
    expect(pass.reservation.unitId, 'u1');
    expect(pass.reservation.status, ReservationStatus.confirmed);
    expect(pass.reservation.start, DateTime.utc(2026, 9, 26, 8, 30));
    expect(pass.reservation.customerName, 'Ravi Kumar');
    expect(pass.reservation.customerPhone, '9000000001');
    expect(pass.reservation.guests, 2);
    expect(pass.propertyId, 'p1');
    expect(pass.unitName, 'Cottage 1');
  });

  test('a missing unit name is allowed', () {
    final pass = VerifiedPass.fromJson({
      'id': 'res-1',
      'unit_id': 'u1',
      'property_id': 'p1',
      'period': '["2026-09-26 08:30:00+00","2026-09-28 05:30:00+00")',
      'kind': 'booking',
      'status': 'cancelled',
    });
    expect(pass.unitName, isNull);
    expect(pass.reservation.status, ReservationStatus.cancelled);
  });

  group('looksLikeStayPass', () {
    test('accepts a pass, with or without surrounding whitespace', () {
      expect(looksLikeStayPass('rh1.abc'), isTrue);
      expect(looksLikeStayPass('  rh1.abc\n'), isTrue);
    });

    test('rejects booking codes, names, bare ids and empty text', () {
      expect(looksLikeStayPass('PR3F2A'), isFalse);
      expect(looksLikeStayPass('Ravi'), isFalse);
      expect(
        looksLikeStayPass('3f2a1b9c-0000-0000-0000-000000000000'),
        isFalse,
      );
      expect(looksLikeStayPass(''), isFalse);
    });
  });
}
