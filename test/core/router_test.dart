import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pasala/core/current_resort.dart';
import 'package:pasala/core/router.dart';
import 'package:pasala/data/models/app_user.dart';
import 'package:pasala/data/models/current_charges.dart';
import 'package:pasala/data/models/resort_membership.dart';
import 'package:pasala/data/repositories/auth_repository.dart';
import 'package:pasala/data/repositories/stay_repository.dart';
import 'package:pasala/features/stay/checkout_screen.dart';
import 'package:pasala/core/supabase_client.dart';
import 'package:pasala/core/widgets/failure_view.dart';
import 'package:pasala/core/errors.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

Iterable<String> _paths(List<RouteBase> routes) sync* {
  for (final route in routes) {
    if (route is GoRoute) yield route.path;
    yield* _paths(route.routes);
  }
}

class _NoResort extends CurrentResort {
  @override
  ResortMembership? build() => null;
}

class _StaffResort extends CurrentResort {
  @override
  ResortMembership? build() => _staffM;
}

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

    test('accountant lands on /finance', () {
      expect(landingPathFor(_accountant, _accountantM), '/finance');
    });

    test('admin lands on /admin', () {
      expect(landingPathFor(_admin, _adminM), '/admin');
    });

    test('super_admin lands on /owner', () {
      expect(landingPathFor(_superAdmin, _ownerM), '/owner');
    });

    test('owner lands on /owner, staff on /staff, accountant on /finance', () {
      for (final (role, path) in [
        (ResortRole.owner, '/owner'),
        (ResortRole.admin, '/admin'),
        (ResortRole.staff, '/staff'),
        (ResortRole.accountant, '/finance'),
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

    test('accountant -> /finance', () {
      expect(loginRedirect(_accountant, _accountantM), '/finance');
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
        '/admin/units/r1',
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

    // Final review I2: the property id in the URL must be the current
    // resort's -- another resort's id is not found, not trusted.
    test("/admin/units/:propertyId only opens the current resort's units", () {
      expect(_to(_admin, _adminM, '/admin/units/r1'), null);
      expect(_to(_admin, _adminM, '/admin/units/other-resort'), '/404');
      expect(_to(_superAdmin, _ownerM, '/admin/units/other-resort'), '/404');
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
      expect(_to(_staff, _staffM, '/admin/check-out/res-1'), null);
    });

    test('is redirected away from admin-only management routes', () {
      for (final path in [
        '/admin',
        '/admin/properties',
        '/admin/units/r1',
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
      expect(_to(_accountant, _accountantM, '/admin/check-out/res-1'), null);
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

    test('/choose-resort moves on once a resort is picked', () {
      const staffAtB = ResortMembership(
          propertyId: 'b', resortName: 'B', role: ResortRole.staff);
      const twoResorts = AppUser(id: 'u2', email: 'e2', memberships: [
        ResortMembership(propertyId: 'a', resortName: 'A', role: ResortRole.owner),
        staffAtB,
      ]);
      // The chooser never navigates itself: picking only sets the resort.
      expect(_to(twoResorts, staffAtB, '/choose-resort'), '/staff');
      expect(_to(twoResorts, staffAtB, '/choose-resort'),
          landingPathFor(twoResorts, staffAtB));
    });

    test('/owner/team requires owner', () {
      expect(_to(_superAdmin, _ownerM, '/owner/team'), null);
      expect(_to(_admin, _adminM, '/owner/team'), '/404');
    });
  });

  group('room status grid', () {
    test('the app router registers /staff/rooms', () {
      TestWidgetsFlutterBinding.ensureInitialized();
      final container = ProviderContainer(overrides: [
        currentUserProvider.overrideWith((ref) => Stream.value(null)),
        currentResortProvider.overrideWith(_NoResort.new),
      ]);
      addTearDown(container.dispose);

      final router = container.read(routerProvider);

      expect(_paths(router.configuration.routes), contains('/staff/rooms'));
    });

    test('/staff/rooms opens for every role at the current resort', () {
      expect(_to(_superAdmin, _ownerM, '/staff/rooms'), null);
      expect(_to(_admin, _adminM, '/staff/rooms'), null);
      expect(_to(_staff, _staffM, '/staff/rooms'), null);
      expect(_to(_accountant, _accountantM, '/staff/rooms'), null);
    });

    test('/staff/rooms is closed to customers', () {
      expect(_to(_customer, null, '/staff/rooms'), '/404');
    });
  });

  group('coupons', () {
    test('the app router registers /admin/coupons', () {
      TestWidgetsFlutterBinding.ensureInitialized();
      final container = ProviderContainer(overrides: [
        currentUserProvider.overrideWith((ref) => Stream.value(null)),
        currentResortProvider.overrideWith(_NoResort.new),
      ]);
      addTearDown(container.dispose);

      final router = container.read(routerProvider);

      expect(_paths(router.configuration.routes), contains('/admin/coupons'));
    });

    test('/admin/coupons opens for owners and admins only', () {
      expect(_to(_superAdmin, _ownerM, '/admin/coupons'), null);
      expect(_to(_admin, _adminM, '/admin/coupons'), null);
      expect(_to(_staff, _staffM, '/admin/coupons'), '/404');
      expect(_to(_accountant, _accountantM, '/admin/coupons'), '/404');
      expect(_to(_customer, null, '/admin/coupons'), '/404');
    });
  });

  group('finance', () {
    test('owner, admin and accountant open /finance', () {
      expect(_to(_superAdmin, _ownerM, '/finance'), null);
      expect(_to(_admin, _adminM, '/finance'), null);
      expect(_to(_accountant, _accountantM, '/finance'), null);
    });

    test('staff and customers are refused /finance', () {
      expect(_to(_staff, _staffM, '/finance'), '/404');
      expect(_to(_customer, null, '/finance'), '/404');
    });

    test('two memberships and no pick go to /choose-resort first', () {
      const u = AppUser(id: 'u', email: 'e', memberships: [
        ResortMembership(propertyId: 'a', resortName: 'A', role: ResortRole.accountant),
        ResortMembership(propertyId: 'b', resortName: 'B', role: ResortRole.staff),
      ]);
      expect(_to(u, null, '/finance'), '/choose-resort');
    });

    test('an accountant who picked a resort they are only staff at is refused', () {
      const u = AppUser(id: 'u', email: 'e', memberships: [
        ResortMembership(propertyId: 'a', resortName: 'A', role: ResortRole.accountant),
        ResortMembership(propertyId: 'b', resortName: 'B', role: ResortRole.staff),
      ]);
      expect(_to(u, u.memberships.last, '/finance'), '/404');
      expect(_to(u, u.memberships.first, '/finance'), null);
    });

    test('the app router registers /finance', () {
      TestWidgetsFlutterBinding.ensureInitialized();
      final container = ProviderContainer(overrides: [
        currentUserProvider.overrideWith((ref) => Stream.value(null)),
        currentResortProvider.overrideWith(_NoResort.new),
      ]);
      addTearDown(container.dispose);

      final router = container.read(routerProvider);

      expect(_paths(router.configuration.routes), contains('/finance'));
    });
  });

  group('desk checkout', () {
    test('customers are refused /admin/check-out/:reservationId', () {
      expect(_to(_customer, null, '/admin/check-out/res-1'), '/404');
    });

    // A web refresh or back/forward rebuilds the page from the URL alone:
    // no route `extra` survives it, so the reservation id and desk mode
    // must both live in the path.
    testWidgets('builds the desk checkout from the URL alone', (tester) async {
      final container = ProviderContainer(overrides: [
        currentUserProvider.overrideWith((ref) => Stream.value(_staff)),
        currentResortProvider.overrideWith(_StaffResort.new),
        currentChargesProvider.overrideWith((ref, id) async => const CurrentCharges(
              stayAmount: 3000,
              foodAmount: 0,
              activityAmount: 0,
              total: 3000,
              paid: 1000,
              balance: 2000,
            )),
      ]);
      addTearDown(container.dispose);
      // Riverpod 3 auto-disposes an unlistened provider before its stream
      // emits; keep the signed-in user alive, as the widget tree would.
      container.listen(currentUserProvider, (_, _) {});
      await container.read(currentUserProvider.future);
      final router = container.read(routerProvider);

      // Straight to the URL, as a reload does -- no splash, no `extra`.
      router.go('/admin/check-out/res-1');
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      final screen = tester.widget<CheckoutScreen>(find.byType(CheckoutScreen));
      expect(screen.reservationId, 'res-1');
      expect(screen.desk, isTrue);
    });
  });

  // E2E bug (e2e/tests/frontdesk.spec.ts): reloading the desk checkout
  // landed on the user's landing page instead of the checkout.
  group('reload / cold start', () {
    test('keeps one GoRouter while the signed-in user and resort change',
        () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final users = StreamController<AppUser?>();
      addTearDown(users.close);
      final container = ProviderContainer(overrides: [
        currentUserProvider.overrideWith((ref) => users.stream),
        currentResortProvider.overrideWith(_StaffResort.new),
      ]);
      addTearDown(container.dispose);

      // Listened, as MaterialApp.router's `ref.watch` would.
      container.listen(currentUserProvider, (_, _) {});
      final first = container.listen(routerProvider, (_, _) {}).read();
      users.add(_staff);
      await container.read(currentUserProvider.future);
      users.add(const AppUser(id: 's', email: 'staff@pasala.test', memberships: [_staffM]));
      await pumpEventQueue();

      // A fresh GoRouter restarts at its initialLocation (/splash), which
      // sends a signed-in user to their landing page -- losing the page.
      expect(container.read(routerProvider), same(first));
    });

    testWidgets(
        'a cold start at /admin/check-out/:id lands there once the session '
        'has loaded', (tester) async {
      final users = StreamController<AppUser?>();
      addTearDown(users.close);
      final container = ProviderContainer(overrides: [
        currentUserProvider.overrideWith((ref) => users.stream),
        currentResortProvider.overrideWith(_StaffResort.new),
        currentChargesProvider.overrideWith((ref, id) async => const CurrentCharges(
              stayAmount: 3000,
              foodAmount: 0,
              activityAmount: 0,
              total: 3000,
              paid: 1000,
              balance: 2000,
            )),
      ]);
      addTearDown(container.dispose);

      // A reload: the browser URL is the app's first route, and the stored
      // session has not been read yet (the user stream has not emitted).
      tester.platformDispatcher.defaultRouteNameTestValue =
          '/admin/check-out/res-1';
      addTearDown(tester.platformDispatcher.clearDefaultRouteNameTestValue);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: Consumer(
          builder: (_, ref, _) =>
              MaterialApp.router(routerConfig: ref.watch(routerProvider)),
        ),
      ));
      await tester.pump();
      // Flutter web answers defaultRouteName from the URL only until the
      // app's first navigation, then '/' (the engine resets it).
      tester.platformDispatcher.defaultRouteNameTestValue = '/';

      users.add(_staff);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      final router = container.read(routerProvider);
      final url = router.routeInformationParser
          .restoreRouteInformation(router.routerDelegate.currentConfiguration)!
          .uri;
      expect(url.path, '/admin/check-out/res-1');
      final screen = tester.widget<CheckoutScreen>(find.byType(CheckoutScreen));
      expect(screen.reservationId, 'res-1');
      expect(screen.desk, isTrue);
    });

    // E2E (frontdesk.spec.ts, on the web build): when the session loads,
    // the user AND the resort both change, so the router is refreshed
    // twice. The first refresh's redirect handed back the held location
    // and forgot it; the second, still on /splash, then sent the user to
    // their landing page (/admin) instead.
    testWidgets(
        'a cold start at /admin/check-out/:id still lands there when the '
        'resort resolves along with the user (two refreshes)', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final users = StreamController<AppUser?>();
      addTearDown(users.close);
      final container = ProviderContainer(overrides: [
        currentUserProvider.overrideWith((ref) => users.stream),
        // The real CurrentResort: null until the user loads, then the
        // user's one membership -- a second router refresh.
        currentChargesProvider.overrideWith((ref, id) async => const CurrentCharges(
              stayAmount: 3000,
              foodAmount: 0,
              activityAmount: 0,
              total: 3000,
              paid: 1000,
              balance: 2000,
            )),
      ]);
      addTearDown(container.dispose);

      tester.platformDispatcher.defaultRouteNameTestValue =
          '/admin/check-out/res-1';
      addTearDown(tester.platformDispatcher.clearDefaultRouteNameTestValue);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: Consumer(
          builder: (_, ref, _) =>
              MaterialApp.router(routerConfig: ref.watch(routerProvider)),
        ),
      ));
      await tester.pump();
      tester.platformDispatcher.defaultRouteNameTestValue = '/';

      users.add(_staff);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      // Past the splash's own 1.5s auto-advance, in case it is still up.
      await tester.pump(const Duration(seconds: 2));

      final router = container.read(routerProvider);
      expect(router.routerDelegate.currentConfiguration.uri.path,
          '/admin/check-out/res-1');
      final screen = tester.widget<CheckoutScreen>(find.byType(CheckoutScreen));
      expect(screen.reservationId, 'res-1');
      expect(screen.desk, isTrue);
    });

    testWidgets(
        'a signed-out cold start at a protected path never shows it: splash '
        'then welcome', (tester) async {
      final users = StreamController<AppUser?>();
      addTearDown(users.close);
      final container = ProviderContainer(overrides: [
        currentUserProvider.overrideWith((ref) => users.stream),
        currentResortProvider.overrideWith(_NoResort.new),
      ]);
      addTearDown(container.dispose);

      tester.platformDispatcher.defaultRouteNameTestValue =
          '/admin/check-out/res-1';
      addTearDown(tester.platformDispatcher.clearDefaultRouteNameTestValue);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: Consumer(
          builder: (_, ref, _) =>
              MaterialApp.router(routerConfig: ref.watch(routerProvider)),
        ),
      ));
      await tester.pump();
      tester.platformDispatcher.defaultRouteNameTestValue = '/';

      users.add(null);
      await tester.pump();
      expect(find.byType(CheckoutScreen), findsNothing);
      // The splash auto-advances to /welcome after 1.5s.
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(seconds: 1));

      final router = container.read(routerProvider);
      expect(router.routerDelegate.currentConfiguration.uri.path, '/welcome');
      expect(find.byType(CheckoutScreen), findsNothing);
    });
  });

  // Review of the single-GoRouter change: the router is no longer rebuilt
  // when the user or resort changes, so every flow that relied on a rebuild
  // sending the user to `landingPathFor` must still get there -- and the
  // page being left must not be rebuilt against a resort it no longer has
  // (many screens read `ref.watch(currentResortProvider)!`).
  group('resort changes still land (routerProvider)', () {
    testWidgets(
        'picking a resort on /choose-resort moves a 2-resort user to that '
        "resort's landing page", (tester) async {
      const user = AppUser(
          id: 'u', email: 'u@pasala.test', memberships: [_pickA, _pickB]);
      final app = await _pumpApp(tester, () => user);
      expect(_pathOf(app.router), '/choose-resort');

      await tester.tap(find.byKey(const Key('choose-resort-b')));
      await _settle(tester);

      expect(_pathOf(app.router), landingPathFor(user, _pickB));
      expect(_pathOf(app.router), '/staff');
      await _tearDownApp(tester);
    });

    testWidgets(
        'a remembered pick that loads after the user moves them off '
        '/choose-resort', (tester) async {
      const user = AppUser(
          id: 'u', email: 'u@pasala.test', memberships: [_pickA, _pickB]);
      final app = await _pumpApp(tester, () => user);
      expect(_pathOf(app.router), '/choose-resort');

      // As if shared_preferences answered after the user fetch.
      unawaited(app.container.read(currentResortProvider.notifier).select('a'));
      await _settle(tester);

      expect(_pathOf(app.router), '/owner');
      await _tearDownApp(tester);
    });

    testWidgets(
        'switching to a resort with a different role lands there, even when '
        'the stored pick takes frames to save', (tester) async {
      const user = AppUser(
          id: 'u', email: 'u@pasala.test', memberships: [_pickA, _adminAtB]);
      final app = await _pumpApp(
        tester,
        () => user,
        prefs: {'current_resort_id': 'a'},
        // Slower than the page transition: the switcher's page (/owner,
        // which an admin may not open) is gone before the write lands.
        prefsDelay: const Duration(seconds: 2),
      );
      expect(_pathOf(app.router), '/owner');

      await tester.tap(find.byKey(const Key('resort-switcher')));
      await _settle(tester);
      await tester.tap(find.byKey(const Key('resort-switcher-b')));
      await _settle(tester);

      expect(app.container.read(currentResortProvider), _adminAtB);
      expect(_pathOf(app.router), '/admin');
      await _tearDownApp(tester);
    });

    testWidgets(
        'losing access to the only resort lands on the landing page for '
        'the re-fetched user, not /404', (tester) async {
      AppUser user = const AppUser(
          id: 'u', email: 'u@pasala.test', memberships: [_adminAtB]);
      final app = await _pumpApp(tester, () => user);
      app.router.go('/admin/outbox');
      await _settle(tester);
      expect(_pathOf(app.router), '/admin/outbox');

      // The server no longer lists the membership, and a screen shows the
      // NotAMember failure it got back.
      user = const AppUser(id: 'u', email: 'u@pasala.test');
      app.overlay.value = const FailureView(error: NotAMember());
      await _settle(tester);

      expect(app.container.read(currentResortProvider), isNull);
      expect(_pathOf(app.router), '/');
      await _tearDownApp(tester);
    });

    testWidgets(
        'losing access to one of three resorts lands on /choose-resort',
        (tester) async {
      const c = ResortMembership(
          propertyId: 'c', resortName: 'C', role: ResortRole.staff);
      AppUser user = const AppUser(
          id: 'u', email: 'u@pasala.test', memberships: [_pickA, _adminAtB, c]);
      final app = await _pumpApp(tester, () => user,
          prefs: {'current_resort_id': 'b'});
      expect(_pathOf(app.router), '/admin');

      user = const AppUser(
          id: 'u', email: 'u@pasala.test', memberships: [_pickA, c]);
      app.overlay.value = const FailureView(error: NotAMember());
      await _settle(tester);

      expect(app.container.read(currentResortProvider), isNull);
      expect(_pathOf(app.router), '/choose-resort');
      await _tearDownApp(tester);
    });

    testWidgets('signing out from a resort screen lands on /login',
        (tester) async {
      AppUser? user = const AppUser(
          id: 'u', email: 'u@pasala.test', memberships: [_adminAtB]);
      final app = await _pumpApp(tester, () => user);
      app.router.go('/admin/outbox');
      await _settle(tester);
      expect(_pathOf(app.router), '/admin/outbox');

      // The auth stream reports the session gone.
      user = null;
      app.container.invalidate(currentUserProvider);
      await _settle(tester);

      expect(_pathOf(app.router), '/login');
      await _tearDownApp(tester);
    });
  });
}

