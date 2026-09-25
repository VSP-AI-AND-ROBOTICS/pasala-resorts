import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pasala/core/current_resort.dart';
import 'package:pasala/core/errors.dart';
import 'package:pasala/data/models/app_user.dart';
import 'package:pasala/data/models/resort_membership.dart';
import 'package:pasala/data/repositories/auth_repository.dart';
import 'package:pasala/data/repositories/resort_member_repository.dart';
import 'package:pasala/features/owner/team_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// In-memory stand-in for [ResortMemberRepository], mirroring
/// `FakeUserAdminSource` in the deleted `users_screen_test.dart`.
class FakeResortMemberSource implements ResortMemberSource {
  List<ResortMember> rows = [];
  Object? listError;
  Object? addError;
  Object? setRoleError;
  Object? removeError;
  final List<(String, String, ResortRole)> addCalls = [];
  final List<(String, String, ResortRole)> setRoleCalls = [];
  final List<(String, String)> removeCalls = [];

  @override
  Future<List<ResortMember>> list(String propertyId) async {
    if (listError != null) throw listError!;
    return rows;
  }

  @override
  Future<void> add(String propertyId, String email, ResortRole role) async {
    addCalls.add((propertyId, email, role));
    if (addError != null) throw addError!;
  }

  @override
  Future<void> setRole(
      String propertyId, String userId, ResortRole role) async {
    setRoleCalls.add((propertyId, userId, role));
    if (setRoleError != null) throw setRoleError!;
  }

  @override
  Future<void> remove(String propertyId, String userId) async {
    removeCalls.add((propertyId, userId));
    if (removeError != null) throw removeError!;
  }
}

ResortMember _member({
  String userId = 'u1',
  String email = 'ravi@example.com',
  String? fullName = 'Ravi Kumar',
  ResortRole role = ResortRole.staff,
}) =>
    ResortMember(
      userId: userId,
      email: email,
      fullName: fullName,
      role: role,
      createdAt: DateTime.utc(2026, 1, 1),
    );

const _resortA = ResortMembership(
    propertyId: 'resort-a', resortName: 'Pasala Farm', role: ResortRole.owner);
const _owner = AppUser(
    id: 'owner-1', email: 'owner@pasala.test', memberships: [_resortA]);

