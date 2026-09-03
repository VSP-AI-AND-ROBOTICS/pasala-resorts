import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pasala/data/models/property.dart';
import 'package:pasala/data/models/quote.dart';
import 'package:pasala/data/models/reservation.dart';
import 'package:pasala/features/admin/admin_bookings_screen.dart';
import 'package:pasala/features/browse/providers.dart';
import 'package:pasala/features/staff/providers.dart';

Reservation _res(
  String id, {
  ReservationStatus status = ReservationStatus.confirmed,
  ReservationKind kind = ReservationKind.booking,
  String? customerName,
  String? customerPhone,
}) =>
    Reservation(
      id: id,
      unitId: 'u1',
      start: DateTime(2026, 8, 4),
      end: DateTime(2026, 8, 6),
      kind: kind,
      status: status,
      customerName: customerName,
      customerPhone: customerPhone,
    );

void main() {
  group('filterBookings', () {
    final all = [
      _res('hold-1', status: ReservationStatus.hold),
      _res('pending-1', status: ReservationStatus.pendingPayment),
      _res('confirmed-1', status: ReservationStatus.confirmed),
      _res('checked-in-1', status: ReservationStatus.checkedIn),
      _res('checked-out-1', status: ReservationStatus.checkedOut),
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
        'checked-in-1',
        'checked-out-1',
        'cancelled-1',
      ]);
    });

    test('Pending returns hold and pending-payment bookings', () {
      final result = filterBookings(all, BookingStatusFilter.pending);
      expect(result.map((r) => r.id), ['hold-1', 'pending-1']);
    });

    test('Confirmed returns confirmed and checked-in bookings', () {
      final result = filterBookings(all, BookingStatusFilter.confirmed);
      expect(result.map((r) => r.id), ['confirmed-1', 'checked-in-1']);
    });

    test('Completed returns only checked-out bookings', () {
      final result = filterBookings(all, BookingStatusFilter.completed);
      expect(result.map((r) => r.id), ['checked-out-1']);
    });

    test('Cancelled returns only cancelled bookings', () {
      final result = filterBookings(all, BookingStatusFilter.cancelled);
      expect(result.map((r) => r.id), ['cancelled-1']);
    });

    test('a block never appears under All/confirmed/pending/cancelled/'
        'completed', () {
      for (final filter in [
        BookingStatusFilter.all,
        BookingStatusFilter.confirmed,
        BookingStatusFilter.pending,
        BookingStatusFilter.cancelled,
        BookingStatusFilter.completed,
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

  group('bookingCode', () {
    test('derives a short, uppercase code from the reservation id', () {
      expect(bookingCode('3f2a1b9c-0000-0000-0000-000000000000'), 'PR3F2A');
    });

    test('pads a short id rather than throwing', () {
      expect(bookingCode('ab'), 'PRAB00');
    });
  });

  group('bookingMatchesSearch', () {
    final reservation = _res(
      '3f2a1b9c-0000-0000-0000-000000000000',
      customerName: 'Ramesh Kumar',
      customerPhone: '9876543210',
    );

    test('an empty query always matches', () {
      expect(bookingMatchesSearch(reservation, ''), isTrue);
    });

    test('matches on booking code, case-insensitively', () {
      expect(bookingMatchesSearch(reservation, 'pr3f2a'), isTrue);
    });

    test('matches on guest name, case-insensitively', () {
      expect(bookingMatchesSearch(reservation, 'ramesh'), isTrue);
    });

    test('matches on phone', () {
      expect(bookingMatchesSearch(reservation, '98765'), isTrue);
    });

    test('does not match an unrelated query', () {
      expect(bookingMatchesSearch(reservation, 'sneha'), isFalse);
    });
  });

  group('AdminBookingsScreen', () {
    const property = Property(
      id: 'p1',
      name: 'Pasala Farm House',
      slug: 'pasala-farm-house',
      description: null,
      address: null,
      images: [],
      amenities: [],
      checkInTime: '14:00',
      checkOutTime: '11:00',
      isActive: true,
    );

    Widget app(List<Reservation> bookings) {
      final router = GoRouter(
        initialLocation: '/admin/bookings',
        routes: [
          GoRoute(
              path: '/admin/bookings',
              builder: (_, _) => const AdminBookingsScreen()),
          GoRoute(
              path: '/property/:id',
              builder: (_, _) => const Text('PROPERTY SCREEN')),
        ],
      );
      return ProviderScope(
        overrides: [
          allBookingsProvider.overrideWith((ref) async => bookings),
          propertiesProvider.overrideWith((ref) async => [property]),
        ],
        child: MaterialApp.router(routerConfig: router),
      );
    }

    testWidgets('an empty result shows a clear message, not a blank screen',
        (tester) async {
      await tester.pumpWidget(app(const []));
      await tester.pumpAndSettle();

      expect(find.text('No bookings match this filter.'), findsOneWidget);
    });

    testWidgets('switching to the Cancelled chip narrows the list',
        (tester) async {
      final bookings = [
        _res('confirmed-1'),
        _res('cancelled-1', status: ReservationStatus.cancelled),
      ];
      await tester.pumpWidget(app(bookings));
      await tester.pumpAndSettle();

      // Both rows show under All.
      expect(find.byType(Card), findsNWidgets(2));

      // "Cancelled" also appears as a status pill on the cancelled row, so
      // scope the tap to the filter chip itself.
      await tester.tap(find.descendant(
        of: find.byType(ChoiceChip),
        matching: find.text('Cancelled'),
      ));
      await tester.pumpAndSettle();

      expect(find.byType(Card), findsOneWidget);
    });

    testWidgets('typing in the search field narrows by guest name',
        (tester) async {
      final bookings = [
        _res('1', customerName: 'Ramesh Kumar'),
        _res('2', customerName: 'Sneha Reddy'),
      ];
      await tester.pumpWidget(app(bookings));
      await tester.pumpAndSettle();

      expect(find.byType(Card), findsNWidgets(2));

      await tester.enterText(
        find.byType(TextField),
        'sneha',
      );
      await tester.pumpAndSettle();

      expect(find.byType(Card), findsOneWidget);
      expect(find.text('Sneha Reddy'), findsOneWidget);
    });

    testWidgets('a card shows the guest name, status, and amount',
        (tester) async {
      final quote = Quote.fromJson({
        'currency': 'INR',
        'guests': 4,
        'lines': const [],
        'subtotal': 35000,
        'cleaning_fee': 0,
        'total': 35000,
      });
      final booking = Reservation(
        id: '3f2a1b9c-0000-0000-0000-000000000000',
        unitId: 'u1',
        start: DateTime(2026, 9, 12),
        end: DateTime(2026, 9, 14),
        kind: ReservationKind.booking,
        status: ReservationStatus.confirmed,
        customerName: 'Ramesh Kumar',
        guests: 4,
        quote: quote,
      );
      await tester.pumpWidget(app([booking]));
      await tester.pumpAndSettle();

      expect(find.text('PR3F2A'), findsOneWidget);
      expect(find.text('Ramesh Kumar'), findsOneWidget);
      // "Confirmed" also labels the filter chip above the list, so scope
      // the status-pill assertion to inside the card itself.
      expect(
        find.descendant(
          of: find.byType(AdminBookingCard),
          matching: find.text('Confirmed'),
        ),
        findsOneWidget,
      );
      expect(find.text('4 Guests'), findsOneWidget);
      expect(find.textContaining('35,000'), findsOneWidget);
    });

    testWidgets('tapping "New Booking" navigates to the property booking flow',
        (tester) async {
      await tester.pumpWidget(app(const []));
      await tester.pumpAndSettle();

      await tester.tap(find.text('New Booking'));
      await tester.pumpAndSettle();

      expect(find.text('PROPERTY SCREEN'), findsOneWidget);
    });
  });
}
