import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/invoice.dart';
import 'invoice_pdf_renderer.dart';
import 'pdf_fonts.dart';
import 'report_pdf.dart';
import 'report_pdf_renderer.dart';

/// Turns an [Invoice] or a [ReportPdf] into PDF bytes. Tests override
/// [pdfExporterProvider] with `FakePdfExporter`.
abstract class PdfExporter {
  Future<Uint8List> invoice(Invoice invoice);
  Future<Uint8List> report(ReportPdf report);
}

/// Loads the bundled fonts on first use (and again after a failed load),
/// then renders with them.
class PasalaPdfExporter implements PdfExporter {
  PasalaPdfExporter({Future<PdfFonts> Function()? loadFonts})
    : _loadFonts = loadFonts ?? loadPdfFonts;

  final Future<PdfFonts> Function() _loadFonts;
  Future<PdfFonts>? _fonts;

  Future<PdfFonts> _fontsOnce() async {
    final pending = _fonts ??= _loadFonts();
    try {
      return await pending;
    } catch (_) {
      if (identical(_fonts, pending)) _fonts = null;
      rethrow;
    }
  }

  @override
  Future<Uint8List> invoice(Invoice invoice) async =>
      renderInvoicePdf(invoice, await _fontsOnce());

  @override
  Future<Uint8List> report(ReportPdf report) async =>
      renderReportPdf(report, await _fontsOnce());
}

final pdfExporterProvider = Provider<PdfExporter>((ref) => PasalaPdfExporter());
