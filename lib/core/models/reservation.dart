import 'package:flutter/foundation.dart';

enum ReservationStatus {
  pending,
  confirmed,
  checkedIn,
  checkedOut,
  cancelled;

  String get dbValue {
    switch (this) {
      case ReservationStatus.pending:
        return 'pending';
      case ReservationStatus.confirmed:
        return 'confirmed';
      case ReservationStatus.checkedIn:
        return 'checked_in';
      case ReservationStatus.checkedOut:
        return 'checked_out';
      case ReservationStatus.cancelled:
        return 'cancelled';
    }
  }

  static ReservationStatus fromString(String str) {
    switch (str.toLowerCase()) {
      case 'pending':
        return ReservationStatus.pending;
      case 'confirmed':
        return ReservationStatus.confirmed;
      case 'checked_in':
      case 'checkedin':
        return ReservationStatus.checkedIn;
      case 'checked_out':
      case 'checkedout':
        return ReservationStatus.checkedOut;
      case 'cancelled':
        return ReservationStatus.cancelled;
      default:
        return ReservationStatus.confirmed;
    }
  }

  String get displayName {
    switch (this) {
      case ReservationStatus.pending:
        return 'Pending';
      case ReservationStatus.confirmed:
        return 'Confirmed';
      case ReservationStatus.checkedIn:
        return 'Checked-In';
      case ReservationStatus.checkedOut:
        return 'Checked-Out';
      case ReservationStatus.cancelled:
        return 'Cancelled';
    }
  }
}

@immutable
class Reservation {
  final String id;
  final String resortId;
  final String? customerId;
  final String unitId;
  final String? unitName;
  final DateTime checkIn;
  final DateTime checkOut;
  final double totalAmount;
  final double advanceAmount;
  final ReservationStatus status;
  final String guestName;
  final String guestPhone;
  final String guestEmail;
  final int guestCount;
  final DateTime createdAt;

  const Reservation({
    required this.id,
    required this.resortId,
    this.customerId,
    required this.unitId,
    this.unitName,
    required this.checkIn,
    required this.checkOut,
    required this.totalAmount,
    required this.advanceAmount,
    required this.status,
    required this.guestName,
    required this.guestPhone,
    required this.guestEmail,
    required this.guestCount,
    required this.createdAt,
  });

  factory Reservation.fromJson(Map<String, dynamic> json) {
    return Reservation(
      id: json['id'] as String,
      resortId: json['resort_id'] as String,
      customerId: json['customer_id'] as String?,
      unitId: json['unit_id'] as String,
      unitName: json['unit_name'] as String?,
      checkIn: DateTime.parse(json['check_in'] as String),
      checkOut: DateTime.parse(json['check_out'] as String),
      totalAmount: (json['total_amount'] as num).toDouble(),
      advanceAmount: (json['advance_amount'] as num).toDouble(),
      status: ReservationStatus.fromString(json['status'] as String? ?? 'confirmed'),
      guestName: json['guest_name'] as String? ?? 'Guest',
      guestPhone: json['guest_phone'] as String? ?? '',
      guestEmail: json['guest_email'] as String? ?? '',
      guestCount: json['guest_count'] as int? ?? 1,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'resort_id': resortId,
      'customer_id': customerId,
      'unit_id': unitId,
      'unit_name': unitName,
      'check_in': checkIn.toIso8601String().split('T')[0],
      'check_out': checkOut.toIso8601String().split('T')[0],
      'total_amount': totalAmount,
      'advance_amount': advanceAmount,
      'status': status.dbValue,
      'guest_name': guestName,
      'guest_phone': guestPhone,
      'guest_email': guestEmail,
      'guest_count': guestCount,
      'created_at': createdAt.toIso8601String(),
    };
  }

  Reservation copyWith({
    String? id,
    String? resortId,
    String? customerId,
    String? unitId,
    String? unitName,
    DateTime? checkIn,
    DateTime? checkOut,
    double? totalAmount,
    double? advanceAmount,
    ReservationStatus? status,
    String? guestName,
    String? guestPhone,
    String? guestEmail,
    int? guestCount,
    DateTime? createdAt,
  }) {
    return Reservation(
      id: id ?? this.id,
      resortId: resortId ?? this.resortId,
      customerId: customerId ?? this.customerId,
      unitId: unitId ?? this.unitId,
      unitName: unitName ?? this.unitName,
      checkIn: checkIn ?? this.checkIn,
      checkOut: checkOut ?? this.checkOut,
      totalAmount: totalAmount ?? this.totalAmount,
      advanceAmount: advanceAmount ?? this.advanceAmount,
      status: status ?? this.status,
      guestName: guestName ?? this.guestName,
      guestPhone: guestPhone ?? this.guestPhone,
      guestEmail: guestEmail ?? this.guestEmail,
      guestCount: guestCount ?? this.guestCount,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
