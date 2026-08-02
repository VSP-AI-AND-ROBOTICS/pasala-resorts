import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pasala/core/errors.dart';
import 'package:pasala/data/models/quote.dart';
import 'package:pasala/data/models/refund_quote.dart';
import 'package:pasala/data/models/reservation.dart';
import 'package:pasala/data/repositories/booking_repository.dart';
import 'package:pasala/features/account/booking_detail_screen.dart';
import 'package:pasala/features/booking/providers.dart' show reservationProvider;

/// A [RefundSource] fake whose `computeRefund` either returns a scripted
/// [RefundQuote] or throws a scripted [BookingFailure], recording every
/// reservation id it was asked about -- this is what lets a test prove the
/// fetch happens (and happens with the right id) BEFORE the cancellation
/// dialog opens, not that the dialog merely displays whatever it's handed.
class _FakeRefundSource implements RefundSource {
  _FakeRefundSource({RefundQuote? result, this.failure})
      : result = result ??
            const RefundQuote(daysBefore: 10, refundPct: 100, refundAmount: 13500);
  final RefundQuote result;
  final BookingFailure? failure;
  final List<String> calls = [];

  @override
  Future<RefundQuote> computeRefund(String reservationId) async {
    calls.add(reservationId);
    if (failure != null) throw failure!;
    return result;
  }
}

/// A [BookingActions] fake whose `cancel` either succeeds (returning a
/// cancelled copy of the reservation) or throws a scripted [BookingFailure],
/// recording every call it received so a test can assert exactly what was
/// sent to the server.
class _FakeCancelActions implements BookingActions {
  _FakeCancelActions({this.failure});
  final BookingFailure? failure;
  final List<({String reservationId, String reason})> cancelCalls = [];

  @override
  Future<Reservation> cancel({
    required String reservationId,
    required String reason,
  }) async {
    cancelCalls.add((reservationId: reservationId, reason: reason));
    if (failure != null) throw failure!;
    return Reservation(
      id: reservationId,
      unitId: 'unit-1',
      start: DateTime.utc(2026, 8, 3),
      end: DateTime.utc(2026, 8, 5),
      kind: ReservationKind.booking,
      status: ReservationStatus.cancelled,
    );
  }

  @override
  Future<Quote> quote({
    required String unitId,
    required DateTime from,
    required DateTime to,
    required int guests,
    String? slotTypeId,
    String? couponCode,
  }) =>
      throw UnimplementedError();

  @override
  Future<Reservation> createHold({
    required String unitId,
    required DateTime from,
    required DateTime to,
    required int guests,
    String? slotTypeId,
    num? expectedTotal,
    String? couponCode,
  }) =>
      throw UnimplementedError();

  @override
  Future<Reservation> confirm({
    required String reservationId,
    required String paymentRef,
    required num amount,
  }) =>
      throw UnimplementedError();
}

Quote _quote() => Quote.fromJson(const {
      'currency': 'INR',
      'guests': 4,
      'lines': [
        {
          'date': '2026-08-03',
          'label': 'Weekend rate',
          'amount': 12000,
          'extra_guests': 0,
          'extra_guest_amount': 0,
        },
      ],
      'subtotal': 12000,
      'cleaning_fee': 1500,
      'total': 13500,
    });

Reservation _reservation({
  required ReservationStatus status,
  String id = 'r1',
}) =>
    Reservation(
      id: id,
      unitId: 'unit-1',
      start: DateTime.utc(2026, 8, 3),
      end: DateTime.utc(2026, 8, 5),
      kind: ReservationKind.booking,
      status: status,
      guests: 4,
      quote: _quote(),
    );

/// I4: an admin block has no customer, no guests, and no quote -- it exists
/// purely to keep a unit off the calendar.
Reservation _block({String id = 'block-1'}) => Reservation(
      id: id,
      unitId: 'unit-1',
      start: DateTime.utc(2026, 8, 3),
      end: DateTime.utc(2026, 8, 5),
      kind: ReservationKind.block,
      status: ReservationStatus.confirmed,
      blockReason: 'roof repair',
    );

