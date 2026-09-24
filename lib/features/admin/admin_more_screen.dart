import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/tokens.dart';

/// `/admin/more` -- every admin/management screen that isn't one of the
/// dashboard's own Quick Actions. Before the dashboard redesign, all of
/// these lived as tiles on `/admin` itself; moving the dashboard to the
/// mockup's Quick-Actions layout displaced them one tap deeper rather than
/// removing them -- every one of these routes still exists and is still
/// admin-reachable, just from here instead.
class AdminMoreScreen extends StatelessWidget {
  const AdminMoreScreen({super.key});

  static const _destinations = [
    (
      icon: Icons.home_work_outlined,
      title: 'Properties',
      subtitle: 'Manage properties, units and rates',
      path: '/admin/properties',
    ),
    (
      icon: Icons.dashboard_outlined,
      title: 'Financial Dashboard',
      subtitle: 'Revenue, occupancy and the business at a glance',
      path: '/admin/dashboard',
    ),
    (
      icon: Icons.account_balance_outlined,
      title: 'Finance',
      subtitle: 'Collections, ledger, tax and settlements',
      path: '/finance',
    ),
    (
      icon: Icons.outbox_outlined,
      title: 'Outbox',
      subtitle: 'Queued booking notifications -- not yet sent to anyone',
      path: '/admin/outbox',
    ),
    (
      icon: Icons.event_busy_outlined,
      title: 'Staff shifts',
      subtitle: 'Assign and manage staff work shifts',
      path: '/admin/staff-shifts',
    ),
    (
      icon: Icons.event_available_outlined,
      title: 'Leave requests',
      subtitle: 'Review and decide staff leave requests',
      path: '/admin/leave-requests',
    ),
    (
      icon: Icons.how_to_reg_outlined,
      title: 'Attendance',
      subtitle: "See who's checked in, today or any past day",
      path: '/admin/attendance',
    ),
    (
      icon: Icons.checklist_outlined,
      title: 'Tasks',
      subtitle: 'Assign and track staff work',
      path: '/admin/tasks',
    ),
    (
      icon: Icons.room_service_outlined,
      title: 'Service requests',
      subtitle: 'Assign and track in-stay service requests',
      path: '/admin/service-requests',
    ),
  ];

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('More')),
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
                  return _MoreCard(
                    icon: d.icon,
                    title: d.title,
                    subtitle: d.subtitle,
                    onTap: () => context.push(d.path),
                  );
                },
              );
            },
          ),
        ),
      );
}

class _MoreCard extends StatelessWidget {
  const _MoreCard({
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
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: scheme.primary, size: 32),
              const SizedBox(height: Spacing.sm),
              Text(title,
                  style: textTheme.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: Spacing.xs),
              Flexible(
                child: Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
