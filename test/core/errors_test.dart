import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
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

  test('23505 unique violation maps to DuplicateValue', () {
    expect(map('23505'), isA<DuplicateValue>());
  });

  test('DuplicateValue never leaks the raw constraint-name text', () {
    final failure = map(
      '23505',
      'duplicate key value violates unique constraint "properties_slug_key"',
    );
    expect(failure, isA<DuplicateValue>());
    expect(failure.message, isNot(contains('constraint')));
    expect(failure.message, isNot(contains('properties_slug_key')));
  });

  // I5: on web, BrowserClient (package:http) throws ClientException for
  // transport failures instead of dart:io's SocketException, which never
  // fires in a browser at all.
  test('a web-shaped ClientException maps to NetworkFailure', () {
    final exception = http.ClientException(
      'Failed to fetch',
      Uri.parse('https://project.supabase.co/rest/v1/reservations'),
    );
    expect(mapPostgrestError(exception), isA<NetworkFailure>());
  });

  test('NetworkFailure from a ClientException never leaks the endpoint URL',
      () {
    final exception = http.ClientException(
      'Failed to fetch',
      Uri.parse('https://project.supabase.co/rest/v1/reservations'),
    );
    final failure = mapPostgrestError(exception);
    expect(failure.message, isNot(contains('supabase.co')));
  });

  // I7: every AuthException used to collapse to NotPermitted regardless of
  // cause, so a mistyped password, a duplicate signup email, and a flaky
  // network were indistinguishable on the app's first screen.
  test('a 400 AuthApiException (bad credentials) maps to InvalidCredentials',
      () {
    final failure = mapPostgrestError(
      const AuthApiException('Invalid login credentials', statusCode: '400'),
    );
    expect(failure, isA<InvalidCredentials>());
    expect(failure.message, 'Invalid login credentials');
  });

  test(
      'a 422 AuthApiException (duplicate signup email) maps to '
      'InvalidCredentials', () {
    final failure = mapPostgrestError(
      const AuthApiException('User already registered', statusCode: '422'),
    );
    expect(failure, isA<InvalidCredentials>());
    expect(failure.message, 'User already registered');
  });

  test('an AuthRetryableFetchException maps to NetworkFailure', () {
    expect(
      mapPostgrestError(AuthRetryableFetchException(message: 'timed out')),
      isA<NetworkFailure>(),
    );
  });

  test('an AuthApiException with neither 400 nor 422 maps to NotPermitted',
      () {
    final failure = mapPostgrestError(
      const AuthApiException('server error', statusCode: '500'),
    );
    expect(failure, isA<NotPermitted>());
  });

  test('a bare AuthException (no statusCode) maps to NotPermitted', () {
    expect(mapPostgrestError(const AuthException('unexpected')),
        isA<NotPermitted>());
  });

  test('InvalidCredentials is distinguishable from NotPermitted and '
      'NetworkFailure', () {
    final credentials = mapPostgrestError(
      const AuthApiException('Invalid login credentials', statusCode: '400'),
    );
    final permission = mapPostgrestError(
      const AuthApiException('server error', statusCode: '500'),
    );
    final network =
        mapPostgrestError(AuthRetryableFetchException(message: 'x'));
    expect(credentials.runtimeType, isNot(permission.runtimeType));
    expect(credentials.runtimeType, isNot(network.runtimeType));
  });
}
