import 'package:flutter/material.dart';

import 'staff_task.dart';
import 'unit.dart';

/// What a room tile shows. Derived server-side by `room_status_board`
/// (0047_room_status.sql), in this order: a checked-in reservation makes a
/// room [occupied]; otherwise its stored [RoomState] decides -- `out_of_order`
/// is [maintenance], `dirty` is [cleaning], `ready` (or no stored row) is
/// [available]. Never stored and never sent back.
enum RoomStatus { available, occupied, cleaning, maintenance }

/// Unknown text is rejected rather than defaulted -- a silent fallback
/// would hide a server/app mismatch.
RoomStatus roomStatusFromDb(String raw) => switch (raw) {
  'available' => RoomStatus.available,
  'occupied' => RoomStatus.occupied,
  'cleaning' => RoomStatus.cleaning,
  'maintenance' => RoomStatus.maintenance,
  _ => throw ArgumentError('Unknown room status: $raw'),
};

/// Label, icon and colour for a [RoomStatus]. The icon and the label always
/// travel with the colour: a status is never told by colour alone.
extension RoomStatusDisplay on RoomStatus {
  String get label => switch (this) {
    RoomStatus.available => 'Available',
    RoomStatus.occupied => 'Occupied',
    RoomStatus.cleaning => 'Cleaning',
    RoomStatus.maintenance => 'Maintenance',
  };

  IconData get icon => switch (this) {
    RoomStatus.available => Icons.check_circle_outline,
    RoomStatus.occupied => Icons.person_outline,
    RoomStatus.cleaning => Icons.cleaning_services_outlined,
    RoomStatus.maintenance => Icons.build_outlined,
  };

  Color get color => switch (this) {
    RoomStatus.available => const Color(0xFF2E7D32),
    RoomStatus.occupied => const Color(0xFF1565C0),
    RoomStatus.cleaning => const Color(0xFFB26A00),
    RoomStatus.maintenance => const Color(0xFFC62828),
  };
}

/// The housekeeping state a person sets (`unit_room_status.state`). A unit
/// with no stored row is [ready].
enum RoomState { ready, dirty, outOfOrder }

RoomState roomStateFromDb(String raw) => switch (raw) {
  'ready' => RoomState.ready,
  'dirty' => RoomState.dirty,
  'out_of_order' => RoomState.outOfOrder,
  _ => throw ArgumentError('Unknown room state: $raw'),
};

/// Inverse of [roomStateFromDb] -- the Postgres `room_state` label.
String roomStateToDb(RoomState state) => switch (state) {
  RoomState.ready => 'ready',
  RoomState.dirty => 'dirty',
  RoomState.outOfOrder => 'out_of_order',
};

/// One row of `room_status_board(p_property)`: one active unit of the
/// resort, with its derived [status], its stored [state] (so an occupied
/// room can still carry a needs-cleaning or out-of-order badge), and its
/// open housekeeping task, if any.
class RoomBoardEntry {
  const RoomBoardEntry({
    required this.unitId,
    required this.name,
    required this.bookingMode,
    required this.status,
    required this.state,
    this.reason,
    this.occupiedReservationId,
    this.guestFirstName,
    this.arrivingToday = false,
    this.housekeepingTaskId,
    this.housekeeperName,
    this.housekeepingStatus,
    this.housekeepingDispatchedAt,
    this.overdue = false,
  });

  factory RoomBoardEntry.fromJson(Map<String, dynamic> json) => RoomBoardEntry(
    unitId: json['unit_id'] as String,
    name: json['name'] as String,
    bookingMode: BookingMode.values.byName(json['booking_mode'] as String),
    status: roomStatusFromDb(json['effective_status'] as String),
    state: roomStateFromDb(json['state'] as String),
    reason: json['reason'] as String?,
    occupiedReservationId: json['occupied_reservation_id'] as String?,
    guestFirstName: json['guest_first_name'] as String?,
    arrivingToday: json['arriving_today'] as bool? ?? false,
    housekeepingTaskId: json['housekeeping_task_id'] as String?,
    housekeeperName: json['housekeeper_name'] as String?,
    housekeepingStatus: json['housekeeping_status'] == null
        ? null
        : taskStatusFromDb(json['housekeeping_status'] as String),
    housekeepingDispatchedAt: json['housekeeping_dispatched_at'] == null
        ? null
        : DateTime.parse(json['housekeeping_dispatched_at'] as String).toUtc(),
    overdue: json['overdue'] as bool? ?? false,
  );

  final String unitId;
  final String name;
  final BookingMode bookingMode;
  final RoomStatus status;
  final RoomState state;

  /// Why the room is out of order; null unless [state] is
  /// [RoomState.outOfOrder].
  final String? reason;
  final String? occupiedReservationId;
  final String? guestFirstName;

  /// A confirmed booking starts today (Asia/Kolkata).
  final bool arrivingToday;
  final String? housekeepingTaskId;
  final String? housekeeperName;
  final TaskStatus? housekeepingStatus;

  /// When housekeeping was sent (the task's `created_at`).
  final DateTime? housekeepingDispatchedAt;

  /// The open housekeeping task is older than the resort's SLA.
  final bool overdue;

  /// Slot-only units are day-use rooms.
  bool get isDayUse => bookingMode == BookingMode.slot;

  bool get hasOpenHousekeeping => housekeepingTaskId != null;

  /// Whole minutes since housekeeping was sent, or null with no open task.
  int? minutesSinceDispatch(DateTime now) => housekeepingDispatchedAt == null
      ? null
      : now.difference(housekeepingDispatchedAt!).inMinutes;
}

/// One row of `list_dispatchable_staff(p_property)`: a `staff` member of
/// the resort who can be sent to clean a room.
class DispatchableStaff {
  const DispatchableStaff({required this.userId, this.fullName});

  factory DispatchableStaff.fromJson(Map<String, dynamic> json) =>
      DispatchableStaff(
        userId: json['user_id'] as String,
        fullName: json['full_name'] as String?,
      );

  final String userId;
  final String? fullName;

  String get displayName {
    final name = fullName?.trim() ?? '';
    return name.isEmpty ? 'Unnamed staff member' : name;
  }
}
