import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/errors.dart';
import '../../core/format.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/failure_view.dart';
import '../../data/models/billing.dart';
import '../../data/models/subscription.dart';
import '../../data/repositories/billing_repository.dart';

/// Opens Razorpay's hosted subscription page. A seam, so widget tests
/// never launch a browser.
typedef BillingLinkOpener = Future<bool> Function(Uri uri);

final billingLinkOpenerProvider = Provider<BillingLinkOpener>(
  (ref) => (uri) => launchUrl(uri, mode: LaunchMode.externalApplication),
);

/// "Pay / manage subscription" (P8): pick a plan and continue to Razorpay,
/// or cancel auto-pay; the last payments below. Pops with the message the
/// Settings screen shows as a snackbar, or null when dismissed.
class ManageSubscriptionSheet extends ConsumerStatefulWidget {
  const ManageSubscriptionSheet({
    super.key,
    required this.propertyId,
    required this.plans,
    this.billing,
    this.currentTier,
  });

  final String propertyId;

  /// The plans with a Razorpay plan id, from the probe. Never empty: the
  /// card only offers the sheet when there is one.
  final List<SubscriptionPlan> plans;
  final ResortBilling? billing;

  /// The resort's plan today, preselected when it can be paid online.
  final SubscriptionTier? currentTier;

  @override
  ConsumerState<ManageSubscriptionSheet> createState() =>
      _ManageSubscriptionSheetState();
}

class _ManageSubscriptionSheetState
    extends ConsumerState<ManageSubscriptionSheet> {
  late SubscriptionTier _tier = _initialTier();
  bool _busy = false;
  String? _error;

  SubscriptionTier _initialTier() {
    final billable = widget.plans.map((p) => p.tier).toSet();
    for (final tier in [widget.billing?.tier, widget.currentTier]) {
      if (tier != null && billable.contains(tier)) return tier;
    }
    return widget.plans.first.tier;
  }

  String get _planName =>
      widget.plans.firstWhere((p) => p.tier == _tier).name;

  Future<void> _continue() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await ref
          .read(billingSourceProvider)
          .subscribe(widget.propertyId, _tier);
      if (!mounted) return;
      if (result.action == SubscribeAction.unchanged) {
        Navigator.of(context).pop('Auto-pay is already on for $_planName.');
        return;
      }
      final url = result.shortUrl;
      final opened =
          url != null && await ref.read(billingLinkOpenerProvider)(Uri.parse(url));
      if (!mounted) return;
      if (!opened) {
        setState(() {
          _busy = false;
          _error = url == null
              ? 'Razorpay did not send a payment link. Try again.'
              : 'Could not open $url';
        });
        return;
      }
      Navigator.of(context)
          .pop('Finish the payment on the Razorpay page, then tap Refresh.');
    } on BookingFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = FailureView.messageFor(e);
      });
    }
  }

  Future<void> _cancel() async {
    // Pop with the dialog's own context (see resort_card.dart).
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cancel auto-pay?'),
        content: const Text('Your plan stays paid until the end of the '
            'current period. Nothing more is charged.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep auto-pay'),
          ),
          FilledButton(
            key: const Key('billing-cancel-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Cancel auto-pay'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final action =
          await ref.read(billingSourceProvider).cancel(widget.propertyId);
      if (!mounted) return;
      Navigator.of(context).pop(switch (action) {
        CancelAction.cancelScheduled =>
          'Auto-pay will end with the current period.',
        CancelAction.cancelled => 'Auto-pay cancelled.',
        CancelAction.none => 'There was no auto-pay to cancel.',
      });
    } on BookingFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = FailureView.messageFor(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final invoices = ref.watch(subscriptionInvoicesProvider(widget.propertyId));

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(Spacing.md, Spacing.md, Spacing.md,
            Spacing.md + MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Pay / manage subscription', style: textTheme.titleLarge),
              const SizedBox(height: Spacing.xs),
              Text(
                'Razorpay charges your plan every month. A change of plan '
                'starts when your current period ends.',
                style: textTheme.bodySmall,
              ),
              const SizedBox(height: Spacing.sm),
              for (final plan in widget.plans)
                ListTile(
                  key: Key('billing-tier-${subscriptionTierToDb(plan.tier)}'),
                  title: Text(plan.name),
                  subtitle: Text('${formatInr(plan.monthlyPriceInr)} / month'),
                  selected: plan.tier == _tier,
                  trailing: Icon(plan.tier == _tier
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked),
                  onTap: _busy ? null : () => setState(() => _tier = plan.tier),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: Spacing.sm),
                  child: Text(
                    _error!,
                    key: const Key('billing-error'),
                    style: TextStyle(color: scheme.error),
                  ),
                ),
              const SizedBox(height: Spacing.sm),
              FilledButton(
                key: const Key('billing-continue'),
                onPressed: _busy ? null : _continue,
                child: const Text('Continue to payment'),
              ),
              if (widget.billing?.canCancel ?? false)
                TextButton(
                  key: const Key('billing-cancel'),
                  onPressed: _busy ? null : _cancel,
                  child: const Text('Cancel auto-pay'),
                ),
              const Divider(height: Spacing.lg),
              Text('Payments', style: textTheme.titleSmall),
              switch (invoices) {
                AsyncData(:final value) when value.isEmpty =>
                  const Text('No payments yet'),
                AsyncData(:final value) => Column(
                    children: [
                      for (final invoice in value)
                        ListTile(
                          key: Key('billing-invoice-${invoice.id}'),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                              '${formatDate(invoice.paidAt)} · ${invoice.tier.label}'),
                          trailing: Text(formatInr(invoice.amountInr)),
                        ),
                    ],
                  ),
                AsyncError() => const Text('Could not load payments'),
                _ => const Text('Loading…'),
              },
            ],
          ),
        ),
      ),
    );
  }
}
