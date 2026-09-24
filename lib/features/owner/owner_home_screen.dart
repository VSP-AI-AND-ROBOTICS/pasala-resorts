import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/current_resort.dart';
import '../../core/format.dart';
import '../../core/greeting.dart';
import '../../core/theme/tokens.dart';
import '../../data/repositories/auth_repository.dart';
import '../reports/providers.dart';

/// `/owner` -- the super_admin landing page and hub for the whole Owner
/// flow (Business Dashboard -> Revenue -> Occupancy -> Bookings ->
/// Food/Activity Sales -> Expenses -> Staff Performance -> Reports ->
/// Settings). Reachable only by `super_admin` -- the router redirects
/// everyone else to `/404`, matching `AdminHomeScreen`'s own comment that
/// route guarding is UX only: every RPC/table this hub leads to carries its
/// own real Postgres-level gate independent of this screen.
///
/// Leads with a greeting and the two business figures an owner checks
/// first (revenue and net profit this month, from the same
/// `dashboard_summary()` RPC `BusinessDashboardScreen` already reads) --
/// the same "real data at the top, then the destination grid" shape as
/// `AdminHomeScreen`. The destination tiles follow, including Rooms (the
/// room status grid).
class OwnerHomeScreen extends ConsumerWidget {
  const OwnerHomeScreen({super.key});

  static const _destinations = [
    (
      icon: Icons.dashboard_outlined,
      title: 'Business dashboard',
      subtitle: 'Revenue, occupancy, sales and expenses at a glance',
      path: '/owner/dashboard',
    ),
    (
      icon: Icons.account_balance_outlined,
      title: 'Finance',
      subtitle: 'Collections, ledger, tax and settlements',
      path: '/finance',
    ),
    (
      icon: Icons.trending_up_outlined,
      title: 'Revenue',
      subtitle: 'Revenue by date range and property',
      // Reuses the existing Reports screen (Revenue/Occupancy toggle)
      // rather than a second, near-duplicate screen -- see
      // OwnerReportsScreen's own comment for why the two are kept separate.
      path: '/admin/reports',
    ),
    (
      icon: Icons.pie_chart_outline,
      title: 'Occupancy',
      subtitle: 'Occupancy by date range and property',
      path: '/admin/reports',
    ),
    (
      icon: Icons.event_note_outlined,
      title: 'Bookings',
      subtitle: 'Every reservation across every property',
      path: '/admin/bookings',
    ),
    (
      icon: Icons.meeting_room_outlined,
      title: 'Rooms',
      subtitle: 'Room status, housekeeping and maintenance',
      path: '/staff/rooms',
    ),
    (
      icon: Icons.restaurant_outlined,
      title: 'Food & activity sales',
      subtitle: 'Log and review on-site sales',
      path: '/owner/food-sales',
    ),
    (
      icon: Icons.receipt_long_outlined,
      title: 'Expenses',
      subtitle: 'Track business expenses by category',
      path: '/owner/expenses',
    ),
    (
      icon: Icons.leaderboard_outlined,
      title: 'Staff performance',
      subtitle: 'Task completion, attendance and punctuality by staff member',
      path: '/owner/staff-performance',
    ),
    (
      icon: Icons.summarize_outlined,
      title: 'Reports',
      subtitle: 'Export revenue, occupancy, sales and expenses as CSV',
      path: '/owner/reports',
    ),
    (
      icon: Icons.tune_outlined,
      title: 'Settings',
      subtitle: 'Farmhouse info, pricing, policies and permissions',
      path: '/owner/settings',
    ),
    (
      icon: Icons.groups_outlined,
      title: 'Team',
      subtitle: 'Add, re-role or remove who has access to this resort',
      path: '/owner/team',
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider).value;
    final firstName = user?.fullName?.split(' ').first ?? 'Owner';
    final now = DateTime.now();
    // A screen reached without a current resort is impossible after Task
    // 14's redirect.
    final propertyId = ref.watch(currentResortProvider)!.propertyId;
    final summaryAsync = ref.watch(dashboardSummaryProvider(propertyId));
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    final monthRevenue = summaryAsync.value?.monthRevenue;
    final netProfit = summaryAsync.value?.netProfitMonth;

    return Scaffold(
      appBar: AppBar(title: const Text('Owner')),
      body: ListView(
        padding: const EdgeInsets.all(Spacing.md),
        children: [
          Text('${greetingFor(now)}, $firstName 👋',
              style: textTheme.headlineSmall),
          const SizedBox(height: Spacing.xs),
          Text(
            fullDateFor(now),
            style:
                textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: Spacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _KpiCard(
                  icon: Icons.currency_rupee,
                  label: 'Revenue this month',
                  value: monthRevenue == null ? '—' : formatInr(monthRevenue),
                  color: scheme.primary,
                ),
              ),
              const SizedBox(width: Spacing.md),
              Expanded(
                child: _KpiCard(
                  icon: Icons.trending_up,
                  label: 'Net profit this month',
                  value: netProfit == null ? '—' : formatInr(netProfit),
                  // Red reads as "losing money this month" -- a real signal
                  // an owner should notice at a glance, not just decoration.
                  color: (netProfit ?? 0) < 0 ? scheme.error : scheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: Spacing.lg),
          Text('MANAGE',
              style: textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant, letterSpacing: 0.5)),
          const SizedBox(height: Spacing.sm),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = (constraints.maxWidth / 260).floor().clamp(1, 4);
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  mainAxisSpacing: Spacing.md,
                  crossAxisSpacing: Spacing.md,
                  childAspectRatio: 1.6,
                ),
                itemCount: _destinations.length,
                itemBuilder: (context, i) {
                  final d = _destinations[i];
                  return _OwnerCard(
                    icon: d.icon,
                    title: d.title,
                    subtitle: d.subtitle,
                    onTap: () => context.go(d.path),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color),
            const SizedBox(height: Spacing.sm),
            Text(value,
                style: textTheme.headlineSmall
                    ?.copyWith(color: color, fontWeight: FontWeight.w700)),
            const SizedBox(height: Spacing.xs),
            Text(label,
                style: textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

class _OwnerCard extends StatelessWidget {
  const _OwnerCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(Spacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: scheme.primary, size: 32),
              const SizedBox(height: Spacing.sm),
              Text(title, style: textTheme.titleMedium),
              const SizedBox(height: Spacing.xs),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
