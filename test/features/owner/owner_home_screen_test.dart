import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pasala/data/models/app_user.dart';
import 'package:pasala/data/models/report.dart';
import 'package:pasala/data/repositories/auth_repository.dart';
import 'package:pasala/features/owner/owner_home_screen.dart';
import 'package:pasala/features/reports/providers.dart';

const _owner = AppUser(
  id: 'owner-1',
  email: 'super@pasala.test',
  fullName: 'Priya Owner',
);

Widget _appFor({
  DashboardSummary summary = const DashboardSummary(
    todayRevenue: 0,
    monthRevenue: 120000,
    occupancyPct: 0,
    upcomingArrivals: 0,
    cancellationsThisMonth: 0,
    activeHolds: 0,
    netProfitMonth: 45000,
  ),
}) {
  final router = GoRouter(
    initialLocation: '/owner',
    routes: [
      GoRoute(path: '/owner', builder: (_, _) => const OwnerHomeScreen()),
      GoRoute(path: '/admin/bookings', builder: (_, _) => const Text('Bookings screen')),
    ],
  );

  return ProviderScope(
    overrides: [
      currentUserProvider.overrideWith((ref) => Stream.value(_owner)),
      dashboardSummaryProvider.overrideWith((ref) async => summary),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  testWidgets('greets the signed-in owner by first name', (tester) async {
    await tester.pumpWidget(_appFor());
    await tester.pumpAndSettle();

    expect(find.textContaining('Priya'), findsOneWidget);
  });

  testWidgets('shows real revenue and net profit figures', (tester) async {
    await tester.pumpWidget(_appFor());
    await tester.pumpAndSettle();

    expect(find.textContaining('1,20,000'), findsOneWidget);
    expect(find.textContaining('45,000'), findsOneWidget);
  });

  testWidgets('shows a tile for every step of the Owner flow', (tester) async {
    // The default test surface is too short to render all 9 grid tiles at
    // once -- GridView.builder virtualizes offscreen children, so without
    // this the last couple of tiles simply aren't in the tree yet.
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_appFor());
    await tester.pumpAndSettle();

    for (final title in [
      'Business dashboard',
      'Revenue',
      'Occupancy',
      'Bookings',
      'Food & activity sales',
      'Expenses',
      'Staff performance',
      'Reports',
      'Settings',
    ]) {
      expect(find.text(title), findsOneWidget, reason: title);
    }
  });

  testWidgets('tapping a tile navigates to its route', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_appFor());
    await tester.pumpAndSettle();

    final bookingsTile = find.text('Bookings');
    await tester.ensureVisible(bookingsTile);
    await tester.pumpAndSettle();
    await tester.tap(bookingsTile);
    await tester.pumpAndSettle();

    expect(find.text('Bookings screen'), findsOneWidget);
  });
}
