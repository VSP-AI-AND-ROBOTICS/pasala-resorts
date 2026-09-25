import 'package:flutter_test/flutter_test.dart';

import '../support/fake_invoice_source.dart';

void main() {
  test('totals add up the lines', () {
    final invoice = sampleInvoice();
    expect(invoice.subtotal, 11300);
    expect(invoice.taxTotal, 1360);
    expect(invoice.total, 12660);
    expect(invoice.advancePaid, 3192);
  });

  test('title and file name', () {
    expect(sampleInvoice().title, 'Invoice');
    expect(sampleInvoice(provisional: true).title, 'Provisional bill');
    expect(sampleInvoice().fileName, 'invoice-FIN-R-3F2A9C1B.pdf');
  });

  test('a line total is its amount plus its tax', () {
    final room = sampleInvoice().lines.first;
    expect(room.total, 11080);
  });
}
