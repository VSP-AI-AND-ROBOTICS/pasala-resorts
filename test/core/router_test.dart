import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/router.dart';
import 'package:pasala/data/models/app_user.dart';
import 'package:pasala/data/models/resort_membership.dart';

const _ownerM =
    ResortMembership(propertyId: 'r1', resortName: 'R1', role: ResortRole.owner);
const _adminM =
    ResortMembership(propertyId: 'r1', resortName: 'R1', role: ResortRole.admin);
const _staffM =
    ResortMembership(propertyId: 'r1', resortName: 'R1', role: ResortRole.staff);
const _accountantM = ResortMembership(
    propertyId: 'r1', resortName: 'R1', role: ResortRole.accountant);

const _admin =
    AppUser(id: 'a', email: 'admin@pasala.test', memberships: [_adminM]);
const _superAdmin =
    AppUser(id: 'sa', email: 'sa@pasala.test', memberships: [_ownerM]);
const _staff =
    AppUser(id: 's', email: 'staff@pasala.test', memberships: [_staffM]);
const _accountant = AppUser(
    id: 'ac', email: 'accountant@pasala.test', memberships: [_accountantM]);
const _customer = AppUser(id: 'c', email: 'customer@pasala.test');

String? _to(AppUser? user, ResortMembership? resort, String path) => redirectFor(
      user: user,
      resort: resort,
      path: path,
      onPreAuthScreen: false,
    );

