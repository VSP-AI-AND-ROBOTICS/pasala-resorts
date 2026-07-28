import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/errors.dart';
import 'package:pasala/core/widgets/failure_view.dart';

void main() {
  testWidgets("shows a BookingFailure's own curated message", (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: FailureView(error: UnitUnavailable()),
    ));

    expect(find.text(const UnitUnavailable().message), findsOneWidget);
  });

  testWidgets(
      'never renders the raw server text carried by UnknownFailure '
      '(the carried-forward fix for Task 16)', (tester) async {
    const raw = 'permission denied for table reservations';
    await tester.pumpWidget(const MaterialApp(
      home: FailureView(error: UnknownFailure(raw)),
    ));

    expect(find.textContaining(raw), findsNothing);
    expect(find.text('Something went wrong.'), findsOneWidget);
  });

  testWidgets('falls back to a generic message for a non-BookingFailure error',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: FailureView(error: 'raw exception string'),
    ));

    expect(find.text('Something went wrong.'), findsOneWidget);
  });

  testWidgets('shows a retry button when onRetry is supplied', (tester) async {
    var tapped = false;
    await tester.pumpWidget(MaterialApp(
      home: FailureView(error: const NotFound(), onRetry: () => tapped = true),
    ));

    expect(find.text('Retry'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    expect(tapped, isTrue);
  });

  testWidgets('shows no retry button when onRetry is omitted', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: FailureView(error: NotFound()),
    ));

    expect(find.text('Retry'), findsNothing);
  });
}
