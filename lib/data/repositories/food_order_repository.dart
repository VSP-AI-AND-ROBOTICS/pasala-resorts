import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors.dart';
import '../../core/supabase_client.dart';
import '../models/food_item.dart';
import '../models/food_order.dart';

class FoodOrderRepository {
  FoodOrderRepository(this._db);
  final SupabaseClient _db;

  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } catch (e) {
      throw mapPostgrestError(e);
    }
  }

  Future<List<FoodCategory>> categories(String propertyId) => _guard(() async {
        final rows = await _db
            .from('food_categories')
            .select()
            .eq('property_id', propertyId)
            .order('sort_order');
        return rows.map((e) => FoodCategory.fromJson(e)).toList();
      });

  Future<List<FoodItem>> items(String categoryId) => _guard(() async {
        final rows = await _db
            .from('food_items')
            .select()
            .eq('category_id', categoryId)
            .order('name');
        return rows.map((e) => FoodItem.fromJson(e)).toList();
      });

  /// `p_items` is `[{"food_item_id": id, "quantity": qty}, ...]` -- prices
  /// are never sent, the server prices every line from `food_items.price`.
  Future<FoodOrder> placeOrder({
    required String reservationId,
    required Map<String, int> quantitiesByItemId,
    String? notes,
  }) =>
      _guard(() async {
        final row = await _db.rpc('place_food_order', params: {
          'p_reservation_id': reservationId,
          'p_items': quantitiesByItemId.entries
              .map((e) => {'food_item_id': e.key, 'quantity': e.value})
              .toList(),
          'p_notes': notes,
        });
        return FoodOrder.fromJson(row as Map<String, dynamic>);
      });

  Future<List<FoodOrder>> myOrders(String reservationId) => _guard(() async {
        final rows = await _db
            .from('food_orders')
            .select('*, food_order_items(*)')
            .eq('reservation_id', reservationId)
            .order('created_at', ascending: false);
        return rows.map((e) => FoodOrder.fromJson(e)).toList();
      });

  /// All orders, optionally narrowed by status -- the kitchen queue.
  Future<List<FoodOrder>> allOrders({FoodOrderStatus? status}) => _guard(() async {
        dynamic query = _db.from('food_orders').select('*, food_order_items(*)');
        if (status != null) query = query.eq('status', foodOrderStatusToDb(status));
        final rows = await query.order('created_at', ascending: false) as List;
        return rows.map((e) => FoodOrder.fromJson(e as Map<String, dynamic>)).toList();
      });

  Future<void> updateStatus({
    required String orderId,
    required FoodOrderStatus status,
  }) =>
      _guard(() async {
        await _db
            .from('food_orders')
            .update({'status': foodOrderStatusToDb(status)}).eq('id', orderId);
      });
}

final foodOrderRepositoryProvider = Provider<FoodOrderRepository>(
  (ref) => FoodOrderRepository(ref.watch(supabaseProvider)),
);

final foodCategoriesProvider =
    FutureProvider.family<List<FoodCategory>, String>(
  (ref, propertyId) =>
      ref.watch(foodOrderRepositoryProvider).categories(propertyId),
);

final foodItemsProvider = FutureProvider.family<List<FoodItem>, String>(
  (ref, categoryId) => ref.watch(foodOrderRepositoryProvider).items(categoryId),
);

final myFoodOrdersProvider = FutureProvider.family<List<FoodOrder>, String>(
  (ref, reservationId) =>
      ref.watch(foodOrderRepositoryProvider).myOrders(reservationId),
);

final allFoodOrdersProvider =
    FutureProvider.family<List<FoodOrder>, FoodOrderStatus?>(
  (ref, status) =>
      ref.watch(foodOrderRepositoryProvider).allOrders(status: status),
);
