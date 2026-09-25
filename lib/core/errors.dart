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

/// `P0002` from `add_resort_member` specifically -- the email typed into
/// Team's "Add member" dialog doesn't match any signed-up account. The
/// server sends this as a bare `not_found` code with no user-facing text,
/// same shape as every other `P0002` site in this app (`mapPostgrestError`
/// maps those generically to [NotFound], "That item no longer exists.") --
/// but that message is wrong here (nothing "existed" to go missing; the
/// email was just never signed up), so `ResortMemberRepository.add` catches
/// this one `P0002` itself and throws this instead, with the specific
/// next-step copy the Team screen needs.
class NoAccountFound extends BookingFailure {
  const NoAccountFound()
      : super('No account with that email — ask them to sign up first.');
}

/// P0023 -- the last-owner guard (`set_role` / `remove_resort_member`)
/// refused to demote or remove a resort's only owner. The server sends the
/// bare code word `last_owner`, so the copy lives here.
class LastOwner extends BookingFailure {
  const LastOwner() : super('A resort must keep at least one owner.');
}

/// P0021 -- the resort-consistency trigger (0043_resort_tenancy.sql)
/// refused a row whose parent (a unit, a reservation, a task ...) belongs
/// to a different resort. The server sends the bare code word
/// `resort_mismatch`, so the copy lives here.
class ResortMismatch extends BookingFailure {
  const ResortMismatch() : super('That belongs to a different resort.');
}

/// P0030 -- `set_room_status` refused Maintenance without a reason. The
/// room sheet asks for one first, so this is a backstop.
class ReasonRequired extends BookingFailure {
  const ReasonRequired()
      : super('Enter a reason to mark a room as Maintenance.');
}

/// P0031 -- `dispatch_housekeeping` found an open housekeeping task for the
/// room (someone else sent housekeeping a moment ago).
class AlreadyDispatched extends BookingFailure {
  const AlreadyDispatched()
      : super('Housekeeping is already on its way to this room.');
}

/// P0038 -- `billing_subscribe_state`: the chosen tier has no Razorpay
/// plan id yet, so it cannot be paid online (P8). The server sends the
/// bare code word `billing_unavailable`, so the copy lives here.
class BillingUnavailable extends BookingFailure {
  const BillingUnavailable()
      : super("Online payment isn't set up for this plan yet. "
            'Contact ResortHub.');
}

/// P0037 -- `retry_outbox_message` refused a message that is not failed or
/// dry run (it is already queued again, sent, or skipped).
class NotRetryable extends BookingFailure {
  const NotRetryable()
      : super('Only failed or dry-run messages can be sent again.');
}

/// P0035 -- `properties_check_service_tax` refused a food or spa rate
/// outside 0..28. The Taxes screen checks the range first, so this is a
/// backstop.
class TaxRateOutOfRange extends BookingFailure {
  const TaxRateOutOfRange()
      : super('Food and spa tax rates must be between 0% and 28%.');
}

/// Why `verify_stay_pass` refused a check-in pass (P0034).
enum PassRejection { invalid, expired, otherResort }

/// P0034 -- `verify_stay_pass` (0052_stay_pass.sql) refused a scanned or
/// typed check-in pass. The server sends one of three bare code words
/// (`pass_invalid`, `pass_expired`, `pass_other_resort`), so the copy lives
/// here; anything else reads as invalid.
class StayPassRejected extends BookingFailure {
  const StayPassRejected.invalid()
      : reason = PassRejection.invalid,
        super('This is not a valid check-in pass.');

  const StayPassRejected.expired()
      : reason = PassRejection.expired,
        super('This pass has expired. Ask the guest to reopen their booking, '
            'or find them in the list.');

  const StayPassRejected.otherResort()
      : reason = PassRejection.otherResort,
        super('This pass is for a booking at a different resort.');

  factory StayPassRejected.fromServer(String code) => switch (code) {
        'pass_expired' => const StayPassRejected.expired(),
        'pass_other_resort' => const StayPassRejected.otherResort(),
        _ => const StayPassRejected.invalid(),
      };

  final PassRejection reason;
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
    // P0020-P0023: resort-tenancy errors. P0020 (not_a_member), P0021
    // (resort_mismatch), P0022 (resort_suspended) and P0023 (last_owner)
    // get dedicated failures with their own copy -- the server sends only
    // a bare code word for each.
    'P0020' => const NotAMember(),
    'P0021' => const ResortMismatch(),
    'P0022' => const ResortSuspended(),
    'P0023' => const LastOwner(),
    // P0030/P0031: room status (0047). The server sends bare codes
    // (`reason_required`, `already_dispatched`), so the copy lives here.
    'P0030' => const ReasonRequired(),
    'P0031' => const AlreadyDispatched(),
    // P0038: subscription billing (0057). Bare code word, copy lives here.
    'P0038' => const BillingUnavailable(),
    // P0037: outbox delivery (0056). Only retry_outbox_message reaches the
    // app; complete_outbox_message's P0037 is service_role-only.
    'P0037' => const NotRetryable(),
    // P0035: food and spa tax rates (0053). Bare code word from the server.
    'P0035' => const TaxRateOutOfRange(),
    // P0034: check-in passes (0052). Bare code words; see StayPassRejected.
    'P0034' => StayPassRejected.fromServer(message),
    '23514' => InvalidState(message),
    '23505' => const DuplicateValue(),
    _ => UnknownFailure(message),
  };
}
