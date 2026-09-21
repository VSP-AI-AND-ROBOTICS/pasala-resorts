import 'package:flutter/foundation.dart';

enum PaymentStatus {
  pending,
  succeeded,
  failed,
  refunded;

  String get dbValue {
    switch (this) {
      case PaymentStatus.pending:
        return 'pending';
      case PaymentStatus.succeeded:
        return 'succeeded';
      case PaymentStatus.failed:
        return 'failed';
      case PaymentStatus.refunded:
        return 'refunded';
    }
  }

  static PaymentStatus fromString(String str) {
    switch (str.toLowerCase()) {
      case 'pending':
        return PaymentStatus.pending;
      case 'succeeded':
      case 'success':
        return PaymentStatus.succeeded;
      case 'failed':
        return PaymentStatus.failed;
      case 'refunded':
        return PaymentStatus.refunded;
      default:
        return PaymentStatus.pending;
    }
  }
}

enum PaymentKind {
  advance,
  balance,
  full;

  String get dbValue {
    switch (this) {
      case PaymentKind.advance:
        return 'advance';
      case PaymentKind.balance:
        return 'balance';
      case PaymentKind.full:
        return 'full';
    }
  }

  static PaymentKind fromString(String str) {
    switch (str.toLowerCase()) {
      case 'advance':
        return PaymentKind.advance;
      case 'balance':
        return PaymentKind.balance;
      case 'full':
      default:
        return PaymentKind.full;
    }
  }
}

@immutable
class BookingPayment {
  final String id;
  final String bookingId;
  final String resortId;
  final double amount;
  final PaymentKind paymentKind;
  final PaymentStatus status;
  final String gatewayProvider;
  final String transactionRef;
  final String idempotencyKey;
  final Map<String, dynamic> metadata;
  final DateTime createdAt;

  const BookingPayment({
    required this.id,
    required this.bookingId,
    required this.resortId,
    required this.amount,
    required this.paymentKind,
    required this.status,
    this.gatewayProvider = 'demo_gateway',
    required this.transactionRef,
    required this.idempotencyKey,
    this.metadata = const {},
    required this.createdAt,
  });

  factory BookingPayment.fromJson(Map<String, dynamic> json) {
    return BookingPayment(
      id: json['id'] as String,
      bookingId: json['booking_id'] as String,
      resortId: json['resort_id'] as String,
      amount: (json['amount'] as num).toDouble(),
      paymentKind: PaymentKind.fromString(json['payment_kind'] as String? ?? 'advance'),
      status: PaymentStatus.fromString(json['status'] as String? ?? 'pending'),
      gatewayProvider: json['gateway_provider'] as String? ?? 'demo_gateway',
      transactionRef: json['transaction_ref'] as String? ?? '',
      idempotencyKey: json['idempotency_key'] as String? ?? '',
      metadata: json['metadata'] as Map<String, dynamic>? ?? {},
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'booking_id': bookingId,
      'resort_id': resortId,
      'amount': amount,
      'payment_kind': paymentKind.dbValue,
      'status': status.dbValue,
      'gateway_provider': gatewayProvider,
      'transaction_ref': transactionRef,
      'idempotency_key': idempotencyKey,
      'metadata': metadata,
      'created_at': createdAt.toIso8601String(),
    };
  }
}

@immutable
class SubscriptionPayment {
  final String id;
  final String subscriptionId;
  final String resortId;
  final double amount;
  final PaymentStatus status;
  final String transactionRef;
  final String gatewayProvider;
  final String paymentMethod;
  final String idempotencyKey;
  final DateTime createdAt;

  const SubscriptionPayment({
    required this.id,
    required this.subscriptionId,
    required this.resortId,
    required this.amount,
    required this.status,
    required this.transactionRef,
    this.gatewayProvider = 'demo_gateway',
    this.paymentMethod = 'card',
    required this.idempotencyKey,
    required this.createdAt,
  });

  factory SubscriptionPayment.fromJson(Map<String, dynamic> json) {
    return SubscriptionPayment(
      id: json['id'] as String,
      subscriptionId: json['subscription_id'] as String,
      resortId: json['resort_id'] as String,
      amount: (json['amount'] as num).toDouble(),
      status: PaymentStatus.fromString(json['status'] as String? ?? 'pending'),
      transactionRef: json['transaction_ref'] as String? ?? '',
      gatewayProvider: json['gateway_provider'] as String? ?? 'demo_gateway',
      paymentMethod: json['payment_method'] as String? ?? 'card',
      idempotencyKey: json['idempotency_key'] as String? ?? '',
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'subscription_id': subscriptionId,
      'resort_id': resortId,
      'amount': amount,
      'status': status.dbValue,
      'transaction_ref': transactionRef,
      'gateway_provider': gatewayProvider,
      'payment_method': paymentMethod,
      'idempotency_key': idempotencyKey,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
