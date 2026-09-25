import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../core/format.dart';
import '../../core/theme/spacing.dart';
import '../../core/widgets/failure_view.dart';
import '../../data/models/listing.dart';
import '../../data/models/subscription.dart';
import '../../data/repositories/listing_repository.dart';

/// The Pending review filter (P10), applied on the device like the resort
/// filter: [query] matches the resort name, the city or the applicant's
/// email, ignoring case and surrounding spaces; a [tier] keeps only that
/// tier. Order is kept.
List<PendingListing> filterPendingListings(
  List<PendingListing> pending, {
  String query = '',
  SubscriptionTier? tier,
}) {
  final q = query.trim().toLowerCase();
  bool matches(PendingListing p) =>
      q.isEmpty ||
      p.name.toLowerCase().contains(q) ||
      p.city.toLowerCase().contains(q) ||
      p.applicantEmail.toLowerCase().contains(q);
  return [
    for (final p in pending)
      if ((tier == null || p.tier == tier) && matches(p)) p,
  ];
}

/// The console's "Waiting for review" card: submitted applications
/// waiting for a decision, and how many are still being set up. Tapping it
/// switches the Pending review filter.
class PendingListingsCard extends ConsumerWidget {
  const PendingListingsCard({
    super.key,
    required this.selected,
    required this.onTap,
  });

  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending =
        ref.watch(pendingListingsProvider).value ?? const <PendingListing>[];
    final submitted = pending.where((p) => p.submitted).length;
    final settingUp = pending.length - submitted;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      key: const Key('pending-listings-card'),
      color: selected ? scheme.secondaryContainer : null,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(Spacing.md),
          child: Row(
            children: [
              Icon(Icons.pending_actions_outlined, color: scheme.primary),
              const SizedBox(width: Spacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Waiting for review', style: textTheme.labelLarge),
                    Text('$submitted',
                        key: const Key('pending-count'),
                        style: textTheme.headlineSmall),
                    Text('$settingUp setting up',
                        style: textTheme.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The list shown while the Pending review filter is on.
class PendingListingsList extends ConsumerWidget {
  const PendingListingsList({
    super.key,
    required this.query,
    required this.tier,
    required this.onChanged,
  });

  final String query;
  final SubscriptionTier? tier;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      ref.watch(pendingListingsProvider).when(
            loading: () => const Padding(
              padding: EdgeInsets.all(Spacing.lg),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => FailureView(
              error: e,
              onRetry: () => ref.invalidate(pendingListingsProvider),
            ),
            data: (pending) {
              final shown =
                  filterPendingListings(pending, query: query, tier: tier);
              if (shown.isEmpty) {
                return const Padding(
                  key: Key('no-pending-listings'),
                  padding: EdgeInsets.all(Spacing.lg),
                  child: Text('No resorts are waiting for review.',
                      textAlign: TextAlign.center),
                );
              }
              return Column(
                children: [
                  for (final l in shown) ...[
                    PendingListingCard(listing: l, onChanged: onChanged),
                    const SizedBox(height: Spacing.sm),
                  ],
                ],
              );
            },
          );
}

/// One undecided application: the resort, the applicant, the contact
/// details, the plan, whether it was submitted, the six checklist items
/// (a check or a cross beside each title), and Approve / Reject.
class PendingListingCard extends ConsumerWidget {
  const PendingListingCard({
    super.key,
    required this.listing,
    required this.onChanged,
  });

  final PendingListing listing;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final id = listing.propertyId;
    final submittedAt = listing.submittedAt;

    return Card(
      key: Key('pending-listing-$id'),
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(listing.name, style: textTheme.titleMedium)),
                Chip(label: Text(listing.tier.label), side: BorderSide.none),
              ],
            ),
            Text('${listing.city} · ${listing.address}'),
            Text(listing.applicantName == null
                ? listing.applicantEmail
                : '${listing.applicantName} · ${listing.applicantEmail}'),
            Text(listing.contactPhone),
            const SizedBox(height: Spacing.xs),
            Text(listing.description,
                style: textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(height: Spacing.sm),
            Text(
              submittedAt == null
                  ? 'Setting up — not submitted yet'
                  : 'Submitted ${formatDate(submittedAt.toLocal())}',
              style: textTheme.labelLarge?.copyWith(
                  color: submittedAt == null
                      ? scheme.onSurfaceVariant
                      : scheme.primary),
            ),
            const SizedBox(height: Spacing.sm),
            Wrap(
              spacing: Spacing.sm,
              runSpacing: Spacing.xs,
              children: [
                for (final step in SetupStep.values)
                  Chip(
                    key: Key('pending-step-$id-${step.name}'),
                    avatar: Icon(
                      (listing.setup[step] ?? false) ? Icons.check : Icons.close,
                      size: 16,
                    ),
                    label: Text(step.title),
                    side: BorderSide.none,
                  ),
              ],
            ),
            const SizedBox(height: Spacing.sm),
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                spacing: Spacing.sm,
                children: [
                  TextButton(
                    key: Key('reject-$id'),
                    onPressed: () => _reject(context),
                    child: const Text('Reject'),
                  ),
                  FilledButton(
                    key: Key('approve-$id'),
                    onPressed: listing.canApprove
                        ? () => _approve(context, ref)
                        : null,
                    child: const Text('Approve'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _approve(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Approve ${listing.name}?'),
        content: const Text('It goes live for guests now.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('approve-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Approve'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(listingReviewSourceProvider).approve(listing.propertyId);
      onChanged();
    } on BookingFailure catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(FailureView.messageFor(e))));
      }
    }
  }

  Future<void> _reject(BuildContext context) async {
    final rejected = await showDialog<bool>(
      context: context,
      builder: (_) => RejectListingDialog(listing: listing),
    );
    if (rejected == true) onChanged();
  }
}

/// Asks for the reason the owner will see (5 to 500 characters, as
/// `reject_listing` requires), then rejects. Pops `true` once rejected.
class RejectListingDialog extends ConsumerStatefulWidget {
  const RejectListingDialog({super.key, required this.listing});

  final PendingListing listing;

  @override
  ConsumerState<RejectListingDialog> createState() =>
      _RejectListingDialogState();
}

class _RejectListingDialogState extends ConsumerState<RejectListingDialog> {
  final _formKey = GlobalKey<FormState>();
  final _reason = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(listingReviewSourceProvider)
          .reject(widget.listing.propertyId, _reason.text.trim());
      if (mounted) Navigator.of(context).pop(true);
    } on BookingFailure catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = FailureView.messageFor(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text('Reject ${widget.listing.name}?'),
        content: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                key: const Key('reject-reason'),
                controller: _reason,
                decoration: const InputDecoration(
                    labelText: 'Reason (the owner sees this)'),
                minLines: 2,
                maxLines: 4,
                maxLength: 500,
                validator: validateRejectionReason,
              ),
              if (_error != null)
                Text(_error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('reject-confirm'),
            onPressed: _busy ? null : _submit,
            child: const Text('Reject'),
          ),
        ],
      );
}
