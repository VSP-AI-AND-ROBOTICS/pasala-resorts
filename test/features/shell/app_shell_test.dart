import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
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
}
