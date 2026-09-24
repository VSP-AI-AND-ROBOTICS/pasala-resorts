import 'package:pasala/data/models/resort_membership.dart';
import 'package:pasala/data/repositories/resort_member_repository.dart';

/// Shared roster for the assignee/staff pickers on the admin and owner
/// staff-ops screens, which list `list_resort_members` for the current
/// resort. Every one of those tests pins the current resort to `p1`.
const rosterResortId = 'p1';

/// The one member of resort [rosterResortId].
final rosterStaff = ResortMember(
  userId: 'staff-1',
  email: 'staff@pasala.test',
  fullName: 'Sita Staff',
  role: ResortRole.staff,
  createdAt: DateTime.utc(2026, 1, 1),
);

/// Someone who works at a different resort -- they must never show up in a
/// picker while [rosterResortId] is the current resort.
final rosterOtherResortMember = ResortMember(
  userId: 'other-1',
  email: 'olga@elsewhere.test',
  fullName: 'Olga Otherresort',
  role: ResortRole.staff,
  createdAt: DateTime.utc(2026, 1, 1),
);

/// Overrides [resortMembersProvider] so resort [rosterResortId] lists only
/// [rosterStaff] and any other resort lists only [rosterOtherResortMember]:
/// a screen that asked for the wrong resort's roster would show Olga.
final rosterOverride = resortMembersProvider.overrideWith(
  (ref, propertyId) async =>
      propertyId == rosterResortId ? [rosterStaff] : [rosterOtherResortMember],
);
