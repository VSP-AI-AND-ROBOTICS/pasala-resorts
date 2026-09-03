import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../core/format.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/failure_view.dart';
import '../../data/models/expense.dart';
import '../../data/repositories/expense_repository.dart';
import '../browse/providers.dart';

DateTimeRange _currentMonth() {
  final now = DateTime.now();
  return DateTimeRange(
    start: DateTime(now.year, now.month, 1),
    end: DateTime(now.year, now.month + 1, 0),
  );
}

/// `/owner/expenses` -- log and review business expenses, full CRUD.
/// Financial data: reachable only through the super_admin-only `/owner`
/// route, and `expenses_read` (0027_expenses.sql) additionally restricts
/// the underlying table to admin/accountant/super_admin regardless.
class ExpensesScreen extends ConsumerStatefulWidget {
  const ExpensesScreen({super.key});

  @override
  ConsumerState<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends ConsumerState<ExpensesScreen> {
  DateTimeRange _range = _currentMonth();

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
    final filter = (from: _range.start, to: _range.end);
    final expenses = ref.watch(expensesProvider(filter));

    return Scaffold(
      appBar: AppBar(title: const Text('Expenses')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                Spacing.md, Spacing.md, Spacing.md, Spacing.sm),
            child: OutlinedButton.icon(
              onPressed: _pickRange,
              icon: const Icon(Icons.date_range_outlined),
              label: Text(
                '${formatDate(_range.start)} – ${formatDate(_range.end)}',
              ),
            ),
          ),
          Expanded(
            child: AsyncView(
              value: expenses,
              onRetry: () => ref.invalidate(expensesProvider(filter)),
              empty: () => const EmptyState(
                icon: Icons.receipt_long_outlined,
                title: 'No expenses logged in this period',
                message: 'Tap + to log a business expense.',
              ),
              data: (list) => ListView(
                children: [
                  for (final expense in list)
                    Padding(
                      key: Key('expense-row-${expense.id}'),
                      padding: const EdgeInsets.symmetric(
                        horizontal: Spacing.md,
                        vertical: Spacing.xs,
                      ),
                      child: Card(
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Theme.of(context)
                                .colorScheme
                                .errorContainer
                                .withValues(alpha: 0.5),
                            child: Icon(Icons.receipt_long_outlined,
                                color: Theme.of(context).colorScheme.onErrorContainer),
                          ),
                          title: Text(expense.description.isEmpty
                              ? expense.category
                              : expense.description),
                          subtitle: Text(
                            '${expense.category} · ${formatDate(expense.expenseDate)}'
                            '${expense.paidTo == null ? '' : ' · ${expense.paidTo}'}',
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                formatInr(expense.amount),
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                              PopupMenuButton<String>(
                                onSelected: (value) =>
                                    _onMenuSelected(context, filter, expense, value),
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
          MaterialPageRoute(builder: (_) => const ExpenseFormScreen()),
        ),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _onMenuSelected(
    BuildContext context,
    ExpenseFilter filter,
    Expense expense,
    String value,
  ) {
    switch (value) {
      case 'edit':
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => ExpenseFormScreen(existing: expense)),
        );
      case 'delete':
        _delete(context, filter, expense);
    }
  }

  Future<void> _delete(
    BuildContext context,
    ExpenseFilter filter,
    Expense expense,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete this expense?'),
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
      await ref.read(expenseRepositoryProvider).delete(expense.id);
      ref.invalidate(expensesProvider(filter));
    } on BookingFailure catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(FailureView.messageFor(e))));
      }
    }
  }
}

/// Create/edit form for an [Expense].
class ExpenseFormScreen extends ConsumerStatefulWidget {
  const ExpenseFormScreen({super.key, this.existing});

  final Expense? existing;

  @override
  ConsumerState<ExpenseFormScreen> createState() => _ExpenseFormScreenState();
}

class _ExpenseFormScreenState extends ConsumerState<ExpenseFormScreen> {
  late final TextEditingController _category;
  late final TextEditingController _description;
  late final TextEditingController _amount;
  late final TextEditingController _paidTo;
  late DateTime _expenseDate;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _category = TextEditingController(text: existing?.category ?? '');
    _description = TextEditingController(text: existing?.description ?? '');
    _amount = TextEditingController(text: '${existing?.amount ?? ''}');
    _paidTo = TextEditingController(text: existing?.paidTo ?? '');
    _expenseDate = existing?.expenseDate ?? DateTime.now();
  }

  @override
  void dispose() {
    _category.dispose();
    _description.dispose();
    _amount.dispose();
    _paidTo.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _expenseDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _expenseDate = picked);
  }

  Future<void> _save() async {
    final category = _category.text.trim();
    final amount = num.tryParse(_amount.text.trim());
    if (category.isEmpty || amount == null || amount < 0) {
      setState(() => _error = 'Enter a category and a valid amount.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final properties = await ref.read(propertiesProvider.future);
      final propertyId = widget.existing?.propertyId ??
          (properties.isEmpty ? '' : properties.first.id);
      final paidTo = _paidTo.text.trim();
      final expense = Expense(
        id: widget.existing?.id ?? '',
        propertyId: propertyId,
        expenseDate: _expenseDate,
        category: category,
        description: _description.text.trim(),
        amount: amount,
        paidTo: paidTo.isEmpty ? null : paidTo,
      );
      final repo = ref.read(expenseRepositoryProvider);
      if (widget.existing == null) {
        await repo.create(expense);
      } else {
        await repo.update(widget.existing!.id, expense);
      }
      ref.invalidate(expensesProvider);
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
          title: Text(widget.existing == null ? 'New expense' : 'Edit expense'),
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
                        TextField(
                          key: const Key('expense-form-category'),
                          controller: _category,
                          decoration: const InputDecoration(
                            labelText: 'Category',
                            helperText: 'e.g. Utilities, Maintenance, Supplies, Salaries',
                          ),
                        ),
                        const SizedBox(height: Spacing.sm),
                        TextField(
                          key: const Key('expense-form-description'),
                          controller: _description,
                          decoration: const InputDecoration(labelText: 'Description'),
                        ),
                        const SizedBox(height: Spacing.sm),
                        TextField(
                          key: const Key('expense-form-amount'),
                          controller: _amount,
                          keyboardType:
                              const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(labelText: 'Amount'),
                        ),
                        const SizedBox(height: Spacing.sm),
                        TextField(
                          key: const Key('expense-form-paid-to'),
                          controller: _paidTo,
                          decoration: const InputDecoration(
                            labelText: 'Paid to',
                            helperText: 'Optional',
                          ),
                        ),
                        const SizedBox(height: Spacing.sm),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.event_outlined),
                          title: const Text('Date'),
                          trailing: Text(formatDate(_expenseDate)),
                          onTap: _pickDate,
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
