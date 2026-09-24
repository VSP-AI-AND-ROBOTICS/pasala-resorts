import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pasala/core/current_resort.dart';
import 'package:pasala/core/theme/app_theme.dart';
import 'package:pasala/data/models/app_user.dart';
import 'package:pasala/data/models/report.dart';
import 'package:pasala/data/models/resort_membership.dart';
import 'package:pasala/data/repositories/auth_repository.dart';
import 'package:pasala/features/owner/owner_home_screen.dart';
import 'package:pasala/features/reports/providers.dart';

class _FixedResort extends CurrentResort {
  _FixedResort(this._value);
  final ResortMembership? _value;
  @override
  ResortMembership? build() => _value;
}

const _ownerM =
    ResortMembership(propertyId: 'p1', resortName: 'Pasala', role: ResortRole.owner);

const _owner = AppUser(
  id: 'owner-1',
  email: 'super@pasala.test',
  memberships: [_ownerM],
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
  ThemeMode themeMode = ThemeMode.light,
}) {
  final router = GoRouter(
    initialLocation: '/owner',
    routes: [
      GoRoute(path: '/owner', builder: (_, _) => const OwnerHomeScreen()),
      GoRoute(path: '/admin/bookings', builder: (_, _) => const Text('Bookings screen')),
      GoRoute(path: '/staff/rooms', builder: (_, _) => const Text('Rooms screen')),
      GoRoute(path: '/finance', builder: (_, _) => const Text('Finance screen')),
    ],
  );

  return ProviderScope(
    overrides: [
      currentUserProvider.overrideWith((ref) => Stream.value(_owner)),
      currentResortProvider.overrideWith(() => _FixedResort(_ownerM)),
      dashboardSummaryProvider.overrideWith((ref, propertyId) async => summary),
    ],
    child: MaterialApp.router(
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: themeMode,
      routerConfig: router,
    ),
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
      'Finance',
      'Revenue',
      'Occupancy',
      'Bookings',
      'Rooms',
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

  testWidgets('renders in ThemeMode.dark without throwing', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_appFor(themeMode: ThemeMode.dark));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('Priya'), findsOneWidget);
  });

  testWidgets('the Rooms tile opens the room status grid', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_appFor());
    await tester.pumpAndSettle();

    final roomsTile = find.text('Rooms');
    await tester.ensureVisible(roomsTile);
    await tester.pumpAndSettle();
    await tester.tap(roomsTile);
    await tester.pumpAndSettle();

    expect(find.text('Rooms screen'), findsOneWidget);
  });

  testWidgets('the Finance tile opens the Finance screen', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_appFor());
    await tester.pumpAndSettle();

    final financeTile = find.text('Finance');
    await tester.ensureVisible(financeTile);
    await tester.pumpAndSettle();
    await tester.tap(financeTile);
    await tester.pumpAndSettle();

    expect(find.text('Finance screen'), findsOneWidget);
  });
}
