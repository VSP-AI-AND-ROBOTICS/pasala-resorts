import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/widgets/staggered_fade_in.dart';
import 'package:pasala/data/models/reservation.dart';
import 'package:pasala/features/account/my_bookings_screen.dart';
import 'package:pasala/features/account/providers.dart';

void main() {
  testWidgets('shows the facade illustration in the empty state', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          myBookingsProvider
              .overrideWith((ref) => Future.value(const <Reservation>[])),
        ],
        child: const MaterialApp(home: MyBookingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No bookings yet'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('shows bookings with a staggered entrance wrapper', (
    tester,
  ) async {
    final reservation = Reservation(
      id: 'r1',
      unitId: 'u1',
      start: DateTime(2026, 8, 3, 14),
      end: DateTime(2026, 8, 5, 11),
      kind: ReservationKind.booking,
      status: ReservationStatus.confirmed,
      guests: 2,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          myBookingsProvider.overrideWith((ref) => Future.value([reservation])),
        ],
        child: const MaterialApp(home: MyBookingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Confirmed'), findsOneWidget);
    expect(find.byType(StaggeredFadeIn), findsAtLeastNWidgets(1));
  });

  testWidgets('labels each booking with its own resort when the guest has '
      'bookings at two resorts', (tester) async {
    final riverside = Reservation(
      id: 'r1',
      unitId: 'u1',
      start: DateTime(2026, 8, 3, 14),
      end: DateTime(2026, 8, 5, 11),
      kind: ReservationKind.booking,
      status: ReservationStatus.confirmed,
      guests: 2,
      resortName: 'Pasala Riverside',
    );
    final hilltop = Reservation(
      id: 'r2',
      unitId: 'u2',
      start: DateTime(2026, 9, 10, 14),
      end: DateTime(2026, 9, 12, 11),
      kind: ReservationKind.booking,
      status: ReservationStatus.confirmed,
      guests: 3,
      resortName: 'Pasala Hilltop',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          myBookingsProvider
              .overrideWith((ref) => Future.value([riverside, hilltop])),
        ],
        child: const MaterialApp(home: MyBookingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Pasala Riverside'), findsOneWidget);
    expect(find.text('Pasala Hilltop'), findsOneWidget);
  });
}
