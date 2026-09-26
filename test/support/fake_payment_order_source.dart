import 'package:pasala/data/models/payment_order.dart';
import 'package:pasala/data/repositories/payment_order_repository.dart';

/// A [PaymentOrderSource] with scripted answers and call logs.
class FakePaymentOrderSource implements PaymentOrderSource {
  CreateOrderResult createResult = const PaymentsNotConfigured();
  Object? createError;
  VerifyResult verifyResult = const VerifyResult(
    outcome: VerifyOutcome.paid,
    reservationId: 'r1',
  );
  Object? verifyError;

  final createCalls =
      <({String reservationId, num amount, PaymentPurpose purpose})>[];
  final verifyCalls =
      <({String orderId, String paymentId, String signature})>[];

  @override
  Future<CreateOrderResult> createOrder({
    required String reservationId,
    required num amount,
    required PaymentPurpose purpose,
  }) async {
    createCalls.add((
      reservationId: reservationId,
      amount: amount,
      purpose: purpose,
    ));
    if (createError != null) throw createError!;
    return createResult;
  }

  @override
  Future<VerifyResult> verify({
    required String orderId,
    required String paymentId,
    required String signature,
  }) async {
    verifyCalls.add((
      orderId: orderId,
      paymentId: paymentId,
      signature: signature,
    ));
    if (verifyError != null) throw verifyError!;
    return verifyResult;
  }
}

RazorpayOrder razorpayOrder({
  String orderId = 'order_P6test0001',
  int amountPaise = 500000,
  String reservationId = 'r1',
}) => RazorpayOrder(
  keyId: 'rzp_test_fixture',
  orderId: orderId,
  amountPaise: amountPaise,
  currency: 'INR',
  name: 'Online A',
  description: 'Online A: booking advance',
  reservationId: reservationId,
  prefillName: 'Gita Guest',
  prefillEmail: 'gita@example.com',
);
