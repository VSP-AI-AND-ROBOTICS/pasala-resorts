import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/current_resort.dart';
import 'package:pasala/data/models/app_user.dart';
import 'package:pasala/data/models/resort_membership.dart';
import 'package:pasala/data/repositories/auth_repository.dart';
import 'package:pasala/features/resorts/choose_resort_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _a = ResortMembership(propertyId: 'a', resortName: 'Pasala Farm', role: ResortRole.owner);
const _b = ResortMembership(propertyId: 'b', resortName: 'Beach Resort', role: ResortRole.staff);
const _user = AppUser(id: 'u', email: 'u@pasala.test', memberships: [_a, _b]);

void main() {
  testWidgets('lists every membership with its resort name and role label', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(ProviderScope(
      overrides: [
        currentUserProvider.overrideWith((ref) => Stream.value(_user)),
      ],
      child: const MaterialApp(home: ChooseResortScreen()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Pasala Farm'), findsOneWidget);
    expect(find.text('Owner'), findsOneWidget);
    expect(find.text('Beach Resort'), findsOneWidget);
    expect(find.text('Staff / Incharge'), findsOneWidget);
  });

  testWidgets('tapping a resort selects it as the current resort', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer(overrides: [
      currentUserProvider.overrideWith((ref) => Stream.value(_user)),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: ChooseResortScreen()),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('choose-resort-b')));
    await tester.pumpAndSettle();

    expect(container.read(currentResortProvider), _b);
  });
}
