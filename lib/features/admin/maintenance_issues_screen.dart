import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/current_resort.dart';
import '../../core/errors.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/failure_view.dart';
import '../../data/models/maintenance_issue.dart';
import '../../data/repositories/maintenance_repository.dart';
import '../../data/repositories/profile_directory_repository.dart';

/// `/admin/maintenance` -- mirrors `service_requests_screen.dart`'s
/// assign+status shape, plus a priority chip.
class MaintenanceIssuesScreen extends ConsumerStatefulWidget {
  const MaintenanceIssuesScreen({super.key});

  @override
  ConsumerState<MaintenanceIssuesScreen> createState() => _MaintenanceIssuesScreenState();
}

class _MaintenanceIssuesScreenState extends ConsumerState<MaintenanceIssuesScreen> {
  MaintenanceStatus? _statusFilter;

  Future<void> _assign(String id, String staffId) async {
    try {
      await ref.read(maintenanceRepositoryProvider).assign(id: id, staffId: staffId);
      final propertyId = ref.read(currentResortProvider)!.propertyId;
      ref.invalidate(maintenanceIssuesProvider(
          (propertyId: propertyId, assignedStaffId: null, status: _statusFilter)));
    } on BookingFailure catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(FailureView.messageFor(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final propertyId = ref.watch(currentResortProvider)!.propertyId;
    final filter = (propertyId: propertyId, assignedStaffId: null, status: _statusFilter);
    final issuesAsync = ref.watch(maintenanceIssuesProvider(filter));
    final profiles = ref.watch(adminProfilesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Maintenance Issues')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(Spacing.md),
            child: DropdownButtonFormField<MaintenanceStatus?>(
              initialValue: _statusFilter,
              decoration: const InputDecoration(labelText: 'Status'),
              items: [
                const DropdownMenuItem(value: null, child: Text('All')),
                for (final s in MaintenanceStatus.values)
                  DropdownMenuItem(value: s, child: Text(maintenanceStatusLabel(s))),
              ],
              onChanged: (value) => setState(() => _statusFilter = value),
            ),
          ),
          Expanded(
            child: AsyncView(
              value: issuesAsync,
              onRetry: () => ref.invalidate(maintenanceIssuesProvider(filter)),
              empty: () => const EmptyState(
                icon: Icons.build_outlined,
                title: 'No issues match this filter',
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
                          Row(
                            children: [
                              Expanded(
                                child: Text(maintenanceCategoryLabel(issue.category),
                                    style: Theme.of(context).textTheme.titleMedium),
                              ),
                              Chip(
                                label: Text(maintenancePriorityLabel(issue.priority)),
                                side: BorderSide.none,
                              ),
                            ],
                          ),
                          if (issue.description.isNotEmpty) Text(issue.description),
                          const SizedBox(height: Spacing.sm),
                          Row(
                            children: [
                              Expanded(
                                child: profiles.when(
                                  loading: () => const SizedBox.shrink(),
                                  error: (_, _) => const SizedBox.shrink(),
                                  data: (list) {
                                    final staffOrAbove = list
                                        .where((p) => p.isStaffOrAbove)
                                        .toList();
                                    return DropdownButtonFormField<String?>(
                                      initialValue: issue.assignedStaffId,
                                      decoration: const InputDecoration(labelText: 'Assign to'),
                                      items: [
                                        const DropdownMenuItem(value: null, child: Text('Unassigned')),
                                        for (final p in staffOrAbove)
                                          DropdownMenuItem(
                                              value: p.id, child: Text(p.fullName ?? p.email)),
                                      ],
                                      onChanged: (staffId) =>
                                          staffId == null ? null : _assign(issue.id, staffId),
                                    );
                                  },
                                ),
                              ),
                              const SizedBox(width: Spacing.sm),
                              Chip(
                                label: Text(maintenanceStatusLabel(issue.status)),
                                side: BorderSide.none,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
