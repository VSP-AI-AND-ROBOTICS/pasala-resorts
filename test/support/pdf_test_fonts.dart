import 'dart:io';
import 'dart:typed_data';

import 'package:pasala/core/pdf/pdf_fonts.dart';

/// The bundled PDF fonts read straight from disk (`flutter test` runs in
/// the package root), for renderer tests that do not go through the app's
/// asset bundle.
PdfFonts testPdfFonts() =>
    PdfFonts.fromBytes(_read(pdfFontRegularAsset), _read(pdfFontBoldAsset));

ByteData _read(String path) =>
    ByteData.sublistView(File(path).readAsBytesSync());
