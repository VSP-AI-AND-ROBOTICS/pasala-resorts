import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import 'razorpay_checkout.dart';

/// Razorpay's hosted Checkout script. Injected on first use only, so a
/// deployment without Razorpay keys never loads anything from Razorpay.
const checkoutScriptUrl = 'https://checkout.razorpay.com/v1/checkout.js';

RazorpayCheckout createRazorpayCheckout() => WebRazorpayCheckout();

@JS('Razorpay')
extension type _Razorpay._(JSObject _) implements JSObject {
  external factory _Razorpay(JSObject options);
  external void open();
  external void on(String event, JSFunction handler);
}

/// Razorpay Checkout.js through `dart:js_interop`.
class WebRazorpayCheckout implements RazorpayCheckout {
  static Future<void>? _loading;

  static Future<void> _ensureLoaded() {
    if (globalContext.has('Razorpay')) return Future.value();
    return _loading ??= _inject();
  }

  static Future<void> _inject() async {
    final loaded = Completer<void>();
    final script = web.HTMLScriptElement()
      ..src = checkoutScriptUrl
      ..async = true;
    script.onload = ((web.Event _) {
      if (!loaded.isCompleted) loaded.complete();
    }).toJS;
    script.onerror = ((web.Event _) {
      if (!loaded.isCompleted) {
        loaded.completeError(StateError('checkout.js failed to load'));
      }
    }).toJS;
    web.document.head!.append(script);
    try {
      await loaded.future.timeout(const Duration(seconds: 20));
    } catch (_) {
      _loading = null; // the next payment tries again
      script.remove();
      rethrow;
    }
  }

  @override
  Future<CheckoutOutcome> open(CheckoutRequest request) async {
    try {
      await _ensureLoaded();
    } catch (_) {
      return const CheckoutFailed(checkoutLoadFailedMessage);
    }

    final result = Completer<CheckoutOutcome>();
    String? lastError;

    final options = checkoutOptions(request).jsify()! as JSObject;
    options['handler'] = ((JSObject response) {
      final data = (response.dartify() as Map?) ?? const {};
      final paymentId = data['razorpay_payment_id'] as String?;
      final orderId = data['razorpay_order_id'] as String?;
      final signature = data['razorpay_signature'] as String?;
      if (result.isCompleted) return;
      result.complete(paymentId == null || orderId == null || signature == null
          ? const CheckoutFailed(incompleteResponseMessage)
          : CheckoutSucceeded(
              paymentId: paymentId, orderId: orderId, signature: signature));
    }).toJS;
    final modal = JSObject();
    modal['ondismiss'] = (() {
      if (result.isCompleted) return;
      final error = lastError;
      result.complete(
          error == null ? const CheckoutDismissed() : CheckoutFailed(error));
    }).toJS;
    options['modal'] = modal;

    final razorpay = _Razorpay(options);
    // Checkout.js keeps its window open after a failed attempt so the
    // guest can retry; remember why, in case they then close it.
    razorpay.on(
        'payment.failed',
        ((JSObject response) {
          final data = (response.dartify() as Map?) ?? const {};
          final error = data['error'];
          final description = error is Map ? error['description'] : null;
          lastError = description is String && description.trim().isNotEmpty
              ? description
              : paymentFailedMessage;
        }).toJS);
    razorpay.open();
    return result.future;
  }
}
