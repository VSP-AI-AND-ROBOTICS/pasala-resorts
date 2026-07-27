import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/errors.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  BookingFailure map(String code, [String message = 'boom']) =>
      mapPostgrestError(PostgrestException(message: message, code: code));

  test('exclusion violation maps to UnitUnavailable', () {
    expect(map('23P01'), isA<UnitUnavailable>());
  });

  test('P0006 maps to HoldExpired', () {
    expect(map('P0006'), isA<HoldExpired>());
  });

  test('P0007 maps to QuoteStale and keeps the server message', () {
    final failure = map('P0007', 'price changed to 13500');
    expect(failure, isA<QuoteStale>());
    expect(failure.message, contains('13500'));
  });

  test('P0008 and 42501 both map to NotPermitted', () {
    expect(map('P0008'), isA<NotPermitted>());
    expect(map('42501'), isA<NotPermitted>());
  });

  test('NotPermitted never leaks the server message', () {
    expect(map('42501', 'permission denied for table reservations').message,
        isNot(contains('reservations')));
  });

  test('a socket error maps to NetworkFailure', () {
    expect(mapPostgrestError(const SocketException('no route')),
        isA<NetworkFailure>());
  });

  test('P0002 maps to NotFound', () {
    expect(map('P0002'), isA<NotFound>());
  });

  test('P0003, P0004, P0005, and P0009 map to InvalidState', () {
    for (final code in ['P0003', 'P0004', 'P0005', 'P0009']) {
      expect(map(code), isA<InvalidState>(), reason: code);
    }
  });

  test('23514 check violation maps to InvalidState', () {
    expect(map('23514'), isA<InvalidState>());
  });

  test('an unknown code maps to UnknownFailure', () {
    expect(map('99999'), isA<UnknownFailure>());
  });
}
