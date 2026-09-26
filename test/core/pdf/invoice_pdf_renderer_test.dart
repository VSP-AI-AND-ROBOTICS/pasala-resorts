import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/pdf/invoice_pdf_renderer.dart';
import 'package:pasala/data/models/invoice.dart';

import '../../support/fake_invoice_source.dart';
import '../../support/pdf_test_fonts.dart';

void main() {
  final fonts = testPdfFonts();

  test('the sample invoice is a one-page PDF', () async {
    final doc = buildInvoiceDocument(sampleInvoice(), fonts);
    final bytes = await doc.save();
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    expect(doc.document.pdfPageList.pages, hasLength(1));
  });

  test('a provisional bill with notes and no payments renders', () async {
    final bytes = await renderInvoicePdf(
      sampleInvoice(
        provisional: true,
        payments: const [],
        paid: 0,
        amountDue: 12660,
        notes: const [
          'The stay is still in progress, so this bill may change before checkout.',
        ],
      ),
      fonts,
    );
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });

  test('many lines flow onto more pages', () async {
    final doc = buildInvoiceDocument(
      sampleInvoice(
        lines: [
          for (var i = 0; i < 80; i++)
            InvoiceLine(
              kind: InvoiceLineKind.foodDrink,
              label: 'Line $i',
              amount: 10,
            ),
        ],
      ),
      fonts,
    );
    await doc.save();
    expect(doc.document.pdfPageList.pages.length, greaterThan(1));
  });

  test('a guest name in Devanagari still renders', () async {
    final bytes = await renderInvoicePdf(
      sampleInvoice(guestName: 'सीता 🌸'),
      fonts,
    );
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });
}
