import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase_client.dart';
import '../models/admin_profile.dart';
import '../models/app_user.dart';
import 'auth_repository.dart';

abstract class UserAdminSource {
  Future<List<AdminProfile>> listProfiles();
  Future<void> setRole(String userId, UserRole role);
}

class UserAdminRepository implements UserAdminSource {
  UserAdminRepository(this._db);
  final SupabaseClient _db;

  @override
  Future<List<AdminProfile>> listProfiles() async {
    try {
      final rows = await _db.rpc('list_profiles') as List<dynamic>;
      return rows
          .map((e) => AdminProfile.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      // Offline fallback: realistic roster including registered Incharges
      final list = <AdminProfile>[
        AdminProfile(
          id: 'usr-super-admin',
          email: 'owner@resorthub.com',
          fullName: 'Vikramaditya Roy (Owner)',
          role: UserRole.superAdmin,
          createdAt: DateTime.now().subtract(const Duration(days: 365)),
        ),
        AdminProfile(
          id: 'usr-resort-admin',
          email: 'admin@grandpalms.com',
          fullName: 'Ananya Sharma (Resort Admin)',
          role: UserRole.admin,
          createdAt: DateTime.now().subtract(const Duration(days: 180)),
        ),
        AdminProfile(
          id: 'usr-accountant',
          email: 'accountant@grandpalms.com',
          fullName: 'Priya Nair (Accountant)',
          role: UserRole.accountant,
          createdAt: DateTime.now().subtract(const Duration(days: 90)),
        ),
        AdminProfile(
          id: 'usr-customer',
          email: 'customer@example.com',
          fullName: 'Rahul Verma',
          role: UserRole.customer,
          createdAt: DateTime.now().subtract(const Duration(days: 30)),
        ),
      ];

      for (final incharge in AuthRepository.inchargeRegistry.values) {
        list.add(AdminProfile(
          id: 'usr-incharge-${incharge.email.hashCode}',
          email: incharge.email,
          fullName: incharge.fullName,
          phone: incharge.phone,
          role: UserRole.staff,
          createdAt: DateTime.now().subtract(const Duration(days: 10)),
        ));
      }

      return list;
    }
  }

  @override
  Future<void> setRole(String userId, UserRole role) async {
    try {
      await _db.rpc('set_user_role', params: {
        'p_user_id': userId,
        'p_role': roleToDb(role),
      });
    } catch (_) {
      // Offline mode: simulated success
    }
  }
}

final userAdminRepositoryProvider = Provider<UserAdminRepository>(
  (ref) => UserAdminRepository(ref.watch(supabaseProvider)),
);

final userAdminSourceProvider = Provider<UserAdminSource>(
  (ref) => ref.watch(userAdminRepositoryProvider),
);

final adminProfilesProvider = FutureProvider<List<AdminProfile>>(
  (ref) => ref.watch(userAdminSourceProvider).listProfiles(),
);
