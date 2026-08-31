import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors.dart';
import '../../core/supabase_client.dart';
import '../models/attendance_record.dart';

/// The (staff, date) an admin or staff screen wants to see -- `staffId:
/// null` means "every staff member" (admin only; RLS returns only the
/// caller's own rows for anyone else regardless), `date: null` means
/// "every date on record." A record, not positional params, so
/// `FutureProvider.family` can key on it directly.
typedef AttendanceFilter = ({String? staffId, DateTime? date});

class AttendanceRepository {
  AttendanceRepository(this._db);
  final SupabaseClient _db;

  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } catch (e) {
      throw mapPostgrestError(e);
    }
  }

  String _dateOnly(DateTime d) => d.toIso8601String().substring(0, 10);

  /// A direct table select with an explicit foreign-key-qualified
  /// `profiles` embed. This table has only one FK to `profiles`
  /// (`staff_id`), so a bare `profiles(full_name)` would actually
  /// resolve unambiguously today -- but the hint is used anyway,
  /// consistent with the fix `leave_requests` needed after its final
  /// review (that table's SECOND FK, `decided_by`, made its embed
  /// ambiguous and broke at runtime with no test catching it). Naming
  /// the relationship here guards against the same class of bug if this
  /// table ever grows a second FK to `profiles`.
  Future<List<AttendanceRecord>> list({
    String? staffId,
    DateTime? date,
  }) =>
      _guard(() async {
        dynamic query = _db
            .from('attendance_records')
            .select('*, profiles!attendance_records_staff_id_fkey(full_name)');
        if (staffId != null) query = query.eq('staff_id', staffId);
        if (date != null) query = query.eq('work_date', _dateOnly(date));
        final rows = await query.order('work_date', ascending: false) as List;
        return rows
            .map((e) => AttendanceRecord.fromJson(e as Map<String, dynamic>))
            .toList();
      });

  /// Checks [staffId] in for today. `work_date`/`check_out_at` are
  /// deliberately not sent -- the server enforces `work_date = current_date`
  /// via `attendance_records_own_insert`'s `with check`, and
  /// `check_in_at` defaults to `now()`.
  Future<void> checkIn({required String staffId}) => _guard(() async {
        await _db.from('attendance_records').insert({
          'staff_id': staffId,
          'work_date': _dateOnly(DateTime.now()),
        });
      });

  /// Checks the record at [id] out now, via the `check_out_attendance`
  /// RPC -- NOT a direct table update. Postgres RLS requires a row to be
  /// visible via an applicable SELECT-type policy before an UPDATE
  /// policy's own `USING` clause is even consulted; a same-tier staff
  /// peer attempting to check someone else out has no such visibility
  /// (they aren't the row's owner and aren't admin), so a raw UPDATE
  /// would silently affect zero rows instead of raising an error -- a
  /// gap discovered and fixed at the database layer in Task 1 (see
  /// `0023_attendance_records.sql`'s `check_out_attendance` function).
  /// The RPC does its own explicit ownership check and raises
  /// immediately, so this method only needs to surface whatever error
  /// it returns.
  Future<void> checkOut({required String id}) => _guard(() async {
        await _db.rpc('check_out_attendance', params: {'p_id': id});
      });
}

final attendanceRepositoryProvider = Provider<AttendanceRepository>(
  (ref) => AttendanceRepository(ref.watch(supabaseProvider)),
);

final attendanceRecordsProvider =
    FutureProvider.family<List<AttendanceRecord>, AttendanceFilter>(
  (ref, filter) => ref.watch(attendanceRepositoryProvider).list(
        staffId: filter.staffId,
        date: filter.date,
      ),
);
