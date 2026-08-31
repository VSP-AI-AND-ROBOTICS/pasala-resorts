// test/features/auth/welcome_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
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
}
