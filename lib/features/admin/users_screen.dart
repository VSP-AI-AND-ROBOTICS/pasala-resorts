import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/failure_view.dart';
import '../../data/models/admin_profile.dart';
import '../../data/models/app_user.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/user_admin_repository.dart';

String _roleLabel(UserRole role) => switch (role) {
      UserRole.customer => 'Customer',
      UserRole.staff => 'Staff',
      UserRole.admin => 'Admin',
      UserRole.accountant => 'Accountant',
      UserRole.superAdmin => 'Super admin',
    };

/// `/admin/users` -- the roster from `public.list_profiles()`, with a role
/// control for a super admin and read-only role text for everyone else who
/// can reach this screen (a plain admin).
///
/// There is no "Add user" button anywhere on this screen, deliberately: an
/// `auth.users` row can only be created with the service-role key, which
/// must never ship inside this client -- see the migration header on
/// 0019_user_admin.sql. The only path to a new account is `/signup`,
/// followed by a super admin promoting the resulting (always `customer`)
/// profile from here -- [_ExplainerBanner] says so up front, so an admin
/// who came looking for that button reads why it doesn't exist instead of
/// guessing.
class UsersScreen extends ConsumerWidget {
  const UsersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profilesAsync = ref.watch(adminProfilesProvider);
    // A plain admin can reach this screen (RLS/list_profiles allow
    // admin-or-above) but `set_user_role` is super_admin-only server-side
    // (0019_user_admin.sql) -- a dropdown that always fails for them would
    // be worse than no control at all, so [_ProfileTile] renders read-only
    // text instead whenever the signed-in user isn't a super admin.
    final canEditRoles =
        ref.watch(currentUserProvider).value?.role == UserRole.superAdmin;

    return Scaffold(
      appBar: AppBar(title: const Text('Users')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ExplainerBanner(canEditRoles: canEditRoles),
          Expanded(
            child: AsyncView(
              value: profilesAsync,
              onRetry: () => ref.invalidate(adminProfilesProvider),
              empty: () => const EmptyState(
                icon: Icons.people_outline,
                title: 'No users yet',
                message: 'Accounts appear here once someone signs up.',
              ),
              data: (profiles) => ListView.builder(
                padding: const EdgeInsets.only(bottom: Spacing.md),
                itemCount: profiles.length,
                itemBuilder: (context, i) => Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Spacing.md,
                    vertical: Spacing.xs,
                  ),
                  child: _ProfileTile(
                    profile: profiles[i],
                    canEditRole: canEditRoles,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExplainerBanner extends StatelessWidget {
  const _ExplainerBanner({required this.canEditRoles});

  /// Whether the signed-in user is a super admin -- mirrors
  /// [UsersScreen.canEditRoles]. When false, an extra line explains why
  /// every row below shows read-only role text instead of a dropdown,
  /// rather than leaving a viewer to guess whether that's a bug.
  final bool canEditRoles;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const Key('sign-up-then-promote-banner'),
      width: double.infinity,
      color: scheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.md,
        vertical: Spacing.sm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: scheme.onSurfaceVariant),
          const SizedBox(width: Spacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'There is no "Add user" button here. New staff create '
                  'their own account at Sign up, then a super admin '
                  'promotes them to the right role below.',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
                if (!canEditRoles)
                  Padding(
                    padding: const EdgeInsets.only(top: Spacing.xs),
                    child: Text(
                      'Only a super admin can change roles, so yours are '
                      'shown here as read-only text.',
                      key: const Key('read-only-role-explainer'),
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileTile extends ConsumerStatefulWidget {
  const _ProfileTile({required this.profile, required this.canEditRole});

  final AdminProfile profile;
  final bool canEditRole;

  @override
  ConsumerState<_ProfileTile> createState() => _ProfileTileState();
}

class _ProfileTileState extends ConsumerState<_ProfileTile> {
  bool _busy = false;

  Future<void> _changeRole(UserRole role) async {
    if (role == widget.profile.role) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(userAdminSourceProvider)
          .setRole(widget.profile.id, role);
      // Refetch rather than patch the row locally: the server is the only
      // source of truth for whether the change actually landed (e.g. the
      // P0014 last-super-admin guard rejects some changes outright), and a
      // stale optimistic update here would show a role that was never
      // actually granted.
      ref.invalidate(adminProfilesProvider);
    } on BookingFailure catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(FailureView.messageFor(e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;
    final name = (profile.fullName?.trim().isNotEmpty ?? false)
        ? profile.fullName!
        : profile.email;

    return Card(
      child: ListTile(
        title: Text(name),
        subtitle: Text(profile.email),
        trailing: widget.canEditRole
            ? DropdownButton<UserRole>(
                key: Key('role-dropdown-${profile.id}'),
                value: profile.role,
                onChanged: _busy
                    ? null
                    : (role) {
                        if (role != null) _changeRole(role);
                      },
                items: [
                  for (final role in UserRole.values)
                    DropdownMenuItem(
                      value: role,
                      child: Text(_roleLabel(role)),
                    ),
                ],
              )
            : Text(
                _roleLabel(profile.role),
                key: Key('role-text-${profile.id}'),
              ),
      ),
    );
  }
}
