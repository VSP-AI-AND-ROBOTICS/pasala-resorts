import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors.dart';
import '../../core/supabase_client.dart';
import '../models/resort_membership.dart';

/// One row of `list_resort_members(p_property)` -- an existing account's
/// membership at a resort, joined server-side with its profile and
/// `auth.users` email (see 0045_resort_functions.sql), same shape as the
/// deleted `AdminProfile` but resort-scoped instead of global. Also backs
/// the staff pickers on the admin and owner staff-ops screens.
class ResortMember {
  const ResortMember({
    required this.userId,
    required this.email,
    this.fullName,
    required this.role,
    required this.createdAt,
  });

  factory ResortMember.fromJson(Map<String, dynamic> json) => ResortMember(
        userId: json['user_id'] as String,
        email: json['email'] as String,
        fullName: json['full_name'] as String?,
        role: resortRoleFromDb(json['role'] as String),
        createdAt: DateTime.parse(json['created_at'] as String).toUtc(),
      );

  final String userId;
  final String email;
  final String? fullName;
  final ResortRole role;
  final DateTime createdAt;
}

/// The slice of [ResortMemberRepository] that [TeamScreen] needs, mirroring
/// the deleted `UserAdminSource`: tests override just this provider with a
/// fake instead of needing a real `SupabaseClient`.
abstract class ResortMemberSource {
  Future<List<ResortMember>> list(String propertyId);
  Future<void> add(String propertyId, String email, ResortRole role);
  Future<void> setRole(String propertyId, String userId, ResortRole role);
  Future<void> remove(String propertyId, String userId);
}

/// Backs `/owner/team` via `list_resort_members`, `add_resort_member`,
/// `set_member_role` and `remove_resort_member` -- all four owner-only
/// server-side (see 0045_resort_functions.sql), so this repository does no
/// role-checking of its own; a non-owner calling any of them simply gets
/// `P0020`/`P0008` back through [mapPostgrestError], same as any other RPC.
class ResortMemberRepository implements ResortMemberSource {
  ResortMemberRepository(this._db);
  final SupabaseClient _db;

  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } catch (e) {
      throw mapPostgrestError(e);
    }
  }

  @override
  Future<List<ResortMember>> list(String propertyId) => _guard(() async {
        final rows = await _db.rpc('list_resort_members', params: {
          'p_property': propertyId,
        }) as List<dynamic>;
        return rows
            .map((e) => ResortMember.fromJson(e as Map<String, dynamic>))
            .toList();
      });

  /// Adds an existing account, found by [email], as a member of
  /// [propertyId] with [role]. See [NoAccountFound]'s doc comment for why
  /// this method's `P0002` is caught here rather than left to the global
  /// [mapPostgrestError] mapping.
  @override
  Future<void> add(String propertyId, String email, ResortRole role) =>
      _guard(() async {
        try {
          await _db.rpc('add_resort_member', params: {
            'p_property': propertyId,
            'p_email': email,
            'p_role': resortRoleToDb(role),
          });
        } on PostgrestException catch (e) {
          if (e.code == 'P0002') throw const NoAccountFound();
          rethrow;
        }
      });

  @override
  Future<void> setRole(String propertyId, String userId, ResortRole role) =>
      _guard(() async {
        await _db.rpc('set_member_role', params: {
          'p_property': propertyId,
          'p_user': userId,
          'p_role': resortRoleToDb(role),
        });
      });

  @override
  Future<void> remove(String propertyId, String userId) => _guard(() async {
        await _db.rpc('remove_resort_member', params: {
          'p_property': propertyId,
          'p_user': userId,
        });
      });
}

final resortMemberRepositoryProvider = Provider<ResortMemberRepository>(
  (ref) => ResortMemberRepository(ref.watch(supabaseProvider)),
);

/// [ResortMemberSource] seam around [resortMemberRepositoryProvider],
/// mirroring `outboxSourceProvider`: [TeamScreen] only ever calls through
/// this interface, so tests can override just this provider with a fake.
final resortMemberSourceProvider = Provider<ResortMemberSource>(
  (ref) => ref.watch(resortMemberRepositoryProvider),
);

final resortMembersProvider =
    FutureProvider.family<List<ResortMember>, String>(
  (ref, propertyId) => ref.watch(resortMemberSourceProvider).list(propertyId),
  // Screens show their own Retry button; don't also auto-retry (Riverpod 3
  // retries non-Error throws by default).
  retry: (retryCount, error) => null,
);
