import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/router.dart';
import 'package:pasala/data/models/app_user.dart';

const _admin = AppUser(id: 'a', email: 'admin@pasala.test', role: UserRole.admin);
const _superAdmin =
    AppUser(id: 'sa', email: 'sa@pasala.test', role: UserRole.superAdmin);
const _staff = AppUser(id: 's', email: 'staff@pasala.test', role: UserRole.staff);
const _accountant =
    AppUser(id: 'ac', email: 'accountant@pasala.test', role: UserRole.accountant);
const _customer =
    AppUser(id: 'c', email: 'customer@pasala.test', role: UserRole.customer);

String? _to(AppUser? user, String path) =>
    redirectFor(user: user, path: path, onPreAuthScreen: false);

void main() {
  group('unauthenticated', () {
    test('is sent to /login for any protected path', () {
      expect(_to(null, '/'), '/login');
      expect(_to(null, '/admin/dashboard'), '/login');
    });

    test('is left on /splash, /welcome, /login, and /signup', () {
      for (final path in ['/splash', '/welcome', '/login', '/signup']) {
        expect(
          redirectFor(user: null, path: path, onPreAuthScreen: true),
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
          redirectFor(user: _customer, path: path, onPreAuthScreen: true),
          '/',
          reason: path,
        );
      }
    },
  );

  group('landingPathFor', () {
    test('customer lands on /', () {
      expect(landingPathFor(_customer), '/');
    });

    test('staff lands on /staff', () {
      expect(landingPathFor(_staff), '/staff');
    });

    test('accountant lands on /staff/dashboard', () {
      expect(landingPathFor(_accountant), '/staff/dashboard');
    });

    test('admin lands on /admin', () {
      expect(landingPathFor(_admin), '/admin');
    });

    test('super_admin lands on /owner', () {
      expect(landingPathFor(_superAdmin), '/owner');
    });
  });

  group('redirectFor sends a signed-in user hitting /login by role', () {
    String? loginRedirect(AppUser user) =>
        redirectFor(user: user, path: '/login', onPreAuthScreen: true);

    test('customer -> /', () {
      expect(loginRedirect(_customer), '/');
    });

    test('staff -> /staff', () {
      expect(loginRedirect(_staff), '/staff');
    });

    test('accountant -> /staff/dashboard', () {
      expect(loginRedirect(_accountant), '/staff/dashboard');
    });

    test('admin -> /admin', () {
      expect(loginRedirect(_admin), '/admin');
    });

    test('super_admin -> /owner', () {
      expect(loginRedirect(_superAdmin), '/owner');
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
        '/admin/users',
      ]) {
        expect(_to(_admin, path), null, reason: path);
      }
    });

    test('super_admin reaches every /admin/* route too', () {
      expect(_to(_superAdmin, '/admin/properties'), null);
      expect(_to(_superAdmin, '/admin/dashboard'), null);
    });
  });

  group('staff', () {
    test('reaches /admin/dashboard, /admin/reports and /admin/outbox', () {
      expect(_to(_staff, '/admin/dashboard'), null);
      expect(_to(_staff, '/admin/reports'), null);
      expect(_to(_staff, '/admin/outbox'), null);
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
        '/admin/users',
      ]) {
        expect(_to(_staff, path), '/404', reason: path);
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
        expect(_to(_staff, path), null, reason: path);
      }
    });
  });

  group('accountant', () {
    test('reaches /admin/dashboard, /admin/reports and /admin/outbox', () {
      expect(_to(_accountant, '/admin/dashboard'), null);
      expect(_to(_accountant, '/admin/reports'), null);
      expect(_to(_accountant, '/admin/outbox'), null);
    });

    test('is redirected away from admin-only management routes', () {
      expect(_to(_accountant, '/admin/properties'), '/404');
      expect(_to(_accountant, '/admin/bookings'), '/404');
      expect(_to(_accountant, '/admin/users'), '/404');
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
        expect(_to(_accountant, path), null, reason: path);
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
        expect(_to(_superAdmin, path), null, reason: path);
      }
    });

    test('a plain admin is redirected away from every /owner/* route', () {
      expect(_to(_admin, '/owner'), '/404');
      expect(_to(_admin, '/owner/dashboard'), '/404');
      expect(_to(_admin, '/owner/settings'), '/404');
    });

    test('staff, accountant, and customer are all redirected away too', () {
      expect(_to(_staff, '/owner'), '/404');
      expect(_to(_accountant, '/owner'), '/404');
      expect(_to(_customer, '/owner'), '/404');
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
        '/admin/users',
      ]) {
        expect(_to(_customer, path), '/404', reason: path);
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
        expect(_to(_customer, path), '/404', reason: path);
      }
    });

    test('reaches ordinary customer routes', () {
      expect(_to(_customer, '/'), null);
      expect(_to(_customer, '/bookings'), null);
    });
  });
}
