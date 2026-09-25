import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pasala/data/models/reservation.dart';
import 'package:pasala/data/models/unit.dart';
import 'package:pasala/data/repositories/stay_pass_repository.dart';
import 'package:pasala/features/admin/admin_bookings_screen.dart' show bookingCode;
import 'package:pasala/features/booking/confirmation_screen.dart';
import 'package:pasala/features/booking/providers.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../support/fake_stay_pass_source.dart';

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

Widget _appFor({Reservation? reservation, FakeStayPassSource? passes}) {
  final res = reservation ?? _reservation;
  final router = GoRouter(
    initialLocation: '/booking/${res.id}',
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
      stayPassSourceProvider.overrideWithValue(passes ?? FakeStayPassSource()),
      reservationProvider(res.id).overrideWith((ref) => Future.value(res)),
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

  testWidgets('shows the occasion when one was given', (tester) async {
    final reservation = Reservation(
      id: 'r-occasion',
      unitId: 'u1',
      start: DateTime.utc(2026, 8, 20),
      end: DateTime.utc(2026, 8, 22),
      kind: ReservationKind.booking,
      status: ReservationStatus.confirmed,
      guests: 2,
      occasion: 'Anniversary weekend',
    );

    await tester.pumpWidget(_appFor(reservation: reservation));
    await tester.pumpAndSettle();

    expect(find.textContaining('Anniversary weekend'), findsOneWidget);
  });

  testWidgets('shows nothing extra when no occasion was given', (
    tester,
  ) async {
    await tester.pumpWidget(_appFor());
    await tester.pumpAndSettle();

    expect(find.textContaining('For:'), findsNothing);
  });

  testWidgets('shows the signed check-in pass and the booking code',
      (tester) async {
    final passes = FakeStayPassSource();
    await tester.pumpWidget(_appFor(passes: passes));
    await tester.pumpAndSettle();

    expect(find.byType(QrImageView), findsOneWidget);
    expect(passes.issueCalls, everyElement('r1'));
    expect(find.text('Booking code ${bookingCode('r1')}'), findsOneWidget);
    expect(find.text('Show this at check-in'), findsOneWidget);
  });
}