// Used by the 'resort changes still land' group.
const _pickA =
    ResortMembership(propertyId: 'a', resortName: 'A', role: ResortRole.owner);
const _pickB =
    ResortMembership(propertyId: 'b', resortName: 'B', role: ResortRole.staff);
const _adminAtB =
    ResortMembership(propertyId: 'b', resortName: 'B', role: ResortRole.admin);

/// `shared_preferences` whose writes take [delay] to land, like a real
/// platform channel -- frames run before the write's future completes.
class _SlowPrefsStore extends InMemorySharedPreferencesStore {
  _SlowPrefsStore(super.data, this.delay) : super.withData();

  final Duration delay;

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    return super.setValue(valueType, key, value);
  }

  @override
  Future<bool> remove(String key) async {
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    return super.remove(key);
  }
}


typedef _App = ({
  ProviderContainer container,
  GoRouter router,
  ValueNotifier<Widget?> overlay,
});

/// The real app: `routerProvider` inside `MaterialApp.router`, the real
/// `CurrentResort`, and a user stream that re-reads [user] on every
/// (re)subscription, so an `invalidate` re-fetches whatever [user] is now.
/// `overlay` mounts a widget over the current page (e.g. the `FailureView`
/// a screen shows). The landing screens' Supabase calls fail fast (tests
/// answer every HTTP request with a 400); only the router's location is
/// asserted.
Future<_App> _pumpApp(
  WidgetTester tester,
  AppUser? Function() user, {
  Map<String, Object> prefs = const {},
  Duration prefsDelay = Duration.zero,
}) async {
  SharedPreferences.setMockInitialValues({});
  SharedPreferencesStorePlatform.instance = _SlowPrefsStore(
      {for (final e in prefs.entries) 'flutter.${e.key}': e.value},
      prefsDelay);
  final container = ProviderContainer(
    overrides: [
      currentUserProvider.overrideWith((ref) => Stream.value(user())),
      supabaseProvider.overrideWithValue(SupabaseClient(
        'http://localhost:54321',
        'test-anon-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      )),
    ],
    retry: (_, _) => null,
  );
  addTearDown(container.dispose);
  final overlay = ValueNotifier<Widget?>(null);
  addTearDown(overlay.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: Consumer(builder: (_, ref, _) {
      final router = ref.watch(routerProvider);
      return MaterialApp.router(
        routerConfig: router,
        builder: (_, child) => Stack(children: [
          child!,
          // Under the router, as a page's own FailureView would be.
          InheritedGoRouter(
            goRouter: router,
            child: ValueListenableBuilder<Widget?>(
              valueListenable: overlay,
              builder: (_, widget, _) => widget == null
                  ? const SizedBox.shrink()
                  : Material(type: MaterialType.transparency, child: widget),
            ),
          ),
        ]),
      );
    }),
  ));
  await _settle(tester);
  return (
    container: container,
    router: container.read(routerProvider),
    overlay: overlay,
  );
}

/// Unmounts the app and lets in-flight timers (page transitions, the
/// splash delay) finish before the test's invariants are checked.
Future<void> _tearDownApp(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await _settle(tester);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 500));
  }
}

String _pathOf(GoRouter router) =>
    router.routerDelegate.currentConfiguration.uri.path;
