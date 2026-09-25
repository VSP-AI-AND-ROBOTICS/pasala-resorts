import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart' show TtfParser;
import 'package:pdf/widgets.dart' as pw;

/// Noto Sans (SIL OFL 1.1, assets/fonts/OFL.txt). The PDF standard fonts
/// have no ₹ sign, so every document this app makes uses these instead.
const pdfFontRegularAsset = 'assets/fonts/NotoSans-Regular.ttf';
const pdfFontBoldAsset = 'assets/fonts/NotoSans-Bold.ttf';

/// Whitespace the layout needs even though a font has no glyph for it.
const _alwaysKept = {0x09, 0x0A, 0x0D, 0x20};

/// The two fonts every PDF is set in, and the characters they can draw.
class PdfFonts {
  PdfFonts._(this.regular, this.bold, this._supported);

  factory PdfFonts.fromBytes(ByteData regular, ByteData bold) => PdfFonts._(
    pw.Font.ttf(regular),
    pw.Font.ttf(bold),
    TtfParser(regular).charToGlyphIndexMap.keys.toSet(),
  );

  final pw.Font regular;
  final pw.Font bold;
  final Set<int> _supported;

  /// Base and bold fonts for `pw.Document(theme: ...)`.
  pw.ThemeData get theme => pw.ThemeData.withFont(base: regular, bold: bold);

  bool supports(int rune) => _supported.contains(rune);

  /// [text] with every character the font cannot draw (Devanagari, emoji,
  /// ...) replaced by `?`, so a guest's name never breaks a document.
  String safe(String text) => String.fromCharCodes(
    text.runes.map(
      (r) => _alwaysKept.contains(r) || _supported.contains(r) ? r : 0x3F,
    ),
  );
}

/// Loads both fonts from the app's asset bundle.
Future<PdfFonts> loadPdfFonts([AssetBundle? bundle]) async {
  final assets = bundle ?? rootBundle;
  final regular = await assets.load(pdfFontRegularAsset);
  final bold = await assets.load(pdfFontBoldAsset);
  return PdfFonts.fromBytes(regular, bold);
}
