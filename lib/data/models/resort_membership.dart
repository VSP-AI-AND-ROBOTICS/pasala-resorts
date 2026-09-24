enum ResortRole { owner, admin, staff, accountant }

/// Unknown role text is rejected, not defaulted -- a silent fallback would
/// hide a data bug (a resort_members row with a role Postgres's enum no
/// longer has, or a typo introduced by a future migration).
ResortRole resortRoleFromDb(String raw) => switch (raw) {
      'owner' => ResortRole.owner,
      'admin' => ResortRole.admin,
      'staff' => ResortRole.staff,
      'accountant' => ResortRole.accountant,
      _ => throw ArgumentError('Unknown resort role: $raw'),
    };

/// Inverse of [resortRoleFromDb] -- the Postgres `resort_role` enum's text
/// label, not Dart's camelCase name.
String resortRoleToDb(ResortRole role) => switch (role) {
      ResortRole.owner => 'owner',
      ResortRole.admin => 'admin',
      ResortRole.staff => 'staff',
      ResortRole.accountant => 'accountant',
    };

/// UI copy says "Resort"; `staff` is labelled "Staff / Incharge" per the
/// tenancy spec.
String resortRoleLabel(ResortRole role) => switch (role) {
      ResortRole.owner => 'Owner',
      ResortRole.admin => 'Admin',
      ResortRole.staff => 'Staff / Incharge',
      ResortRole.accountant => 'Accountant',
    };

/// One row of `resort_members`, joined with the resort (`properties`) it
/// grants access to.
class ResortMembership {
  const ResortMembership({
    required this.propertyId,
    required this.resortName,
    required this.role,
    this.status = 'active',
  });

  factory ResortMembership.fromJson(Map<String, dynamic> json) {
    final property = json['properties'] as Map<String, dynamic>?;
    return ResortMembership(
      propertyId: json['property_id'] as String,
      resortName: property?['name'] as String? ?? '',
      role: resortRoleFromDb(json['role'] as String),
      status: property?['status'] as String? ?? 'active',
    );
  }

  final String propertyId;
  final String resortName;
  final ResortRole role;

  /// The resort's own status (`active`/`suspended`), not the membership's.
  final String status;
}
