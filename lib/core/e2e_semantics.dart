import 'package:flutter/foundation.dart';
import 'package:flutter/semantics.dart';

/// True only in the Playwright build (`--dart-define=E2E=true`, see
/// `e2e/build-app.sh`). A compile-time constant, so a normal build carries
/// no trace of the E2E path.
const bool kE2eBuild = bool.fromEnvironment('E2E');

SemanticsHandle? _e2eSemantics;

/// Turns the semantics tree on for the life of the app when [enabled] (the
/// E2E build), so Flutter web renders its `flt-semantics` DOM -- ARIA roles
/// and labels -- without anyone pressing the hidden "Enable accessibility"
/// button. Playwright drives the app through that DOM, since everything
/// else is painted on a canvas. Does nothing when [enabled] is false, and
/// nothing on a second call.
void ensureE2eSemantics({bool enabled = kE2eBuild}) {
  if (!enabled || _e2eSemantics != null) return;
  _e2eSemantics = SemanticsBinding.instance.ensureSemantics();
}

/// Releases the handle [ensureE2eSemantics] took. Tests only: flutter_test
/// fails a test that ends with a semantics handle still open.
@visibleForTesting
void disposeE2eSemantics() {
  _e2eSemantics?.dispose();
  _e2eSemantics = null;
}
