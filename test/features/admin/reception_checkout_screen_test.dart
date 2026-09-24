import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pasala/core/current_resort.dart';
import 'package:pasala/data/models/reservation.dart';
import 'package:pasala/data/models/resort_membership.dart';
import 'package:pasala/data/repositories/room_status_repository.dart';
import 'package:pasala/data/repositories/stay_repository.dart';
import 'package:pasala/features/admin/reception_checkout_screen.dart';

import '../../support/fake_room_board_source.dart';

const _resort =
    ResortMembership(propertyId: 'p1', resortName: 'Pasala', role: ResortRole.admin);

class _FixedResort extends CurrentResort {
  @override
  ResortMembership? build() => _resort;
}

Reservation _checkedIn(String id, {String? customerName}) => Reservation(
      id: id,
      unitId: 'u1',
      start: DateTime(2026, 9, 1),
      end: DateTime(2026, 9, 3),
      kind: ReservationKind.booking,
      status: ReservationStatus.checkedIn,
      customerName: customerName,
      guests: 2,
    );

final listedPropertyIds = <String>[];

Widget _appFor(List<Reservation> guests) {
  final router = GoRouter(
    initialLocation: '/admin/check-out',
    routes: [
      GoRoute(
          path: '/admin/check-out',
          builder: (_, _) => const ReceptionCheckoutScreen()),
      GoRoute(
          path: '/my-stay/checkout',
          builder: (_, _) => const Text('CHECKOUT SCREEN')),
    ],
  );
  return ProviderScope(
    overrides: [
      checkedInProvider.overrideWith((ref, propertyId) async {
        listedPropertyIds.add(propertyId);
        return guests;
      }),
      currentResortProvider.overrideWith(_FixedResort.new),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  testWidgets('shows an empty state when no guests are checked in',
      (tester) async {
    await tester.pumpWidget(_appFor(const []));
    await tester.pumpAndSettle();

    expect(find.text('No guests currently checked in'), findsOneWidget);
  });

  testWidgets('lists every checked-in guest with a Check Out action',
      (tester) async {
    await tester.pumpWidget(
      _appFor([_checkedIn('r1', customerName: 'Ravi Kumar')]),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ravi Kumar'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Check Out'), findsOneWidget);
    // Review Focus #1: the screen must pass the current resort's id
    // through to the repository, not rely on RLS alone.
    expect(listedPropertyIds, everyElement('p1'));
  });

  testWidgets('tapping Check Out navigates to the checkout screen',
      (tester) async {
    await tester.pumpWidget(
      _appFor([_checkedIn('r1', customerName: 'Ravi Kumar')]),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Check Out'));
    await tester.pumpAndSettle();

    expect(find.text('CHECKOUT SCREEN'), findsOneWidget);
  });

  // I9: the checkedIn() repository query never embedded the guest's
  // profile, so this screen's `g.customerName ?? 'Guest'` fallback always
  // fired -- reception could not tell which checked-in guest was which by
  // name. This widget test alone can't catch that (it feeds a Reservation
  // with the name already attached, bypassing the repository), but it
  // locks in the fallback still behaves correctly when a name is genuinely
  // absent, now that the common case is fixed at the repository level in
  // stay_repository.dart.
  testWidgets('falls back to "Guest" only when no name is available',
      (tester) async {
    await tester.pumpWidget(
      _appFor([_checkedIn('r1', customerName: null)]),
    );
    await tester.pumpAndSettle();

    expect(find.text('Guest'), findsOneWidget);
  });

  testWidgets('returning from checkout refetches the room board',
      (tester) async {
    final board = FakeRoomBoardSource();
    final router = GoRouter(
      initialLocation: '/admin/check-out',
      routes: [
        GoRoute(
            path: '/admin/check-out',
            builder: (_, _) => const ReceptionCheckoutScreen()),
        GoRoute(
            path: '/my-stay/checkout',
            builder: (_, _) => const Text('CHECKOUT SCREEN')),
      ],
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [
        checkedInProvider.overrideWith(
            (ref, propertyId) async => [_checkedIn('r1', customerName: 'Ravi Kumar')]),
        currentResortProvider.overrideWith(_FixedResort.new),
        roomBoardSourceProvider.overrideWithValue(board),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        // Stands in for an open Rooms tab, which keeps the board alive.
        builder: (context, child) => Stack(children: [
          child!,
          Consumer(builder: (_, ref, _) {
            ref.watch(roomBoardProvider('p1'));
            return const SizedBox.shrink();
          }),
        ]),
      ),
    ));
    await tester.pumpAndSettle();
    final before = board.boardCalls.length;

    await tester.tap(find.widgetWithText(FilledButton, 'Check Out'));
    await tester.pumpAndSettle();
    GoRouter.of(tester.element(find.text('CHECKOUT SCREEN'))).pop();
    await tester.pumpAndSettle();

    expect(board.boardCalls.length, greaterThan(before));
  });
}
