import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pasala/data/models/property.dart';
import 'package:pasala/data/models/slot_type.dart';
import 'package:pasala/data/models/unit.dart';
import 'package:pasala/data/repositories/catalog_repository.dart';
import 'package:pasala/features/admin/unit_form_screen.dart';
import 'package:pasala/features/admin/units_screen.dart';

/// In-memory stand-in for [CatalogRepository] so these tests never touch
/// Supabase. Dart's implicit interfaces mean `implements CatalogRepository`
/// only needs its public members covered -- the private `_db`/`_guard`
/// members live in the real class's own library and aren't part of this
/// contract from here.
class FakeCatalogRepository implements CatalogRepository {
  final List<Unit> unitsStore = [];
  int _idCounter = 0;

  @override
  Future<List<Property>> properties() async => [];

  @override
  Future<Property> property(String id) => throw UnimplementedError();

  @override
  Future<Unit> unit(String id) async =>
      unitsStore.firstWhere((u) => u.id == id);

  @override
  Future<List<Unit>> units(String propertyId) async =>
      unitsStore.where((u) => u.propertyId == propertyId).toList();

  @override
  Future<List<SlotType>> slotTypes(String propertyId) async => [];

  @override
  Future<Property> upsertProperty(Property property, {String? id}) =>
      throw UnimplementedError();

  @override
  Future<Unit> upsertUnit(Unit unit, {String? id}) async {
    final saved = Unit(
      id: id ?? 'unit-${_idCounter++}',
      propertyId: unit.propertyId,
      name: unit.name,
      description: unit.description,
      capacityBase: unit.capacityBase,
      capacityMax: unit.capacityMax,
      bookingMode: unit.bookingMode,
      isActive: unit.isActive,
    );
    unitsStore.removeWhere((u) => u.id == saved.id);
    unitsStore.add(saved);
    return saved;
  }
}

void main() {
  testWidgets('rejects max capacity below base capacity', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: UnitFormScreen(propertyId: 'a1'),
    ));

    await tester.enterText(find.byKey(const Key('unit-name')), 'Villa');
    await tester.enterText(find.byKey(const Key('unit-capacity-base')), '8');
    await tester.enterText(find.byKey(const Key('unit-capacity-max')), '4');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pump();

    expect(find.text('Max must be at least the base capacity'), findsOneWidget);
  });

  testWidgets('accepts max capacity exactly equal to base capacity', (
    tester,
  ) async {
    // The DB check constraint is `capacity_max >= capacity_base` (not `>`),
    // so equality must be a valid, error-free state -- guards against an
    // off-by-one in the validator that would reject what the database
    // happily accepts. A real GoRouter is needed because a successful
    // create navigates to the rates screen (see UnitFormScreen._save).
    final repo = FakeCatalogRepository();
    final router = GoRouter(
      initialLocation: '/form',
      routes: [
        GoRoute(
          path: '/form',
          builder: (_, _) => const UnitFormScreen(propertyId: 'a1'),
        ),
        GoRoute(
          path: '/admin/rates/:unitId',
          builder: (_, _) => const Scaffold(body: Text('Rates')),
        ),
      ],
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [catalogRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp.router(routerConfig: router),
    ));

    await tester.enterText(find.byKey(const Key('unit-name')), 'Cabin');
    await tester.enterText(find.byKey(const Key('unit-capacity-base')), '4');
    await tester.enterText(find.byKey(const Key('unit-capacity-max')), '4');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pump();

    expect(find.text('Max must be at least the base capacity'), findsNothing);
  });

  testWidgets(
      'creating a unit shows the add-a-base-rate prompt and navigates to '
      'the rates screen', (tester) async {
    final repo = FakeCatalogRepository();
    final router = GoRouter(
      initialLocation: '/admin/units/p1',
      routes: [
        GoRoute(
          path: '/admin/units/:propertyId',
          builder: (_, state) =>
              UnitsScreen(propertyId: state.pathParameters['propertyId']!),
        ),
        GoRoute(
          path: '/admin/rates/:unitId',
          builder: (_, state) =>
              Scaffold(body: Text('Rates for ${state.pathParameters['unitId']}')),
        ),
      ],
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [catalogRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('unit-name')), 'Villa');
    await tester.enterText(find.byKey(const Key('unit-capacity-base')), '2');
    await tester.enterText(find.byKey(const Key('unit-capacity-max')), '6');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(
      find.text('Unit created. Add a base rate before it can be booked.'),
      findsOneWidget,
    );
    expect(find.textContaining('Rates for unit-0'), findsOneWidget);
  });

  testWidgets(
      'editing a unit invalidates unitsProvider(propertyId) so the list '
      'reflects the change', (tester) async {
    final repo = FakeCatalogRepository();
    // Seed the store directly with a known id so the edit flow below can
    // target it without going through the create UI first.
    repo.unitsStore.add(const Unit(
      id: 'unit-0',
      propertyId: 'p1',
      name: 'Old Name',
      capacityBase: 2,
      capacityMax: 4,
      bookingMode: BookingMode.nightly,
      isActive: true,
    ));

    await tester.pumpWidget(ProviderScope(
      overrides: [catalogRepositoryProvider.overrideWithValue(repo)],
      child: const MaterialApp(home: UnitsScreen(propertyId: 'p1')),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Old Name'), findsOneWidget);

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('unit-name')), 'New Name');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    // Back on UnitsScreen: if the save hadn't invalidated
    // unitsProvider('p1'), this would still show the stale cached value
    // ("Old Name") even though the fake repository's store was mutated.
    expect(find.text('New Name'), findsOneWidget);
    expect(find.text('Old Name'), findsNothing);
  });
}
