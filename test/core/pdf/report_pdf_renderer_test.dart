import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/pdf/report_pdf.dart';
import 'package:pasala/core/pdf/report_pdf_renderer.dart';

import '../../support/pdf_test_fonts.dart';

ReportPdf _report(List<List<String>> rows, {List<String>? totals}) => ReportPdf(
  title: 'Settlements',
  resortName: 'Resort R',
  gstinLabel: 'GSTIN 29ABCDE1234F1Z5',
  periodLabel: '1 Aug 2026 – 31 Aug 2026',
  fileName: 'fin-r-settlements-2026-08-01-2026-08-31.pdf',
  columns: const [
    ReportPdfColumn('Guest', flex: 2),
    ReportPdfColumn('Total', numeric: true),
  ],
  rows: rows,
  totals: totals,
  notes: const ['Tax by category', 'Room: taxable ₹9,000.00, tax ₹1,080.00'],
);

List<List<String>> _rows(int n) => [
  for (var i = 0; i < n; i++) ['Guest $i', '₹1,000.00'],
];

void main() {
  final fonts = testPdfFonts();

  test('a short report is a one-page PDF', () async {
    final doc = buildReportDocument(
      _report(_rows(3), totals: ['Total', '₹3,000.00']),
      fonts,
      generatedAt: DateTime(2026, 9, 25, 10),
    );
    final bytes = await doc.save();
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    expect(doc.document.pdfPageList.pages, hasLength(1));
  });

  test(
    'long reports run to many pages past the default 20-page limit',
    () async {
      final doc = buildReportDocument(_report(_rows(800)), fonts);
      await doc.save();
      expect(doc.document.pdfPageList.pages.length, greaterThan(20));
    },
  );

  test('an empty report is one page with its message', () async {
    final doc = buildReportDocument(_report(const []), fonts);
    await doc.save();
    expect(doc.document.pdfPageList.pages, hasLength(1));
  });

  test('a row with the wrong number of cells is a programming error', () {
    expect(
      () => buildReportDocument(
        _report(const [
          ['only one'],
        ]),
        fonts,
      ),
      throwsArgumentError,
    );
    expect(
      () => buildReportDocument(
        _report(_rows(1), totals: const ['Total']),
        fonts,
      ),
      throwsArgumentError,
    );
  });

  test('text the font cannot draw does not break the document', () async {
    final bytes = await renderReportPdf(
      _report(const [
        ['सीता 🌸', '₹1.00'],
      ]),
      fonts,
    );
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });
}
