import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/current_resort.dart';
import '../../core/errors.dart';
import '../../core/format.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/failure_view.dart';
import '../../data/models/food_order.dart';
import '../../data/repositories/food_order_repository.dart';

/// `/admin/kitchen-orders` (also reachable by plain staff, see
/// `/staff/food-orders`) -- every food order by status, with a status
/// dropdown per row for kitchen fulfilment.
class KitchenOrdersScreen extends ConsumerStatefulWidget {
  const KitchenOrdersScreen({super.key});

  @override
  ConsumerState<KitchenOrdersScreen> createState() => _KitchenOrdersScreenState();
}

class _KitchenOrdersScreenState extends ConsumerState<KitchenOrdersScreen> {
  FoodOrderStatus? _filter;

  Future<void> _updateStatus(
    String orderId,
    FoodOrderStatus status,
    AllFoodOrdersFilter filter,
  ) async {
    try {
      await ref.read(foodOrderRepositoryProvider).updateStatus(orderId: orderId, status: status);
      ref.invalidate(allFoodOrdersProvider(filter));
    } on BookingFailure catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(FailureView.messageFor(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final propertyId = ref.watch(currentResortProvider)!.propertyId;
    final filter = (propertyId: propertyId, status: _filter);
    final ordersAsync = ref.watch(allFoodOrdersProvider(filter));

    return Scaffold(
      appBar: AppBar(title: const Text('Kitchen Orders')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(Spacing.md),
            child: DropdownButtonFormField<FoodOrderStatus?>(
              initialValue: _filter,
              decoration: const InputDecoration(labelText: 'Status'),
              items: [
                const DropdownMenuItem(value: null, child: Text('All')),
                for (final s in FoodOrderStatus.values)
                  DropdownMenuItem(value: s, child: Text(foodOrderStatusLabel(s))),
              ],
              onChanged: (value) => setState(() => _filter = value),
            ),
          ),
          Expanded(
            child: AsyncView(
              value: ordersAsync,
              onRetry: () => ref.invalidate(allFoodOrdersProvider(filter)),
              empty: () => const EmptyState(
                icon: Icons.restaurant_outlined,
                title: 'No orders match this filter',
              ),
              data: (orders) => ListView.builder(
                padding: const EdgeInsets.all(Spacing.md),
                itemCount: orders.length,
                itemBuilder: (context, i) {
                  final order = orders[i];
                  return Card(
                    margin: const EdgeInsets.only(bottom: Spacing.sm),
                    child: Padding(
                      padding: const EdgeInsets.all(Spacing.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final item in order.items)
                            Text('${item.quantity} × ${item.itemName}'),
                          const SizedBox(height: Spacing.xs),
                          Text(formatInr(order.total),
                              style: Theme.of(context).textTheme.bodyLarge),
                          const SizedBox(height: Spacing.sm),
                          DropdownButton<FoodOrderStatus>(
                            value: order.status,
                            items: [
                              for (final s in FoodOrderStatus.values)
                                DropdownMenuItem(value: s, child: Text(foodOrderStatusLabel(s))),
                            ],
                            onChanged: (s) =>
                                s == null ? null : _updateStatus(order.id, s, filter),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
