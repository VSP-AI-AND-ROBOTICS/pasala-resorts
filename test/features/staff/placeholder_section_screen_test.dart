import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/features/staff/placeholder_section_screen.dart';

void main() {
  testWidgets('shows the section title in the app bar and a coming-soon '
      'message in the body', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: PlaceholderSectionScreen(
          title: 'Working Hours',
          icon: Icons.schedule_outlined,
        ),
      ),
    );

    expect(find.text('Working Hours'), findsWidgets);
    expect(find.textContaining('Coming soon'), findsOneWidget);
  });
}
