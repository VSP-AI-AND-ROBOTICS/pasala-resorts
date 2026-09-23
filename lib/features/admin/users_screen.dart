import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/failure_view.dart';
import '../../data/models/admin_profile.dart';
import '../../data/models/app_user.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/user_admin_repository.dart';
import 'assign_incharge_dialog.dart';

String _roleLabel(UserRole role) => switch (role) {
      UserRole.customer => 'Customer',
      UserRole.staff => 'Staff / Incharge',
      UserRole.admin => 'Admin',
      UserRole.accountant => 'Accountant',
      UserRole.superAdmin => 'Super admin',
    };

/// `/admin/users` -- the roster from `public.list_profiles()`, with direct
/// incharge assignment controls allowing admins to assign/change operations incharges.
class UsersScreen extends ConsumerWidget {
  const UsersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profilesAsync = ref.watch(adminProfilesProvider);
    final currentUser = ref.watch(currentUserProvider).value;
    final canEditRoles = currentUser?.role == UserRole.superAdmin;
    final isAdminOrAbove = currentUser?.isAdmin ?? true;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Users & Incharges'),
        actions: [
          if (isAdminOrAbove)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              child: FilledButton.icon(
                key: const Key('assign-incharge-action-btn'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.resortCoral,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.badge, size: 18),
                label: const Text('Assign / Change Incharge'),
                onPressed: () {
                  showDialog<bool>(
                    context: context,
                    builder: (context) => const AssignInchargeDialog(),
                  ).then((value) {
                    if (value == true && context.mounted) {
                      ref.invalidate(adminProfilesProvider);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Operations Incharge assigned successfully!'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  });
                },
              ),
            ),
        ],
      ),
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
                  'Operations Incharges can be directly assigned or updated above with their dedicated work email and password provided by the Admin. Other roles are managed via profile promotion.',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
                if (!canEditRoles)
                  Padding(
                    padding: const EdgeInsets.only(top: Spacing.xs),
                    child: Text(
                      'Super admin permissions apply to global roles; resort-level incharge credentials can be managed anytime by resort administrators.',
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
