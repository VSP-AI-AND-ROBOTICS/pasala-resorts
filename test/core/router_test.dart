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
    redirectFor(user: user, path: path, loggingIn: false);

void main() {
  group('unauthenticated', () {
    test('is sent to /login for any protected path', () {
      expect(_to(null, '/'), '/login');
      expect(_to(null, '/admin/dashboard'), '/login');
    });

    test('is left on /login and /signup', () {
      expect(redirectFor(user: null, path: '/login', loggingIn: true), null);
      expect(redirectFor(user: null, path: '/signup', loggingIn: true), null);
    });
  });

  test('a signed-in user hitting /login or /signup is sent home', () {
    expect(redirectFor(user: _customer, path: '/login', loggingIn: true), '/');
  });

  group('admin', () {
    test('reaches every /admin/* route', () {
      for (final path in [
        '/admin',
        '/admin/properties',
        '/admin/units/u1',
        '/admin/rates/u1',
        '/admin/block/u1',
        '/admin/bookings',
        '/admin/dashboard',
        '/admin/reports',
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
    test('reaches /admin/dashboard and /admin/reports', () {
      expect(_to(_staff, '/admin/dashboard'), null);
      expect(_to(_staff, '/admin/reports'), null);
    });

    test('is redirected away from admin-only management routes', () {
      for (final path in [
        '/admin',
        '/admin/properties',
        '/admin/units/u1',
        '/admin/rates/u1',
        '/admin/block/u1',
        '/admin/bookings',
      ]) {
        expect(_to(_staff, path), '/404', reason: path);
      }
    });

    test('reaches /staff', () {
      expect(_to(_staff, '/staff'), null);
    });
  });

  group('accountant', () {
    test('reaches /admin/dashboard and /admin/reports', () {
      expect(_to(_accountant, '/admin/dashboard'), null);
      expect(_to(_accountant, '/admin/reports'), null);
    });

    test('is redirected away from admin-only management routes', () {
      expect(_to(_accountant, '/admin/properties'), '/404');
      expect(_to(_accountant, '/admin/bookings'), '/404');
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
      ]) {
        expect(_to(_customer, path), '/404', reason: path);
      }
    });

    test('is redirected away from /staff', () {
      expect(_to(_customer, '/staff'), '/404');
    });

    test('reaches ordinary customer routes', () {
      expect(_to(_customer, '/'), null);
      expect(_to(_customer, '/bookings'), null);
    });
  });
}
