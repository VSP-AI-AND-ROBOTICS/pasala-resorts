# Pasala Resorts — Staff Assigned Work / Tasks Design

Date: 2026-08-20
Builds on: the staff Work Schedules / Time Slots feature (spec
`2026-08-19-staff-work-shifts-design.md`), Leave Management (spec
`2026-08-20-staff-leave-management-design.md`), and Daily Work Status
(spec `2026-08-20-staff-daily-work-status-design.md`) — same
staff-operations hub, same admin/staff screen conventions. A fourth
sibling feature with no data dependency on any of them.
Status: approved by user in brainstorming session; ready for implementation
planning

## 1. What This Is

The fourth of the placeholder sections in the staff-operations hub to get
a real implementation: **Assigned Work / Tasks**. Admin assigns a task
(title + description) to one staff member; that staff member sees their
own tasks and moves each one through a simple status — To Do, In
Progress, Done. There is currently no schema, no repository, and no
screen for any of this; it is built from scratch.

Scope, by role:

- **Admin** gets a new screen listing every task, filterable by staff
  member and/or status, with the ability to create, edit (title,
  description, reassign), and delete any task.
- **Staff/accountant** get `/staff/tasks` wired to a real screen: a list
  of their own assigned tasks, each with a control to change its status.

This is the first sibling feature where the assignee (not just admin)
needs a genuine write path on the shared table — every prior sibling was
either admin-write-only (Work Schedules) or staff-creates/admin-decides
(Leave Management) or staff-owns-the-whole-row (Daily Work Status's
checkout). Here, admin owns everything about a task except its status,
and the assignee owns exactly the status field on their own row. See §3
for how this shapes the RLS design.

## 2. Scope

**In scope:** a new `tasks` table + RLS policies + a write-enforcement
trigger (new migration `supabase/migrations/0024_tasks.sql`), a new
`TaskRepository` (`lib/data/repositories/task_repository.dart`) and
`StaffTask` model (`lib/data/models/staff_task.dart` — named `StaffTask`,
not `Task`, to avoid colliding with Flutter's own `Task` widget class in
scope wherever both are imported), a new admin screen
(`lib/features/admin/tasks_screen.dart`, routed at `/admin/tasks`, linked
from `AdminHomeScreen`), and a real implementation of the existing staff
placeholder route `/staff/tasks` (replacing `PlaceholderSectionScreen` at
that one route only).

**Out of scope:** Working Hours (the one remaining hub placeholder —
separate future spec). Due dates, priority levels, status notes/comments,
multiple assignees per task, task categories/tags, attachments,
notifications, and any interaction with `staff_shifts`/`attendance_records`
— all explicitly deferred, see §7.

## 3. Data Model

One new table:

```sql
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
```

Notes on the design choices:

- **One assignee per task, plain `uuid` column** — not a join table.
  Matches the approved "one staff member per task" decision; a join
  table would only add value for multi-assignee tasks, which are out of
  scope.
- **`description` is `not null default ''`**, not nullable. The approved
  design is "just a title and description," so a task always has both;
  an empty string represents "no description given" without needing a
  three-state (filled/empty/null) distinction anywhere in the UI.
- **`task_status` enum, not text + check constraint.** Matches
  `leave_status`'s precedent in `0022_leave_requests.sql`. Three values
  only: `todo`, `in_progress`, `done` — no `cancelled` or `blocked`,
  since those weren't part of the approved scope.
- **No status-transition ordering enforced.** A staff member can move a
  task from `done` back to `in_progress` (e.g., they marked it done by
  mistake) or from `todo` straight to `done`. The approved design asked
  for three states, not a strict forward-only workflow; enforcing
  sequence would be a feature nobody asked for.
- **`updated_at`, unlike Daily Work Status's table.** Unlike an
  attendance check-out (a one-shot, one-way transition where the
  transition timestamp *is* `check_out_at`), a task's status can change
  repeatedly and admin can edit title/description/assignee at any time —
  there is no single column that already captures "when did this last
  change," so a real `updated_at` earns its place here. Maintained by a
  trigger (below), not client-supplied.
- **No `notes`/`comment` field**, matching the approved "no notes, just
  the status" decision.

