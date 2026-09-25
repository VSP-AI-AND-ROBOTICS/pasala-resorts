import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../../data/models/billing.dart';
import '../../data/models/subscription.dart';
import '../../data/repositories/billing_repository.dart';
import '../../data/repositories/subscription_repository.dart';
import 'manage_subscription_sheet.dart';

/// Auto-pay for the resort's ResortHub plan (P8), under the Plan tile in
/// Settings. Renders nothing unless billing-subscribe says auto-pay can be
/// offered (Razorpay keys set, and at least one plan has a Razorpay plan
/// id), so a deployment without Razorpay keeps its manual plans exactly as
/// before. Owner-only, like the rest of `/owner/settings`.
class SubscriptionBillingCard extends ConsumerWidget {
  const SubscriptionBillingCard({super.key, required this.propertyId});

  final String propertyId;

  void _refresh(WidgetRef ref) {
    ref.invalidate(resortBillingProvider(propertyId));
    ref.invalidate(subscriptionInvoicesProvider(propertyId));
    ref.invalidate(resortPlanProvider(propertyId));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final availability =
        switch (ref.watch(billingAvailabilityProvider(propertyId))) {
      AsyncData(:final value) when value.canPay => value,
      _ => null,
    };
    if (availability == null) return const SizedBox.shrink();

    final (statusLine, billing) =
        switch (ref.watch(resortBillingProvider(propertyId))) {
      AsyncData(:final value) =>
        (value == null ? 'No auto-pay set up' : billingStatusLine(value), value),
      AsyncError() => ('Could not load auto-pay', null),
      _ => ('Loading…', null),
    };
    final currentTier = switch (ref.watch(resortPlanProvider(propertyId))) {
      AsyncData(:final value) => value?.tier,
      _ => null,
    };
    final paid = billing == null
        ? null
        : lastPaymentLine(billing.lastPaymentInr, billing.lastPaymentAt);
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      key: const Key('owner-billing-card'),
      margin: const EdgeInsets.only(bottom: Spacing.sm),
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.autorenew, color: scheme.secondary),
                const SizedBox(width: Spacing.sm),
                Expanded(child: Text('Auto-pay', style: textTheme.titleMedium)),
                IconButton(
                  key: const Key('billing-refresh'),
                  tooltip: 'Refresh',
                  icon: const Icon(Icons.refresh),
                  onPressed: () => _refresh(ref),
                ),
              ],
            ),
            Text(statusLine, key: const Key('billing-status-line')),
            if (paid != null)
              Text(
                paid,
                key: const Key('billing-last-payment'),
                style: textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            const SizedBox(height: Spacing.sm),
            FilledButton.tonal(
              key: const Key('billing-manage-btn'),
              onPressed: () => _openSheet(
                  context, ref, availability, billing, currentTier),
              child: const Text('Pay / manage subscription'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openSheet(
    BuildContext context,
    WidgetRef ref,
    BillingAvailability availability,
    ResortBilling? billing,
    SubscriptionTier? currentTier,
  ) async {
    final message = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ManageSubscriptionSheet(
        propertyId: propertyId,
        plans: availability.plans,
        billing: billing,
        currentTier: currentTier,
      ),
    );
    if (!context.mounted) return;
    _refresh(ref);
    if (message != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }
}
