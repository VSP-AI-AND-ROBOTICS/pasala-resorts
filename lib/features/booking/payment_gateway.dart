import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/payment_order.dart';
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

/// The seam phase 2 replaces with Razorpay. Everything upstream of this
/// interface — hold creation, confirmation, calendar updates — is already
/// exercised by the mock, so swapping the implementation changes no other file.
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

/// The actual selection logic, extracted from [paymentGatewayProvider] so it
/// can be exercised directly in a plain unit test. `--dart-define` values
/// are baked in as compile-time constants (see [_razorpayKeyId] above), so a
/// normal `flutter test` run can never observe the provider itself resolving
/// to [RazorpayGateway] -- without this seam, `razorpay_gateway_test.dart`
/// could only ever prove the empty-key (MockGateway) branch, and deleting
/// the [RazorpayGateway] branch entirely would pass every test in this repo
/// just as well as keeping it (I7).
PaymentGateway resolvePaymentGateway({
  required String keyId,
  required String keySecret,
}) {
  if (keyId.isEmpty) {
    return const MockGateway();
  }
  return RazorpayGateway(keyId: keyId, keySecret: keySecret);
}

final paymentGatewayProvider = Provider<PaymentGateway>((ref) =>
    resolvePaymentGateway(
        keyId: _razorpayKeyId, keySecret: _razorpayKeySecret));

/// The Razorpay payment window for this platform. Tests override it with
/// `FakeRazorpayCheckout`.
final razorpayCheckoutProvider =
    Provider<RazorpayCheckout>((ref) => createRazorpayCheckout());
