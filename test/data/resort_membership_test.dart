import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/data/models/resort_membership.dart';

void main() {
  test('parses a membership row joined with its resort', () {
    final m = ResortMembership.fromJson({
      'property_id': 'p1',
      'role': 'staff',
      'properties': {'name': 'Pasala Farm House', 'status': 'active'},
    });
    expect(m.propertyId, 'p1');
    expect(m.resortName, 'Pasala Farm House');
    expect(m.role, ResortRole.staff);
    expect(resortRoleLabel(m.role), 'Staff / Incharge');
  });

  test('unknown role text is rejected, not defaulted', () {
    expect(() => resortRoleFromDb('super_admin'), throwsArgumentError);
  });

  // Final review I1: properties_read hides an archived resort from its own
  // members, so the embed comes back null. Such a membership must be
  // dropped, not auto-picked as an "active" resort with an empty name.
  test('a membership whose embedded resort is missing is rejected, not '
      'defaulted to active', () {
    expect(
      () => ResortMembership.fromJson({
        'property_id': 'p1',
        'role': 'staff',
        'properties': null,
      }),
      throwsArgumentError,
    );
  });

  test('membershipsFromEmbed keeps active and suspended resorts and drops '
      'hidden or archived ones', () {
    final memberships = membershipsFromEmbed([
      {
        'property_id': 'active',
        'role': 'owner',
        'properties': {'name': 'Active Resort', 'status': 'active'},
      },
      {
        'property_id': 'suspended',
        'role': 'staff',
        'properties': {'name': 'Suspended Resort', 'status': 'suspended'},
      },
      {'property_id': 'hidden', 'role': 'admin', 'properties': null},
      {
        'property_id': 'archived',
        'role': 'admin',
        'properties': {'name': 'Archived Resort', 'status': 'archived'},
      },
    ]);

    expect(memberships.map((m) => m.propertyId), ['active', 'suspended']);
    expect(memberships.last.status, 'suspended');
  });

  test('membershipsFromEmbed treats a missing embed as no memberships', () {
    expect(membershipsFromEmbed(null), isEmpty);
  });
}
