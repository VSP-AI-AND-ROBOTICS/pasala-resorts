import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/invoice.dart';
import 'report_pdf.dart';

/// Turns an [Invoice] or a [ReportPdf] into PDF bytes. Tests override
/// [pdfExporterProvider] with `FakePdfExporter`.
abstract class PdfExporter {
  Future<Uint8List> invoice(Invoice invoice);
  Future<Uint8List> report(ReportPdf report);
}

class PasalaPdfExporter implements PdfExporter {
  @override
  Future<Uint8List> invoice(Invoice invoice) =>
      throw UnimplementedError('PasalaPdfExporter.invoice lands in P2 Task 4');

  @override
  Future<Uint8List> report(ReportPdf report) =>
      throw UnimplementedError('PasalaPdfExporter.report lands in P2 Task 4');
}

final pdfExporterProvider = Provider<PdfExporter>((ref) => PasalaPdfExporter());
