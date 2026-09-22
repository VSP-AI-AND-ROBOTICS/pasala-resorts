import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors.dart';
import '../../core/supabase_client.dart';
import '../models/admin_profile.dart';
import '../models/app_user.dart';

/// The slice of [UserAdminRepository] that [UsersScreen] needs, mirroring
/// [OutboxSource] in `outbox_repository.dart`: tests override just this
/// provider with a fake instead of needing a real `SupabaseClient`.
abstract class UserAdminSource {
  Future<List<AdminProfile>> listProfiles();
  Future<void> setRole(String userId, UserRole role);
}

/// Backs `/admin/users`. Both RPCs it calls are gated server-side --
/// `list_profiles` to admin-or-above, `set_user_role` to super_admin only
/// (see 0019_user_admin.sql) -- so this repository does no role-checking of
/// its own; a plain admin calling [setRole] simply gets `P0008` back
/// through [mapPostgrestError], same as any other RPC in this app.
class UserAdminRepository implements UserAdminSource {
  UserAdminRepository(this._db);
  final SupabaseClient _db;

  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } catch (e) {
      throw mapPostgrestError(e);
    }
  }

  @override
  Future<List<AdminProfile>> listProfiles() => _guard(() async {
        final rows = await _db.rpc('list_profiles') as List<dynamic>;
        return rows
            .map((e) => AdminProfile.fromJson(e as Map<String, dynamic>))
            .toList();
      });

  @override
  Future<void> setRole(String userId, UserRole role) => _guard(() async {
        await _db.rpc('set_user_role', params: {
          'p_user_id': userId,
          'p_role': roleToDb(role),
        });
      });
}

final userAdminRepositoryProvider = Provider<UserAdminRepository>(
  (ref) => UserAdminRepository(ref.watch(supabaseProvider)),
);

/// [UserAdminSource] seam around [userAdminRepositoryProvider], mirroring
/// [outboxSourceProvider] in `outbox_repository.dart`.
final userAdminSourceProvider = Provider<UserAdminSource>(
  (ref) => ref.watch(userAdminRepositoryProvider),
);

final adminProfilesProvider = FutureProvider<List<AdminProfile>>(
  (ref) => ref.watch(userAdminSourceProvider).listProfiles(),
);
