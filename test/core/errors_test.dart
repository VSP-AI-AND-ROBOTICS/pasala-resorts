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

  test('P0020 maps to NotAMember', () {
    expect(map('P0020', 'not_a_member'), isA<NotAMember>());
  });

  test('P0021 maps to ResortMismatch with readable copy, never the raw code',
      () {
    final failure = map('P0021', 'resort_mismatch');
    expect(failure, isA<ResortMismatch>());
    expect(failure.message, 'That belongs to a different resort.');
    expect(failure.message, isNot(contains('resort_mismatch')));
  });

  test('P0022 maps to ResortSuspended', () {
    expect(map('P0022'), isA<ResortSuspended>());
  });

  test('P0023 maps to LastOwner with readable copy, never the raw code', () {
    final failure = map('P0023', 'last_owner');
    expect(failure, isA<LastOwner>());
    expect(failure.message, 'A resort must keep at least one owner.');
    expect(failure.message, isNot(contains('last_owner')));
  });

  test('P0030 maps to ReasonRequired with readable copy', () {
    final failure = map('P0030', 'reason_required');
    expect(failure, isA<ReasonRequired>());
    expect(failure.message, 'Enter a reason to mark a room as Maintenance.');
  });

  test('P0031 maps to AlreadyDispatched with readable copy', () {
    final failure = map('P0031', 'already_dispatched');
    expect(failure, isA<AlreadyDispatched>());
    expect(failure.message, 'Housekeeping is already on its way to this room.');
  });

  group('P0034 maps to StayPassRejected by code word', () {
    test('pass_invalid', () {
      final failure = map('P0034', 'pass_invalid');
      expect(failure, isA<StayPassRejected>());
      expect((failure as StayPassRejected).reason, PassRejection.invalid);
      expect(failure.message, 'This is not a valid check-in pass.');
    });

    test('pass_expired', () {
      final failure = map('P0034', 'pass_expired') as StayPassRejected;
      expect(failure.reason, PassRejection.expired);
      expect(failure.message,
          'This pass has expired. Ask the guest to reopen their booking, '
          'or find them in the list.');
    });

    test('pass_other_resort', () {
      final failure = map('P0034', 'pass_other_resort') as StayPassRejected;
      expect(failure.reason, PassRejection.otherResort);
      expect(failure.message,
          'This pass is for a booking at a different resort.');
    });

    // Review Focus 5: whatever the server sends, the desk never sees raw
    // text, and an unknown word reads as an invalid pass.
    test('an unknown code word reads as invalid and never leaks', () {
      final failure = map('P0034', 'something_new') as StayPassRejected;
      expect(failure.reason, PassRejection.invalid);
      expect(failure.message, isNot(contains('something_new')));
    });
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

  // Task 7: P0010-P0013 are coupon errors raised by resolve_coupon/
  // get_quote/create_hold. Their messages are written for the customer
  // (e.g. "coupon SAVE10 has expired") and are safe to show verbatim, so
  // -- unlike NotPermitted -- they map to InvalidState and keep the
  // server's message rather than replacing it with a generic one.
  test('P0010-P0013 map to InvalidState and preserve the server message', () {
    for (final code in ['P0010', 'P0011', 'P0012', 'P0013']) {
      final failure = map(code, 'coupon SAVE10 has expired');
      expect(failure, isA<InvalidState>(), reason: code);
      expect(failure.message, 'coupon SAVE10 has expired', reason: code);
    }
  });

  test('P0010 maps to InvalidState (coupon not found or inactive)', () {
    expect(map('P0010'), isA<InvalidState>());
  });

  test('P0011 maps to InvalidState (coupon expired)', () {
    expect(map('P0011'), isA<InvalidState>());
  });

  test('P0012 maps to InvalidState (coupon usage limit reached)', () {
    expect(map('P0012'), isA<InvalidState>());
  });

  test('P0013 maps to InvalidState (booking below coupon minimum)', () {
    expect(map('P0013'), isA<InvalidState>());
  });

  test('P0014 maps to InvalidState and preserves the server message '
      '(set_user_role last-super-admin guard)', () {
    final failure =
        map('P0014', 'cannot change role: this is the last remaining super_admin');
    expect(failure, isA<InvalidState>());
    expect(failure.message,
        'cannot change role: this is the last remaining super_admin');
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
