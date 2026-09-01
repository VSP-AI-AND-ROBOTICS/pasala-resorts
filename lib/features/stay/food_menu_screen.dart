import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/failure_view.dart';
import '../../core/errors.dart';
import '../../data/models/food_item.dart';
import '../../data/repositories/food_order_repository.dart';
import '../booking/providers.dart' show unitByIdProvider;
import '../booking/providers.dart' show reservationProvider;

/// Browse the menu and build a cart -- a plain local `Map<itemId, qty>`,
/// no new package needed. Prices shown here are the live [FoodItem.price]
/// for browsing convenience only; `place_food_order` re-prices every line
/// server-side at order time, so a stale client price can never be charged.
class FoodMenuScreen extends ConsumerStatefulWidget {
  const FoodMenuScreen({super.key, required this.reservationId});

  final String reservationId;

  @override
  ConsumerState<FoodMenuScreen> createState() => _FoodMenuScreenState();
}

class _FoodMenuScreenState extends ConsumerState<FoodMenuScreen> {
  final Map<String, int> _cart = {};
  final Map<String, FoodItem> _itemsById = {};
  bool _placing = false;

  double get _cartTotal => _cart.entries
      .fold(0.0, (sum, e) => sum + (_itemsById[e.key]?.price ?? 0) * e.value);

  void _changeQty(FoodItem item, int delta) {
    setState(() {
      _itemsById[item.id] = item;
      final next = (_cart[item.id] ?? 0) + delta;
      if (next <= 0) {
        _cart.remove(item.id);
      } else {
        _cart[item.id] = next;
      }
    });
  }

  Future<void> _placeOrder() async {
    if (_cart.isEmpty || _placing) return;
    setState(() => _placing = true);
    try {
      await ref.read(foodOrderRepositoryProvider).placeOrder(
            reservationId: widget.reservationId,
            quantitiesByItemId: _cart,
          );
      if (!mounted) return;
      setState(() => _cart.clear());
      ref.invalidate(myFoodOrdersProvider(widget.reservationId));
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Order placed')));
      context.push('/my-stay/food/orders', extra: widget.reservationId);
    } on BookingFailure catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(FailureView.messageFor(e))));
    } finally {
      if (mounted) setState(() => _placing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final reservationAsync = ref.watch(reservationProvider(widget.reservationId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Order Food'),
        actions: [
          IconButton(
            tooltip: 'My orders',
            icon: const Icon(Icons.receipt_long_outlined),
            onPressed: () => context.push('/my-stay/food/orders',
                extra: widget.reservationId),
          ),
        ],
      ),
      body: AsyncView(
        value: reservationAsync,
        data: (reservation) {
          final propertyAsync = ref.watch(unitByIdProvider(reservation.unitId));
          return AsyncView(
            value: propertyAsync,
            data: (unit) => _Menu(
              propertyId: unit.propertyId,
              cart: _cart,
              onChangeQty: _changeQty,
            ),
          );
        },
      ),
      bottomNavigationBar: _cart.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(Spacing.md),
                child: FilledButton(
                  onPressed: _placing ? null : _placeOrder,
                  child: Text(_placing
                      ? 'Placing…'
                      : 'Place order · ${formatInr(_cartTotal)}'),
                ),
              ),
            ),
    );
  }
}

class _Menu extends ConsumerWidget {
  const _Menu({required this.propertyId, required this.cart, required this.onChangeQty});

  final String propertyId;
  final Map<String, int> cart;
  final void Function(FoodItem item, int delta) onChangeQty;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(foodCategoriesProvider(propertyId));
    return AsyncView(
      value: categoriesAsync,
      empty: () => const EmptyState(
        icon: Icons.restaurant_outlined,
        title: 'The menu is not set up yet',
      ),
      data: (categories) => ListView(
        padding: const EdgeInsets.all(Spacing.md),
        children: [
          for (final category in categories)
            _CategorySection(category: category, cart: cart, onChangeQty: onChangeQty),
        ],
      ),
    );
  }
}

class _CategorySection extends ConsumerWidget {
  const _CategorySection({required this.category, required this.cart, required this.onChangeQty});

  final FoodCategory category;
  final Map<String, int> cart;
  final void Function(FoodItem item, int delta) onChangeQty;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemsAsync = ref.watch(foodItemsProvider(category.id));
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(category.name, style: textTheme.titleMedium),
          const SizedBox(height: Spacing.sm),
          AsyncView(
            value: itemsAsync,
            data: (items) => Column(
              children: [
                for (final item in items)
                  _ItemRow(
                    item: item,
                    quantity: cart[item.id] ?? 0,
                    onChangeQty: onChangeQty,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.item, required this.quantity, required this.onChangeQty});

  final FoodItem item;
  final int quantity;
  final void Function(FoodItem item, int delta) onChangeQty;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      margin: const EdgeInsets.only(bottom: Spacing.sm),
      child: Padding(
        padding: const EdgeInsets.all(Spacing.sm),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.name, style: textTheme.bodyLarge),
                  if (item.description != null)
                    Text(item.description!,
                        style: textTheme.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant)),
                  const SizedBox(height: Spacing.xs),
                  Text(formatInr(item.price), style: textTheme.bodyMedium),
                ],
              ),
            ),
            if (!item.isAvailable)
              Text('Unavailable',
                  style: textTheme.bodySmall?.copyWith(color: scheme.error))
            else if (quantity == 0)
              OutlinedButton(
                onPressed: () => onChangeQty(item, 1),
                child: const Text('Add'),
              )
            else
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: () => onChangeQty(item, -1),
                  ),
                  Text('$quantity', style: textTheme.titleMedium),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline),
                    onPressed: () => onChangeQty(item, 1),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
