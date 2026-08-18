import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pasala/core/errors.dart';
import 'package:pasala/data/models/quote.dart';
import 'package:pasala/data/models/reservation.dart';
import 'package:pasala/data/models/unit.dart';
import 'package:pasala/data/repositories/booking_repository.dart';
import 'package:pasala/features/booking/booking_screen.dart';
import 'package:pasala/features/booking/payment_gateway.dart';
import 'package:pasala/features/booking/providers.dart';
import 'package:pasala/features/calendar/providers.dart';

/// A [BookingActions] fake that reproduces the one piece of database
/// behavior this entire defect hinges on: `reservations_no_overlap`, the
/// exclusion constraint with NO same-customer exemption (see
/// `supabase/migrations`). `createHold` throws [UnitUnavailable] whenever
/// the requested range overlaps any reservation still tracked as "live" in
/// [_live] -- exactly the 23P01 collision a resurrected Finding-1 bug would
/// reproduce against a real database. If this fake ever sees
/// [UnitUnavailable] surface out of the orchestration functions under test,
/// that means the client tried to hold a range its own still-live hold
/// already occupies.
class _FakeBookingActions implements BookingActions {
  Quote? quoteToReturn;

  final Map<String, Reservation> _live = {};
  final List<String> calls = [];
  final List<String> cancelledIds = [];
  int _nextId = 0;

  bool _overlaps(Reservation a, DateTime from, DateTime to) =>
      a.start.isBefore(to.toUtc()) && from.toUtc().isBefore(a.end);

  final List<String?> couponCodesSeen = [];

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
    return quoteToReturn!;
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
    couponCodesSeen.add(couponCode);
    for (final r in _live.values) {
      if (r.unitId == unitId && _overlaps(r, from, to)) {
        // The real 23P01 -> UnitUnavailable path. Reached only if a bug
        // let two live holds/bookings collide over the same range.
        throw const UnitUnavailable();
      }
    }
    final id = 'hold-${_nextId++}';
    final reservation = Reservation(
      id: id,
      unitId: unitId,
      start: from.toUtc(),
      end: to.toUtc(),
      kind: ReservationKind.booking,
      status: ReservationStatus.hold,
      holdExpiresAt: DateTime.now().toUtc().add(const Duration(minutes: 15)),
      occasion: occasion,
    );
    _live[id] = reservation;
    return reservation;
  }

  @override
  Future<Reservation> confirm({
    required String reservationId,
    required String paymentRef,
    required num amount,
  }) async {
    calls.add('confirm');
    final held = _live[reservationId];
    if (held == null) throw const NotFound();
    final confirmed = Reservation(
      id: held.id,
      unitId: held.unitId,
      start: held.start,
      end: held.end,
      kind: held.kind,
      status: ReservationStatus.confirmed,
    );
    _live[reservationId] = confirmed;
    return confirmed;
  }

  @override
  Future<Reservation> cancel({
    required String reservationId,
    required String reason,
  }) async {
    calls.add('cancel');
    cancelledIds.add(reservationId);
    final removed = _live.remove(reservationId);
    if (removed == null) throw const NotFound();
    return Reservation(
      id: removed.id,
      unitId: removed.unitId,
      start: removed.start,
      end: removed.end,
      kind: removed.kind,
      status: ReservationStatus.cancelled,
    );
  }
}

/// A [PaymentGateway] whose outcomes are scripted call-by-call, so a test
/// can fail the first charge and succeed the second. `MockGateway.alwaysFail`
/// can't express that shape on its own -- it is a single constant for the
/// whole gateway instance -- which is exactly why this fake exists.
class _ScriptedGateway implements PaymentGateway {
  _ScriptedGateway(this._results);
  final List<PaymentResult> _results;
  int callCount = 0;

  @override
  Future<PaymentResult> charge({
    required String reservationId,
    required num amount,
  }) async {
    final result = _results[callCount.clamp(0, _results.length - 1)];
    callCount++;
    return result;
  }
}

Quote _quote({num total = 5500}) => Quote.fromJson({
      'currency': 'INR',
      'guests': 2,
      'lines': [
        {
          'date': '2026-08-10',
          'label': 'Weekday rate',
          'amount': total,
          'extra_guests': 0,
          'extra_guest_amount': 0,
        },
      ],
      'subtotal': total,
      'cleaning_fee': 0,
      'total': total,
    });

const _unit = Unit(
  id: 'unit-1',
  propertyId: 'prop-1',
  name: 'Garden Room',
  capacityBase: 2,
  capacityMax: 4,
  bookingMode: BookingMode.nightly,
  isActive: true,
);

