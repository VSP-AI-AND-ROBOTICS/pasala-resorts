import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/empty_state.dart';
import '../../data/models/food_order.dart';
import '../../data/repositories/food_order_repository.dart';

class FoodOrderStatusScreen extends ConsumerWidget {
  const FoodOrderStatusScreen({super.key, required this.reservationId});

  final String reservationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersAsync = ref.watch(myFoodOrdersProvider(reservationId));

    return Scaffold(
      appBar: AppBar(title: const Text('My Food Orders')),
      body: AsyncView(
        value: ordersAsync,
        onRetry: () => ref.invalidate(myFoodOrdersProvider(reservationId)),
        empty: () => const EmptyState(
          icon: Icons.receipt_long_outlined,
          title: 'No food orders yet',
        ),
        data: (orders) => ListView.builder(
          padding: const EdgeInsets.all(Spacing.md),
          itemCount: orders.length,
          itemBuilder: (context, i) => _OrderCard(order: orders[i]),
        ),
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order});

  final FoodOrder order;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: Spacing.sm),
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    order.createdAt == null
                        ? 'Order'
                        : formatDay(order.createdAt!.toLocal()),
                    style: textTheme.titleMedium,
                  ),
                ),
                Chip(
                  label: Text(foodOrderStatusLabel(order.status)),
                  backgroundColor: order.status == FoodOrderStatus.cancelled
                      ? scheme.surfaceContainerHigh
                      : scheme.primaryContainer,
                  side: BorderSide.none,
                ),
              ],
            ),
            const SizedBox(height: Spacing.sm),
            for (final item in order.items)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Expanded(child: Text('${item.quantity} × ${item.itemName}')),
                    Text(formatInr(item.lineTotal)),
                  ],
                ),
              ),
            const Divider(),
            Row(
              children: [
                const Expanded(child: Text('Total')),
                Text(formatInr(order.total),
                    style: textTheme.bodyLarge
                        ?.copyWith(fontWeight: FontWeight.w600)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
