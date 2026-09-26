import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'pdf_fonts.dart';
import 'pdf_format.dart';
import 'report_pdf.dart';

/// A4 landscape, the resort/title/period on every page, the table header
/// repeated on every page, a bold totals row, notes, and "Page x of y".
/// `maxPages` is raised from pdf's default 20 so a year of settlements
/// still renders.
pw.Document buildReportDocument(
  ReportPdf report,
  PdfFonts fonts, {
  bool compress = true,
  DateTime? generatedAt,
}) {
  final width = report.columns.length;
  for (final row in [
    ...report.rows,
    if (report.totals != null) report.totals!,
  ]) {
    if (row.length != width) {
      throw ArgumentError(
        'Every row needs $width cells, got ${row.length}: $row',
      );
    }
  }
  final s = fonts.safe;
  final at = (generatedAt ?? DateTime.now()).toLocal();
  const small = pw.TextStyle(fontSize: 8);
  final smallBold = pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold);

  pw.Widget cell(String text, ReportPdfColumn column, pw.TextStyle style) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        child: pw.Text(
          s(text),
          style: style,
          textAlign: column.numeric ? pw.TextAlign.right : pw.TextAlign.left,
        ),
      );

  pw.TableRow tableRow(
    List<String> cells,
    pw.TextStyle style, {
    bool repeat = false,
    PdfColor? shade,
  }) => pw.TableRow(
    repeat: repeat,
    decoration: shade == null ? null : pw.BoxDecoration(color: shade),
    children: [
      for (var i = 0; i < cells.length; i++)
        cell(cells[i], report.columns[i], style),
    ],
  );

  final doc = pw.Document(
    compress: compress,
    theme: fonts.theme,
    title: '${report.title} ${report.periodLabel}',
    creator: 'ResortHub',
  );
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.all(28),
      maxPages: 1000,
      header: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            children: [
              pw.Expanded(
                child: pw.Text(
                  s(report.resortName),
                  style: pw.TextStyle(
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
              pw.Text(
                s(report.gstinLabel),
                style: const pw.TextStyle(fontSize: 9),
              ),
            ],
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            s('${report.title} · ${report.periodLabel}'),
            style: const pw.TextStyle(fontSize: 11),
          ),
          pw.SizedBox(height: 8),
        ],
      ),
      footer: (context) => pw.Row(
        children: [
          pw.Expanded(
            child: pw.Text(
              'Generated ${pdfDate(at)} ${DateFormat.Hm().format(at)}',
              style: small,
            ),
          ),
          pw.Text(
            'Page ${context.pageNumber} of ${context.pagesCount}',
            style: small,
          ),
        ],
      ),
      build: (context) => [
        if (report.rows.isEmpty)
          pw.Text(s(report.emptyMessage))
        else
          pw.Table(
            border: pw.TableBorder.all(width: 0.4, color: PdfColors.grey500),
            columnWidths: {
              for (var i = 0; i < width; i++)
                i: pw.FlexColumnWidth(report.columns[i].flex),
            },
            children: [
              tableRow(
                [for (final c in report.columns) c.header],
                smallBold,
                repeat: true,
                shade: PdfColors.grey200,
              ),
              for (final row in report.rows) tableRow(row, small),
              if (report.totals != null)
                tableRow(report.totals!, smallBold, shade: PdfColors.grey100),
            ],
          ),
        if (report.notes.isNotEmpty) ...[
          pw.SizedBox(height: 10),
          for (final note in report.notes)
            pw.Text(s(note), style: const pw.TextStyle(fontSize: 9)),
        ],
      ],
    ),
  );
  return doc;
}

Future<Uint8List> renderReportPdf(
  ReportPdf report,
  PdfFonts fonts, {
  bool compress = true,
  DateTime? generatedAt,
}) => buildReportDocument(
  report,
  fonts,
  compress: compress,
  generatedAt: generatedAt,
).save();
