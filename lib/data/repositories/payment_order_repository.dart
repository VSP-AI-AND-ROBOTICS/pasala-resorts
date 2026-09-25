import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase_client.dart';
import '../models/payment_order.dart';

/// Calls one Edge Function by name with a JSON body. In the app this is
/// `supabase.functions.invoke`; tests pass a fake.
typedef FunctionInvoker =
    Future<FunctionResponse> Function(
      String functionName,
      Map<String, dynamic> body,
    );

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
/// `payments-verify` Edge Functions.
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
  }) => throw UnimplementedError('PaymentFunctionsSource.createOrder: Task 9');

  @override
  Future<VerifyResult> verify({
    required String orderId,
    required String paymentId,
    required String signature,
  }) => throw UnimplementedError('PaymentFunctionsSource.verify: Task 9');
}

final paymentOrderSourceProvider = Provider<PaymentOrderSource>((ref) {
  final db = ref.watch(supabaseProvider);
  return PaymentFunctionsSource(
    (name, body) => db.functions.invoke(name, body: body),
  );
});
