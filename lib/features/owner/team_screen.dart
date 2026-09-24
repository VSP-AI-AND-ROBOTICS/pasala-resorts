import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/current_resort.dart';
import '../../core/errors.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/failure_view.dart';
import '../../data/models/resort_membership.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/resort_member_repository.dart';

/// `/owner/team` -- owner-only (via `redirectFor`'s blanket `/owner/*`
/// owner-only rule), replacing the deleted `/admin/users`. Lists
/// `list_resort_members` for the current resort, with a role dropdown and
/// a remove action per member, and an "Add member" dialog that adds an
/// EXISTING account by email.
///
/// There is still no "create an account" button here, same reasoning as
/// the deleted `UsersScreen`: only `/signup` creates an `auth.users` row
/// (the service-role key that could do it server-side must never ship in
/// this client) -- [_ExplainerBanner] says so up front, reworded for the
/// resort-scoped world: accounts are created at Sign Up, and the owner
/// adds them here by email, resort by resort, instead of a super admin
/// promoting a role globally.
class TeamScreen extends ConsumerWidget {
  const TeamScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final propertyId = ref.watch(currentResortProvider)?.propertyId;
    if (propertyId == null) {
      // The router only ever sends an owner (who always has a current
      // resort) here -- this guards the brief moment right after sign-out
      // or a lost-access redirect, before the router's own redirect fires.
      return const Scaffold(body: SizedBox.shrink());
    }
    final membersAsync = ref.watch(resortMembersProvider(propertyId));

    return Scaffold(
      appBar: AppBar(title: const Text('Team')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _ExplainerBanner(),
          Expanded(
            child: AsyncView(
              value: membersAsync,
              onRetry: () =>
                  ref.invalidate(resortMembersProvider(propertyId)),
              empty: () => const EmptyState(
                icon: Icons.people_outline,
                title: 'No team members yet',
                message: 'Tap + to add someone who has already signed up.',
              ),
              data: (members) => ListView.builder(
                padding: const EdgeInsets.only(bottom: Spacing.md),
                itemCount: members.length,
                itemBuilder: (context, i) => Padding(
                  key: Key('member-row-${members[i].userId}'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: Spacing.md,
                    vertical: Spacing.xs,
                  ),
                  child:
                      _MemberTile(propertyId: propertyId, member: members[i]),
                ),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        key: const Key('add-member-fab'),
        onPressed: () => showDialog<void>(
          context: context,
          builder: (_) => _AddMemberDialog(propertyId: propertyId),
        ),
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _ExplainerBanner extends StatelessWidget {
  const _ExplainerBanner();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const Key('sign-up-then-add-banner'),
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
            child: Text(
              'Accounts are created at Sign Up. Once someone has an '
              'account, add them here by email and pick their role for '
              'this resort.',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

class _MemberTile extends ConsumerStatefulWidget {
  const _MemberTile({required this.propertyId, required this.member});

  final String propertyId;
  final ResortMember member;

  @override
  ConsumerState<_MemberTile> createState() => _MemberTileState();
}

class _MemberTileState extends ConsumerState<_MemberTile> {
  bool _busy = false;

  /// After a change to the signed-in owner's OWN membership, refetch the
  /// user so the router and the resort switcher stop acting on the old
  /// role (or on a resort they were just removed from).
  void _refreshSelfIfChanged() {
    final me = ref.read(currentUserProvider).value?.id;
    if (me != null && me == widget.member.userId) {
      ref.invalidate(currentUserProvider);
    }
  }

  Future<void> _changeRole(ResortRole role) async {
    if (role == widget.member.role) return;
    setState(() => _busy = true);
    try {
      await ref.read(resortMemberSourceProvider).setRole(
            widget.propertyId,
            widget.member.userId,
            role,
          );
      // Refetch rather than patch the row locally: the server is the only
      // source of truth for whether the change actually landed (e.g. the
      // P0023 last-owner guard rejects some changes outright), and a
      // stale optimistic update here would show a role that was never
      // actually granted -- leaving the dropdown on the OLD role (still
      // read straight off [widget.member], untouched below) is exactly
      // what a rejected change should look like.
      ref.invalidate(resortMembersProvider(widget.propertyId));
      _refreshSelfIfChanged();
    } on BookingFailure catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(FailureView.messageFor(e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove() async {
    final member = widget.member;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Remove ${member.fullName ?? member.email}?'),
        content: const Text(
          'They will lose access to this resort. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await ref
          .read(resortMemberSourceProvider)
          .remove(widget.propertyId, member.userId);
      ref.invalidate(resortMembersProvider(widget.propertyId));
      _refreshSelfIfChanged();
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
    final member = widget.member;
    final name = (member.fullName?.trim().isNotEmpty ?? false)
        ? member.fullName!
        : member.email;

    return Card(
      child: ListTile(
        title: Text(name),
        subtitle: Text(member.email),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButton<ResortRole>(
              key: Key('role-dropdown-${member.userId}'),
              value: member.role,
              onChanged: _busy
                  ? null
                  : (role) {
                      if (role != null) _changeRole(role);
                    },
              items: [
                for (final role in ResortRole.values)
                  DropdownMenuItem(
                    value: role,
                    child: Text(resortRoleLabel(role)),
                  ),
              ],
            ),
            IconButton(
              key: Key('remove-member-${member.userId}'),
              tooltip: 'Remove',
              icon: const Icon(Icons.person_remove_outlined),
              onPressed: _busy ? null : _remove,
            ),
          ],
        ),
      ),
    );
  }
}

/// The "Add member" dialog -- an existing account's email plus the role
/// to grant it, mirroring `TaskFormScreen`'s inline error text (rather
/// than a snackbar) so a typo doesn't close the dialog and lose it.
class _AddMemberDialog extends ConsumerStatefulWidget {
  const _AddMemberDialog({required this.propertyId});

  final String propertyId;

  @override
  ConsumerState<_AddMemberDialog> createState() => _AddMemberDialogState();
}

class _AddMemberDialogState extends ConsumerState<_AddMemberDialog> {
  final _email = TextEditingController();
  ResortRole _role = ResortRole.staff;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    if (email.isEmpty) {
      setState(() => _error = 'Enter an email address.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(resortMemberSourceProvider)
          .add(widget.propertyId, email, _role);
      ref.invalidate(resortMembersProvider(widget.propertyId));
      if (mounted) Navigator.of(context).pop();
    } on BookingFailure catch (e) {
      setState(() => _error = FailureView.messageFor(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add member'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            key: const Key('add-member-email'),
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Email'),
          ),
          const SizedBox(height: Spacing.sm),
          DropdownButtonFormField<ResortRole>(
            key: const Key('add-member-role'),
            initialValue: _role,
            decoration: const InputDecoration(labelText: 'Role'),
            items: [
              for (final role in ResortRole.values)
                DropdownMenuItem(
                    value: role, child: Text(resortRoleLabel(role))),
            ],
            onChanged: (role) {
              if (role != null) setState(() => _role = role);
            },
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: Spacing.sm),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('add-member-submit'),
          onPressed: _busy ? null : _submit,
          child: const Text('Add'),
        ),
      ],
    );
  }
}
