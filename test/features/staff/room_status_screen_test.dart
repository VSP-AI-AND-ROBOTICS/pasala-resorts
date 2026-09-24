import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pasala/core/current_resort.dart';
import 'package:pasala/core/errors.dart';
import 'package:pasala/data/models/resort_membership.dart';
import 'package:pasala/data/models/room_status.dart';
import 'package:pasala/data/models/unit.dart';
import 'package:pasala/data/repositories/room_status_repository.dart';
import 'package:pasala/features/staff/room_status_screen.dart';
import 'package:pasala/features/staff/room_tile.dart';

import '../../support/fake_room_board_source.dart';

class _FixedResort extends CurrentResort {
  _FixedResort(this._value);
  final ResortMembership _value;
  @override
  ResortMembership? build() => _value;
}

const _staffM =
    ResortMembership(propertyId: 'p1', resortName: 'Pasala', role: ResortRole.staff);
const _accountantM = ResortMembership(
    propertyId: 'p1', resortName: 'Pasala', role: ResortRole.accountant);

final _now = DateTime.utc(2026, 9, 25, 10);

final _rooms = [
  boardEntry(unitId: 'u1', name: 'Cottage 1'),
  boardEntry(
    unitId: 'u2',
    name: 'Cottage 2',
    status: RoomStatus.occupied,
    occupiedReservationId: 'r1',
    guestFirstName: 'Gita',
  ),
  boardEntry(
    unitId: 'u3',
    name: 'Day Hut',
    bookingMode: BookingMode.slot,
    status: RoomStatus.cleaning,
    state: RoomState.dirty,
    housekeepingTaskId: 't1',
    housekeeperName: 'Hari Housekeeper',
    housekeepingDispatchedAt: _now.subtract(const Duration(minutes: 75)),
    overdue: true,
  ),
  boardEntry(
    unitId: 'u4',
    name: 'Cottage 4',
    status: RoomStatus.maintenance,
    state: RoomState.outOfOrder,
    reason: 'AC broken',
    arrivingToday: true,
  ),
];

Future<void> _pump(
  WidgetTester tester,
  FakeRoomBoardSource source, {
  ResortMembership resort = _staffM,
}) async {
  final router = GoRouter(
    initialLocation: '/staff/rooms',
    routes: [
      GoRoute(
          path: '/staff/rooms',
          builder: (_, _) => RoomStatusScreen(clock: () => _now)),
      GoRoute(
          path: '/admin/check-in',
          builder: (_, _) => const Text('CHECK-IN SCREEN')),
      GoRoute(
          path: '/admin/check-out',
          builder: (_, _) => const Text('CHECK-OUT SCREEN')),
    ],
  );
  await tester.pumpWidget(ProviderScope(
    overrides: [
      roomBoardSourceProvider.overrideWithValue(source),
      currentResortProvider.overrideWith(() => _FixedResort(resort)),
    ],
    child: MaterialApp.router(routerConfig: router),
  ));
  await tester.pumpAndSettle();
}

Finder _inTile(String unitId, Finder matching) =>
    find.descendant(of: find.byKey(Key('room-tile-$unitId')), matching: matching);

