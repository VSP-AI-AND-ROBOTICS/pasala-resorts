// Picks the Razorpay payment window for the platform being compiled:
// Checkout.js on the web, razorpay_flutter on Android/iOS (other native
// platforms get UnsupportedRazorpayCheckout from the mobile file), and a
// stub anywhere else. dart.library.js_interop is the web test, as in
// lib/features/reports/csv_download.dart.
export 'razorpay_checkout_stub.dart'
    if (dart.library.js_interop) 'razorpay_checkout_web.dart'
    if (dart.library.io) 'razorpay_checkout_mobile.dart';
