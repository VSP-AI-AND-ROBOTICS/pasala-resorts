// Delivers a CSV string to the user, returning whether delivery actually
// happened.
//
// On the web this triggers a real browser download (see
// csv_download_web.dart). Everywhere else there is no filesystem this app
// can safely write to without another package (share_plus, path_provider --
// both deferred, see the task brief), so csv_download_stub.dart always
// returns false. ReportsScreen uses that to show an honest "not available on
// this platform yet" message instead of silently doing nothing, which is
// worse than admitting the gap.
//
// dart.library.js_interop (rather than the deprecated dart.library.html) is
// the condition, per current Flutter guidance for detecting a web compile
// target without pulling in dart:html -- flutter_lints'
// avoid_web_libraries_in_flutter rule would flag that import anyway.
export 'csv_download_stub.dart'
    if (dart.library.js_interop) 'csv_download_web.dart';
