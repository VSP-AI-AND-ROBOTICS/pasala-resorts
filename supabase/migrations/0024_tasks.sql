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
