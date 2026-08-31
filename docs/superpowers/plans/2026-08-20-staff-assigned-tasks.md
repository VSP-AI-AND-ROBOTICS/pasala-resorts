# Staff Assigned Work / Tasks Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let admin assign a title+description task to one staff member, and let that staff member move it through To Do → In Progress → Done.

**Architecture:** One new table (`tasks`) with RLS split three ways: admin full read/write, the assignee's own-row read, and a narrow own-row status-only update — enforced by a single `before update or delete` trigger, the same shape `staff_shifts` already uses for its admin-only case, extended here with an owner branch. A `TaskRepository` wraps it; an admin screen (list/filter/create/edit/delete, mirroring `staff_shifts_screen.dart`) and a staff screen (own list + status control, replacing the `/staff/tasks` placeholder) consume it.

**Tech Stack:** Flutter + Riverpod + go_router, Supabase Postgres + RLS + pgTAP, matching every sibling feature already in this codebase (Work Schedules, Leave Management, Daily Work Status).

**Spec:** `docs/superpowers/specs/2026-08-20-staff-assigned-tasks-design.md`

## Global Constraints

- New migration file: `supabase/migrations/0024_tasks.sql` (next after `0023_attendance_records.sql`).
- New pgTAP test file: `supabase/tests/20_tasks_test.sql` (next after `19_attendance_records_test.sql`).
- Model class is named `StaffTask`, not `Task` — avoids colliding with Flutter's own `Task` class wherever both might be imported (spec §2).
- Table has NO `notes`/`comment`, NO due date, NO priority column — matches the approved "just a title and description" / "no notes" decisions (spec §3, §7).
- Exactly one `assignee_id` column, not a join table — one assignee per task (spec §3, §7).
- No status-transition ordering is enforced anywhere (DB or UI) — a task may move between any two of `todo`/`in_progress`/`done` in either direction (spec §3).
- Admin's edit form never lets admin change `status` — that field is the assignee's alone to change, via the separate staff-facing control (spec §5).
- Every repository call is wrapped in the existing `_guard`/`mapPostgrestError` pattern from `lib/core/errors.dart` — no widget must ever see a raw `PostgrestException`.
- `flutter test`, `flutter analyze`, and `supabase test db` must all run clean at the end of every task. The three pre-existing `hold_lifecycle_test.dart` failures are the known baseline and must remain exactly those three, unchanged.

---

### Task 1: `tasks` table, RLS, and write-enforcement trigger

**Files:**
- Create: `supabase/migrations/0024_tasks.sql`
- Create: `supabase/tests/20_tasks_test.sql`

