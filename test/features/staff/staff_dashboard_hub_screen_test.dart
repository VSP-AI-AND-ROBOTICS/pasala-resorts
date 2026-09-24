import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pasala/core/current_resort.dart';
import 'package:pasala/data/models/resort_membership.dart';
import 'package:pasala/features/staff/staff_dashboard_hub_screen.dart';

const _staffM =
    ResortMembership(propertyId: 'r1', resortName: 'R1', role: ResortRole.staff);
const _accountantM = ResortMembership(
    propertyId: 'r1', resortName: 'R1', role: ResortRole.accountant);

class _FixedResort extends CurrentResort {
  _FixedResort(this._value);
  final ResortMembership? _value;
  @override
  ResortMembership? build() => _value;
}

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

  Widget appFor({ResortMembership resort = _staffM}) {
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
        currentResortProvider.overrideWith(() => _FixedResort(resort)),
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

    await tester.pumpWidget(appFor(resort: _staffM));
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

    await tester.pumpWidget(appFor(resort: _accountantM));
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
