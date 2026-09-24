import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/current_resort.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/async_view.dart';
import '../../data/models/resort_membership.dart';
import '../../data/repositories/auth_repository.dart';

/// `/staff/profile` -- the signed-in staff/accountant member's own details.
/// Everything shown here already lives on [AppUser] (sourced from
/// `profiles`, see `AuthRepository`), so this reads `currentUserProvider`
/// directly rather than issuing a fresh query. Read-only for now; editing
/// name/phone is a separate future task.
class StaffProfileScreen extends ConsumerWidget {
  const StaffProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final resort = ref.watch(currentResortProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: AsyncView(
        value: user,
        onRetry: () => ref.invalidate(currentUserProvider),
        data: (u) => u == null
            ? const SizedBox.shrink()
            : ListView(
                padding: const EdgeInsets.all(Spacing.md),
                children: [
                  _ProfileField(label: 'Name', value: u.fullName),
                  _ProfileField(label: 'Phone', value: u.phone),
                  _ProfileField(label: 'Email', value: u.email),
                  _ProfileField(
                    label: 'Role',
                    value: resort == null ? null : resortRoleLabel(resort.role),
                  ),
                ],
              ),
      ),
    );
  }
}

class _ProfileField extends StatelessWidget {
  const _ProfileField({required this.label, required this.value});

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Spacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: textTheme.labelMedium
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: Spacing.xs),
          Text(value?.isNotEmpty == true ? value! : 'Not set',
              style: textTheme.bodyLarge),
          const Divider(height: Spacing.lg),
        ],
      ),
    );
  }
}
