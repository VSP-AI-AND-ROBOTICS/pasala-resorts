import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/failure_view.dart';
import '../../data/models/app_user.dart';
import '../../data/repositories/auth_repository.dart';

/// Responsive chrome shared by every signed-in screen: a bottom navigation
/// bar on narrow layouts, a navigation rail on wide ones. Destinations vary
/// by role, but the router redirect is what actually blocks access.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.child});
  final Widget child;

  static const _customerDestinations = [
    (path: '/', icon: Icons.home_outlined, label: 'Browse'),
    (path: '/bookings', icon: Icons.event_outlined, label: 'Bookings'),
  ];

  static const _adminDestinations = [
    (path: '/', icon: Icons.home_outlined, label: 'Browse'),
    (path: '/bookings', icon: Icons.event_outlined, label: 'Bookings'),
    (path: '/admin', icon: Icons.settings_outlined, label: 'Admin'),
  ];

  static const _staffDestinations = [
    (path: '/', icon: Icons.home_outlined, label: 'Browse'),
    (path: '/staff', icon: Icons.task_alt_outlined, label: 'Today'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider).value;
    final destinations = switch (user?.role) {
      UserRole.admin || UserRole.superAdmin => _adminDestinations,
      UserRole.staff || UserRole.accountant => _staffDestinations,
      _ => _customerDestinations,
    };

    final location = GoRouterState.of(context).uri.path;
    var index = destinations.indexWhere((d) => location == d.path);
    if (index < 0) index = 0;

    void go(int i) => context.go(destinations[i].path);

    final wide = MediaQuery.sizeOf(context).width >= 840;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pasala Resorts'),
        actionsPadding: const EdgeInsets.symmetric(horizontal: Spacing.sm),
        actions: [
          if (user != null)
            IconButton(
              tooltip: 'Sign out',
              icon: const Icon(Icons.logout),
              onPressed: () async {
                try {
                  await ref.read(authRepositoryProvider).signOut();
                  if (context.mounted) context.go('/login');
                } on BookingFailure catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(FailureView.messageFor(e))));
                  }
                }
              },
            ),
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
}
