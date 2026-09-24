import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

sealed class BookingFailure implements Exception {
  const BookingFailure(this.message);
  final String message;
  @override
  String toString() => '$runtimeType: $message';
}

class UnitUnavailable extends BookingFailure {
  const UnitUnavailable()
      : super('Those dates were just taken. Pick another slot.');
}

class HoldExpired extends BookingFailure {
  const HoldExpired()
      : super('Your 15-minute hold expired. Start again — dates are kept.');
}

class QuoteStale extends BookingFailure {
  const QuoteStale(super.message);
}

class NotPermitted extends BookingFailure {
  const NotPermitted() : super('You do not have access to do that.');
}

/// P0020 -- the signed-in user has no `resort_members` row for the resort a
/// function or query was scoped to, e.g. a remembered current resort they
/// have since been removed from.
class NotAMember extends BookingFailure {
  const NotAMember() : super('You no longer have access to this resort.');
}

/// P0022 -- the resort's `properties.status` is `suspended`. Staff writes
/// via functions are refused; the guest can still read and cancel.
class ResortSuspended extends BookingFailure {
  const ResortSuspended()
      : super('This resort is suspended — changes are disabled.');
}

/// A 400/422 from Supabase auth: a mistyped password on sign-in, or a
/// duplicate email on sign-up. Kept distinct from [NotPermitted] (I7) --
/// without this, every one of those looked identical to "you don't have
/// access", including on the app's very first screen, before the customer
/// has anything to have access to. [message] comes straight from
/// [AuthException.message], which -- unlike [PostgrestException.message] --
/// is already written for an end user (e.g. "Invalid login credentials",
/// "User already registered"), so it is safe to show verbatim.
class InvalidCredentials extends BookingFailure {
  const InvalidCredentials(super.message);
}

class NotFound extends BookingFailure {
  const NotFound() : super('That item no longer exists.');
}

class InvalidState extends BookingFailure {
  const InvalidState(super.message);
}

class NetworkFailure extends BookingFailure {
  const NetworkFailure() : super('Cannot reach the server. Check your connection.');
}

class UnknownFailure extends BookingFailure {
  const UnknownFailure(super.message);
}

/// A unique-constraint violation (Postgres `23505`) -- e.g. `properties.slug`
/// is `unique`, so re-using a slug on create raises this. Without this arm,
/// the code fell through to [UnknownFailure] and [FailureView] would show its
/// generic fallback with no hint of what to fix; this gives the admin a
/// specific, actionable message instead while still never repeating the raw
/// constraint-name text Postgres sent.
class DuplicateValue extends BookingFailure {
  const DuplicateValue()
      : super('That value is already in use. Try a different one.');
}

/// Translates a Supabase or transport error into a typed failure.
/// Widgets must never see a [PostgrestException].
BookingFailure mapPostgrestError(Object error) {
  if (error is BookingFailure) return error;
  if (error is SocketException) return const NetworkFailure();
  // `dart:io`'s SocketException never fires on web -- `BrowserClient` (the
  // `package:http` client Supabase uses there) throws a `ClientException`
  // for the exact same "offline"/DNS/CORS-preflight-failed case instead.
  // Without this arm an offline web user fell through to UnknownFailure,
  // which meant `FailureView` showed its raw-text branch carrying the
  // Supabase endpoint URL (I5).
  if (error is http.ClientException) return const NetworkFailure();

  // Auth errors are handled before the Postgrest switch below: they carry
  // their own status/message shape (a `String?` statusCode, not a Postgrest
  // error code), and I7 needs to distinguish a credential problem from a
  // network blip from an actual permission failure -- collapsing all three
  // to NotPermitted (the old behaviour) made every one of them read as "you
  // do not have access to do that," including on the sign-in screen before
  // the customer has anything to have access to.
  if (error is AuthRetryableFetchException) return const NetworkFailure();
  if (error is AuthApiException) {
    return switch (error.statusCode) {
      '400' || '422' => InvalidCredentials(error.message),
      _ => const NotPermitted(),
    };
  }
  if (error is AuthException) return const NotPermitted();

  final code = switch (error) {
    PostgrestException(:final code) => code,
    _ => null,
  };
  final message = switch (error) {
    PostgrestException(:final message) => message,
    _ => error.toString(),
  };

  return switch (code) {
    '23P01' => const UnitUnavailable(),
    'P0006' => const HoldExpired(),
    'P0007' => QuoteStale(message),
    'P0008' || '42501' => const NotPermitted(),
    'P0002' => const NotFound(),
    // P0010-P0013 are coupon errors raised by resolve_coupon (via get_quote
    // and create_hold): unknown/inactive code, expired, usage limit
    // reached, and booking below the coupon's minimum. Every one of these
    // messages is written for the customer -- e.g. "coupon SAVE10 has
    // expired" -- and safe to show verbatim, same as P0003/P0004/P0005/
    // P0009 below.
    'P0003' || 'P0004' || 'P0005' || 'P0009' ||
    'P0010' || 'P0011' || 'P0012' || 'P0013' => InvalidState(message),
    // P0014: set_user_role's last-super-admin guard (0019_user_admin.sql)
    // -- refuses to demote the only remaining super_admin, since that would
    // lock every human out of administration with no recovery but psql.
    // The message is written for the admin reading it and safe to show
    // verbatim, same as the other InvalidState-mapped codes above.
    'P0014' => InvalidState(message),
    // P0020-P0023: resort-tenancy errors. P0020 (not_a_member) and P0022
    // (resort_suspended) get dedicated failures with their own copy;
    // P0021 (resort_mismatch) and P0023 (last_owner) carry a
    // server-written message that's already safe to show verbatim, same
    // as the other InvalidState-mapped codes above.
    'P0020' => const NotAMember(),
    'P0021' => InvalidState(message),
    'P0022' => const ResortSuspended(),
    'P0023' => InvalidState(message),
    '23514' => InvalidState(message),
    '23505' => const DuplicateValue(),
    _ => UnknownFailure(message),
  };
}
