import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/theme/app_theme.dart';
import 'package:pasala/core/theme/tokens.dart';

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

    for (final type in [FilledButton, OutlinedButton]) {
      final size = tester.getSize(find.byType(type));
      expect(size.height, greaterThanOrEqualTo(PasalaTokens.minTapTarget),
          reason: '$type is below the minimum tap target');
    }
  });
}
