import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/pdf/pdf_fonts.dart';

import '../../support/pdf_test_fonts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the bundled font has the rupee sign and Latin text', () {
    final fonts = testPdfFonts();
    expect(fonts.supports(0x20B9), isTrue, reason: '₹');
    expect(fonts.supports('A'.codeUnitAt(0)), isTrue);
    expect(fonts.supports('–'.codeUnitAt(0)), isTrue, reason: 'en dash');
    expect(fonts.supports('·'.codeUnitAt(0)), isTrue, reason: 'middle dot');
  });

  test('safe() keeps what the font draws and replaces the rest with ?', () {
    final fonts = testPdfFonts();
    expect(fonts.safe('Gita Guest ₹1,080.00'), 'Gita Guest ₹1,080.00');
    expect(fonts.safe('Line 1\nLine 2\tend'), 'Line 1\nLine 2\tend');
    expect(fonts.safe('सीता'), '????');
    expect(fonts.safe('Spa 🌸'), 'Spa ?');
  });

  test('loadPdfFonts reads both fonts from the app bundle', () async {
    final fonts = await loadPdfFonts();
    expect(fonts.supports(0x20B9), isTrue);
  });
}
