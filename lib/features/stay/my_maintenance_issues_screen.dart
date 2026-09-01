import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/empty_state.dart';
import '../../data/models/maintenance_issue.dart';
import '../../data/repositories/maintenance_repository.dart';

class MyMaintenanceIssuesScreen extends ConsumerWidget {
  const MyMaintenanceIssuesScreen({super.key, required this.reservationId});

  final String reservationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final issuesAsync = ref.watch(myMaintenanceIssuesProvider(reservationId));

    return Scaffold(
      appBar: AppBar(title: const Text('My Reported Issues')),
      body: AsyncView(
        value: issuesAsync,
        onRetry: () => ref.invalidate(myMaintenanceIssuesProvider(reservationId)),
        empty: () => const EmptyState(
          icon: Icons.build_outlined,
          title: 'No issues reported yet',
        ),
        data: (issues) => ListView.builder(
          padding: const EdgeInsets.all(Spacing.md),
          itemCount: issues.length,
          itemBuilder: (context, i) {
            final issue = issues[i];
            return Card(
              margin: const EdgeInsets.only(bottom: Spacing.sm),
              child: ListTile(
                title: Text(maintenanceCategoryLabel(issue.category)),
                subtitle: Text(
                  issue.description.isEmpty
                      ? maintenancePriorityLabel(issue.priority)
                      : '${issue.description}\n${maintenancePriorityLabel(issue.priority)} priority',
                ),
                isThreeLine: issue.description.isNotEmpty,
                trailing: Chip(
                  label: Text(maintenanceStatusLabel(issue.status)),
                  side: BorderSide.none,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