void main() {
  late GoRouter router;

  Widget app({
    required Reservation reservation,
    required BookingActions actions,
    RefundSource? refunds,
  }) {
    router = GoRouter(
      initialLocation: '/bookings',
      routes: [
        GoRoute(
          path: '/bookings',
          builder: (_, _) => const Scaffold(body: Text('bookings-list')),
        ),
        GoRoute(
          path: '/booking-detail/:id',
          builder: (_, state) =>
              BookingDetailScreen(reservationId: state.pathParameters['id']!),
        ),
      ],
    );
    return ProviderScope(
      overrides: [
        reservationProvider(reservation.id).overrideWith((ref) async => reservation),
        bookingActionsProvider.overrideWithValue(actions),
        refundSourceProvider.overrideWithValue(refunds ?? _FakeRefundSource()),
      ],
      child: MaterialApp.router(routerConfig: router),
    );
  }

  Future<void> openDetail(
    WidgetTester tester,
    Reservation reservation,
    BookingActions actions, {
    RefundSource? refunds,
  }) async {
    await tester.pumpWidget(
        app(reservation: reservation, actions: actions, refunds: refunds));
    await tester.pumpAndSettle();
    router.push('/booking-detail/${reservation.id}');
    await tester.pumpAndSettle();
  }

  testWidgets('shows the stored quote breakdown, not a recomputed one', (tester) async {
    final reservation = _reservation(status: ReservationStatus.confirmed);
    await openDetail(tester, reservation, _FakeCancelActions());

    expect(find.text('Weekend rate'), findsOneWidget);
    expect(find.text('₹13,500'), findsOneWidget,
        reason: 'the total must come straight from Quote.total, never be '
            're-derived in Dart');
  });

  testWidgets('the cancel action is present for a confirmed reservation', (tester) async {
    final reservation = _reservation(status: ReservationStatus.confirmed);
    await openDetail(tester, reservation, _FakeCancelActions());

    expect(find.byKey(const Key('cancel-booking-button')), findsOneWidget);
  });

  testWidgets('the cancel action is absent for a cancelled reservation', (tester) async {
    final reservation = _reservation(status: ReservationStatus.cancelled);
    await openDetail(tester, reservation, _FakeCancelActions());

    expect(find.byKey(const Key('cancel-booking-button')), findsNothing);
  });

  testWidgets('the cancel action is absent for a hold', (tester) async {
    final reservation = _reservation(status: ReservationStatus.hold);
    await openDetail(tester, reservation, _FakeCancelActions());

    expect(find.byKey(const Key('cancel-booking-button')), findsNothing);
  });

  testWidgets(
      'cancelling with a reason calls cancel with that reason, invalidates '
      'the list, and returns to it', (tester) async {
    final reservation = _reservation(status: ReservationStatus.confirmed);
    final actions = _FakeCancelActions();
    await openDetail(tester, reservation, actions);

    await tester.tap(find.byKey(const Key('cancel-booking-button')));
    await tester.pumpAndSettle();

    expect(find.textContaining('released'), findsOneWidget);
    // The computed refund line, and the separate "not yet automated" note
    // -- both present, neither one hidden or missing.
    expect(find.byKey(const Key('refund-preview-text')), findsOneWidget);
    expect(find.textContaining('not yet automated'), findsOneWidget);

    await tester.enterText(
        find.byKey(const Key('cancel-reason-field')), 'change of plans');
    await tester.tap(find.byKey(const Key('confirm-cancel-button')));
    await tester.pumpAndSettle();

    expect(actions.cancelCalls, [(reservationId: 'r1', reason: 'change of plans')]);
    expect(find.text('bookings-list'), findsOneWidget,
        reason: 'a successful cancel must pop back to the bookings list');
  });

  testWidgets(
      'fetches the refund preview from compute_refund BEFORE the dialog '
      'opens, and shows the exact figure it returned', (tester) async {
    final reservation = _reservation(status: ReservationStatus.confirmed);
    final refunds = _FakeRefundSource(
      result: const RefundQuote(daysBefore: 5, refundPct: 50, refundAmount: 6750),
    );
    await openDetail(tester, reservation, _FakeCancelActions(), refunds: refunds);

    await tester.tap(find.byKey(const Key('cancel-booking-button')));
    await tester.pumpAndSettle();

    expect(refunds.calls, ['r1'],
        reason: 'the reservation id must be fetched before the dialog is '
            'shown, not derived or guessed by the dialog itself');
    expect(
      find.text('You will be refunded ₹6,750 (50% of ₹13,500).'),
      findsOneWidget,
      reason: 'the figure comes straight from RefundQuote, never '
          'recomputed from quote.total in Dart',
    );
  });

  testWidgets(
      'a zero refund is stated plainly, not hidden or omitted', (tester) async {
    final reservation = _reservation(status: ReservationStatus.confirmed);
    final refunds = _FakeRefundSource(
      result: const RefundQuote(daysBefore: 0, refundPct: 0, refundAmount: 0),
    );
    await openDetail(tester, reservation, _FakeCancelActions(), refunds: refunds);

    await tester.tap(find.byKey(const Key('cancel-booking-button')));
    await tester.pumpAndSettle();

    expect(
      find.text('You will be refunded ₹0 (0% of ₹13,500).'),
      findsOneWidget,
      reason: 'a zero refund must still say so in the same line, not be '
          'silently dropped',
    );
  });

  testWidgets(
      'a BookingFailure from compute_refund surfaces its message and never '
      'opens the cancellation dialog', (tester) async {
    final reservation = _reservation(status: ReservationStatus.confirmed);
    final refunds = _FakeRefundSource(failure: const NetworkFailure());
    await openDetail(tester, reservation, _FakeCancelActions(), refunds: refunds);

    await tester.tap(find.byKey(const Key('cancel-booking-button')));
    await tester.pumpAndSettle();

    expect(find.text(const NetworkFailure().message), findsOneWidget);
    expect(find.byKey(const Key('cancel-reason-field')), findsNothing,
        reason: 'the dialog must not open on a failed refund preview -- '
            'showing a stale or missing figure would be worse than not '
            'showing the dialog at all');
    expect(find.byType(CircularProgressIndicator), findsNothing,
        reason: 'the button must be usable again, not stuck on a spinner');
  });

  testWidgets('dismissing the dialog with Keep booking cancels nothing', (tester) async {
    final reservation = _reservation(status: ReservationStatus.confirmed);
    final actions = _FakeCancelActions();
    await openDetail(tester, reservation, actions);

    await tester.tap(find.byKey(const Key('cancel-booking-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('keep-booking-button')));
    await tester.pumpAndSettle();

    expect(actions.cancelCalls, isEmpty);
    expect(find.byKey(const Key('cancel-booking-button')), findsOneWidget,
        reason: 'still on the detail screen, not popped');
  });

  testWidgets(
      'a BookingFailure from cancel surfaces its message and leaves the '
      'screen usable, rather than a stuck spinner', (tester) async {
    final reservation = _reservation(status: ReservationStatus.confirmed);
    final actions = _FakeCancelActions(failure: const NetworkFailure());
    await openDetail(tester, reservation, actions);

    await tester.tap(find.byKey(const Key('cancel-booking-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('cancel-reason-field')), 'change of plans');
    await tester.tap(find.byKey(const Key('confirm-cancel-button')));
    await tester.pumpAndSettle();

    expect(find.text(const NetworkFailure().message), findsOneWidget);
    expect(find.text('bookings-list'), findsNothing,
        reason: 'a failed cancel must not navigate away');
    expect(find.byKey(const Key('cancel-booking-button')), findsOneWidget,
        reason: 'the button must be usable again, not permanently disabled '
            'behind a spinner');
    final button =
        tester.widget<OutlinedButton>(find.byKey(const Key('cancel-booking-button')));
    expect(button.onPressed, isNotNull);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  group('admin block (I4)', () {
    testWidgets('renders without a guest count or a quote row', (tester) async {
      await openDetail(tester, _block(), _FakeCancelActions());

      // No crash, and no stray "null guests" / empty money rows.
      expect(find.textContaining('guests'), findsNothing);
      expect(find.text('Price breakdown'), findsNothing);
      expect(find.text('Admin block'), findsOneWidget);
      expect(find.textContaining('roof repair'), findsOneWidget);
    });

    testWidgets('the action is labelled Remove block, not Cancel booking',
        (tester) async {
      await openDetail(tester, _block(), _FakeCancelActions());

      expect(find.byKey(const Key('cancel-booking-button')), findsOneWidget);
      expect(find.text('Remove block'), findsOneWidget);
      expect(find.text('Cancel booking'), findsNothing);
    });

    testWidgets('removing a block calls cancel and returns to the list',
        (tester) async {
      final block = _block();
      final actions = _FakeCancelActions();
      await openDetail(tester, block, actions);

      await tester.tap(find.byKey(const Key('cancel-booking-button')));
      await tester.pumpAndSettle();

      // The block dialog must not promise a refund that will never happen.
      expect(find.textContaining('refund'), findsNothing);

      await tester.enterText(
          find.byKey(const Key('cancel-reason-field')), 'no longer needed');
      await tester.tap(find.byKey(const Key('confirm-cancel-button')));
      await tester.pumpAndSettle();

      expect(actions.cancelCalls,
          [(reservationId: block.id, reason: 'no longer needed')]);
      expect(find.text('bookings-list'), findsOneWidget);
    });
  });
}
