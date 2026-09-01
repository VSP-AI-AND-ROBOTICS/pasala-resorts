import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/failure_view.dart';
import '../../data/models/maintenance_issue.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/maintenance_repository.dart';

/// `/staff/maintenance` -- the signed-in staff member's own assigned
/// issues, status-only, mirroring `staff_service_requests_screen.dart`.
class StaffMaintenanceIssuesScreen extends ConsumerWidget {
  const StaffMaintenanceIssuesScreen({super.key});

  Future<void> _updateStatus(WidgetRef ref, BuildContext context,
      MaintenanceFilter filter, String id, MaintenanceStatus status) async {
    try {
      await ref.read(maintenanceRepositoryProvider).updateStatus(id: id, status: status);
      ref.invalidate(maintenanceIssuesProvider(filter));
    } on BookingFailure catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(FailureView.messageFor(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider).value;
    final staffId = user?.id;
    final filter = (assignedStaffId: staffId, status: null);
    final issuesAsync = staffId == null
        ? const AsyncValue<List<MaintenanceIssue>>.data([])
        : ref.watch(maintenanceIssuesProvider(filter));

    return Scaffold(
      appBar: AppBar(title: const Text('My Maintenance Issues')),
      body: AsyncView(
        value: issuesAsync,
        onRetry: staffId == null ? null : () => ref.invalidate(maintenanceIssuesProvider(filter)),
        empty: () => const EmptyState(
          icon: Icons.build_outlined,
          title: 'No issues assigned yet',
        ),
        data: (issues) => ListView.builder(
          padding: const EdgeInsets.all(Spacing.md),
          itemCount: issues.length,
          itemBuilder: (context, i) {
            final issue = issues[i];
            return Card(
              margin: const EdgeInsets.only(bottom: Spacing.sm),
              child: Padding(
                padding: const EdgeInsets.all(Spacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(maintenanceCategoryLabel(issue.category),
                        style: Theme.of(context).textTheme.titleMedium),
                    if (issue.description.isNotEmpty) Text(issue.description),
                    const SizedBox(height: Spacing.sm),
                    DropdownButton<MaintenanceStatus>(
                      value: issue.status,
                      items: [
                        for (final s in MaintenanceStatus.values)
                          DropdownMenuItem(value: s, child: Text(maintenanceStatusLabel(s))),
                      ],
                      onChanged: (s) =>
                          s == null ? null : _updateStatus(ref, context, filter, issue.id, s),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
