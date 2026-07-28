import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/data/models/reservation.dart';
import 'package:pasala/features/account/my_bookings_screen.dart';

void main() {
  Reservation res(ReservationStatus status) => Reservation(
        id: 'c1',
        unitId: 'b1',
        start: DateTime(2026, 8, 3, 14),
        end: DateTime(2026, 8, 5, 11),
        kind: ReservationKind.booking,
        status: status,
        guests: 4,
      );

  testWidgets('shows the stay dates and a status chip', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: BookingTile(reservation: res(ReservationStatus.confirmed))),
    ));

    expect(find.textContaining('3 Aug'), findsOneWidget);
    expect(find.text('Confirmed'), findsOneWidget);
  });

  testWidgets('a cancelled booking is labelled cancelled', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: BookingTile(reservation: res(ReservationStatus.cancelled))),
    ));

    expect(find.text('Cancelled'), findsOneWidget);
  });

  // Beyond-the-brief coverage: every ReservationStatus must render its own
  // label. A hold and a booking are not the same thing to a customer -- a
  // hold is a 15-minute reservation that may simply vanish -- so mislabeling
  // one as the other (or as blank) is a real correctness bug, not cosmetic.
  group('status label covers all four ReservationStatus values', () {
    for (final (status, label) in [
      (ReservationStatus.hold, 'On hold'),
      (ReservationStatus.pendingPayment, 'Payment due'),
      (ReservationStatus.confirmed, 'Confirmed'),
      (ReservationStatus.cancelled, 'Cancelled'),
    ]) {
      testWidgets('$status -> "$label"', (tester) async {
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(body: BookingTile(reservation: res(status))),
        ));

        expect(find.text(label), findsOneWidget);
      });
    }
  });

  testWidgets('onTap fires when the tile is tapped', (tester) async {
    var tapped = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: BookingTile(
          reservation: res(ReservationStatus.confirmed),
          onTap: () => tapped = true,
        ),
      ),
    ));

    await tester.tap(find.byType(BookingTile));
    expect(tapped, isTrue);
  });
}
