import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/current_resort.dart';
import '../../core/errors.dart';
import '../../core/format.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/failure_view.dart';
import '../../data/models/food_sale.dart';
import '../../data/models/resort_membership.dart';
import '../../data/repositories/food_sale_repository.dart';

String _categoryLabel(SaleCategory c) => switch (c) {
      SaleCategory.food => 'Food',
      SaleCategory.activity => 'Activity',
    };

DateTimeRange _currentMonth() {
  final now = DateTime.now();
  return DateTimeRange(
    start: DateTime(now.year, now.month, 1),
    end: DateTime(now.year, now.month + 1, 0),
  );
}

/// `/owner/food-sales` -- log and review on-site food/activity sales,
/// following `TasksScreen`'s shape (filter bar, list, FAB, popup-menu
/// edit/delete). `food_activity_sales_read`/`_insert`
/// (0026_food_activity_sales.sql) grant staff-or-above read+add, but edit/
/// delete (`_admin_write`/`_admin_delete`) stay owner/admin-only -- so the
/// FAB shows for any signed-in user at the current resort, while the
/// popup menu only renders when the current resort's role is owner or
/// admin.
class FoodSalesScreen extends ConsumerStatefulWidget {
  const FoodSalesScreen({super.key});

  @override
  ConsumerState<FoodSalesScreen> createState() => _FoodSalesScreenState();
}

class _FoodSalesScreenState extends ConsumerState<FoodSalesScreen> {
  DateTimeRange _range = _currentMonth();
  SaleCategory? _category;

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDateRange: _range,
    );
    if (picked != null) setState(() => _range = picked);
  }

  @override
  Widget build(BuildContext context) {
    // A screen reached without a current resort is impossible after Task
    // 14's redirect.
    final resort = ref.watch(currentResortProvider)!;
    final filter = (
      propertyId: resort.propertyId,
      from: _range.start,
      to: _range.end,
      category: _category,
    );
    final sales = ref.watch(foodSalesProvider(filter));
    final canEditOrDelete =
        const {ResortRole.owner, ResortRole.admin}.contains(resort.role);

    return Scaffold(
      appBar: AppBar(title: const Text('Food & activity sales')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(Spacing.md),
            child: Wrap(
              spacing: Spacing.md,
              runSpacing: Spacing.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: _pickRange,
                  icon: const Icon(Icons.date_range_outlined),
                  label: Text(
                    '${formatDate(_range.start)} – ${formatDate(_range.end)}',
                  ),
                ),
                DropdownButton<SaleCategory?>(
                  key: const Key('sale-category-filter'),
                  value: _category,
                  hint: const Text('All categories'),
                  items: [
                    const DropdownMenuItem(
                        value: null, child: Text('All categories')),
                    for (final c in SaleCategory.values)
                      DropdownMenuItem(value: c, child: Text(_categoryLabel(c))),
                  ],
                  onChanged: (value) => setState(() => _category = value),
                ),
              ],
            ),
          ),
          Expanded(
            child: AsyncView(
              value: sales,
              onRetry: () => ref.invalidate(foodSalesProvider(filter)),
              empty: () => const EmptyState(
                icon: Icons.restaurant_outlined,
                title: 'No sales logged in this period',
                message: 'Tap + to log a food or activity sale.',
              ),
              data: (list) => ListView(
                children: [
                  for (final sale in list)
                    Padding(
                      key: Key('sale-row-${sale.id}'),
                      padding: const EdgeInsets.symmetric(
                        horizontal: Spacing.md,
                        vertical: Spacing.xs,
                      ),
                      child: Card(
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Theme.of(context)
                                .colorScheme
                                .primaryContainer
                                .withValues(alpha: 0.6),
                            child: Icon(
                              sale.category == SaleCategory.food
                                  ? Icons.restaurant_outlined
                                  : Icons.local_activity_outlined,
                              color: Theme.of(context).colorScheme.onPrimaryContainer,
                            ),
                          ),
                          title: Text(sale.itemName),
                          subtitle: Text(
                            '${_categoryLabel(sale.category)} · '
                            '${formatDate(sale.saleDate)} · '
                            '${sale.quantity} × ${formatInr(sale.unitPrice)}',
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                formatInr(sale.amount),
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                              if (canEditOrDelete)
                                PopupMenuButton<String>(
                                  onSelected: (value) =>
                                      _onMenuSelected(context, filter, sale, value),
                                  itemBuilder: (context) => const [
                                    PopupMenuItem(value: 'edit', child: Text('Edit')),
                                    PopupMenuItem(value: 'delete', child: Text('Delete')),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => FoodSaleFormScreen(propertyId: resort.propertyId),
          ),
        ),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _onMenuSelected(
    BuildContext context,
    FoodSaleFilter filter,
    FoodSale sale,
    String value,
  ) {
    switch (value) {
      case 'edit':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) =>
                FoodSaleFormScreen(propertyId: sale.propertyId, existing: sale),
          ),
        );
      case 'delete':
        _delete(context, filter, sale);
    }
  }

  Future<void> _delete(
    BuildContext context,
    FoodSaleFilter filter,
    FoodSale sale,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Delete "${sale.itemName}"?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      await ref.read(foodSaleRepositoryProvider).delete(sale.id);
      ref.invalidate(foodSalesProvider(filter));
    } on BookingFailure catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(FailureView.messageFor(e))));
      }
    }
  }
}

