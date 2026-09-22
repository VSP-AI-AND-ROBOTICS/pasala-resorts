import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/theme/app_theme.dart';

void main() {
  testWidgets('every interactive control meets the minimum tap target',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.light),
      home: Scaffold(
        body: Column(
          children: [
            FilledButton(onPressed: () {}, child: const Text('Book')),
            OutlinedButton(onPressed: () {}, child: const Text('Cancel')),
          ],
        ),
      ),
    ));

    // I7: this used to assert against `PasalaTokens.minTapTarget` -- the
    // SAME constant the theme's buttons are sized from (see
    // `lib/core/theme/app_theme.dart`) -- so the test could never fail: if
    // that token were ever accidentally changed to something below the
    // real WCAG/Material minimum, both sides of the comparison would move
    // together and this would still pass. The literal `48.0` is the actual
    // external requirement (WCAG 2.5.5 / Material's minimum touch target),
    // independent of whatever this codebase's own token happens to be set
    // to right now.
    for (final type in [FilledButton, OutlinedButton]) {
      final size = tester.getSize(find.byType(type));
      expect(size.height, greaterThanOrEqualTo(48.0),
          reason: '$type is below the minimum tap target');
    }
  });
}
