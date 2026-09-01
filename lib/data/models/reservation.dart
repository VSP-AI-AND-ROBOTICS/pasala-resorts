import 'quote.dart';

enum ReservationKind { booking, block, ota }

enum ReservationStatus { hold, pendingPayment, confirmed, checkedIn, checkedOut, cancelled }

ReservationStatus _status(String raw) => switch (raw) {
      'hold' => ReservationStatus.hold,
      'pending_payment' => ReservationStatus.pendingPayment,
      'confirmed' => ReservationStatus.confirmed,
      'checked_in' => ReservationStatus.checkedIn,
      'checked_out' => ReservationStatus.checkedOut,
      'cancelled' => ReservationStatus.cancelled,
      _ => throw ArgumentError('unknown status $raw'),
    };

/// Parses a Postgres tstzrange literal: ["2026-08-03 08:30:00+00","...")
({DateTime start, DateTime end}) parsePeriod(String raw) {
  final parts = raw
      .substring(1, raw.length - 1)
      .split(',')
      .map((s) => s.replaceAll('"', '').trim())
      .toList();
  return (
    start: DateTime.parse(parts[0].replaceFirst(' ', 'T')).toUtc(),
    end: DateTime.parse(parts[1].replaceFirst(' ', 'T')).toUtc(),
  );
}

class Reservation {
  const Reservation({
    required this.id,
    required this.unitId,
    required this.start,
    required this.end,
    required this.kind,
    required this.status,
    this.customerId,
    this.guests,
    this.quote,
    this.holdExpiresAt,
    this.blockReason,
    this.occasion,
    this.checkedInAt,
    this.checkedOutAt,
  });

  final String id;
  final String unitId;
  final DateTime start;
  final DateTime end;
  final ReservationKind kind;
  final ReservationStatus status;
  final String? customerId;
  final int? guests;
  final Quote? quote;
  final DateTime? holdExpiresAt;
  final String? blockReason;
  final DateTime? checkedInAt;
  final DateTime? checkedOutAt;

  /// A free-text note captured at hold time (e.g. "Anniversary weekend").
  /// Never read by pricing -- purely informational, shown on the
  /// confirmation and booking-detail screens when non-empty.
  final String? occasion;

  bool get isHold => status == ReservationStatus.hold;

  Duration? get holdRemaining {
    final expiry = holdExpiresAt;
    if (expiry == null) return null;
    final left = expiry.difference(DateTime.now().toUtc());
    return left.isNegative ? Duration.zero : left;
  }

  factory Reservation.fromJson(Map<String, dynamic> json) {
    final period = parsePeriod(json['period'] as String);
    return Reservation(
      id: json['id'] as String,
      unitId: json['unit_id'] as String,
      start: period.start,
      end: period.end,
      kind: ReservationKind.values.byName(json['kind'] as String),
      status: _status(json['status'] as String),
      customerId: json['customer_id'] as String?,
      guests: (json['guests'] as num?)?.toInt(),
      quote: json['quote'] == null
          ? null
          : Quote.fromJson(json['quote'] as Map<String, dynamic>),
      holdExpiresAt: json['hold_expires_at'] == null
          ? null
          : DateTime.parse(json['hold_expires_at'] as String).toUtc(),
      blockReason: json['block_reason'] as String?,
      occasion: json['occasion'] as String?,
      checkedInAt: json['checked_in_at'] == null
          ? null
          : DateTime.parse(json['checked_in_at'] as String).toUtc(),
      checkedOutAt: json['checked_out_at'] == null
          ? null
          : DateTime.parse(json['checked_out_at'] as String).toUtc(),
    );
  }

  /// Built from `unit_calendar_events`, the identity-free occupancy mirror.
  /// customerId, guests and quote are intentionally absent -- this row exists
  /// so any viewer can see THAT a date is taken, never by whom.
  factory Reservation.fromCalendarEvent(Map<String, dynamic> json) {
    final period = parsePeriod(json['period'] as String);
    return Reservation(
      id: json['reservation_id'] as String,
      unitId: json['unit_id'] as String,
      start: period.start,
      end: period.end,
      kind: ReservationKind.values.byName(json['kind'] as String),
      status: _status(json['status'] as String),
    );
  }
}
