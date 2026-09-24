/// One row of `public.list_profiles()` -- a profile plus its email, joined
/// in from `auth.users` server-side (see 0019_user_admin.sql) because no
/// client role, not even admin, has a grant on `auth.users` itself.
class AdminProfile {
  const AdminProfile({
    required this.id,
    required this.email,
    required this.isStaffOrAbove,
    required this.createdAt,
    this.fullName,
    this.phone,
  });

  final String id;
  final String? fullName;
  final String? phone;

  /// Whether this profile's (legacy, global, pre-tenancy) role is anything
  /// but `customer` -- the only thing every assignee-picker screen that
  /// reads this model actually needed. Kept as a bare bool rather than the
  /// full `UserRole` enum (deleted from `app_user.dart` in Task 14, along
  /// with `AppUser.role`) since nothing else here ever used the specific
  /// role -- see `ProfileDirectoryRepository`'s doc comment.
  final bool isStaffOrAbove;

  final String email;
  final DateTime createdAt;

  factory AdminProfile.fromJson(Map<String, dynamic> json) => AdminProfile(
        id: json['id'] as String,
        fullName: json['full_name'] as String?,
        phone: json['phone'] as String?,
        isStaffOrAbove: json['role'] != 'customer',
        email: json['email'] as String? ?? '',
        createdAt: DateTime.parse(json['created_at'] as String).toUtc(),
      );
}
