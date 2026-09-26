import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pasala/core/current_resort.dart';
import 'package:pasala/core/errors.dart';
import 'package:pasala/data/models/reservation.dart';
import 'package:pasala/data/models/resort_membership.dart';
import 'package:pasala/data/models/room_status.dart';
import 'package:pasala/data/repositories/room_status_repository.dart';
import 'package:pasala/data/repositories/stay_pass_repository.dart';
import 'package:pasala/data/repositories/stay_repository.dart';
import 'package:pasala/features/admin/pass_check_in_sheet.dart';
import 'package:pasala/features/admin/reception_checkin_screen.dart';

import '../../support/fake_room_board_source.dart';
import '../../support/fake_stay_pass_source.dart';

const _resort =
    ResortMembership(propertyId: 'p1', resortName: 'Pasala', role: ResortRole.admin);

const _bookingId = '3f2a1b9c-0000-0000-0000-000000000000';
const _otherId = 'aa11bb22-0000-0000-0000-000000000000';

class _FixedResort extends CurrentResort {
  @override
  ResortMembership? build() => _resort;
}

Reservation _booking({String? customerName, String id = _bookingId}) => Reservation(
      id: id,
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
    FakeStayPassSource? passes,
  }) {
    // /admin/check-in/scan is Task 5's screen; a stub stands in for it
    // here, returning a code or nothing the way the real one pops.
    final router = GoRouter(
      initialLocation: '/admin/check-in',
      routes: [
        GoRoute(
          path: '/admin/check-in',
          builder: (_, _) => const ReceptionCheckinScreen(),
          routes: [
            GoRoute(
              path: 'scan',
              builder: (context, _) => Scaffold(
                body: Column(
                  children: [
                    TextButton(
                      onPressed: () => context.pop('rh1.scanned'),
                      child: const Text('FAKE READ'),
                    ),
                    TextButton(
                      onPressed: () => context.pop(),
                      child: const Text('FAKE CANCEL'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
    return ProviderScope(
      overrides: [
        todaysArrivalsProvider.overrideWith((ref, propertyId) async {
          listedPropertyIds.add(propertyId);
          return arrivals;
        }),
        currentResortProvider.overrideWith(_FixedResort.new),
        roomBoardSourceProvider
            .overrideWithValue(board ?? FakeRoomBoardSource()),
        stayPassSourceProvider
            .overrideWithValue(passes ?? FakeStayPassSource()),
        if (stay != null) stayRepositoryProvider.overrideWithValue(stay),
      ],
      child: MaterialApp.router(routerConfig: router),
    );
  }

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

  testWidgets('each row shows the booking code the guest sees', (tester) async {
    await tester.pumpWidget(appFor([_booking(customerName: 'Ravi Kumar')]));
    await tester.pumpAndSettle();

    expect(find.textContaining('Booking PR3F2A'), findsOneWidget);
  });

  testWidgets('typing a booking code, name or phone filters the list',
      (tester) async {
    await tester.pumpWidget(appFor([
      _booking(customerName: 'Ravi Kumar'),
      _booking(customerName: 'Meera Nair', id: _otherId),
    ]));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('checkin-search')), 'pr3f');
    await tester.pumpAndSettle();
    expect(find.text('Ravi Kumar'), findsOneWidget);
    expect(find.text('Meera Nair'), findsNothing);

    await tester.enterText(find.byKey(const Key('checkin-search')), 'meera');
    await tester.pumpAndSettle();
    expect(find.text('Ravi Kumar'), findsNothing);
    expect(find.text('Meera Nair'), findsOneWidget);
  });

  testWidgets('a search that matches nothing says so', (tester) async {
    await tester.pumpWidget(appFor([_booking(customerName: 'Ravi Kumar')]));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('checkin-search')), 'zzz');
    await tester.pumpAndSettle();

    expect(find.text('No booking matches "zzz"'), findsOneWidget);
  });

  testWidgets(
      'Scan pass reads a pass, opens its check-in, and Check in guest checks in',
      (tester) async {
    final passes = FakeStayPassSource()..verified = verifiedPass();
    final stay = _FakeStayRepository();
    await tester.pumpWidget(appFor([_booking(customerName: 'Ravi Kumar')],
        passes: passes, stay: stay));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('scan-pass-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('FAKE READ'));
    await tester.pumpAndSettle();

    expect(passes.verifyCalls, ['rh1.scanned']);
    expect(find.text('Pass verified'), findsOneWidget);
    expect(find.textContaining('Cottage 1'), findsWidgets);
    expect(find.text('9000000001'), findsOneWidget);

    await tester.tap(find.byKey(const Key('pass-check-in')));
    await tester.pumpAndSettle();

    expect(stay.checkIns, [_bookingId]);
    expect(find.text('Checked in'), findsOneWidget);
    expect(find.text('Pass verified'), findsNothing);
  });

  testWidgets('closing the scanner without a code does nothing', (tester) async {
    final passes = FakeStayPassSource();
    await tester.pumpWidget(
        appFor([_booking(customerName: 'Ravi Kumar')], passes: passes));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('scan-pass-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('FAKE CANCEL'));
    await tester.pumpAndSettle();

    expect(passes.verifyCalls, isEmpty);
    expect(find.text('Ravi Kumar'), findsOneWidget);
  });

  testWidgets('a rejected pass shows why, and no sheet', (tester) async {
    final passes = FakeStayPassSource()
      ..verifyError = const StayPassRejected.expired();
    await tester.pumpWidget(
        appFor([_booking(customerName: 'Ravi Kumar')], passes: passes));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('scan-pass-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('FAKE READ'));
    await tester.pumpAndSettle();

    expect(find.text(const StayPassRejected.expired().message), findsOneWidget);
    expect(find.text('Pass verified'), findsNothing);
  });

  // Review Focus 3.
  testWidgets('a pass for another resort is refused even when the server '
      'verified it', (tester) async {
    final passes = FakeStayPassSource()
      ..verified = verifiedPass(propertyId: 'p2');
    final stay = _FakeStayRepository();
    await tester.pumpWidget(appFor([_booking(customerName: 'Ravi Kumar')],
        passes: passes, stay: stay));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('scan-pass-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('FAKE READ'));
    await tester.pumpAndSettle();

    expect(find.text(const StayPassRejected.otherResort().message), findsOneWidget);
    expect(find.text('Pass verified'), findsNothing);
    expect(stay.checkIns, isEmpty);
  });

  // Review Focus 2.
  testWidgets('a pass typed by a keyboard scanner opens on Enter, trimmed',
      (tester) async {
    final passes = FakeStayPassSource()..verified = verifiedPass();
    await tester.pumpWidget(
        appFor([_booking(customerName: 'Ravi Kumar')], passes: passes));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('checkin-search')), '  rh1.typed \n');
    await tester.testTextInput.receiveAction(TextInputAction.go);
    await tester.pumpAndSettle();

    expect(passes.verifyCalls, ['rh1.typed']);
    expect(find.text('Pass verified'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byKey(const Key('checkin-search'))).controller!.text,
      isEmpty,
    );
  });

  testWidgets('the Open pass button shows only for a pass', (tester) async {
    final passes = FakeStayPassSource()..verified = verifiedPass();
    await tester.pumpWidget(
        appFor([_booking(customerName: 'Ravi Kumar')], passes: passes));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('checkin-search')), 'PR3F');
    await tester.pump();
    expect(find.byKey(const Key('open-pass')), findsNothing);

    await tester.enterText(find.byKey(const Key('checkin-search')), 'rh1.pasted');
    await tester.pump();
    // While a pass is being typed the list is not filtered by it.
    expect(find.text('Ravi Kumar'), findsOneWidget);
    await tester.tap(find.byKey(const Key('open-pass')));
    await tester.pumpAndSettle();

    expect(passes.verifyCalls, ['rh1.pasted']);
  });

  testWidgets('an already checked-in booking shows its status and no button',
      (tester) async {
    final passes = FakeStayPassSource()
      ..verified = verifiedPass(status: ReservationStatus.checkedIn);
    await tester.pumpWidget(
        appFor([_booking(customerName: 'Ravi Kumar')], passes: passes));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('scan-pass-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('FAKE READ'));
    await tester.pumpAndSettle();

    expect(find.text('Already checked in'), findsOneWidget);
    expect(find.byKey(const Key('pass-check-in')), findsNothing);
  });

  testWidgets('the sheet warns when the room still needs cleaning',
      (tester) async {
    final passes = FakeStayPassSource()..verified = verifiedPass();
    await tester.pumpWidget(appFor(
      [_booking(customerName: 'Ravi Kumar')],
      passes: passes,
      board: FakeRoomBoardSource()
        ..entries = [
          boardEntry(unitId: 'u1', state: RoomState.dirty, status: RoomStatus.cleaning),
        ],
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('scan-pass-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('FAKE READ'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('pass-room-warning')), findsOneWidget);
    expect(find.byKey(const Key('pass-check-in')), findsOneWidget);
  });

  group('passStatusLine', () {
    test('says what happened to a booking that cannot be checked in', () {
      expect(passStatusLine(ReservationStatus.checkedIn), 'Already checked in');
      expect(passStatusLine(ReservationStatus.checkedOut),
          'This stay has already checked out');
      expect(passStatusLine(ReservationStatus.cancelled), 'This booking was cancelled');
      expect(passStatusLine(ReservationStatus.hold), 'This booking is not confirmed yet');
      expect(passStatusLine(ReservationStatus.pendingPayment),
          'This booking is not confirmed yet');
    });
  });
}
