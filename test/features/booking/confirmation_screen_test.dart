// test/features/booking/confirmation_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pasala/data/models/reservation.dart';
import 'package:pasala/data/models/unit.dart';
import 'package:pasala/features/booking/confirmation_screen.dart';
import 'package:pasala/features/booking/providers.dart';

final _reservation = Reservation(
  id: 'r1',
  unitId: 'u1',
  start: DateTime.utc(2026, 8, 20),
  end: DateTime.utc(2026, 8, 22),
  kind: ReservationKind.booking,
  status: ReservationStatus.confirmed,
  guests: 2,
);

const _unit = Unit(
  id: 'u1',
  propertyId: 'p1',
  name: 'Dallas Cottage',
  capacityBase: 2,
  capacityMax: 4,
  bookingMode: BookingMode.nightly,
  isActive: true,
);

Widget _appFor() {
  final router = GoRouter(
    initialLocation: '/booking/r1',
    routes: [
      GoRoute(
        path: '/booking/:id',
        builder: (_, state) =>
            ConfirmationScreen(reservationId: state.pathParameters['id']!),
      ),
      GoRoute(path: '/bookings', builder: (_, _) => const SizedBox()),
      GoRoute(path: '/', builder: (_, _) => const SizedBox()),
    ],
  );

  return ProviderScope(
    overrides: [
      reservationProvider('r1').overrideWith((ref) => Future.value(_reservation)),
      unitByIdProvider('u1').overrideWith((ref) => Future.value(_unit)),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  testWidgets('shows the unit name and stay dates once confirmed', (
    tester,
  ) async {
    await tester.pumpWidget(_appFor());
    await tester.pumpAndSettle();

    expect(find.text('Dallas Cottage'), findsOneWidget);
    expect(find.textContaining('Aug'), findsWidgets);
  });

  testWidgets('animates the checkmark in with a scale transition', (
    tester,
  ) async {
    await tester.pumpWidget(_appFor());
    await tester.pump();

    expect(find.byType(TweenAnimationBuilder<double>), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
  });
}
