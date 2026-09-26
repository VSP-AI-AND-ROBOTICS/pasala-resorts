import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'pdf_deliver.dart';

/// Hands a finished PDF to the user: a download on the web, the share sheet
/// elsewhere. Returns false where the platform cannot take it. A provider so
/// widget tests can capture the file instead.
typedef PdfDeliverer = Future<bool> Function(String filename, Uint8List bytes);

final pdfDelivererProvider = Provider<PdfDeliverer>((ref) => deliverPdf);
