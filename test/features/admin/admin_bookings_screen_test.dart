import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/data/models/reservation.dart';
import 'package:pasala/features/admin/admin_bookings_screen.dart';
import 'package:pasala/features/staff/providers.dart';

Reservation _res(
  String id, {
  ReservationStatus status = ReservationStatus.confirmed,
  ReservationKind kind = ReservationKind.booking,
}) =>
    Reservation(
      id: id,
      unitId: 'u1',
      start: DateTime(2026, 8, 4),
      end: DateTime(2026, 8, 6),
      kind: kind,
      status: status,
    );

void main() {
  group('filterBookings', () {
    final all = [
      _res('hold-1', status: ReservationStatus.hold),
      _res('pending-1', status: ReservationStatus.pendingPayment),
      _res('confirmed-1', status: ReservationStatus.confirmed),
      _res('confirmed-2', status: ReservationStatus.confirmed),
      _res('cancelled-1', status: ReservationStatus.cancelled),
      // Admin blocks are not "bookings" and must never appear, in any
      // filter -- they have no customer, quote, or guest to show.
      _res('block-1',
          status: ReservationStatus.confirmed, kind: ReservationKind.block),
    ];

    test('All returns every booking-kind reservation, excluding blocks', () {
      final result = filterBookings(all, BookingStatusFilter.all);
      expect(result.map((r) => r.id), [
        'hold-1',
        'pending-1',
        'confirmed-1',
        'confirmed-2',
        'cancelled-1',
      ]);
    });

    test('On hold returns only hold-status bookings', () {
      final result = filterBookings(all, BookingStatusFilter.onHold);
      expect(result.map((r) => r.id), ['hold-1']);
    });

    test('Confirmed returns only confirmed bookings', () {
      final result = filterBookings(all, BookingStatusFilter.confirmed);
      expect(result.map((r) => r.id), ['confirmed-1', 'confirmed-2']);
    });

    test('Cancelled returns only cancelled bookings', () {
      final result = filterBookings(all, BookingStatusFilter.cancelled);
      expect(result.map((r) => r.id), ['cancelled-1']);
    });

    test('a block never appears under All/onHold/confirmed/cancelled', () {
      for (final filter in [
        BookingStatusFilter.all,
        BookingStatusFilter.onHold,
        BookingStatusFilter.confirmed,
        BookingStatusFilter.cancelled,
      ]) {
        expect(filterBookings(all, filter).map((r) => r.id),
            isNot(contains('block-1')));
      }
    });

    // I4: a block previously had no filter at all -- an admin could only
    // find (and thus only undo) one via psql. This is the escape hatch.
    test('Blocks returns only block-kind reservations', () {
      final result = filterBookings(all, BookingStatusFilter.blocks);
      expect(result.map((r) => r.id), ['block-1']);
    });

    test('a non-block booking never appears under Blocks', () {
      final result = filterBookings(all, BookingStatusFilter.blocks);
      expect(result.map((r) => r.id), isNot(contains('confirmed-1')));
    });
  });

  group('AdminBookingsScreen', () {
    Widget app(List<Reservation> bookings) => ProviderScope(
          overrides: [
            allBookingsProvider.overrideWith((ref) async => bookings),
          ],
          child: const MaterialApp(home: AdminBookingsScreen()),
        );

    testWidgets('an empty result shows a clear message, not a blank screen',
        (tester) async {
      await tester.pumpWidget(app(const []));
      await tester.pumpAndSettle();

      expect(find.text('No bookings match this filter.'), findsOneWidget);
    });

    testWidgets('switching to the Cancelled segment narrows the list',
        (tester) async {
      final bookings = [
        _res('confirmed-1'),
        _res('cancelled-1', status: ReservationStatus.cancelled),
      ];
      await tester.pumpWidget(app(bookings));
      await tester.pumpAndSettle();

      // Both rows show under All.
      expect(find.byType(Card), findsNWidgets(2));

      // "Cancelled" also appears as a status Chip on the cancelled row, so
      // scope the tap to the segmented button itself.
      await tester.tap(find.descendant(
        of: find.byType(SegmentedButton<BookingStatusFilter>),
        matching: find.text('Cancelled'),
      ));
      await tester.pumpAndSettle();

      expect(find.byType(Card), findsOneWidget);
    });
  });
}
