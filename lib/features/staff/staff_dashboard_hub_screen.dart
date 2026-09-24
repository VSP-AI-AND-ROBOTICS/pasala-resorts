import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/current_resort.dart';
import '../../core/theme/tokens.dart';
import '../../data/models/resort_membership.dart';

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
/// exactly that). Every one of these points at a real, existing screen
/// whose RLS/RPC grant was already wider than the app's navigation ever
/// exposed: `food_activity_sales_read`/`_insert` (0026) grant
/// staff-or-above, `expenses_read` (0027) grants admin/accountant/
/// super_admin, `outbox_read` (0017) grants staff-or-above, and
/// `check_in_booking`/`checkout_booking` (0037) grant staff-or-above too
/// -- reception need not be an admin account to check a guest in or
/// settle their bill. So every signed-in user reaching this hub can log a
/// sale, check a guest in or out, and read the notification queue; an
/// accountant specifically can also read (though not write -- see
/// `ExpensesScreen`) the books.
List<StaffHubSection> _extraSections(ResortRole role) => [
      (
        path: '/admin/check-in',
        icon: Icons.login_outlined,
        title: 'Check-In',
      ),
      (
        path: '/admin/check-out',
        icon: Icons.logout_outlined,
        title: 'Check-Out',
      ),
      (
        path: '/owner/food-sales',
        icon: Icons.point_of_sale_outlined,
        title: 'Food & Activity Sales',
      ),
      (
        path: '/admin/outbox',
        icon: Icons.outbox_outlined,
        title: 'Outbox',
      ),
      if (role == ResortRole.accountant)
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
    final role = ref.watch(currentResortProvider)?.role;
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
