import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors.dart';
import '../../core/supabase_client.dart';
import '../models/staff_shift.dart';

/// The (staff, date-range) an admin or staff screen wants to see --
/// `staffId: null` means "every staff member" (admin only; RLS returns
/// nothing useful for a non-admin regardless), `from`/`to: null` means "no
/// bound on that side." A record, not positional params, so
/// `FutureProvider.family` can key on it directly.
typedef StaffShiftFilter = ({String? staffId, DateTime? from, DateTime? to});

class StaffShiftRepository {
  StaffShiftRepository(this._db);
  final SupabaseClient _db;

  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } catch (e) {
      throw mapPostgrestError(e);
    }
  }

  String _dateOnly(DateTime d) => d.toIso8601String().substring(0, 10);

  /// Reads through `list_staff_shifts()` (not a direct table select) --
  /// see that function's own comment in `0021_staff_shifts.sql` for why:
  /// it joins in `profiles.full_name` and applies exactly the same RLS a
  /// hand-written query would, so a staff/accountant caller passing
  /// [staffId] for someone else simply gets zero rows back, never an error
  /// and never someone else's shift.
  Future<List<StaffShift>> list({
    String? staffId,
    DateTime? from,
    DateTime? to,
  }) =>
      _guard(() async {
        final rows = await _db.rpc('list_staff_shifts', params: {
          'p_staff_id': staffId,
          'p_from': from == null ? null : _dateOnly(from),
          'p_to': to == null ? null : _dateOnly(to),
        }) as List<dynamic>;
        return rows
            .map((e) => StaffShift.fromJson(e as Map<String, dynamic>))
            .toList();
      });

  /// Inserts one row per calendar day in [range] (inclusive of both ends),
  /// all carrying the same [start]/[end]/[notes] -- a single day is simply
  /// a range whose start equals its end. One batched `insert` call, not
  /// one round trip per day.
  Future<void> createRange({
    required String staffId,
    required DateTimeRange range,
    required TimeOfDay start,
    required TimeOfDay end,
    String? notes,
  }) =>
      _guard(() async {
        final rows = <Map<String, dynamic>>[];
        for (var d = range.start;
            !d.isAfter(range.end);
            d = d.add(const Duration(days: 1))) {
          rows.add({
            'staff_id': staffId,
            'shift_date': _dateOnly(d),
            'start_time': formatTimeOfDay(start),
            'end_time': formatTimeOfDay(end),
            'notes': notes,
          });
        }
        await _db.from('staff_shifts').insert(rows);
      });

  /// Edits one already-created shift row in place (date, time, notes --
  /// not a bulk range operation; that's [createRange]'s job for new
  /// assignments only).
  Future<StaffShift> updateOne(StaffShift shift) => _guard(() async {
        final row = await _db
            .from('staff_shifts')
            .update(shift.toInsert())
            .eq('id', shift.id)
            .select()
            .single();
        return StaffShift.fromJson(row);
      });

  Future<void> delete(String id) => _guard(() async {
        await _db.from('staff_shifts').delete().eq('id', id);
      });
}

final staffShiftRepositoryProvider = Provider<StaffShiftRepository>(
  (ref) => StaffShiftRepository(ref.watch(supabaseProvider)),
);

final staffShiftsProvider =
    FutureProvider.family<List<StaffShift>, StaffShiftFilter>(
  (ref, filter) => ref.watch(staffShiftRepositoryProvider).list(
        staffId: filter.staffId,
        from: filter.from,
        to: filter.to,
      ),
);
