import 'resort_membership.dart';

@Deprecated('Use memberships and currentResortProvider')
enum UserRole { customer, staff, admin, accountant, superAdmin }

@Deprecated('Use memberships and currentResortProvider')
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
@Deprecated('Use memberships and currentResortProvider')
String roleToDb(UserRole role) => switch (role) {
      UserRole.customer => 'customer',
      UserRole.staff => 'staff',
      UserRole.admin => 'admin',
      UserRole.accountant => 'accountant',
      UserRole.superAdmin => 'super_admin',
    };

/// A platform-level role, distinct from a [ResortRole] at any one resort.
/// The platform admin gets no row access to resort-owned tables -- it is
/// an operator role, not a membership.
enum PlatformRole { customer, platformAdmin }

class AppUser {
  const AppUser({
    required this.id,
    required this.email,
    @Deprecated('Use memberships and currentResortProvider')
    this.role = UserRole.customer,
    this.platformRole = PlatformRole.customer,
    this.memberships = const [],
    this.fullName,
    this.phone,
  });

  final String id;
  final String email;
  final String? fullName;
  final String? phone;

  @Deprecated('Use memberships and currentResortProvider')
  final UserRole role;

  final PlatformRole platformRole;
  final List<ResortMembership> memberships;

  @Deprecated('Use memberships and currentResortProvider')
  bool get isAdmin => role == UserRole.admin || role == UserRole.superAdmin;

  @Deprecated('Use memberships and currentResortProvider')
  bool get isStaffOrAbove => role != UserRole.customer;

  bool get isPlatformAdmin => platformRole == PlatformRole.platformAdmin;

  ResortMembership? membershipFor(String propertyId) {
    for (final m in memberships) {
      if (m.propertyId == propertyId) return m;
    }
    return null;
  }
}
