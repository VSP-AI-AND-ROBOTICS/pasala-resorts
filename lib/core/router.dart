import 'package:flutter/material.dart';
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
import '../features/admin/users_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/signup_screen.dart';
import '../features/booking/booking_screen.dart';
import '../features/booking/confirmation_screen.dart';
import '../features/browse/browse_screen.dart';
import '../features/browse/property_screen.dart';
import '../features/ota/ical_screen.dart';
import '../features/outbox/outbox_screen.dart';
import '../features/reports/dashboard_screen.dart';
import '../features/reports/reports_screen.dart';
import '../features/shell/app_shell.dart';
import '../features/shell/not_found_screen.dart';
import '../features/staff/today_screen.dart';
import 'theme/tokens.dart';

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
  if (loggingIn) return landingPathFor(user);

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

/// Where [user] lands immediately after signing in (or after navigating to
/// `/login`/`/signup` while already signed in) -- see `redirectFor`'s
/// `loggingIn` branch above, and the two call sites in `login_screen.dart`
/// and `signup_screen.dart`. Every role used to land on `/` (customer
/// browse), including staff and admins, who have no reason to browse
/// holidays the moment they sign in.
///
/// Kept next to [redirectFor], and consulted by it, so the two role
/// matrices cannot drift apart: a role that `redirectFor` refuses on a path
/// can never be the path [landingPathFor] sends that same role to.
String landingPathFor(AppUser user) {
  if (user.isAdmin) return '/admin';
  if (user.role == UserRole.accountant) return '/admin/dashboard';
  if (user.role == UserRole.staff) return '/staff';
  return '/';
}

/// A fade + slight upward slide, used for every customer-facing route so
/// navigation reads as one continuous surface rather than a hard cut.
/// Admin/staff routes keep GoRouter's default transition — this is a
/// customer-facing polish detail, not a platform-wide behaviour change.
Page<void> fadeSlidePage(Widget child, GoRouterState state) =>
    CustomTransitionPage<void>(
      key: state.pageKey,
      child: child,
      transitionDuration: PasalaTokens.motionBase,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(parent: animation, curve: Curves.easeOut);
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.04),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
    );

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
      GoRoute(
        path: '/login',
        pageBuilder: (_, state) => fadeSlidePage(const LoginScreen(), state),
      ),
      GoRoute(
        path: '/signup',
        pageBuilder: (_, state) => fadeSlidePage(const SignupScreen(), state),
      ),
      GoRoute(path: '/404', builder: (_, _) => const NotFoundScreen()),
      ShellRoute(
        builder: (_, _, child) => AppShell(child: child),
        routes: [
          GoRoute(
            path: '/',
            pageBuilder: (_, state) => fadeSlidePage(const BrowseScreen(), state),
          ),
          GoRoute(
            path: '/property/:id',
            pageBuilder: (_, state) => fadeSlidePage(
              PropertyScreen(propertyId: state.pathParameters['id']!),
              state,
            ),
          ),
          GoRoute(
            path: '/book/:unitId',
            pageBuilder: (_, state) => fadeSlidePage(
              BookingScreen(unitId: state.pathParameters['unitId']!),
              state,
            ),
          ),
          GoRoute(
            path: '/booking/:id',
            pageBuilder: (_, state) => fadeSlidePage(
              ConfirmationScreen(reservationId: state.pathParameters['id']!),
              state,
            ),
          ),
          GoRoute(
            path: '/bookings',
            pageBuilder: (_, state) =>
                fadeSlidePage(const MyBookingsScreen(), state),
          ),
          GoRoute(
            path: '/booking-detail/:id',
            pageBuilder: (_, state) => fadeSlidePage(
              BookingDetailScreen(reservationId: state.pathParameters['id']!),
              state,
            ),
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
            path: '/admin/ota/:unitId',
            builder: (_, state) =>
                IcalScreen(unitId: state.pathParameters['unitId']!),
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
          GoRoute(
            path: '/admin/users',
            builder: (_, _) => const UsersScreen(),
          ),
          GoRoute(path: '/staff', builder: (_, _) => const TodayScreen()),
        ],
      ),
    ],
    errorBuilder: (_, _) => const NotFoundScreen(),
  );
});