HoldParams _params({
  DateTime? from,
  DateTime? to,
  String? unitId,
  String? couponCode,
  String? occasion,
}) =>
    HoldParams(
      unitId: unitId ?? 'unit-1',
      from: from ?? DateTime.utc(2026, 8, 10),
      to: to ?? DateTime.utc(2026, 8, 12),
      guests: 2,
      slotTypeId: null,
      couponCode: couponCode,
      occasion: occasion,
    );

void main() {
  test('HoldParams equality includes occasion', () {
    HoldParams params(String? occasion) => HoldParams(
          unitId: 'u1',
          from: DateTime.utc(2026, 8, 3),
          to: DateTime.utc(2026, 8, 5),
          guests: 2,
          slotTypeId: null,
          couponCode: null,
          occasion: occasion,
        );

    expect(params('Birthday'), params('Birthday'));
    expect(params('Birthday') == params('Anniversary'), isFalse);
    expect(params('Birthday') == params(null), isFalse);
  });

  group('decideHoldAction (pure)', () {
    test('no live hold -> none, regardless of the incoming selection', () {
      expect(
        decideHoldAction(hold: null, heldParams: null, nextParams: _params()),
        HoldAction.none,
      );
    });

    test('live hold + byte-for-byte identical selection -> reuseExisting', () {
      final hold = Reservation(
        id: 'r1',
        unitId: 'unit-1',
        start: DateTime.utc(2026, 8, 10),
        end: DateTime.utc(2026, 8, 12),
        kind: ReservationKind.booking,
        status: ReservationStatus.hold,
      );
      expect(
        decideHoldAction(
          hold: hold,
          heldParams: _params(),
          nextParams: _params(),
        ),
        HoldAction.reuseExisting,
      );
    });

    for (final (label, other) in [
      ('unit differs', _params(unitId: 'unit-2')),
      ('from differs', _params(from: DateTime.utc(2026, 8, 11))),
      ('to differs', _params(to: DateTime.utc(2026, 8, 13))),
      // A coupon change must invalidate a live hold too -- reusing a hold
      // whose stored quote predates a newly-applied coupon would confirm
      // the OLD (higher) amount against a payment charged at the NEW
      // (discounted) one. See HoldParams.couponCode's doc comment.
      ('coupon code differs', _params(couponCode: 'SAVE10')),
    ]) {
      test('live hold + selection where $label -> releaseAndClear', () {
        final hold = Reservation(
          id: 'r1',
          unitId: 'unit-1',
          start: DateTime.utc(2026, 8, 10),
          end: DateTime.utc(2026, 8, 12),
          kind: ReservationKind.booking,
          status: ReservationStatus.hold,
        );
        expect(
          decideHoldAction(
              hold: hold, heldParams: _params(), nextParams: other),
          HoldAction.releaseAndClear,
        );
      });
    }

    test('live hold + incomplete selection (nextParams null) -> releaseAndClear', () {
      final hold = Reservation(
        id: 'r1',
        unitId: 'unit-1',
        start: DateTime.utc(2026, 8, 10),
        end: DateTime.utc(2026, 8, 12),
        kind: ReservationKind.booking,
        status: ReservationStatus.hold,
      );
      expect(
        decideHoldAction(hold: hold, heldParams: _params(), nextParams: null),
        HoldAction.releaseAndClear,
      );
    });
  });

  group('resolveSelectionChange (pure orchestration + fake repository)', () {
    test('no hold live: no cancel call, resolves to none/no hold', () async {
      final actions = _FakeBookingActions();
      final result = await resolveSelectionChange(
        actions: actions,
        currentHold: null,
        currentHeldParams: null,
        nextParams: _params(),
      );

      expect(result.action, HoldAction.none);
      expect(actions.calls, isEmpty);
    });

    test(
        'selection changes while a hold is live: cancel is called with the '
        'OLD hold id, and the fake reports it live no more', () async {
      final actions = _FakeBookingActions();
      final oldHold = await actions.createHold(
        unitId: 'unit-1',
        from: DateTime.utc(2026, 8, 10),
        to: DateTime.utc(2026, 8, 12),
        guests: 2,
      );
      actions.calls.clear(); // isolate the createHold above from assertions

      final result = await resolveSelectionChange(
        actions: actions,
        currentHold: oldHold,
        currentHeldParams: _params(),
        // A different range -- the customer picked new dates.
        nextParams: _params(from: DateTime.utc(2026, 8, 20), to: DateTime.utc(2026, 8, 22)),
      );

      expect(result.action, HoldAction.releaseAndClear);
      expect(result.hold, isNull);
      expect(actions.calls, ['cancel']);
      expect(actions.cancelledIds, [oldHold.id]);

      // The freed range is now bookable again by anyone, including a
      // subsequent createHold call for it from the SAME customer -- proving
      // cancel() actually freed the range in the fake, not just recorded a
      // call.
      final rehold = await actions.createHold(
        unitId: 'unit-1',
        from: DateTime.utc(2026, 8, 10),
        to: DateTime.utc(2026, 8, 12),
        guests: 2,
      );
      expect(rehold.id, isNot(oldHold.id));
    });

    test(
        'a matching re-selection reuses the hold and never calls cancel or '
        'createHold', () async {
      final actions = _FakeBookingActions();
      final hold = await actions.createHold(
        unitId: 'unit-1',
        from: DateTime.utc(2026, 8, 10),
        to: DateTime.utc(2026, 8, 12),
        guests: 2,
      );
      actions.calls.clear();

      final result = await resolveSelectionChange(
        actions: actions,
        currentHold: hold,
        currentHeldParams: _params(),
        nextParams: _params(), // identical
      );

      expect(result.action, HoldAction.reuseExisting);
      expect(result.hold, same(hold));
      expect(actions.calls, isEmpty,
          reason: 'reusing a still-matching hold must not touch the '
              'repository at all');
    });

    test(
        'a release failure is reported, not thrown -- caller can keep going',
        () async {
      final failingActions = _ThrowingCancelActions();
      final hold = Reservation(
        id: 'r1',
        unitId: 'unit-1',
        start: DateTime.utc(2026, 8, 10),
        end: DateTime.utc(2026, 8, 12),
        kind: ReservationKind.booking,
        status: ReservationStatus.hold,
      );

      final result = await resolveSelectionChange(
        actions: failingActions,
        currentHold: hold,
        currentHeldParams: _params(),
        nextParams: _params(from: DateTime.utc(2026, 9, 1), to: DateTime.utc(2026, 9, 3)),
      );

      expect(result.releaseFailure, isA<NetworkFailure>());
      expect(result.hold, isNull, reason: 'the UI must not stay pinned to a '
          'hold it could not confirm was released -- a stale one still '
          'expires on its own in 15 minutes');
    });
  });

  group('resolveHoldForPayment (pure orchestration + fake repository)', () {
    test('no matching live hold: creates a fresh one', () async {
      final actions = _FakeBookingActions()..quoteToReturn = _quote();
      final hold = await resolveHoldForPayment(
        actions: actions,
        currentHold: null,
        currentHeldParams: null,
        params: _params(),
        expectedTotal: 5500,
      );

      expect(hold.status, ReservationStatus.hold);
      expect(actions.calls, ['createHold']);
    });

    test('a matching live hold is reused: createHold is never called', () async {
      final actions = _FakeBookingActions();
      final existing = await actions.createHold(
        unitId: 'unit-1',
        from: DateTime.utc(2026, 8, 10),
        to: DateTime.utc(2026, 8, 12),
        guests: 2,
      );
      actions.calls.clear();

      final hold = await resolveHoldForPayment(
        actions: actions,
        currentHold: existing,
        currentHeldParams: _params(),
        params: _params(),
        expectedTotal: 5500,
      );

      expect(hold, same(existing));
      expect(actions.calls, isEmpty);
    });

    test('a fresh hold carries the coupon code through to createHold',
        () async {
      final actions = _FakeBookingActions()..quoteToReturn = _quote();
      await resolveHoldForPayment(
        actions: actions,
        currentHold: null,
        currentHeldParams: null,
        params: _params(couponCode: 'SAVE10'),
        expectedTotal: 5500,
      );

      expect(actions.couponCodesSeen, ['SAVE10'],
          reason: 'skipping this is the exact trap the brief calls out: '
              'create_hold must re-quote WITH the same coupon the client '
              'was quoted, or a couponed hold fails with a stale-quote '
              'error');
    });

    test('no coupon means createHold is called with a null coupon code',
        () async {
      final actions = _FakeBookingActions()..quoteToReturn = _quote();
      await resolveHoldForPayment(
        actions: actions,
        currentHold: null,
        currentHeldParams: null,
        params: _params(),
        expectedTotal: 5500,
      );

      expect(actions.couponCodesSeen, [null]);
    });
  });

  group(
      'Critical-defect regression: same-customer retry after a declined '
      'payment (fake repository reproduces the 23P01 exclusion constraint)',
      () {
    test(
        'a declined charge does not orphan the hold, and the retry reuses '
        'it -- the customer never sees UnitUnavailable', () async {
      final actions = _FakeBookingActions()..quoteToReturn = _quote();
      final gateway = _ScriptedGateway([
        const PaymentResult.failure('Mock gateway declined the payment.'),
        const PaymentResult.success('ref-ok'),
      ]);
      final params = _params();

      Reservation? hold;
      HoldParams? heldParams;
      BookingFailure? lastFailure;

      Future<void> attemptPay() async {
        final resolvedHold = await resolveHoldForPayment(
          actions: actions,
          currentHold: hold,
          currentHeldParams: heldParams,
          params: params,
          expectedTotal: 5500,
        );
        hold = resolvedHold;
        heldParams = params;

        final payment =
            await gateway.charge(reservationId: resolvedHold.id, amount: 5500);
        if (!payment.succeeded) {
          // Mirrors `_pay`'s catch: an InvalidState (declined card) does NOT
          // clear `hold`/`heldParams` -- the hold is still live.
          lastFailure = InvalidState(payment.failureMessage!);
          return;
        }
        hold = await actions.confirm(
            reservationId: resolvedHold.id, paymentRef: payment.reference, amount: 5500);
      }

      // Attempt 1: declined.
      await attemptPay();
      expect(lastFailure, isA<InvalidState>());
      expect(hold, isNotNull, reason: 'the hold must survive a payment '
          'decline -- it is still live server-side');
      expect(actions.calls, ['createHold']);

      // Customer retries with the SAME dates.
      lastFailure = null;
      await attemptPay();

      expect(lastFailure, isNull, reason: 'the retry must succeed');
      expect(
        actions.calls,
        ['createHold', 'confirm'],
        reason: 'the retry must reuse the existing hold: exactly one '
            'createHold total, no second one colliding with the first, and '
            'no UnitUnavailable was ever thrown by the fake\'s overlap check',
      );
      expect(hold!.status, ReservationStatus.confirmed);
    });
  });

  testWidgets('createHold passes the occasion through to the fake', (
    tester,
  ) async {
    final actions = _FakeBookingActions()
      ..quoteToReturn = _quote();
    final reservation = await actions.createHold(
      unitId: 'u1',
      from: DateTime.utc(2026, 8, 3),
      to: DateTime.utc(2026, 8, 5),
      guests: 2,
      occasion: 'Birthday celebration',
    );
    expect(reservation.occasion, 'Birthday celebration');
  });

  // ---------------------------------------------------------------------
  // Widget-level test: Finding 3 (re-entrancy) needs a real button and two
  // taps with no `pump()` between them, which only a widget test can give.
  // ---------------------------------------------------------------------

  group('BookingScreen widget', () {
    Widget bookingApp({
      required BookingActions actions,
      required PaymentGateway gateway,
    }) {
      final router = GoRouter(
        initialLocation: '/book/${_unit.id}',
        routes: [
          GoRoute(
            path: '/book/:unitId',
            builder: (_, state) => Scaffold(
              body: BookingScreen(unitId: state.pathParameters['unitId']!),
            ),
          ),
          GoRoute(
            path: '/booking/:id',
            builder: (_, state) => Scaffold(
              body: Text('confirmed:${state.pathParameters['id']}'),
            ),
          ),
        ],
      );

      return ProviderScope(
        overrides: [
          unitByIdProvider(_unit.id).overrideWith((ref) async => _unit),
          unitCalendarSourceProvider
              .overrideWithValue(_NoOccupancyCalendarSource()),
          bookingActionsProvider.overrideWithValue(actions),
          paymentGatewayProvider.overrideWithValue(gateway),
        ],
        child: MaterialApp.router(routerConfig: router),
      );
    }

    testWidgets('does not wrap itself in its own Scaffold or AppBar', (
      tester,
    ) async {
      // Now that BookingScreen no longer supplies its own
      // SingleChildScrollView, its content needs a real scrollable ancestor
      // to avoid overflowing the fixed test viewport -- in the real app,
      // Task 2's PropertyScreen provides that; here, since this test's own
      // router route wraps BookingScreen in a bare Scaffold with no
      // scrollable, the surface is grown instead so the unrelated overflow
      // doesn't mask the thing this test actually checks.
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      tester.view.physicalSize = const Size(800, 4000);
      tester.view.devicePixelRatio = 1.0;

      final actions = _FakeBookingActions()..quoteToReturn = _quote();
      final gateway = _ScriptedGateway([const PaymentResult.success('ref-1')]);

      await tester.pumpWidget(bookingApp(actions: actions, gateway: gateway));
      await tester.pumpAndSettle();

      // The test's own router route wraps BookingScreen in exactly one
      // Scaffold (see the `bookingApp` helper) -- if BookingScreen still
      // supplied its own, there would be two.
      expect(find.byType(Scaffold), findsOneWidget);
      expect(find.byType(AppBar), findsNothing);
    });

    Future<void> pickRange(
      WidgetTester tester,
      _MonthCursor cursor,
      DateTime from,
      DateTime to,
    ) async {
      Future<void> tapDay(DateTime day) async {
        while (cursor.value.year != day.year || cursor.value.month != day.month) {
          await tester.tap(find.byIcon(Icons.chevron_right));
          await tester.pumpAndSettle();
          cursor.value = DateTime(cursor.value.year, cursor.value.month + 1);
        }
        await tester.tap(find.byKey(Key('day-${day.day}')));
        await tester.pumpAndSettle();
      }

      await tapDay(from);
      await tapDay(to);
    }

    testWidgets('double-tap on Pay charges exactly once (Finding 3)',
        (tester) async {
      final actions = _FakeBookingActions()..quoteToReturn = _quote();
      final gateway = _ScriptedGateway([
        const PaymentResult.success('ref-1'),
        const PaymentResult.success('ref-2'),
      ]);

      await tester.pumpWidget(bookingApp(actions: actions, gateway: gateway));
      await tester.pumpAndSettle();

      final now = DateTime.now();
      final from = DateTime(now.year, now.month, now.day).add(const Duration(days: 5));
      final to = from.add(const Duration(days: 2));
      final cursor = _MonthCursor(DateTime(now.year, now.month));
      await pickRange(tester, cursor, from, to);

      final payButton =
          tester.widget<FilledButton>(find.byKey(const Key('pay-button')));

      // Invoke the button's own `onPressed` twice, back-to-back, with no
      // `await` between the calls -- this is the actual race
      // `if (_busy) return;` closes. Going through `tester.tap()` twice
      // (each call internally awaits a down/up gesture sequence) turned out
      // to let Dart's microtask queue fully drain the FIRST `_pay()` call
      // -- including the fake gateway charge and confirm, all of which
      // resolve via plain microtasks with no real timer/IO boundary --
      // before the second `tester.tap()` line even ran, so it was
      // dispatching a second, legitimate, non-racing tap rather than a
      // genuine simultaneous double-press. Calling `onPressed!()` twice on
      // the same synchronous line reproduces the real race precisely:
      // `_pay()` runs synchronously up to its first `await` (setting
      // `_busy = true` on the way, since `setState`'s callback runs
      // synchronously), so the second call sees `_busy == true` and returns
      // immediately -- exactly what a real double-tap needs to hit.
      payButton.onPressed!();
      payButton.onPressed!();

      // Drain the async chain WITHOUT advancing the fake clock (no Duration
      // argument), so the 1-second hold ticker started once createHold
      // resolves never actually fires during this test.
      for (var i = 0; i < 15; i++) {
        await tester.pump();
      }

      expect(gateway.callCount, 1,
          reason: 'a second tap before the first pay() completed must be a '
              'no-op -- a real gateway behind this seam would otherwise '
              'double-charge the customer');
      expect(actions.calls.where((c) => c == 'createHold').length, 1);
      expect(find.text('confirmed:hold-0'), findsOneWidget,
          reason: 'the single accepted tap must still complete the booking');
    });

    testWidgets(
        'a declined payment shows Resume payment/Cancel hold, and Resume '
        're-opens the SAME hold/quote (no new createHold or quote call)',
        (tester) async {
      final actions = _FakeBookingActions()..quoteToReturn = _quote();
      final gateway = _ScriptedGateway([
        const PaymentResult.failure('Mock gateway declined the payment.'),
        const PaymentResult.success('ref-ok'),
      ]);

      await tester.pumpWidget(bookingApp(actions: actions, gateway: gateway));
      await tester.pumpAndSettle();

      final now = DateTime.now();
      final from = DateTime(now.year, now.month, now.day).add(const Duration(days: 5));
      final to = from.add(const Duration(days: 2));
      final cursor = _MonthCursor(DateTime(now.year, now.month));
      await pickRange(tester, cursor, from, to);
      actions.calls.clear(); // isolate the quote fetch above from assertions

      // Sheet auto-opens once the quote resolves.
      expect(find.byKey(const Key('pay-button')), findsOneWidget);
      await tester.tap(find.byKey(const Key('pay-button')));
      await tester.pumpAndSettle();

      expect(actions.calls, ['createHold'],
          reason: 'the decline must not touch the hold at all -- it stays '
              'live server-side');
      expect(gateway.callCount, 1);

      // The sheet closed on the decline (Finding 2's pop), and the customer
      // is back on BookingScreen with no visible way to pay -- until the
      // dead-end fix.
      expect(find.byKey(const Key('pay-button')), findsNothing);
      expect(find.byKey(const Key('resume-hold-button')), findsOneWidget);
      expect(find.byKey(const Key('cancel-hold-button')), findsOneWidget);

      // Resuming must reopen the sheet WITHOUT creating a new hold or
      // re-quoting -- it reuses the existing hold and its stored quote.
      await tester.tap(find.byKey(const Key('resume-hold-button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('pay-button')), findsOneWidget,
          reason: 'Resume payment must reopen the QuoteSheet');
      expect(actions.calls, ['createHold'],
          reason: 'reopening the sheet must not call quote or createHold '
              'again');

      // Retrying now succeeds, reusing the same hold (exactly Finding 1's
      // retry-after-decline path).
      await tester.tap(find.byKey(const Key('pay-button')));
      await tester.pumpAndSettle();

      expect(gateway.callCount, 2);
      expect(
        actions.calls,
        ['createHold', 'confirm'],
        reason: 'the retry via Resume must reuse the existing hold -- '
            'exactly one createHold total',
      );
      expect(find.text('confirmed:hold-0'), findsOneWidget);
    });

    testWidgets(
        'Cancel hold calls cancel_booking immediately and removes the resume '
        'banner, instead of making the customer wait out the 15-minute '
        'expiry', (tester) async {
      final actions = _FakeBookingActions()..quoteToReturn = _quote();
      final gateway = _ScriptedGateway([
        const PaymentResult.failure('Mock gateway declined the payment.'),
      ]);

      await tester.pumpWidget(bookingApp(actions: actions, gateway: gateway));
      await tester.pumpAndSettle();

      final now = DateTime.now();
      final from = DateTime(now.year, now.month, now.day).add(const Duration(days: 5));
      final to = from.add(const Duration(days: 2));
      final cursor = _MonthCursor(DateTime(now.year, now.month));
      await pickRange(tester, cursor, from, to);

      await tester.tap(find.byKey(const Key('pay-button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('cancel-hold-button')), findsOneWidget);
      final heldId = actions.cancelledIds; // empty so far
      expect(heldId, isEmpty);

      await tester.tap(find.byKey(const Key('cancel-hold-button')));
      await tester.pumpAndSettle();

      expect(actions.cancelledIds, ['hold-0'],
          reason: 'Cancel hold must call cancel_booking for the held '
              'reservation, freeing the dates immediately');
      expect(find.byKey(const Key('hold-banner')), findsNothing,
          reason: 'the banner (and its Resume/Cancel controls) must '
              'disappear once the hold is gone');
      expect(find.byKey(const Key('resume-hold-button')), findsNothing);
    });
  });
}

/// Records a mutable "currently displayed month" in step with the number of
/// times the test has tapped the calendar's forward chevron, so a test can
/// navigate to an arbitrary day regardless of what "today" is when the
/// suite runs.
class _MonthCursor {
  _MonthCursor(this.value);
  DateTime value;
}

/// A [UnitCalendarSource] with no occupied dates at all -- every day in
/// range is available to tap. `BookingScreen`'s hold lifecycle is what's
/// under test here, not the calendar's occupancy rendering (that's
/// `availability_calendar_test.dart`'s job).
class _NoOccupancyCalendarSource implements UnitCalendarSource {
  @override
  Stream<List<Reservation>> watchUnit(String unitId) => const Stream.empty();

  @override
  Future<List<Reservation>> fetchUnit(String unitId) async => const [];
}

/// A [BookingActions] whose `cancel` always fails with a [NetworkFailure],
/// used to prove [resolveSelectionChange] reports a release failure instead
/// of throwing out of the caller.
class _ThrowingCancelActions implements BookingActions {
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
    String? occasion,
  }) =>
      throw UnimplementedError();

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
  }) async {
    throw const NetworkFailure();
  }
}
