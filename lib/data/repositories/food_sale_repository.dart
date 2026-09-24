import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors.dart';
import '../../core/supabase_client.dart';
import '../models/food_sale.dart';

String _d(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// The (date-range, category) an Owner screen wants to see -- `category:
/// null` means "both food and activity." A record, not positional params,
/// so `FutureProvider.family` can key on it directly.
typedef FoodSaleFilter = ({
  String propertyId,
  DateTime from,
  DateTime to,
  SaleCategory? category,
});

class FoodSaleRepository {
  FoodSaleRepository(this._db);
  final SupabaseClient _db;

  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } catch (e) {
      throw mapPostgrestError(e);
    }
  }

  /// A direct table select -- staff-or-above can read every sale (this is
  /// a front-desk log, not financial data), so no RPC/embed is needed the
  /// way `TaskRepository.list` needs one for assignee names.
  Future<List<FoodSale>> list({
    required String propertyId,
    required DateTime from,
    required DateTime to,
    SaleCategory? category,
  }) =>
      _guard(() async {
        dynamic query = _db
            .from('food_activity_sales')
            .select()
            .eq('property_id', propertyId)
            .gte('sale_date', _d(from))
            .lte('sale_date', _d(to));
        if (category != null) {
          query = query.eq('category', saleCategoryToDb(category));
        }
        final rows =
            await query.order('sale_date', ascending: false) as List;
        return rows.map((e) => FoodSale.fromJson(e as Map<String, dynamic>)).toList();
      });

  Future<void> create(FoodSale sale) => _guard(() async {
        await _db.from('food_activity_sales').insert(sale.toInsert());
      });

  /// Admin-only in practice -- `food_activity_sales_admin_write` rejects
  /// anyone else, matching zero rows changed rather than throwing (see
  /// `properties_write`'s same shape in `0003_properties_units.sql`).
  Future<void> update(String id, FoodSale sale) => _guard(() async {
        await _db.from('food_activity_sales').update(sale.toInsert()).eq('id', id);
      });

  Future<void> delete(String id) => _guard(() async {
        await _db.from('food_activity_sales').delete().eq('id', id);
      });
}

final foodSaleRepositoryProvider = Provider<FoodSaleRepository>(
  (ref) => FoodSaleRepository(ref.watch(supabaseProvider)),
);

final foodSalesProvider = FutureProvider.family<List<FoodSale>, FoodSaleFilter>(
  (ref, filter) => ref.watch(foodSaleRepositoryProvider).list(
        propertyId: filter.propertyId,
        from: filter.from,
        to: filter.to,
        category: filter.category,
      ),
);
