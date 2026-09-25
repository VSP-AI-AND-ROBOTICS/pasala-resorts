import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pasala/core/current_resort.dart';
import 'package:pasala/data/models/resort_membership.dart';
import 'package:pasala/data/models/staff_task.dart';
import 'package:pasala/data/repositories/task_repository.dart';
import 'package:pasala/features/admin/tasks_screen.dart';

import '../../support/resort_roster.dart';

/// In-memory stand-in for [TaskRepository], mirroring
/// `FakeStaffShiftRepository` in `staff_shifts_screen_test.dart`. Each row
/// in [store] is tracked against the resort it belongs to in
/// [_propertyIdByTaskId], and [list] filters by it the same way a real
/// `.eq('property_id', propertyId)` query would -- so a test can seed rows
/// for two different resorts and assert only the current one's reach the
/// screen (Review Focus #1). A row seeded straight into [store] (bypassing
/// [create]) is tagged for a resort via [addToResort].
class FakeTaskRepository implements TaskRepository {
  final List<StaffTask> store = [];
  final Map<String, String> _propertyIdByTaskId = {};
  final List<String> deletedIds = [];
  final List<String> listedPropertyIds = [];
  final List<String> createdPropertyIds = [];
  int _idCounter = 0;

  /// Seeds [task] directly into [store], tagged as belonging to
  /// [propertyId] -- for tests that build rows by hand rather than through
  /// [create].
  void addToResort(String propertyId, StaffTask task) {
    store.add(task);
    _propertyIdByTaskId[task.id] = propertyId;
  }

  @override
  Future<List<StaffTask>> list({
    required String propertyId,
    String? assigneeId,
    TaskStatus? status,
  }) async {
    listedPropertyIds.add(propertyId);
    return store.where((t) {
      if (_propertyIdByTaskId[t.id] != propertyId) return false;
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
  }) async {
    createdPropertyIds.add(propertyId);
    addToResort(
      propertyId,
      StaffTask(
        id: 'task-${_idCounter++}',
        assigneeId: assigneeId,
        assigneeName: assigneeId == 'staff-1' ? 'Sita Staff' : 'Anil Accounts',
        title: title,
        description: description,
        status: TaskStatus.todo,
      ),
    );
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
    _propertyIdByTaskId.remove(id);
  }
}

const _resort =
    ResortMembership(propertyId: 'p1', resortName: 'Pasala', role: ResortRole.admin);

class _FixedResort extends CurrentResort {
  @override
  ResortMembership? build() => _resort;
}

Widget _appFor(FakeTaskRepository repo) => ProviderScope(
      overrides: [
        taskRepositoryProvider.overrideWithValue(repo),
        rosterOverride,
        currentResortProvider.overrideWith(_FixedResort.new),
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
      ..addToResort('p1', const StaffTask(
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
      ..addToResort('p1', const StaffTask(
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
      ..addToResort('p1', const StaffTask(
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

  // E2E bug (e2e/tests/staff.spec.ts): in the real app /admin/tasks lives
  // inside the router's ShellRoute, so the screen's own context resolves to
  // the shell navigator while showDialog puts the dialog on the root one.
  // The dialog's buttons must pop the dialog, not the Tasks page.
  testWidgets('confirming delete inside a ShellRoute closes the dialog, not '
      'the page', (tester) async {
    final repo = FakeTaskRepository()
      ..addToResort('p1', const StaffTask(
        id: 't1',
        assigneeId: 'staff-1',
        assigneeName: 'Sita Staff',
        title: 'Restock minibar',
        description: 'Villa 2',
        status: TaskStatus.todo,
      ));
    final router = GoRouter(
      initialLocation: '/admin/tasks',
      routes: [
        ShellRoute(
          builder: (_, _, child) => Scaffold(body: child),
          routes: [
            GoRoute(path: '/admin', builder: (_, _) => const Text('Admin home')),
            GoRoute(path: '/admin/tasks', builder: (_, _) => const TasksScreen()),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        taskRepositoryProvider.overrideWithValue(repo),
        rosterOverride,
        currentResortProvider.overrideWith(_FixedResort.new),
      ],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pumpAndSettle();

    // Cancel first: the dialog closes and the page stays.
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(TasksScreen), findsOneWidget);
    expect(repo.deletedIds, isEmpty);

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(TasksScreen), findsOneWidget);
    expect(repo.deletedIds, ['t1']);
    expect(find.text('Restock minibar'), findsNothing);
  });

  // Review Focus #1: a person with memberships at two resorts must never
  // see resort B's rows while working in resort A. The fake returns rows
  // for both "p1" (the current resort, per `_appFor`'s `_FixedResort`) and
  // "p2" -- only "p1"'s task reaches the screen, and `TaskRepository.list`
  // is called with exactly the current resort's id.
  testWidgets(
      'TaskRepository.list: rows from another resort never reach the screen',
      (tester) async {
    final repo = FakeTaskRepository()
      ..addToResort('p1', const StaffTask(
        id: 't1',
        assigneeId: 'staff-1',
        assigneeName: 'Sita Staff',
        title: 'Resort A task',
        description: '',
        status: TaskStatus.todo,
      ))
      ..addToResort('p2', const StaffTask(
        id: 't2',
        assigneeId: 'staff-1',
        assigneeName: 'Sita Staff',
        title: 'Resort B task',
        description: '',
        status: TaskStatus.todo,
      ));

    await tester.pumpWidget(_appFor(repo));
    await tester.pumpAndSettle();

    expect(find.text('Resort A task'), findsOneWidget);
    expect(find.text('Resort B task'), findsNothing);
    expect(repo.listedPropertyIds, everyElement('p1'));
  });

  // Final review C1: the picker lists `list_resort_members` for the current
  // resort only -- never another resort's staff.
  testWidgets("the staff filter lists only the current resort's members", (tester) async {
    await tester.pumpWidget(_appFor(FakeTaskRepository()));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('task-staff-picker')));
    await tester.pumpAndSettle();

    expect(find.text('Sita Staff'), findsWidgets);
    expect(find.text('Olga Otherresort'), findsNothing);
  });

  testWidgets("the create form's assignee picker lists only the current "
      "resort's members", (tester) async {
    await tester.pumpWidget(_appFor(FakeTaskRepository()));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('task-form-assignee-picker')));
    await tester.pumpAndSettle();

    expect(find.text('Sita Staff'), findsWidgets);
    expect(find.text('Olga Otherresort'), findsNothing);
  });
}
