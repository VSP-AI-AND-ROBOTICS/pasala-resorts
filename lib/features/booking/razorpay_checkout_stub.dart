import 'razorpay_checkout.dart';

/// Any platform with no Razorpay SDK wired up.
RazorpayCheckout createRazorpayCheckout() =>
    const UnsupportedRazorpayCheckout();
