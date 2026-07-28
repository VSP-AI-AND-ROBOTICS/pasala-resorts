import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/repositories/auth_repository.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/signup_screen.dart';
import '../features/shell/app_shell.dart';
import '../features/shell/not_found_screen.dart';

/// Route guarding is user experience only. RLS in Postgres is what actually
/// enforces access; a customer who forges a route sees a not-found page and
/// would get 42501 from the database regardless.
final routerProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(currentUserProvider);

  return GoRouter(
    initialLocation: '/',
    redirect: (context, state) {
      final user = auth.value;
      final loggingIn =
          state.matchedLocation == '/login' || state.matchedLocation == '/signup';

      if (user == null) return loggingIn ? null : '/login';
      if (loggingIn) return '/';

      final path = state.matchedLocation;
      if (path.startsWith('/admin') && !user.isAdmin) return '/404';
      if (path.startsWith('/staff') && !user.isStaffOrAbove) return '/404';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/signup', builder: (_, _) => const SignupScreen()),
      GoRoute(path: '/404', builder: (_, _) => const NotFoundScreen()),
      ShellRoute(
        builder: (_, _, child) => AppShell(child: child),
        routes: [
          // TODO(Task 14): replace this placeholder with the browse screen.
          // An empty `routes: []` list on ShellRoute has no matchable child,
          // so `/` (the initialLocation) fails to resolve. This placeholder
          // keeps the shell reachable until Task 14 adds the real screen.
          GoRoute(
            path: '/',
            builder: (_, _) => const Center(child: Text('Pasala')),
          ),
        ],
      ),
    ],
    errorBuilder: (_, _) => const NotFoundScreen(),
  );
});
