import 'package:pasala/features/booking/razorpay_checkout.dart';

/// A payment window that answers [outcome] immediately and logs requests.
class FakeRazorpayCheckout implements RazorpayCheckout {
  FakeRazorpayCheckout([this.outcome = const CheckoutDismissed()]);

  CheckoutOutcome outcome;
  final requests = <CheckoutRequest>[];

  @override
  Future<CheckoutOutcome> open(CheckoutRequest request) async {
    requests.add(request);
    return outcome;
  }
}
