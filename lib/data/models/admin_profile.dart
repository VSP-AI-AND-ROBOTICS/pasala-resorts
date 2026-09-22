import 'app_user.dart';

/// One row of `public.list_profiles()` -- a profile plus its email, joined
/// in from `auth.users` server-side (see 0019_user_admin.sql) because no
/// client role, not even admin, has a grant on `auth.users` itself.
class AdminProfile {
  const AdminProfile({
    required this.id,
    required this.email,
    required this.role,
    required this.createdAt,
    this.fullName,
    this.phone,
  });

  final String id;
  final String? fullName;
  final String? phone;
  final UserRole role;
  final String email;
  final DateTime createdAt;

  factory AdminProfile.fromJson(Map<String, dynamic> json) => AdminProfile(
        id: json['id'] as String,
        fullName: json['full_name'] as String?,
        phone: json['phone'] as String?,
        role: roleFromDb(json['role'] as String),
        email: json['email'] as String? ?? '',
        createdAt: DateTime.parse(json['created_at'] as String).toUtc(),
      );
}