RLS follows a hybrid of two established conventions: `staff_shifts`'s
admin-full-control shape (admin can insert/update/delete anything) plus a
narrower staff-owner update path modeled on the same
enforcement-trigger-because-RLS-USING-can't-raise-an-error pattern
already used by `staff_shifts_enforce_admin_write` and
`leave_requests_enforce_admin_decision`. Unlike Daily Work Status's
checkout, this does **not** need a `SECURITY DEFINER` RPC: that gap only
arises when a *non-owner, non-admin* caller needs to be denied (a same-
tier peer with no SELECT visibility into someone else's row). Here, the
assignee updating their own task's status is always the row's owner and
therefore always has SELECT visibility into it via
`tasks_own_read` — the RLS-visibility gap simply doesn't apply to an
owner acting on their own row, so a direct client `UPDATE` gated by a
trigger works correctly for this case, exactly as it already does for
admin in `staff_shifts`.

```sql
alter table public.tasks enable row level security;

grant select, insert, update, delete on public.tasks to authenticated;

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
-- through the same UPDATE policy; the trigger below is what actually
-- distinguishes and restricts what each caller may change. RLS itself
-- only needs to admit rows either side can see, which own_read/
-- admin_select already guarantee.
create policy tasks_update on public.tasks
  for update to authenticated
  using (public.is_admin() or assignee_id = auth.uid());

-- `using (true)`, not `using (is_admin())`: a non-admin DELETE attempt
-- on a row they CAN see (their own, via tasks_own_read) would otherwise
-- pass RLS's visibility check but fail this policy's own USING clause,
-- silently deleting zero rows with no error -- misleading, not insecure.
-- Matching staff_shifts_admin_delete's own convention, USING stays
-- permissive and the trigger below raises an explicit, clear error
-- instead.
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

## 4. Repository & Model

`lib/data/models/staff_task.dart` — a plain model matching the table:
`id`, `assigneeId`, `assigneeName` (populated only on the admin-facing
joined read, `null` otherwise — same convention as `StaffShift.staffName`
and `LeaveRequest.staffName`), `title`, `description`, `status` (a Dart
enum `TaskStatus { todo, inProgress, done }`, mapped to/from the
Postgres enum's snake_case string values), `createdAt`, `updatedAt`.

`lib/data/repositories/task_repository.dart` — follows
`LeaveRequestRepository`'s shape: constructed with a raw `SupabaseClient`,
wraps every call in the existing `_guard`/`mapPostgrestError` pattern,
uses a direct table `select` with a `profiles` embed for reads
(`profiles!tasks_assignee_id_fkey(full_name)` — this table has only one
FK to `profiles`, but the hint is included anyway for consistency with
`AttendanceRepository`'s same defensive choice).

- `list({String? assigneeId, TaskStatus? status}) -> Future<List<StaffTask>>`
  — both filters optional and apply server-side; `assigneeId: null` means
  every staff member (admin only — a non-admin caller's RLS-scoped rows
  are already limited to their own regardless of this parameter).
- `create({required String assigneeId, required String title, required String description}) -> Future<void>`
  — admin only; a non-admin caller's insert is rejected by
  `tasks_admin_insert` and surfaces as the existing generic permission
  `BookingFailure`.
- `update({required String id, required String title, required String description, required String assigneeId}) -> Future<void>`
  — admin only, full edit (title/description/reassignment).
- `updateStatus({required String id, required TaskStatus status}) -> Future<void>`
  — the assignee's own path; a plain table `.update()` restricted to the
  `status` column, relying on `tasks_enforce_write_trigger` for
  enforcement (no RPC needed — see §3).
- `delete({required String id}) -> Future<void>` — admin only.

Providers, matching the established convention: a plain
`Provider<TaskRepository>`, plus a `FutureProvider.family`
(`tasksProvider`, keyed on a `TaskFilter` record
`({String? assigneeId, TaskStatus? status})`) for the screens to watch.

## 5. Admin Screen — `/admin/tasks`

Routed from a new `AdminHomeScreen` destination ("Tasks" /
`checklist`-style icon / "Assign and track staff work"), gated admin-only
like `/admin/staff-shifts` and `/admin/leave-requests`.

- List of every task, newest first, each row showing assignee name,
  title, and a status chip/badge.
- Filter controls: a staff-member dropdown (same
  `adminProfilesProvider`-filtered-to-staff-or-above pattern already
  established) and a status dropdown, both optional/"all" by default —
  matching the approved "everything, filterable" decision for admin's
  default view (i.e., the initial unfiltered load shows tasks in every
  status, not just non-Done ones).
- A create action (e.g. a FAB or app-bar button) opens a form: assignee
  dropdown, title field, description field. Mirrors
  `staff_shifts_screen.dart`'s create-dialog shape.
- Each row has edit and delete actions. Edit opens the same form
  pre-filled, allowing title/description/reassignment changes (not
  status — status is the assignee's to change, so the admin edit form
  intentionally excludes it, avoiding a second, ambiguous path to change
  the same field two different roles can write). Delete opens a
  confirmation dialog before calling `TaskRepository.delete`.
- `EmptyState` when the current filter matches nothing (e.g. "No tasks
  match this filter").

## 6. Staff Screen — `/staff/tasks`

Replaces the existing `PlaceholderSectionScreen` route registration only.

- A list of the signed-in staff member's own tasks (server-filtered via
  `tasksProvider` keyed to their own id — never a client-side filter over
  every task), newest first.
- Each row shows title, description, and a status control (e.g. a
  segmented button or dropdown cycling To Do / In Progress / Done) that
  calls `TaskRepository.updateStatus` directly — no confirmation dialog,
  no form, matching the "just the status" decision.
- `EmptyState` when the staff member has no assigned tasks at all
  ("No tasks assigned yet").

## 7. Explicitly Deferred

- **No due dates or priority.** Matches the approved "neither — just a
  title and description" decision. If either becomes needed later, it's
  an additive column and an additive UI affordance, not a redesign of
  this table.
- **No status notes or comments.** Matches the approved "no notes, just
  the status" decision — a status change carries no explanation field
  anywhere in this schema.
- **No multiple assignees per task.** One `assignee_id` column, not a
  join table. A task that genuinely needs two people is out of scope for
  this slice.
- **No task categories, tags, or grouping.** Every task is a flat row;
  there is no folder/project/category concept layered on top.
- **No interaction with `staff_shifts` or `attendance_records`.** Tasks
  are not scheduled against shifts and not cross-referenced with
  check-in/check-out — matching the independence precedent already set
  between every prior pair of sibling features.
- **No notifications.** No push/email/outbox entry when a task is
  assigned, reassigned, or its status changes.
- **No task history/audit log of status changes.** `updated_at` records
  only the most recent change, not a full timeline of every transition.

## 8. Testing

- Pure logic: `TaskStatus` enum <-> Postgres string mapping (both
  directions), tested directly without a widget.
- `TaskRepository`: no dedicated unit-test file, matching the established
  convention (`RateRepository`, `StaffShiftRepository`,
  `LeaveRequestRepository`, `AttendanceRepository`) — exercised via a
  `FakeTaskRepository` in the screen widget tests.
- Widget tests: admin list+filter+create+edit+delete (mirroring
  `staff_shifts_screen_test.dart`'s coverage shape, since this is the
  first sibling since Staff Shifts to need admin edit/delete), staff
  status-control interaction and list rendering, confirming a staff
  member never sees another staff member's tasks even when seeded.
- pgTAP: table/RLS/trigger coverage mirroring `17_staff_shifts_test.sql`'s
  admin-full-control shape plus `18_leave_requests_test.sql`'s
  owner-can-only-touch-one-field shape — admin can create/edit/reassign/
  delete any task, a staff member can update only the `status` of their
  own task (attempting to change title/description/assignee is
  rejected), a staff member cannot update or delete another staff
  member's task, and a staff member's `select` only ever returns their
  own rows while admin's `select` returns everyone's. New file
  `supabase/tests/20_tasks_test.sql`.
- `flutter test`, `flutter analyze`, and `supabase test db` all run
  clean at the end. The three pre-existing, unrelated
  `hold_lifecycle_test.dart` failures are expected to remain exactly
  those three, unchanged by this work.
