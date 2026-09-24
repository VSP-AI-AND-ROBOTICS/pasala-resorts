// test/features/auth/welcome_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pasala/core/theme/app_assets.dart';
import 'package:pasala/features/auth/welcome_screen.dart';

void main() {
  Widget appFor() {
    final router = GoRouter(
      initialLocation: '/welcome',
      routes: [
        GoRoute(path: '/welcome', builder: (_, _) => const WelcomeScreen()),
        GoRoute(path: '/login', builder: (_, _) => const Text('Login screen')),
        GoRoute(path: '/signup', builder: (_, _) => const Text('Signup screen')),
      ],
    );
    return MaterialApp.router(routerConfig: router);
  }

  testWidgets('Sign In navigates to /login', (tester) async {
    await tester.pumpWidget(appFor());

    await tester.tap(find.widgetWithText(FilledButton, 'Sign In'));
    await tester.pumpAndSettle();

    expect(find.text('Login screen'), findsOneWidget);
  });

  testWidgets('Sign Up navigates to /signup', (tester) async {
    await tester.pumpWidget(appFor());

    await tester.tap(find.widgetWithText(OutlinedButton, 'Sign Up'));
    await tester.pumpAndSettle();

    expect(find.text('Signup screen'), findsOneWidget);
  });

  testWidgets('shows the ResortHub name, not the old Pasala Resorts brand', (
    tester,
  ) async {
    await tester.pumpWidget(appFor());

    expect(find.text('ResortHub'), findsOneWidget);
    expect(find.text('Pasala Resorts'), findsNothing);
  });

  testWidgets(
    'renders exactly one hero image, flush with the left edge, on a '
    'narrow surface',
    (tester) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(appFor());
      await tester.pumpAndSettle();

      final heroImage = find.byWidgetPredicate(
        (widget) =>
            widget is Image &&
            widget.image is AssetImage &&
            (widget.image as AssetImage).assetName ==
                AppAssets.heroNightAerial,
      );
      expect(heroImage, findsOneWidget);
      expect(tester.getTopLeft(heroImage).dx, 0);
    },
  );
}
