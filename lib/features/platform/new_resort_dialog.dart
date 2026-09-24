import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../core/theme/spacing.dart';
import '../../core/widgets/failure_view.dart';
import '../../data/models/subscription.dart';
import '../../data/repositories/platform_repository.dart';

/// "+ Add resort" (REQ-08): a name, an owner email -- which must belong to
/// an existing account (no in-app account creation; see the tenancy design
/// spec) -- and the plan it starts on: a tier (default Starter) and a
/// trial (default on, 30 days, 1 to 365). With the trial off the resort
/// starts active with no end date.
class NewResortDialog extends ConsumerStatefulWidget {
  const NewResortDialog({super.key});

  @override
  ConsumerState<NewResortDialog> createState() => _NewResortDialogState();
}

class _NewResortDialogState extends ConsumerState<NewResortDialog> {
  final _name = TextEditingController();
  final _ownerEmail = TextEditingController();
  final _trialDays = TextEditingController(text: '30');
  SubscriptionTier _tier = SubscriptionTier.starter;
  bool _trial = true;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _ownerEmail.dispose();
    _trialDays.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _name.text.trim();
    final ownerEmail = _ownerEmail.text.trim();
    if (name.isEmpty || ownerEmail.isEmpty) {
      setState(() => _error = 'Enter a name and an owner email.');
      return;
    }
    var trialDays = 0;
    if (_trial) {
      final days = int.tryParse(_trialDays.text.trim());
      if (days == null || days < 1 || days > 365) {
        setState(() => _error = 'Enter a trial of 1 to 365 days.');
        return;
      }
      trialDays = days;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(platformSourceProvider)
          .createResort(name, ownerEmail, tier: _tier, trialDays: trialDays);
      if (!mounted) return;
      ref.invalidate(platformResortsProvider);
      ref.invalidate(platformTotalsProvider);
      Navigator.of(context).pop();
    } on BookingFailure catch (e) {
      if (mounted) setState(() => _error = FailureView.messageFor(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Add resort'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const Key('new-resort-name'),
                controller: _name,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              const SizedBox(height: Spacing.sm),
              TextField(
                key: const Key('new-resort-owner-email'),
                controller: _ownerEmail,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Owner email',
                  helperText: 'Must belong to an existing account',
                ),
              ),
              const SizedBox(height: Spacing.sm),
              DropdownButtonFormField<SubscriptionTier>(
                key: const Key('new-resort-tier'),
                initialValue: _tier,
                decoration: const InputDecoration(labelText: 'Plan'),
                items: [
                  for (final t in SubscriptionTier.values)
                    DropdownMenuItem(value: t, child: Text(t.label)),
                ],
                onChanged: (t) {
                  if (t != null) setState(() => _tier = t);
                },
              ),
              SwitchListTile(
                key: const Key('new-resort-trial'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Start with a trial'),
                value: _trial,
                onChanged: (on) => setState(() => _trial = on),
              ),
              if (_trial)
                TextField(
                  key: const Key('new-resort-trial-days'),
                  controller: _trialDays,
                  keyboardType: TextInputType.number,
                  decoration:
                      const InputDecoration(labelText: 'Trial length (days)'),
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
            onPressed: _busy ? null : _create,
            child: const Text('Create'),
          ),
        ],
      );
}
