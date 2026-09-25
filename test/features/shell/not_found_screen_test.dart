import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/features/shell/not_found_screen.dart';

void main() {
  // A bare Text produced no heading (and, on web, no ARIA role at all), so
  // screen readers had nothing to announce and the E2E suite's
  // waitForFlutter never saw the screen render.
  testWidgets('"Page not found" is a level-1 heading for screen readers',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(const MaterialApp(home: NotFoundScreen()));

    final heading = find.text('Page not found');
    expect(heading, findsOneWidget);
    expect(
      tester.getSemantics(heading),
      isSemantics(label: 'Page not found', isHeader: true),
    );
    expect(tester.getSemantics(heading).getSemanticsData().headingLevel, 1);
    semantics.dispose();
  });

  testWidgets('explains what happened below the heading', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: NotFoundScreen()));

    expect(
      find.text("This page doesn't exist, or you don't have access to it."),
      findsOneWidget,
    );
  });
}
