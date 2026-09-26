import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/data/models/current_charges.dart';
import 'package:pasala/data/repositories/stay_repository.dart';
import 'package:pasala/features/stay/current_charges_screen.dart';

Future<void> _pump(WidgetTester tester, CurrentCharges charges) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [currentChargesProvider.overrideWith((ref, id) async => charges)],
    child: const MaterialApp(home: CurrentChargesScreen(reservationId: 'r1')),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the tax inside food and inside activities', (tester) async {
    await _pump(
        tester,
        const CurrentCharges(
          stayAmount: 5000,
          foodAmount: 630,
          foodTax: 36.25,
          activityAmount: 2360,
          activityTax: 360,
          total: 7990,
          paid: 0,
          balance: 7990,
        ));

    expect(find.text('₹630'), findsOneWidget);
    expect(
        find.descendant(
            of: find.byKey(const Key('charges-food-tax')),
            matching: find.text('Includes tax ₹36.25')),
        findsOneWidget);
    expect(
        find.descendant(
            of: find.byKey(const Key('charges-activity-tax')),
            matching: find.text('Includes tax ₹360.00')),
        findsOneWidget);
  });

  testWidgets('no tax line when there is no tax', (tester) async {
    await _pump(
        tester,
        const CurrentCharges(
          stayAmount: 3000,
          foodAmount: 200,
          activityAmount: 0,
          total: 3200,
          paid: 1000,
          balance: 2200,
        ));

    expect(find.textContaining('Includes tax'), findsNothing);
  });
}
