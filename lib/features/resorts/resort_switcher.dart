import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/current_resort.dart';
import '../../core/router.dart';
import '../../data/models/resort_membership.dart';
import '../../data/repositories/auth_repository.dart';

/// App-bar action for a user with 2+ resort memberships -- renders nothing
/// for anyone with 0 or 1 (see `resolveCurrentResort`, which already picks
/// the single membership automatically, so a switcher would have nothing
/// useful to offer there). Embedded in `AppShell`'s admin/owner/staff/
/// accountant app bars (never the customer one -- a customer has no
/// membership to switch between).
///
/// Picking a resort persists it via `currentResortProvider.notifier.select`
/// and then navigates straight to that resort's own landing path (the same
/// `landingPathFor` the router's redirect uses on sign-in) -- e.g. picking
/// a resort where the user is staff lands on `/staff`, not wherever the
/// admin screen they switched from happens to be, since that screen may
/// not even be reachable at the new resort's role.
class ResortSwitcher extends ConsumerWidget {
  const ResortSwitcher({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider).value;
    final memberships = user?.memberships ?? const <ResortMembership>[];
    if (user == null || memberships.length < 2) return const SizedBox.shrink();

    return PopupMenuButton<ResortMembership>(
      key: const Key('resort-switcher'),
      tooltip: 'Switch resort',
      icon: const Icon(Icons.swap_horiz),
      onSelected: (membership) async {
        // `select` sets the new resort before it awaits the write to
        // `shared_preferences`, and the router re-checks the current page
        // against it at once -- e.g. `/owner` for a resort where the user
        // is admin becomes `/404`, outside the shell, which unmounts this
        // switcher. So navigate in the same turn, with the router taken
        // up front, instead of after the write behind a `mounted` check.
        final router = GoRouter.of(context);
        final saving = ref
            .read(currentResortProvider.notifier)
            .select(membership.propertyId);
        router.go(landingPathFor(user, membership));
        await saving;
      },
      itemBuilder: (context) => [
        for (final membership in memberships)
          PopupMenuItem(
            key: Key('resort-switcher-${membership.propertyId}'),
            value: membership,
            child: Text(membership.resortName),
          ),
      ],
    );
  }
}
