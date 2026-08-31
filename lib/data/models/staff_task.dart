enum TaskStatus { todo, inProgress, done }

TaskStatus taskStatusFromDb(String raw) => switch (raw) {
      'todo' => TaskStatus.todo,
      'in_progress' => TaskStatus.inProgress,
      'done' => TaskStatus.done,
      _ => throw ArgumentError('unknown task status $raw'),
    };

String taskStatusToDb(TaskStatus status) => switch (status) {
      TaskStatus.todo => 'todo',
      TaskStatus.inProgress => 'in_progress',
      TaskStatus.done => 'done',
    };

/// One task assigned to a staff/accountant member. [assigneeName] is
/// populated only when the row came with an embedded `profiles` object
/// (the repository's `list()` always joins it; a bare insert/update
/// response does not) -- `null` is never treated as an error, just "no
/// name on this particular response." Named `StaffTask`, not `Task`, to
/// avoid colliding with Flutter's own `Task` class.
class StaffTask {
  const StaffTask({
    required this.id,
    required this.assigneeId,
    required this.title,
    required this.description,
    required this.status,
    this.assigneeName,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String assigneeId;
  final String? assigneeName;
  final String title;
  final String description;
  final TaskStatus status;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory StaffTask.fromJson(Map<String, dynamic> json) => StaffTask(
        id: json['id'] as String,
        assigneeId: json['assignee_id'] as String,
        assigneeName:
            (json['profiles'] as Map<String, dynamic>?)?['full_name'] as String?,
        title: json['title'] as String,
        description: json['description'] as String? ?? '',
        status: taskStatusFromDb(json['status'] as String),
        createdAt: json['created_at'] == null
            ? null
            : DateTime.parse(json['created_at'] as String),
        updatedAt: json['updated_at'] == null
            ? null
            : DateTime.parse(json['updated_at'] as String),
      );

  /// Payload for a new task -- deliberately excludes `id` (server-
  /// assigned), `status` (server defaults to `todo`), `created_at`/
  /// `updated_at` (server-assigned defaults), and `assignee_name` (a
  /// read-only join result, not a column).
  Map<String, dynamic> toInsert() => {
        'assignee_id': assigneeId,
        'title': title,
        'description': description,
      };
}
