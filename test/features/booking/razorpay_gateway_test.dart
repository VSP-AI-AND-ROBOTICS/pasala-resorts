import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/errors.dart';
import 'package:pasala/data/models/payment_order.dart';
import 'package:pasala/data/repositories/payment_order_repository.dart';
import 'package:pasala/features/booking/payment_gateway.dart';
import 'package:pasala/features/booking/razorpay_checkout.dart';
import 'package:pasala/features/booking/razorpay_gateway.dart';

import '../../support/fake_payment_order_source.dart';
import '../../support/fake_razorpay_checkout.dart';

/// Records what the gateway delegated to it.
class _RecordingFallback implements PaymentGateway {
  final calls = <({String reservationId, num amount, PaymentPurpose purpose})>[];

  @override
  Future<PaymentResult> charge({
    required String reservationId,
    required num amount,
    PaymentPurpose purpose = PaymentPurpose.advance,
  }) async {
    calls.add((reservationId: reservationId, amount: amount, purpose: purpose));
    return const PaymentResult.success('mock_fallback');
  }
}

const _succeeded = CheckoutSucceeded(
  paymentId: 'pay_P6test0001',
  orderId: 'order_P6test0001',
  signature: 'sig',
);

void main() {
  late FakePaymentOrderSource orders;
  late FakeRazorpayCheckout checkout;
  late _RecordingFallback fallback;
  late RazorpayGateway gateway;

  setUp(() {
    orders = FakePaymentOrderSource();
    checkout = FakeRazorpayCheckout();
    fallback = _RecordingFallback();
    gateway = RazorpayGateway(orders: orders, checkout: checkout, fallback: fallback);
  });

  test('without Razorpay keys the mock takes the payment, exactly as before',
      () async {
    orders.createResult = const PaymentsNotConfigured();

    final result = await gateway.charge(reservationId: 'r1', amount: 5000);

    expect(result.reference, 'mock_fallback');
    expect(fallback.calls,
        [(reservationId: 'r1', amount: 5000, purpose: PaymentPurpose.advance)]);
    expect(checkout.requests, isEmpty);
  });

  test('the order is created for the amount and purpose asked', () async {
    await gateway.charge(
        reservationId: 'r2', amount: 3000, purpose: PaymentPurpose.balance);
    expect(orders.createCalls,
        [(reservationId: 'r2', amount: 3000, purpose: PaymentPurpose.balance)]);
  });

  test('a created order opens the payment window with its details', () async {
    orders.createResult = razorpayOrder();
    await gateway.charge(reservationId: 'r1', amount: 5000);

    final request = checkout.requests.single;
    expect(request.keyId, 'rzp_test_fixture');
    expect(request.orderId, 'order_P6test0001');
    expect(request.amountPaise, 500000);
    expect(request.name, 'Online A');
    expect(request.prefillEmail, 'gita@example.com');
    expect(fallback.calls, isEmpty);
  });

  test('a paid window is verified and its payment id is the reference',
      () async {
    orders.createResult = razorpayOrder();
    checkout.outcome = _succeeded;

    final result = await gateway.charge(reservationId: 'r1', amount: 5000);

    expect(orders.verifyCalls, [
      (orderId: 'order_P6test0001', paymentId: 'pay_P6test0001', signature: 'sig')
    ]);
    expect(result.succeeded, isTrue);
    expect(result.reference, 'pay_P6test0001');
  });

  test('closing the window is a cancelled payment and nothing is verified',
      () async {
    orders.createResult = razorpayOrder();
    checkout.outcome = const CheckoutDismissed();

    final result = await gateway.charge(reservationId: 'r1', amount: 5000);

    expect(result.succeeded, isFalse);
    expect(result.failureMessage, 'Payment cancelled.');
    expect(orders.verifyCalls, isEmpty);
  });

  test("a failed window passes on the window's message", () async {
    orders.createResult = razorpayOrder();
    checkout.outcome = const CheckoutFailed('Network error during payment. Try again.');

    final result = await gateway.charge(reservationId: 'r1', amount: 5000);

    expect(result.failureMessage, 'Network error during payment. Try again.');
  });

  test('an answer for another order is never verified', () async {
    orders.createResult = razorpayOrder();
    checkout.outcome = const CheckoutSucceeded(
        paymentId: 'pay_x', orderId: 'order_other', signature: 'sig');

    final result = await gateway.charge(reservationId: 'r1', amount: 5000);

    expect(result.succeeded, isFalse);
    expect(orders.verifyCalls, isEmpty);
  });

  test('an unapplied payment fails with the refund message', () async {
    orders
      ..createResult = razorpayOrder()
      ..verifyResult = const VerifyResult(
          outcome: VerifyOutcome.unapplied,
          reservationId: 'r1',
          refund: RefundState.initiated);
    checkout.outcome = _succeeded;

    final refunding = await gateway.charge(reservationId: 'r1', amount: 5000);
    expect(refunding.succeeded, isFalse);
    expect(refunding.failureMessage,
        'Your payment could not be added to this booking, so it is being refunded in full.');

    orders.verifyResult = const VerifyResult(
        outcome: VerifyOutcome.unapplied,
        reservationId: 'r1',
        refund: RefundState.failed);
    final contact = await gateway.charge(reservationId: 'r1', amount: 5000);
    expect(contact.failureMessage,
        'Your payment could not be added to this booking. The resort will refund it.');
  });

  test('a payment Razorpay has not captured is not confirmed yet', () async {
    orders
      ..createResult = razorpayOrder()
      ..verifyResult = const VerifyResult(
          outcome: VerifyOutcome.pending, reservationId: 'r1');
    checkout.outcome = _succeeded;

    final result = await gateway.charge(reservationId: 'r1', amount: 5000);

    expect(result.succeeded, isFalse);
    expect(result.failureMessage, paymentNotConfirmedYetMessage);
  });

  test("the server's refusals reach the caller as BookingFailures", () async {
    orders.createError = const HoldExpired();
    await expectLater(gateway.charge(reservationId: 'r1', amount: 5000),
        throwsA(isA<HoldExpired>()));

    orders
      ..createError = null
      ..createResult = razorpayOrder()
      ..verifyError = const InvalidState(paymentNotConfirmedYetMessage);
    checkout.outcome = _succeeded;
    await expectLater(gateway.charge(reservationId: 'r1', amount: 5000),
        throwsA(isA<InvalidState>()));
  });

  group('paymentGatewayProvider', () {
    test('always builds a RazorpayGateway, which falls back to the real mock',
        () async {
      final container = ProviderContainer(overrides: [
        paymentOrderSourceProvider.overrideWithValue(FakePaymentOrderSource()),
        razorpayCheckoutProvider.overrideWithValue(FakeRazorpayCheckout()),
      ]);
      addTearDown(container.dispose);

      final gateway = container.read(paymentGatewayProvider);
      expect(gateway, isA<RazorpayGateway>());

      final result = await gateway.charge(reservationId: 'c1', amount: 11500);
      expect(result.reference, 'mock_c1_11500');
    });
  });
}
