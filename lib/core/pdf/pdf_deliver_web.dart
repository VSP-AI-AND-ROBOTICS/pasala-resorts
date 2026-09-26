import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Web: an in-memory Blob and a throwaway anchor with `download` set.
Future<bool> deliverPdf(String filename, Uint8List bytes) async {
  final blob = web.Blob(
    <JSAny>[bytes.toJS].toJS,
    web.BlobPropertyBag(type: 'application/pdf'),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = filename;
  anchor.click();
  web.URL.revokeObjectURL(url);
  return true;
}
