import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/models/app_user.dart';
import '../data/repositories/auth_repository.dart';
import '../data/models/activity.dart';
import '../features/account/booking_detail_screen.dart';
import '../features/account/my_bookings_screen.dart';
import '../features/admin/admin_bookings_screen.dart';
import '../features/admin/admin_home_screen.dart';
import '../features/admin/attendance_screen.dart';
import '../features/admin/kitchen_orders_screen.dart';
import '../features/admin/maintenance_issues_screen.dart';
import '../features/admin/reception_checkin_screen.dart';
import '../features/admin/service_requests_screen.dart';
import '../features/admin/tasks_screen.dart';
import '../features/admin/block_dates_screen.dart';
import '../features/admin/leave_requests_screen.dart';
import '../features/admin/property_form_screen.dart';
import '../features/admin/rate_rules_screen.dart';
import '../features/admin/staff_shifts_screen.dart';
import '../features/admin/units_screen.dart';
import '../features/admin/users_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/signup_screen.dart';
import '../features/auth/welcome_screen.dart';
import '../features/booking/confirmation_screen.dart';
import '../features/browse/browse_screen.dart';
import '../features/browse/property_screen.dart';
import '../features/ota/ical_screen.dart';
import '../features/outbox/outbox_screen.dart';
import '../features/owner/business_dashboard_screen.dart';
import '../features/owner/expenses_screen.dart';
import '../features/owner/food_sales_screen.dart';
import '../features/owner/owner_home_screen.dart';
import '../features/owner/owner_reports_screen.dart';
import '../features/owner/owner_settings_screen.dart';
import '../features/owner/staff_performance_screen.dart';
import '../features/reports/dashboard_screen.dart';
import '../features/reports/reports_screen.dart';
import '../features/shell/app_shell.dart';
import '../features/shell/not_found_screen.dart';
import '../features/splash/splash_screen.dart';
import '../features/staff/assigned_tasks_screen.dart';
import '../features/staff/daily_status_screen.dart';
import '../features/staff/leave_screen.dart';
import '../features/staff/my_food_orders_screen.dart';
import '../features/staff/my_maintenance_issues_screen.dart';
import '../features/staff/my_service_requests_screen.dart';
import '../features/staff/placeholder_section_screen.dart';
import '../features/staff/staff_dashboard_hub_screen.dart';
import '../features/staff/staff_profile_screen.dart';
import '../features/staff/time_slots_screen.dart';
import '../features/staff/today_screen.dart';
import '../features/staff/work_schedules_screen.dart';
import '../features/stay/activity_booking_form_screen.dart';
import '../features/stay/activity_catalog_screen.dart';
import '../features/stay/checkout_screen.dart';
import '../features/stay/current_charges_screen.dart';
import '../features/stay/final_invoice_screen.dart';
import '../features/stay/food_menu_screen.dart';
import '../features/stay/food_order_status_screen.dart';
import '../features/stay/maintenance_report_screen.dart';
import '../features/stay/my_activity_bookings_screen.dart';
import '../features/stay/my_maintenance_issues_screen.dart';
import '../features/stay/my_service_requests_screen.dart';
import '../features/stay/my_stay_screen.dart';
import '../features/stay/review_screen.dart';
import '../features/stay/service_request_screen.dart';
import 'theme/tokens.dart';

/// Decides where `path` should redirect to, given the signed-in [user]
/// (`null` before sign-in) and whether `path` is one of the four
/// pre-authentication screens (splash, welcome, login, signup).
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
  required bool onPreAuthScreen,
}) {
  if (user == null) return onPreAuthScreen ? null : '/login';
  if (onPreAuthScreen) return landingPathFor(user);

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
  // The Owner flow (Business Dashboard -> ... -> Settings) is a distinct,
  // more powerful surface than `/admin` -- Cancellation Policy and Booking
  // Rules write data (`refund_rules`, `properties.min_nights`/`max_nights`)
  // that today's `/admin` screens have never exposed to any role. Kept
  // `super_admin`-only rather than `isAdmin` so a plain `admin` account
  // cannot reach it just by knowing the URL -- same "route guarding is UX
  // only" caveat as above: every RPC/table this leads to still carries its
  // own real Postgres-level gate independent of this check.
  if (path.startsWith('/owner') && user.role != UserRole.superAdmin) {
    return '/404';
  }
  return null;
}

