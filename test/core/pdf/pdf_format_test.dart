import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/pdf/pdf_format.dart';

void main() {
  test('pdfMoney keeps paise, the rupee sign and Indian grouping', () {
    expect(pdfMoney(1080), '₹1,080.00');
    expect(pdfMoney(123456.5), '₹1,23,456.50');
    expect(pdfMoney(0), '₹0.00');
    final negative = pdfMoney(-1000);
    expect(negative.startsWith('-'), isTrue);
    expect(negative, contains('1,000.00'));
  });

  test('pdfDate prints d MMM yyyy', () {
    expect(pdfDate(DateTime(2026, 8, 12, 11)), '12 Aug 2026');
  });
}
