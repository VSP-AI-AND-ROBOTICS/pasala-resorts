import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pasala/data/models/app_user.dart';
import 'package:pasala/data/models/property.dart';
import 'package:pasala/data/models/quote.dart';
import 'package:pasala/data/models/report.dart';
import 'package:pasala/data/models/reservation.dart';
import 'package:pasala/data/models/review.dart';
import 'package:pasala/data/models/unit.dart';
import 'package:pasala/data/repositories/auth_repository.dart';
import 'package:pasala/data/repositories/review_repository.dart';
import 'package:pasala/features/admin/admin_home_screen.dart';
import 'package:pasala/features/browse/providers.dart';
import 'package:pasala/features/reports/providers.dart';
import 'package:pasala/features/staff/providers.dart';

Reservation _booking(
  String id, {
  required DateTime start,
  required DateTime end,
  ReservationStatus status = ReservationStatus.confirmed,
  String? customerName,
  int? guests,
  Quote? quote,
}) =>
    Reservation(
      id: id,
      unitId: 'u1',
      start: start,
      end: end,
      kind: ReservationKind.booking,
      status: status,
      customerName: customerName,
      guests: guests,
      quote: quote,
    );

void main() {
  group('nextArrival', () {
    final now = DateTime(2026, 9, 10, 8);

    test('picks the soonest confirmed booking starting today or later', () {
      final bookings = [
        _booking('later', start: DateTime(2026, 9, 15), end: DateTime(2026, 9, 16)),
        _booking('soonest',
            start: DateTime(2026, 9, 11), end: DateTime(2026, 9, 12)),
      ];
      expect(nextArrival(bookings, now)?.id, 'soonest');
    });

    test('ignores a confirmed booking whose dates already passed', () {
      final bookings = [
        _booking('past', start: DateTime(2026, 9, 1), end: DateTime(2026, 9, 2)),
      ];
      expect(nextArrival(bookings, now), isNull);
    });

    test('ignores a checked-in booking -- it has already arrived', () {
      final bookings = [
        _booking('here',
            start: DateTime(2026, 9, 10),
            end: DateTime(2026, 9, 12),
            status: ReservationStatus.checkedIn),
      ];
      expect(nextArrival(bookings, now), isNull);
    });

    test('a booking starting today counts as an arrival', () {
      final bookings = [
        _booking('today', start: DateTime(2026, 9, 10), end: DateTime(2026, 9, 11)),
      ];
      expect(nextArrival(bookings, now)?.id, 'today');
    });

    test('returns null when there are no upcoming confirmed bookings', () {
      expect(nextArrival(const [], now), isNull);
    });
  });

  group('isFarmhouseOccupied', () {
    test('true when any booking is checked in', () {
      final bookings = [
        _booking('here',
            start: DateTime(2026, 9, 1),
            end: DateTime(2026, 9, 2),
            status: ReservationStatus.checkedIn),
      ];
      expect(isFarmhouseOccupied(bookings), isTrue);
    });

    test('false when nothing is checked in', () {
      final bookings = [
        _booking('confirmed',
            start: DateTime(2026, 9, 1), end: DateTime(2026, 9, 2)),
      ];
      expect(isFarmhouseOccupied(bookings), isFalse);
    });

    test('false for an empty list', () {
      expect(isFarmhouseOccupied(const []), isFalse);
    });
  });

  group('bookingsThisMonth', () {
    final now = DateTime(2026, 9, 15);

    test('includes a non-cancelled booking starting this month', () {
      final bookings = [
        _booking('this-month',
            start: DateTime(2026, 9, 3), end: DateTime(2026, 9, 4)),
      ];
      expect(bookingsThisMonth(bookings, now).map((r) => r.id), ['this-month']);
    });

    test('excludes a cancelled booking even if this month', () {
      final bookings = [
        _booking('cancelled',
            start: DateTime(2026, 9, 3),
            end: DateTime(2026, 9, 4),
            status: ReservationStatus.cancelled),
      ];
      expect(bookingsThisMonth(bookings, now), isEmpty);
    });

    test('excludes a booking starting a different month', () {
      final bookings = [
        _booking('other-month',
            start: DateTime(2026, 8, 3), end: DateTime(2026, 8, 4)),
      ];
      expect(bookingsThisMonth(bookings, now), isEmpty);
    });

    // I10: this count feeds "Avg. Booking Value" alongside
    // dashboard_summary()'s month_revenue, which is strictly month-to-date
    // -- a future arrival later this month has no revenue yet, so counting
    // it here understated the average. Excluding it keeps both figures on
    // the same date window.
    test('excludes a booking later this month that hasn\'t arrived yet', () {
      final bookings = [
        _booking('future-this-month',
            start: DateTime(2026, 9, 20), end: DateTime(2026, 9, 22)),
      ];
      expect(bookingsThisMonth(bookings, now), isEmpty);
    });

    test('includes a booking arriving today', () {
      final bookings = [
        _booking('today',
            start: DateTime(2026, 9, 15), end: DateTime(2026, 9, 17)),
      ];
      expect(bookingsThisMonth(bookings, now).map((r) => r.id), ['today']);
    });
  });

  group('formatTimeOfDay', () {
    test('formats an afternoon time', () {
      expect(formatTimeOfDay('14:00'), '2:00 PM');
    });

    test('formats a morning time', () {
      expect(formatTimeOfDay('09:30'), '9:30 AM');
    });

    test('formats midnight as 12 AM', () {
      expect(formatTimeOfDay('00:00'), '12:00 AM');
    });

    test('formats noon as 12 PM', () {
      expect(formatTimeOfDay('12:00'), '12:00 PM');
    });
  });

  group('relativeDayLabel', () {
    final now = DateTime(2026, 9, 10, 8);

    test('the same calendar day reads as Today', () {
      expect(relativeDayLabel(DateTime(2026, 9, 10, 23), now), 'Today');
    });

    test('the next calendar day reads as Tomorrow', () {
      expect(relativeDayLabel(DateTime(2026, 9, 11), now), 'Tomorrow');
    });

    test('any other day falls back to a plain formatted date', () {
      expect(relativeDayLabel(DateTime(2026, 9, 20), now), isNot('Today'));
      expect(relativeDayLabel(DateTime(2026, 9, 20), now), isNot('Tomorrow'));
    });
  });

  group('relativeTime', () {
    final now = DateTime(2026, 9, 10, 12);

    test('under an hour reads as Just now', () {
      expect(relativeTime(now.subtract(const Duration(minutes: 30)), now),
          'Just now');
    });

    test('a few hours ago', () {
      expect(relativeTime(now.subtract(const Duration(hours: 3)), now),
          '3 hours ago');
    });

    test('a couple of days ago', () {
      expect(relativeTime(now.subtract(const Duration(days: 2)), now),
          '2 days ago');
    });

    test('a month or more falls back to a plain formatted date', () {
      final result = relativeTime(now.subtract(const Duration(days: 40)), now);
      expect(result, isNot(contains('ago')));
    });
  });

  group('AdminHomeScreen', () {
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

    const unit = Unit(
      id: 'u1',
      propertyId: 'p1',
      name: 'Farm House',
      capacityBase: 4,
      capacityMax: 20,
      bookingMode: BookingMode.nightly,
      isActive: true,
    );

    const admin = AppUser(
      id: 'admin-1',
      email: 'admin@pasala.test',
      role: UserRole.admin,
      fullName: 'Asha Admin',
    );

    Widget app({List<Reservation> bookings = const [], List<Review> reviews = const []}) {
      final router = GoRouter(
        initialLocation: '/admin',
        routes: [
          GoRoute(path: '/admin', builder: (_, _) => const AdminHomeScreen()),
          GoRoute(
              path: '/admin/block/:unitId', builder: (_, _) => const SizedBox()),
          GoRoute(
              path: '/admin/check-in',
              builder: (_, _) => const Text('CHECK-IN SCREEN')),
          GoRoute(
              path: '/admin/check-out',
              builder: (_, _) => const Text('CHECK-OUT SCREEN')),
          GoRoute(
              path: '/admin/kitchen-orders', builder: (_, _) => const SizedBox()),
          GoRoute(path: '/admin/maintenance', builder: (_, _) => const SizedBox()),
          GoRoute(path: '/owner/expenses', builder: (_, _) => const SizedBox()),
          GoRoute(path: '/admin/reviews', builder: (_, _) => const SizedBox()),
          GoRoute(path: '/admin/reports', builder: (_, _) => const SizedBox()),
          GoRoute(
              path: '/admin/outbox',
              builder: (_, _) => const Text('OUTBOX SCREEN')),
          GoRoute(
              path: '/property/:id',
              builder: (_, _) => const Text('PROPERTY SCREEN')),
        ],
      );

      return ProviderScope(
        overrides: [
          currentUserProvider.overrideWith((ref) => Stream.value(admin)),
          propertiesProvider.overrideWith((ref) async => [property]),
          unitsProvider(property.id).overrideWith((ref) async => [unit]),
          allBookingsProvider.overrideWith((ref) async => bookings),
          allReviewsProvider.overrideWith((ref) async => reviews),
          dashboardSummaryProvider.overrideWith((ref) async => DashboardSummary(
                todayRevenue: 0,
                monthRevenue: 52900,
                occupancyPct: 0,
                upcomingArrivals: bookings.length,
                cancellationsThisMonth: 0,
                activeHolds: 0,
              )),
        ],
        child: MaterialApp.router(routerConfig: router),
      );
    }

    Future<void> useTallSurface(WidgetTester tester) async {
      // The dashboard is one long scrollable column -- without a tall
      // enough surface, sections below the fold (Quick Actions, Guest
      // Experience, Business Snapshot) simply aren't laid out yet.
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }

    testWidgets('greets the signed-in admin by first name', (tester) async {
      await useTallSurface(tester);
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();

      expect(find.textContaining('Asha'), findsOneWidget);
    });

    testWidgets('shows READY when nobody is checked in', (tester) async {
      await useTallSurface(tester);
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();

      // "READY" also labels the (always-ready) Farmhouse Readiness card's
      // pill, so assert on the status card's own unique subtitle instead.
      expect(find.text('Available for booking'), findsOneWidget);
    });

    testWidgets('shows OCCUPIED when a guest is checked in', (tester) async {
      final bookings = [
        _booking('here',
            start: DateTime(2026, 9, 1),
            end: DateTime(2026, 9, 2),
            status: ReservationStatus.checkedIn),
      ];
      await useTallSurface(tester);
      await tester.pumpWidget(app(bookings: bookings));
      await tester.pumpAndSettle();

      expect(find.text('A guest is currently checked in'), findsOneWidget);
    });

    testWidgets('tapping Check-in navigates to /admin/check-in',
        (tester) async {
      await useTallSurface(tester);
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('quick-action-Check-in')));
      await tester.pumpAndSettle();

      expect(find.text('CHECK-IN SCREEN'), findsOneWidget);
    });

    testWidgets('tapping New Booking navigates to the property booking flow',
        (tester) async {
      await useTallSurface(tester);
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('quick-action-New Booking')));
      await tester.pumpAndSettle();

      expect(find.text('PROPERTY SCREEN'), findsOneWidget);
    });

    testWidgets('tapping Check-out navigates to /admin/check-out',
        (tester) async {
      await useTallSurface(tester);
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('quick-action-Check-out')));
      await tester.pumpAndSettle();

      expect(find.text('CHECK-OUT SCREEN'), findsOneWidget);
    });

    testWidgets('tapping Send Message navigates to /admin/outbox',
        (tester) async {
      await useTallSurface(tester);
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('quick-action-Send Message')));
      await tester.pumpAndSettle();

      expect(find.text('OUTBOX SCREEN'), findsOneWidget);
    });

    testWidgets('shows the real average rating from reviews', (tester) async {
      final reviews = [
        Review(
          id: 'r1',
          reservationId: 'res-1',
          customerId: 'c1',
          farmhouseRating: 5,
          cleanlinessRating: 5,
          foodRating: 5,
          serviceRating: 5,
          activitiesRating: 5,
          overallRating: 5,
          feedback: 'Wonderful stay!',
          createdAt: DateTime.now().subtract(const Duration(days: 2)),
        ),
        Review(
          id: 'r2',
          reservationId: 'res-2',
          customerId: 'c2',
          farmhouseRating: 4,
          cleanlinessRating: 4,
          foodRating: 4,
          serviceRating: 4,
          activitiesRating: 4,
          overallRating: 4,
          feedback: '',
          createdAt: DateTime.now().subtract(const Duration(days: 5)),
        ),
      ];
      await useTallSurface(tester);
      await tester.pumpWidget(app(reviews: reviews));
      await tester.pumpAndSettle();

      expect(find.text('4.5'), findsOneWidget);
    });
  });
}
