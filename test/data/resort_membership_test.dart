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
}
