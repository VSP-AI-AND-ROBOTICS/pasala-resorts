import 'dart:io';
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

  final code = switch (error) {
    PostgrestException(:final code) => code,
    AuthException() => '42501',
    _ => null,
  };
  final message = switch (error) {
    PostgrestException(:final message) => message,
    AuthException(:final message) => message,
    _ => error.toString(),
  };

  return switch (code) {
    '23P01' => const UnitUnavailable(),
    'P0006' => const HoldExpired(),
    'P0007' => QuoteStale(message),
    'P0008' || '42501' => const NotPermitted(),
    'P0002' => const NotFound(),
    'P0003' || 'P0004' || 'P0005' || 'P0009' => InvalidState(message),
    '23514' => InvalidState(message),
    '23505' => const DuplicateValue(),
    _ => UnknownFailure(message),
  };
}
