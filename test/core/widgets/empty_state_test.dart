import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/widgets/empty_state.dart';

void main() {
  testWidgets('shows the icon when no image is given', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: EmptyState(icon: Icons.event_busy_outlined, title: 'No bookings yet'),
      ),
    ));

    expect(find.byIcon(Icons.event_busy_outlined), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('shows the image instead of the icon when one is given', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: EmptyState(
          icon: Icons.event_busy_outlined,
          title: 'No bookings yet',
          image: 'assets/images/facade_daytime.webp',
        ),
      ),
    ));

    expect(find.byIcon(Icons.event_busy_outlined), findsNothing);
    expect(find.byType(Image), findsOneWidget);
  });
}
