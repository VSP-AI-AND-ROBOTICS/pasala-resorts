import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pasala/data/models/reservation.dart';
import 'package:pasala/data/repositories/stay_repository.dart';
import 'package:pasala/features/admin/reception_checkout_screen.dart';

Reservation _checkedIn(String id, {String? customerName}) => Reservation(
      id: id,
      unitId: 'u1',
      start: DateTime(2026, 9, 1),
      end: DateTime(2026, 9, 3),
      kind: ReservationKind.booking,
      status: ReservationStatus.checkedIn,
      customerName: customerName,
      guests: 2,
    );

Widget _appFor(List<Reservation> guests) {
  final router = GoRouter(
    initialLocation: '/admin/check-out',
    routes: [
      GoRoute(
          path: '/admin/check-out',
          builder: (_, _) => const ReceptionCheckoutScreen()),
      GoRoute(
          path: '/my-stay/checkout',
          builder: (_, _) => const Text('CHECKOUT SCREEN')),
    ],
  );
  return ProviderScope(
    overrides: [
      checkedInProvider.overrideWith((ref) async => guests),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  testWidgets('shows an empty state when no guests are checked in',
      (tester) async {
    await tester.pumpWidget(_appFor(const []));
    await tester.pumpAndSettle();

    expect(find.text('No guests currently checked in'), findsOneWidget);
  });

  testWidgets('lists every checked-in guest with a Check Out action',
      (tester) async {
    await tester.pumpWidget(
      _appFor([_checkedIn('r1', customerName: 'Ravi Kumar')]),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ravi Kumar'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Check Out'), findsOneWidget);
  });

  testWidgets('tapping Check Out navigates to the checkout screen',
      (tester) async {
    await tester.pumpWidget(
      _appFor([_checkedIn('r1', customerName: 'Ravi Kumar')]),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Check Out'));
    await tester.pumpAndSettle();

    expect(find.text('CHECKOUT SCREEN'), findsOneWidget);
  });
}
