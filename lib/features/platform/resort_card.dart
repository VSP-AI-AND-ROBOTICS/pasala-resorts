import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../core/format.dart';
import '../../core/theme/spacing.dart';
import '../../core/widgets/failure_view.dart';
import '../../data/models/subscription.dart';
import '../../data/repositories/platform_repository.dart';
import 'change_plan_dialog.dart';

String _statusLabel(String status) =>
    status.isEmpty ? status : status[0].toUpperCase() + status.substring(1);

/// One resort on the platform console: name, status, owners, its plan
/// (tier chip and plan line), booking summary, and the actions -- Change
/// plan (Set plan when it has none) and Suspend (active) or Reactivate
/// (suspended). An archived resort gets no action at all, and a pending
/// one (P10) waits for Approve or Reject in the Pending review list.
/// [onChanged] runs after a change, so the console refetches the list and
/// the cards.
class ResortCard extends ConsumerWidget {
  const ResortCard({super.key, required this.resort, required this.onChanged});

  final ResortSummary resort;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final suspended = resort.status == 'suspended';
    // Archived resorts are neither suspended nor active: they get no
    // status action here (Suspend would pretend they were active).
    final archived = resort.status == 'archived';
    // A pending resort waits for Approve / Reject in the Pending review
    // list (P10); Suspend or a plan change here would bypass the review.
    final pending = resort.status == 'pending';
    final plan = resort.plan;

    return Card(
      key: Key('resort-row-${resort.propertyId}'),
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(resort.name,
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                Chip(
                  label: Text(
                      pending ? 'Pending review' : _statusLabel(resort.status)),
                  backgroundColor: pending
                      ? scheme.tertiaryContainer
                      : suspended
                          ? scheme.errorContainer
                          : archived
                              ? scheme.surfaceContainerHighest
                              : scheme.secondaryContainer,
                  side: BorderSide.none,
                ),
              ],
            ),
            const SizedBox(height: Spacing.xs),
            Text(
              resort.ownerEmails.isEmpty
                  ? 'No owner'
                  : resort.ownerEmails.join(', '),
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: Spacing.sm),
            Wrap(
              spacing: Spacing.sm,
              runSpacing: Spacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Chip(
                  key: Key('resort-tier-${resort.propertyId}'),
                  label: Text(plan?.tier.label ?? 'No plan'),
                  backgroundColor: plan == null
                      ? scheme.surfaceContainerHighest
                      : scheme.primaryContainer,
                  side: BorderSide.none,
                ),
                if (plan != null) PlanLine(plan: plan),
              ],
            ),
            const SizedBox(height: Spacing.sm),
            Text(
              '${resort.bookings30d} bookings · ${formatInr(resort.revenue30d)} '
              '(last 30 days)',
            ),
            Text(
              '${resort.bookings365d} bookings · ${formatInr(resort.revenue365d)} '
              '(last 365 days)',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
            if (!archived && !pending) ...[
              const SizedBox(height: Spacing.sm),
              Align(
                alignment: Alignment.centerRight,
                child: Wrap(
                  spacing: Spacing.sm,
                  runSpacing: Spacing.xs,
                  alignment: WrapAlignment.end,
                  children: [
                    TextButton(
                      key: Key('resort-plan-btn-${resort.propertyId}'),
                      onPressed: () => _changePlan(context),
                      child: Text(plan == null ? 'Set plan' : 'Change plan'),
                    ),
                    OutlinedButton(
                      key: Key('resort-status-btn-${resort.propertyId}'),
                      onPressed: () => _confirmAndSetStatus(context, ref),
                      child: Text(suspended ? 'Reactivate' : 'Suspend'),
                    ),
                  ],
                ),
              ),
            ],
            if (pending) ...[
              const SizedBox(height: Spacing.sm),
              Text(
                'Waiting for review: see Pending review above.',
                key: Key('resort-pending-note-${resort.propertyId}'),
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _changePlan(BuildContext context) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => ChangePlanDialog(resort: resort),
    );
    if (saved == true) onChanged();
  }

  Future<void> _confirmAndSetStatus(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final suspending = resort.status != 'suspended';
    final newStatus = suspending ? 'suspended' : 'active';
    final actionLabel = suspending ? 'Suspend' : 'Reactivate';

    // Pop with the dialog's own context: showDialog puts the dialog on the
    // root navigator, but if this card is ever embedded inside the
    // router's ShellRoute, the screen's `context` would resolve to the
    // shell navigator, so popping that would remove the page and leave the
    // dialog up.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('$actionLabel ${resort.name}?'),
        content: Text(
          suspending
              ? 'Staff at this resort will no longer be able to make changes. '
                'The guest can still read and cancel their bookings.'
              : 'This resort will be reactivated and staff can work again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(actionLabel),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      await ref
          .read(platformSourceProvider)
          .setStatus(resort.propertyId, newStatus);
      onChanged();
    } on BookingFailure catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(FailureView.messageFor(e))));
      }
    }
  }
}

/// The plan line next to the tier chip. A lapsed plan gets a warning icon
/// and the error colour on top of the word "Lapsed", so the state never
/// depends on colour alone.
class PlanLine extends StatelessWidget {
  const PlanLine({super.key, required this.plan});

  final ResortPlan plan;

  @override
  Widget build(BuildContext context) {
    final text = planStatusLine(plan);
    if (!plan.lapsed) return Text(text);
    final error = Theme.of(context).colorScheme.error;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.warning_amber_rounded, size: 18, color: error),
        const SizedBox(width: Spacing.xs),
        Flexible(child: Text(text, style: TextStyle(color: error))),
      ],
    );
  }
}