void main() {
  /// How many times `currentUserProvider` has been built in the current
  /// test -- a rebuild after the first means someone invalidated it.
  var userBuilds = 0;

  Future<void> pump(
    WidgetTester tester, {
    required FakeResortMemberSource source,
  }) async {
    SharedPreferences.setMockInitialValues({});
    userBuilds = 0;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        resortMemberSourceProvider.overrideWithValue(source),
        currentUserProvider.overrideWith((ref) {
          userBuilds++;
          return Stream.value(_owner);
        }),
        currentResortProvider.overrideWith(() => _FixedResort(_resortA)),
      ],
      // Keeps the signed-in user listened to, as the router does in the app.
      child: MaterialApp(
        home: Consumer(builder: (context, ref, _) {
          ref.watch(currentUserProvider);
          return const TeamScreen();
        }),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('explains accounts are created at Sign Up and added here by '
      'email', (tester) async {
    await pump(tester, source: FakeResortMemberSource());

    expect(find.textContaining('Sign Up'), findsOneWidget);
    expect(find.textContaining('email'), findsWidgets);
  });

  testWidgets('renders each member with their name, email and role label',
      (tester) async {
    final source = FakeResortMemberSource()
      ..rows = [_member(role: ResortRole.staff)];
    await pump(tester, source: source);

    expect(find.text('Ravi Kumar'), findsOneWidget);
    expect(find.text('ravi@example.com'), findsOneWidget);
    expect(find.text('Staff / Incharge'), findsOneWidget);
  });

  testWidgets('an empty roster shows an EmptyState, not a blank screen',
      (tester) async {
    await pump(tester, source: FakeResortMemberSource());

    expect(find.text('No team members yet'), findsOneWidget);
  });

  testWidgets(
      'adding new@x.com as Staff calls add(resort-a, new@x.com, staff)',
      (tester) async {
    final source = FakeResortMemberSource();
    await pump(tester, source: source);

    await tester.tap(find.byKey(const Key('add-member-fab')));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const Key('add-member-email')), 'new@x.com');
    await tester.tap(find.byKey(const Key('add-member-role')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Staff / Incharge').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('add-member-submit')));
    await tester.pumpAndSettle();

    expect(source.addCalls, [('resort-a', 'new@x.com', ResortRole.staff)]);
  });

  testWidgets(
      'a P0023 failure from setRole shows the error text and leaves the '
      'dropdown on the old role', (tester) async {
    final source = FakeResortMemberSource()
      ..rows = [_member(userId: 'u1', role: ResortRole.admin)]
      ..setRoleError = const LastOwner();
    await pump(tester, source: source);

    await tester.tap(find.byKey(const Key('role-dropdown-u1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Owner').last);
    await tester.pumpAndSettle();

    expect(find.text('A resort must keep at least one owner.'), findsOneWidget);
    // The dropdown still shows the OLD role -- the change was refused, so
    // the UI must not have applied it optimistically.
    expect(find.text('Admin'), findsWidgets);
  });

  testWidgets('tapping remove on a member calls remove(resort-a, u1)',
      (tester) async {
    final source = FakeResortMemberSource()..rows = [_member(userId: 'u1')];
    await pump(tester, source: source);

    await tester.tap(find.byKey(const Key('remove-member-u1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();

    expect(source.removeCalls, [('resort-a', 'u1')]);
  });

  // Final review F4: changing or removing your OWN membership must refetch
  // the signed-in user, so the stale role (and resort) don't linger in the
  // router and the resort switcher.
  Future<int> settledUserBuilds(WidgetTester tester) async {
    await tester.pumpAndSettle();
    return userBuilds;
  }

  testWidgets('changing your own role refetches the signed-in user',
      (tester) async {
    final source = FakeResortMemberSource()
      ..rows = [
        _member(userId: 'owner-1', role: ResortRole.owner),
        _member(userId: 'u2', email: 'co@example.com', role: ResortRole.owner),
      ];
    await pump(tester, source: source);
    final before = await settledUserBuilds(tester);

    await tester.tap(find.byKey(const Key('role-dropdown-owner-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Admin').last);
    await tester.pumpAndSettle();

    expect(source.setRoleCalls, [('resort-a', 'owner-1', ResortRole.admin)]);
    expect(await settledUserBuilds(tester), greaterThan(before));
  });

  testWidgets('removing yourself refetches the signed-in user',
      (tester) async {
    final source = FakeResortMemberSource()
      ..rows = [_member(userId: 'owner-1', role: ResortRole.owner)];
    await pump(tester, source: source);
    final before = await settledUserBuilds(tester);

    await tester.tap(find.byKey(const Key('remove-member-owner-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();

    expect(source.removeCalls, [('resort-a', 'owner-1')]);
    expect(await settledUserBuilds(tester), greaterThan(before));
  });

  testWidgets("changing someone else's role leaves the signed-in user alone",
      (tester) async {
    final source = FakeResortMemberSource()
      ..rows = [_member(userId: 'u1', role: ResortRole.staff)];
    await pump(tester, source: source);
    final before = await settledUserBuilds(tester);

    await tester.tap(find.byKey(const Key('role-dropdown-u1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Admin').last);
    await tester.pumpAndSettle();

    expect(source.setRoleCalls, [('resort-a', 'u1', ResortRole.admin)]);
    expect(await settledUserBuilds(tester), before);
  });

  // E2E-shaped bug: /owner/team lives inside the router's ShellRoute, so the
  // screen's own context resolves to the shell navigator while showDialog
  // puts the confirm dialog on the root one. The dialog's buttons must pop
  // the dialog, not the page (lib/features/admin/tasks_screen.dart's
  // ShellRoute regression test is the model for this one).
  testWidgets(
      'confirming remove inside a ShellRoute closes the dialog, not the page',
      (tester) async {
    final source = FakeResortMemberSource()..rows = [_member(userId: 'u1')];
    final router = GoRouter(
      initialLocation: '/owner/team',
      routes: [
        ShellRoute(
          builder: (_, _, child) => Scaffold(body: child),
          routes: [
            GoRoute(path: '/owner', builder: (_, _) => const Text('Owner home')),
            GoRoute(path: '/owner/team', builder: (_, _) => const TeamScreen()),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);

    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(ProviderScope(
      overrides: [
        resortMemberSourceProvider.overrideWithValue(source),
        currentUserProvider.overrideWith((ref) => Stream.value(_owner)),
        currentResortProvider.overrideWith(() => _FixedResort(_resortA)),
      ],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pumpAndSettle();

    // Cancel first: the dialog closes and the page stays.
    await tester.tap(find.byKey(const Key('remove-member-u1')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(TeamScreen), findsOneWidget);
    expect(source.removeCalls, isEmpty);

    await tester.tap(find.byKey(const Key('remove-member-u1')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(TeamScreen), findsOneWidget);
    expect(source.removeCalls, [('resort-a', 'u1')]);
  });
}

/// Test-only [CurrentResort] that always resolves to a fixed value,
/// mirroring `_FixedResort` in `app_shell_test.dart`.
class _FixedResort extends CurrentResort {
  _FixedResort(this._value);
  final ResortMembership? _value;
  @override
  ResortMembership? build() => _value;
}
