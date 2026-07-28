import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/features/booking/payment_gateway.dart';

void main() {
  test('mock gateway succeeds and returns a reference', () async {
    final result = await MockGateway(latency: Duration.zero)
        .charge(reservationId: 'c1', amount: 11500);

    expect(result.succeeded, isTrue);
    expect(result.reference, startsWith('mock_'));
    expect(result.reference, contains('c1'));
  });

  test('mock gateway can be configured to fail', () async {
    final result = await MockGateway(alwaysFail: true, latency: Duration.zero)
        .charge(reservationId: 'c1', amount: 11500);

    expect(result.succeeded, isFalse);
    expect(result.failureMessage, isNotNull);
  });
}
