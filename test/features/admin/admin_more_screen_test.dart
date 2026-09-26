import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pasala/features/admin/admin_more_screen.dart';

void main() {
  testWidgets(
      'lists every management screen the old Admin home grid used to hold',
      (tester) async {
    // GridView.builder virtualizes offscreen children -- without a tall
    // enough surface, the later tiles simply aren't in the tree yet.
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: AdminMoreScreen()));
    await tester.pumpAndSettle();

    for (final title in const [
      'Properties',
      'Financial Dashboard',
      'Finance',
      'Coupons',
      'Outbox',
      'Staff shifts',
      'Leave requests',
      'Attendance',
      'Tasks',
      'Service requests',
    ]) {
      expect(find.text(title), findsOneWidget, reason: title);
    }
  });

  testWidgets('the Finance entry opens /finance', (tester) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final router = GoRouter(
      initialLocation: '/admin/more',
      routes: [
        GoRoute(path: '/admin/more', builder: (_, _) => const AdminMoreScreen()),
        GoRoute(path: '/finance', builder: (_, _) => const Text('Finance screen')),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Finance'));
    await tester.pumpAndSettle();

    expect(find.text('Finance screen'), findsOneWidget);
  });

  testWidgets('the Coupons entry opens /admin/coupons', (tester) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final router = GoRouter(
      initialLocation: '/admin/more',
      routes: [
        GoRoute(path: '/admin/more', builder: (_, _) => const AdminMoreScreen()),
        GoRoute(
            path: '/admin/coupons',
            builder: (_, _) => const Text('Coupons screen')),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Coupons'));
    await tester.pumpAndSettle();

    expect(find.text('Coupons screen'), findsOneWidget);
  });
}
