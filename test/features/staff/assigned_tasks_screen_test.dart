import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/current_resort.dart';
import 'package:pasala/data/models/app_user.dart';
import 'package:pasala/data/models/resort_membership.dart';
import 'package:pasala/data/models/staff_task.dart';
import 'package:pasala/data/repositories/auth_repository.dart';
import 'package:pasala/data/repositories/task_repository.dart';
import 'package:pasala/features/staff/assigned_tasks_screen.dart';

const _staff = AppUser(
  id: 'staff-1',
  email: 'staff@pasala.test',
);

const _resort =
    ResortMembership(propertyId: 'p1', resortName: 'Pasala', role: ResortRole.staff);

class _FixedResort extends CurrentResort {
  @override
  ResortMembership? build() => _resort;
}

class FakeTaskRepository implements TaskRepository {
  final List<StaffTask> store = [];
  final List<String> listedPropertyIds = [];

  @override
  Future<List<StaffTask>> list({
    required String propertyId,
    String? assigneeId,
    TaskStatus? status,
  }) async {
    listedPropertyIds.add(propertyId);
    return store.where((t) {
      if (assigneeId != null && t.assigneeId != assigneeId) return false;
      if (status != null && t.status != status) return false;
      return true;
    }).toList();
  }

  @override
  Future<void> create({
    required String propertyId,
    required String assigneeId,
    required String title,
    required String description,
  }) async =>
      throw UnimplementedError('staff never creates tasks');

  @override
  Future<void> update({
    required String id,
    required String title,
    required String description,
    required String assigneeId,
  }) async =>
      throw UnimplementedError('staff never edits task details');

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
  Future<void> delete({required String id}) async =>
      throw UnimplementedError('staff never deletes tasks');
}

Widget _appFor(FakeTaskRepository repo) => ProviderScope(
      overrides: [
        currentUserProvider.overrideWith((ref) => Stream.value(_staff)),
        currentResortProvider.overrideWith(_FixedResort.new),
        taskRepositoryProvider.overrideWithValue(repo),
      ],
      child: const MaterialApp(home: AssignedTasksScreen()),
    );

void main() {
  testWidgets('shows an empty state when the staff member has no tasks', (
    tester,
  ) async {
    await tester.pumpWidget(_appFor(FakeTaskRepository()));
    await tester.pumpAndSettle();

    expect(find.text('No tasks assigned yet'), findsOneWidget);
  });

  testWidgets('lists only the signed-in staff member\'s own tasks', (tester) async {
    final repo = FakeTaskRepository()
      ..store.addAll(const [
        StaffTask(
          id: 't1',
          assigneeId: 'staff-1',
          title: 'Restock minibar',
          description: 'Villa 2',
          status: TaskStatus.todo,
        ),
        StaffTask(
          id: 't2',
          assigneeId: 'someone-else',
          title: 'Not mine',
          description: '',
          status: TaskStatus.todo,
        ),
      ]);

    await tester.pumpWidget(_appFor(repo));
    await tester.pumpAndSettle();

    expect(find.text('Restock minibar'), findsOneWidget);
    expect(find.text('Not mine'), findsNothing);
    // Review Focus #1: the screen must pass the current resort's id
    // through to the repository, not rely on RLS alone.
    expect(repo.listedPropertyIds, everyElement('p1'));
  });

  testWidgets('changing the status control calls updateStatus', (tester) async {
    final repo = FakeTaskRepository()
      ..store.add(const StaffTask(
        id: 't1',
        assigneeId: 'staff-1',
        title: 'Restock minibar',
        description: 'Villa 2',
        status: TaskStatus.todo,
      ));

    await tester.pumpWidget(_appFor(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('task-status-t1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('In Progress').last);
    await tester.pumpAndSettle();

    expect(repo.store.first.status, TaskStatus.inProgress);
    expect(find.text('In Progress'), findsWidgets);
  });
}
