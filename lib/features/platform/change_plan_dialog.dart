import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../core/format.dart';
import '../../core/theme/spacing.dart';
import '../../core/widgets/failure_view.dart';
import '../../data/models/subscription.dart';
import '../../data/repositories/platform_repository.dart';

/// "Change plan" / "Set plan" on a resort card: the tier, the status, the
/// date that status needs (a trial's last day, required; or the paid-until
/// date, optional) and notes, saved with `set_resort_subscription`. Pops
/// `true` after a save so the caller refetches the list and the cards,
/// `false` on Cancel.
class ChangePlanDialog extends ConsumerStatefulWidget {
  const ChangePlanDialog({super.key, required this.resort, this.today});

  final ResortSummary resort;

  /// Today's date, for the default 30-day trial of a resort with no plan.
  /// Defaults to the device's date; tests pin it.
  final DateTime? today;

  @override
  ConsumerState<ChangePlanDialog> createState() => _ChangePlanDialogState();
}

class _ChangePlanDialogState extends ConsumerState<ChangePlanDialog> {
  late SubscriptionTier _tier;
  late SubscriptionStatus _status;
  DateTime? _trialEndsOn;
  DateTime? _paidThrough;
  final _notes = TextEditingController();
  String? _error;
  bool _busy = false;

  DateTime get _today {
    final now = widget.today ?? DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  bool get _isTrial => _status == SubscriptionStatus.trial;

  @override
  void initState() {
    super.initState();
    final plan = widget.resort.plan;
    if (plan == null) {
      // A resort with no plan starts where "Add resort" would: a 30-day
      // Starter trial.
      final today = _today;
      _tier = SubscriptionTier.starter;
      _status = SubscriptionStatus.trial;
      _trialEndsOn = DateTime(today.year, today.month, today.day + 30);
    } else {
      _tier = plan.tier;
      _status = plan.status;
      _trialEndsOn = plan.trialEndsOn;
      _paidThrough = plan.paidThrough;
      _notes.text = plan.notes ?? '';
    }
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final current = _isTrial ? _trialEndsOn : _paidThrough;
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? _today,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _error = null;
      if (_isTrial) {
        _trialEndsOn = picked;
      } else {
        _paidThrough = picked;
      }
    });
  }

  Future<void> _save() async {
    if (_isTrial && _trialEndsOn == null) {
      setState(() => _error = 'Pick the date the trial ends.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final notes = _notes.text.trim();
      await ref.read(platformSourceProvider).setSubscription(
            widget.resort.propertyId,
            tier: _tier,
            status: _status,
            trialEndsOn: _isTrial ? _trialEndsOn : null,
            paidThrough: _isTrial ? null : _paidThrough,
            notes: notes.isEmpty ? null : notes,
          );
      if (mounted) Navigator.of(context).pop(true);
    } on BookingFailure catch (e) {
      if (mounted) setState(() => _error = FailureView.messageFor(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final date = _isTrial ? _trialEndsOn : _paidThrough;

    return AlertDialog(
      title: Text('Plan for ${widget.resort.name}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<SubscriptionTier>(
              key: const Key('plan-tier'),
              initialValue: _tier,
              decoration: const InputDecoration(labelText: 'Tier'),
              items: [
                for (final t in SubscriptionTier.values)
                  DropdownMenuItem(value: t, child: Text(t.label)),
              ],
              onChanged: (t) {
                if (t != null) setState(() => _tier = t);
              },
            ),
            const SizedBox(height: Spacing.md),
            SegmentedButton<SubscriptionStatus>(
              key: const Key('plan-status'),
              segments: [
                for (final s in SubscriptionStatus.values)
                  ButtonSegment(value: s, label: Text(s.label)),
              ],
              selected: {_status},
              onSelectionChanged: (selected) => setState(() {
                _status = selected.first;
                _error = null;
              }),
            ),
            const SizedBox(height: Spacing.md),
            Row(
              children: [
                Expanded(child: Text(_isTrial ? 'Trial ends' : 'Paid until')),
                TextButton.icon(
                  key: const Key('plan-date'),
                  onPressed: _busy ? null : _pickDate,
                  icon: const Icon(Icons.event_outlined),
                  label: Text(date == null ? 'No end date' : formatDate(date)),
                ),
                if (!_isTrial && _paidThrough != null)
                  IconButton(
                    key: const Key('plan-date-clear'),
                    tooltip: 'No end date',
                    icon: const Icon(Icons.clear),
                    onPressed: () => setState(() => _paidThrough = null),
                  ),
              ],
            ),
            const SizedBox(height: Spacing.sm),
            TextField(
              key: const Key('plan-notes'),
              controller: _notes,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Notes',
                helperText: "Visible to the resort's owners and admins",
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: Spacing.sm),
              Text(_error!, style: TextStyle(color: scheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('plan-save'),
          onPressed: _busy ? null : _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