/// Create/edit form for a [FoodSale]. [propertyId] is the current resort's
/// -- for a new sale it becomes the row's `property_id`; for an edit it is
/// ignored in favour of the existing row's own (unchanged) resort.
class FoodSaleFormScreen extends ConsumerStatefulWidget {
  const FoodSaleFormScreen({super.key, required this.propertyId, this.existing});

  final String propertyId;
  final FoodSale? existing;

  @override
  ConsumerState<FoodSaleFormScreen> createState() => _FoodSaleFormScreenState();
}

class _FoodSaleFormScreenState extends ConsumerState<FoodSaleFormScreen> {
  late final TextEditingController _itemName;
  late final TextEditingController _quantity;
  late final TextEditingController _unitPrice;
  late final TextEditingController _notes;
  late SaleCategory _category;
  late DateTime _saleDate;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _itemName = TextEditingController(text: existing?.itemName ?? '');
    _quantity = TextEditingController(text: '${existing?.quantity ?? 1}');
    _unitPrice = TextEditingController(text: '${existing?.unitPrice ?? ''}');
    _notes = TextEditingController(text: existing?.notes ?? '');
    _category = existing?.category ?? SaleCategory.food;
    _saleDate = existing?.saleDate ?? DateTime.now();
  }

  @override
  void dispose() {
    _itemName.dispose();
    _quantity.dispose();
    _unitPrice.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _saleDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _saleDate = picked);
  }

  Future<void> _save() async {
    final itemName = _itemName.text.trim();
    final quantity = int.tryParse(_quantity.text.trim());
    final unitPrice = num.tryParse(_unitPrice.text.trim());
    if (itemName.isEmpty || quantity == null || quantity <= 0 || unitPrice == null) {
      setState(() => _error = 'Enter a valid item name, quantity, and unit price.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final propertyId = widget.existing?.propertyId ?? widget.propertyId;
      final notes = _notes.text.trim();
      final sale = FoodSale(
        id: widget.existing?.id ?? '',
        propertyId: propertyId,
        saleDate: _saleDate,
        category: _category,
        itemName: itemName,
        quantity: quantity,
        unitPrice: unitPrice,
        amount: unitPrice * quantity,
        notes: notes.isEmpty ? null : notes,
      );
      final repo = ref.read(foodSaleRepositoryProvider);
      if (widget.existing == null) {
        await repo.create(sale);
      } else {
        await repo.update(widget.existing!.id, sale);
      }
      ref.invalidate(foodSalesProvider);
      if (mounted) Navigator.of(context).pop();
    } on BookingFailure catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(FailureView.messageFor(e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(widget.existing == null ? 'New sale' : 'Edit sale'),
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(Spacing.lg),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(Spacing.md),
                    child: Column(
                      children: [
                        DropdownButtonFormField<SaleCategory>(
                          key: const Key('sale-form-category'),
                          initialValue: _category,
                          decoration: const InputDecoration(labelText: 'Category'),
                          items: [
                            for (final c in SaleCategory.values)
                              DropdownMenuItem(value: c, child: Text(_categoryLabel(c))),
                          ],
                          onChanged: (value) =>
                              setState(() => _category = value ?? SaleCategory.food),
                        ),
                        const SizedBox(height: Spacing.sm),
                        TextField(
                          key: const Key('sale-form-item-name'),
                          controller: _itemName,
                          decoration: const InputDecoration(labelText: 'Item'),
                        ),
                        const SizedBox(height: Spacing.sm),
                        TextField(
                          key: const Key('sale-form-quantity'),
                          controller: _quantity,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Quantity'),
                        ),
                        const SizedBox(height: Spacing.sm),
                        TextField(
                          key: const Key('sale-form-unit-price'),
                          controller: _unitPrice,
                          keyboardType:
                              const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(labelText: 'Unit price'),
                        ),
                        const SizedBox(height: Spacing.sm),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.event_outlined),
                          title: const Text('Date'),
                          trailing: Text(formatDate(_saleDate)),
                          onTap: _pickDate,
                        ),
                        TextField(
                          key: const Key('sale-form-notes'),
                          controller: _notes,
                          decoration: const InputDecoration(
                            labelText: 'Notes',
                            helperText: 'Optional',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: Spacing.sm),
                    child: Text(
                      _error!,
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ),
                const SizedBox(height: Spacing.lg),
                FilledButton(
                  onPressed: _busy ? null : _save,
                  child: const Text('Save'),
                ),
              ],
            ),
          ),
        ),
      );
}
