import 'resort_membership.dart';

/// A platform-level role, distinct from a [ResortRole] at any one resort.
/// The platform admin gets no row access to resort-owned tables -- it is
/// an operator role, not a membership.
enum PlatformRole { customer, platformAdmin }

class AppUser {
  const AppUser({
    required this.id,
    required this.email,
    this.platformRole = PlatformRole.customer,
    this.memberships = const [],
    this.fullName,
    this.phone,
  });

  final String id;
  final String email;
  final String? fullName;
  final String? phone;

  final PlatformRole platformRole;
  final List<ResortMembership> memberships;

  bool get isPlatformAdmin => platformRole == PlatformRole.platformAdmin;

  ResortMembership? membershipFor(String propertyId) {
    for (final m in memberships) {
      if (m.propertyId == propertyId) return m;
    }
    return null;
  }
}
