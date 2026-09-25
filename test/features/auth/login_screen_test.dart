import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pasala/core/router.dart';
import 'package:pasala/core/widgets/brand_mark.dart';
import 'package:pasala/data/models/app_user.dart';
import 'package:pasala/data/repositories/auth_repository.dart';
import 'package:pasala/features/auth/login_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Signs anyone in as a customer with no memberships.
class _FakeAuth implements AuthRepository {
  @override
  Future<AppUser> signIn(String email, String password) async =>
      const AppUser(id: 'u1', email: 'asha@example.com');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _routed(String location) {
  final router = GoRouter(
    initialLocation: location,
    routes: [
      GoRoute(
        path: '/login',
        builder: (_, state) => LoginScreen(next: postSignInPath(state.uri)),
      ),
      GoRoute(
        path: '/signup',
        builder: (_, state) =>
            Text('Signup next=${state.uri.queryParameters['next']}'),
      ),
      GoRoute(
        path: '/list-your-resort',
        builder: (_, _) => const Text('List page'),
      ),
      GoRoute(path: '/', builder: (_, _) => const Text('Browse')),
    ],
  );
  return ProviderScope(
    overrides: [authRepositoryProvider.overrideWithValue(_FakeAuth())],
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('shows email, password, and a sign-in button', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));

    expect(find.byKey(const Key('login-email')), findsOneWidget);
    expect(find.byKey(const Key('login-password')), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Sign in'), findsOneWidget);
  });

  testWidgets('rejects an empty email', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));

    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pump();

    expect(find.text('Enter your email'), findsOneWidget);
  });

  testWidgets('shows the ResortHub name, not the Pasala logo or name',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));

    expect(find.text('ResortHub'), findsOneWidget);
    expect(find.text('Pasala Resorts'), findsNothing);
    expect(find.byType(BrandMark), findsNothing);
  });

  testWidgets('after signing in, goes on to an allowed next page',
      (tester) async {
    await tester.pumpWidget(_routed('/login?next=%2Flist-your-resort'));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const Key('login-email')), 'asha@example.com');
    await tester.enterText(
        find.byKey(const Key('login-password')), 'password123');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();

    expect(find.text('List page'), findsOneWidget);
  });

  testWidgets('without next, signing in lands where the role lands',
      (tester) async {
    await tester.pumpWidget(_routed('/login'));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const Key('login-email')), 'asha@example.com');
    await tester.enterText(
        find.byKey(const Key('login-password')), 'password123');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();

    expect(find.text('Browse'), findsOneWidget);
  });

  testWidgets('Create an account keeps next', (tester) async {
    await tester.pumpWidget(_routed('/login?next=%2Flist-your-resort'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Create an account'));
    await tester.tap(find.text('Create an account'));
    await tester.pumpAndSettle();

    expect(find.text('Signup next=/list-your-resort'), findsOneWidget);
  });
}
