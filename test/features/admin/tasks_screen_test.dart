import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/data/models/admin_profile.dart';
import 'package:pasala/data/models/staff_task.dart';
import 'package:pasala/data/repositories/profile_directory_repository.dart';
import 'package:pasala/data/repositories/task_repository.dart';
import 'package:pasala/features/admin/tasks_screen.dart';

/// In-memory stand-in for [TaskRepository], mirroring
/// `FakeStaffShiftRepository` in `staff_shifts_screen_test.dart`.
class FakeTaskRepository implements TaskRepository {
  final List<StaffTask> store = [];
  final List<String> deletedIds = [];
  int _idCounter = 0;

  @override
  Future<List<StaffTask>> list({String? assigneeId, TaskStatus? status}) async =>
      store.where((t) {
        if (assigneeId != null && t.assigneeId != assigneeId) return false;
        if (status != null && t.status != status) return false;
        return true;
      }).toList();

  @override
  Future<void> create({
    required String assigneeId,
    required String title,
    required String description,
  }) async {
    store.add(StaffTask(
      id: 'task-${_idCounter++}',
      assigneeId: assigneeId,
      assigneeName: assigneeId == 'staff-1' ? 'Sita Staff' : 'Anil Accounts',
      title: title,
      description: description,
      status: TaskStatus.todo,
    ));
  }

  @override
  Future<void> update({
    required String id,
    required String title,
    required String description,
    required String assigneeId,
  }) async {
    final i = store.indexWhere((t) => t.id == id);
    final existing = store[i];
    store[i] = StaffTask(
      id: existing.id,
      assigneeId: assigneeId,
      assigneeName: assigneeId == existing.assigneeId
          ? existing.assigneeName
          : (assigneeId == 'staff-1' ? 'Sita Staff' : 'Anil Accounts'),
      title: title,
      description: description,
      status: existing.status,
    );
  }

  @override
  Future<void> updateStatus({required String id, required TaskStatus status}) async {
    final i = store.indexWhere((t) => t.id == id);
    final existing = store[i];
    store[i] = StaffTask(
      id: existing.id,
      assigneeId: existing.assigneeId,
      assigneeName: existing.assigneeName,
      title: existing.title,
      description: existing.description,
      status: status,
    );
  }

  @override
  Future<void> delete({required String id}) async {
    deletedIds.add(id);
    store.removeWhere((t) => t.id == id);
  }
}

final _staffProfile = AdminProfile(
  id: 'staff-1',
  email: 'staff@pasala.test',
  isStaffOrAbove: true,
  fullName: 'Sita Staff',
  createdAt: DateTime.utc(2026, 1, 1),
);

Widget _appFor(FakeTaskRepository repo) => ProviderScope(
      overrides: [
        taskRepositoryProvider.overrideWithValue(repo),
        adminProfilesProvider.overrideWith((ref) async => [_staffProfile]),
      ],
      child: const MaterialApp(home: TasksScreen()),
    );

void main() {
  testWidgets('shows an empty state when no tasks exist yet', (tester) async {
    await tester.pumpWidget(_appFor(FakeTaskRepository()));
    await tester.pumpAndSettle();

    expect(find.text('No tasks match this filter'), findsOneWidget);
  });

  testWidgets('the FAB opens the create-task form with an assignee picker', (
    tester,
  ) async {
    await tester.pumpWidget(_appFor(FakeTaskRepository()));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    expect(find.text('New task'), findsOneWidget);
    expect(find.byKey(const Key('task-form-assignee-picker')), findsOneWidget);
  });

  testWidgets('filling the create form and saving adds a task to the list', (
    tester,
  ) async {
    final repo = FakeTaskRepository();
    await tester.pumpWidget(_appFor(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('task-form-assignee-picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sita Staff').last);
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('task-form-title')), 'Restock minibar');
    await tester.enterText(
      find.byKey(const Key('task-form-description')),
      'Villa 2 is out of water bottles',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(repo.store, hasLength(1));
    expect(find.text('Restock minibar'), findsOneWidget);
  });

  testWidgets('lists an existing task with assignee name, title, and status', (
    tester,
  ) async {
    final repo = FakeTaskRepository()
      ..store.add(const StaffTask(
        id: 't1',
        assigneeId: 'staff-1',
        assigneeName: 'Sita Staff',
        title: 'Restock minibar',
        description: 'Villa 2',
        status: TaskStatus.inProgress,
      ));

    await tester.pumpWidget(_appFor(repo));
    await tester.pumpAndSettle();

    expect(find.text('Sita Staff'), findsOneWidget);
    expect(find.text('Restock minibar'), findsOneWidget);
    expect(find.textContaining('In Progress'), findsOneWidget);
  });

  testWidgets('editing a task does not expose a status control', (tester) async {
    final repo = FakeTaskRepository()
      ..store.add(const StaffTask(
        id: 't1',
        assigneeId: 'staff-1',
        assigneeName: 'Sita Staff',
        title: 'Restock minibar',
        description: 'Villa 2',
        status: TaskStatus.todo,
      ));

    await tester.pumpWidget(_appFor(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();

    expect(find.text('Edit task'), findsOneWidget);
    expect(find.byKey(const Key('task-form-title')), findsOneWidget);
    expect(find.textContaining('Status'), findsNothing);
  });

  testWidgets('confirming delete removes the task', (tester) async {
    final repo = FakeTaskRepository()
      ..store.add(const StaffTask(
        id: 't1',
        assigneeId: 'staff-1',
        assigneeName: 'Sita Staff',
        title: 'Restock minibar',
        description: 'Villa 2',
        status: TaskStatus.todo,
      ));

    await tester.pumpWidget(_appFor(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(repo.deletedIds, ['t1']);
    expect(find.text('Restock minibar'), findsNothing);
  });
}
