import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:pasala/core/errors.dart';
import 'package:pasala/data/models/payment_order.dart';
import 'package:pasala/data/repositories/payment_order_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

typedef _Call = (String, Map<String, dynamic>);

PaymentFunctionsSource _answering(Object? data, [List<_Call>? calls]) =>
    PaymentFunctionsSource((name, body) async {
      calls?.add((name, body));
      return FunctionResponse(data: data, status: 200);
    });

PaymentFunctionsSource _throwing(Object error) =>
    PaymentFunctionsSource((name, body) async => throw error);

FunctionException _status(int status, [Object? details]) =>
    FunctionException(status: status, details: details);

Future<CreateOrderResult> _create(PaymentFunctionsSource source) =>
    source.createOrder(
        reservationId: 'r1', amount: 5000, purpose: PaymentPurpose.advance);

Future<VerifyResult> _verify(PaymentFunctionsSource source) => source.verify(
    orderId: 'order_1', paymentId: 'pay_1', signature: 'sig');

void main() {
  group('createOrder', () {
    test('posts the reservation, rupees and purpose to payments-create-order',
        () async {
      final calls = <_Call>[];
      await _answering({'configured': false}, calls).createOrder(
          reservationId: 'r2', amount: 3000, purpose: PaymentPurpose.balance);
      expect(calls.single.$1, 'payments-create-order');
      expect(calls.single.$2,
          {'reservation_id': 'r2', 'amount': 3000, 'purpose': 'balance'});
    });

    test('configured:false means pay through the mock', () async {
      expect(await _create(_answering({'configured': false})),
          isA<PaymentsNotConfigured>());
    });

    test('a created order is read', () async {
      final result = await _create(_answering({
        'configured': true,
        'key_id': 'rzp_test_fixture',
        'order_id': 'order_1',
        'amount': 500000,
        'currency': 'INR',
        'name': 'Online A',
        'description': 'Online A: booking advance',
        'reservation_id': 'r1',
        'prefill': {'name': null, 'email': null, 'contact': null},
      }));
      expect((result as RazorpayOrder).orderId, 'order_1');
    });

    test('a function that is not deployed (404) means the mock', () async {
      expect(await _create(_throwing(_status(404, 'Not Found'))),
          isA<PaymentsNotConfigured>());
    });

    test('a 5xx without our error body (booting) means the mock', () async {
      expect(await _create(_throwing(_status(503, {'code': 'BOOT_ERROR'}))),
          isA<PaymentsNotConfigured>());
    });

    test('an unreachable function (network / CORS) means the mock', () async {
      expect(await _create(_throwing(http.ClientException('XMLHttpRequest error.'))),
          isA<PaymentsNotConfigured>());
    });

    test('our own 5xx is an error, not the mock', () async {
      await expectLater(
          _create(_throwing(_status(500, {'error': 'internal', 'message': 'x'}))),
          throwsA(isA<UnknownFailure>()));
    });

    test('a database refusal maps through its Postgres code', () async {
      await expectLater(
          _create(_throwing(_status(409,
              {'error': 'db', 'code': 'P0006', 'message': 'hold expired'}))),
          throwsA(isA<HoldExpired>()));
      await expectLater(
          _create(_throwing(_status(409, {
            'error': 'db',
            'code': 'P0036',
            'message': 'online_payment_required'
          }))),
          throwsA(isA<OnlinePaymentRequired>()));
    });

    test('a Razorpay outage is a readable InvalidState', () async {
      await expectLater(
          _create(_throwing(_status(502, {'error': 'gateway', 'message': 'x'}))),
          throwsA(isA<InvalidState>().having((e) => e.message, 'message',
              'The payment service is not responding. Try again in a minute.')));
    });

    test('401 is NotPermitted', () async {
      await expectLater(
          _create(_throwing(
              _status(401, {'error': 'unauthorized', 'message': 'Sign in'}))),
          throwsA(isA<NotPermitted>()));
    });
  });

  group('verify', () {
    test('posts the three Checkout values to payments-verify', () async {
      final calls = <_Call>[];
      await _answering({
        'configured': true,
        'outcome': 'paid',
        'reservation_id': 'r1',
        'refund': null,
      }, calls)
          .verify(orderId: 'order_1', paymentId: 'pay_1', signature: 'sig');
      expect(calls.single.$1, 'payments-verify');
      expect(calls.single.$2, {
        'razorpay_order_id': 'order_1',
        'razorpay_payment_id': 'pay_1',
        'razorpay_signature': 'sig',
      });
    });

    test('reads paid and unapplied', () async {
      expect(
          (await _verify(_answering({
            'configured': true,
            'outcome': 'paid',
            'reservation_id': 'r1',
          })))
              .outcome,
          VerifyOutcome.paid);
      final unapplied = await _verify(_answering({
        'configured': true,
        'outcome': 'unapplied',
        'reservation_id': 'r1',
        'refund': 'initiated',
      }));
      expect(unapplied.outcome, VerifyOutcome.unapplied);
      expect(unapplied.refund, RefundState.initiated);
    });

    test('a bad signature is a readable InvalidState', () async {
      await expectLater(
          _verify(_throwing(_status(
              400, {'error': 'invalid_signature', 'message': 'x'}))),
          throwsA(isA<InvalidState>()));
    });

    test('a network error after paying says "not confirmed yet", not failed',
        () async {
      await expectLater(
          _verify(_throwing(http.ClientException('XMLHttpRequest error.'))),
          throwsA(isA<InvalidState>().having(
              (e) => e.message, 'message', paymentNotConfirmedYetMessage)));
    });

    test('Razorpay not answering the verify says "not confirmed yet"',
        () async {
      // The guest may already have paid: "try again" would invite a second
      // payment.
      await expectLater(
          _verify(_throwing(_status(
              502, {'error': 'gateway', 'message': 'x'}))),
          throwsA(isA<InvalidState>().having(
              (e) => e.message, 'message', paymentNotConfirmedYetMessage)));
    });

    test('an unreachable verify function says "not confirmed yet"', () async {
      await expectLater(_verify(_throwing(_status(404))),
          throwsA(isA<InvalidState>().having(
              (e) => e.message, 'message', paymentNotConfirmedYetMessage)));
    });

    test('payments switched off mid-payment says "not confirmed yet"',
        () async {
      await expectLater(_verify(_answering({'configured': false})),
          throwsA(isA<InvalidState>().having(
              (e) => e.message, 'message', paymentNotConfirmedYetMessage)));
    });
  });
}
