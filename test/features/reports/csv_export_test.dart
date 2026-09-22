import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/features/reports/csv_export.dart';

void main() {
  test('quotes fields containing a comma', () {
    expect(toCsv([['a', 'b,c']]), 'a,"b,c"\r\n');
  });

  test('escapes embedded quotes by doubling them', () {
    expect(toCsv([['say "hi"']]), '"say ""hi"""\r\n');
  });

  test('quotes fields containing a newline', () {
    expect(toCsv([['line1\nline2']]), '"line1\nline2"\r\n');
  });

  test('emits one CRLF-terminated record per row', () {
    expect(toCsv([['a'], ['b']]), 'a\r\nb\r\n');
  });
}
