import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/data/models/room_status.dart';
import 'package:pasala/data/models/staff_task.dart';
import 'package:pasala/data/models/unit.dart';

void main() {
  group('RoomBoardEntry.fromJson', () {
    test('parses a full room_status_board row', () {
      final entry = RoomBoardEntry.fromJson(const {
        'unit_id': 'u1',
        'name': 'Cottage 1',
        'booking_mode': 'nightly',
        'effective_status': 'occupied',
        'state': 'dirty',
        'reason': null,
        'occupied_reservation_id': 'r1',
        'guest_first_name': 'Gita',
        'arriving_today': false,
        'housekeeping_task_id': 't1',
        'housekeeper_name': 'Hari Housekeeper',
        'housekeeping_status': 'in_progress',
        'housekeeping_dispatched_at': '2026-09-25T04:30:00+00:00',
        'overdue': true,
      });

      expect(entry.unitId, 'u1');
      expect(entry.name, 'Cottage 1');
      expect(entry.bookingMode, BookingMode.nightly);
      expect(entry.status, RoomStatus.occupied);
      expect(entry.state, RoomState.dirty);
      expect(entry.occupiedReservationId, 'r1');
      expect(entry.guestFirstName, 'Gita');
      expect(entry.arrivingToday, isFalse);
      expect(entry.housekeepingTaskId, 't1');
      expect(entry.housekeeperName, 'Hari Housekeeper');
      expect(entry.housekeepingStatus, TaskStatus.inProgress);
      expect(entry.housekeepingDispatchedAt, DateTime.utc(2026, 9, 25, 4, 30));
      expect(entry.overdue, isTrue);
      expect(entry.hasOpenHousekeeping, isTrue);
    });

    test('parses a ready room with nothing going on', () {
      final entry = RoomBoardEntry.fromJson(const {
        'unit_id': 'u2',
        'name': 'Day Hut',
        'booking_mode': 'slot',
        'effective_status': 'available',
        'state': 'ready',
        'reason': null,
        'occupied_reservation_id': null,
        'guest_first_name': null,
        'arriving_today': true,
        'housekeeping_task_id': null,
        'housekeeper_name': null,
        'housekeeping_status': null,
        'housekeeping_dispatched_at': null,
        'overdue': false,
      });

      expect(entry.status, RoomStatus.available);
      expect(entry.state, RoomState.ready);
      expect(entry.isDayUse, isTrue);
      expect(entry.arrivingToday, isTrue);
      expect(entry.hasOpenHousekeeping, isFalse);
      expect(entry.housekeepingStatus, isNull);
      expect(entry.housekeepingDispatchedAt, isNull);
    });

    test('an out-of-order room keeps its reason', () {
      final entry = RoomBoardEntry.fromJson(const {
        'unit_id': 'u4',
        'name': 'Cottage 4',
        'booking_mode': 'both',
        'effective_status': 'maintenance',
        'state': 'out_of_order',
        'reason': 'AC broken',
        'arriving_today': false,
        'overdue': false,
      });

      expect(entry.status, RoomStatus.maintenance);
      expect(entry.state, RoomState.outOfOrder);
      expect(entry.reason, 'AC broken');
      expect(entry.isDayUse, isFalse);
    });

    test('an unknown effective_status is rejected, not defaulted', () {
      expect(() => roomStatusFromDb('haunted'), throwsArgumentError);
    });
  });

  group('RoomState <-> db', () {
    test('round-trips every value', () {
      for (final state in RoomState.values) {
        expect(roomStateFromDb(roomStateToDb(state)), state);
      }
    });

    test('outOfOrder is out_of_order in the database', () {
      expect(roomStateToDb(RoomState.outOfOrder), 'out_of_order');
    });
  });

  test('every status has its own label and icon', () {
    expect(RoomStatus.values.map((s) => s.label).toList(), [
      'Available',
      'Occupied',
      'Cleaning',
      'Maintenance',
    ]);
    expect(RoomStatus.values.map((s) => s.icon).toSet(), hasLength(4));
    expect(RoomStatus.values.map((s) => s.color).toSet(), hasLength(4));
  });

  test('minutesSinceDispatch counts whole minutes, null without a task', () {
    final dispatched = DateTime.utc(2026, 9, 25, 10);
    final entry = RoomBoardEntry(
      unitId: 'u1',
      name: 'Cottage 1',
      bookingMode: BookingMode.nightly,
      status: RoomStatus.cleaning,
      state: RoomState.dirty,
      housekeepingTaskId: 't1',
      housekeepingDispatchedAt: dispatched,
    );
    expect(
      entry.minutesSinceDispatch(
        dispatched.add(const Duration(minutes: 25, seconds: 40)),
      ),
      25,
    );

    const idle = RoomBoardEntry(
      unitId: 'u2',
      name: 'Cottage 2',
      bookingMode: BookingMode.nightly,
      status: RoomStatus.available,
      state: RoomState.ready,
    );
    expect(idle.minutesSinceDispatch(dispatched), isNull);
  });

  group('DispatchableStaff', () {
    test('parses a list_dispatchable_staff row', () {
      final s = DispatchableStaff.fromJson(const {
        'user_id': 's1',
        'full_name': 'Hari Housekeeper',
      });
      expect(s.userId, 's1');
      expect(s.displayName, 'Hari Housekeeper');
    });

    test('a member without a name still gets a label', () {
      const s = DispatchableStaff(userId: 's2', fullName: '  ');
      expect(s.displayName, 'Unnamed staff member');
    });
  });
}
