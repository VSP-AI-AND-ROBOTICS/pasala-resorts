import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/features/admin/property_form_screen.dart';

void main() {
  // The property form has enough fields (name, slug, description, address,
  // amenities, two time pickers, an active switch, plus Save) that it
  // overflows the default 800x600 test surface and its Save button sits
  // below the fold -- inside a scrollable ListView, widgets beyond the
  // viewport aren't built into the element tree at all, so `find` can't see
  // Save without either scrolling or a taller surface. A taller surface
  // keeps these tests focused on validation, not scroll mechanics.
  Future<void> useTallSurface(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('rejects an empty name', (tester) async {
    await useTallSurface(tester);
    await tester.pumpWidget(const MaterialApp(home: PropertyFormScreen()));

    // Slug is filled so the name validator is isolated as the failure cause.
    await tester.enterText(find.byKey(const Key('property-slug')), 'riverside');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pump();

    expect(find.text('Enter a name'), findsOneWidget);
  });

  testWidgets('rejects an empty slug', (tester) async {
    await useTallSurface(tester);
    await tester.pumpWidget(const MaterialApp(home: PropertyFormScreen()));

    await tester.enterText(
        find.byKey(const Key('property-name')), 'Pasala Riverside');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pump();

    expect(find.text('Enter a slug'), findsOneWidget);
  });
}
