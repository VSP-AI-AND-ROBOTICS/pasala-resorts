import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/current_resort.dart';
import 'package:pasala/data/models/app_user.dart';
import 'package:pasala/data/models/resort_membership.dart';
import 'package:pasala/data/repositories/auth_repository.dart';
import 'package:pasala/features/staff/staff_profile_screen.dart';

const _staffM =
    ResortMembership(propertyId: 'r1', resortName: 'R1', role: ResortRole.staff);
const _accountantM = ResortMembership(
    propertyId: 'r1', resortName: 'R1', role: ResortRole.accountant);

const _staff = AppUser(
  id: 'staff-1',
  email: 'staff@pasala.test',
  memberships: [_staffM],
  fullName: 'Ravi Kumar',
  phone: '+91 98765 43210',
);

class _FixedResort extends CurrentResort {
  _FixedResort(this._value);
  final ResortMembership? _value;
  @override
  ResortMembership? build() => _value;
}

Widget _appFor(AppUser? user, {ResortMembership? resort}) {
  final defaultResort =
      user == null || user.memberships.isEmpty ? null : user.memberships.first;
  return ProviderScope(
    overrides: [
      currentUserProvider.overrideWith((ref) => Stream.value(user)),
      currentResortProvider
          .overrideWith(() => _FixedResort(resort ?? defaultResort)),
    ],
    child: const MaterialApp(
      home: Scaffold(body: StaffProfileScreen()),
    ),
  );
}

void main() {
  testWidgets('shows the signed-in staff member\'s name, phone, email, and '
      'role', (tester) async {
    await tester.pumpWidget(_appFor(_staff));
    await tester.pumpAndSettle();

    expect(find.text('Ravi Kumar'), findsOneWidget);
    expect(find.text('+91 98765 43210'), findsOneWidget);
    expect(find.text('staff@pasala.test'), findsOneWidget);
    expect(find.text('Staff / Incharge'), findsOneWidget);
  });

  testWidgets('a missing name/phone shows a placeholder rather than "null"', (
    tester,
  ) async {
    const bare = AppUser(
      id: 'staff-2',
      email: 'new.staff@pasala.test',
      memberships: [_staffM],
    );
    await tester.pumpWidget(_appFor(bare));
    await tester.pumpAndSettle();

    expect(find.text('null'), findsNothing);
    expect(find.text('Not set'), findsWidgets);
  });

  testWidgets('an accountant sees their own role labelled Accountant', (
    tester,
  ) async {
    const accountant = AppUser(
      id: 'acc-1',
      email: 'accounts@pasala.test',
      memberships: [_accountantM],
      fullName: 'Meera Rao',
    );
    await tester.pumpWidget(_appFor(accountant));
    await tester.pumpAndSettle();

    expect(find.text('Accountant'), findsOneWidget);
  });
}
