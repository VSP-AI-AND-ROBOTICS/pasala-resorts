import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors.dart';
import '../../core/supabase_client.dart';
import '../models/leave_request.dart';

/// The (staff, status) an admin or staff screen wants to see -- `staffId:
/// null` means "every staff member" (admin only; RLS returns only the
/// caller's own rows for anyone else regardless), `status: null` means
/// "every status." A record, not positional params, so
/// `FutureProvider.family` can key on it directly.
typedef LeaveRequestFilter = ({String? staffId, LeaveStatus? status});

class LeaveRequestRepository {
  LeaveRequestRepository(this._db);
  final SupabaseClient _db;

  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } catch (e) {
      throw mapPostgrestError(e);
    }
  }

  /// A direct table select with a `profiles` embed for `staff_name` --
  /// unlike Work Schedules' `list_staff_shifts()` RPC, no RPC is needed
  /// here: neither this method nor either screen ever lets a caller pick
  /// someone else's id to filter by (staff/accountant screens always pass
  /// their own id, admin passes whatever it likes since it can already
  /// see everything), so there is no filter-based leak for an RPC to
  /// close that plain RLS doesn't already close on its own.
  Future<List<LeaveRequest>> list({
    String? staffId,
    LeaveStatus? status,
  }) =>
      _guard(() async {
        dynamic query = _db
            .from('leave_requests')
            .select('*, profiles!leave_requests_staff_id_fkey(full_name)');
        if (staffId != null) query = query.eq('staff_id', staffId);
        if (status != null) query = query.eq('status', leaveStatusToDb(status));
        final rows = await query.order('created_at', ascending: false) as List;
        return rows
            .map((e) => LeaveRequest.fromJson(e as Map<String, dynamic>))
            .toList();
      });

  /// Submits one new request, always `pending` (the server column default
  /// and `leave_requests_own_insert`'s `with check` both enforce this --
  /// the client never sends a `status`).
  Future<void> create({
    required String staffId,
    required DateTimeRange range,
    String? reason,
  }) =>
      _guard(() async {
        await _db.from('leave_requests').insert(
              LeaveRequest(
                id: '',
                staffId: staffId,
                startDate: range.start,
                endDate: range.end,
                reason: reason,
                status: LeaveStatus.pending,
              ).toInsert(),
            );
      });

  /// Records an admin's decision. [decided_by] is the CALLING admin's own
  /// id (only an admin can reach this method's RLS-gated update path at
  /// all) -- set client-side, unlike `staff_shifts.created_by`'s
  /// `default auth.uid()`, because this single call must set `status` and
  /// `decided_by` together, and a column `default` only applies on
  /// insert, never on update.
  Future<void> decide({
    required String id,
    required bool approved,
  }) =>
      _guard(() async {
        final adminId = _db.auth.currentUser!.id;
        await _db.from('leave_requests').update({
          'status': leaveStatusToDb(approved ? LeaveStatus.approved : LeaveStatus.rejected),
          'decided_by': adminId,
          'decided_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('id', id);
      });
}

final leaveRequestRepositoryProvider = Provider<LeaveRequestRepository>(
  (ref) => LeaveRequestRepository(ref.watch(supabaseProvider)),
);

final leaveRequestsProvider =
    FutureProvider.family<List<LeaveRequest>, LeaveRequestFilter>(
  (ref, filter) => ref.watch(leaveRequestRepositoryProvider).list(
        staffId: filter.staffId,
        status: filter.status,
      ),
);