**Interfaces:**
- Consumes: `public.is_admin()` (existing helper, used by every sibling table's RLS), `public.profiles` (existing table, FK target for `assignee_id`/`created_by`).
- Produces: table `public.tasks(id uuid, assignee_id uuid, title text, description text, status public.task_status, created_by uuid, created_at timestamptz, updated_at timestamptz)`; enum `public.task_status` with values `'todo'`, `'in_progress'`, `'done'`; function `public.tasks_enforce_write()` + trigger `tasks_enforce_write_trigger` (used only inside this migration — later tasks never call it directly).

- [ ] **Step 1: Write the migration**

Create `supabase/migrations/0024_tasks.sql`:

```sql
-- Backs the admin "Tasks" screen and the staff Assigned Work hub section
-- (see docs/superpowers/specs/2026-08-20-staff-assigned-tasks-design.md).
--
-- Deliberately NOT modelled: multiple assignees per task (one uuid
-- column, not a join table), due dates, priority levels, and status
-- notes/comments -- all out of scope for this slice, see the spec's
-- "Explicitly Deferred" section. No status-transition ordering is
-- enforced either -- a task may move between any two of todo/
-- in_progress/done in either direction.
create type public.task_status as enum ('todo', 'in_progress', 'done');

create table public.tasks (
  id          uuid primary key default gen_random_uuid(),
  assignee_id uuid not null references public.profiles(id) on delete cascade,
  title       text not null,
  description text not null default '',
  status      public.task_status not null default 'todo',
  created_by  uuid not null default auth.uid() references public.profiles(id),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create index tasks_assignee_idx on public.tasks(assignee_id, status);

grant select, insert, update, delete on public.tasks to authenticated;

alter table public.tasks enable row level security;

create policy tasks_admin_select on public.tasks
  for select to authenticated
  using (public.is_admin());

create policy tasks_own_read on public.tasks
  for select to authenticated
  using (assignee_id = auth.uid());

create policy tasks_admin_insert on public.tasks
  for insert to authenticated
  with check (public.is_admin());

-- Both admin (full write) and the assignee (status-only write) go
-- through this same UPDATE policy; the trigger below is what actually
-- distinguishes and restricts what each caller may change. RLS itself
-- only needs to admit rows either side can see, which own_read/
-- admin_select already guarantee.
create policy tasks_update on public.tasks
  for update to authenticated
  using (public.is_admin() or assignee_id = auth.uid());

-- `using (true)`, not `using (is_admin())`: a non-admin DELETE attempt
-- on a row they CAN see (their own, via tasks_own_read) would otherwise
-- pass RLS's visibility check but fail this policy's own USING clause,
-- silently deleting zero rows with no error -- misleading, not
-- insecure. Matching staff_shifts_admin_delete's own convention, USING
-- stays permissive and the trigger below raises an explicit, clear
-- error instead.
create policy tasks_admin_delete on public.tasks
  for delete to authenticated
  using (true);

-- Enforces what RLS's USING clause cannot: for UPDATE, admin may change
-- anything while the assignee may change ONLY status (never title,
-- description, assignee, or the audit columns) on a row they own; for
-- DELETE, only admin may delete at all. updated_at is always
-- server-set on UPDATE, never client-supplied.
create function public.tasks_enforce_write()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if TG_OP = 'DELETE' then
    if not public.is_admin() then
      raise sqlstate '42501' using
        message = 'permission denied for table tasks',
        hint = 'only an administrator can delete a task';
    end if;
    return old;
  end if;

  if public.is_admin() then
    new.updated_at := now();
    return new;
  end if;

  if new.assignee_id <> old.assignee_id then
    raise sqlstate '42501' using
      message = 'permission denied for table tasks',
      hint = 'only an administrator can reassign a task';
  end if;

  if new.title is distinct from old.title
      or new.description is distinct from old.description
      or new.created_by is distinct from old.created_by
      or new.created_at is distinct from old.created_at then
    raise sqlstate '42501' using
      message = 'permission denied for table tasks',
      hint = 'only an administrator can edit a task''s details';
  end if;

  if old.assignee_id <> auth.uid() then
    raise sqlstate '42501' using
      message = 'permission denied for table tasks',
      hint = 'you can only update the status of your own tasks';
  end if;

  new.updated_at := now();
  return new;
end;
$$;

create trigger tasks_enforce_write_trigger
  before update or delete on public.tasks
  for each row execute function public.tasks_enforce_write();
```

- [ ] **Step 2: Write the pgTAP test file**

Create `supabase/tests/20_tasks_test.sql`. This reuses the same fixture
profile ids every sibling test file uses: `...0002` = admin,
`...0003` = staff, `...0004` = accountant (all already seeded by
`00_setup_test.sql` / earlier test files' shared fixtures).

```sql
-- tasks + RLS + tasks_enforce_write(), added in 0024_tasks.sql to back
-- the staff Assigned Work hub section and its admin tasks screen. See
-- that migration's header for the one-assignee-per-task and
-- no-transition-ordering design decisions.

begin;
select plan(23);

select has_table('public', 'tasks', 'tasks table exists');
select has_function('public', 'tasks_enforce_write',
  'the write-enforcement trigger function exists');

-- === insert: admin-only ======================================================

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}';

select lives_ok(
  $$insert into public.tasks (id, assignee_id, title, description)
    values ('97111111-1111-1111-1111-111111111111',
            '10000000-0000-0000-0000-000000000003',
            'Restock minibar', 'Villa 2 is out of water bottles')$$,
  'admin can create a task assigned to a staff member');

set local request.jwt.claims to
  '{"sub":"10000000-0000-0000-0000-000000000003","role":"authenticated"}';

select throws_ok(
  $$insert into public.tasks (assignee_id, title)
    values ('10000000-0000-0000-0000-000000000003', 'Self-assigned task')$$,
  '42501', null, 'a staff member cannot create their own task');

-- === select: own rows only for staff, everything for admin ==================

select is(
  (select count(*)::int from public.tasks),
  1,
  'a staff member sees only their own task via direct select');

set local request.jwt.claims to
  '{"sub":"10000000-0000-0000-0000-000000000004","role":"authenticated"}';

select is(
  (select count(*)::int from public.tasks),
  0,
  'a different staff member sees none of someone else''s tasks');

set local request.jwt.claims to
  '{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}';

select lives_ok(
  $$insert into public.tasks (id, assignee_id, title, description)
    values ('97222222-2222-2222-2222-222222222222',
            '10000000-0000-0000-0000-000000000004',
            'Reconcile petty cash', '')$$,
  'admin can create a second task for a different assignee');

select is(
  (select count(*)::int from public.tasks),
  2,
  'admin sees every task via direct select');

-- === update: assignee may change ONLY status on their own task ==============

set local request.jwt.claims to
  '{"sub":"10000000-0000-0000-0000-000000000003","role":"authenticated"}';

select lives_ok(
  $$update public.tasks set status = 'in_progress'
    where id = '97111111-1111-1111-1111-111111111111'$$,
  'the assignee can move their own task to in_progress');

select lives_ok(
  $$update public.tasks set status = 'done'
    where id = '97111111-1111-1111-1111-111111111111'$$,
  'the assignee can move their own task all the way to done');

select lives_ok(
  $$update public.tasks set status = 'todo'
    where id = '97111111-1111-1111-1111-111111111111'$$,
  'the assignee can move a done task back to todo -- no transition ordering enforced');

select throws_ok(
  $$update public.tasks set title = 'Rewritten title'
    where id = '97111111-1111-1111-1111-111111111111'$$,
  '42501', null,
  'the assignee cannot change a task''s title -- only status may change');

select throws_ok(
  $$update public.tasks set description = 'Rewritten description'
    where id = '97111111-1111-1111-1111-111111111111'$$,
  '42501', null,
  'the assignee cannot change a task''s description either');

select throws_ok(
  $$update public.tasks set assignee_id = '10000000-0000-0000-0000-000000000004'
    where id = '97111111-1111-1111-1111-111111111111'$$,
  '42501', null, 'the assignee cannot reassign their own task to someone else');

select throws_ok(
  $$update public.tasks set status = 'done'
    where id = '97222222-2222-2222-2222-222222222222'$$,
  '42501', null,
  'a staff member cannot update the status of someone else''s task '
  '(not visible to them, so RLS filters it out before the trigger ever runs)');

-- === update: admin may change anything, including reassignment ==============

set local request.jwt.claims to
  '{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}';

select lives_ok(
  $$update public.tasks
      set title = 'Reconcile petty cash (urgent)',
          description = 'Do this before end of day',
          assignee_id = '10000000-0000-0000-0000-000000000003'
    where id = '97222222-2222-2222-2222-222222222222'$$,
  'admin can edit title, description, and reassign a task');

reset role;
select is(
  (select assignee_id from public.tasks
    where id = '97222222-2222-2222-2222-222222222222'),
  '10000000-0000-0000-0000-000000000003'::uuid,
  'the reassignment is visible directly on the table');

select is(
  (select updated_at > created_at from public.tasks
    where id = '97222222-2222-2222-2222-222222222222'),
  true,
  'updated_at moves forward on a write');

-- === delete: admin-only, explicit error for anyone else ======================

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"10000000-0000-0000-0000-000000000003","role":"authenticated"}';

select throws_ok(
  $$delete from public.tasks where id = '97111111-1111-1111-1111-111111111111'$$,
  '42501', null,
  'a staff member cannot delete their own task -- delete is admin-only');

set local request.jwt.claims to
  '{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}';

select lives_ok(
  $$delete from public.tasks where id = '97111111-1111-1111-1111-111111111111'$$,
  'admin can delete a task');

reset role;
select is(
  (select count(*)::int from public.tasks),
  1,
  'the deleted task is actually gone');

-- === anon: no access at all ===================================================

set local role anon;
set local request.jwt.claims to '{"role":"anon"}';

select throws_ok(
  $$select * from public.tasks$$,
  '42501', null, 'anon cannot select tasks');

select throws_ok(
  $$insert into public.tasks (assignee_id, title)
    values ('10000000-0000-0000-0000-000000000003', 'x')$$,
  '42501', null, 'anon cannot insert into tasks');

select * from finish();
rollback;
```

- [ ] **Step 3: Run the test file and confirm it passes**

Run: `npx supabase test db`
Expected: all files pass, including `20_tasks_test.sql` at `plan(23)` with 23/23 ok.

- [ ] **Step 4: Run the full pgTAP suite to confirm nothing else broke**

Run: `npx supabase test db`
Expected: `All tests successful.` across every file (20 files now).

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/0024_tasks.sql supabase/tests/20_tasks_test.sql
git commit -m "feat(db): add tasks table, RLS, and write-enforcement trigger"
```

---

### Task 2: `StaffTask` Dart model

**Files:**
- Create: `lib/data/models/staff_task.dart`
- Test: `test/data/staff_task_test.dart`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: enum `TaskStatus { todo, inProgress, done }`; functions `taskStatusFromDb(String) -> TaskStatus` and `taskStatusToDb(TaskStatus) -> String`; class `StaffTask` with fields `id (String)`, `assigneeId (String)`, `assigneeName (String?)`, `title (String)`, `description (String)`, `status (TaskStatus)`, `createdAt (DateTime?)`, `updatedAt (DateTime?)`; factory `StaffTask.fromJson(Map<String, dynamic>)`; method `Map<String, dynamic> toInsert()`.

- [ ] **Step 1: Write the failing test**

Create `test/data/staff_task_test.dart`:

```dart
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/staff_task_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:pasala/data/models/staff_task.dart'`

- [ ] **Step 3: Write the model**

Create `lib/data/models/staff_task.dart`:

```dart
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/data/staff_task_test.dart`
Expected: PASS, all tests green.

- [ ] **Step 5: Commit**

```bash
git add lib/data/models/staff_task.dart test/data/staff_task_test.dart
git commit -m "feat(model): add StaffTask model"
```

---

### Task 3: `TaskRepository`

**Files:**
- Create: `lib/data/repositories/task_repository.dart`

**Interfaces:**
- Consumes: `StaffTask`, `TaskStatus`, `taskStatusToDb` from `lib/data/models/staff_task.dart` (Task 2); `mapPostgrestError` from `lib/core/errors.dart`; `supabaseProvider` from `lib/core/supabase_client.dart`.
- Produces: typedef `TaskFilter = ({String? assigneeId, TaskStatus? status})`; class `TaskRepository` with `list({String? assigneeId, TaskStatus? status}) -> Future<List<StaffTask>>`, `create({required String assigneeId, required String title, required String description}) -> Future<void>`, `update({required String id, required String title, required String description, required String assigneeId}) -> Future<void>`, `updateStatus({required String id, required TaskStatus status}) -> Future<void>`, `delete({required String id}) -> Future<void>`; providers `taskRepositoryProvider` (`Provider<TaskRepository>`) and `tasksProvider` (`FutureProvider.family<List<StaffTask>, TaskFilter>`).

- [ ] **Step 1: Write the repository**

Create `lib/data/repositories/task_repository.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors.dart';
import '../../core/supabase_client.dart';
import '../models/staff_task.dart';

/// The (assignee, status) an admin or staff screen wants to see --
/// `assigneeId: null` means "every staff member" (admin only; RLS
/// returns only the caller's own rows for anyone else regardless),
/// `status: null` means "every status." A record, not positional
/// params, so `FutureProvider.family` can key on it directly.
typedef TaskFilter = ({String? assigneeId, TaskStatus? status});

class TaskRepository {
  TaskRepository(this._db);
  final SupabaseClient _db;

  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } catch (e) {
      throw mapPostgrestError(e);
    }
  }

  /// A direct table select with a `profiles` embed for `assignee_name`
  /// -- this table has only one FK to `profiles`, so the ambiguity that
  /// required an explicit FK hint on `leave_requests` doesn't strictly
  /// apply here, but the hint is included anyway for consistency with
  /// `AttendanceRepository`'s same defensive choice.
  Future<List<StaffTask>> list({
    String? assigneeId,
    TaskStatus? status,
  }) =>
      _guard(() async {
        dynamic query = _db
            .from('tasks')
            .select('*, profiles!tasks_assignee_id_fkey(full_name)');
        if (assigneeId != null) query = query.eq('assignee_id', assigneeId);
        if (status != null) query = query.eq('status', taskStatusToDb(status));
        final rows = await query.order('created_at', ascending: false) as List;
        return rows.map((e) => StaffTask.fromJson(e as Map<String, dynamic>)).toList();
      });

  /// Creates a new task, always `todo` (the server column default --
  /// the client never sends a `status`). Admin-only; `tasks_admin_insert`
  /// rejects anyone else.
  Future<void> create({
    required String assigneeId,
    required String title,
    required String description,
  }) =>
      _guard(() async {
        await _db.from('tasks').insert(
              StaffTask(
                id: '',
                assigneeId: assigneeId,
                title: title,
                description: description,
                status: TaskStatus.todo,
              ).toInsert(),
            );
      });

  /// Full edit -- title, description, and/or reassignment. Admin-only;
  /// deliberately excludes `status`, which only [updateStatus] may
  /// change (see the spec's "two roles, two fields" split).
  Future<void> update({
    required String id,
    required String title,
    required String description,
    required String assigneeId,
  }) =>
      _guard(() async {
        await _db.from('tasks').update({
          'title': title,
          'description': description,
          'assignee_id': assigneeId,
        }).eq('id', id);
      });

  /// The assignee's own path -- a plain table update restricted to the
  /// `status` column, relying on `tasks_enforce_write_trigger` for
  /// enforcement (no RPC needed: the caller is always the row's owner,
  /// so the RLS-visibility gap Daily Work Status's checkout hit does
  /// not apply here -- see the spec's §3).
  Future<void> updateStatus({
    required String id,
    required TaskStatus status,
  }) =>
      _guard(() async {
        await _db.from('tasks').update({'status': taskStatusToDb(status)}).eq('id', id);
      });

  Future<void> delete({required String id}) => _guard(() async {
        await _db.from('tasks').delete().eq('id', id);
      });
}

final taskRepositoryProvider = Provider<TaskRepository>(
  (ref) => TaskRepository(ref.watch(supabaseProvider)),
);

final tasksProvider = FutureProvider.family<List<StaffTask>, TaskFilter>(
  (ref, filter) => ref.watch(taskRepositoryProvider).list(
        assigneeId: filter.assigneeId,
        status: filter.status,
      ),
);
```

- [ ] **Step 2: Run static analysis to confirm it compiles cleanly**

Run: `flutter analyze lib/data/repositories/task_repository.dart`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add lib/data/repositories/task_repository.dart
git commit -m "feat(repo): add TaskRepository"
```

---

### Task 4: Admin Tasks screen — `/admin/tasks`

**Files:**
- Create: `lib/features/admin/tasks_screen.dart`
- Test: `test/features/admin/tasks_screen_test.dart`
- Modify: `lib/core/router.dart` (add the route)
- Modify: `lib/features/admin/admin_home_screen.dart` (add the destination)

**Interfaces:**
- Consumes: `StaffTask`, `TaskStatus` (Task 2); `TaskRepository`, `TaskFilter`, `taskRepositoryProvider`, `tasksProvider` (Task 3); `AdminProfile`, `adminProfilesProvider` from `lib/data/repositories/user_admin_repository.dart` (existing); `UserRole` from `lib/data/models/app_user.dart` (existing).
- Produces: widgets `TasksScreen` (list+filter+FAB) and `TaskFormScreen` (create/edit form) in `lib/features/admin/tasks_screen.dart`.

- [ ] **Step 1: Write the failing widget test**

Create `test/features/admin/tasks_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/data/models/admin_profile.dart';
import 'package:pasala/data/models/app_user.dart';
import 'package:pasala/data/models/staff_task.dart';
import 'package:pasala/data/repositories/task_repository.dart';
import 'package:pasala/data/repositories/user_admin_repository.dart';
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
  role: UserRole.staff,
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/features/admin/tasks_screen_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:pasala/features/admin/tasks_screen.dart'`

- [ ] **Step 3: Write the screen**

Create `lib/features/admin/tasks_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/failure_view.dart';
import '../../data/models/app_user.dart';
import '../../data/models/staff_task.dart';
import '../../data/repositories/task_repository.dart';
import '../../data/repositories/user_admin_repository.dart';

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
    final filter = (assigneeId: _assigneeId, status: _statusFilter);
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
                          list.where((p) => p.role != UserRole.customer).toList();
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
                          subtitle: Text(
                            [
                              task.assigneeName ?? task.assigneeId,
                              if (task.description.isNotEmpty) task.description,
                              statusLabel(task.status),
                            ].join(' · '),
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
                      list.where((p) => p.role != UserRole.customer).toList();
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/features/admin/tasks_screen_test.dart`
Expected: PASS, all tests green.

- [ ] **Step 5: Wire the route**

In `lib/core/router.dart`, add the import alongside the other admin
screen imports (find the line importing `attendance_screen.dart` and
add this next to it):

```dart
import '../features/admin/tasks_screen.dart';
```

Then add the route immediately after the `/admin/attendance` route
(around line 249 in the current file):

```dart
          GoRoute(
            path: '/admin/tasks',
            builder: (_, _) => const TasksScreen(),
          ),
```

- [ ] **Step 6: Add the AdminHomeScreen destination**

In `lib/features/admin/admin_home_screen.dart`, add a new entry to the
`_destinations` list, immediately after the `'Attendance'` entry:

```dart
    (
      icon: Icons.checklist_outlined,
      title: 'Tasks',
      subtitle: 'Assign and track staff work',
      path: '/admin/tasks',
    ),
```

- [ ] **Step 7: Run static analysis**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 8: Run the full Flutter test suite**

Run: `flutter test`
Expected: only the 3 pre-existing `hold_lifecycle_test.dart` failures remain; no new failures.

- [ ] **Step 9: Commit**

```bash
git add lib/features/admin/tasks_screen.dart test/features/admin/tasks_screen_test.dart lib/core/router.dart lib/features/admin/admin_home_screen.dart
git commit -m "feat(admin): add Tasks screen with create/edit/delete"
```

---

### Task 5: Staff Tasks screen — `/staff/tasks`

**Files:**
- Create: `lib/features/staff/assigned_tasks_screen.dart`
- Test: `test/features/staff/assigned_tasks_screen_test.dart`
- Modify: `lib/core/router.dart` (replace the `PlaceholderSectionScreen` at `/staff/tasks`)

**Interfaces:**
- Consumes: `StaffTask`, `TaskStatus` (Task 2); `TaskRepository`, `taskRepositoryProvider`, `tasksProvider` (Task 3); `statusLabel` from `lib/features/admin/tasks_screen.dart` (Task 4 — reused as-is, not duplicated); `currentUserProvider` from `lib/data/repositories/auth_repository.dart` (existing, same pattern `daily_status_screen.dart` and `leave_screen.dart` already use).
- Produces: widget `AssignedTasksScreen` in `lib/features/staff/assigned_tasks_screen.dart`.

- [ ] **Step 1: Write the failing widget test**

Create `test/features/staff/assigned_tasks_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/data/models/app_user.dart';
import 'package:pasala/data/models/staff_task.dart';
import 'package:pasala/data/repositories/auth_repository.dart';
import 'package:pasala/data/repositories/task_repository.dart';
import 'package:pasala/features/staff/assigned_tasks_screen.dart';

const _staff = AppUser(
  id: 'staff-1',
  email: 'staff@pasala.test',
  role: UserRole.staff,
);

class FakeTaskRepository implements TaskRepository {
  final List<StaffTask> store = [];

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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/features/staff/assigned_tasks_screen_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:pasala/features/staff/assigned_tasks_screen.dart'`

- [ ] **Step 3: Write the screen**

Create `lib/features/staff/assigned_tasks_screen.dart`:

```dart
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/features/staff/assigned_tasks_screen_test.dart`
Expected: PASS, all tests green.

- [ ] **Step 5: Wire the route**

In `lib/core/router.dart`, add the import alongside the other staff
screen imports (find the line importing `daily_status_screen.dart` and
add this next to it):

```dart
import '../features/staff/assigned_tasks_screen.dart';
```

Then replace the existing `/staff/tasks` route (the
`PlaceholderSectionScreen` one, currently around line 270-276):

```dart
          GoRoute(
            path: '/staff/tasks',
            builder: (_, _) => const AssignedTasksScreen(),
          ),
```

- [ ] **Step 6: Run static analysis**

Run: `flutter analyze`
Expected: `No issues found!` (confirms `PlaceholderSectionScreen`'s import in `router.dart` is still used elsewhere -- `/staff/working-hours` still references it -- so no unused-import warning.)

- [ ] **Step 7: Run the full Flutter test suite**

Run: `flutter test`
Expected: only the 3 pre-existing `hold_lifecycle_test.dart` failures remain; no new failures.

- [ ] **Step 8: Commit**

```bash
git add lib/features/staff/assigned_tasks_screen.dart test/features/staff/assigned_tasks_screen_test.dart lib/core/router.dart
git commit -m "feat(staff): wire /staff/tasks to the Assigned Work screen"
```

---

### Task 6: Full-suite verification

**Files:** none (verification only).

**Interfaces:** none — this task consumes everything from Tasks 1-5 and produces no new interface.

- [ ] **Step 1: Run the full pgTAP suite**

Run: `npx supabase test db`
Expected: `All tests successful.` across all 20 files (00 through 20, matching the file count after Task 1).

- [ ] **Step 2: Run static analysis**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 3: Run the full Flutter test suite**

Run: `flutter test`
Expected: exactly the same 3 pre-existing `hold_lifecycle_test.dart` failures as the established baseline, nothing new.

- [ ] **Step 4: Independently verify the two new database surfaces live**

Using the local Supabase REST endpoint (same technique used in Daily
Work Status's Task 6): confirm the `profiles!tasks_assignee_id_fkey`
embed resolves (HTTP 200, `full_name` populated) on a `GET
/rest/v1/tasks?select=*,profiles!tasks_assignee_id_fkey(full_name)`
call authenticated as admin, and that a staff-authenticated `PATCH
/rest/v1/tasks?id=eq.<their-own-task-id>` with body `{"status":
"in_progress"}` succeeds (HTTP 200/204) while the same call with body
`{"title": "hacked"}` is rejected (HTTP 403, `42501`).

- [ ] **Step 5: No commit needed for this task** (verification only — if
  any step above fails, fix the regression, re-run this task's steps,
  and commit the fix under a `fix:` message before considering the
  plan complete).
