// test/core/widgets/app_splash_overlay_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/theme/tokens.dart';
import 'package:pasala/core/widgets/app_splash_overlay.dart';
import 'package:pasala/core/widgets/brand_mark.dart';

void main() {
  testWidgets('shows the brand mark, then removes itself after the fade', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(
      home: AppSplashOverlay(child: Text('home content')),
    ));

    expect(find.byType(BrandMark), findsOneWidget);
    expect(find.text('home content'), findsOneWidget);

    await tester.pump(PasalaTokens.motionBase * 3);
    await tester.pump(PasalaTokens.motionBase);

    expect(find.byType(BrandMark), findsNothing);
    expect(find.text('home content'), findsOneWidget);
  });
}
