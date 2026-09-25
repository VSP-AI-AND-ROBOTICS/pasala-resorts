import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/failure_view.dart';
import '../../data/models/property.dart';
import '../../data/models/refund_rule.dart';
import '../../data/repositories/refund_rule_repository.dart';

/// Cancellation policy -- CRUD over the `refund_rules` ladder
/// (`0013_refund_policy.sql`). This table has been admin-configurable only
/// via Supabase Studio/psql since phase 2 shipped (see the README's "Known
/// limitations") -- this is its first in-app screen. `compute_refund`
/// itself is unchanged: it already picks the rule with the greatest
/// `min_days_before` that does not exceed the real days-before-check-in, so
/// this screen only needs to let an owner add/edit/remove tiers, never
/// re-implement that selection logic.
class CancellationPolicyScreen extends ConsumerWidget {
  const CancellationPolicyScreen({super.key, required this.property});

  final Property property;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rules = ref.watch(refundRulesProvider(property.id));

    return Scaffold(
      appBar: AppBar(title: const Text('Cancellation policy')),
      body: AsyncView(
        value: rules,
        onRetry: () => ref.invalidate(refundRulesProvider(property.id)),
        empty: () => const EmptyState(
          icon: Icons.policy_outlined,
          title: 'No refund tiers yet',
          message: 'Tap + to add one. With no tiers, a cancellation refunds nothing.',
        ),
        data: (list) => ListView(
          padding: const EdgeInsets.all(Spacing.md),
          children: [
            for (final rule in list)
              Card(
                key: Key('refund-rule-row-${rule.id}'),
                margin: const EdgeInsets.only(bottom: Spacing.sm),
                child: ListTile(
                  title: Text('${rule.minDaysBefore}+ days before check-in'),
                  subtitle: Text('${rule.refundPct}% refunded'),
                  trailing: PopupMenuButton<String>(
                    onSelected: (value) => _onMenuSelected(context, ref, rule, value),
                    itemBuilder: (context) => const [
                      PopupMenuItem(value: 'edit', child: Text('Edit')),
                      PopupMenuItem(value: 'delete', child: Text('Delete')),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => RefundRuleFormScreen(property: property)),
        ),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _onMenuSelected(
    BuildContext context,
    WidgetRef ref,
    RefundRule rule,
    String value,
  ) {
    switch (value) {
      case 'edit':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => RefundRuleFormScreen(property: property, existing: rule),
          ),
        );
      case 'delete':
        _delete(context, ref, rule);
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, RefundRule rule) async {
    // Pop with the dialog's own context: showDialog puts the dialog on the
    // root navigator, but inside the router's ShellRoute the screen's
    // `context` resolves to the shell navigator, so popping that would
    // remove the Cancellation policy page and leave the dialog up.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this tier?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      await ref.read(refundRuleRepositoryProvider).delete(rule.id);
      ref.invalidate(refundRulesProvider(property.id));
    } on BookingFailure catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(FailureView.messageFor(e))));
      }
    }
  }
}

/// Create/edit form for one [RefundRule] tier.
class RefundRuleFormScreen extends ConsumerStatefulWidget {
  const RefundRuleFormScreen({super.key, required this.property, this.existing});

  final Property property;
  final RefundRule? existing;

  @override
  ConsumerState<RefundRuleFormScreen> createState() => _RefundRuleFormScreenState();
}

class _RefundRuleFormScreenState extends ConsumerState<RefundRuleFormScreen> {
  late final TextEditingController _minDaysBefore;
  late final TextEditingController _refundPct;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _minDaysBefore =
        TextEditingController(text: '${widget.existing?.minDaysBefore ?? ''}');
    _refundPct = TextEditingController(text: '${widget.existing?.refundPct ?? ''}');
  }

  @override
  void dispose() {
    _minDaysBefore.dispose();
    _refundPct.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final minDaysBefore = int.tryParse(_minDaysBefore.text.trim());
    final refundPct = num.tryParse(_refundPct.text.trim());
    if (minDaysBefore == null || minDaysBefore < 0 ||
        refundPct == null || refundPct < 0 || refundPct > 100) {
      setState(() => _error =
          'Enter a non-negative day count and a refund percentage between 0 and 100.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final rule = RefundRule(
        id: widget.existing?.id ?? '',
        propertyId: widget.property.id,
        minDaysBefore: minDaysBefore,
        refundPct: refundPct,
      );
      final repo = ref.read(refundRuleRepositoryProvider);
      if (widget.existing == null) {
        await repo.create(rule);
      } else {
        await repo.update(widget.existing!.id, rule);
      }
      ref.invalidate(refundRulesProvider(widget.property.id));
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
          title: Text(widget.existing == null ? 'New refund tier' : 'Edit refund tier'),
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(Spacing.lg),
              children: [
                TextField(
                  key: const Key('refund-rule-min-days-field'),
                  controller: _minDaysBefore,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Days before check-in',
                    helperText: 'This tier applies from this many days out onward',
                  ),
                ),
                const SizedBox(height: Spacing.sm),
                TextField(
                  key: const Key('refund-rule-pct-field'),
                  controller: _refundPct,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Refund percentage'),
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
