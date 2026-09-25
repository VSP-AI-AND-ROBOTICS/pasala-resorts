import '../../data/models/payment_order.dart';

/// The Razorpay payment window: Checkout.js on the web, razorpay_flutter
/// on Android/iOS (razorpay_checkout_platform.dart picks one).

const unsupportedCheckoutMessage =
    'Online payment is not available on this device.';
const paymentFailedMessage = 'Payment failed. Try again or choose another method.';
const networkFailedMessage = 'Network error during payment. Try again.';
const checkoutLoadFailedMessage =
    'Could not load the payment window. Check your connection and try again.';
const incompleteResponseMessage =
    'The payment window gave an incomplete answer. If money was taken, '
    'contact the resort.';
const externalWalletMessage =
    'That wallet is not supported here. Choose another payment method.';

/// What the payment window needs. Only the public key id -- never a secret.
class CheckoutRequest {
  const CheckoutRequest({
    required this.keyId,
    required this.orderId,
    required this.amountPaise,
    required this.currency,
    required this.name,
    required this.description,
    this.prefillName,
    this.prefillEmail,
    this.prefillContact,
  });

  factory CheckoutRequest.fromOrder(RazorpayOrder order) => CheckoutRequest(
    keyId: order.keyId,
    orderId: order.orderId,
    amountPaise: order.amountPaise,
    currency: order.currency,
    name: order.name,
    description: order.description,
    prefillName: order.prefillName,
    prefillEmail: order.prefillEmail,
    prefillContact: order.prefillContact,
  );

  final String keyId;
  final String orderId;
  final int amountPaise;
  final String currency;
  final String name;
  final String description;
  final String? prefillName;
  final String? prefillEmail;
  final String? prefillContact;
}

sealed class CheckoutOutcome {
  const CheckoutOutcome();
}

/// Razorpay says the guest paid. Not trusted until `payments-verify` has
/// checked [signature] on the server.
final class CheckoutSucceeded extends CheckoutOutcome {
  const CheckoutSucceeded({
    required this.paymentId,
    required this.orderId,
    required this.signature,
  });

  final String paymentId;
  final String orderId;
  final String signature;
}

/// The guest closed the window without paying.
final class CheckoutDismissed extends CheckoutOutcome {
  const CheckoutDismissed();
}

/// The window failed; [message] is written for the guest.
final class CheckoutFailed extends CheckoutOutcome {
  const CheckoutFailed(this.message);

  final String message;
}

abstract interface class RazorpayCheckout {
  Future<CheckoutOutcome> open(CheckoutRequest request);
}

/// Platforms without a Razorpay SDK (desktop): says so rather than hanging.
class UnsupportedRazorpayCheckout implements RazorpayCheckout {
  const UnsupportedRazorpayCheckout();

  @override
  Future<CheckoutOutcome> open(CheckoutRequest request) async =>
      const CheckoutFailed(unsupportedCheckoutMessage);
}

/// The options both payment windows take (Razorpay's documented Checkout
/// options). Empty prefill fields are left out.
Map<String, Object?> checkoutOptions(CheckoutRequest request) => {
      'key': request.keyId,
      'order_id': request.orderId,
      'amount': request.amountPaise,
      'currency': request.currency,
      'name': request.name,
      'description': request.description,
      'prefill': <String, Object?>{
        if (request.prefillName != null) 'name': request.prefillName,
        if (request.prefillEmail != null) 'email': request.prefillEmail,
        if (request.prefillContact != null) 'contact': request.prefillContact,
      },
    };
