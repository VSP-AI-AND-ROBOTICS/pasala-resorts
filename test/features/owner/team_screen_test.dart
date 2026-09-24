import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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
  Future<void> pump(
    WidgetTester tester, {
    required FakeResortMemberSource source,
  }) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(ProviderScope(
      overrides: [
        resortMemberSourceProvider.overrideWithValue(source),
        currentUserProvider.overrideWith((ref) => Stream.value(_owner)),
        currentResortProvider.overrideWith(() => _FixedResort(_resortA)),
      ],
      child: const MaterialApp(home: TeamScreen()),
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
      ..setRoleError = const InvalidState('Resort must keep at least one owner.');
    await pump(tester, source: source);

    await tester.tap(find.byKey(const Key('role-dropdown-u1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Owner').last);
    await tester.pumpAndSettle();

    expect(find.text('Resort must keep at least one owner.'), findsOneWidget);
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
}

/// Test-only [CurrentResort] that always resolves to a fixed value,
/// mirroring `_FixedResort` in `app_shell_test.dart`.
class _FixedResort extends CurrentResort {
  _FixedResort(this._value);
  final ResortMembership? _value;
  @override
  ResortMembership? build() => _value;
}
