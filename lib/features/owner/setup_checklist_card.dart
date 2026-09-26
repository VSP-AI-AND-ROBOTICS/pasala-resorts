import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../core/format.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/failure_view.dart';
import '../../data/models/listing.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/listing_repository.dart';
import '../admin/units_screen.dart';
import '../browse/providers.dart';
import 'cancellation_policy_screen.dart';
import 'payment_settings_screen.dart';
import 'property_photos_screen.dart';
import 'tax_settings_screen.dart';

/// Opens the screen that finishes one checklist step; completes when the
/// owner comes back.
typedef OpenSetupStep = Future<void> Function(SetupStep step);

/// Pushes the existing screen for [step] at [propertyId]. Units and rates
/// share `UnitsScreen`, whose menu leads to each unit's rates.
Future<void> openSetupStep(
  BuildContext context,
  WidgetRef ref,
  String propertyId,
  SetupStep step,
) async {
  final navigator = Navigator.of(context);
  final Widget screen = switch (step) {
    SetupStep.photos => PropertyPhotosScreen(propertyId: propertyId),
    SetupStep.units || SetupStep.rates => UnitsScreen(propertyId: propertyId),
    SetupStep.payments => PaymentSettingsScreen(
        property: await ref.read(propertyProvider(propertyId).future)),
    SetupStep.cancellation => CancellationPolicyScreen(
        property: await ref.read(propertyProvider(propertyId).future)),
    SetupStep.tax => TaxSettingsScreen(
        property: await ref.read(propertyProvider(propertyId).future)),
  };
  await navigator.push(MaterialPageRoute<void>(builder: (_) => screen));
}

/// The setup checklist a pending resort's owner sees at the top of `/owner`
/// (P10 spec decisions 3, 10, 11): six steps worked out by the server,
/// each opening its screen and refetched on return, and "Submit for
/// review" once all are done. Done / not done is an icon with a label and
/// a word, never colour alone.
class SetupChecklistCard extends ConsumerStatefulWidget {
  const SetupChecklistCard({
    super.key,
    required this.propertyId,
    required this.resortName,
    this.onOpenStep,
  });

  final String propertyId;
  final String resortName;

  /// Tests pass a recorder; the app uses [openSetupStep].
  final OpenSetupStep? onOpenStep;

  @override
  ConsumerState<SetupChecklistCard> createState() =>
      _SetupChecklistCardState();
}

class _SetupChecklistCardState extends ConsumerState<SetupChecklistCard> {
  bool _submitting = false;

  void _refetch() => ref.invalidate(listingSetupProvider(widget.propertyId));

  Future<void> _open(SetupStep step) async {
    final open = widget.onOpenStep ??
        (s) => openSetupStep(context, ref, widget.propertyId, s);
    await open(step);
    if (mounted) _refetch();
  }

  Future<void> _submit() async {
    setState(() => _submitting = true);
    try {
      await ref.read(listingSourceProvider).submitForReview(widget.propertyId);
      _refetch();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Submitted for review.')));
      }
    } on BookingFailure catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(FailureView.messageFor(e))));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final setup = ref.watch(listingSetupProvider(widget.propertyId));
    final value = setup.value;
    final Widget body;
    if (value != null) {
      body = value.isPending ? _checklist(context, value) : _live(context);
    } else if (setup.hasError) {
      body = _error();
    } else {
      body = const Padding(
        padding: EdgeInsets.all(Spacing.md),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return Card(
      key: const Key('setup-checklist'),
      child: Padding(padding: const EdgeInsets.all(Spacing.md), child: body),
    );
  }

  Widget _checklist(BuildContext context, ListingSetup setup) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final submitted = setup.submittedAt;
    final total = SetupStep.values.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Finish setting up ${widget.resortName}',
                  style: textTheme.titleMedium),
            ),
            IconButton(
              tooltip: 'Refresh checklist',
              icon: const Icon(Icons.refresh),
              onPressed: _refetch,
            ),
          ],
        ),
        Text(
          'Your resort is hidden from guests until ResortHub approves it.',
          style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: Spacing.sm),
        Text('${setup.doneCount} of $total done',
            key: const Key('setup-progress')),
        const SizedBox(height: Spacing.xs),
        LinearProgressIndicator(value: setup.doneCount / total),
        const SizedBox(height: Spacing.sm),
        for (final step in SetupStep.values)
          ListTile(
            key: Key('setup-step-${step.name}'),
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              setup.isDone(step)
                  ? Icons.check_circle
                  : Icons.radio_button_unchecked,
              color:
                  setup.isDone(step) ? scheme.primary : scheme.onSurfaceVariant,
              semanticLabel: setup.isDone(step) ? 'Done' : 'Not done',
            ),
            title: Text(step.title),
            subtitle: Text(step.hint),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _open(step),
          ),
        const SizedBox(height: Spacing.sm),
        if (submitted != null)
          Text(
            'Submitted for review on ${formatDate(submitted.toLocal())}. '
            'We will email you when it is decided.',
            key: const Key('setup-submitted'),
          )
        else ...[
          FilledButton(
            key: const Key('setup-submit'),
            onPressed: setup.complete && !_submitting ? _submit : null,
            child: const Text('Submit for review'),
          ),
          if (!setup.complete) ...[
            const SizedBox(height: Spacing.xs),
            Text('Complete every step to submit.', style: textTheme.bodySmall),
          ],
        ],
      ],
    );
  }

  Widget _live(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Your resort is live',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: Spacing.xs),
          Text('ResortHub approved ${widget.resortName}. '
              'Guests can now find and book it.'),
          const SizedBox(height: Spacing.sm),
          TextButton(
            key: const Key('setup-live-refresh'),
            // Refetching the user updates the membership's status, so the
            // owner hub stops showing this card.
            onPressed: () => ref.invalidate(currentUserProvider),
            child: const Text('Refresh'),
          ),
        ],
      );

  Widget _error() => Row(
        children: [
          const Expanded(child: Text('Could not load your setup checklist')),
          TextButton(onPressed: _refetch, child: const Text('Retry')),
        ],
      );
}
