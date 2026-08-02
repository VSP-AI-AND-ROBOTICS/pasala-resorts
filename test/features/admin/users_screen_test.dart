import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/errors.dart';
import 'package:pasala/data/models/admin_profile.dart';
import 'package:pasala/data/models/app_user.dart';
import 'package:pasala/data/repositories/auth_repository.dart';
import 'package:pasala/data/repositories/user_admin_repository.dart';
import 'package:pasala/features/admin/users_screen.dart';

/// In-memory stand-in for [UserAdminRepository], mirroring
/// `FakeOutboxSource` in `outbox_screen_test.dart`.
class FakeUserAdminSource implements UserAdminSource {
  List<AdminProfile> rows = [];
  Object? listError;
  Object? setRoleError;
  final List<(String, UserRole)> setRoleCalls = [];

  @override
  Future<List<AdminProfile>> listProfiles() async {
    if (listError != null) throw listError!;
    return rows;
  }

  @override
  Future<void> setRole(String userId, UserRole role) async {
    setRoleCalls.add((userId, role));
    if (setRoleError != null) throw setRoleError!;
  }
}

AdminProfile _profile({
  String id = 'u1',
  String email = 'ravi@example.com',
  String? fullName = 'Ravi Kumar',
  UserRole role = UserRole.customer,
}) =>
    AdminProfile(
      id: id,
      email: email,
      fullName: fullName,
      role: role,
      createdAt: DateTime.utc(2026, 1, 1),
    );

const _admin =
    AppUser(id: 'admin-id', email: 'admin@pasala.test', role: UserRole.admin);
const _superAdmin = AppUser(
    id: 'sa-id', email: 'sa@pasala.test', role: UserRole.superAdmin);

void main() {
  Future<void> pump(
    WidgetTester tester, {
    required FakeUserAdminSource source,
    required AppUser actor,
  }) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        userAdminSourceProvider.overrideWithValue(source),
        currentUserProvider.overrideWith((ref) => Stream.value(actor)),
      ],
      child: const MaterialApp(home: UsersScreen()),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('explains there is no add-user button and how accounts appear',
      (tester) async {
    await pump(tester, source: FakeUserAdminSource(), actor: _superAdmin);

    expect(find.byKey(const Key('sign-up-then-promote-banner')),
        findsOneWidget);
    expect(find.textContaining('Add user'), findsOneWidget);
  });

  testWidgets('an empty roster shows an EmptyState, not a blank screen',
      (tester) async {
    await pump(tester, source: FakeUserAdminSource(), actor: _superAdmin);

    expect(find.text('No users yet'), findsOneWidget);
  });

  testWidgets('a row shows the name, email and role', (tester) async {
    final source = FakeUserAdminSource()
      ..rows = [_profile(role: UserRole.staff)];
    await pump(tester, source: source, actor: _admin);

    expect(find.text('Ravi Kumar'), findsOneWidget);
    expect(find.text('ravi@example.com'), findsOneWidget);
    expect(find.text('Staff'), findsOneWidget);
  });

  testWidgets('a super admin sees a role dropdown for each row',
      (tester) async {
    final source = FakeUserAdminSource()..rows = [_profile()];
    await pump(tester, source: source, actor: _superAdmin);

    expect(find.byType(DropdownButton<UserRole>), findsOneWidget);
    expect(find.byKey(const Key('role-dropdown-u1')), findsOneWidget);
  });

  testWidgets(
      'a plain admin sees the role as read-only text, with no dropdown at '
      'all -- the database would refuse their change anyway', (tester) async {
    final source = FakeUserAdminSource()..rows = [_profile()];
    await pump(tester, source: source, actor: _admin);

    expect(find.byType(DropdownButton<UserRole>), findsNothing);
    expect(find.byKey(const Key('role-text-u1')), findsOneWidget);
  });

  testWidgets(
      'a successful role change by a super admin calls the repository and '
      'refreshes the list', (tester) async {
    final source = FakeUserAdminSource()
      ..rows = [_profile(role: UserRole.customer)];
    await pump(tester, source: source, actor: _superAdmin);

    await tester.tap(find.byKey(const Key('role-dropdown-u1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Staff'));
    await tester.pumpAndSettle();

    expect(source.setRoleCalls, [('u1', UserRole.staff)]);
  });

  testWidgets(
      'a failed role change surfaces its message and leaves the list usable',
      (tester) async {
    final source = FakeUserAdminSource()
      ..rows = [_profile(role: UserRole.customer)]
      ..setRoleError = const NotPermitted();
    await pump(tester, source: source, actor: _superAdmin);

    await tester.tap(find.byKey(const Key('role-dropdown-u1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Staff'));
    await tester.pumpAndSettle();

    expect(find.text('You do not have access to do that.'), findsOneWidget);
    // The row -- and its control -- are still there: one failed change must
    // not blank the screen or make the rest of the roster unreachable.
    expect(find.byKey(const Key('role-dropdown-u1')), findsOneWidget);
    expect(find.text('Ravi Kumar'), findsOneWidget);
  });
}
