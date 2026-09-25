import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

import 'razorpay_checkout.dart';

/// razorpay_flutter has Android and iOS plugins only; on desktop its
/// platform channel never answers, so those get the unsupported window.
RazorpayCheckout createRazorpayCheckout() => switch (defaultTargetPlatform) {
      TargetPlatform.android || TargetPlatform.iOS => MobileRazorpayCheckout(),
      _ => const UnsupportedRazorpayCheckout(),
    };

CheckoutOutcome outcomeFromSuccess(PaymentSuccessResponse response) {
  final paymentId = response.paymentId;
  final orderId = response.orderId;
  final signature = response.signature;
  if (paymentId == null || orderId == null || signature == null) {
    return const CheckoutFailed(incompleteResponseMessage);
  }
  return CheckoutSucceeded(
      paymentId: paymentId, orderId: orderId, signature: signature);
}

/// The SDK's own messages can be raw JSON, so the guest gets ours.
CheckoutOutcome outcomeFromFailure(PaymentFailureResponse response) =>
    switch (response.code) {
      Razorpay.PAYMENT_CANCELLED => const CheckoutDismissed(),
      Razorpay.NETWORK_ERROR => const CheckoutFailed(networkFailedMessage),
      _ => const CheckoutFailed(paymentFailedMessage),
    };

/// Razorpay's native checkout (Android/iOS) through razorpay_flutter. One
/// SDK instance per payment, cleared afterwards.
class MobileRazorpayCheckout implements RazorpayCheckout {
  @override
  Future<CheckoutOutcome> open(CheckoutRequest request) async {
    final razorpay = Razorpay();
    final result = Completer<CheckoutOutcome>();
    void finish(CheckoutOutcome outcome) {
      if (!result.isCompleted) result.complete(outcome);
    }

    razorpay
      ..on(Razorpay.EVENT_PAYMENT_SUCCESS,
          (PaymentSuccessResponse r) => finish(outcomeFromSuccess(r)))
      ..on(Razorpay.EVENT_PAYMENT_ERROR,
          (PaymentFailureResponse r) => finish(outcomeFromFailure(r)))
      ..on(Razorpay.EVENT_EXTERNAL_WALLET,
          (ExternalWalletResponse _) => finish(const CheckoutFailed(externalWalletMessage)));
    try {
      razorpay.open(checkoutOptions(request));
      return await result.future;
    } finally {
      razorpay.clear();
    }
  }
}
