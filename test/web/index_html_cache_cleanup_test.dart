import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'web/index.html unregisters stale service workers and clears old '
    'flutter caches before flutter_bootstrap.js loads',
    () {
      final html = File('web/index.html').readAsStringSync();

      final cleanupIndex = html.indexOf('serviceWorker');
      final bootstrapIndex = html.indexOf('<script src="flutter_bootstrap.js"');

      expect(
        cleanupIndex,
        greaterThanOrEqualTo(0),
        reason: 'expected a service-worker cleanup script in web/index.html',
      );
      expect(
        bootstrapIndex,
        greaterThanOrEqualTo(0),
        reason: 'expected the flutter_bootstrap.js script tag',
      );
      expect(
        cleanupIndex,
        lessThan(bootstrapIndex),
        reason:
            'the cache cleanup script must run before flutter_bootstrap.js '
            'so it removes stale caches ahead of the new build loading',
      );

      // Guarded feature checks: must not assume serviceWorker/caches exist.
      expect(html, contains('navigator.serviceWorker?.getRegistrations'));
      expect(html, contains('.unregister()'));
      expect(html, contains('window.caches?.keys'));
      expect(html, contains("startsWith('flutter-')"));
    },
  );
}
