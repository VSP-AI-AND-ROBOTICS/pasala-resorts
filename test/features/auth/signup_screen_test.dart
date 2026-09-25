import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pasala/core/router.dart';
import 'package:pasala/core/widgets/brand_mark.dart';
import 'package:pasala/features/auth/signup_screen.dart';

void main() {
  testWidgets('shows name, email, and password fields', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SignupScreen()));

    expect(find.byKey(const Key('signup-name')), findsOneWidget);
    expect(find.byKey(const Key('signup-email')), findsOneWidget);
    expect(find.byKey(const Key('signup-password')), findsOneWidget);
    expect(
      find.widgetWithText(FilledButton, 'Create account'),
      findsOneWidget,
    );
  });

  testWidgets('rejects a password shorter than 8 characters', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SignupScreen()));

    await tester.enterText(find.byKey(const Key('signup-name')), 'Ravi Kumar');
    await tester.enterText(
      find.byKey(const Key('signup-email')),
      'ravi@example.com',
    );
    await tester.enterText(find.byKey(const Key('signup-password')), '1234567');

    await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
    await tester.pump();

    expect(find.text('Use at least 8 characters'), findsOneWidget);
  });

  testWidgets('shows the ResortHub name, not the Pasala logo or name',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SignupScreen()));

    expect(find.text('ResortHub'), findsOneWidget);
    expect(find.text('Pasala Resorts'), findsNothing);
    expect(find.byType(BrandMark), findsNothing);
  });

  testWidgets('Already have an account keeps next', (tester) async {
    final router = GoRouter(
      initialLocation: '/signup?next=%2Flist-your-resort',
      routes: [
        GoRoute(
          path: '/signup',
          builder: (_, state) => SignupScreen(next: postSignInPath(state.uri)),
        ),
        GoRoute(
          path: '/login',
          builder: (_, state) =>
              Text('Login next=${state.uri.queryParameters['next']}'),
        ),
      ],
    );
    await tester.pumpWidget(
        ProviderScope(child: MaterialApp.router(routerConfig: router)));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Already have an account? Sign in'));
    await tester.tap(find.text('Already have an account? Sign in'));
    await tester.pumpAndSettle();

    expect(find.text('Login next=/list-your-resort'), findsOneWidget);
  });
}
