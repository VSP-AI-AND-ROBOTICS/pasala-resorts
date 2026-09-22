import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/format.dart';

void main() {
  test('formatInr renders int and numeric(12,2)-style decimal identically', () {
    final fromInt = formatInr(16500);
    final fromDecimal = formatInr(16500.00);

    expect(fromInt, fromDecimal);
    expect(fromInt, '₹16,500');
  });
}
