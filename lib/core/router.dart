import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/repositories/auth_repository.dart';
import '../features/account/booking_detail_screen.dart';
import '../features/account/my_bookings_screen.dart';
import '../features/admin/admin_bookings_screen.dart';
import '../features/admin/admin_home_screen.dart';
import '../features/admin/block_dates_screen.dart';
import '../features/admin/property_form_screen.dart';
import '../features/admin/rate_rules_screen.dart';
import '../features/admin/units_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/signup_screen.dart';
import '../features/booking/booking_screen.dart';
import '../features/booking/confirmation_screen.dart';
import '../features/browse/browse_screen.dart';
import '../features/browse/property_screen.dart';
import '../features/shell/app_shell.dart';
import '../features/shell/not_found_screen.dart';
import '../features/staff/today_screen.dart';

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
          GoRoute(path: '/', builder: (_, _) => const BrowseScreen()),
          GoRoute(
            path: '/property/:id',
            builder: (_, state) =>
                PropertyScreen(propertyId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: '/book/:unitId',
            builder: (_, state) =>
                BookingScreen(unitId: state.pathParameters['unitId']!),
          ),
          GoRoute(
            path: '/booking/:id',
            builder: (_, state) =>
                ConfirmationScreen(reservationId: state.pathParameters['id']!),
          ),
          GoRoute(path: '/bookings', builder: (_, _) => const MyBookingsScreen()),
          GoRoute(
            path: '/booking-detail/:id',
            builder: (_, state) =>
                BookingDetailScreen(reservationId: state.pathParameters['id']!),
          ),
          GoRoute(path: '/admin', builder: (_, _) => const AdminHomeScreen()),
          GoRoute(
            path: '/admin/properties',
            builder: (_, _) => const AdminPropertiesScreen(),
          ),
          GoRoute(
            path: '/admin/units/:propertyId',
            builder: (_, state) =>
                UnitsScreen(propertyId: state.pathParameters['propertyId']!),
          ),
          GoRoute(
            path: '/admin/rates/:unitId',
            builder: (_, state) =>
                RateRulesScreen(unitId: state.pathParameters['unitId']!),
          ),
          GoRoute(
            path: '/admin/block/:unitId',
            builder: (_, state) =>
                BlockDatesScreen(unitId: state.pathParameters['unitId']!),
          ),
          GoRoute(
            path: '/admin/bookings',
            builder: (_, _) => const AdminBookingsScreen(),
          ),
          GoRoute(path: '/staff', builder: (_, _) => const TodayScreen()),
        ],
      ),
    ],
    errorBuilder: (_, _) => const NotFoundScreen(),
  );
});
