import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/models/reservation.dart';
import 'package:pasala/core/models/payment.dart';
import 'package:pasala/features/payments/payment_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('Demo Payment Gateway Idempotency Tests', () {
    late DemoPaymentGateway paymentGateway;

    setUp(() {
      paymentGateway = DemoPaymentGateway();
    });

    test('Duplicate processing requests with identical idempotency key return cached success without duplicate records', () async {
      final reservation = Reservation(
        id: 'res-idemp-101',
        resortId: 'resort-grand-palms',
        customerId: 'usr-customer',
        unitId: 'unit-gp-101',
        checkIn: DateTime.now().add(const Duration(days: 1)),
        checkOut: DateTime.now().add(const Duration(days: 3)),
        totalAmount: 1000.0,
        advanceAmount: 350.0,
        status: ReservationStatus.pending,
        guestName: 'Idempotent Tester',
        guestPhone: '1234567890',
        guestEmail: 'test@idemp.com',
        guestCount: 2,
        createdAt: DateTime.now(),
      );

      const idempotencyKey = 'unique-idempotency-key-999';

      // First call
      final result1 = await paymentGateway.processBookingPayment(
        reservation: reservation,
        amount: 350.0,
        paymentKind: PaymentKind.advance,
        idempotencyKey: idempotencyKey,
        paymentMethod: 'card',
      );

      expect(result1.isSuccess, isTrue);
      expect(result1.idempotencyKey, idempotencyKey);

      // Replay identical call with same idempotency key
      final result2 = await paymentGateway.processBookingPayment(
        reservation: reservation,
        amount: 350.0,
        paymentKind: PaymentKind.advance,
        idempotencyKey: idempotencyKey,
        paymentMethod: 'card',
      );

      expect(result2.isSuccess, isTrue);
      expect(result2.transactionRef, equals(result1.transactionRef));
      expect(result2.idempotencyKey, equals(result1.idempotencyKey));
    });
  });
}
