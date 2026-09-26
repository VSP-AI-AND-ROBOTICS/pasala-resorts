// Web: a Blob download, exactly like csv_download_web.dart, so the browser
// (and Playwright) sees an ordinary download. Everywhere else: the
// platform share sheet through package:printing.
export 'pdf_deliver_share.dart'
    if (dart.library.js_interop) 'pdf_deliver_web.dart';
