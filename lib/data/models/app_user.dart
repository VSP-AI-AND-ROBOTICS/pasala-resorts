enum UserRole { customer, staff, admin, accountant, superAdmin }

UserRole roleFromDb(String raw) => switch (raw) {
      'customer' => UserRole.customer,
      'staff' => UserRole.staff,
      'admin' => UserRole.admin,
      'accountant' => UserRole.accountant,
      'super_admin' => UserRole.superAdmin,
      _ => UserRole.customer,
    };

/// Inverse of [roleFromDb] -- needed by `set_user_role`'s `p_role` param
/// (`UserAdminRepository.setRole`), which takes the enum's Postgres text
/// label, not Dart's camelCase name.
String roleToDb(UserRole role) => switch (role) {
      UserRole.customer => 'customer',
      UserRole.staff => 'staff',
      UserRole.admin => 'admin',
      UserRole.accountant => 'accountant',
      UserRole.superAdmin => 'super_admin',
    };

class AppUser {
  const AppUser({
    required this.id,
    required this.email,
    required this.role,
    this.fullName,
    this.phone,
  });

  final String id;
  final String email;
  final String? fullName;
  final String? phone;
  final UserRole role;

  bool get isAdmin => role == UserRole.admin || role == UserRole.superAdmin;
  bool get isStaffOrAbove => role != UserRole.customer;
}
