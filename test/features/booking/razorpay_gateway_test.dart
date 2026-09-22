import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/features/booking/payment_gateway.dart';
import 'package:pasala/features/booking/razorpay_gateway.dart';

// I7: `paymentGatewayProvider` selects between `MockGateway` and
// `RazorpayGateway` based on `--dart-define` compile-time constants, which
// a plain `flutter test` run can never set per-test -- so, before this fix,
// nothing here ever exercised the branch that actually returns a
// `RazorpayGateway`. Deleting that branch entirely (`if (keyId.isEmpty)
// return const MockGateway(); return const MockGateway();`, say) would have
// passed every test in this file identically. `resolvePaymentGateway` is
// the same selection logic pulled out of the provider specifically so it
// can be called directly with any keyId/keySecret, positive branch
// included.

void main() {
  group('RazorpayGateway configuration', () {
    test('an empty key id throws a clear configuration error at '
        'construction time, not silently at charge time', () {
      expect(
        () => RazorpayGateway(keyId: '', keySecret: 'secret'),
        throwsA(isA<RazorpayConfigurationError>().having(
          (e) => e.message,
          'message',
          contains('key id'),
        )),
      );
    });

    test('a whitespace-only key id is treated as empty', () {
      expect(
        () => RazorpayGateway(keyId: '   ', keySecret: 'secret'),
        throwsA(isA<RazorpayConfigurationError>()),
      );
    });

    test('an empty key secret throws a clear configuration error too', () {
      expect(
        () => RazorpayGateway(keyId: 'rzp_test_123', keySecret: ''),
        throwsA(isA<RazorpayConfigurationError>().having(
          (e) => e.message,
          'message',
          contains('key secret'),
        )),
      );
    });

    test('a valid-looking key does not throw at construction', () {
      expect(
        () => RazorpayGateway(keyId: 'rzp_test_123', keySecret: 'shh'),
        returnsNormally,
      );
    });

    test('RazorpayConfigurationError.toString includes the message', () {
      const error = RazorpayConfigurationError('boom');
      expect(error.toString(), contains('boom'));
    });
  });

  group('paymentGatewayProvider', () {
    test('resolves to MockGateway when no Razorpay key is defined via '
        '--dart-define -- a misconfigured build cannot quietly take fake '
        'payments in production', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final gateway = container.read(paymentGatewayProvider);

      expect(gateway, isA<MockGateway>());
      expect(gateway, isNot(isA<RazorpayGateway>()));
    });
  });

  group('resolvePaymentGateway (I7: the positive branch)', () {
    test('an empty key id resolves to MockGateway', () {
      final gateway =
          resolvePaymentGateway(keyId: '', keySecret: 'irrelevant');
      expect(gateway, isA<MockGateway>());
    });

    test(
        'a non-empty key id resolves to a REAL RazorpayGateway, not '
        'MockGateway -- the branch a build with a real merchant account '
        'actually depends on', () {
      final gateway = resolvePaymentGateway(
        keyId: 'rzp_test_123',
        keySecret: 'shh',
      );

      expect(gateway, isA<RazorpayGateway>());
      expect(gateway, isNot(isA<MockGateway>()));
    });
  });
}
