import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/payment_order.dart';
import '../../data/repositories/payment_order_repository.dart';
import 'razorpay_checkout.dart';
import 'razorpay_checkout_platform.dart';
import 'razorpay_gateway.dart';

export '../../data/models/payment_order.dart' show PaymentPurpose;

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

/// How the app takes a payment. [RazorpayGateway] is the only
/// implementation the app uses; [MockGateway] is its fallback when the
/// deployment has no Razorpay keys, and tests use their own fakes.
abstract interface class PaymentGateway {
  /// Takes [amount] rupees for [reservationId]. [purpose] tells the server
  /// which rule the amount must meet: the advance range for a hold, the
  /// balance due for a checked-in stay.
  Future<PaymentResult> charge({
    required String reservationId,
    required num amount,
    PaymentPurpose purpose = PaymentPurpose.advance,
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
    PaymentPurpose purpose = PaymentPurpose.advance,
  }) async {
    await Future<void>.delayed(latency);
    if (alwaysFail) {
      return const PaymentResult.failure('Mock gateway declined the payment.');
    }
    return PaymentResult.success(
        'mock_${reservationId}_${amount.toStringAsFixed(0)}');
  }
}

/// Every payment asks the server first: with Razorpay keys set it takes a
/// real payment, without them [RazorpayGateway] hands it to [MockGateway]
/// exactly as before P6. The app never holds a Razorpay secret.
final paymentGatewayProvider = Provider<PaymentGateway>((ref) => RazorpayGateway(
      orders: ref.watch(paymentOrderSourceProvider),
      checkout: ref.watch(razorpayCheckoutProvider),
    ));

/// The Razorpay payment window for this platform. Tests override it with
/// `FakeRazorpayCheckout`.
final razorpayCheckoutProvider =
    Provider<RazorpayCheckout>((ref) => createRazorpayCheckout());
