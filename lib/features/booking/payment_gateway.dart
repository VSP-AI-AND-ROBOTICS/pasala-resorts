import 'package:flutter_riverpod/flutter_riverpod.dart';

class PaymentResult {
  const PaymentResult.success(this.reference)
      : succeeded = true,
        failureMessage = null;

  const PaymentResult.failure(this.failureMessage)
      : succeeded = false,
        reference = '';

  final bool succeeded;
  final String reference;
  final String? failureMessage;
}

/// The seam phase 2 replaces with Razorpay. Everything upstream of this
/// interface — hold creation, confirmation, calendar updates — is already
/// exercised by the mock, so swapping the implementation changes no other file.
abstract interface class PaymentGateway {
  Future<PaymentResult> charge({
    required String reservationId,
    required num amount,
  });
}

class MockGateway implements PaymentGateway {
  const MockGateway({
    this.alwaysFail = false,
    this.latency = const Duration(milliseconds: 400),
  });

  final bool alwaysFail;
  final Duration latency;

  @override
  Future<PaymentResult> charge({
    required String reservationId,
    required num amount,
  }) async {
    await Future<void>.delayed(latency);
    if (alwaysFail) {
      return const PaymentResult.failure('Mock gateway declined the payment.');
    }
    return PaymentResult.success(
        'mock_${reservationId}_${amount.toStringAsFixed(0)}');
  }
}

final paymentGatewayProvider =
    Provider<PaymentGateway>((ref) => const MockGateway());
