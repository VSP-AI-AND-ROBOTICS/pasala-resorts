import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors.dart';
import '../../core/supabase_client.dart';
import '../models/admin_profile.dart';

/// Read-only staff directory backing the assignee pickers on the Tasks,
/// Staff Shifts, Attendance, Leave Requests, Maintenance Issues, Service
/// Requests and Staff Performance screens.
///
/// Split out of the old `UserAdminRepository` (deleted in Task 14 along
/// with the Users screen and the global `UserRole` it depended on): this
/// keeps only the read-only `list_profiles` call those pickers need. Role
/// management itself moves to the resort-scoped `list_resort_members` and
/// the Team screen (Task 18) -- this repository is a bridge until then, so
/// [listProfiles] is not yet scoped to the current resort the way a
/// picker should be; see `AdminProfile.isStaffOrAbove`'s doc comment.
class ProfileDirectoryRepository {
  ProfileDirectoryRepository(this._db);
  final SupabaseClient _db;

  Future<List<AdminProfile>> listProfiles() async {
    try {
      final rows = await _db.rpc('list_profiles') as List<dynamic>;
      return rows
          .map((e) => AdminProfile.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw mapPostgrestError(e);
    }
  }
}

final profileDirectoryRepositoryProvider =
    Provider<ProfileDirectoryRepository>(
  (ref) => ProfileDirectoryRepository(ref.watch(supabaseProvider)),
);

final adminProfilesProvider = FutureProvider<List<AdminProfile>>(
  (ref) => ref.watch(profileDirectoryRepositoryProvider).listProfiles(),
);
