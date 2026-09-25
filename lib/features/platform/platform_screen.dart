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
import '../../data/repositories/listing_repository.dart';
import '../../data/repositories/platform_repository.dart';
import 'new_resort_dialog.dart';
import 'pending_listings.dart';
import 'plan_prices_dialog.dart';
import 'platform_totals_row.dart';
import 'resort_card.dart';
import 'resort_filter.dart';

/// `/platform` -- the platform admin's SaaS console (REQ-08): the
/// Subscribed / Active / MRR cards, a live search and a tier filter over
/// every resort, per resort its status, owners, plan, booking summary and
/// actions, "Add resort", and the plan prices. A "Waiting for review" card
/// and a Pending review filter show the resort applications waiting for
/// Approve or Reject (P10). The platform admin has no membership at any
/// resort and no row access to any resort-owned table (see the tenancy
/// design spec), so this screen reads and writes only through
/// [PlatformSource].
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

  /// The Pending review filter (P10): per-visit UI state, like the search.
  bool _pendingOnly = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// After any change the list and the cards both move.
  void _refresh() {
    ref.invalidate(platformResortsProvider);
    ref.invalidate(platformTotalsProvider);
    ref.invalidate(pendingListingsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final resortsAsync = ref.watch(platformResortsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Platform'),
        actions: [
          IconButton(
            key: const Key('plan-prices-btn'),
            tooltip: 'Plan prices',
            icon: const Icon(Icons.sell_outlined),
            onPressed: _openPlanPrices,
          ),
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
          message: 'Tap Add resort to create the first one.',
        ),
        data: (resorts) {
          final shown =
              filterResorts(resorts, query: _search.text, tier: _tier);
          return ListView(
            // Room at the bottom so the extended button never covers the
            // last card's actions.
            padding: const EdgeInsets.fromLTRB(
                Spacing.md, Spacing.md, Spacing.md, Spacing.xxl + Spacing.xl),
            children: [
              const PlatformTotalsRow(),
              const SizedBox(height: Spacing.md),
              PendingListingsCard(
                selected: _pendingOnly,
                onTap: () => setState(() => _pendingOnly = !_pendingOnly),
              ),
              const SizedBox(height: Spacing.md),
              ResortFilterBar(
                search: _search,
                tier: _tier,
                onSearchChanged: (_) => setState(() {}),
                onTierChanged: (tier) => setState(() => _tier = tier),
              ),
              const SizedBox(height: Spacing.sm),
              Align(
                alignment: Alignment.centerLeft,
                child: FilterChip(
                  key: const Key('pending-filter'),
                  label: const Text('Pending review'),
                  selected: _pendingOnly,
                  onSelected: (on) => setState(() => _pendingOnly = on),
                ),
              ),
              const SizedBox(height: Spacing.md),
              if (_pendingOnly)
                PendingListingsList(
                  query: _search.text,
                  tier: _tier,
                  onChanged: _refresh,
                )
              else if (shown.isEmpty)
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
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('add-resort-fab'),
        onPressed: () => showDialog<void>(
          context: context,
          builder: (_) => const NewResortDialog(),
        ),
        icon: const Icon(Icons.add),
        label: const Text('Add resort'),
      ),
    );
  }

  Future<void> _openPlanPrices() async {
    try {
      final plans = await ref.read(subscriptionPlansProvider.future);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => PlanPricesDialog(plans: plans),
      );
    } on BookingFailure catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(FailureView.messageFor(e))));
      }
    }
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
