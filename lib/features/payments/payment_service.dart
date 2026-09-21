import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../../core/models/payment.dart';
import '../../core/models/reservation.dart';
import '../../core/services/mock_data_store.dart';

class PaymentResult {
  final bool isSuccess;
  final String transactionRef;
  final String idempotencyKey;
  final String message;
  final BookingPayment? bookingPayment;
  final SubscriptionPayment? subscriptionPayment;

  const PaymentResult({
    required this.isSuccess,
    required this.transactionRef,
    required this.idempotencyKey,
    required this.message,
    this.bookingPayment,
    this.subscriptionPayment,
  });
}

abstract class PaymentGateway {
  Future<PaymentResult> processBookingPayment({
    required Reservation reservation,
    required double amount,
    required PaymentKind paymentKind,
    required String idempotencyKey,
    required String paymentMethod, // 'card', 'upi', 'netbanking'
  });

  Future<PaymentResult> processSubscriptionPayment({
    required String subscriptionId,
    required String resortId,
    required double amount,
    required String idempotencyKey,
    required String paymentMethod,
  });
}

class DemoPaymentGateway implements PaymentGateway {
  final MockDataStore _store = MockDataStore.instance;
  final Uuid _uuid = const Uuid();

  // Track processed idempotency keys to ensure strict idempotency
  final Set<String> _processedKeys = {};
  final Map<String, PaymentResult> _cachedResults = {};

  @override
  Future<PaymentResult> processBookingPayment({
    required Reservation reservation,
    required double amount,
    required PaymentKind paymentKind,
    required String idempotencyKey,
    required String paymentMethod,
  }) async {
    // 1. Check Idempotency
    if (_processedKeys.contains(idempotencyKey)) {
      if (kDebugMode) {
        print('Idempotent call detected for key: $idempotencyKey. Returning cached result.');
      }
      return _cachedResults[idempotencyKey]!;
    }

    // Check if store already has a succeeded payment for this idempotency key
    final existing = _store.bookingPayments.any((p) => p.idempotencyKey == idempotencyKey && p.status == PaymentStatus.succeeded);
    if (existing) {
      final prev = _store.bookingPayments.firstWhere((p) => p.idempotencyKey == idempotencyKey);
      return PaymentResult(
        isSuccess: true,
        transactionRef: prev.transactionRef,
        idempotencyKey: idempotencyKey,
        message: 'Payment already processed successfully (Idempotent replay).',
        bookingPayment: prev,
      );
    }

    // Simulate network delay for payment provider call
    await Future.delayed(const Duration(milliseconds: 600));

    final txnRef = 'BKG-DEMO-${_uuid.v4().substring(0, 8).toUpperCase()}';
    
    final newPayment = BookingPayment(
      id: 'bp-${_uuid.v4().substring(0, 8)}',
      bookingId: reservation.id,
      resortId: reservation.resortId,
      amount: amount,
      paymentKind: paymentKind,
      status: PaymentStatus.succeeded,
      gatewayProvider: 'demo_gateway',
      transactionRef: txnRef,
      idempotencyKey: idempotencyKey,
      metadata: {
        'payment_method': paymentMethod,
        'guest_name': reservation.guestName,
        'guest_email': reservation.guestEmail,
      },
      createdAt: DateTime.now(),
    );

    // Save to store
    _store.bookingPayments.add(newPayment);

    // Update reservation status if fully paid or confirmed
    final resIndex = _store.reservations.indexWhere((r) => r.id == reservation.id);
    if (resIndex != -1) {
      _store.reservations[resIndex] = _store.reservations[resIndex].copyWith(
        status: ReservationStatus.confirmed,
      );
    }

    final result = PaymentResult(
      isSuccess: true,
      transactionRef: txnRef,
      idempotencyKey: idempotencyKey,
      message: 'Booking payment of ₹${amount.toStringAsFixed(2)} ($paymentKind) processed successfully.',
      bookingPayment: newPayment,
    );

    _processedKeys.add(idempotencyKey);
    _cachedResults[idempotencyKey] = result;

    return result;
  }

  @override
  Future<PaymentResult> processSubscriptionPayment({
    required String subscriptionId,
    required String resortId,
    required double amount,
    required String idempotencyKey,
    required String paymentMethod,
  }) async {
    // 1. Idempotency verification
    if (_processedKeys.contains(idempotencyKey)) {
      return _cachedResults[idempotencyKey]!;
    }

    await Future.delayed(const Duration(milliseconds: 600));

    final txnRef = 'SUB-DEMO-${_uuid.v4().substring(0, 8).toUpperCase()}';

    final newPayment = SubscriptionPayment(
      id: 'sp-${_uuid.v4().substring(0, 8)}',
      subscriptionId: subscriptionId,
      resortId: resortId,
      amount: amount,
      status: PaymentStatus.succeeded,
      transactionRef: txnRef,
      gatewayProvider: 'demo_gateway',
      paymentMethod: paymentMethod,
      idempotencyKey: idempotencyKey,
      createdAt: DateTime.now(),
    );

    _store.subscriptionPayments.add(newPayment);

    final result = PaymentResult(
      isSuccess: true,
      transactionRef: txnRef,
      idempotencyKey: idempotencyKey,
      message: 'Resort subscription payment of ₹${amount.toStringAsFixed(2)} processed successfully.',
      subscriptionPayment: newPayment,
    );

    _processedKeys.add(idempotencyKey);
    _cachedResults[idempotencyKey] = result;

    return result;
  }
}
