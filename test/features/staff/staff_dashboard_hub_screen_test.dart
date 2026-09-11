import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pasala/data/models/app_user.dart';
import 'package:pasala/data/repositories/auth_repository.dart';
import 'package:pasala/features/staff/staff_dashboard_hub_screen.dart';

const _staff = AppUser(
  id: 'staff-1',
  email: 'staff@pasala.test',
  role: UserRole.staff,
  fullName: 'Sita Staff',
);

const _accountant = AppUser(
  id: 'accountant-1',
  email: 'accounts@pasala.test',
  role: UserRole.accountant,
  fullName: 'Anil Accounts',
);

void main() {
  group('staffHubSections', () {
    test('has exactly one entry per requested staff section', () {
      expect(
        staffHubSections.map((s) => s.title).toSet(),
        {
          'Profile',
          'Working Hours',
          'Leave Management',
          'Assigned Work',
          'Work Schedules',
          'Time Slots',
          'Daily Work Status',
          'Food Orders',
          'Service Requests',
          'Maintenance',
        },
      );
    });

    test('every section has a unique route path', () {
      final paths = staffHubSections.map((s) => s.path).toList();
      expect(paths.toSet().length, paths.length);
    });

    test('every path lives under /staff, so router gating already covers it', () {
      for (final section in staffHubSections) {
        expect(section.path, startsWith('/staff/'));
      }
    });
  });

  Widget appFor({AppUser user = _staff}) {
    final router = GoRouter(
      initialLocation: '/hub',
      routes: [
        GoRoute(
          path: '/hub',
          builder: (_, _) => const StaffDashboardHubScreen(),
        ),
        for (final section in [
          ...staffHubSections,
          const (
            path: '/admin/check-in',
            icon: Icons.login_outlined,
            title: 'Check-In',
          ),
          const (
            path: '/admin/check-out',
            icon: Icons.logout_outlined,
            title: 'Check-Out',
          ),
          const (
            path: '/owner/food-sales',
            icon: Icons.point_of_sale_outlined,
            title: 'Food & Activity Sales',
          ),
          const (
            path: '/admin/outbox',
            icon: Icons.outbox_outlined,
            title: 'Outbox',
          ),
          const (
            path: '/owner/expenses',
            icon: Icons.receipt_long_outlined,
            title: 'Expenses',
          ),
        ])
          GoRoute(
            path: section.path,
            builder: (_, _) => Scaffold(
              body: Text('destination:${section.path}'),
            ),
          ),
      ],
    );
    return ProviderScope(
      overrides: [
        currentUserProvider.overrideWith((ref) => Stream.value(user)),
      ],
      child: MaterialApp.router(routerConfig: router),
    );
  }

  testWidgets('lists a tappable card for every staff section', (
    tester,
  ) async {
    // Three more sections were added for the Guest Stay Experience feature,
    // pushing the list past what the default test viewport's cache extent
    // builds -- same fix as `owner_home_screen_test.dart`'s own
    // GridView virtualization issue.
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(appFor());
    await tester.pumpAndSettle();

    for (final section in staffHubSections) {
      expect(find.text(section.title), findsOneWidget, reason: section.title);
    }
  });

  testWidgets('tapping a card navigates to its route', (tester) async {
    await tester.pumpWidget(appFor());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Leave Management'));
    await tester.pumpAndSettle();

    expect(find.text('destination:/staff/leave'), findsOneWidget);
  });

  // I7: food_activity_sales_read/_insert, outbox_read, check_in_booking and
  // checkout_booking all grant staff-or-above -- every staff-or-above user
  // gets Check-In, Check-Out, Food & Activity Sales and Outbox cards.
  // expenses_read grants admin/accountant/super_admin, so only an
  // accountant also gets an Expenses card (plain staff must not see
  // expenses at all).
  testWidgets('a plain staff member sees the staff-or-above extras but not Expenses', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(appFor(user: _staff));
    await tester.pumpAndSettle();

    expect(find.text('Check-In'), findsOneWidget);
    expect(find.text('Check-Out'), findsOneWidget);
    expect(find.text('Food & Activity Sales'), findsOneWidget);
    expect(find.text('Outbox'), findsOneWidget);
    expect(find.text('Expenses'), findsNothing);
  });

  testWidgets('an accountant sees every extra, including Expenses', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(appFor(user: _accountant));
    await tester.pumpAndSettle();

    expect(find.text('Check-In'), findsOneWidget);
    expect(find.text('Check-Out'), findsOneWidget);
    expect(find.text('Food & Activity Sales'), findsOneWidget);
    expect(find.text('Outbox'), findsOneWidget);
    expect(find.text('Expenses'), findsOneWidget);
  });

  testWidgets('tapping Check-In navigates to /admin/check-in', (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(appFor());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Check-In'));
    await tester.pumpAndSettle();

    expect(find.text('destination:/admin/check-in'), findsOneWidget);
  });
}
