import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../data/models/invoice.dart';
import '../format.dart';
import 'pdf_fonts.dart';
import 'pdf_format.dart';

/// A4 portrait: the resort (name, address, GSTIN) and the title, number and
/// date; who and what was billed; the charge lines with Amount / Tax /
/// Total; totals; every payment; paid and amount due; notes.
pw.Document buildInvoiceDocument(
  Invoice invoice,
  PdfFonts fonts, {
  bool compress = true,
}) {
  final s = fonts.safe;
  const muted = pw.TextStyle(fontSize: 9, color: PdfColors.grey700);
  const bold = pw.TextStyle(fontWeight: pw.FontWeight.bold);

  String taxCell(InvoiceLine line) {
    if (line.tax == 0) return '—';
    final pct = line.taxPct;
    return pct == null
        ? pdfMoney(line.tax)
        : '${pdfMoney(line.tax)} (${formatPct(pct)}%)';
  }

  pw.Widget cell(String text, {bool right = false, pw.TextStyle? style}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: pw.Text(
          s(text),
          style: style,
          textAlign: right ? pw.TextAlign.right : pw.TextAlign.left,
        ),
      );

  pw.Widget amountRow(String label, String value, {bool strong = false}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.Row(
          children: [
            pw.Expanded(child: pw.Text(s(label), style: strong ? bold : null)),
            pw.Text(s(value), style: strong ? bold : null),
          ],
        ),
      );

  String paymentLabel(InvoicePayment p) => [
    p.kind.label,
    p.method.label,
    if (p.reference != null) 'Ref ${p.reference}',
    pdfDate(p.paidAt),
  ].join(' · ');

  final doc = pw.Document(
    compress: compress,
    theme: fonts.theme,
    title: '${invoice.title} ${invoice.number}',
    creator: 'ResortHub',
  );
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(36),
      maxPages: 50,
      footer: (context) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text(
          'Page ${context.pageNumber} of ${context.pagesCount}',
          style: muted,
        ),
      ),
      build: (context) => [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    s(invoice.resortName),
                    style: pw.TextStyle(
                      fontSize: 16,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  if (invoice.resortAddress != null)
                    pw.Text(s(invoice.resortAddress!), style: muted),
                  pw.Text(
                    s(
                      invoice.gstin == null
                          ? 'GSTIN not set'
                          : 'GSTIN ${invoice.gstin}',
                    ),
                    style: muted,
                  ),
                ],
              ),
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text(
                  invoice.title.toUpperCase(),
                  style: pw.TextStyle(
                    fontSize: 18,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.Text(s('No. ${invoice.number}')),
                pw.Text('Date ${pdfDate(invoice.issuedAt)}'),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 18),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('BILLED TO', style: muted),
                  pw.Text(s(invoice.guestName), style: bold),
                ],
              ),
            ),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('STAY', style: muted),
                  if (invoice.unitName != null)
                    pw.Text(s(invoice.unitName!), style: bold),
                  pw.Text(
                    '${pdfDate(invoice.stayStart)} – ${pdfDate(invoice.stayEnd)}',
                  ),
                  if (invoice.guests != null)
                    pw.Text('${invoice.guests} guests'),
                ],
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 18),
        pw.Table(
          border: pw.TableBorder.all(width: 0.4, color: PdfColors.grey400),
          columnWidths: const {
            0: pw.FlexColumnWidth(3),
            1: pw.FlexColumnWidth(1.4),
            2: pw.FlexColumnWidth(1.6),
            3: pw.FlexColumnWidth(1.4),
          },
          children: [
            pw.TableRow(
              repeat: true,
              decoration: const pw.BoxDecoration(color: PdfColors.grey200),
              children: [
                cell('Description', style: bold),
                cell('Amount', right: true, style: bold),
                cell('Tax', right: true, style: bold),
                cell('Total', right: true, style: bold),
              ],
            ),
            for (final line in invoice.lines)
              pw.TableRow(
                children: [
                  cell(line.label),
                  cell(pdfMoney(line.amount), right: true),
                  cell(taxCell(line), right: true),
                  cell(pdfMoney(line.total), right: true),
                ],
              ),
          ],
        ),
        pw.SizedBox(height: 10),
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.SizedBox(
            width: 240,
            child: pw.Column(
              children: [
                amountRow('Subtotal (excl. tax)', pdfMoney(invoice.subtotal)),
                amountRow('Tax', pdfMoney(invoice.taxTotal)),
                amountRow('Total', pdfMoney(invoice.total), strong: true),
              ],
            ),
          ),
        ),
        pw.SizedBox(height: 18),
        pw.Text('PAYMENTS', style: muted),
        if (invoice.payments.isEmpty) pw.Text('No payments yet.'),
        for (final p in invoice.payments)
          amountRow(paymentLabel(p), pdfMoney(p.amount)),
        pw.Divider(color: PdfColors.grey400, thickness: 0.5),
        amountRow('Total paid', pdfMoney(invoice.paid)),
        amountRow('Amount due', pdfMoney(invoice.amountDue), strong: true),
        pw.SizedBox(height: 18),
        for (final note in invoice.notes) pw.Text(s(note), style: muted),
        pw.Text(
          'This is a computer-generated document; no signature is required.',
          style: muted,
        ),
      ],
    ),
  );
  return doc;
}

Future<Uint8List> renderInvoicePdf(
  Invoice invoice,
  PdfFonts fonts, {
  bool compress = true,
}) => buildInvoiceDocument(invoice, fonts, compress: compress).save();
