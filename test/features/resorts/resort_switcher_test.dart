import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pasala/core/current_resort.dart';
import 'package:pasala/data/models/app_user.dart';
import 'package:pasala/data/models/resort_membership.dart';
import 'package:pasala/data/repositories/auth_repository.dart';
import 'package:pasala/features/resorts/resort_switcher.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _a = ResortMembership(
    propertyId: 'a', resortName: 'Pasala Farm', role: ResortRole.owner);
const _b = ResortMembership(
    propertyId: 'b', resortName: 'Beach Resort', role: ResortRole.staff);

const _oneMembership =
    AppUser(id: 'u', email: 'u@pasala.test', memberships: [_a]);
const _twoMemberships =
    AppUser(id: 'u', email: 'u@pasala.test', memberships: [_a, _b]);

Widget _appFor(AppUser user) {
  final router = GoRouter(
    initialLocation: '/owner',
    routes: [
      GoRoute(
        path: '/owner',
        builder: (_, _) => Scaffold(
          appBar: AppBar(actions: const [ResortSwitcher()]),
        ),
      ),
      GoRoute(path: '/staff', builder: (_, _) => const SizedBox()),
    ],
  );

  return ProviderScope(
    overrides: [
      currentUserProvider.overrideWith((ref) => Stream.value(user)),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  testWidgets('is hidden when the user has only one membership',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(_appFor(_oneMembership));
    await tester.pumpAndSettle();

    expect(find.byType(ResortSwitcher), findsOneWidget);
    expect(find.byIcon(Icons.swap_horiz), findsNothing);
  });

  testWidgets('shows a menu of resort names with 2+ memberships',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(_appFor(_twoMemberships));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.swap_horiz), findsOneWidget);

    await tester.tap(find.byIcon(Icons.swap_horiz));
    await tester.pumpAndSettle();

    expect(find.text('Pasala Farm'), findsOneWidget);
    expect(find.text('Beach Resort'), findsOneWidget);
  });

  testWidgets('picking a resort updates currentResortProvider to it',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer(overrides: [
      currentUserProvider.overrideWith((ref) => Stream.value(_twoMemberships)),
    ]);
    addTearDown(container.dispose);

    final router = GoRouter(
      initialLocation: '/owner',
      routes: [
        GoRoute(
          path: '/owner',
          builder: (_, _) => Scaffold(
            appBar: AppBar(actions: const [ResortSwitcher()]),
          ),
        ),
        GoRoute(path: '/staff', builder: (_, _) => const SizedBox()),
      ],
    );

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.swap_horiz));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Beach Resort'));
    await tester.pumpAndSettle();

    expect(container.read(currentResortProvider), _b);
    // Beach Resort's role is staff -- landingPathFor sends staff to
    // `/staff`.
    expect(
        router.routerDelegate.currentConfiguration.uri.path, '/staff');
  });
}
