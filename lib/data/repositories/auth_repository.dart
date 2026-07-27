import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors.dart';
import '../../core/supabase_client.dart';
import '../models/app_user.dart';

class AuthRepository {
  AuthRepository(this._db);
  final SupabaseClient _db;

  Future<AppUser> _profileFor(User user) async {
    final row =
        await _db.from('profiles').select().eq('id', user.id).maybeSingle();
    return AppUser(
      id: user.id,
      email: user.email ?? '',
      fullName: row?['full_name'] as String?,
      phone: row?['phone'] as String?,
      role: roleFromDb(row?['role'] as String? ?? 'customer'),
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

  Future<void> signOut() => _db.auth.signOut();

  Future<AppUser?> current() async {
    final user = _db.auth.currentUser;
    return user == null ? null : _profileFor(user);
  }

  Stream<AppUser?> watch() => _db.auth.onAuthStateChange.asyncMap(
        (state) async => state.session == null
            ? null
            : await _profileFor(state.session!.user),
      );
}

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(ref.watch(supabaseProvider)),
);

final currentUserProvider = StreamProvider<AppUser?>((ref) async* {
  final repo = ref.watch(authRepositoryProvider);
  yield await repo.current();
  yield* repo.watch();
});
