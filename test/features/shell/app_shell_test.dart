import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pasala/core/widgets/brand_mark.dart';
import 'package:pasala/data/models/app_user.dart';
import 'package:pasala/data/repositories/auth_repository.dart';
import 'package:pasala/features/shell/app_shell.dart';

const _admin = AppUser(
  id: 'admin-id',
  email: 'admin@pasala.test',
  role: UserRole.admin,
);

const _customer = AppUser(
  id: 'customer-id',
  email: 'ravi@example.com',
  role: UserRole.customer,
);

const _staff = AppUser(
  id: 'staff-id',
  email: 'staff@pasala.test',
  role: UserRole.staff,
);

const _accountant = AppUser(
  id: 'accountant-id',
  email: 'accounts@pasala.test',
  role: UserRole.accountant,
);

Widget _appFor(AppUser user) {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      ShellRoute(
        builder: (_, _, child) => AppShell(child: child),
        routes: [
          GoRoute(path: '/', builder: (_, _) => const SizedBox()),
        ],
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      // Override rather than hitting Supabase: this proves the shell reads
      // role off currentUserProvider without any network dependency.
      currentUserProvider.overrideWith((ref) => Stream.value(user)),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  testWidgets('shows the Admin destination for an admin user', (
    tester,
  ) async {
    await tester.pumpWidget(_appFor(_admin));
    await tester.pumpAndSettle();

    expect(find.text('Admin'), findsOneWidget);
  });

  testWidgets('does not show the Admin destination for a customer', (
    tester,
  ) async {
    await tester.pumpWidget(_appFor(_customer));
    await tester.pumpAndSettle();

    expect(find.text('Admin'), findsNothing);
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
    expect(find.text('Admin'), findsNothing);
  });

  testWidgets('shows Dashboard and Reports destinations for an accountant', (
    tester,
  ) async {
    await tester.pumpWidget(_appFor(_accountant));
    await tester.pumpAndSettle();

    expect(find.text('Dashboard'), findsOneWidget);
    expect(find.text('Reports'), findsOneWidget);
    expect(find.text('Admin'), findsNothing);
  });

  testWidgets('shows the brand mark in the app bar', (tester) async {
    await tester.pumpWidget(_appFor(_customer));
    await tester.pumpAndSettle();

    expect(find.byType(BrandMark), findsOneWidget);
  });
}
