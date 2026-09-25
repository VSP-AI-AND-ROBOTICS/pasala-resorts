import 'package:pasala/data/models/room_status.dart';
import 'package:pasala/data/models/staff_task.dart';
import 'package:pasala/data/models/unit.dart';
import 'package:pasala/data/repositories/room_status_repository.dart';

/// In-memory [RoomBoardSource]. Set [entries]/[staff] for what the server
/// would return, an `...Error` to make that call throw, and read the call
/// logs to assert what a screen asked for.
class FakeRoomBoardSource implements RoomBoardSource {
  List<RoomBoardEntry> entries = [];
  List<DispatchableStaff> staff = [];
  Object? boardError;
  Object? setStatusError;
  Object? dispatchError;
  Object? staffError;

  final List<String> boardCalls = [];
  final List<(String, RoomState, String?)> setStatusCalls = [];
  final List<(String, String, String?)> dispatchCalls = [];
  final List<String> staffCalls = [];

  @override
  Future<List<RoomBoardEntry>> board(String propertyId) async {
    boardCalls.add(propertyId);
    if (boardError != null) throw boardError!;
    return entries;
  }

  @override
  Future<void> setStatus(
    String unitId,
    RoomState state, {
    String? reason,
  }) async {
    setStatusCalls.add((unitId, state, reason));
    if (setStatusError != null) throw setStatusError!;
  }

  @override
  Future<String> dispatch(
    String unitId,
    String assigneeId, {
    String? note,
  }) async {
    dispatchCalls.add((unitId, assigneeId, note));
    if (dispatchError != null) throw dispatchError!;
    return 'task-new';
  }

  @override
  Future<List<DispatchableStaff>> dispatchableStaff(String propertyId) async {
    staffCalls.add(propertyId);
    if (staffError != null) throw staffError!;
    return staff;
  }
}

/// A board row with defaults for a plain, ready, available room; override
/// only what a test is about.
RoomBoardEntry boardEntry({
  String unitId = 'u1',
  String name = 'Cottage 1',
  BookingMode bookingMode = BookingMode.nightly,
  RoomStatus status = RoomStatus.available,
  RoomState state = RoomState.ready,
  String? reason,
  String? occupiedReservationId,
  String? guestFirstName,
  bool arrivingToday = false,
  String? housekeepingTaskId,
  String? housekeeperName,
  TaskStatus? housekeepingStatus,
  DateTime? housekeepingDispatchedAt,
  bool overdue = false,
}) => RoomBoardEntry(
  unitId: unitId,
  name: name,
  bookingMode: bookingMode,
  status: status,
  state: state,
  reason: reason,
  occupiedReservationId: occupiedReservationId,
  guestFirstName: guestFirstName,
  arrivingToday: arrivingToday,
  housekeepingTaskId: housekeepingTaskId,
  housekeeperName: housekeeperName,
  housekeepingStatus: housekeepingStatus,
  housekeepingDispatchedAt: housekeepingDispatchedAt,
  overdue: overdue,
);
