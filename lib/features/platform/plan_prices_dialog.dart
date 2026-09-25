import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../core/theme/spacing.dart';
import '../../core/widgets/failure_view.dart';
import '../../data/models/subscription.dart';
import '../../data/repositories/platform_repository.dart';

/// "Plan prices" (spec decision 11): the monthly INR price of each plan,
/// and (P8) the Razorpay plan behind it -- blank keeps that plan billed by
/// hand. Save sends only what changed, through `set_plan_price` and
/// `set_plan_razorpay_id`. A change applies to every resort on that plan
/// at once, so the list, the cards (MRR) and the plans are refetched --
/// even after a partial failure, because the changes saved before it are
/// real.
class PlanPricesDialog extends ConsumerStatefulWidget {
  const PlanPricesDialog({super.key, required this.plans});

  final List<SubscriptionPlan> plans;

  @override
  ConsumerState<PlanPricesDialog> createState() => _PlanPricesDialogState();
}

class _PlanPricesDialogState extends ConsumerState<PlanPricesDialog> {
  late final Map<SubscriptionTier, TextEditingController> _prices = {
    for (final plan in widget.plans)
      plan.tier: TextEditingController(text: _show(plan.monthlyPriceInr)),
  };
  late final Map<SubscriptionTier, TextEditingController> _planIds = {
    for (final plan in widget.plans)
      plan.tier: TextEditingController(text: plan.razorpayPlanId ?? ''),
  };
  String? _error;
  bool _busy = false;

  /// The same rule as the database's check (0057_subscription_billing.sql).
  static final _planIdPattern = RegExp(r'^plan_[A-Za-z0-9]{6,40}$');

  static String _show(num price) =>
      price % 1 == 0 ? price.toStringAsFixed(0) : price.toStringAsFixed(2);

  @override
  void dispose() {
    for (final c in [..._prices.values, ..._planIds.values]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final changes = <SubscriptionTier, num>{};
    final planIdChanges = <SubscriptionTier, String?>{};
    for (final plan in widget.plans) {
      final text = _prices[plan.tier]!.text.trim().replaceAll(',', '');
      final value = num.tryParse(text);
      if (value == null || value < 0) {
        setState(() =>
            _error = 'Enter a monthly price of 0 or more for every plan.');
        return;
      }
      if (value != plan.monthlyPriceInr) changes[plan.tier] = value;

      final id = _planIds[plan.tier]!.text.trim();
      if (id.isNotEmpty && !_planIdPattern.hasMatch(id)) {
        setState(() => _error = 'A Razorpay plan id looks like plan_ '
            'followed by letters and digits.');
        return;
      }
      final newId = id.isEmpty ? null : id;
      if (newId != plan.razorpayPlanId) planIdChanges[plan.tier] = newId;
    }
    if (changes.isEmpty && planIdChanges.isEmpty) {
      Navigator.of(context).pop();
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    BookingFailure? failure;
    try {
      final source = ref.read(platformSourceProvider);
      for (final change in changes.entries) {
        await source.setPlanPrice(change.key, change.value);
      }
      for (final change in planIdChanges.entries) {
        await source.setRazorpayPlanId(change.key, change.value);
      }
    } on BookingFailure catch (e) {
      failure = e;
    }
    if (!mounted) return;
    ref.invalidate(subscriptionPlansProvider);
    ref.invalidate(platformTotalsProvider);
    ref.invalidate(platformResortsProvider);
    if (failure == null) {
      Navigator.of(context).pop();
    } else {
      setState(() {
        _busy = false;
        _error = FailureView.messageFor(failure!);
      });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Plan prices (per month)'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final plan in widget.plans)
                Padding(
                  padding: const EdgeInsets.only(bottom: Spacing.sm),
                  child: TextField(
                    key: Key('plan-price-${subscriptionTierToDb(plan.tier)}'),
                    controller: _prices[plan.tier],
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: plan.name,
                      prefixText: '₹ ',
                    ),
                  ),
                ),
              Text(
                'A change applies to every resort on that plan, and to MRR, '
                'straight away.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: Spacing.md),
              Text('Razorpay auto-pay',
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: Spacing.sm),
              for (final plan in widget.plans)
                Padding(
                  padding: const EdgeInsets.only(bottom: Spacing.sm),
                  child: TextField(
                    key: Key('plan-razorpay-${subscriptionTierToDb(plan.tier)}'),
                    controller: _planIds[plan.tier],
                    decoration: InputDecoration(
                      labelText: '${plan.name} Razorpay plan id',
                      helperText: 'Blank = billed by hand',
                    ),
                  ),
                ),
              if (_error != null) ...[
                const SizedBox(height: Spacing.sm),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('plan-prices-save'),
            onPressed: _busy ? null : _save,
            child: const Text('Save'),
          ),
        ],
      );
}
