import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/current_resort.dart';
import '../../core/errors.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/failure_view.dart';
import '../../data/models/staff_task.dart';
import '../../data/repositories/profile_directory_repository.dart';
import '../../data/repositories/task_repository.dart';

String statusLabel(TaskStatus status) => switch (status) {
      TaskStatus.todo => 'To Do',
      TaskStatus.inProgress => 'In Progress',
      TaskStatus.done => 'Done',
    };

/// `/admin/tasks` -- admin-only (a write action, not the staff-or-above
/// carve-out `/admin/dashboard`/`/admin/reports` get). Defaults to
/// showing every task in every status, per the approved "everything,
/// filterable" decision -- unlike Leave Management's pending-first
/// default, there is no single "needs a decision" state here worth
/// defaulting to.
class TasksScreen extends ConsumerStatefulWidget {
  const TasksScreen({super.key});

  @override
  ConsumerState<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends ConsumerState<TasksScreen> {
  String? _assigneeId;
  TaskStatus? _statusFilter;

  @override
  Widget build(BuildContext context) {
    final propertyId = ref.watch(currentResortProvider)!.propertyId;
    final filter = (propertyId: propertyId, assigneeId: _assigneeId, status: _statusFilter);
    final tasks = ref.watch(tasksProvider(filter));
    final profiles = ref.watch(adminProfilesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Tasks')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(Spacing.md),
            child: Row(
              children: [
                Expanded(
                  child: profiles.when(
                    loading: () => const SizedBox.shrink(),
                    error: (_, _) => const SizedBox.shrink(),
                    data: (list) {
                      final staffOrAbove =
                          list.where((p) => p.isStaffOrAbove).toList();
                      return DropdownButtonFormField<String?>(
                        key: const Key('task-staff-picker'),
                        initialValue: _assigneeId,
                        decoration: const InputDecoration(labelText: 'Staff member'),
                        items: [
                          const DropdownMenuItem(value: null, child: Text('All staff')),
                          for (final p in staffOrAbove)
                            DropdownMenuItem(
                              value: p.id,
                              child: Text(p.fullName ?? p.email),
                            ),
                        ],
                        onChanged: (value) => setState(() => _assigneeId = value),
                      );
                    },
                  ),
                ),
                const SizedBox(width: Spacing.sm),
                Expanded(
                  child: DropdownButtonFormField<TaskStatus?>(
                    key: const Key('task-status-filter'),
                    initialValue: _statusFilter,
                    decoration: const InputDecoration(labelText: 'Status'),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('All')),
                      for (final status in TaskStatus.values)
                        DropdownMenuItem(value: status, child: Text(statusLabel(status))),
                    ],
                    onChanged: (value) => setState(() => _statusFilter = value),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: AsyncView(
              value: tasks,
              onRetry: () => ref.invalidate(tasksProvider(filter)),
              empty: () => const EmptyState(
                icon: Icons.checklist_outlined,
                title: 'No tasks match this filter',
                message: 'Tap + to assign a staff member their first task.',
              ),
              data: (list) => ListView(
                children: [
                  for (final task in list)
                    Padding(
                      key: Key('task-row-${task.id}'),
                      padding: const EdgeInsets.symmetric(
                        horizontal: Spacing.md,
                        vertical: Spacing.xs,
                      ),
                      child: Card(
                        child: ListTile(
                          title: Text(task.title),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(task.assigneeName ?? task.assigneeId),
                              Text(
                                [
                                  if (task.description.isNotEmpty) task.description,
                                  statusLabel(task.status),
                                ].join(' · '),
                              ),
                            ],
                          ),
                          trailing: PopupMenuButton<String>(
                            onSelected: (value) =>
                                _onMenuSelected(context, filter, task, value),
                            itemBuilder: (context) => const [
                              PopupMenuItem(value: 'edit', child: Text('Edit')),
                              PopupMenuItem(value: 'delete', child: Text('Delete')),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const TaskFormScreen()),
        ),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _onMenuSelected(
    BuildContext context,
    TaskFilter filter,
    StaffTask task,
    String value,
  ) {
    switch (value) {
      case 'edit':
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => TaskFormScreen(existing: task)),
        );
      case 'delete':
        _delete(context, filter, task);
    }
  }

  Future<void> _delete(BuildContext context, TaskFilter filter, StaffTask task) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Delete "${task.title}"?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      await ref.read(taskRepositoryProvider).delete(id: task.id);
      ref.invalidate(tasksProvider(filter));
    } on BookingFailure catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(FailureView.messageFor(e))));
      }
    }
  }
}

/// Create/edit form for a [StaffTask]. Deliberately has NO status
/// control -- status is the assignee's alone to change, via the
/// separate staff-facing screen; exposing it here would be a second,
/// ambiguous path to change the same field two different roles can
/// write (see the spec's §5).
class TaskFormScreen extends ConsumerStatefulWidget {
  const TaskFormScreen({super.key, this.existing});

  final StaffTask? existing;

  @override
  ConsumerState<TaskFormScreen> createState() => _TaskFormScreenState();
}

class _TaskFormScreenState extends ConsumerState<TaskFormScreen> {
  late final TextEditingController _title;
  late final TextEditingController _description;
  String? _assigneeId;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _title = TextEditingController(text: existing?.title ?? '');
    _description = TextEditingController(text: existing?.description ?? '');
    _assigneeId = existing?.assigneeId;
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final assigneeId = _assigneeId;
    final title = _title.text.trim();
    if (assigneeId == null || title.isEmpty) {
      setState(() => _error = 'Pick a staff member and enter a title.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final existing = widget.existing;
      final description = _description.text.trim();
      if (existing == null) {
        await ref.read(taskRepositoryProvider).create(
              propertyId: ref.read(currentResortProvider)!.propertyId,
              assigneeId: assigneeId,
              title: title,
              description: description,
            );
      } else {
        await ref.read(taskRepositoryProvider).update(
              id: existing.id,
              title: title,
              description: description,
              assigneeId: assigneeId,
            );
      }
      ref.invalidate(tasksProvider);
      if (mounted) Navigator.of(context).pop();
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
    final profiles = ref.watch(adminProfilesProvider);

    return Scaffold(
      appBar: AppBar(title: Text(widget.existing == null ? 'New task' : 'Edit task')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(Spacing.lg),
            children: [
              profiles.when(
                loading: () => const SizedBox.shrink(),
                error: (_, _) => const SizedBox.shrink(),
                data: (list) {
                  final staffOrAbove =
                      list.where((p) => p.isStaffOrAbove).toList();
                  return DropdownButtonFormField<String>(
                    key: const Key('task-form-assignee-picker'),
                    initialValue: _assigneeId,
                    decoration: const InputDecoration(labelText: 'Staff member'),
                    items: [
                      for (final p in staffOrAbove)
                        DropdownMenuItem(value: p.id, child: Text(p.fullName ?? p.email)),
                    ],
                    onChanged: (value) => setState(() => _assigneeId = value),
                  );
                },
              ),
              const SizedBox(height: Spacing.md),
              TextField(
                key: const Key('task-form-title'),
                controller: _title,
                decoration: const InputDecoration(labelText: 'Title'),
              ),
              const SizedBox(height: Spacing.sm),
              TextField(
                key: const Key('task-form-description'),
                controller: _description,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  helperText: 'Optional',
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: Spacing.sm),
                  child: Text(
                    _error!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
              const SizedBox(height: Spacing.lg),
              FilledButton(
                onPressed: _busy ? null : _save,
                child: const Text('Save'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
