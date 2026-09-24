import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors.dart';
import '../../core/theme/spacing.dart';
import '../../core/theme/theme_toggle_button.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/failure_view.dart';
import '../../data/models/subscription.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/platform_repository.dart';
import 'platform_totals_row.dart';
import 'resort_card.dart';
import 'resort_filter.dart';

/// `/platform` -- the platform admin's SaaS console (REQ-08): the
/// Subscribed / Active / MRR cards, a live search and a tier filter over
/// every resort, and per resort its status, owners, booking summary and
/// actions. The platform admin has no membership at any resort and no row
/// access to any resort-owned table (see the tenancy design spec), so this
/// screen reads and writes only through [PlatformSource].
///
/// Sits outside `AppShell`'s `ShellRoute` -- like `/choose-resort` -- since
/// its nav destinations are keyed off a current resort the platform admin
/// never has, so it carries its own sign-out action instead.
class PlatformScreen extends ConsumerStatefulWidget {
  const PlatformScreen({super.key});

  @override
  ConsumerState<PlatformScreen> createState() => _PlatformScreenState();
}

class _PlatformScreenState extends ConsumerState<PlatformScreen> {
  final _search = TextEditingController();
  SubscriptionTier? _tier;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// After any change the list and the cards both move.
  void _refresh() {
    ref.invalidate(platformResortsProvider);
    ref.invalidate(platformTotalsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final resortsAsync = ref.watch(platformResortsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Platform'),
        actions: [
          const ThemeToggleButton(),
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: _signOut,
          ),
        ],
      ),
      body: AsyncView(
        value: resortsAsync,
        onRetry: _refresh,
        empty: () => const EmptyState(
          icon: Icons.apartment_outlined,
          title: 'No resorts yet',
          message: 'Tap + to create the first one.',
        ),
        data: (resorts) {
          final shown =
              filterResorts(resorts, query: _search.text, tier: _tier);
          return ListView(
            padding: const EdgeInsets.all(Spacing.md),
            children: [
              const PlatformTotalsRow(),
              const SizedBox(height: Spacing.md),
              ResortFilterBar(
                search: _search,
                tier: _tier,
                onSearchChanged: (_) => setState(() {}),
                onTierChanged: (tier) => setState(() => _tier = tier),
              ),
              const SizedBox(height: Spacing.md),
              if (shown.isEmpty)
                const Padding(
                  key: Key('no-matching-resorts'),
                  padding: EdgeInsets.all(Spacing.lg),
                  child: Text(
                    'No resorts match your search.',
                    textAlign: TextAlign.center,
                  ),
                )
              else
                for (final resort in shown) ...[
                  ResortCard(resort: resort, onChanged: _refresh),
                  const SizedBox(height: Spacing.sm),
                ],
            ],
          );
        },
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

  Future<void> _signOut() async {
    try {
      await ref.read(authRepositoryProvider).signOut();
      if (mounted) context.go('/login');
    } on BookingFailure catch (e) {
      if (mounted) {
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
