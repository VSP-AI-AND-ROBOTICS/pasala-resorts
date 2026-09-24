import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/current_resort.dart';
import 'package:pasala/core/errors.dart';
import 'package:pasala/data/models/reservation.dart';
import 'package:pasala/data/models/resort_membership.dart';
import 'package:pasala/data/models/room_status.dart';
import 'package:pasala/data/repositories/room_status_repository.dart';
import 'package:pasala/data/repositories/stay_repository.dart';
import 'package:pasala/features/admin/reception_checkin_screen.dart';

import '../../support/fake_room_board_source.dart';

const _resort =
    ResortMembership(propertyId: 'p1', resortName: 'Pasala', role: ResortRole.admin);

const _bookingId = '3f2a1b9c-0000-0000-0000-000000000000';

class _FixedResort extends CurrentResort {
  @override
  ResortMembership? build() => _resort;
}

Reservation _booking({String? customerName}) => Reservation(
      id: _bookingId,
      unitId: 'u1',
      start: DateTime(2026, 9, 14),
      end: DateTime(2026, 9, 16),
      kind: ReservationKind.booking,
      status: ReservationStatus.confirmed,
      customerName: customerName,
      guests: 2,
    );

/// Only [checkIn] is reached from this screen.
class _FakeStayRepository implements StayRepository {
  final checkIns = <String>[];

  @override
  Future<Reservation> checkIn(String reservationId) async {
    checkIns.add(reservationId);
    return _booking(customerName: 'Ravi Kumar');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final listedPropertyIds = <String>[];

  Widget appFor(
    List<Reservation> arrivals, {
    FakeRoomBoardSource? board,
    _FakeStayRepository? stay,
  }) =>
      ProviderScope(
        overrides: [
          todaysArrivalsProvider.overrideWith((ref, propertyId) async {
            listedPropertyIds.add(propertyId);
            return arrivals;
          }),
          currentResortProvider.overrideWith(_FixedResort.new),
          roomBoardSourceProvider
              .overrideWithValue(board ?? FakeRoomBoardSource()),
          if (stay != null) stayRepositoryProvider.overrideWithValue(stay),
        ],
        child: const MaterialApp(home: ReceptionCheckinScreen()),
      );

  // I9: this screen previously showed only a date range and an internal
  // booking id -- reception had no way to identify WHO they were checking
  // in without cross-referencing a booking id by hand. Reproduced live: a
  // real guest ("Ravi Kumar") appeared here as an anonymous date range.
  testWidgets('shows the guest\'s real name when the query returns one',
      (tester) async {
    await tester.pumpWidget(appFor([_booking(customerName: 'Ravi Kumar')]));
    await tester.pumpAndSettle();

    expect(find.text('Ravi Kumar'), findsOneWidget);
    // Review Focus #1: the screen must pass the current resort's id
    // through to the repository, not rely on RLS alone.
    expect(listedPropertyIds, everyElement('p1'));
  });

  testWidgets('falls back to "Guest" only when no name is available',
      (tester) async {
    await tester.pumpWidget(appFor([_booking(customerName: null)]));
    await tester.pumpAndSettle();

    expect(find.text('Guest'), findsOneWidget);
  });

  testWidgets('the date range and guest count still show in the subtitle',
      (tester) async {
    await tester.pumpWidget(appFor([_booking(customerName: 'Ravi Kumar')]));
    await tester.pumpAndSettle();

    expect(find.textContaining('14 Sep'), findsOneWidget);
    expect(find.textContaining('2 guests'), findsOneWidget);
  });

  group('roomWarningFor', () {
    test('warns about a dirty room and a room in maintenance', () {
      expect(roomWarningFor(boardEntry(state: RoomState.dirty)),
          'Room not cleaned yet');
      expect(
          roomWarningFor(
              boardEntry(state: RoomState.outOfOrder, reason: 'AC broken')),
          'Maintenance: AC broken');
    });

    test('says nothing for a ready room or an unknown one', () {
      expect(roomWarningFor(boardEntry()), isNull);
      expect(roomWarningFor(null), isNull);
    });
  });

  testWidgets('warns, without blocking, when the room still needs cleaning',
      (tester) async {
    await tester.pumpWidget(appFor(
      [_booking(customerName: 'Ravi Kumar')],
      board: FakeRoomBoardSource()
        ..entries = [
          boardEntry(unitId: 'u1', state: RoomState.dirty, status: RoomStatus.cleaning),
        ],
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('room-warning-$_bookingId')), findsOneWidget);
    expect(find.text('Room not cleaned yet'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Check In'), findsOneWidget);
  });

  testWidgets('shows the maintenance reason', (tester) async {
    await tester.pumpWidget(appFor(
      [_booking(customerName: 'Ravi Kumar')],
      board: FakeRoomBoardSource()
        ..entries = [
          boardEntry(
              unitId: 'u1',
              state: RoomState.outOfOrder,
              status: RoomStatus.maintenance,
              reason: 'AC broken'),
        ],
    ));
    await tester.pumpAndSettle();

    expect(find.text('Maintenance: AC broken'), findsOneWidget);
  });

  testWidgets('a ready room shows no warning', (tester) async {
    await tester.pumpWidget(appFor(
      [_booking(customerName: 'Ravi Kumar')],
      board: FakeRoomBoardSource()..entries = [boardEntry(unitId: 'u1')],
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('room-warning-$_bookingId')), findsNothing);
  });

  // Review Focus 4: the warning is advice; a board that fails to load must
  // not take check-in down with it.
  testWidgets('a room board that fails to load does not block check-in',
      (tester) async {
    await tester.pumpWidget(appFor(
      [_booking(customerName: 'Ravi Kumar')],
      board: FakeRoomBoardSource()..boardError = const NetworkFailure(),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Ravi Kumar'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Check In'), findsOneWidget);
    expect(find.byKey(const Key('room-warning-$_bookingId')), findsNothing);
  });

  testWidgets('checking in refetches the room board', (tester) async {
    final board = FakeRoomBoardSource()..entries = [boardEntry(unitId: 'u1')];
    final stay = _FakeStayRepository();
    await tester.pumpWidget(
        appFor([_booking(customerName: 'Ravi Kumar')], board: board, stay: stay));
    await tester.pumpAndSettle();
    final before = board.boardCalls.length;

    await tester.tap(find.widgetWithText(FilledButton, 'Check In'));
    await tester.pumpAndSettle();

    expect(stay.checkIns, [_bookingId]);
    expect(board.boardCalls.length, greaterThan(before));
  });
}
