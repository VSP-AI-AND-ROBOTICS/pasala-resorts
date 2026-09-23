import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../models/user_profile.dart';
import '../services/mock_data_store.dart';
import '../../features/auth/login_page.dart';
import '../../features/auth/incharge_login_page.dart';
import '../../features/super_admin/browse_resorts_page.dart';
import '../../features/super_admin/subscriptions_page.dart';
import '../../features/super_admin/payment_management_page.dart';
import '../../features/super_admin/reports_page.dart';
import '../../features/admin/admin_dashboard_page.dart';
import '../../features/incharge/incharge_dashboard_page.dart';
import '../../features/accountant/accountant_dashboard_page.dart';
import '../../features/customer/customer_home_page.dart';
import '../../features/customer/resort_detail_page.dart';
import '../../features/customer/my_bookings_page.dart';
import '../../features/auth/register_page.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

class AppRouter {
  static final MockDataStore _store = MockDataStore.instance;

  static final GoRouter router = GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/customer',
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginPage(),
      ),
      GoRoute(
        path: '/register',
        builder: (context, state) => const RegisterPage(),
      ),
      GoRoute(
        path: '/incharge-login',
        builder: (context, state) => const InchargeLoginPage(),
      ),
      // --- Super Admin / Co-Owner Routes ---
      GoRoute(
        path: '/super-admin',
        builder: (context, state) => const BrowseResortsPage(),
        routes: [
          GoRoute(
            path: 'subscriptions',
            builder: (context, state) => const SubscriptionsPage(),
          ),
          GoRoute(
            path: 'payments',
            builder: (context, state) => const PaymentManagementPage(),
          ),
          GoRoute(
            path: 'reports',
            builder: (context, state) => const ReportsPage(),
          ),
        ],
      ),
      // --- Resort Admin / Manager Route ---
      GoRoute(
        path: '/admin',
        builder: (context, state) => const AdminDashboardPage(),
      ),
      // --- Incharge Operational Route ---
      GoRoute(
        path: '/incharge',
        builder: (context, state) => const InchargeDashboardPage(),
      ),
      // --- Accountant Financial Route ---
      GoRoute(
        path: '/accountant',
        builder: (context, state) => const AccountantDashboardPage(),
      ),
      // --- Customer Discovery & Booking Routes ---
      GoRoute(
        path: '/customer',
        builder: (context, state) => const CustomerHomePage(),
        routes: [
          GoRoute(
            path: 'resort/:id',
            builder: (context, state) {
              final resortId = state.pathParameters['id']!;
              return ResortDetailPage(resortId: resortId);
            },
          ),
          GoRoute(
            path: 'my-bookings',
            builder: (context, state) => const MyBookingsPage(),
          ),
        ],
      ),
    ],
    redirect: (context, state) {
      final user = _store.currentUser;
      final loc = state.matchedLocation;

      // Always allow auth routes
      if (loc == '/login' || loc == '/incharge-login' || loc == '/register') {
        // If already logged in, redirect to their dashboard
        if (user != null) return _getInitialRouteForRole(user.role);
        return null;
      }

      // Not logged in — go to login
      if (user == null) return '/login';

      // Strict role guards — each role may ONLY visit its own routes
      if (loc.startsWith('/super-admin') && user.role != AppRole.superAdmin) {
        return _getInitialRouteForRole(user.role);
      }
      if (loc.startsWith('/admin') && user.role != AppRole.admin) {
        return _getInitialRouteForRole(user.role);
      }
      if (loc.startsWith('/incharge') && user.role != AppRole.incharge) {
        return _getInitialRouteForRole(user.role);
      }
      if (loc.startsWith('/accountant') && user.role != AppRole.accountant) {
        return _getInitialRouteForRole(user.role);
      }
      if (loc.startsWith('/customer') && user.role != AppRole.customer) {
        if (loc.startsWith('/customer/resort/')) {
          return null; // Allow viewing resort details and availability page for promo links & preview
        }
        return _getInitialRouteForRole(user.role);
      }

      return null;
    },
  );

  static String _getInitialRouteForRole(AppRole role) {
    switch (role) {
      case AppRole.superAdmin:
        return '/super-admin';
      case AppRole.admin:
        return '/admin';
      case AppRole.incharge:
        return '/incharge';
      case AppRole.accountant:
        return '/accountant';
      case AppRole.customer:
        return '/customer';
    }
  }
}
