import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pasala/features/staff/staff_dashboard_hub_screen.dart';

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

  Widget appFor() {
    final router = GoRouter(
      initialLocation: '/hub',
      routes: [
        GoRoute(
          path: '/hub',
          builder: (_, _) => const StaffDashboardHubScreen(),
        ),
        for (final section in staffHubSections)
          GoRoute(
            path: section.path,
            builder: (_, _) => Scaffold(
              body: Text('destination:${section.path}'),
            ),
          ),
      ],
    );
    return MaterialApp.router(routerConfig: router);
  }

  testWidgets('lists a tappable card for every staff section', (
    tester,
  ) async {
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
}
