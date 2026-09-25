import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/features/booking/razorpay_checkout.dart';
import 'package:pasala/features/booking/razorpay_checkout_mobile.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

const _request = CheckoutRequest(
  keyId: 'rzp_test_fixture',
  orderId: 'order_P6test0001',
  amountPaise: 500000,
  currency: 'INR',
  name: 'Online A',
  description: 'Online A: booking advance',
  prefillName: 'Gita Guest',
  prefillContact: '+919800000001',
);

void main() {
  test('checkoutOptions carries the order and leaves out empty prefill', () {
    expect(checkoutOptions(_request), {
      'key': 'rzp_test_fixture',
      'order_id': 'order_P6test0001',
      'amount': 500000,
      'currency': 'INR',
      'name': 'Online A',
      'description': 'Online A: booking advance',
      'prefill': {'name': 'Gita Guest', 'contact': '+919800000001'},
    });
  });

  test('checkoutOptions never carries a secret', () {
    final text = checkoutOptions(_request).toString();
    expect(text, isNot(contains('secret')));
  });

  group('mobile', () {
    test('a complete success is CheckoutSucceeded', () {
      final outcome = outcomeFromSuccess(PaymentSuccessResponse(
          'pay_1', 'order_1', 'sig', const {}));
      expect(outcome, isA<CheckoutSucceeded>());
      final ok = outcome as CheckoutSucceeded;
      expect((ok.paymentId, ok.orderId, ok.signature), ('pay_1', 'order_1', 'sig'));
    });

    test('a success without a signature cannot be verified', () {
      final outcome =
          outcomeFromSuccess(PaymentSuccessResponse('pay_1', 'order_1', null, const {}));
      expect(outcome, isA<CheckoutFailed>());
    });

    test('cancelling is dismissed, a network error and others are failures', () {
      expect(
          outcomeFromFailure(
              PaymentFailureResponse(Razorpay.PAYMENT_CANCELLED, 'cancelled', null)),
          isA<CheckoutDismissed>());
      expect(
          (outcomeFromFailure(PaymentFailureResponse(Razorpay.NETWORK_ERROR, '{"raw":1}', null))
                  as CheckoutFailed)
              .message,
          'Network error during payment. Try again.');
      expect(
          (outcomeFromFailure(PaymentFailureResponse(Razorpay.UNKNOWN_ERROR, '{"raw":1}', null))
                  as CheckoutFailed)
              .message,
          'Payment failed. Try again or choose another method.');
    });

    test('Android and iOS get the native window, desktop the unsupported one',
        () {
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(createRazorpayCheckout(), isA<MobileRazorpayCheckout>());
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(createRazorpayCheckout(), isA<MobileRazorpayCheckout>());
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      expect(createRazorpayCheckout(), isA<UnsupportedRazorpayCheckout>());
    });
  });
}
