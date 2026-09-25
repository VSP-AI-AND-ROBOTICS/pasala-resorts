import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors.dart';
import '../../core/supabase_client.dart';
import '../models/staff_task.dart';

/// The (assignee, status) an admin or staff screen wants to see --
/// `assigneeId: null` means "every staff member" (admin only; RLS
/// returns only the caller's own rows for anyone else regardless),
/// `status: null` means "every status." A record, not positional
/// params, so `FutureProvider.family` can key on it directly.
typedef TaskFilter = ({
  String propertyId,
  String? assigneeId,
  TaskStatus? status,
});

class TaskRepository {
  TaskRepository(this._db);
  final SupabaseClient _db;

  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } catch (e) {
      throw mapPostgrestError(e);
    }
  }

  /// A direct table select with a `profiles` embed for `assignee_name`
  /// -- this table has only one FK to `profiles`, so the ambiguity that
  /// required an explicit FK hint on `leave_requests` doesn't strictly
  /// apply here, but the hint is included anyway for consistency with
  /// `AttendanceRepository`'s same defensive choice.
  /// `units(name)` names the room of a housekeeping task (0047).
  Future<List<StaffTask>> list({
    required String propertyId,
    String? assigneeId,
    TaskStatus? status,
  }) =>
      _guard(() async {
        dynamic query = _db
            .from('tasks')
            .select('*, profiles!tasks_assignee_id_fkey(full_name), units(name)')
            .eq('property_id', propertyId);
        if (assigneeId != null) query = query.eq('assignee_id', assigneeId);
        if (status != null) query = query.eq('status', taskStatusToDb(status));
        final rows = await query.order('created_at', ascending: false) as List;
        return rows.map((e) => StaffTask.fromJson(e as Map<String, dynamic>)).toList();
      });

  /// Creates a new task, always `todo` (the server column default --
  /// the client never sends a `status`). Admin-only; `tasks_admin_insert`
  /// rejects anyone else.
  Future<void> create({
    required String propertyId,
    required String assigneeId,
    required String title,
    required String description,
  }) =>
      _guard(() async {
        await _db.from('tasks').insert({
          'property_id': propertyId,
          ...StaffTask(
            id: '',
            assigneeId: assigneeId,
            title: title,
            description: description,
            status: TaskStatus.todo,
          ).toInsert(),
        });
      });

  /// Full edit -- title, description, and/or reassignment. Admin-only;
  /// deliberately excludes `status`, which only [updateStatus] may
  /// change (see the spec's "two roles, two fields" split).
  Future<void> update({
    required String id,
    required String title,
    required String description,
    required String assigneeId,
  }) =>
      _guard(() async {
        await _db.from('tasks').update({
          'title': title,
          'description': description,
          'assignee_id': assigneeId,
        }).eq('id', id);
      });

  /// The assignee's own path -- a plain table update restricted to the
  /// `status` column, relying on `tasks_enforce_write_trigger` for
  /// enforcement (no RPC needed: the caller is always the row's owner,
  /// so the RLS-visibility gap Daily Work Status's checkout hit does
  /// not apply here -- see the spec's §3).
  Future<void> updateStatus({
    required String id,
    required TaskStatus status,
  }) =>
      _guard(() async {
        await _db.from('tasks').update({'status': taskStatusToDb(status)}).eq('id', id);
      });

  Future<void> delete({required String id}) => _guard(() async {
        await _db.from('tasks').delete().eq('id', id);
      });
}

final taskRepositoryProvider = Provider<TaskRepository>(
  (ref) => TaskRepository(ref.watch(supabaseProvider)),
);

final tasksProvider = FutureProvider.family<List<StaffTask>, TaskFilter>(
  (ref, filter) => ref.watch(taskRepositoryProvider).list(
        propertyId: filter.propertyId,
        assigneeId: filter.assigneeId,
        status: filter.status,
      ),
  // Screens show their own Retry button; don't also auto-retry (Riverpod 3
  // retries non-Error throws by default).
  retry: (retryCount, error) => null,
);
