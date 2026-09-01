import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/data/models/food_sale.dart';
import 'package:pasala/data/models/property.dart';
import 'package:pasala/data/repositories/food_sale_repository.dart';
import 'package:pasala/features/browse/providers.dart';
import 'package:pasala/features/owner/food_sales_screen.dart';

/// In-memory stand-in for [FoodSaleRepository], mirroring
/// `FakeTaskRepository` in `tasks_screen_test.dart`.
class FakeFoodSaleRepository implements FoodSaleRepository {
  final List<FoodSale> store = [];
  final List<String> deletedIds = [];
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
    required DateTime from,
    required DateTime to,
    SaleCategory? category,
  }) async =>
      store.where((s) {
        if (category != null && s.category != category) return false;
        return _inRange(s.saleDate, from, to);
      }).toList();

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

const _property = Property(
  id: 'p1',
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

Widget _appFor(FakeFoodSaleRepository repo) => ProviderScope(
      overrides: [
        foodSaleRepositoryProvider.overrideWithValue(repo),
        propertiesProvider.overrideWith((ref) async => [_property]),
      ],
      child: const MaterialApp(home: FoodSalesScreen()),
    );

void main() {
  testWidgets('shows an empty state when no sales exist yet', (tester) async {
    await tester.pumpWidget(_appFor(FakeFoodSaleRepository()));
    await tester.pumpAndSettle();

    expect(find.text('No sales logged in this period'), findsOneWidget);
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
    expect(find.text('Breakfast platter'), findsOneWidget);
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
}
