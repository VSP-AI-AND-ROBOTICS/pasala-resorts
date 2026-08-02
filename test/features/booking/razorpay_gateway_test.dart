import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/features/booking/payment_gateway.dart';
import 'package:pasala/features/booking/razorpay_gateway.dart';

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
}
