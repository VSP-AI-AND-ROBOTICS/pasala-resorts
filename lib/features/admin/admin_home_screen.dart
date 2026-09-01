import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/tokens.dart';

/// `/admin` landing page. Reachable only by `isAdmin` users -- the router
/// redirects everyone else to `/404`, and `properties_write`/`units_write`
/// RLS policies are the real enforcement underneath.
class AdminHomeScreen extends StatelessWidget {
  const AdminHomeScreen({super.key});

  static const _destinations = [
    (
      icon: Icons.home_work_outlined,
      title: 'Properties',
      subtitle: 'Manage properties, units and rates',
      path: '/admin/properties',
    ),
    (
      icon: Icons.event_note_outlined,
      title: 'All bookings',
      subtitle: 'Every reservation across every property',
      path: '/admin/bookings',
    ),
    (
      icon: Icons.task_alt_outlined,
      title: 'Today',
      subtitle: 'Arrivals, departures and who is in house',
      path: '/staff',
    ),
    (
      icon: Icons.dashboard_outlined,
      title: 'Dashboard',
      subtitle: 'Revenue, occupancy and the business at a glance',
      path: '/admin/dashboard',
    ),
    (
      icon: Icons.summarize_outlined,
      title: 'Reports',
      subtitle: 'Revenue and occupancy by date range, exportable as CSV',
      path: '/admin/reports',
    ),
    (
      icon: Icons.outbox_outlined,
      title: 'Outbox',
      subtitle: 'Queued booking notifications -- not yet sent to anyone',
      path: '/admin/outbox',
    ),
    (
      icon: Icons.people_outline,
      title: 'Users',
      subtitle: 'See every account and promote staff to the right role',
      path: '/admin/users',
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
      subtitle: 'See who\'s checked in, today or any past day',
      path: '/admin/attendance',
    ),
    (
      icon: Icons.checklist_outlined,
      title: 'Tasks',
      subtitle: 'Assign and track staff work',
      path: '/admin/tasks',
    ),
    (
      icon: Icons.how_to_reg_outlined,
      title: 'Check-In',
      subtitle: 'Check today\'s confirmed arrivals in',
      path: '/admin/check-in',
    ),
    (
      icon: Icons.restaurant_outlined,
      title: 'Kitchen orders',
      subtitle: 'Every in-stay food order, by status',
      path: '/admin/kitchen-orders',
    ),
    (
      icon: Icons.room_service_outlined,
      title: 'Service requests',
      subtitle: 'Assign and track in-stay service requests',
      path: '/admin/service-requests',
    ),
    (
      icon: Icons.build_outlined,
      title: 'Maintenance',
      subtitle: 'Assign and track reported maintenance issues',
      path: '/admin/maintenance',
    ),
  ];

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Admin')),
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
              return _AdminCard(
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

class _AdminCard extends StatelessWidget {
  const _AdminCard({
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
