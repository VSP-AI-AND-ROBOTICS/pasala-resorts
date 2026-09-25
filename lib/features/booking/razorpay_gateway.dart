import '../../data/models/payment_order.dart';
import '../../data/repositories/payment_order_repository.dart';
import 'payment_gateway.dart';
import 'razorpay_checkout.dart';

const paymentCancelledMessage = 'Payment cancelled.';
const paymentMismatchMessage =
    'The payment window answered for a different order. If money was taken, '
    'contact the resort.';
const unappliedRefundingMessage =
    'Your payment could not be added to this booking, so it is being '
    'refunded in full.';
const unappliedContactMessage =
    'Your payment could not be added to this booking. The resort will '
    'refund it.';

/// Online payments through Razorpay, with no secret in the app (spec
/// decisions 6 and 16):
///  1. `payments-create-order` checks the amount and creates the order --
///     or says online payments are not configured, and [fallback] (the
///     mock) takes the payment exactly as before P6;
///  2. the platform's Razorpay window collects the payment;
///  3. `payments-verify` checks Razorpay's signature and settles the
///     payment server-side (confirms the hold, or checks the guest out).
///
/// The caller's own `confirm_booking` / `checkout_booking` that follows a
/// success then finds the booking already settled and returns it.
class RazorpayGateway implements PaymentGateway {
  const RazorpayGateway({
    required PaymentOrderSource orders,
    required RazorpayCheckout checkout,
    PaymentGateway fallback = const MockGateway(),
  })  : _orders = orders,
        _checkout = checkout,
        _fallback = fallback;

  final PaymentOrderSource _orders;
  final RazorpayCheckout _checkout;
  final PaymentGateway _fallback;

  @override
  Future<PaymentResult> charge({
    required String reservationId,
    required num amount,
    PaymentPurpose purpose = PaymentPurpose.advance,
  }) async {
    final order = await _orders.createOrder(
      reservationId: reservationId,
      amount: amount,
      purpose: purpose,
    );
    switch (order) {
      case PaymentsNotConfigured():
        return _fallback.charge(
          reservationId: reservationId,
          amount: amount,
          purpose: purpose,
        );
      case RazorpayOrder():
        return _pay(order);
    }
  }

  Future<PaymentResult> _pay(RazorpayOrder order) async {
    final outcome = await _checkout.open(CheckoutRequest.fromOrder(order));
    switch (outcome) {
      case CheckoutDismissed():
        return const PaymentResult.failure(paymentCancelledMessage);
      case CheckoutFailed(:final message):
        return PaymentResult.failure(message);
      case CheckoutSucceeded():
        if (outcome.orderId != order.orderId) {
          return const PaymentResult.failure(paymentMismatchMessage);
        }
        final verified = await _orders.verify(
          orderId: order.orderId,
          paymentId: outcome.paymentId,
          signature: outcome.signature,
        );
        return switch (verified.outcome) {
          VerifyOutcome.paid => PaymentResult.success(outcome.paymentId),
          VerifyOutcome.unapplied => PaymentResult.failure(
              verified.refund == RefundState.initiated
                  ? unappliedRefundingMessage
                  : unappliedContactMessage),
        };
    }
  }
}
