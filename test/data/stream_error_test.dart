import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:pasala/core/errors.dart';
import 'package:pasala/data/models/reservation.dart';

void main() {
  test('a stream error is mapped to a BookingFailure', () async {
    final source = Stream<List<Map<String, dynamic>>>.error(
      PostgrestException(
        message: 'permission denied for table reservations',
        code: '42501',
      ),
    );

    final mapped = source
        .map((rows) => rows.map(Reservation.fromJson).toList())
        .handleError((Object e) => throw mapPostgrestError(e));

    await expectLater(mapped, emitsError(isA<NotPermitted>()));
  });

  test('the mapped failure does not leak the underlying table name', () async {
    final source = Stream<List<Map<String, dynamic>>>.error(
      PostgrestException(
        message: 'permission denied for table reservations',
        code: '42501',
      ),
    );

    final mapped = source
        .map((rows) => rows.map(Reservation.fromJson).toList())
        .handleError((Object e) => throw mapPostgrestError(e));

    try {
      await mapped.first;
      fail('expected an error');
    } catch (e) {
      expect(e, isA<NotPermitted>());
      expect((e as NotPermitted).message, isNot(contains('reservations')));
    }
  });

  test('mapPostgrestError is idempotent for a BookingFailure input', () {
    const original = NotPermitted();
    expect(identical(mapPostgrestError(original), original), isTrue);
  });
}
