import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/tokens.dart';

/// `/owner` -- the super_admin landing page and hub for the whole Owner
/// flow (Business Dashboard -> Revenue -> Occupancy -> Bookings ->
/// Food/Activity Sales -> Expenses -> Staff Performance -> Reports ->
/// Settings). Reachable only by `super_admin` -- the router redirects
/// everyone else to `/404`, matching `AdminHomeScreen`'s own comment that
/// route guarding is UX only: every RPC/table this hub leads to carries its
/// own real Postgres-level gate independent of this screen.
class OwnerHomeScreen extends StatelessWidget {
  const OwnerHomeScreen({super.key});

  static const _destinations = [
    (
      icon: Icons.dashboard_outlined,
      title: 'Business dashboard',
      subtitle: 'Revenue, occupancy, sales and expenses at a glance',
      path: '/owner/dashboard',
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
  ];

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Owner')),
    body: Padding(
      padding: const EdgeInsets.all(Spacing.md),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = (constraints.maxWidth / 260).floor().clamp(1, 4);
          return GridView.builder(
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
    ),
  );
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
