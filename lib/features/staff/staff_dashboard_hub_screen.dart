import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/tokens.dart';
import '../../data/models/app_user.dart';
import '../../data/repositories/auth_repository.dart';

/// One entry point on the staff-operations hub. Pure data so the hub's
/// contents (and every path's `/staff/*` prefix, which is what
/// `redirectFor` gates on) are testable without a widget -- see
/// `staff_dashboard_hub_screen_test.dart`.
typedef StaffHubSection = ({String path, IconData icon, String title});

const staffHubSections = <StaffHubSection>[
  (path: '/staff/profile', icon: Icons.badge_outlined, title: 'Profile'),
  (
    path: '/staff/working-hours',
    icon: Icons.schedule_outlined,
    title: 'Working Hours',
  ),
  (
    path: '/staff/leave',
    icon: Icons.event_busy_outlined,
    title: 'Leave Management',
  ),
  (
    path: '/staff/tasks',
    icon: Icons.checklist_outlined,
    title: 'Assigned Work',
  ),
  (
    path: '/staff/schedules',
    icon: Icons.calendar_month_outlined,
    title: 'Work Schedules',
  ),
  (
    path: '/staff/time-slots',
    icon: Icons.access_time_outlined,
    title: 'Time Slots',
  ),
  (
    path: '/staff/daily-status',
    icon: Icons.fact_check_outlined,
    title: 'Daily Work Status',
  ),
  (
    path: '/staff/food-orders',
    icon: Icons.restaurant_outlined,
    title: 'Food Orders',
  ),
  (
    path: '/staff/service-requests',
    icon: Icons.room_service_outlined,
    title: 'Service Requests',
  ),
  (
    path: '/staff/maintenance',
    icon: Icons.build_outlined,
    title: 'Maintenance',
  ),
];

/// Sections gated by more than a bare `/staff` prefix, so they live outside
/// [staffHubSections] (kept `/staff/*`-only -- see that list's own doc
/// comment and `staff_dashboard_hub_screen_test.dart`, which asserts
/// exactly that). Both point at real, existing screens whose RLS grant was
/// already wider than the app's navigation ever exposed:
/// `food_activity_sales_read`/`_insert` (0026_food_activity_sales.sql)
/// grant staff-or-above, and `expenses_read` (0027_expenses.sql) grants
/// admin/accountant/super_admin -- so every signed-in user reaching this
/// hub can log a food/activity sale, and an accountant specifically can
/// also read (though not write -- see `ExpensesScreen`) the books.
List<StaffHubSection> _extraSections(UserRole role) => [
      (
        path: '/owner/food-sales',
        icon: Icons.point_of_sale_outlined,
        title: 'Food & Activity Sales',
      ),
      if (role == UserRole.accountant)
        (
          path: '/owner/expenses',
          icon: Icons.receipt_long_outlined,
          title: 'Expenses',
        ),
    ];

/// `/staff/dashboard` -- the staff-operations home. Every card here is a
/// staff/accountant responsibility, never a customer-facing one (Browse is
/// deliberately absent from this whole role's nav, see `AppShell`).
class StaffDashboardHubScreen extends ConsumerWidget {
  const StaffDashboardHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(currentUserProvider).value?.role;
    final sections = [
      ...staffHubSections,
      if (role != null) ..._extraSections(role),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard')),
      body: ListView.separated(
        padding: const EdgeInsets.all(Spacing.md),
        itemCount: sections.length,
        separatorBuilder: (_, _) => const SizedBox(height: Spacing.sm),
        itemBuilder: (context, i) {
          final section = sections[i];
          return Card(
            child: ListTile(
              leading: Icon(section.icon),
              title: Text(section.title),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push(section.path),
            ),
          );
        },
      ),
    );
  }
}
