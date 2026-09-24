import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/current_resort.dart';
import '../../core/errors.dart';
import '../../core/theme/theme_toggle_button.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/brand_mark.dart';
import '../../core/widgets/failure_view.dart';
import '../../data/models/resort_membership.dart';
import '../../data/repositories/auth_repository.dart';
import '../resorts/resort_switcher.dart';

/// Responsive chrome shared by every signed-in screen: a bottom navigation
/// bar on narrow layouts, a navigation rail on wide ones. Destinations vary
/// by role, but the router redirect is what actually blocks access.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.child});
  final Widget child;

  static const _customerDestinations = [
    (path: '/', icon: Icons.home_outlined, label: 'Browse'),
    (path: '/bookings', icon: Icons.event_outlined, label: 'Bookings'),
    (path: '/my-stay', icon: Icons.holiday_village_outlined, label: 'My Stay'),
  ];

  // Dashboard / Bookings / More -- Browse (the customer holiday-shopping
  // flow) drops off entirely here, matching staff/accountant below: it was
  // never admin work to begin with. `/admin/more` holds every management
  // screen (Properties, Users, Staff shifts, ...) that isn't one of the
  // dashboard's own Quick Actions -- see `AdminMoreScreen`'s own doc for
  // why that split exists.
  static const _adminDestinations = [
    (path: '/admin', icon: Icons.dashboard_outlined, label: 'Dashboard'),
    // `/admin/bookings` (every reservation across every property), not the
    // customer-facing `/bookings` (that admin account's own, always-empty
    // booking history) -- an admin tapping "Bookings" wants the former.
    (path: '/admin/bookings', icon: Icons.event_outlined, label: 'Bookings'),
    (path: '/admin/more', icon: Icons.more_horiz, label: 'More'),
  ];

  // super_admin gets an "Owner" tab instead of "Admin" -- the Owner hub
  // itself links out to `/admin/*` for anything not rebuilt in the Owner
  // flow (properties/units, outbox, block dates, ...), so no admin
  // capability becomes unreachable by swapping this destination out.
  static const _ownerDestinations = [
    (path: '/', icon: Icons.home_outlined, label: 'Browse'),
    // Same reasoning as `_adminDestinations` above -- a super_admin's own
    // `/bookings` history is always empty; `/admin/bookings` (every
    // reservation across every property) is what "Bookings" here means.
    // `redirectFor` already permits `/admin/*` for `{owner, admin}`, so
    // this needs no router change.
    (path: '/admin/bookings', icon: Icons.event_outlined, label: 'Bookings'),
    (path: '/owner', icon: Icons.apartment_outlined, label: 'Owner'),
  ];

  // Staff and accountant work entirely within their own tools -- Browse is
  // the customer holiday-shopping flow, which is none of their job, so it
  // is not one of these destinations. Staff/accountant cannot reach
  // `/admin` (that stays admin-only), but `report_revenue`/
  // `report_occupancy` explicitly permit them -- and the router allows
  // `/admin/reports` for staff-or-above (see `router.dart`) -- so Reports
  // must stay reachable from here. Dashboard now points at `/staff/dashboard`
  // (the staff-operations hub), not `/admin/dashboard` (the financial
  // summary) -- that route stays admin-only-reachable via `AdminMoreScreen`,
  // untouched by this change.
  static const _staffDestinations = [
    (path: '/staff', icon: Icons.task_alt_outlined, label: 'Today'),
    (
      path: '/staff/dashboard',
      icon: Icons.dashboard_outlined,
      label: 'Dashboard',
    ),
    (
      path: '/admin/reports',
      icon: Icons.summarize_outlined,
      label: 'Reports',
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider).value;
    final resort = ref.watch(currentResortProvider);
    final destinations = switch (resort?.role) {
      ResortRole.owner => _ownerDestinations,
      ResortRole.admin => _adminDestinations,
      ResortRole.staff || ResortRole.accountant => _staffDestinations,
      null => _customerDestinations,
    };

    final location = GoRouterState.of(context).uri.path;
    var index = destinations.indexWhere((d) => location == d.path);
    if (index < 0) index = 0;

    void go(int i) => context.go(destinations[i].path);

    final wide = MediaQuery.sizeOf(context).width >= PasalaTokens.wideBreakpoint;

    return Scaffold(
      appBar: AppBar(
        title: const BrandMark(),
        actionsPadding: const EdgeInsets.symmetric(horizontal: Spacing.sm),
        actions: [
          if (user != null) ...[
            // Renders nothing for a user with 0 or 1 memberships (see
            // `ResortSwitcher`'s own doc comment) -- shown for every
            // signed-in staff role (owner/admin/staff/accountant), never
            // the customer bar below, since a customer holds no resort
            // membership to switch between.
            if (resort != null) const ResortSwitcher(),
            if (resort == null)
              // Customers get a bell + profile avatar instead of a bare
              // sign-out icon -- there is no notifications feature or
              // dedicated profile screen behind these yet, so the bell stays
              // decorative and the avatar opens a sheet with just the one
              // thing that already existed here (sign out), rather than
              // implying pages that don't exist.
              ..._customerActions(context, ref)
            else if (resort.role == ResortRole.admin)
              // Same treatment as the customer bar -- a decorative bell, a
              // role label, and a profile avatar opening the shared account
              // sheet (name/email/role + sign out) -- rather than a bare
              // logout icon with no identity shown at all.
              ..._adminActions(context, ref)
            else ...[
              // Owner/staff/accountant: no bell or profile avatar yet (see
              // `_adminActions`'s own comment), but they get the same
              // theme toggle as admin.
              const ThemeToggleButton(),
              IconButton(
                tooltip: 'Sign out',
                icon: const Icon(Icons.logout),
                onPressed: () => signOut(context, ref),
              ),
            ],
          ],
        ],
      ),
      body: wide
          ? Row(children: [
              NavigationRail(
                selectedIndex: index,
                onDestinationSelected: go,
                labelType: NavigationRailLabelType.all,
                leading: const SizedBox(height: Spacing.md),
                destinations: [
                  for (final d in destinations)
                    NavigationRailDestination(
                        icon: Icon(d.icon), label: Text(d.label)),
                ],
              ),
              const VerticalDivider(width: 1),
              Expanded(child: child),
            ])
          : child,
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: index,
              onDestinationSelected: go,
              destinations: [
                for (final d in destinations)
                  NavigationDestination(icon: Icon(d.icon), label: d.label),
              ],
            ),
    );
  }

  List<Widget> _customerActions(BuildContext context, WidgetRef ref) => [
        IconButton(
          tooltip: 'Notifications',
          icon: const Icon(Icons.notifications_outlined),
          onPressed: null,
        ),
        IconButton(
          tooltip: 'Account',
          padding: EdgeInsets.zero,
          icon: const CircleAvatar(
            radius: 16,
            backgroundColor: PasalaTokens.seed,
            child: Icon(Icons.person, color: Colors.white, size: 18),
          ),
          onPressed: () => showAccountSheet(context, ref),
        ),
      ];

  List<Widget> _adminActions(BuildContext context, WidgetRef ref) => [
        const ThemeToggleButton(),
        IconButton(
          tooltip: 'Notifications',
          icon: const Icon(Icons.notifications_outlined),
          onPressed: null,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Spacing.xs),
          child: Text(
            'Admin',
            style: Theme.of(context).textTheme.labelLarge,
          ),
        ),
        IconButton(
          tooltip: 'Account',
          padding: EdgeInsets.zero,
          icon: const CircleAvatar(
            radius: 16,
            backgroundColor: PasalaTokens.seed,
            child: Icon(Icons.person, color: Colors.white, size: 18),
          ),
          onPressed: () => showAccountSheet(context, ref),
        ),
      ];
}

