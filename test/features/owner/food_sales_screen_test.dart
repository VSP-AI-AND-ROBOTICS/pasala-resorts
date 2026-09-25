import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pasala/core/current_resort.dart';
import 'package:pasala/data/models/app_user.dart';
import 'package:pasala/data/models/food_sale.dart';
import 'package:pasala/data/models/resort_membership.dart';
import 'package:pasala/data/models/payment_method.dart';
import 'package:pasala/data/repositories/finance_repository.dart';
import 'package:pasala/data/repositories/food_sale_repository.dart';
import 'package:pasala/features/finance/providers.dart';
import 'package:pasala/features/owner/food_sales_screen.dart';

import '../../support/fake_finance_source.dart';

class _FixedResort extends CurrentResort {
  _FixedResort(this._value);
  final ResortMembership? _value;
  @override
  ResortMembership? build() => _value;
}

/// In-memory stand-in for [FoodSaleRepository], mirroring
/// `FakeTaskRepository` in `tasks_screen_test.dart`.
class FakeFoodSaleRepository implements FoodSaleRepository {
  final List<FoodSale> store = [];
  final List<String> deletedIds = [];
  final List<String> listedPropertyIds = [];
  int _idCounter = 0;

  /// Compares dates only, ignoring time-of-day -- matching the real
  /// [FoodSaleRepository.list], which sends `_d()`-truncated `YYYY-MM-DD`
  /// strings to Postgres's `date` columns. Comparing full `DateTime`s here
  /// instead would make this fake diverge from production behaviour right
  /// on the last day of any month, when "now" (a fixture's `saleDate`) has
  /// a time-of-day later than the filter's midnight-`to` boundary.
  bool _inRange(DateTime date, DateTime from, DateTime to) {
    final d = DateTime(date.year, date.month, date.day);
    final f = DateTime(from.year, from.month, from.day);
    final t = DateTime(to.year, to.month, to.day);
    return !d.isBefore(f) && !d.isAfter(t);
  }

  @override
  Future<List<FoodSale>> list({
    required String propertyId,
    required DateTime from,
    required DateTime to,
    SaleCategory? category,
  }) async {
    listedPropertyIds.add(propertyId);
    return store.where((s) {
      if (s.propertyId != propertyId) return false;
      if (category != null && s.category != category) return false;
      return _inRange(s.saleDate, from, to);
    }).toList();
  }

  @override
  Future<void> create(FoodSale sale) async {
    store.add(FoodSale(
      id: 'sale-${_idCounter++}',
      propertyId: sale.propertyId,
      saleDate: sale.saleDate,
      category: sale.category,
      itemName: sale.itemName,
      quantity: sale.quantity,
      unitPrice: sale.unitPrice,
      amount: sale.amount,
      paymentMethod: sale.paymentMethod,
      notes: sale.notes,
    ));
  }

  @override
  Future<void> update(String id, FoodSale sale) async {
    final i = store.indexWhere((s) => s.id == id);
    store[i] = FoodSale(
      id: id,
      propertyId: sale.propertyId,
      saleDate: sale.saleDate,
      category: sale.category,
      itemName: sale.itemName,
      quantity: sale.quantity,
      unitPrice: sale.unitPrice,
      amount: sale.amount,
      paymentMethod: sale.paymentMethod,
      notes: sale.notes,
    );
  }

  @override
  Future<void> delete(String id) async {
    deletedIds.add(id);
    store.removeWhere((s) => s.id == id);
  }
}

const _adminM =
    ResortMembership(propertyId: 'p1', resortName: 'Pasala', role: ResortRole.admin);
const _staffM =
    ResortMembership(propertyId: 'p1', resortName: 'Pasala', role: ResortRole.staff);

const _admin = AppUser(
  id: 'admin-1',
  email: 'admin@pasala.test',
  memberships: [_adminM],
  fullName: 'Asha Admin',
);

const _staff = AppUser(
  id: 'staff-1',
  email: 'staff@pasala.test',
  memberships: [_staffM],
  fullName: 'Sita Staff',
);

Widget _appFor(
  FakeFoodSaleRepository repo, {
  AppUser user = _admin,
  ResortMembership? resort,
  FakeFinanceSource? finance,
}) =>
    ProviderScope(
      overrides: [
        foodSaleRepositoryProvider.overrideWithValue(repo),
        currentResortProvider.overrideWith(
            () => _FixedResort(resort ?? user.memberships.first)),
        financeSourceProvider.overrideWithValue(finance ?? FakeFinanceSource()),
      ],
      child: MaterialApp(
        home: const FoodSalesScreen(),
        // Stands in for an open Finance screen, which keeps its summary alive.
        builder: (context, child) => Stack(children: [
          child!,
          Consumer(builder: (_, ref, _) {
            ref.watch(financeSummaryProvider('p1'));
            return const SizedBox.shrink();
          }),
        ]),
      ),
    );

Future<void> _fillNewSale(WidgetTester tester) async {
  await tester.tap(find.byType(FloatingActionButton));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('sale-form-item-name')), 'Breakfast platter');
  await tester.enterText(find.byKey(const Key('sale-form-quantity')), '2');
  await tester.enterText(find.byKey(const Key('sale-form-unit-price')), '300');
}