/// Where [user] lands immediately after signing in (or after navigating to
/// `/login`/`/signup` while already signed in) -- see `redirectFor`'s
/// `onPreAuthScreen` branch above, and the two call sites in `login_screen.dart`
/// and `signup_screen.dart`. Every role used to land on `/` (customer
/// browse), including staff and admins, who have no reason to browse
/// holidays the moment they sign in.
///
/// Kept next to [redirectFor], and consulted by it, so the two role
/// matrices cannot drift apart: a role that `redirectFor` refuses on a path
/// can never be the path [landingPathFor] sends that same role to.
String landingPathFor(AppUser user) {
  if (user.role == UserRole.superAdmin) return '/owner';
  if (user.isAdmin) return '/admin';
  // Both land on the staff-operations hub, not `/admin/dashboard` (the
  // financial summary `AdminHomeScreen` still links to for admin) -- that
  // route is no longer reachable from either role's own nav (see
  // `AppShell._staffDestinations`), so landing there would strand them one
  // tap short of the tabs they actually have.
  if (user.role == UserRole.accountant) return '/staff/dashboard';
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

  const preAuthPaths = {'/splash', '/welcome', '/login', '/signup'};
  return GoRouter(
    initialLocation: '/splash',
    redirect: (context, state) => redirectFor(
      user: auth.value,
      path: state.matchedLocation,
      onPreAuthScreen: preAuthPaths.contains(state.matchedLocation),
    ),
    routes: [
      GoRoute(
        path: '/splash',
        pageBuilder: (_, state) => fadeSlidePage(const SplashScreen(), state),
      ),
      GoRoute(
        path: '/welcome',
        pageBuilder: (_, state) => fadeSlidePage(const WelcomeScreen(), state),
      ),
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
          GoRoute(
            path: '/admin/staff-shifts',
            builder: (_, _) => const StaffShiftsScreen(),
          ),
          GoRoute(
            path: '/admin/leave-requests',
            builder: (_, _) => const LeaveRequestsScreen(),
          ),
          GoRoute(
            path: '/admin/attendance',
            builder: (_, _) => const AttendanceScreen(),
          ),
          GoRoute(
            path: '/admin/tasks',
            builder: (_, _) => const TasksScreen(),
          ),
          GoRoute(path: '/owner', builder: (_, _) => const OwnerHomeScreen()),
          GoRoute(
            path: '/owner/dashboard',
            builder: (_, _) => const BusinessDashboardScreen(),
          ),
          GoRoute(
            path: '/owner/food-sales',
            builder: (_, _) => const FoodSalesScreen(),
          ),
          GoRoute(
            path: '/owner/expenses',
            builder: (_, _) => const ExpensesScreen(),
          ),
          GoRoute(
            path: '/owner/staff-performance',
            builder: (_, _) => const StaffPerformanceScreen(),
          ),
          GoRoute(
            path: '/owner/reports',
            builder: (_, _) => const OwnerReportsScreen(),
          ),
          GoRoute(
            path: '/owner/settings',
            builder: (_, _) => const OwnerSettingsScreen(),
          ),
          GoRoute(path: '/staff', builder: (_, _) => const TodayScreen()),
          GoRoute(
            path: '/staff/dashboard',
            builder: (_, _) => const StaffDashboardHubScreen(),
          ),
          GoRoute(
            path: '/staff/profile',
            builder: (_, _) => const StaffProfileScreen(),
          ),
          GoRoute(
            path: '/staff/working-hours',
            builder: (_, _) => const PlaceholderSectionScreen(
              title: 'Working Hours',
              icon: Icons.schedule_outlined,
            ),
          ),
          GoRoute(
            path: '/staff/leave',
            builder: (_, _) => const LeaveScreen(),
          ),
          GoRoute(
            path: '/staff/tasks',
            builder: (_, _) => const AssignedTasksScreen(),
          ),
          GoRoute(
            path: '/staff/schedules',
            builder: (_, _) => const WorkSchedulesScreen(),
          ),
          GoRoute(
            path: '/staff/time-slots',
            builder: (_, _) => const TimeSlotsScreen(),
          ),
          GoRoute(
            path: '/staff/daily-status',
            builder: (_, _) => const DailyStatusScreen(),
          ),
          GoRoute(
            path: '/staff/food-orders',
            builder: (_, _) => const MyFoodOrdersScreen(),
          ),
          GoRoute(
            path: '/staff/service-requests',
            builder: (_, _) => const StaffServiceRequestsScreen(),
          ),
          GoRoute(
            path: '/staff/maintenance',
            builder: (_, _) => const StaffMaintenanceIssuesScreen(),
          ),
          GoRoute(
            path: '/admin/check-in',
            builder: (_, _) => const ReceptionCheckinScreen(),
          ),
          GoRoute(
            path: '/admin/kitchen-orders',
            builder: (_, _) => const KitchenOrdersScreen(),
          ),
          GoRoute(
            path: '/admin/service-requests',
            builder: (_, _) => const ServiceRequestsScreen(),
          ),
          GoRoute(
            path: '/admin/maintenance',
            builder: (_, _) => const MaintenanceIssuesScreen(),
          ),
          GoRoute(
            path: '/my-stay',
            pageBuilder: (_, state) => fadeSlidePage(const MyStayScreen(), state),
          ),
          GoRoute(
            path: '/my-stay/food',
            pageBuilder: (_, state) => fadeSlidePage(
              FoodMenuScreen(reservationId: state.extra! as String),
              state,
            ),
          ),
          GoRoute(
            path: '/my-stay/food/orders',
            pageBuilder: (_, state) => fadeSlidePage(
              FoodOrderStatusScreen(reservationId: state.extra! as String),
              state,
            ),
          ),
          GoRoute(
            path: '/my-stay/activities',
            pageBuilder: (_, state) => fadeSlidePage(
              ActivityCatalogScreen(reservationId: state.extra! as String),
              state,
            ),
          ),
          GoRoute(
            path: '/my-stay/activities/bookings',
            pageBuilder: (_, state) => fadeSlidePage(
              MyActivityBookingsScreen(reservationId: state.extra! as String),
              state,
            ),
          ),
          GoRoute(
            path: '/my-stay/activities/book/:activityId',
            pageBuilder: (_, state) {
              final args = state.extra!
                  as ({String reservationId, Activity activity});
              return fadeSlidePage(
                ActivityBookingFormScreen(
                  reservationId: args.reservationId,
                  activity: args.activity,
                ),
                state,
              );
            },
          ),
          GoRoute(
            path: '/my-stay/service-requests',
            pageBuilder: (_, state) => fadeSlidePage(
              ServiceRequestScreen(reservationId: state.extra! as String),
              state,
            ),
          ),
          GoRoute(
            path: '/my-stay/service-requests/mine',
            pageBuilder: (_, state) => fadeSlidePage(
              MyServiceRequestsScreen(reservationId: state.extra! as String),
              state,
            ),
          ),
          GoRoute(
            path: '/my-stay/maintenance',
            pageBuilder: (_, state) => fadeSlidePage(
              MaintenanceReportScreen(reservationId: state.extra! as String),
              state,
            ),
          ),
          GoRoute(
            path: '/my-stay/maintenance/mine',
            pageBuilder: (_, state) => fadeSlidePage(
              MyMaintenanceIssuesScreen(reservationId: state.extra! as String),
              state,
            ),
          ),
          GoRoute(
            path: '/my-stay/charges',
            pageBuilder: (_, state) => fadeSlidePage(
              CurrentChargesScreen(reservationId: state.extra! as String),
              state,
            ),
          ),
          GoRoute(
            path: '/my-stay/checkout',
            pageBuilder: (_, state) => fadeSlidePage(
              CheckoutScreen(reservationId: state.extra! as String),
              state,
            ),
          ),
          GoRoute(
            path: '/my-stay/invoice/:id',
            pageBuilder: (_, state) => fadeSlidePage(
              FinalInvoiceScreen(reservationId: state.pathParameters['id']!),
              state,
            ),
          ),
          GoRoute(
            path: '/my-stay/review/:id',
            pageBuilder: (_, state) => fadeSlidePage(
              ReviewScreen(reservationId: state.pathParameters['id']!),
              state,
            ),
          ),
        ],
      ),
    ],
    errorBuilder: (_, _) => const NotFoundScreen(),
  );
});
