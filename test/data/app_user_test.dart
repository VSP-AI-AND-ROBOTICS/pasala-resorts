import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/data/models/app_user.dart';
import 'package:pasala/data/models/resort_membership.dart';

void main() {
  const a = ResortMembership(propertyId: 'a', resortName: 'A', role: ResortRole.owner);
  const b = ResortMembership(propertyId: 'b', resortName: 'B', role: ResortRole.staff);

  test('membershipFor finds the role at a given resort', () {
    const u = AppUser(id: 'u', email: 'u@x', memberships: [a, b]);
    expect(u.membershipFor('b')?.role, ResortRole.staff);
    expect(u.membershipFor('c'), isNull);
  });

  test('platform admin flag', () {
    const u = AppUser(id: 'u', email: 'u@x', platformRole: PlatformRole.platformAdmin);
    expect(u.isPlatformAdmin, isTrue);
  });
}
