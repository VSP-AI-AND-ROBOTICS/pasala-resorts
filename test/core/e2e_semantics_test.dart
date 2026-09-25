import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/e2e_semantics.dart';
// Imported so this test fails to compile if main.dart stops building with
// the E2E hook in it.
import 'package:pasala/main.dart' as app;

void main() {
  tearDown(disposeE2eSemantics);

  test('the E2E flag is off in a normal build', () {
    expect(kE2eBuild, isFalse);
    expect(app.main, isA<Function>());
  });

  testWidgets('does nothing when not an E2E build', (tester) async {
    await tester.pumpWidget(const SizedBox());
    ensureE2eSemantics(enabled: false);
    expect(SemanticsBinding.instance.semanticsEnabled, isFalse);
  }, semanticsEnabled: false);

  testWidgets('turns semantics on in an E2E build', (tester) async {
    await tester.pumpWidget(const SizedBox());
    ensureE2eSemantics(enabled: true);
    ensureE2eSemantics(enabled: true); // a second call is a no-op
    expect(SemanticsBinding.instance.semanticsEnabled, isTrue);
    disposeE2eSemantics();
    expect(SemanticsBinding.instance.semanticsEnabled, isFalse);
  }, semanticsEnabled: false);
}