void main() {
  group('unauthenticated', () {
    test('is sent to /login for any protected path', () {
      expect(_to(null, null, '/'), '/login');
      expect(_to(null, null, '/admin/dashboard'), '/login');
    });

    test('is left on /splash, /welcome, /login, and /signup', () {
      for (final path in ['/splash', '/welcome', '/login', '/signup']) {
        expect(
          redirectFor(user: null, resort: null, path: path, onPreAuthScreen: true),
          null,
          reason: path,
        );
      }
    });
  });

  test(
    'a signed-in customer hitting any pre-auth screen is sent home',
    () {
      for (final path in ['/splash', '/welcome', '/login', '/signup']) {
        expect(
          redirectFor(
              user: _customer, resort: null, path: path, onPreAuthScreen: true),
          '/',
          reason: path,
        );
      }
    },
  );

  group('landingPathFor', () {
    test('customer lands on /', () {
      expect(landingPathFor(_customer, null), '/');
    });

    test('staff lands on /staff', () {
      expect(landingPathFor(_staff, _staffM), '/staff');
    });

    test('accountant lands on /staff/dashboard', () {
      expect(landingPathFor(_accountant, _accountantM), '/staff/dashboard');
    });

    test('admin lands on /admin', () {
      expect(landingPathFor(_admin, _adminM), '/admin');
    });

    test('super_admin lands on /owner', () {
      expect(landingPathFor(_superAdmin, _ownerM), '/owner');
    });

    test('owner lands on /owner, staff on /staff, accountant on dashboard', () {
      for (final (role, path) in [
        (ResortRole.owner, '/owner'),
        (ResortRole.admin, '/admin'),
        (ResortRole.staff, '/staff'),
        (ResortRole.accountant, '/staff/dashboard'),
      ]) {
        final m = ResortMembership(propertyId: 'a', resortName: 'A', role: role);
        final u = AppUser(id: 'u', email: 'e', memberships: [m]);
        expect(landingPathFor(u, m), path, reason: '$role');
      }
    });

    test('two memberships without a pick go to /choose-resort', () {
      const u = AppUser(id: 'u', email: 'e', memberships: [
        ResortMembership(propertyId: 'a', resortName: 'A', role: ResortRole.owner),
        ResortMembership(propertyId: 'b', resortName: 'B', role: ResortRole.staff),
      ]);
      expect(landingPathFor(u, null), '/choose-resort');
      expect(
          redirectFor(user: u, resort: null, path: '/admin', onPreAuthScreen: false),
          '/choose-resort');
    });

    test('platform admin lands on /platform; others are refused it', () {
      const admin = AppUser(id: 'p', email: 'e', platformRole: PlatformRole.platformAdmin);
      expect(landingPathFor(admin, null), '/platform');
      const cust = AppUser(id: 'c', email: 'e');
      expect(
          redirectFor(
              user: cust, resort: null, path: '/platform', onPreAuthScreen: false),
          '/404');
    });
  });

  group('redirectFor sends a signed-in user hitting /login by role', () {
    String? loginRedirect(AppUser user, ResortMembership? resort) => redirectFor(
        user: user, resort: resort, path: '/login', onPreAuthScreen: true);

    test('customer -> /', () {
      expect(loginRedirect(_customer, null), '/');
    });

    test('staff -> /staff', () {
      expect(loginRedirect(_staff, _staffM), '/staff');
    });

    test('accountant -> /staff/dashboard', () {
      expect(loginRedirect(_accountant, _accountantM), '/staff/dashboard');
    });

    test('admin -> /admin', () {
      expect(loginRedirect(_admin, _adminM), '/admin');
    });

    test('super_admin -> /owner', () {
      expect(loginRedirect(_superAdmin, _ownerM), '/owner');
    });
  });

  group('admin', () {
    test('reaches every /admin/* route', () {
      for (final path in [
        '/admin',
        '/admin/properties',
        '/admin/units/u1',
        '/admin/rates/u1',
        '/admin/block/u1',
        '/admin/ota/u1',
        '/admin/bookings',
        '/admin/dashboard',
        '/admin/reports',
        '/admin/outbox',
      ]) {
        expect(_to(_admin, _adminM, path), null, reason: path);
      }
    });

    test('super_admin reaches every /admin/* route too', () {
      expect(_to(_superAdmin, _ownerM, '/admin/properties'), null);
      expect(_to(_superAdmin, _ownerM, '/admin/dashboard'), null);
    });
  });

  group('staff', () {
    test('reaches /admin/dashboard, /admin/reports, /admin/outbox, '
        '/admin/check-in and /admin/check-out', () {
      expect(_to(_staff, _staffM, '/admin/dashboard'), null);
      expect(_to(_staff, _staffM, '/admin/reports'), null);
      expect(_to(_staff, _staffM, '/admin/outbox'), null);
      expect(_to(_staff, _staffM, '/admin/check-in'), null);
      expect(_to(_staff, _staffM, '/admin/check-out'), null);
    });

    test('is redirected away from admin-only management routes', () {
      for (final path in [
        '/admin',
        '/admin/properties',
        '/admin/units/u1',
        '/admin/rates/u1',
        '/admin/block/u1',
        '/admin/ota/u1',
        '/admin/bookings',
      ]) {
        expect(_to(_staff, _staffM, path), '/404', reason: path);
      }
    });

    test('reaches /staff and every /staff/* section route', () {
      for (final path in [
        '/staff',
        '/staff/dashboard',
        '/staff/profile',
        '/staff/working-hours',
        '/staff/leave',
        '/staff/tasks',
        '/staff/schedules',
        '/staff/time-slots',
        '/staff/daily-status',
      ]) {
        expect(_to(_staff, _staffM, path), null, reason: path);
      }
    });
  });

  group('accountant', () {
    test('reaches /admin/dashboard, /admin/reports, /admin/outbox, '
        '/admin/check-in and /admin/check-out', () {
      expect(_to(_accountant, _accountantM, '/admin/dashboard'), null);
      expect(_to(_accountant, _accountantM, '/admin/reports'), null);
      expect(_to(_accountant, _accountantM, '/admin/outbox'), null);
      expect(_to(_accountant, _accountantM, '/admin/check-in'), null);
      expect(_to(_accountant, _accountantM, '/admin/check-out'), null);
    });

    test('is redirected away from admin-only management routes', () {
      expect(_to(_accountant, _accountantM, '/admin/properties'), '/404');
      expect(_to(_accountant, _accountantM, '/admin/bookings'), '/404');
    });

    test('reaches every /staff/* section route', () {
      for (final path in [
        '/staff/dashboard',
        '/staff/profile',
        '/staff/working-hours',
        '/staff/leave',
        '/staff/tasks',
        '/staff/schedules',
        '/staff/time-slots',
        '/staff/daily-status',
      ]) {
        expect(_to(_accountant, _accountantM, path), null, reason: path);
      }
    });
  });

  group('owner', () {
    test('super_admin reaches every /owner/* route', () {
      for (final path in [
        '/owner',
        '/owner/dashboard',
        '/owner/food-sales',
        '/owner/expenses',
        '/owner/staff-performance',
        '/owner/reports',
        '/owner/settings',
      ]) {
        expect(_to(_superAdmin, _ownerM, path), null, reason: path);
      }
    });

    test('a plain admin is redirected away from every /owner/* route '
        'except /owner/expenses', () {
      expect(_to(_admin, _adminM, '/owner'), '/404');
      expect(_to(_admin, _adminM, '/owner/dashboard'), '/404');
      expect(_to(_admin, _adminM, '/owner/settings'), '/404');
    });

    // expenses_read (0027_expenses.sql) already grants admin/accountant/
    // super_admin at the RLS level -- the accountant role exists
    // specifically to read financials (see ExpensesScreen's own doc
    // comment), so it is not just an admin exception.
    test('admin and accountant (but not staff/customer) reach '
        '/owner/expenses', () {
      expect(_to(_admin, _adminM, '/owner/expenses'), null);
      expect(_to(_accountant, _accountantM, '/owner/expenses'), null);
      expect(_to(_staff, _staffM, '/owner/expenses'), '/404');
      expect(_to(_customer, null, '/owner/expenses'), '/404');
    });

    // food_activity_sales_read/_insert (0026_food_activity_sales.sql)
    // grant staff-or-above -- any signed-in staff member logging a
    // walk-in guest's food/pool purchase needs a real destination.
    test('every staff-or-above role (but not customer) reaches '
        '/owner/food-sales', () {
      expect(_to(_admin, _adminM, '/owner/food-sales'), null);
      expect(_to(_accountant, _accountantM, '/owner/food-sales'), null);
      expect(_to(_staff, _staffM, '/owner/food-sales'), null);
      expect(_to(_customer, null, '/owner/food-sales'), '/404');
    });

    test('staff, accountant, and customer are all redirected away from '
        'every other /owner/* route', () {
      expect(_to(_staff, _staffM, '/owner'), '/404');
      expect(_to(_accountant, _accountantM, '/owner'), '/404');
      expect(_to(_customer, null, '/owner'), '/404');
    });

    test('staff at the current resort cannot reach /owner even if owner '
        'elsewhere', () {
      const staffHere =
          ResortMembership(propertyId: 'b', resortName: 'B', role: ResortRole.staff);
      const u = AppUser(id: 'u', email: 'e', memberships: [
        ResortMembership(propertyId: 'a', resortName: 'A', role: ResortRole.owner),
        staffHere,
      ]);
      expect(
          redirectFor(
              user: u, resort: staffHere, path: '/owner', onPreAuthScreen: false),
          '/404');
    });
  });

  group('customer', () {
    test('is redirected away from every /admin/* route, including the '
        'staff-or-above ones', () {
      for (final path in [
        '/admin',
        '/admin/properties',
        '/admin/dashboard',
        '/admin/reports',
        '/admin/outbox',
      ]) {
        expect(_to(_customer, null, path), '/404', reason: path);
      }
    });

    test('is redirected away from /staff and every /staff/* section route', () {
      for (final path in [
        '/staff',
        '/staff/dashboard',
        '/staff/profile',
        '/staff/working-hours',
        '/staff/leave',
        '/staff/tasks',
        '/staff/schedules',
        '/staff/time-slots',
        '/staff/daily-status',
      ]) {
        expect(_to(_customer, null, path), '/404', reason: path);
      }
    });

    test('reaches ordinary customer routes', () {
      expect(_to(_customer, null, '/'), null);
      expect(_to(_customer, null, '/bookings'), null);
    });
  });

  group('platform and choose-resort routes', () {
    test('/platform is platform-admin only', () {
      const admin = AppUser(id: 'p', email: 'e', platformRole: PlatformRole.platformAdmin);
      expect(_to(admin, null, '/platform'), null);
      expect(_to(_customer, null, '/platform'), '/404');
      expect(_to(_admin, _adminM, '/platform'), '/404');
    });

    test('/choose-resort requires 2+ memberships', () {
      const u = AppUser(id: 'u', email: 'e', memberships: [_ownerM]);
      expect(_to(u, null, '/choose-resort'), '/404');
      const twoResorts = AppUser(id: 'u2', email: 'e2', memberships: [
        ResortMembership(propertyId: 'a', resortName: 'A', role: ResortRole.owner),
        ResortMembership(propertyId: 'b', resortName: 'B', role: ResortRole.staff),
      ]);
      expect(_to(twoResorts, null, '/choose-resort'), null);
    });

    test('/owner/team requires owner', () {
      expect(_to(_superAdmin, _ownerM, '/owner/team'), null);
      expect(_to(_admin, _adminM, '/owner/team'), '/404');
    });
  });
}
