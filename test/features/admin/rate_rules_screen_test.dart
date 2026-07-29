import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/data/models/rate_rule.dart';
import 'package:pasala/data/repositories/rate_repository.dart';
import 'package:pasala/features/admin/rate_rules_screen.dart';

/// In-memory stand-in for [RateRepository], mirroring the
/// `FakeCatalogRepository` pattern from `unit_form_test.dart`. Dart's
/// implicit interfaces mean `implements RateRepository` only needs the
/// public members covered -- the private `_db`/`_guard` live in the real
/// class's own library.
class FakeRateRepository implements RateRepository {
  final List<RateRule> store = [];
  final List<RateRule> upsertCalls = [];
  int _idCounter = 0;

  @override
  Future<List<RateRule>> forUnit(String unitId) async =>
      store.where((r) => r.unitId == unitId).toList();

  @override
  Future<RateRule> upsert(RateRule rule, {String? id}) async {
    upsertCalls.add(rule);
    final saved = RateRule(
      id: id ?? 'rate-${_idCounter++}',
      unitId: rule.unitId,
      kind: rule.kind,
      label: rule.label,
      slotTypeId: rule.slotTypeId,
      validFrom: rule.validFrom,
      validTo: rule.validTo,
      weekdays: rule.weekdays,
      price: rule.price,
      extraGuestPrice: rule.extraGuestPrice,
      cleaningFee: rule.cleaningFee,
      priority: rule.priority,
    );
    store.removeWhere((r) => r.id == saved.id);
    store.add(saved);
    return saved;
  }

  @override
  Future<void> delete(String id) async {
    store.removeWhere((r) => r.id == id);
  }
}

