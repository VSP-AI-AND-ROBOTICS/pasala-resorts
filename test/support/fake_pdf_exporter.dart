import 'dart:async';
import 'dart:typed_data';

import 'package:pasala/core/pdf/pdf_exporter.dart';
import 'package:pasala/core/pdf/report_pdf.dart';
import 'package:pasala/data/models/invoice.dart';

/// Records what a screen asked to render and answers [bytes]. Set [error]
/// to make every call throw, [hold] to keep calls pending.
class FakePdfExporter implements PdfExporter {
  static final Uint8List bytes = Uint8List.fromList('%PDF-1.7 fake'.codeUnits);

  final List<Invoice> invoices = [];
  final List<ReportPdf> reports = [];
  Object? error;
  Completer<void>? hold;

  Future<Uint8List> _answer() async {
    if (hold != null) await hold!.future;
    if (error != null) throw error!;
    return bytes;
  }

  @override
  Future<Uint8List> invoice(Invoice invoice) {
    invoices.add(invoice);
    return _answer();
  }

  @override
  Future<Uint8List> report(ReportPdf report) {
    reports.add(report);
    return _answer();
  }
}

/// A [PdfDeliverer] stand-in: records every file, answers [delivers].
class PdfDeliveries {
  PdfDeliveries({this.delivers = true});

  final bool delivers;
  final List<(String, Uint8List)> files = [];

  Future<bool> deliver(String filename, Uint8List bytes) async {
    files.add((filename, bytes));
    return delivers;
  }
}
