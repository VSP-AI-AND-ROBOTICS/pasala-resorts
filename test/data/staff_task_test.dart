import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/data/models/staff_task.dart';

void main() {
  group('taskStatusFromDb / taskStatusToDb', () {
    test('round-trips all three values', () {
      for (final status in TaskStatus.values) {
        expect(taskStatusFromDb(taskStatusToDb(status)), status);
      }
    });

    test('maps in_progress to and from the snake_case db value', () {
      expect(taskStatusToDb(TaskStatus.inProgress), 'in_progress');
      expect(taskStatusFromDb('in_progress'), TaskStatus.inProgress);
    });
  });

  group('StaffTask.fromJson', () {
    test('parses a plain table row (no embedded profiles)', () {
      final task = StaffTask.fromJson(const {
        'id': 't1',
        'assignee_id': 'u1',
        'title': 'Restock minibar',
        'description': 'Villa 2 is out of water bottles',
        'status': 'todo',
        'created_at': '2026-08-20T10:00:00Z',
        'updated_at': '2026-08-20T10:00:00Z',
      });

      expect(task.id, 't1');
      expect(task.assigneeId, 'u1');
      expect(task.assigneeName, isNull);
      expect(task.title, 'Restock minibar');
      expect(task.description, 'Villa 2 is out of water bottles');
      expect(task.status, TaskStatus.todo);
      expect(task.createdAt, DateTime.parse('2026-08-20T10:00:00Z'));
      expect(task.updatedAt, DateTime.parse('2026-08-20T10:00:00Z'));
    });

    test('parses a row with an embedded profiles object', () {
      final task = StaffTask.fromJson(const {
        'id': 't2',
        'assignee_id': 'u2',
        'profiles': {'full_name': 'Sita Staff'},
        'title': 'Reconcile petty cash',
        'description': '',
        'status': 'in_progress',
        'created_at': '2026-08-20T10:00:00Z',
        'updated_at': '2026-08-21T09:00:00Z',
      });

      expect(task.assigneeName, 'Sita Staff');
      expect(task.status, TaskStatus.inProgress);
    });

    test('reads the room name from an embedded units object', () {
      final task = StaffTask.fromJson(const {
        'id': 't3',
        'assignee_id': 'u1',
        'units': {'name': 'Cottage 4'},
        'title': 'Clean Cottage 4',
        'description': '',
        'status': 'todo',
      });

      expect(task.unitName, 'Cottage 4');
    });

    test('a general task has no room', () {
      final task = StaffTask.fromJson(const {
        'id': 't4',
        'assignee_id': 'u1',
        'units': null,
        'title': 'Restock minibar',
        'description': '',
        'status': 'todo',
      });

      expect(task.unitName, isNull);
    });
  });

  test('toInsert never includes id, status, created_at, updated_at, or '
      'assignee_name', () {
    final task = StaffTask.fromJson(const {
      'id': 't1',
      'assignee_id': 'u1',
      'profiles': {'full_name': 'Sita Staff'},
      'title': 'Restock minibar',
      'description': 'Villa 2 is out of water bottles',
      'status': 'todo',
      'created_at': '2026-08-20T10:00:00Z',
      'updated_at': '2026-08-20T10:00:00Z',
    });

    final payload = task.toInsert();
    expect(payload.keys.toSet(), {'assignee_id', 'title', 'description'});
    expect(payload['assignee_id'], 'u1');
    expect(payload['title'], 'Restock minibar');
    expect(payload['description'], 'Villa 2 is out of water bottles');
  });
}
