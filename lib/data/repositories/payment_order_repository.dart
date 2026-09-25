import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors.dart';
import '../../core/supabase_client.dart';
import '../models/payment_order.dart';

/// Calls one Edge Function by name with a JSON body. In the app this is
/// `supabase.functions.invoke`; tests pass a fake.
typedef FunctionInvoker =
    Future<FunctionResponse> Function(
      String functionName,
      Map<String, dynamic> body,
    );

/// Shown when the payment may have gone through but the server could not
/// confirm it: the guest must not pay again blindly. The webhook settles
/// it (spec decision 12).
const paymentNotConfirmedYetMessage =
    'Your payment was received but is not confirmed yet. Check your booking '
    'again in a minute before paying again.';

/// The online-payment calls `RazorpayGateway` makes. Tests override
/// [paymentOrderSourceProvider] with `FakePaymentOrderSource`
/// (test/support/fake_payment_order_source.dart).
abstract interface class PaymentOrderSource {
  /// Asks the server to create a Razorpay order for [amount] rupees, or
  /// learns that online payments are not configured.
  Future<CreateOrderResult> createOrder({
    required String reservationId,
    required num amount,
    required PaymentPurpose purpose,
  });

  /// Hands Razorpay Checkout's answer to the server, which checks the
  /// signature and settles the payment.
  Future<VerifyResult> verify({
    required String orderId,
    required String paymentId,
    required String signature,
  });
}

/// Backs [PaymentOrderSource] with the `payments-create-order` and
/// `payments-verify` Edge Functions. Errors arrive as [BookingFailure]s.
class PaymentFunctionsSource implements PaymentOrderSource {
  PaymentFunctionsSource(this.invoke);

  final FunctionInvoker invoke;

  static const createOrderFunction = 'payments-create-order';
  static const verifyFunction = 'payments-verify';

  @override
  Future<CreateOrderResult> createOrder({
    required String reservationId,
    required num amount,
    required PaymentPurpose purpose,
  }) async {
    final FunctionResponse response;
    try {
      response = await invoke(createOrderFunction, {
        'reservation_id': reservationId,
        'amount': amount,
        'purpose': purpose.wire,
      });
    } on FunctionException catch (e) {
      // Not deployed, or not running: pay as before P6 (spec decision 4).
      if (isFunctionUnavailable(e)) return const PaymentsNotConfigured();
      throw failureFromFunction(e);
    } catch (e) {
      final failure = mapPostgrestError(e);
      // Unreachable (offline, or no functions served, so the browser's CORS
      // preflight failed): the mock again. Safe while online payments are
      // live too -- confirm_booking refuses the mock with P0036.
      if (failure is NetworkFailure) return const PaymentsNotConfigured();
      throw failure;
    }
    return CreateOrderResult.fromJson(_object(response.data));
  }

  @override
  Future<VerifyResult> verify({
    required String orderId,
    required String paymentId,
    required String signature,
  }) async {
    final FunctionResponse response;
    try {
      response = await invoke(verifyFunction, {
        'razorpay_order_id': orderId,
        'razorpay_payment_id': paymentId,
        'razorpay_signature': signature,
      });
    } on FunctionException catch (e) {
      if (isFunctionUnavailable(e)) {
        throw const InvalidState(paymentNotConfirmedYetMessage);
      }
      throw failureFromFunction(e);
    } catch (e) {
      // Razorpay may already have the money: never report this as a
      // failed payment (Review Focus 1).
      final failure = mapPostgrestError(e);
      if (failure is NetworkFailure) {
        throw const InvalidState(paymentNotConfirmedYetMessage);
      }
      throw failure;
    }
    final body = _object(response.data);
    if (body['configured'] != true) {
      throw const InvalidState(paymentNotConfirmedYetMessage);
    }
    return VerifyResult.fromJson(body);
  }
}

Map<String, dynamic> _object(Object? data) => switch (data) {
      final Map<dynamic, dynamic> map => map.cast<String, dynamic>(),
      _ => throw const UnknownFailure('Unexpected answer from payments.'),
    };

/// 404 (not deployed), or a 5xx without the function's own `{"error": …}`
/// body (booting, or the gateway in front of it failed).
bool isFunctionUnavailable(FunctionException e) {
  final details = e.details;
  final ours = details is Map && details['error'] is String;
  return e.status == 404 || (e.status >= 500 && !ours);
}

/// The function's own error bodies (supabase/functions/_shared/http.ts).
BookingFailure failureFromFunction(FunctionException e) {
  final details = e.details is Map
      ? (e.details as Map).cast<String, dynamic>()
      : const <String, dynamic>{};
  return switch (details['error']) {
    'db' => mapPostgrestError(PostgrestException(
        message: details['message'] as String? ?? '',
        code: details['code'] as String?,
      )),
    'unauthorized' => const NotPermitted(),
    'invalid_signature' => const InvalidState(
        'We could not verify this payment. If money was taken, contact the '
        'resort.'),
    'gateway' => const InvalidState(
        'The payment service is not responding. Try again in a minute.'),
    _ => const UnknownFailure('The payment service failed.'),
  };
}

final paymentOrderSourceProvider = Provider<PaymentOrderSource>((ref) {
  final db = ref.watch(supabaseProvider);
  return PaymentFunctionsSource(
      (name, body) => db.functions.invoke(name, body: body));
});
