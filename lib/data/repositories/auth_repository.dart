import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors.dart';
import '../../core/supabase_client.dart';
import '../models/app_user.dart';
import '../models/resort_membership.dart';

class AuthRepository {
  AuthRepository(this._db);
  final SupabaseClient _db;

  Future<AppUser> _profileFor(User user) async {
    final row = await _db
        .from('profiles')
        .select('*, resort_members(property_id, role, properties(name, status))')
        .eq('id', user.id)
        .maybeSingle();
    final memberships = membershipsFromEmbed(row?['resort_members'] as List?);
    return AppUser(
      id: user.id,
      email: user.email ?? '',
      fullName: row?['full_name'] as String?,
      phone: row?['phone'] as String?,
      platformRole: row?['role'] == 'platform_admin'
          ? PlatformRole.platformAdmin
          : PlatformRole.customer,
      memberships: memberships,
    );
  }

  Future<AppUser> signIn(String email, String password) async {
    try {
      final res = await _db.auth
          .signInWithPassword(email: email, password: password);
      return _profileFor(res.user!);
    } catch (e) {
      throw mapPostgrestError(e);
    }
  }

  Future<AppUser> signUp({
    required String email,
    required String password,
    required String fullName,
  }) async {
    try {
      final res = await _db.auth.signUp(
        email: email,
        password: password,
        data: {'full_name': fullName},
      );
      return _profileFor(res.user!);
    } catch (e) {
      throw mapPostgrestError(e);
    }
  }

  Future<void> signOut() async {
    try {
      await _db.auth.signOut();
    } catch (e) {
      throw mapPostgrestError(e);
    }
  }

  Future<AppUser?> current() async {
    final user = _db.auth.currentUser;
    if (user == null) return null;
    try {
      return await _profileFor(user);
    } catch (e) {
      throw mapPostgrestError(e);
    }
  }

  Stream<AppUser?> watch() => _db.auth.onAuthStateChange
      .asyncMap((state) async {
        if (state.session == null) return null;
        try {
          return await _profileFor(state.session!.user);
        } catch (e) {
          throw mapPostgrestError(e);
        }
      })
      .handleError((Object e) => throw mapPostgrestError(e));
}

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(ref.watch(supabaseProvider)),
);

/// Deliberately keeps Riverpod's default auto-retry: this is app-wide auth
/// state the router depends on, not just StaffProfileScreen's secondary Retry.
final currentUserProvider = StreamProvider<AppUser?>((ref) async* {
  final repo = ref.watch(authRepositoryProvider);
  yield await repo.current();
  yield* repo.watch();
});