void main() {
  // I7: food_activity_sales_read/_insert (0026_food_activity_sales.sql)
  // grant staff-or-above read+add, but _admin_write/_admin_delete stay
  // admin-only -- a plain staff member can log a sale (the FAB still
  // works) but must never see an edit/delete menu that would just fail
  // against RLS.
  testWidgets('a staff member can log a sale but sees no edit/delete menu', (
    tester,
  ) async {
    final repo = FakeFoodSaleRepository()
      ..store.add(FoodSale(
        id: 's1',
        propertyId: 'p1',
        saleDate: DateTime.now(),
        category: SaleCategory.food,
        itemName: 'Breakfast platter',
        quantity: 2,
        unitPrice: 300,
        amount: 600,
      ));

    await tester.pumpWidget(_appFor(repo, user: _staff));
    await tester.pumpAndSettle();

    expect(find.text('Breakfast platter'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(find.byType(PopupMenuButton<String>), findsNothing);
  });

  testWidgets('shows an empty state when no sales exist yet', (tester) async {
    await tester.pumpWidget(_appFor(FakeFoodSaleRepository()));
    await tester.pumpAndSettle();

    expect(find.text('No sales logged in this period'), findsOneWidget);
  });

  testWidgets('a sale shows the tax it includes', (tester) async {
    final repo = FakeFoodSaleRepository()
      ..store.add(FoodSale(
        id: 's1',
        propertyId: 'p1',
        saleDate: DateTime.now(),
        category: SaleCategory.food,
        itemName: 'Walk-in thali',
        quantity: 1,
        unitPrice: 210,
        amount: 210,
        taxPct: 12,
        taxAmount: 22.5,
      ))
      ..store.add(FoodSale(
        id: 's2',
        propertyId: 'p1',
        saleDate: DateTime.now(),
        category: SaleCategory.food,
        itemName: 'Tea',
        quantity: 1,
        unitPrice: 20,
        amount: 20,
      ));

    await tester.pumpWidget(_appFor(repo));
    await tester.pumpAndSettle();

    expect(
        find.descendant(
            of: find.byKey(const Key('sale-row-s1')),
            matching: find.textContaining('Includes tax ₹22.50')),
        findsOneWidget);
    // A sale without tax (logged at 0%, or before 0053) says nothing.
    expect(
        find.descendant(
            of: find.byKey(const Key('sale-row-s2')),
            matching: find.textContaining('Includes tax')),
        findsNothing);
  });

  testWidgets('the FAB opens the create-sale form', (tester) async {
    await tester.pumpWidget(_appFor(FakeFoodSaleRepository()));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    expect(find.text('New sale'), findsOneWidget);
    expect(find.byKey(const Key('sale-form-item-name')), findsOneWidget);
  });

  testWidgets('filling the create form and saving adds a sale to the list', (
    tester,
  ) async {
    final repo = FakeFoodSaleRepository();
    await tester.pumpWidget(_appFor(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('sale-form-item-name')), 'Breakfast platter');
    await tester.enterText(find.byKey(const Key('sale-form-quantity')), '2');
    await tester.enterText(find.byKey(const Key('sale-form-unit-price')), '300');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(repo.store, hasLength(1));
    expect(repo.store.single.amount, 600);
    expect(repo.store.single.propertyId, 'p1');
    expect(find.text('Breakfast platter'), findsOneWidget);
  });

  // Review Focus #1: a sale logged at a different resort must never show
  // up while working in this resort.
  testWidgets('a sale logged at a different resort never appears here', (
    tester,
  ) async {
    const otherResort = ResortMembership(
        propertyId: 'p2', resortName: 'Other Resort', role: ResortRole.admin);
    final repo = FakeFoodSaleRepository()
      ..store.add(FoodSale(
        id: 's1',
        propertyId: 'p1',
        saleDate: DateTime.now(),
        category: SaleCategory.food,
        itemName: 'Pasala breakfast platter',
        quantity: 2,
        unitPrice: 300,
        amount: 600,
      ))
      ..store.add(FoodSale(
        id: 's2',
        propertyId: 'p2',
        saleDate: DateTime.now(),
        category: SaleCategory.food,
        itemName: 'Other resort breakfast platter',
        quantity: 1,
        unitPrice: 300,
        amount: 300,
      ));

    await tester.pumpWidget(_appFor(repo, resort: otherResort));
    await tester.pumpAndSettle();

    expect(repo.listedPropertyIds, everyElement('p2'));
    expect(find.text('Other resort breakfast platter'), findsOneWidget);
    expect(find.text('Pasala breakfast platter'), findsNothing);
  });

  testWidgets('confirming delete removes the sale', (tester) async {
    final repo = FakeFoodSaleRepository()
      ..store.add(FoodSale(
        id: 's1',
        propertyId: 'p1',
        saleDate: DateTime.now(),
        category: SaleCategory.food,
        itemName: 'Breakfast platter',
        quantity: 2,
        unitPrice: 300,
        amount: 600,
      ));

    await tester.pumpWidget(_appFor(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(repo.deletedIds, ['s1']);
    expect(find.text('Breakfast platter'), findsNothing);
  });

  // E2E-shaped bug: /owner/food-sales lives inside the router's ShellRoute,
  // so the screen's own context resolves to the shell navigator while
  // showDialog puts the confirm dialog on the root one. The dialog's
  // buttons must pop the dialog, not the page (mirrors
  // lib/features/admin/tasks_screen.dart's ShellRoute regression test).
  testWidgets(
      'confirming delete inside a ShellRoute closes the dialog, not the page',
      (tester) async {
    final repo = FakeFoodSaleRepository()
      ..store.add(FoodSale(
        id: 's1',
        propertyId: 'p1',
        saleDate: DateTime.now(),
        category: SaleCategory.food,
        itemName: 'Breakfast platter',
        quantity: 2,
        unitPrice: 300,
        amount: 600,
      ));
    final router = GoRouter(
      initialLocation: '/owner/food-sales',
      routes: [
        ShellRoute(
          builder: (_, _, child) => Scaffold(body: child),
          routes: [
            GoRoute(path: '/owner', builder: (_, _) => const Text('Owner home')),
            GoRoute(
                path: '/owner/food-sales', builder: (_, _) => const FoodSalesScreen()),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        foodSaleRepositoryProvider.overrideWithValue(repo),
        currentResortProvider.overrideWith(() => _FixedResort(_admin.memberships.first)),
        financeSourceProvider.overrideWithValue(FakeFinanceSource()),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        builder: (context, child) => Stack(children: [
          child!,
          Consumer(builder: (_, ref, _) {
            ref.watch(financeSummaryProvider('p1'));
            return const SizedBox.shrink();
          }),
        ]),
      ),
    ));
    await tester.pumpAndSettle();

    // Cancel first: the dialog closes and the page stays.
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(FoodSalesScreen), findsOneWidget);
    expect(repo.deletedIds, isEmpty);

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(FoodSalesScreen), findsOneWidget);
    expect(repo.deletedIds, ['s1']);
    expect(find.text('Breakfast platter'), findsNothing);
  });

  group('payment method', () {
    testWidgets('a new sale is Cash unless another method is picked', (tester) async {
      final repo = FakeFoodSaleRepository();
      await tester.pumpWidget(_appFor(repo));
      await tester.pumpAndSettle();

      await _fillNewSale(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(repo.store.single.paymentMethod, PaymentMethod.cash);
    });

    testWidgets('the form records the method picked', (tester) async {
      final repo = FakeFoodSaleRepository();
      await tester.pumpWidget(_appFor(repo));
      await tester.pumpAndSettle();

      await _fillNewSale(tester);
      await tester.tap(find.byKey(const Key('sale-form-method')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('UPI').last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(repo.store.single.paymentMethod, PaymentMethod.upi);
    });

    testWidgets('the method list offers the five desk methods and never Online',
        (tester) async {
      await tester.pumpWidget(_appFor(FakeFoodSaleRepository()));
      await tester.pumpAndSettle();

      await _fillNewSale(tester);
      await tester.tap(find.byKey(const Key('sale-form-method')));
      await tester.pumpAndSettle();

      for (final m in PaymentMethod.desk) {
        expect(find.text(m.label), findsWidgets, reason: m.label);
      }
      expect(find.text('Online'), findsNothing);
    });

    testWidgets('each sale shows its method in the list', (tester) async {
      final repo = FakeFoodSaleRepository()
        ..store.add(FoodSale(
          id: 's1',
          propertyId: 'p1',
          saleDate: DateTime.now(),
          category: SaleCategory.activity,
          itemName: 'Pool pass',
          quantity: 1,
          unitPrice: 300,
          amount: 300,
          paymentMethod: PaymentMethod.upi,
        ));
      await tester.pumpWidget(_appFor(repo));
      await tester.pumpAndSettle();

      expect(find.textContaining('Activity · UPI · '), findsOneWidget);
    });

    // Review Focus 3.
    testWidgets('editing a sale keeps its payment method', (tester) async {
      final repo = FakeFoodSaleRepository()
        ..store.add(FoodSale(
          id: 's1',
          propertyId: 'p1',
          saleDate: DateTime.now(),
          category: SaleCategory.food,
          itemName: 'Breakfast platter',
          quantity: 2,
          unitPrice: 300,
          amount: 600,
          paymentMethod: PaymentMethod.bankTransfer,
        ));
      await tester.pumpWidget(_appFor(repo));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('sale-form-quantity')), '3');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(repo.store.single.quantity, 3);
      expect(repo.store.single.paymentMethod, PaymentMethod.bankTransfer);
    });

    testWidgets('saving a sale refetches the finance figures', (tester) async {
      final finance = FakeFinanceSource();
      await tester.pumpWidget(_appFor(FakeFoodSaleRepository(), finance: finance));
      await tester.pumpAndSettle();
      final before = finance.summaryCalls.length;

      await _fillNewSale(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(finance.summaryCalls.length, greaterThan(before));
    });
  });
}
