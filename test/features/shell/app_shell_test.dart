import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pasala/core/current_resort.dart';
import 'package:pasala/core/widgets/brand_mark.dart';
import 'package:pasala/data/models/app_user.dart';
import 'package:pasala/data/models/resort_membership.dart';
import 'package:pasala/data/repositories/auth_repository.dart';
import 'package:pasala/features/shell/app_shell.dart';

const _adminM =
    ResortMembership(propertyId: 'r1', resortName: 'R1', role: ResortRole.admin);
const _staffM =
    ResortMembership(propertyId: 'r1', resortName: 'R1', role: ResortRole.staff);
const _accountantM = ResortMembership(
    propertyId: 'r1', resortName: 'R1', role: ResortRole.accountant);
const _ownerM =
    ResortMembership(propertyId: 'r1', resortName: 'R1', role: ResortRole.owner);

const _admin =
    AppUser(id: 'admin-id', email: 'admin@pasala.test', memberships: [_adminM]);

const _customer = AppUser(id: 'customer-id', email: 'ravi@example.com');

const _staff =
    AppUser(id: 'staff-id', email: 'staff@pasala.test', memberships: [_staffM]);

const _accountant = AppUser(
    id: 'accountant-id',
    email: 'accounts@pasala.test',
    memberships: [_accountantM]);

const _owner =
    AppUser(id: 'owner-id', email: 'super@pasala.test', memberships: [_ownerM]);

/// Test-only [CurrentResort] that always resolves to a fixed value,
/// mirroring how every other provider here is overridden with a fixture
/// instead of exercising the real (SharedPreferences-backed) notifier.
class _FixedResort extends CurrentResort {
  _FixedResort(this._value);
  final ResortMembership? _value;
  @override
  ResortMembership? build() => _value;
}

Widget _appFor(AppUser user) {
  final resort = user.memberships.isEmpty ? null : user.memberships.first;
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      ShellRoute(
        builder: (_, _, child) => AppShell(child: child),
        routes: [
          GoRoute(path: '/', builder: (_, _) => const SizedBox()),
          GoRoute(path: '/admin', builder: (_, _) => const SizedBox()),
          GoRoute(path: '/admin/bookings', builder: (_, _) => const SizedBox()),
          GoRoute(path: '/admin/more', builder: (_, _) => const SizedBox()),
        ],
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      // Override rather than hitting Supabase: this proves the shell reads
      // role off currentUserProvider/currentResortProvider without any
      // network dependency.
      currentUserProvider.overrideWith((ref) => Stream.value(user)),
      currentResortProvider.overrideWith(() => _FixedResort(resort)),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  testWidgets('shows the Dashboard, Bookings, and More destinations for '
      'an admin user', (tester) async {
    await tester.pumpWidget(_appFor(_admin));
    await tester.pumpAndSettle();

    expect(find.text('Dashboard'), findsOneWidget);
    expect(find.text('Bookings'), findsOneWidget);
    expect(find.text('More'), findsOneWidget);
    // Browse (the customer shopping flow) is not admin work.
    expect(find.text('Browse'), findsNothing);
  });

  testWidgets(
      'an admin sees a notifications bell, an "Admin" label, and a profile '
      'avatar in the app bar instead of a bare sign-out icon', (
    tester,
  ) async {
    await tester.pumpWidget(_appFor(_admin));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.notifications_outlined), findsOneWidget);
    expect(find.text('Admin'), findsOneWidget);
    expect(find.byIcon(Icons.person), findsOneWidget);
    // No bare logout icon directly in the app bar -- sign out now lives
    // behind the profile avatar's account sheet instead.
    expect(find.byIcon(Icons.logout), findsNothing);
  });

  testWidgets(
      "tapping an admin's profile avatar opens the account sheet with their "
      'email, role, and a sign-out action', (tester) async {
    await tester.pumpWidget(_appFor(_admin));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.person));
    await tester.pumpAndSettle();

    expect(find.text('admin@pasala.test'), findsWidgets);
    // "Admin" now appears twice: once in the app bar label (behind the
    // sheet), once as the sheet's own role line.
    expect(find.text('Admin'), findsNWidgets(2));
    expect(find.byKey(const Key('account-sheet-sign-out')), findsOneWidget);
  });

  // The admin account has no bookings of its own -- its "Bookings" tab
  // must open the admin's all-reservations list (`/admin/bookings`), never
  // the customer-facing `/bookings` (`MyBookingsScreen`), which would
  // always render an empty "No bookings yet" state for that account.
  testWidgets(
      "an admin's Bookings destination opens /admin/bookings, not /bookings",
      (tester) async {
    await tester.pumpWidget(_appFor(_admin));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Bookings'));
    await tester.pumpAndSettle();

    final router = GoRouter.of(tester.element(find.text('Bookings')));
    expect(router.routerDelegate.currentConfiguration.uri.path,
        '/admin/bookings');
  });

  // super_admin has the same always-empty `/bookings` problem as admin.
  testWidgets(
      "an owner's Bookings destination opens /admin/bookings, not /bookings",
      (tester) async {
    await tester.pumpWidget(_appFor(_owner));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Bookings'));
    await tester.pumpAndSettle();

    final router = GoRouter.of(tester.element(find.text('Bookings')));
    expect(router.routerDelegate.currentConfiguration.uri.path,
        '/admin/bookings');
  });

  testWidgets('does not show the admin-only More destination for a customer',
      (tester) async {
    await tester.pumpWidget(_appFor(_customer));
    await tester.pumpAndSettle();

    expect(find.text('More'), findsNothing);
  });

  // Carried-forward fix: staff and accountant can reach `report_revenue`,
  // `report_occupancy`, and `dashboard_summary` (all explicitly permit
  // staff-or-above), and the router now allows `/admin/dashboard` and
  // `/admin/reports` for them -- but a route being reachable is useless
  // without a way to navigate to it. Both roles share `_staffDestinations`.
  testWidgets('shows Dashboard and Reports destinations for staff', (
    tester,
  ) async {
    await tester.pumpWidget(_appFor(_staff));
    await tester.pumpAndSettle();

    expect(find.text('Dashboard'), findsOneWidget);
    expect(find.text('Reports'), findsOneWidget);
    expect(find.text('More'), findsNothing);
  });

  testWidgets('shows Dashboard and Reports destinations for an accountant', (
    tester,
  ) async {
    await tester.pumpWidget(_appFor(_accountant));
    await tester.pumpAndSettle();

    expect(find.text('Dashboard'), findsOneWidget);
    expect(find.text('Reports'), findsOneWidget);
    expect(find.text('More'), findsNothing);
  });

  // Staff/accountant work entirely within their own tools now -- Browse is
  // the customer holiday-shopping flow, which is not one of them.
  testWidgets('does not show the Browse destination for staff', (
    tester,
  ) async {
    await tester.pumpWidget(_appFor(_staff));
    await tester.pumpAndSettle();

    expect(find.text('Browse'), findsNothing);
  });

  testWidgets('does not show the Browse destination for an accountant', (
    tester,
  ) async {
    await tester.pumpWidget(_appFor(_accountant));
    await tester.pumpAndSettle();

    expect(find.text('Browse'), findsNothing);
  });

  testWidgets('shows the brand mark in the app bar', (tester) async {
    await tester.pumpWidget(_appFor(_customer));
    await tester.pumpAndSettle();

    expect(find.byType(BrandMark), findsOneWidget);
  });
}
