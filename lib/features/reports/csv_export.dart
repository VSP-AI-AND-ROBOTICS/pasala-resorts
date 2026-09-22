/// RFC 4180 CSV. Excel and Google Sheets both accept CRLF records and
/// doubled quotes; anything looser corrupts a cell containing a comma,
/// which in this app means any address or property name.
String toCsv(List<List<String>> rows) {
  final buffer = StringBuffer();
  for (final row in rows) {
    buffer.write(row.map(_field).join(','));
    buffer.write('\r\n');
  }
  return buffer.toString();
}

String _field(String value) {
  final needsQuotes =
      value.contains(',') || value.contains('"') || value.contains('\n');
  if (!needsQuotes) return value;
  return '"${value.replaceAll('"', '""')}"';
}
