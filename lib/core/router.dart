import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/models/app_user.dart';
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
import '../features/outbox/outbox_screen.dart';
import '../features/reports/dashboard_screen.dart';
import '../features/reports/reports_screen.dart';
import '../features/shell/app_shell.dart';
import '../features/shell/not_found_screen.dart';
import '../features/staff/today_screen.dart';

/// Decides where `path` should redirect to, given the signed-in [user]
/// (`null` before sign-in) and whether `path` is the login/signup screen.
/// `null` means "let the navigation proceed as requested".
///
/// Pure so the admin/staff/accountant/customer matrix -- in particular that
/// `/admin/dashboard` and `/admin/reports` are staff-or-above while every
/// other `/admin/*` route stays admin-only -- is unit-testable without
/// pumping a full [GoRouter] and its child screens, several of which (the
/// admin/reports screens) hit Supabase on build. See `router_test.dart`.
///
/// Route guarding is user experience only. RLS in Postgres is what actually
/// enforces access; a customer who forges a route sees a not-found page and
/// would get 42501 from the database regardless.
String? redirectFor({
  required AppUser? user,
  required String path,
  required bool loggingIn,
}) {
  if (user == null) return loggingIn ? null : '/login';
  if (loggingIn) return '/';

  if (path.startsWith('/admin')) {
    // `report_revenue`, `report_occupancy`, and `dashboard_summary` all
    // explicitly permit staff-or-above in the database (`assert_staff`),
    // and the accountant role exists precisely to read financials -- so
    // these two leaf routes are staff-or-above. `outbox_read` (migration
    // 0017) is the same staff-or-above grant -- whoever fields a guest's
    // "did my confirmation go out?" question needs to see the queue, not
    // just an admin -- so `/admin/outbox` joins them here. Every other
    // `/admin/*` route (properties, units, rates, blocking, the bookings
    // list) stays admin-only, matching the RLS/RPC surfaces that actually
    // write data.
    final staffOrAboveOk = user.isStaffOrAbove &&
        (path == '/admin/dashboard' ||
            path == '/admin/reports' ||
            path == '/admin/outbox');
    if (!user.isAdmin && !staffOrAboveOk) return '/404';
  }
  if (path.startsWith('/staff') && !user.isStaffOrAbove) return '/404';
  return null;
}

final routerProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(currentUserProvider);

  return GoRouter(
    initialLocation: '/',
    redirect: (context, state) => redirectFor(
      user: auth.value,
      path: state.matchedLocation,
      loggingIn: state.matchedLocation == '/login' ||
          state.matchedLocation == '/signup',
    ),
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
          GoRoute(
            path: '/admin/dashboard',
            builder: (_, _) => const DashboardScreen(),
          ),
          GoRoute(
            path: '/admin/reports',
            builder: (_, _) => const ReportsScreen(),
          ),
          GoRoute(
            path: '/admin/outbox',
            builder: (_, _) => const OutboxScreen(),
          ),
          GoRoute(path: '/staff', builder: (_, _) => const TodayScreen()),
        ],
      ),
    ],
    errorBuilder: (_, _) => const NotFoundScreen(),
  );
});
