import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/current_resort.dart';
import 'package:pasala/data/models/food_item.dart';
import 'package:pasala/data/models/food_order.dart';
import 'package:pasala/data/models/resort_membership.dart';
import 'package:pasala/data/repositories/food_order_repository.dart';
import 'package:pasala/features/admin/kitchen_orders_screen.dart';

/// In-memory stand-in for [FoodOrderRepository], mirroring
/// `FakeTaskRepository` in `tasks_screen_test.dart`. Each row is tracked
/// against the resort it belongs to, and [allOrders] filters by it the
/// same way a real `.eq('property_id', propertyId)` query would -- so a
/// test can seed rows for two different resorts and assert only the
/// current one's reach the screen (Review Focus #1).
class FakeFoodOrderRepository implements FoodOrderRepository {
  final List<FoodOrder> store = [];
  final Map<String, String> _propertyIdByOrderId = {};
  final List<String> listedPropertyIds = [];

  void addToResort(String propertyId, FoodOrder order) {
    store.add(order);
    _propertyIdByOrderId[order.id] = propertyId;
  }

  @override
  Future<List<FoodCategory>> categories(String propertyId) async =>
      throw UnimplementedError('not used by this screen');

  @override
  Future<List<FoodItem>> items(String categoryId) async =>
      throw UnimplementedError('not used by this screen');

  @override
  Future<FoodOrder> placeOrder({
    required String reservationId,
    required Map<String, int> quantitiesByItemId,
    String? notes,
  }) async =>
      throw UnimplementedError('admin never places a food order');

  @override
  Future<List<FoodOrder>> myOrders(String reservationId) async =>
      throw UnimplementedError('not used by this screen');

  @override
  Future<List<FoodOrder>> allOrders({
    required String propertyId,
    FoodOrderStatus? status,
  }) async {
    listedPropertyIds.add(propertyId);
    return store.where((o) {
      if (_propertyIdByOrderId[o.id] != propertyId) return false;
      if (status != null && o.status != status) return false;
      return true;
    }).toList();
  }

  @override
  Future<void> updateStatus({
    required String orderId,
    required FoodOrderStatus status,
  }) async {
    final i = store.indexWhere((o) => o.id == orderId);
    final existing = store[i];
    store[i] = FoodOrder(
      id: existing.id,
      reservationId: existing.reservationId,
      status: status,
      total: existing.total,
      notes: existing.notes,
      items: existing.items,
      createdAt: existing.createdAt,
    );
  }
}

const _resort =
    ResortMembership(propertyId: 'p1', resortName: 'Pasala', role: ResortRole.staff);

class _FixedResort extends CurrentResort {
  @override
  ResortMembership? build() => _resort;
}

Widget _appFor(FakeFoodOrderRepository repo) => ProviderScope(
      overrides: [
        foodOrderRepositoryProvider.overrideWithValue(repo),
        currentResortProvider.overrideWith(_FixedResort.new),
      ],
      child: const MaterialApp(home: KitchenOrdersScreen()),
    );

void main() {
  testWidgets('shows an empty state when no orders match', (tester) async {
    await tester.pumpWidget(_appFor(FakeFoodOrderRepository()));
    await tester.pumpAndSettle();

    expect(find.text('No orders match this filter'), findsOneWidget);
  });

  testWidgets('lists an existing order with its items', (tester) async {
    final repo = FakeFoodOrderRepository()
      ..addToResort('p1', const FoodOrder(
        id: 'o1',
        reservationId: 'res-1',
        status: FoodOrderStatus.placed,
        total: 250,
        items: [
          FoodOrderItem(
            foodItemId: 'f1',
            itemName: 'Masala Chai',
            unitPrice: 50,
            quantity: 2,
            lineTotal: 100,
          ),
        ],
      ));

    await tester.pumpWidget(_appFor(repo));
    await tester.pumpAndSettle();

    expect(find.text('2 × Masala Chai'), findsOneWidget);
  });

  // Review Focus #1: a person with memberships at two resorts must never
  // see resort B's rows while working in resort A.
  testWidgets(
      'FoodOrderRepository.allOrders: rows from another resort never reach '
      'the screen', (tester) async {
    final repo = FakeFoodOrderRepository()
      ..addToResort('p1', const FoodOrder(
        id: 'o1',
        reservationId: 'res-1',
        status: FoodOrderStatus.placed,
        total: 100,
        items: [
          FoodOrderItem(
            foodItemId: 'f1',
            itemName: 'Resort A Snack',
            unitPrice: 100,
            quantity: 1,
            lineTotal: 100,
          ),
        ],
      ))
      ..addToResort('p2', const FoodOrder(
        id: 'o2',
        reservationId: 'res-2',
        status: FoodOrderStatus.placed,
        total: 100,
        items: [
          FoodOrderItem(
            foodItemId: 'f2',
            itemName: 'Resort B Snack',
            unitPrice: 100,
            quantity: 1,
            lineTotal: 100,
          ),
        ],
      ));

    await tester.pumpWidget(_appFor(repo));
    await tester.pumpAndSettle();

    expect(find.textContaining('Resort A Snack'), findsOneWidget);
    expect(find.textContaining('Resort B Snack'), findsNothing);
    expect(repo.listedPropertyIds, everyElement('p1'));
  });
}