void main() {
  // The form has enough fields (kind selector, five text fields, a date
  // range tile, seven weekday chips, plus Save) that it overflows the
  // default 800x600 test surface -- see `property_form_test.dart` for the
  // same issue and fix.
  Future<void> useTallSurface(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  group('validateRateRuleDates', () {
    test('an override with no date range is rejected', () {
      final error = validateRateRuleDates(
        kind: RateKind.override_,
        validFrom: null,
        validTo: null,
      );
      expect(error, isNotNull);
    });

    test('an override with only one date is rejected', () {
      final error = validateRateRuleDates(
        kind: RateKind.override_,
        validFrom: DateTime(2026, 11, 6),
        validTo: null,
      );
      expect(error, isNotNull);
    });

    test('valid_to before valid_from is rejected regardless of kind', () {
      final error = validateRateRuleDates(
        kind: RateKind.base,
        validFrom: DateTime(2026, 11, 12),
        validTo: DateTime(2026, 11, 6),
      );
      expect(error, isNotNull);
    });

    test('a base rule with no date range at all is fine', () {
      expect(
        validateRateRuleDates(kind: RateKind.base, validFrom: null, validTo: null),
        isNull,
      );
    });

    test('an override with a valid ordered range is fine', () {
      expect(
        validateRateRuleDates(
          kind: RateKind.override_,
          validFrom: DateTime(2026, 11, 6),
          validTo: DateTime(2026, 11, 12),
        ),
        isNull,
      );
    });
  });

  testWidgets(
      'saving an override without a date range is blocked with a clear '
      'message before it reaches the repository', (tester) async {
    await useTallSurface(tester);
    final repo = FakeRateRepository();

    await tester.pumpWidget(ProviderScope(
      overrides: [rateRepositoryProvider.overrideWithValue(repo)],
      child: const MaterialApp(home: RateRuleFormScreen(unitId: 'u1')),
    ));

    await tester.tap(find.text('Override'));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('rate-price')), '9000');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pump();

    expect(
      find.text('Override rules need both a start and end date.'),
      findsOneWidget,
    );
    expect(repo.upsertCalls, isEmpty);
  });

  testWidgets(
      'selecting Saturday and Sunday saves weekdays [6, 7] (Monday-first, '
      'matching ISO weekdays)', (tester) async {
    await useTallSurface(tester);
    final repo = FakeRateRepository();

    await tester.pumpWidget(ProviderScope(
      overrides: [rateRepositoryProvider.overrideWithValue(repo)],
      child: const MaterialApp(home: RateRuleFormScreen(unitId: 'u1')),
    ));

    await tester.enterText(find.byKey(const Key('rate-price')), '6300');
    await tester.tap(find.byKey(const Key('weekday-6')));
    await tester.tap(find.byKey(const Key('weekday-7')));
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pump();

    expect(repo.upsertCalls, hasLength(1));
    expect(repo.upsertCalls.single.weekdays, [6, 7]);
  });

  testWidgets(
      'a rule loaded with weekdays [6, 7] shows exactly Sat and Sun selected',
      (tester) async {
    await useTallSurface(tester);
    final repo = FakeRateRepository();
    const existing = RateRule(
      id: 'r1',
      unitId: 'u1',
      kind: RateKind.weekend,
      price: 6300,
      extraGuestPrice: 800,
      cleaningFee: 600,
      priority: 10,
      weekdays: [6, 7],
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [rateRepositoryProvider.overrideWithValue(repo)],
      child: const MaterialApp(
        home: RateRuleFormScreen(unitId: 'u1', existing: existing),
      ),
    ));

    FilterChip chipFor(int day) =>
        tester.widget<FilterChip>(find.byKey(Key('weekday-$day')));

    for (var day = 1; day <= 5; day++) {
      expect(chipFor(day).selected, isFalse, reason: 'weekday $day');
    }
    expect(chipFor(6).selected, isTrue, reason: 'Saturday (6)');
    expect(chipFor(7).selected, isTrue, reason: 'Sunday (7)');
  });

  testWidgets('a rule with no weekdays selected saves null, not []',
      (tester) async {
    await useTallSurface(tester);
    final repo = FakeRateRepository();

    await tester.pumpWidget(ProviderScope(
      overrides: [rateRepositoryProvider.overrideWithValue(repo)],
      child: const MaterialApp(home: RateRuleFormScreen(unitId: 'u1')),
    ));

    await tester.enterText(find.byKey(const Key('rate-price')), '5000');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pump();

    expect(repo.upsertCalls, hasLength(1));
    final saved = repo.upsertCalls.single;
    expect(saved.weekdays, isEmpty);
    // The resolver treats `weekdays is null` as "matches every day" and
    // `{}` as "matches nothing" -- toInsert() must collapse the empty list
    // to null, not send an empty array.
    expect(saved.toInsert()['weekdays'], isNull);
  });

  group('RateRulesScreen delete confirmation', () {
    const rule = RateRule(
      id: 'r1',
      unitId: 'u1',
      kind: RateKind.base,
      label: 'Weekday',
      price: 4500,
      extraGuestPrice: 800,
      cleaningFee: 600,
      priority: 0,
      weekdays: [],
    );

    Future<void> openDeleteMenu(WidgetTester tester) async {
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
    }

    testWidgets(
        'the confirmation dialog names the rule being deleted',
        (tester) async {
      final repo = FakeRateRepository()..store.add(rule);

      await tester.pumpWidget(ProviderScope(
        overrides: [rateRepositoryProvider.overrideWithValue(repo)],
        child: const MaterialApp(home: RateRulesScreen(unitId: 'u1')),
      ));
      await tester.pumpAndSettle();

      await openDeleteMenu(tester);

      expect(find.text('Delete "Weekday"?'), findsOneWidget);
    });

    testWidgets(
        'dismissing the confirmation dialog does NOT delete the rule',
        (tester) async {
      final repo = FakeRateRepository()..store.add(rule);

      await tester.pumpWidget(ProviderScope(
        overrides: [rateRepositoryProvider.overrideWithValue(repo)],
        child: const MaterialApp(home: RateRulesScreen(unitId: 'u1')),
      ));
      await tester.pumpAndSettle();

      await openDeleteMenu(tester);
      await tester.tap(find.byKey(const Key('keep-rule-button')));
      await tester.pumpAndSettle();

      expect(repo.store, hasLength(1));
      expect(find.text('Weekday'), findsOneWidget);
    });

    testWidgets(
        'confirming the dialog deletes the rule',
        (tester) async {
      final repo = FakeRateRepository()..store.add(rule);

      await tester.pumpWidget(ProviderScope(
        overrides: [rateRepositoryProvider.overrideWithValue(repo)],
        child: const MaterialApp(home: RateRulesScreen(unitId: 'u1')),
      ));
      await tester.pumpAndSettle();

      await openDeleteMenu(tester);
      await tester.tap(find.byKey(const Key('confirm-delete-rule-button')));
      await tester.pumpAndSettle();

      expect(repo.store, isEmpty);
    });
  });
}
