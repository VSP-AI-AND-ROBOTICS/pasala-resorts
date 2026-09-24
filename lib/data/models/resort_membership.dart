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

  /// A row whose resort embed is missing is rejected, not defaulted to an
  /// `active` resort with no name -- see [membershipsFromEmbed], which drops
  /// those rows before they get here.
  factory ResortMembership.fromJson(Map<String, dynamic> json) {
    final property = json['properties'];
    if (property is! Map<String, dynamic>) {
      throw ArgumentError(
        'Membership of ${json['property_id']} has no readable resort',
      );
    }
    return ResortMembership(
      propertyId: json['property_id'] as String,
      resortName: property['name'] as String,
      role: resortRoleFromDb(json['role'] as String),
      status: property['status'] as String,
    );
  }

  final String propertyId;
  final String resortName;
  final ResortRole role;

  /// The resort's own status (`active`/`suspended`), not the membership's.
  /// Archived resorts never get here -- see [membershipsFromEmbed].
  final String status;
}

/// Parses the `resort_members(..., properties(name, status))` embed of a
/// profile row into the memberships the user can actually work in.
///
/// `properties_read` hides an archived resort even from its own members,
/// so such a membership comes back with a null `properties` embed; it is
/// dropped here (as is any row whose resort says `archived`), rather than
/// kept as a nameless resort that would be auto-picked, refused by every
/// resort-scoped call with `P0020`, and picked again after the reload.
/// Suspended resorts stay: their members still read their data.
List<ResortMembership> membershipsFromEmbed(List<dynamic>? rows) => [
  for (final row in (rows ?? const []).cast<Map<String, dynamic>>())
    if (row['properties'] case final Map<String, dynamic> resort
        when resort['status'] != 'archived')
      ResortMembership.fromJson(row),
];
