import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors.dart';
import '../../core/supabase_client.dart';
import '../models/room_status.dart';

/// The slice of [RoomStatusRepository] the room grid, the admin dashboard,
/// reception check-in and Assigned Work need. Tests override
/// [roomBoardSourceProvider] with `FakeRoomBoardSource`
/// (test/support/fake_room_board_source.dart) instead of a real client.
abstract class RoomBoardSource {
  Future<List<RoomBoardEntry>> board(String propertyId);
  Future<void> setStatus(String unitId, RoomState state, {String? reason});

  /// Returns the new housekeeping task's id.
  Future<String> dispatch(String unitId, String assigneeId, {String? note});
  Future<List<DispatchableStaff>> dispatchableStaff(String propertyId);
}

/// Backs the room status grid through the four functions in
/// 0047_room_status.sql. Every one checks the caller's role at the unit's
/// (or given) resort server-side, so this repository checks nothing
/// itself; refusals arrive as P0020/P0022/P0030/P0031 through
/// [mapPostgrestError].
class RoomStatusRepository implements RoomBoardSource {
  RoomStatusRepository(this._db);
  final SupabaseClient _db;

  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } catch (e) {
      throw mapPostgrestError(e);
    }
  }

  @override
  Future<List<RoomBoardEntry>> board(String propertyId) => _guard(() async {
    final rows =
        await _db.rpc('room_status_board', params: {'p_property': propertyId})
            as List<dynamic>;
    return rows
        .map((e) => RoomBoardEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  });

  @override
  Future<void> setStatus(String unitId, RoomState state, {String? reason}) =>
      _guard(() async {
        await _db.rpc(
          'set_room_status',
          params: {
            'p_unit': unitId,
            'p_state': roomStateToDb(state),
            'p_reason': reason,
          },
        );
      });

  @override
  Future<String> dispatch(String unitId, String assigneeId, {String? note}) =>
      _guard(() async {
        final id = await _db.rpc(
          'dispatch_housekeeping',
          params: {'p_unit': unitId, 'p_assignee': assigneeId, 'p_note': note},
        );
        return id as String;
      });

  @override
  Future<List<DispatchableStaff>> dispatchableStaff(String propertyId) =>
      _guard(() async {
        final rows =
            await _db.rpc(
                  'list_dispatchable_staff',
                  params: {'p_property': propertyId},
                )
                as List<dynamic>;
        return rows
            .map((e) => DispatchableStaff.fromJson(e as Map<String, dynamic>))
            .toList();
      });
}

final roomStatusRepositoryProvider = Provider<RoomStatusRepository>(
  (ref) => RoomStatusRepository(ref.watch(supabaseProvider)),
);

/// The [RoomBoardSource] seam every screen calls through.
final roomBoardSourceProvider = Provider<RoomBoardSource>(
  (ref) => ref.watch(roomStatusRepositoryProvider),
);

/// The room board of one resort, keyed by property id so switching resort
/// never shows another resort's rooms. `autoDispose` (like
/// `checkedInProvider`): the grid refetches every time it is opened,
/// whatever path led there, and screens invalidate it after their own
/// writes and after check-in/out.
final roomBoardProvider = FutureProvider.autoDispose
    .family<List<RoomBoardEntry>, String>(
      (ref, propertyId) => ref.watch(roomBoardSourceProvider).board(propertyId),
      // Screens show their own Retry button; don't also auto-retry (Riverpod
      // 3 retries non-Error throws by default).
      retry: (retryCount, error) => null,
    );

/// The resort's `staff` members, for the Send housekeeping picker.
final dispatchableStaffProvider = FutureProvider.autoDispose
    .family<List<DispatchableStaff>, String>(
      (ref, propertyId) =>
          ref.watch(roomBoardSourceProvider).dispatchableStaff(propertyId),
    );
