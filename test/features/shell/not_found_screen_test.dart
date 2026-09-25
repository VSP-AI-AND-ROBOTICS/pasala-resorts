import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pasala/data/models/app_user.dart';
import 'package:pasala/data/models/resort_membership.dart';
import 'package:pasala/data/repositories/auth_repository.dart';
import 'package:pasala/features/shell/not_found_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// NotFoundScreen at `/404`, with stand-in landing pages, for [user].
Future<void> _pumpAt404(WidgetTester tester, AppUser? user) async {
  SharedPreferences.setMockInitialValues({});
  final container = ProviderContainer(overrides: [
    currentUserProvider.overrideWith((ref) => Stream.value(user)),
  ]);
  addTearDown(container.dispose);
  // The app's router keeps the user provider alive; stand in for it.
  container.listen(currentUserProvider, (_, _) {});
  await container.read(currentUserProvider.future);
  final router = GoRouter(initialLocation: '/404', routes: [
    GoRoute(path: '/404', builder: (_, _) => const NotFoundScreen()),
    GoRoute(path: '/staff', builder: (_, _) => const Text('Staff home')),
    GoRoute(path: '/login', builder: (_, _) => const Text('Sign in')),
  ]);
  addTearDown(router.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(routerConfig: router),
  ));
  await tester.pumpAndSettle();
}

void main() {
  // A bare Text produced no heading (and, on web, no ARIA role at all), so
  // screen readers had nothing to announce and the E2E suite's
  // waitForFlutter never saw the screen render.
  testWidgets('"Page not found" is a level-1 heading for screen readers',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(const MaterialApp(home: NotFoundScreen()));

    final heading = find.text('Page not found');
    expect(heading, findsOneWidget);
    expect(
      tester.getSemantics(heading),
      isSemantics(label: 'Page not found', isHeader: true),
    );
    expect(tester.getSemantics(heading).getSemanticsData().headingLevel, 1);
    semantics.dispose();
  });

  testWidgets('explains what happened below the heading', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: NotFoundScreen()));

    expect(
      find.text("This page doesn't exist, or you don't have access to it."),
      findsOneWidget,
    );
  });

  // Reached by a redirect, /404 sits outside the shell: no app bar, no nav.
  testWidgets("offers a way back to the signed-in user's landing page",
      (tester) async {
    await _pumpAt404(
      tester,
      const AppUser(id: 's', email: 's@pasala.test', memberships: [
        ResortMembership(
            propertyId: 'r1', resortName: 'R1', role: ResortRole.staff),
      ]),
    );

    await tester.tap(find.text('Go to my home page'));
    await tester.pumpAndSettle();

    expect(find.text('Staff home'), findsOneWidget);
  });

  testWidgets('sends a signed-out visitor to sign in', (tester) async {
    await _pumpAt404(tester, null);

    await tester.tap(find.text('Go to my home page'));
    await tester.pumpAndSettle();

    expect(find.text('Sign in'), findsOneWidget);
  });
}
