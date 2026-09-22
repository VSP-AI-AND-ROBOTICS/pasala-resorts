-- Staff performance reporting. Needs zero new RLS: the summary RPC reads
-- only `tasks`, `attendance_records`, `leave_requests`, and `staff_shifts`,
-- all of which already grant an admin full select (0021-0024) -- this
-- function runs `security invoker` (the default), relying on the caller's
-- own RLS rather than becoming a fifth `security definer` surface for data
-- that already has a working admin-select policy. See
-- docs/superpowers/specs/2026-08-31-owner-super-admin-flow-design.md.
--
-- `tasks.completed_at` is set once, the moment `status` first transitions
-- to `done`, by the existing `tasks_enforce_write()` trigger -- append-only,
-- same pattern as `updated_at` itself. A task that leaves `done` and comes
-- back (no transition ordering is enforced, per 0024's header) does NOT
-- reset `completed_at` -- it keeps recording the FIRST time the work was
-- finished, which is what "average time to complete" should measure.
alter table public.tasks add column completed_at timestamptz;

create or replace function public.tasks_enforce_write()
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
    new.updated_at := clock_timestamp();
    if new.status = 'done' and old.completed_at is null then
      new.completed_at := clock_timestamp();
    end if;
    return new;
  end if;

  if new.assignee_id <> old.assignee_id then
    raise sqlstate '42501' using
      message = 'permission denied for table tasks',
      hint = 'only an administrator can reassign a task';
  end if;

  if new.id is distinct from old.id
      or new.title is distinct from old.title
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

  new.updated_at := clock_timestamp();
  if new.status = 'done' and old.completed_at is null then
    new.completed_at := clock_timestamp();
  end if;
  return new;
end;
$$;

-- One row per staff member (or a single row when `p_staff_id` is given).
-- `avg_checkin_delay_minutes` only ever averages over days that actually
-- had a scheduled shift AND a check-in -- a staff member with no shifts
-- recorded (this app does not require one to check in) contributes no rows
-- to that average rather than skewing it with a manufactured zero.
create function public.staff_performance_summary(
  p_staff_id uuid default null,
  p_from     date default (now() at time zone 'Asia/Kolkata')::date - 30,
  p_to       date default (now() at time zone 'Asia/Kolkata')::date
) returns table (
  staff_id                  uuid,
  staff_name                text,
  tasks_assigned            int,
  tasks_completed           int,
  completion_rate_pct       numeric,
  avg_completion_hours      numeric,
  days_present              int,
  leave_days_approved       int,
  avg_checkin_delay_minutes numeric
)
language plpgsql
stable
security invoker
as $$
begin
  if not public.is_admin() then
    raise exception 'not permitted' using errcode = 'P0008';
  end if;

  return query
  with staff as (
    select p.id, p.full_name
    from public.profiles p
    where p.role in ('staff', 'admin', 'accountant', 'super_admin')
      and (p_staff_id is null or p.id = p_staff_id)
  ),
  task_stats as (
    select
      t.assignee_id,
      count(*)::int as assigned,
      count(*) filter (where t.status = 'done')::int as completed,
      avg(extract(epoch from (t.completed_at - t.created_at)) / 3600.0)
        filter (where t.completed_at is not null) as avg_hours
    from public.tasks t
    where t.created_at::date between p_from and p_to
    group by t.assignee_id
  ),
  attendance_stats as (
    select
      a.staff_id,
      count(*)::int as present,
      avg(
        extract(epoch from (
          a.check_in_at - (a.work_date + s.start_time)
        )) / 60.0
      ) filter (where s.start_time is not null) as avg_delay
    from public.attendance_records a
    left join public.staff_shifts s
      on s.staff_id = a.staff_id and s.shift_date = a.work_date
    where a.work_date between p_from and p_to
    group by a.staff_id
  ),
  leave_stats as (
    select
      l.staff_id,
      sum(l.end_date - l.start_date + 1)::int as leave_days
    from public.leave_requests l
    where l.status = 'approved'
      and l.start_date <= p_to and l.end_date >= p_from
    group by l.staff_id
  )
  select
    s.id,
    coalesce(s.full_name, ''),
    coalesce(ts.assigned, 0),
    coalesce(ts.completed, 0),
    case when coalesce(ts.assigned, 0) = 0 then 0
         else round(ts.completed * 100.0 / ts.assigned, 1) end,
    round(ts.avg_hours, 1),
    coalesce(ast.present, 0),
    coalesce(ls.leave_days, 0),
    round(ast.avg_delay, 1)
  from staff s
  left join task_stats ts on ts.assignee_id = s.id
  left join attendance_stats ast on ast.staff_id = s.id
  left join leave_stats ls on ls.staff_id = s.id
  order by s.full_name nulls last;
end;
$$;

grant execute on function public.staff_performance_summary to authenticated;
revoke execute on function public.staff_performance_summary from public;
revoke execute on function public.staff_performance_summary from anon;
