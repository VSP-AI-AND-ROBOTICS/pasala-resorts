import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/data/models/payment_order.dart';
import 'package:pasala/features/booking/razorpay_checkout.dart';

void main() {
  test('PaymentPurpose uses the payment_kind wire values', () {
    expect(PaymentPurpose.advance.wire, 'advance');
    expect(PaymentPurpose.balance.wire, 'balance');
  });

  test('configured:false is PaymentsNotConfigured', () {
    expect(
      CreateOrderResult.fromJson({'configured': false}),
      isA<PaymentsNotConfigured>(),
    );
  });

  test('a created order reads every field payments-create-order sends', () {
    final result = CreateOrderResult.fromJson({
      'configured': true,
      'key_id': 'rzp_test_fixture',
      'order_id': 'order_P6test0001',
      'amount': 500000,
      'currency': 'INR',
      'name': 'Online A',
      'description': 'Online A: booking advance',
      'reservation_id': 'r1',
      'prefill': {
        'name': 'Gita Guest',
        'email': 'gita@example.com',
        'contact': null,
      },
    });

    expect(result, isA<RazorpayOrder>());
    final order = result as RazorpayOrder;
    expect(order.keyId, 'rzp_test_fixture');
    expect(order.orderId, 'order_P6test0001');
    expect(order.amountPaise, 500000);
    expect(order.currency, 'INR');
    expect(order.name, 'Online A');
    expect(order.description, 'Online A: booking advance');
    expect(order.reservationId, 'r1');
    expect(order.prefillName, 'Gita Guest');
    expect(order.prefillEmail, 'gita@example.com');
    expect(order.prefillContact, isNull);
  });

  test('VerifyResult reads paid and unapplied with the refund state', () {
    final paid = VerifyResult.fromJson({
      'configured': true,
      'outcome': 'paid',
      'reservation_id': 'r1',
      'refund': null,
    });
    expect(paid.outcome, VerifyOutcome.paid);
    expect(paid.reservationId, 'r1');
    expect(paid.refund, isNull);

    final unapplied = VerifyResult.fromJson({
      'configured': true,
      'outcome': 'unapplied',
      'reservation_id': 'r1',
      'refund': 'initiated',
    });
    expect(unapplied.outcome, VerifyOutcome.unapplied);
    expect(unapplied.refund, RefundState.initiated);
  });

  test('an outcome the app does not know is never read as paid', () {
    final result = VerifyResult.fromJson({
      'configured': true,
      'outcome': 'something-new',
      'reservation_id': 'r1',
    });
    expect(result.outcome, VerifyOutcome.unapplied);
  });

  test('CheckoutRequest.fromOrder copies the order', () {
    const order = RazorpayOrder(
      keyId: 'rzp_test_fixture',
      orderId: 'order_1',
      amountPaise: 300000,
      currency: 'INR',
      name: 'Online A',
      description: 'Online A: stay balance',
      reservationId: 'r2',
      prefillContact: '+919800000001',
    );
    final request = CheckoutRequest.fromOrder(order);
    expect(request.keyId, 'rzp_test_fixture');
    expect(request.orderId, 'order_1');
    expect(request.amountPaise, 300000);
    expect(request.description, 'Online A: stay balance');
    expect(request.prefillContact, '+919800000001');
    expect(request.prefillName, isNull);
  });

  test('the unsupported checkout says so instead of pretending', () async {
    final outcome = await const UnsupportedRazorpayCheckout().open(
      CheckoutRequest.fromOrder(
        const RazorpayOrder(
          keyId: 'k',
          orderId: 'o',
          amountPaise: 100,
          currency: 'INR',
          name: 'n',
          description: 'd',
          reservationId: 'r',
        ),
      ),
    );
    expect(outcome, isA<CheckoutFailed>());
    expect(
      (outcome as CheckoutFailed).message,
      'Online payment is not available on this device.',
    );
  });
}
