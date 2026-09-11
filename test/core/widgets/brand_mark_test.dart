import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/widgets/brand_mark.dart';

void main() {
  testWidgets('carries an accessible label naming the resort', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: BrandMark())));

    expect(find.bySemanticsLabel('Pasala Resorts'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('shows the wordmark text by default', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: BrandMark())));

    expect(find.text('Pasala Resorts'), findsOneWidget);
  });

  testWidgets('hides the wordmark text when showWordmark is false', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: BrandMark(showWordmark: false)),
    ));

    expect(find.text('Pasala Resorts'), findsNothing);
  });
}
