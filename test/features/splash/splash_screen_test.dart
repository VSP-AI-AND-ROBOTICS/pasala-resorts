// test/features/splash/splash_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pasala/core/widgets/brand_mark.dart';
import 'package:pasala/features/splash/splash_screen.dart';

void main() {
  Widget appFor() {
    final router = GoRouter(
      initialLocation: '/splash',
      routes: [
        GoRoute(path: '/splash', builder: (_, _) => const SplashScreen()),
        GoRoute(path: '/welcome', builder: (_, _) => const Text('Welcome')),
      ],
    );
    return MaterialApp.router(routerConfig: router);
  }

  testWidgets('shows the brand mark over the background', (tester) async {
    await tester.pumpWidget(appFor());

    expect(find.byType(BrandMark), findsOneWidget);
  });

  testWidgets('navigates to /welcome after its delay', (tester) async {
    await tester.pumpWidget(appFor());

    expect(find.text('Welcome'), findsNothing);

    await tester.pumpAndSettle(const Duration(seconds: 3));

    expect(find.text('Welcome'), findsOneWidget);
  });
}
