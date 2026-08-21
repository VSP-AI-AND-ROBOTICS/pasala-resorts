import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/failure_view.dart';
import '../../data/models/staff_task.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/task_repository.dart';
import '../admin/tasks_screen.dart' show statusLabel;

/// `/staff/tasks` -- the signed-in staff/accountant member's own
/// assigned tasks, newest first, each with a status control. No title/
/// description editing and no delete -- those are admin-only (see the
/// design spec's §5/§6 role split).
class AssignedTasksScreen extends ConsumerWidget {
  const AssignedTasksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider).value;
    final staffId = user?.id;
    final filter = (assigneeId: staffId, status: null);
    final tasksAsync = staffId == null
        ? const AsyncValue<List<StaffTask>>.data([])
        : ref.watch(tasksProvider(filter));

    return Scaffold(
      appBar: AppBar(title: const Text('Assigned Work')),
      body: AsyncView(
        value: tasksAsync,
        onRetry: staffId == null ? null : () => ref.invalidate(tasksProvider(filter)),
        empty: () => const EmptyState(
          icon: Icons.checklist_outlined,
          title: 'No tasks assigned yet',
          message: 'Tasks your admin assigns to you will show up here.',
        ),
        data: (list) => ListView(
          padding: const EdgeInsets.all(Spacing.md),
          children: [
            for (final task in list)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(Spacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(task.title, style: Theme.of(context).textTheme.titleMedium),
                      if (task.description.isNotEmpty) ...[
                        const SizedBox(height: Spacing.xs),
                        Text(task.description),
                      ],
                      const SizedBox(height: Spacing.sm),
                      DropdownButton<TaskStatus>(
                        key: Key('task-status-${task.id}'),
                        value: task.status,
                        items: [
                          for (final status in TaskStatus.values)
                            DropdownMenuItem(value: status, child: Text(statusLabel(status))),
                        ],
                        onChanged: (status) =>
                            status == null ? null : _updateStatus(ref, context, filter, task.id, status),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _updateStatus(
    WidgetRef ref,
    BuildContext context,
    TaskFilter filter,
    String taskId,
    TaskStatus status,
  ) async {
    try {
      await ref.read(taskRepositoryProvider).updateStatus(id: taskId, status: status);
      ref.invalidate(tasksProvider(filter));
    } on BookingFailure catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(FailureView.messageFor(e))));
      }
    }
  }
}
