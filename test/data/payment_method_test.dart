import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/data/models/payment_method.dart';

void main() {
  test('wire values match the Postgres enum, in order', () {
    expect(PaymentMethod.values.map((m) => m.wire).toList(), [
      'gateway',
      'cash',
      'card',
      'upi',
      'bank_transfer',
      'other',
    ]);
  });

  test('fromWire round-trips every value', () {
    for (final m in PaymentMethod.values) {
      expect(PaymentMethod.fromWire(m.wire), m);
    }
  });

  test('unknown or missing text is Other', () {
    expect(PaymentMethod.fromWire('cheque'), PaymentMethod.other);
    expect(PaymentMethod.fromWire(null), PaymentMethod.other);
  });

  test('desk is every method but gateway, Cash first', () {
    expect(PaymentMethod.desk, [
      PaymentMethod.cash,
      PaymentMethod.card,
      PaymentMethod.upi,
      PaymentMethod.bankTransfer,
      PaymentMethod.other,
    ]);
  });

  test('every method has its own label and icon', () {
    expect(PaymentMethod.values.map((m) => m.label).toList(), [
      'Online',
      'Cash',
      'Card',
      'UPI',
      'Bank transfer',
      'Other',
    ]);
    expect(PaymentMethod.values.map((m) => m.icon).toSet(), hasLength(6));
  });
}
