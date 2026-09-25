import 'dart:convert';

import 'package:http/http.dart' as http;

import 'payment_gateway.dart';

/// Thrown by [RazorpayGateway]'s constructor when it is given no key.
///
/// This is the whole point of validating in the constructor rather than in
/// [RazorpayGateway.charge]: a misconfigured deployment (a build that
/// somehow ends up selecting this gateway with an empty key) fails loudly
/// and immediately, at the moment the object is built, instead of quietly
/// accepting `charge()` calls it can never actually complete.
class RazorpayConfigurationError implements Exception {
  const RazorpayConfigurationError(this.message);

  final String message;

  @override
  String toString() => 'RazorpayConfigurationError: $message';
}

/// The real gateway phase 2 was scoped to add, written against Razorpay's
/// documented Orders API (`POST /v1/orders`, HTTP Basic Auth with
/// `key_id:key_secret`, amount in paise) -- but there is no live Razorpay
/// merchant account to run it against, and completing an actual charge also
/// needs the native `razorpay_flutter` checkout SDK (platform channels,
/// Android/iOS project wiring) that this app does not depend on. Shipping
/// something that merely LOOKS like a working charge would violate the
/// honesty constraint this phase is built on (see docs/STATUS.md), so
/// [charge] goes exactly as far as it honestly can -- creating a real order
/// through the real API shape -- and then fails loudly rather than treating
/// a created order (money not yet moved) as a captured payment.
///
/// [paymentGatewayProvider] in `payment_gateway.dart` only ever selects this
/// class when a non-empty `RAZORPAY_KEY_ID` is supplied via `--dart-define`.
/// Nothing in this repository's build configuration, README, or CI does
/// that, so [MockGateway] stays the default in every build this repo
/// produces today. Enabling this gateway for real is an owner decision that
/// requires a merchant account (see docs/STATUS.md) -- it is not a flag this
/// codebase flips on its own.
class RazorpayGateway implements PaymentGateway {
  RazorpayGateway({
    required String keyId,
    required String keySecret,
    http.Client? client,
  })  : _keyId = keyId,
        _keySecret = keySecret,
        _client = client ?? http.Client() {
    if (_keyId.trim().isEmpty) {
      throw const RazorpayConfigurationError(
          'RazorpayGateway requires a non-empty Razorpay key id. Configure '
          'RAZORPAY_KEY_ID (and RAZORPAY_KEY_SECRET) via --dart-define '
          'before this gateway can be selected -- see docs/STATUS.md.');
    }
    if (_keySecret.trim().isEmpty) {
      throw const RazorpayConfigurationError(
          'RazorpayGateway requires a non-empty Razorpay key secret. '
          'Configure RAZORPAY_KEY_SECRET via --dart-define before this '
          'gateway can be selected -- see docs/STATUS.md.');
    }
  }

  final String _keyId;
  final String _keySecret;
  final http.Client _client;

  static const _ordersUrl = 'https://api.razorpay.com/v1/orders';

  @override
  Future<PaymentResult> charge({
    required String reservationId,
    required num amount,
    PaymentPurpose purpose = PaymentPurpose.advance,
  }) async {
    final auth = base64Encode(utf8.encode('$_keyId:$_keySecret'));
    http.Response response;
    try {
      response = await _client.post(
        Uri.parse(_ordersUrl),
        headers: {
          'Authorization': 'Basic $auth',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          // Razorpay amounts are always the smallest currency unit --
          // paise, not rupees.
          'amount': (amount * 100).round(),
          'currency': 'INR',
          'receipt': reservationId,
        }),
      );
    } finally {
      _client.close();
    }

    if (response.statusCode != 200) {
      return PaymentResult.failure(
          'Razorpay order creation failed (${response.statusCode}): '
          '${response.body}');
    }

    // A created order is not a captured payment -- no money has moved.
    // Actually collecting card/UPI/netbanking details and capturing the
    // charge requires Razorpay's native checkout SDK, which this app does
    // not integrate. Returning PaymentResult.success here would be exactly
    // the "looks live but isn't" outcome this phase forbids, so this fails
    // loudly instead of pretending the order is the charge.
    throw UnimplementedError(
        'RazorpayGateway created a Razorpay order but cannot complete '
        'checkout: no Razorpay checkout SDK is integrated into this app, '
        'and this gateway is not enabled. See docs/STATUS.md.');
  }
}
