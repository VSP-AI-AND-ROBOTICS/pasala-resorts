import 'dart:typed_data';

import 'package:printing/printing.dart';

/// Android, iOS and desktop: the platform share sheet (save, print, send).
Future<bool> deliverPdf(String filename, Uint8List bytes) =>
    Printing.sharePdf(bytes: bytes, filename: filename);
