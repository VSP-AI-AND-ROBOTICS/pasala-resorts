import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pasala/core/current_resort.dart';
import 'package:pasala/data/models/app_user.dart';
import 'package:pasala/data/models/property.dart';
import 'package:pasala/data/models/resort_membership.dart';
import 'package:pasala/data/repositories/auth_repository.dart';
import 'package:pasala/features/admin/property_form_screen.dart';
import 'package:pasala/features/browse/providers.dart' show propertyProvider;
import 'package:shared_preferences/shared_preferences.dart';

const _propertyA = Property(
  id: 'resort-a',
  name: 'Pasala Farm House',
  slug: 'pasala-farm-house',
  description: null,
  address: null,
  images: [],
  amenities: [],
  checkInTime: '14:00',
  checkOutTime: '11:00',
  isActive: true,
);

const _propertyB = Property(
  id: 'resort-b',
  name: 'Beach Resort',
  slug: 'beach-resort',
  description: null,
  address: null,
  images: [],
  amenities: [],
  checkInTime: '14:00',
  checkOutTime: '11:00',
  isActive: true,
);

const _membership = ResortMembership(
  propertyId: 'resort-a',
  resortName: 'Pasala Farm House',
  role: ResortRole.admin,
);
const _admin = AppUser(
  id: 'admin-1',
  email: 'admin@pasala.test',
  memberships: [_membership],
);

/// Resolves `currentResortProvider` to a fixed membership synchronously, on
/// the very first build -- unlike overriding `currentUserProvider` with a
/// `Stream`, which stays in its `loading` state until at least one
/// microtask has run, and `AdminPropertiesScreen` `!`-asserts a non-null
/// current resort on every build per the tenancy design (a screen reached
/// without one is impossible once the router's redirect is in place).
class _FixedCurrentResort extends CurrentResort {
  _FixedCurrentResort(this._value);
  final ResortMembership _value;
  @override
  ResortMembership? build() => _value;
}

void main() {
  group('AdminPropertiesScreen', () {
    Widget app() {
      SharedPreferences.setMockInitialValues({});
      final router = GoRouter(
        initialLocation: '/admin/properties',
        routes: [
          GoRoute(
              path: '/admin/properties',
              builder: (_, _) => const AdminPropertiesScreen()),
          GoRoute(
              path: '/admin/units/:propertyId',
              builder: (_, state) => Text(
                  'UNITS FOR ${state.pathParameters['propertyId']}')),
        ],
      );
      return ProviderScope(
        overrides: [
          currentUserProvider.overrideWith((ref) => Stream.value(_admin)),
          currentResortProvider.overrideWith(() => _FixedCurrentResort(_membership)),
          propertyProvider('resort-a').overrideWith((ref) async => _propertyA),
          propertyProvider('resort-b').overrideWith((ref) async => _propertyB),
        ],
        child: MaterialApp.router(routerConfig: router),
      );
    }

    // Review Focus #1: an admin with memberships at two resorts must see
    // only the current resort's property here, never another resort's.
    testWidgets('shows only the current resort\'s property', (tester) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();

      expect(find.text('Pasala Farm House'), findsOneWidget);
      expect(find.text('Beach Resort'), findsNothing);
    });

    testWidgets('has no action to create another property', (tester) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();

      expect(find.byType(FloatingActionButton), findsNothing);
    });

    testWidgets('tapping the card opens the current resort\'s units',
        (tester) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Pasala Farm House'));
      await tester.pumpAndSettle();

      expect(find.text('UNITS FOR resort-a'), findsOneWidget);
    });
  });

  // The property form has enough fields (name, slug, description, address,
  // amenities, two time pickers, an active switch, plus Save) that it
  // overflows the default 800x600 test surface and its Save button sits
  // below the fold -- inside a scrollable ListView, widgets beyond the
  // viewport aren't built into the element tree at all, so `find` can't see
  // Save without either scrolling or a taller surface. A taller surface
  // keeps these tests focused on validation, not scroll mechanics.
  Future<void> useTallSurface(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('rejects an empty name', (tester) async {
    await useTallSurface(tester);
    await tester.pumpWidget(const MaterialApp(home: PropertyFormScreen()));

    // Slug is filled so the name validator is isolated as the failure cause.
    await tester.enterText(find.byKey(const Key('property-slug')), 'riverside');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pump();

    expect(find.text('Enter a name'), findsOneWidget);
  });

  testWidgets('rejects an empty slug', (tester) async {
    await useTallSurface(tester);
    await tester.pumpWidget(const MaterialApp(home: PropertyFormScreen()));

    await tester.enterText(
        find.byKey(const Key('property-name')), 'Pasala Riverside');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pump();

    expect(find.text('Enter a slug'), findsOneWidget);
  });
}
