import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'razorpay_gateway.dart';

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

// There is no live Razorpay merchant account (see docs/STATUS.md), so
// nothing in this repository's build configuration ever supplies
// RAZORPAY_KEY_ID -- these two constants are always empty in every build
// this repo produces, and this provider always resolves to MockGateway.
// RazorpayGateway exists as a written, importable seam for the day a real
// key exists, not as something this codebase enables on its own. A build
// that IS misconfigured with a key id but no matching secret fails loudly
// at construction time (RazorpayConfigurationError), never silently at
// charge time.
const _razorpayKeyId = String.fromEnvironment('RAZORPAY_KEY_ID');
const _razorpayKeySecret = String.fromEnvironment('RAZORPAY_KEY_SECRET');

final paymentGatewayProvider = Provider<PaymentGateway>((ref) {
  if (_razorpayKeyId.isEmpty) {
    return const MockGateway();
  }
  return RazorpayGateway(keyId: _razorpayKeyId, keySecret: _razorpayKeySecret);
});