/// Signs the current user out via [authRepositoryProvider] and sends them
/// to `/login`, or surfaces a snackbar if sign-out itself fails. Top-level
/// (not private to [AppShell]) so [showAccountSheet]'s own sign-out button
/// -- and any other screen that needs the exact same behaviour, such as the
/// guest browse hero's profile button -- can reuse it rather than each
/// screen inventing its own sign-out handling.
Future<void> signOut(BuildContext context, WidgetRef ref) async {
  try {
    await ref.read(authRepositoryProvider).signOut();
    if (context.mounted) context.go('/login');
  } on BookingFailure catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(FailureView.messageFor(e))));
    }
  }
}

/// The signed-in user's account sheet: name/email, resort role (when one
/// applies), and a sign-out action. [AppShell]'s customer/admin profile
/// avatars open this; it is also "the existing account route" the guest
/// browse hero's profile button opens (`_BrowseHero` in browse_screen.dart)
/// -- there being no separate account screen/route for a signed-in
/// customer to navigate to, only this shared sheet.
void showAccountSheet(BuildContext context, WidgetRef ref) {
  final user = ref.read(currentUserProvider).value;
  final resort = ref.read(currentResortProvider);
  showModalBottomSheet<void>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              user?.fullName ?? user?.email ?? 'Account',
              style: Theme.of(sheetContext).textTheme.titleMedium,
            ),
            if (user?.fullName != null) ...[
              const SizedBox(height: Spacing.xs),
              Text(
                user!.email,
                style: Theme.of(sheetContext).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(sheetContext).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (user != null && resort != null) ...[
              const SizedBox(height: Spacing.xs),
              Text(
                resortRoleLabel(resort.role),
                style: Theme.of(sheetContext).textTheme.labelMedium?.copyWith(
                  color: Theme.of(sheetContext).colorScheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            const SizedBox(height: Spacing.lg),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                key: const Key('account-sheet-sign-out'),
                icon: const Icon(Icons.logout),
                label: const Text('Sign out'),
                onPressed: () {
                  Navigator.of(sheetContext).pop();
                  unawaited(signOut(context, ref));
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