void main() {
  group('pure helpers', () {
    test('roomGridColumns: two on a phone, four to six on wide screens', () {
      expect(roomGridColumns(375), 2);
      expect(roomGridColumns(599), 2);
      expect(roomGridColumns(700), 4);
      expect(roomGridColumns(1000), 5);
      expect(roomGridColumns(1600), 6);
    });

    test('roomStatusCounts counts every status, zero included', () {
      expect(roomStatusCounts([boardEntry()]), {
        RoomStatus.available: 1,
        RoomStatus.occupied: 0,
        RoomStatus.cleaning: 0,
        RoomStatus.maintenance: 0,
      });
    });

    test('housekeepingLine uses the first name and whole minutes', () {
      expect(housekeepingLine(_rooms[2], _now), 'Housekeeping: Hari, 75 min');
      expect(
        housekeepingLine(
          boardEntry(housekeepingTaskId: 't9', housekeepingDispatchedAt: _now),
          _now,
        ),
        'Housekeeping: unassigned, 0 min',
      );
    });
  });

  testWidgets('asks for the current resort\'s board', (tester) async {
    final source = FakeRoomBoardSource()..entries = _rooms;
    await _pump(tester, source);

    expect(source.boardCalls, isNotEmpty);
    expect(source.boardCalls, everyElement('p1'));
  });

  testWidgets('every tile shows its status as an icon and a label',
      (tester) async {
    await _pump(tester, FakeRoomBoardSource()..entries = _rooms);

    for (final (unitId, status) in [
      ('u1', RoomStatus.available),
      ('u2', RoomStatus.occupied),
      ('u3', RoomStatus.cleaning),
      ('u4', RoomStatus.maintenance),
    ]) {
      expect(_inTile(unitId, find.text(status.label)), findsOneWidget,
          reason: unitId);
      expect(_inTile(unitId, find.byIcon(status.icon)), findsOneWidget,
          reason: unitId);
    }
  });

  testWidgets('tiles carry guest, arrival, day use, reason and housekeeping',
      (tester) async {
    await _pump(tester, FakeRoomBoardSource()..entries = _rooms);

    expect(_inTile('u2', find.text('Guest: Gita')), findsOneWidget);
    expect(_inTile('u3', find.text('Day use')), findsOneWidget);
    expect(_inTile('u3', find.text('Housekeeping: Hari, 75 min')), findsOneWidget);
    expect(_inTile('u3', find.text('Overdue')), findsOneWidget);
    expect(_inTile('u4', find.text('Arriving today')), findsOneWidget);
    expect(_inTile('u4', find.text('AC broken')), findsOneWidget);
    expect(_inTile('u1', find.text('Overdue')), findsNothing);
  });

  testWidgets('an occupied room with a stored state carries a badge',
      (tester) async {
    await _pump(
      tester,
      FakeRoomBoardSource()
        ..entries = [
          boardEntry(unitId: 'u1', status: RoomStatus.occupied, state: RoomState.dirty),
          boardEntry(
              unitId: 'u2',
              name: 'Cottage 2',
              status: RoomStatus.occupied,
              state: RoomState.outOfOrder,
              reason: 'Leak'),
        ],
    );

    expect(_inTile('u1', find.text('Needs cleaning')), findsOneWidget);
    expect(_inTile('u2', find.text('Out of order')), findsOneWidget);
  });

  testWidgets('summary chips count each status and filter the grid',
      (tester) async {
    await _pump(tester, FakeRoomBoardSource()..entries = _rooms);

    expect(find.text('Available (1)'), findsOneWidget);
    expect(find.text('Occupied (1)'), findsOneWidget);
    expect(find.text('Cleaning (1)'), findsOneWidget);
    expect(find.text('Maintenance (1)'), findsOneWidget);

    await tester.tap(find.byKey(const Key('room-filter-occupied')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('room-tile-u2')), findsOneWidget);
    expect(find.byKey(const Key('room-tile-u1')), findsNothing);

    await tester.tap(find.byKey(const Key('room-filter-occupied')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('room-tile-u1')), findsOneWidget);
  });

  testWidgets('a filter with no rooms says so', (tester) async {
    await _pump(tester, FakeRoomBoardSource()..entries = [boardEntry()]);

    await tester.tap(find.byKey(const Key('room-filter-maintenance')));
    await tester.pumpAndSettle();

    expect(find.text('No Maintenance rooms right now.'), findsOneWidget);
  });

  testWidgets('a resort with no active units shows an empty state',
      (tester) async {
    await _pump(tester, FakeRoomBoardSource());

    expect(find.text('No rooms yet'), findsOneWidget);
  });

  testWidgets('a failed load goes through FailureView', (tester) async {
    await _pump(tester, FakeRoomBoardSource()..boardError = const NetworkFailure());

    expect(find.text('Cannot reach the server. Check your connection.'),
        findsOneWidget);
  });

  testWidgets('pull to refresh fetches the board again', (tester) async {
    final source = FakeRoomBoardSource()..entries = _rooms;
    await _pump(tester, source);
    final before = source.boardCalls.length;

    await tester.fling(find.byType(ListView), const Offset(0, 400), 1000);
    await tester.pumpAndSettle();

    expect(source.boardCalls.length, greaterThan(before));
  });
}
