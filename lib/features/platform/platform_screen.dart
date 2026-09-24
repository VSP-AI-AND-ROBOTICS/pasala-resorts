import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors.dart';
import '../../core/format.dart';
import '../../core/theme/spacing.dart';
import '../../core/theme/theme_toggle_button.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/failure_view.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/platform_repository.dart';

String _statusLabel(String status) =>
    status.isEmpty ? status : status[0].toUpperCase() + status.substring(1);

/// `/platform` -- the platform admin's minimal console: every resort's
/// status, owners and booking/revenue summary from `platform_resorts()`,
/// a Suspend (active) or Reactivate (suspended) action per row -- none for
/// an archived resort -- and a New resort form. The
/// platform admin has no membership at any resort and no row access to
/// any resort-owned table (see the tenancy design spec), so this screen
/// reads and writes exclusively through [PlatformSource]'s three
/// platform-admin-only RPCs.
///
/// Sits outside `AppShell`'s `ShellRoute` -- like `/choose-resort` -- since
/// its nav destinations are keyed off a current resort the platform admin
/// never has, so it carries its own sign-out action instead.
class PlatformScreen extends ConsumerWidget {
  const PlatformScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resortsAsync = ref.watch(platformResortsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Platform'),
        actions: [
          const ThemeToggleButton(),
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: () => _signOut(context, ref),
          ),
        ],
      ),
      body: AsyncView(
        value: resortsAsync,
        onRetry: () => ref.invalidate(platformResortsProvider),
        empty: () => const EmptyState(
          icon: Icons.apartment_outlined,
          title: 'No resorts yet',
          message: 'Tap + to create the first one.',
        ),
        data: (resorts) => ListView.separated(
          padding: const EdgeInsets.all(Spacing.md),
          itemCount: resorts.length,
          separatorBuilder: (_, _) => const SizedBox(height: Spacing.sm),
          itemBuilder: (context, i) =>
              _ResortCard(resort: resorts[i], onChanged: () {
            ref.invalidate(platformResortsProvider);
          }),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => showDialog<void>(
          context: context,
          builder: (_) => const _NewResortDialog(),
        ),
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(authRepositoryProvider).signOut();
      if (context.mounted) context.go('/login');
    } on BookingFailure catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(FailureView.messageFor(e))));
      }
    }
  }
}

class _ResortCard extends ConsumerWidget {
  const _ResortCard({required this.resort, required this.onChanged});

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

/// "New resort" dialog: a name and an owner email, calling
/// `create_resort` -- the owner email must belong to an existing account
/// (no in-app account creation; see the tenancy design spec).
class _NewResortDialog extends ConsumerStatefulWidget {
  const _NewResortDialog();

  @override
  ConsumerState<_NewResortDialog> createState() => _NewResortDialogState();
}

class _NewResortDialogState extends ConsumerState<_NewResortDialog> {
  final _name = TextEditingController();
  final _ownerEmail = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _ownerEmail.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _name.text.trim();
    final ownerEmail = _ownerEmail.text.trim();
    if (name.isEmpty || ownerEmail.isEmpty) {
      setState(() => _error = 'Enter a name and an owner email.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(platformSourceProvider).createResort(name, ownerEmail);
      ref.invalidate(platformResortsProvider);
      if (mounted) Navigator.of(context).pop();
    } on BookingFailure catch (e) {
      setState(() => _error = FailureView.messageFor(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('New resort'),
        content: Column(
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
            if (_error != null) ...[
              const SizedBox(height: Spacing.sm),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
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
