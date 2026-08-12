import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/widgets/hero_backdrop.dart';

void main() {
  testWidgets('renders the background image and the foreground child', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(
      home: HeroBackdrop(
        imageAsset: 'assets/images/hero_night_aerial.png',
        child: Center(child: Text('Welcome back')),
      ),
    ));

    expect(find.byType(Image), findsOneWidget);
    expect(find.text('Welcome back'), findsOneWidget);
  });
}
