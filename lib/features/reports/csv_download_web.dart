import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Web implementation: builds an in-memory `Blob`, points a throwaway
/// anchor at it with `download` set, and clicks it -- the standard
/// browser-download trick, with no server round-trip needed since the CSV
/// is already fully built client-side by `toCsv`.
bool downloadCsv(String filename, String csv) {
  final blob = web.Blob(
    <JSAny>[csv.toJS].toJS,
    web.BlobPropertyBag(type: 'text/csv;charset=utf-8'),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = filename;
  anchor.click();
  web.URL.revokeObjectURL(url);
  return true;
}
