import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/pdf/pdf_exporter.dart';
import 'package:pasala/core/pdf/pdf_fonts.dart';
import 'package:pasala/core/pdf/report_pdf.dart';

import '../../support/fake_invoice_source.dart';
import '../../support/pdf_test_fonts.dart';

const _report = ReportPdf(
  title: 'Collections',
  resortName: 'Resort R',
  gstinLabel: 'GSTIN not set',
  periodLabel: '1 Aug 2026 – 31 Aug 2026',
  fileName: 'fin-r-collections-2026-08-01-2026-08-31.pdf',
  columns: [ReportPdfColumn('Date'), ReportPdfColumn('Net', numeric: true)],
  rows: [
    ['1 Aug 2026', '₹5,000.00'],
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('renders invoices and reports, loading the fonts once', () async {
    var loads = 0;
    final exporter = PasalaPdfExporter(
      loadFonts: () async {
        loads++;
        return testPdfFonts();
      },
    );
    final invoice = await exporter.invoice(sampleInvoice());
    final report = await exporter.report(_report);
    expect(String.fromCharCodes(invoice.take(5)), '%PDF-');
    expect(String.fromCharCodes(report.take(5)), '%PDF-');
    expect(loads, 1);
  });

  test('a failed font load is retried on the next export', () async {
    var loads = 0;
    final exporter = PasalaPdfExporter(
      loadFonts: () async {
        loads++;
        if (loads == 1) throw StateError('asset missing');
        return testPdfFonts();
      },
    );
    await expectLater(exporter.report(_report), throwsStateError);
    final bytes = await exporter.report(_report);
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    expect(loads, 2);
  });

  test('the default exporter loads the bundled fonts', () async {
    final bytes = await PasalaPdfExporter().report(_report);
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    expect(await loadPdfFonts(), isA<PdfFonts>());
  });
}
