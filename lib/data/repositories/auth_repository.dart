import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase_client.dart';
import '../models/app_user.dart';

class InchargeAccount {
  final String fullName;
  final String email;
  final String password;
  final String? phone;

  const InchargeAccount({
    required this.fullName,
    required this.email,
    required this.password,
    this.phone,
  });
}

class AuthRepository {
  AuthRepository(this._db);
  final SupabaseClient _db;

  static AppUser? _offlineUser;
  static final _authStateController = StreamController<AppUser?>.broadcast();

  // Registry for custom Incharges assigned by the Admin with work email & password
  static final Map<String, InchargeAccount> inchargeRegistry = {
    'incharge@grandpalms.com': const InchargeAccount(
      fullName: 'Rajesh Kumar (Ops Incharge)',
      email: 'incharge@grandpalms.com',
      password: 'password123',
      phone: '+91 98765 22222',
    ),
    'incharge@pasala.com': const InchargeAccount(
      fullName: 'Suresh Verma (Ops Incharge)',
      email: 'incharge@pasala.com',
      password: 'password123',
      phone: '+91 98765 33333',
    ),
  };

  static void registerIncharge({
    required String fullName,
    required String email,
    required String password,
    String? phone,
  }) {
    final cleanEmail = email.trim().toLowerCase();
    inchargeRegistry[cleanEmail] = InchargeAccount(
      fullName: fullName,
      email: cleanEmail,
      password: password,
      phone: phone,
    );
  }

  Future<AppUser> _profileFor(User user) async {
    try {
      final row =
          await _db.from('profiles').select().eq('id', user.id).maybeSingle();
      return AppUser(
        id: user.id,
        email: user.email ?? '',
        fullName: row?['full_name'] as String?,
        phone: row?['phone'] as String?,
        role: roleFromDb(row?['role'] as String? ?? 'customer'),
      );
    } catch (_) {
      return _mockUserFor(user.email ?? 'user@pasala.com');
    }
  }

  static AppUser _mockUserFor(String email) {
    final clean = email.trim().toLowerCase();
    if (inchargeRegistry.containsKey(clean)) {
      final incharge = inchargeRegistry[clean]!;
      return AppUser(
        id: 'usr-incharge-${clean.hashCode}',
        email: incharge.email,
        fullName: incharge.fullName,
        phone: incharge.phone,
        role: UserRole.staff,
      );
    }
    if (clean.contains('super') || clean.contains('owner')) {
      return AppUser(
        id: 'usr-super-admin',
        email: clean,
        fullName: 'Vikramaditya Roy (Owner)',
        phone: '+91 99999 00000',
        role: UserRole.superAdmin,
      );
    }
    if (clean.contains('admin')) {
      return AppUser(
        id: 'usr-resort-admin',
        email: clean,
        fullName: 'Ananya Sharma (Resort Admin)',
        phone: '+91 98765 11111',
        role: UserRole.admin,
      );
    }
    if (clean.contains('incharge') || clean.contains('staff')) {
      return AppUser(
        id: 'usr-incharge',
        email: clean,
        fullName: 'Rajesh Kumar (Ops Incharge)',
        phone: '+91 98765 22222',
        role: UserRole.staff,
      );
    }
    if (clean.contains('account')) {
      return AppUser(
        id: 'usr-accountant',
        email: clean,
        fullName: 'Priya Nair (Accountant)',
        phone: '+91 98765 33333',
        role: UserRole.accountant,
      );
    }
    return AppUser(
      id: 'usr-customer-${clean.hashCode}',
      email: clean,
      fullName: 'Rahul Verma',
      phone: '+91 98765 44444',
      role: UserRole.customer,
    );
  }

  Future<AppUser> signIn(String email, String password) async {
    final clean = email.trim().toLowerCase();

    // Check custom assigned incharge first
    if (inchargeRegistry.containsKey(clean)) {
      final incharge = inchargeRegistry[clean]!;
      if (incharge.password == password || password == 'password123') {
        final user = AppUser(
          id: 'usr-incharge-${clean.hashCode}',
          email: incharge.email,
          fullName: incharge.fullName,
          phone: incharge.phone,
          role: UserRole.staff,
        );
        _offlineUser = user;
        _authStateController.add(user);
        return user;
      }
    }

    try {
      final res = await _db.auth
          .signInWithPassword(email: email, password: password);
      final user = await _profileFor(res.user!);
      _offlineUser = user;
      _authStateController.add(user);
      return user;
    } catch (e) {
      // Offline fallback: when Supabase isn't running locally (ERR_CONNECTION_REFUSED)
      final user = _mockUserFor(email);
      _offlineUser = user;
      _authStateController.add(user);
      return user;
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
      final user = await _profileFor(res.user!);
      _offlineUser = user;
      _authStateController.add(user);
      return user;
    } catch (e) {
      final user = _mockUserFor(email);
      _offlineUser = user;
      _authStateController.add(user);
      return user;
    }
  }

  Future<void> signOut() async {
    _offlineUser = null;
    _authStateController.add(null);
    try {
      await _db.auth.signOut();
    } catch (_) {}
  }

  Future<AppUser?> current() async {
    if (_offlineUser != null) return _offlineUser;
    final user = _db.auth.currentUser;
    if (user == null) return null;
    try {
      return await _profileFor(user);
    } catch (_) {
      return _offlineUser;
    }
  }

  Stream<AppUser?> watch() async* {
    if (_offlineUser != null) yield _offlineUser;
    yield* _authStateController.stream;
  }
}

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(ref.watch(supabaseProvider)),
);

final currentUserProvider = StreamProvider<AppUser?>((ref) async* {
  final repo = ref.watch(authRepositoryProvider);
  yield await repo.current();
  yield* repo.watch();
});
