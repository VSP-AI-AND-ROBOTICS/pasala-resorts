enum UserRole { customer, staff, admin, accountant, superAdmin }

UserRole roleFromDb(String raw) => switch (raw) {
      'customer' => UserRole.customer,
      'staff' => UserRole.staff,
      'admin' => UserRole.admin,
      'accountant' => UserRole.accountant,
      'super_admin' => UserRole.superAdmin,
      _ => UserRole.customer,
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
