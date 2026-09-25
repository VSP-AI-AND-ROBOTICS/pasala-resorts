import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override, ProviderListenable;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pasala/core/errors.dart';
import 'package:pasala/data/models/current_charges.dart';
import 'package:pasala/data/models/payment_method.dart';
import 'package:pasala/data/models/reservation.dart';
import 'package:pasala/data/repositories/finance_repository.dart';
import 'package:pasala/data/repositories/room_status_repository.dart';
import 'package:pasala/data/repositories/stay_repository.dart';
import 'package:pasala/features/booking/payment_gateway.dart';
import 'package:pasala/features/finance/providers.dart';
import 'package:pasala/features/staff/providers.dart';
import 'package:pasala/features/stay/checkout_screen.dart';

import '../../support/fake_finance_source.dart';
import '../../support/fake_room_board_source.dart';

typedef _Checkout = ({
  String reservationId,
  String? paymentRef,
  num amount,
  PaymentMethod method,
});

/// Only [checkout] is reached from this screen.
class _FakeStayRepository implements StayRepository {
  final checkouts = <_Checkout>[];
  Object? checkoutError;

  @override
  Future<Reservation> checkout({
    required String reservationId,
    String? paymentRef,
    required num amount,
    PaymentMethod method = PaymentMethod.gateway,
  }) async {
    checkouts.add((
      reservationId: reservationId,
      paymentRef: paymentRef,
      amount: amount,
      method: method,
    ));
    if (checkoutError != null) throw checkoutError!;
    return Reservation(
      id: reservationId,
      unitId: 'u1',
      start: DateTime(2026, 9, 24),
      end: DateTime(2026, 9, 26),
      kind: ReservationKind.booking,
      status: ReservationStatus.checkedOut,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeGateway implements PaymentGateway {
  final charges = <num>[];
  final purposes = <PaymentPurpose>[];

  /// What [charge] answers; a success with `mock_<id>` when null.
  PaymentResult? result;

  @override
  Future<PaymentResult> charge({required String reservationId, required num amount, PaymentPurpose purpose = PaymentPurpose.advance}) async {
    charges.add(amount);
    purposes.add(purpose);
    return result ?? PaymentResult.success('mock_$reservationId');
  }
}

CurrentCharges _charges(double balance) => CurrentCharges(
      stayAmount: 3000,
      foodAmount: 0,
      activityAmount: 0,
      total: 3000,
      paid: 3000 - balance,
      balance: balance,
    );

/// Opens reception's desk checkout of `r1` at `/admin/check-out/r1`.
const _desk = #desk;

Future<void> _pump(
  WidgetTester tester, {
  required Object extra,
  required _FakeStayRepository stay,
  _FakeGateway? gateway,
  double balance = 2000,
  FakeFinanceSource? finance,
  void Function()? onChargesRead,
  List<Override> overrides = const [],
  List<ProviderListenable<Object?>> keepAlive = const [],
}) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final router = GoRouter(
    initialLocation: extra == _desk ? '/admin/check-out/r1' : '/my-stay/checkout',
    initialExtra: extra == _desk ? null : extra,
    routes: [
      GoRoute(path: '/my-stay/checkout', builder: (_, state) => checkoutScreenFor(state.extra)),
      GoRoute(
          path: '/admin/check-out/:reservationId',
          builder: (_, state) => CheckoutScreen(
              reservationId: state.pathParameters['reservationId']!, desk: true)),
      GoRoute(
          path: '/admin/check-out',
          builder: (_, state) =>
              Text('CHECK-OUT LIST ${state.uri.queryParameters['checkedOut']}')),
      GoRoute(
          path: '/my-stay/invoice/:id',
          builder: (_, state) => Text('INVOICE ${state.pathParameters['id']}')),
    ],
  );
  await tester.pumpWidget(ProviderScope(
    retry: (_, _) => null,
    overrides: [
      stayRepositoryProvider.overrideWithValue(stay),
      currentChargesProvider.overrideWith((ref, id) async {
        onChargesRead?.call();
        return _charges(balance);
      }),
      paymentGatewayProvider.overrideWithValue(gateway ?? _FakeGateway()),
      financeSourceProvider.overrideWithValue(finance ?? FakeFinanceSource()),
      ...overrides,
    ],
    child: MaterialApp.router(
      routerConfig: router,
      // Stands in for an open Finance screen, which keeps its summary alive.
      builder: (context, child) => Stack(children: [
        child!,
        Consumer(builder: (_, ref, _) {
          ref.watch(financeSummaryProvider('p1'));
          for (final provider in keepAlive) {
            ref.watch(provider);
          }
          return const SizedBox.shrink();
        }),
      ]),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  group('desk checkout', () {
    testWidgets('offers the five desk methods, Cash selected, and a reference field',
        (tester) async {
      await _pump(tester, extra: _desk, stay: _FakeStayRepository());

      for (final m in PaymentMethod.desk) {
        expect(find.byKey(Key('desk-method-${m.wire}')), findsOneWidget, reason: m.label);
      }
      expect(find.byKey(const Key('desk-method-gateway')), findsNothing);
      expect(tester.widget<ChoiceChip>(find.byKey(const Key('desk-method-cash'))).selected, isTrue);
      expect(find.byKey(const Key('desk-reference')), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Record ₹2,000 and check out'), findsOneWidget);
    });

    testWidgets('records the chosen method and the trimmed reference, and never calls the gateway',
        (tester) async {
      final stay = _FakeStayRepository();
      final gateway = _FakeGateway();
      await _pump(tester, extra: _desk, stay: stay, gateway: gateway);

      await tester.tap(find.byKey(const Key('desk-method-upi')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('desk-reference')), '  UTR123  ');
      await tester.tap(find.widgetWithText(FilledButton, 'Record ₹2,000 and check out'));
      await tester.pumpAndSettle();

      expect(stay.checkouts, [
        (reservationId: 'r1', paymentRef: 'UTR123', amount: 2000, method: PaymentMethod.upi),
      ]);
      expect(gateway.charges, isEmpty);
      expect(find.text('CHECK-OUT LIST r1'), findsOneWidget);
    });

    testWidgets('a blank reference is sent as none', (tester) async {
      final stay = _FakeStayRepository();
      await _pump(tester, extra: _desk, stay: stay);

      await tester.tap(find.widgetWithText(FilledButton, 'Record ₹2,000 and check out'));
      await tester.pumpAndSettle();

      expect(stay.checkouts.single.paymentRef, isNull);
      expect(stay.checkouts.single.method, PaymentMethod.cash);
    });

    testWidgets('the reference stops at 64 characters', (tester) async {
      await _pump(tester, extra: _desk, stay: _FakeStayRepository());

      await tester.enterText(find.byKey(const Key('desk-reference')), 'x' * 70);
      await tester.pump();

      final field = tester.widget<TextField>(find.byKey(const Key('desk-reference')));
      expect(field.controller!.text, hasLength(64));
    });

    // Review Focus 4.
    testWidgets('with nothing left to pay there is no method to pick', (tester) async {
      final stay = _FakeStayRepository();
      await _pump(tester, extra: _desk, stay: stay, balance: 0);

      expect(find.byKey(const Key('desk-method-cash')), findsNothing);
      expect(find.byKey(const Key('desk-reference')), findsNothing);
      await tester.tap(find.widgetWithText(FilledButton, 'Check out'));
      await tester.pumpAndSettle();

      expect(stay.checkouts, [
        (reservationId: 'r1', paymentRef: null, amount: 0, method: PaymentMethod.gateway),
      ]);
    });

    testWidgets('a refusal is shown and the screen stays', (tester) async {
      final stay = _FakeStayRepository()
        ..checkoutError = const InvalidState('desk payment methods are recorded by resort staff');
      await _pump(tester, extra: _desk, stay: stay);

      await tester.tap(find.widgetWithText(FilledButton, 'Record ₹2,000 and check out'));
      await tester.pumpAndSettle();

      expect(find.text('desk payment methods are recorded by resort staff'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Record ₹2,000 and check out'), findsOneWidget);
    });

    testWidgets('a desk checkout refetches the finance figures', (tester) async {
      final finance = FakeFinanceSource();
      await _pump(tester,
          extra: _desk, stay: _FakeStayRepository(), finance: finance);
      final before = finance.summaryCalls.length;

      await tester.tap(find.widgetWithText(FilledButton, 'Record ₹2,000 and check out'));
      await tester.pumpAndSettle();

      expect(finance.summaryCalls.length, greaterThan(before));
    });

    // The desk checkout used to be pushed from the check-out list, which
    // refetched these on return; it is now reached by URL (so a reload
    // keeps it), and a successful checkout goes back to the list by URL
    // too, so the screen refetches what checkout_booking changed itself.
    testWidgets(
        'a desk checkout refetches the room board, the check-out queue and '
        'the bookings list', (tester) async {
      final board = FakeRoomBoardSource();
      var checkedInCalls = 0;
      var bookingsCalls = 0;
      await _pump(
        tester,
        extra: _desk,
        stay: _FakeStayRepository(),
        overrides: [
          roomBoardSourceProvider.overrideWithValue(board),
          checkedInProvider.overrideWith((ref, propertyId) async {
            checkedInCalls++;
            return const <Reservation>[];
          }),
          allBookingsProvider.overrideWith((ref, propertyId) async {
            bookingsCalls++;
            return const <Reservation>[];
          }),
        ],
        // Stand in for the open Rooms tab, check-out list and dashboard.
        keepAlive: [
          roomBoardProvider('p1'),
          checkedInProvider('p1'),
          allBookingsProvider('p1'),
        ],
      );
      final boardBefore = board.boardCalls.length;
      final checkedInBefore = checkedInCalls;
      final bookingsBefore = bookingsCalls;

      await tester.tap(find.widgetWithText(FilledButton, 'Record ₹2,000 and check out'));
      await tester.pumpAndSettle();

      expect(find.text('CHECK-OUT LIST r1'), findsOneWidget);
      expect(board.boardCalls.length, greaterThan(boardBefore));
      expect(checkedInCalls, greaterThan(checkedInBefore));
      expect(bookingsCalls, greaterThan(bookingsBefore));
    });

    testWidgets('a desk checkout lands back on the check-out list, never the guest invoice',
        (tester) async {
      await _pump(tester, extra: _desk, stay: _FakeStayRepository());

      await tester.tap(find.widgetWithText(FilledButton, 'Record ₹2,000 and check out'));
      await tester.pumpAndSettle();

      expect(find.text('CHECK-OUT LIST r1'), findsOneWidget);
      expect(find.textContaining('INVOICE'), findsNothing);
    });
  });

  group('guest checkout', () {
    testWidgets('is unchanged: no methods, and the gateway takes the balance', (tester) async {
      final stay = _FakeStayRepository();
      final gateway = _FakeGateway();
      await _pump(tester, extra: 'r1', stay: stay, gateway: gateway);

      expect(find.byKey(const Key('desk-method-cash')), findsNothing);
      await tester.tap(find.widgetWithText(FilledButton, 'Pay ₹2,000 and check out'));
      await tester.pumpAndSettle();

      expect(gateway.charges, [2000]);
      expect(stay.checkouts, [
        (reservationId: 'r1', paymentRef: 'mock_r1', amount: 2000, method: PaymentMethod.gateway),
      ]);
      expect(find.text('INVOICE r1'), findsOneWidget);
    });

    testWidgets('pays the balance as a balance payment', (tester) async {
      final gateway = _FakeGateway();
      await _pump(tester, extra: 'r1', stay: _FakeStayRepository(), gateway: gateway);

      await tester.tap(find.widgetWithText(FilledButton, 'Pay ₹2,000 and check out'));
      await tester.pumpAndSettle();

      expect(gateway.purposes, [PaymentPurpose.balance]);
    });

    testWidgets('a failed payment shows why and re-reads the charges', (tester) async {
      final stay = _FakeStayRepository();
      final gateway = _FakeGateway()
        ..result = const PaymentResult.failure(
            'Your payment could not be added to this booking, so it is being refunded in full.');
      var chargesReads = 0;
      await _pump(tester,
          extra: 'r1', stay: stay, gateway: gateway, onChargesRead: () => chargesReads++);
      final readsBefore = chargesReads;

      await tester.tap(find.widgetWithText(FilledButton, 'Pay ₹2,000 and check out'));
      await tester.pumpAndSettle();

      expect(
          find.text('Your payment could not be added to this booking, so it is being refunded in full.'),
          findsOneWidget);
      expect(chargesReads, greaterThan(readsBefore));
      expect(stay.checkouts, isEmpty);
      expect(find.text('INVOICE r1'), findsNothing);
    });

    testWidgets('with nothing to pay it sends no-balance-due', (tester) async {
      final stay = _FakeStayRepository();
      await _pump(tester, extra: 'r1', stay: stay, balance: 0);

      await tester.tap(find.widgetWithText(FilledButton, 'Check out'));
      await tester.pumpAndSettle();

      expect(stay.checkouts.single.paymentRef, 'no-balance-due');
      expect(stay.checkouts.single.method, PaymentMethod.gateway);
    });
  });

  group('checkoutScreenFor', () {
    test("a reservation id is the guest's own checkout", () {
      final screen = checkoutScreenFor('r1') as CheckoutScreen;
      expect(screen.reservationId, 'r1');
      expect(screen.desk, isFalse);
    });

    test('anything else is refused', () {
      expect(() => checkoutScreenFor(null), throwsArgumentError);
    });
  });
}
