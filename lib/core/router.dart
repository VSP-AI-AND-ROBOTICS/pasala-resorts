import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'current_resort.dart';
import '../data/models/app_user.dart';
import '../data/models/resort_membership.dart';
import '../data/repositories/auth_repository.dart';
import '../data/models/activity.dart';
import '../features/account/booking_detail_screen.dart';
import '../features/account/my_bookings_screen.dart';
import '../features/admin/admin_bookings_screen.dart';
import '../features/admin/admin_more_screen.dart';
import '../features/admin/admin_reviews_screen.dart';
import '../features/admin/admin_home_screen.dart';
import '../features/admin/attendance_screen.dart';
import '../features/admin/kitchen_orders_screen.dart';
import '../features/admin/maintenance_issues_screen.dart';
import '../features/admin/reception_checkin_screen.dart';
import '../features/admin/reception_checkout_screen.dart';
import '../features/admin/resort_unit_guard.dart';
import '../features/admin/service_requests_screen.dart';
import '../features/admin/tasks_screen.dart';
import '../features/admin/block_dates_screen.dart';
import '../features/admin/leave_requests_screen.dart';
import '../features/admin/property_form_screen.dart';
import '../features/admin/rate_rules_screen.dart';
import '../features/admin/staff_shifts_screen.dart';
import '../features/admin/units_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/signup_screen.dart';
import '../features/auth/welcome_screen.dart';
import '../features/booking/confirmation_screen.dart';
import '../features/finance/finance_screen.dart';
import '../features/browse/browse_screen.dart';
import '../features/browse/customer_reviews_screen.dart';
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
import '../features/owner/team_screen.dart';
import '../features/platform/platform_screen.dart';
import '../features/reports/dashboard_screen.dart';
import '../features/reports/reports_screen.dart';
import '../features/resorts/choose_resort_screen.dart';
import '../features/shell/app_shell.dart';
import '../features/shell/not_found_screen.dart';
import '../features/splash/splash_screen.dart';
import '../features/staff/assigned_tasks_screen.dart';
import '../features/staff/daily_status_screen.dart';
import '../features/staff/leave_screen.dart';
import '../features/staff/my_food_orders_screen.dart';
import '../features/staff/my_maintenance_issues_screen.dart';
import '../features/staff/my_service_requests_screen.dart';
import '../features/staff/room_status_screen.dart';
import '../features/staff/staff_dashboard_hub_screen.dart';
import '../features/staff/staff_profile_screen.dart';
import '../features/staff/time_slots_screen.dart';
import '../features/staff/today_screen.dart';
import '../features/staff/work_schedules_screen.dart';
import '../features/staff/working_hours_screen.dart';
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
/// (`null` before sign-in), the [resort] they're currently working in
/// (`null` for customers, platform admins, and a multi-resort user who
/// hasn't picked one yet -- see `resolveCurrentResort`), and whether `path`
/// is one of the four pre-authentication screens (splash, welcome, login,
/// signup). `null` means "let the navigation proceed as requested".
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
  required ResortMembership? resort,
  required String path,
  required bool onPreAuthScreen,
}) {
  if (user == null) return onPreAuthScreen ? null : '/login';
  if (onPreAuthScreen) return landingPathFor(user, resort);

  if (path == '/platform') return user.isPlatformAdmin ? null : '/404';
  if (path == '/choose-resort') {
    return user.memberships.length >= 2 ? null : '/404';
  }

  // A user with 2+ memberships who hasn't picked one yet has no role to
  // check any `/admin`, `/staff`, or `/owner` path against -- send them to
  // pick first, rather than either admitting them role-blind or bouncing
  // them to `/404` as if they held no memberships at all.
  if ((path.startsWith('/admin') ||
          path.startsWith('/staff') ||
          path.startsWith('/owner') ||
          path.startsWith('/finance')) &&
      resort == null &&
      user.memberships.isNotEmpty) {
    return '/choose-resort';
  }

  if (path.startsWith('/admin')) {
    // `report_revenue`, `report_occupancy`, and `dashboard_summary` all
    // explicitly permit staff-or-above in the database (`assert_staff`),
    // and the accountant role exists precisely to read financials -- so
    // these two leaf routes are staff-or-above. `outbox_read` (migration
    // 0017) is the same staff-or-above grant -- whoever fields a guest's
    // "did my confirmation go out?" question needs to see the queue, not
    // just an admin -- so `/admin/outbox` joins them here. `check_in_booking`
    // and `checkout_booking` (0037_stay_checkout.sql) are the same
    // staff-or-above grant too -- reception need not be an admin account to
    // check a guest in or settle their final bill -- so `/admin/check-in`
    // and `/admin/check-out` join them here as well, with the desk
    // checkout of one booking at `/admin/check-out/:reservationId`. Every other
    // `/admin/*` route (properties, units, rates, blocking, the bookings
    // list) stays admin-only, matching the RLS/RPC surfaces that actually
    // write data.
    final staffOrAboveOk = resort != null &&
        (path == '/admin/dashboard' ||
            path == '/admin/reports' ||
            path == '/admin/outbox' ||
            path == '/admin/check-in' ||
            path == '/admin/check-out' ||
            path.startsWith('/admin/check-out/'));
    final isAdminHere =
        resort != null && const {ResortRole.owner, ResortRole.admin}.contains(resort.role);
    if (!isAdminHere && !staffOrAboveOk) return '/404';
    // The property id in `/admin/units/:propertyId` comes from the URL:
    // only the current resort's own id opens it. (The unit-id routes are
    // checked by `ResortUnitGuard`, since a unit's resort needs a lookup.)
    const unitsPrefix = '/admin/units/';
    if (path.startsWith(unitsPrefix) &&
        path.substring(unitsPrefix.length) != resort.propertyId) {
      return '/404';
    }
  }
  if (path.startsWith('/staff') && resort == null) return '/404';
  // Finance (REQ-07): owner, admin and accountant at the current resort.
  // report_collections, report_ledger, report_settlements and
  // finance_summary assert the same roles in Postgres; plain staff keep
  // their `/admin/reports` view and get /404 here.
  if (path.startsWith('/finance') &&
      !const {ResortRole.owner, ResortRole.admin, ResortRole.accountant}
          .contains(resort?.role)) {
    return '/404';
  }
  // The Owner flow (Business Dashboard -> ... -> Settings) is a distinct,
  // more powerful surface than `/admin` -- Cancellation Policy and Booking
  // Rules write data (`refund_rules`, `properties.min_nights`/`max_nights`)
  // that today's `/admin` screens have never exposed to any role. Kept
  // owner-only rather than admin-or-owner so a plain `admin` account
  // cannot reach it just by knowing the URL -- same "route guarding is UX
  // only" caveat as above: every RPC/table this leads to still carries its
  // own real Postgres-level gate independent of this check. `/owner/team`
  // (Task 18) is owner-only for the same reason -- adding or removing a
  // member is a step above plain admin.
  // `/owner/expenses` and `/owner/food-sales` are the two exceptions:
  // `expenses_read` (0027_expenses.sql) already grants admin/accountant/
  // super_admin, and `food_activity_sales_read`/`_insert`
  // (0026_food_activity_sales.sql) already grant staff-or-above -- the
  // accountant role exists specifically to read financials, and any staff
  // member logging a walk-in guest's food/pool purchase needs somewhere
  // real to go. Both are let through despite the blanket owner-only
  // rule below; each screen itself still hides the write actions (add/
  // edit/delete) a given role's own RLS grant doesn't cover, matching the
  // "route guarding is UX only" caveat -- the real gate is always Postgres.
  final isExpensesLeaf = path == '/owner/expenses';
  final isFoodSalesLeaf = path == '/owner/food-sales';
  if (path.startsWith('/owner') &&
      !isExpensesLeaf &&
      !isFoodSalesLeaf &&
      resort?.role != ResortRole.owner) {
    return '/404';
  }
  if (isExpensesLeaf &&
      !const {ResortRole.owner, ResortRole.admin}.contains(resort?.role) &&
      resort?.role != ResortRole.accountant) {
    return '/404';
  }
  if (isFoodSalesLeaf && resort == null) return '/404';
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
String landingPathFor(AppUser user, ResortMembership? resort) {
  if (user.isPlatformAdmin) return '/platform';
  if (user.memberships.isEmpty) return '/';
  if (resort == null) return '/choose-resort';
  return switch (resort.role) {
    ResortRole.owner => '/owner',
    ResortRole.admin => '/admin',
    // Finance (REQ-07) is the accountant's own screen -- collections,
    // ledger, tax and settlements -- and the first tab of their bar (see
    // `AppShell._accountantDestinations`).
    ResortRole.accountant => '/finance',
    ResortRole.staff => '/staff',
  };
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

/// The app's one [GoRouter], built once for the app's lifetime.
///
/// It used to `ref.watch` the signed-in user and resort, so every change to
/// either built a brand-new GoRouter, which restarts at `initialLocation`
/// (`/splash`) and sends a signed-in user to their landing page -- any
/// page, e.g. a reloaded desk checkout, was lost. Now a change only
/// re-runs [redirectFor] on the current location (`refreshListenable`).
///
/// A reload also starts before the stored session has been read: the user
/// provider is still loading, which [redirectFor] would treat as signed out
/// and bounce to `/login`. Instead the requested location is held while
/// the app waits on `/splash`, and restored once a signed-in user is known
/// (then checked by [redirectFor] like any other navigation). If the
/// session turns out to be signed out, the held location is dropped.
final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.listen(currentUserProvider, (_, _) => refresh.value++);
  ref.listen(currentResortProvider, (_, _) => refresh.value++);

  const preAuthPaths = {'/splash', '/welcome', '/login', '/signup'};
  String? heldLocation;

  String? redirect(BuildContext context, GoRouterState state) {
    final auth = ref.read(currentUserProvider);
    final path = state.matchedLocation;
    final onPreAuthScreen = preAuthPaths.contains(path);
    if (auth.isLoading && !auth.hasValue) {
      if (onPreAuthScreen) return null;
      heldLocation = state.uri.toString();
      return '/splash';
    }
    final held = heldLocation;
    heldLocation = null;
    if (held != null && onPreAuthScreen && auth.value != null) return held;
    return redirectFor(
      user: auth.value,
      resort: ref.read(currentResortProvider),
      path: path,
      onPreAuthScreen: onPreAuthScreen,
    );
  }

  final router = GoRouter(
    initialLocation: '/splash',
    refreshListenable: refresh,
    redirect: redirect,
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
      // Outside the ShellRoute (like the pre-auth screens): a multi-resort
      // user lands here with no resort picked yet, so `AppShell`'s
      // resort-dependent nav destinations have nothing to key off.
      GoRoute(
        path: '/choose-resort',
        pageBuilder: (_, state) =>
            fadeSlidePage(const ChooseResortScreen(), state),
      ),
      // Also outside the ShellRoute: the platform admin has no membership
      // at any resort, so `AppShell`'s nav destinations (which are all
      // keyed off `currentResortProvider`) have nothing to key off here
      // either -- same reasoning as `/choose-resort` above.
      GoRoute(
        path: '/platform',
        pageBuilder: (_, state) =>
            fadeSlidePage(const PlatformScreen(), state),
      ),
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
            path: '/property/:id/reviews',
            pageBuilder: (_, state) => fadeSlidePage(
              CustomerReviewsScreen(propertyId: state.pathParameters['id']!),
              state,
            ),
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
            builder: (_, state) => ResortUnitGuard(
              unitId: state.pathParameters['unitId']!,
              child: RateRulesScreen(unitId: state.pathParameters['unitId']!),
            ),
          ),
          GoRoute(
            path: '/admin/block/:unitId',
            builder: (_, state) => ResortUnitGuard(
              unitId: state.pathParameters['unitId']!,
              child: BlockDatesScreen(unitId: state.pathParameters['unitId']!),
            ),
          ),
          GoRoute(
            path: '/admin/ota/:unitId',
            builder: (_, state) => ResortUnitGuard(
              unitId: state.pathParameters['unitId']!,
              child: IcalScreen(unitId: state.pathParameters['unitId']!),
            ),
          ),
          GoRoute(
            path: '/admin/bookings',
            builder: (_, _) => const AdminBookingsScreen(),
          ),
          GoRoute(
            path: '/admin/reviews',
            builder: (_, _) => const AdminReviewsScreen(),
          ),
          GoRoute(
            path: '/admin/more',
            builder: (_, _) => const AdminMoreScreen(),
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
          GoRoute(
            path: '/owner/team',
            builder: (_, _) => const TeamScreen(),
          ),
          // Finance (REQ-07). Owner, admin and accountant only (see
          // redirectFor); the report functions enforce the same in Postgres.
          GoRoute(
            path: '/finance',
            builder: (_, _) => const FinanceScreen(),
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
            builder: (_, _) => const WorkingHoursScreen(),
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
          // Room status grid (REQ-06). Open to every role at the current
          // resort through the `/staff/*` rule in redirectFor; the screen
          // hides actions from accountants, and set_room_status /
          // dispatch_housekeeping enforce the roles in Postgres.
          GoRoute(
            path: '/staff/rooms',
            builder: (_, _) => const RoomStatusScreen(),
          ),
          GoRoute(
            path: '/admin/check-in',
            builder: (_, _) => const ReceptionCheckinScreen(),
          ),
          GoRoute(
            path: '/admin/check-out',
            builder: (_, _) => const ReceptionCheckoutScreen(),
            routes: [
              // Reception's desk checkout at /admin/check-out/:reservationId.
              // The reservation id and desk mode both live in the URL so a
              // web refresh or back/forward rebuilds it -- a route `extra`
              // does not survive either. A child of the list so `context.go`
              // (which, unlike `push`, updates the browser URL) still
              // stacks it above the list.
              GoRoute(
                path: ':reservationId',
                pageBuilder: (_, state) => fadeSlidePage(
                  CheckoutScreen(
                    reservationId: state.pathParameters['reservationId']!,
                    desk: true,
                  ),
                  state,
                ),
              ),
            ],
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
              checkoutScreenFor(state.extra),
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
  ref.onDispose(() {
    router.dispose();
    refresh.dispose();
  });
  return router;
});
