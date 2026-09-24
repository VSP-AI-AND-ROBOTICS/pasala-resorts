import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../core/format.dart';
import '../../core/theme/spacing.dart';
import '../../core/widgets/failure_view.dart';
import '../../data/repositories/platform_repository.dart';

String _statusLabel(String status) =>
    status.isEmpty ? status : status[0].toUpperCase() + status.substring(1);

/// One resort on the platform console: name, status, owners, booking
/// summary, and a Suspend (active) or Reactivate (suspended) action --
/// none for an archived resort. [onChanged] runs after a change, so the
/// console refetches the list and the cards.
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
                  label: Text(_statusLabel(resort.status)),
                  backgroundColor: suspended
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
            if (!archived) ...[
              const SizedBox(height: Spacing.sm),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton(
                  key: Key('resort-status-btn-${resort.propertyId}'),
                  onPressed: () => _confirmAndSetStatus(context, ref),
                  child: Text(suspended ? 'Reactivate' : 'Suspend'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _confirmAndSetStatus(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final suspending = resort.status != 'suspended';
    final newStatus = suspending ? 'suspended' : 'active';
    final actionLabel = suspending ? 'Suspend' : 'Reactivate';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('$actionLabel ${resort.name}?'),
        content: Text(
          suspending
              ? 'Staff at this resort will no longer be able to make changes. '
                'The guest can still read and cancel their bookings.'
              : 'This resort will be reactivated and staff can work again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
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
