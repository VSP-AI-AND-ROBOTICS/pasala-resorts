import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pasala/features/owner/owner_home_screen.dart';

void main() {
  testWidgets('shows a tile for every step of the Owner flow', (tester) async {
    // The default test surface is too short to render all 9 grid tiles at
    // once -- GridView.builder virtualizes offscreen children, so without
    // this the last couple of tiles simply aren't in the tree yet.
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final router = GoRouter(
      initialLocation: '/owner',
      routes: [
        GoRoute(path: '/owner', builder: (_, _) => const OwnerHomeScreen()),
        GoRoute(path: '/admin/bookings', builder: (_, _) => const Placeholder()),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
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
    final router = GoRouter(
      initialLocation: '/owner',
      routes: [
        GoRoute(path: '/owner', builder: (_, _) => const OwnerHomeScreen()),
        GoRoute(path: '/admin/bookings', builder: (_, _) => const Text('Bookings screen')),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Bookings'));
    await tester.pumpAndSettle();

    expect(find.text('Bookings screen'), findsOneWidget);
  });
}
