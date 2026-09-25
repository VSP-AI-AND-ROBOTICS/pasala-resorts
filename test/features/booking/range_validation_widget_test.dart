import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:pasala/data/models/quote.dart';
import 'package:pasala/data/models/reservation.dart';
import 'package:pasala/data/models/unit.dart';
import 'package:pasala/data/repositories/booking_repository.dart';
import 'package:pasala/features/booking/booking_screen.dart';
import 'package:pasala/features/booking/payment_gateway.dart';
import 'package:pasala/features/booking/providers.dart';
import 'package:pasala/features/calendar/providers.dart';

const _unit = Unit(
  id: 'unit-1',
  propertyId: 'prop-1',
  name: 'Garden Room',
  capacityBase: 2,
  capacityMax: 4,
  bookingMode: BookingMode.nightly,
  isActive: true,
);

/// A [BookingActions] that fails the test if createHold is ever called --
/// this file only exercises the client-side range check, which must reject
/// an invalid range before it ever reaches the repository.
class _NoCreateHoldActions implements BookingActions {
  final List<String> calls = [];

  @override
  Future<Quote> quote({
    required String unitId,
    required DateTime from,
    required DateTime to,
    required int guests,
    String? slotTypeId,
    String? couponCode,
  }) async {
    calls.add('quote');
    return Quote.fromJson({
      'currency': 'INR',
      'guests': guests,
      'lines': const [],
      'subtotal': 0,
      'cleaning_fee': 0,
      'total': 0,
    });
  }

  @override
  Future<Reservation> createHold({
    required String unitId,
    required DateTime from,
    required DateTime to,
    required int guests,
    String? slotTypeId,
    num? expectedTotal,
    String? couponCode,
    String? occasion,
  }) async {
    calls.add('createHold');
    throw StateError('createHold must not be called for an invalid range');
  }

  @override
  Future<Reservation> confirm({
    required String reservationId,
    required String paymentRef,
    required num amount,
  }) =>
      throw UnimplementedError();

  @override
  Future<Reservation> cancel({
    required String reservationId,
    required String reason,
  }) =>
      throw UnimplementedError();
}

class _NoopGateway implements PaymentGateway {
  @override
  Future<PaymentResult> charge({
    required String reservationId,
    required num amount,
  }) =>
      throw UnimplementedError();
}

/// A [UnitCalendarSource] with one confirmed booking in the middle of an
/// otherwise-open month, so a drag across it can be exercised.
class _MidMonthBookedSource implements UnitCalendarSource {
  _MidMonthBookedSource(this.reservations);
  final List<Reservation> reservations;

  @override
  Stream<List<Reservation>> watchUnit(String unitId) =>
      Stream.value(reservations);

  @override
  Future<List<Reservation>> fetchUnit(String unitId) async => reservations;
}

class _MonthCursor {
  _MonthCursor(this.value);
  DateTime value;
}

void main() {
  Widget bookingApp({
    required BookingActions actions,
    required List<Reservation> reservations,
  }) {
    final router = GoRouter(
      initialLocation: '/book/${_unit.id}',
      routes: [
        GoRoute(
          path: '/book/:unitId',
          builder: (_, state) => Scaffold(
            body: SingleChildScrollView(
              child: BookingScreen(unitId: state.pathParameters['unitId']!),
            ),
          ),
        ),
      ],
    );

    return ProviderScope(
      overrides: [
        unitByIdProvider(_unit.id).overrideWith((ref) async => _unit),
        unitCalendarSourceProvider
            .overrideWithValue(_MidMonthBookedSource(reservations)),
        bookingActionsProvider.overrideWithValue(actions),
        paymentGatewayProvider.overrideWithValue(_NoopGateway()),
      ],
      child: MaterialApp.router(routerConfig: router),
    );
  }

  Future<void> tapDay(
    WidgetTester tester,
    _MonthCursor cursor,
    DateTime day,
  ) async {
    while (cursor.value.year != day.year || cursor.value.month != day.month) {
      await tester.tap(find.byIcon(Icons.chevron_right));
      await tester.pumpAndSettle();
      cursor.value = DateTime(cursor.value.year, cursor.value.month + 1);
    }
    final dayFinder = find.byKey(Key('day-${day.day}'));
    await tester.ensureVisible(dayFinder);
    await tester.pumpAndSettle();
    await tester.tap(dayFinder);
    await tester.pumpAndSettle();
  }

  // The calendar now opens in a bottom sheet from the "Check-in" field
  // instead of sitting inline -- open it once before picking either day;
  // it stays open across both taps and auto-closes once the range is
  // complete (see `_BookingScreenState._openDatePickerSheet`).
  Future<void> openDateSheet(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('check-in-field')));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'completing a range that crosses a booked night is rejected with an '
      'error, and does not create a hold', (tester) async {
    final now = DateTime.now();
    final from = DateTime(now.year, now.month, now.day).add(
      const Duration(days: 5),
    );
    final bookedNight = from.add(const Duration(days: 1));
    final to = from.add(const Duration(days: 3));

    final reservations = [
      Reservation(
        id: 'other',
        unitId: _unit.id,
        start: bookedNight,
        end: bookedNight.add(const Duration(days: 1)),
        kind: ReservationKind.booking,
        status: ReservationStatus.confirmed,
      ),
    ];
    final actions = _NoCreateHoldActions();

    await tester.pumpWidget(
      bookingApp(actions: actions, reservations: reservations),
    );
    await tester.pumpAndSettle();

    final cursor = _MonthCursor(DateTime(now.year, now.month));
    await openDateSheet(tester);
    await tapDay(tester, cursor, from);
    await tapDay(tester, cursor, to);

    expect(
      find.textContaining("aren't available"),
      findsOneWidget,
      reason: 'the completing tap must surface an error instead of silently '
          'accepting a range that crosses a booked night',
    );
    expect(actions.calls, isEmpty,
        reason: 'an invalid range must never reach createHold/quote');
  });

  // E2E (guest.spec.ts): the date sheet's month arrows had no accessible
  // name, so a screen reader announced two bare "button"s and the web
  // suite had to guess which unlabelled button was "next" -- which broke
  // as soon as other unlabelled buttons were on the page.
  testWidgets('the date sheet names its month arrows for screen readers',
      (tester) async {
    await tester.pumpWidget(
      bookingApp(actions: _NoCreateHoldActions(), reservations: const []),
    );
    await tester.pumpAndSettle();
    await openDateSheet(tester);

    expect(find.byTooltip('Previous month'), findsOneWidget);
    expect(find.byTooltip('Next month'), findsOneWidget);

    final now = DateTime.now();
    final next = DateTime(now.year, now.month + 1);
    await tester.tap(find.byTooltip('Next month'));
    await tester.pumpAndSettle();
    expect(find.text(DateFormat.yMMMM().format(next)), findsOneWidget);

    await tester.tap(find.byTooltip('Previous month'));
    await tester.pumpAndSettle();
    expect(find.text(DateFormat.yMMMM().format(DateTime(now.year, now.month))),
        findsOneWidget);
  });
}
