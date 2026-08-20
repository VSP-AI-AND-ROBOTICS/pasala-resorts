-- Backs the admin "Attendance" screen and the staff Daily Work Status
-- hub section (see
-- docs/superpowers/specs/2026-08-20-staff-daily-work-status-design.md).
--
-- Deliberately NOT modelled: multiple check-in/check-out sessions per
-- day (no break tracking) -- the unique constraint below makes exactly
-- one row per staff member per day a database-enforced fact. A missed
-- check-out is never auto-closed and never correctable by anyone,
-- including admin -- it simply stays open (`check_out_at is null`)
-- forever, an honest unedited record of what actually happened. No
-- interaction with staff_shifts -- this table is entirely independent
-- of scheduled shifts, matching the precedent Leave Management already
-- set for staying independent of Work Schedules.
create table public.attendance_records (
  id            uuid primary key default gen_random_uuid(),
  staff_id      uuid not null references public.profiles(id) on delete cascade,
  work_date     date not null,
  check_in_at   timestamptz not null default clock_timestamp(),
  check_out_at  timestamptz,
  constraint attendance_records_unique_per_day unique (staff_id, work_date),
  constraint attendance_records_checkout_after_checkin
    check (check_out_at is null or check_out_at > check_in_at)
);

create index attendance_records_staff_idx on public.attendance_records(staff_id, work_date);

-- No delete grant -- an attendance record is never deleted by anyone.
grant select, insert, update on public.attendance_records to authenticated;

alter table public.attendance_records enable row level security;

create policy attendance_records_admin_select on public.attendance_records
  for select to authenticated
  using (public.is_admin());

create policy attendance_records_own_read on public.attendance_records
  for select to authenticated
  using (staff_id = auth.uid());

-- A caller may only insert TODAY'S check-in for THEMSELVES, not yet
-- checked out. Unlike UPDATE, a failed INSERT `with check` genuinely
-- raises 42501, so no trigger is needed for this path.
create policy attendance_records_own_insert on public.attendance_records
  for insert to authenticated
  with check (
    staff_id = auth.uid()
    and work_date = current_date
    and check_out_at is null
  );

-- `using (true)`, not `using (staff_id = auth.uid())`: a restrictive
-- USING clause here would let RLS silently exclude a denied caller's
-- target row before the trigger below ever runs, producing a silent
-- zero-rows-affected "success" instead of a clear 42501 -- the same
-- problem the sibling features' admin-write triggers already solved
-- (see 0021_staff_shifts.sql, 0022_leave_requests.sql). Enforcement is
-- entirely the trigger's job.
create policy attendance_records_own_update on public.attendance_records
  for update to authenticated
  using (true);

-- Enforces everything a plain RLS policy cannot express on its own:
-- (1) only the record's OWNER may update it (never admin -- admin only
-- reads attendance, it never writes), (2) the only column that may
-- change is check_out_at, and (3) it can only move from null to a real
-- timestamp once -- never cleared, never re-done. Also ensures
-- check_out_at is strictly after check_in_at (handles edge case where
-- now() returns the same value within a transaction).
create function public.attendance_records_enforce_own_checkout()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_current_uid uuid := auth.uid();
begin
  -- Ensure user is authenticated
  if v_current_uid is null then
    raise sqlstate '42501' using
      message = 'permission denied for table attendance_records',
      hint = 'must be authenticated';
  end if;

  -- Only the record owner may check themselves out
  if new.staff_id <> v_current_uid then
    raise sqlstate '42501' using
      message = 'permission denied for table attendance_records',
      hint = 'only the staff member who checked in may check themselves out';
  end if;

  if new.staff_id is distinct from old.staff_id
      or new.work_date is distinct from old.work_date
      or new.check_in_at is distinct from old.check_in_at then
    raise sqlstate '42501' using
      message = 'only check_out_at may be changed',
      hint = 'attendance records are never corrected after the fact';
  end if;

  if old.check_out_at is not null then
    raise sqlstate '42501' using
      message = 'this record is already checked out',
      hint = 'a check-out cannot be changed once recorded';
  end if;

  if new.check_out_at is null then
    raise sqlstate '42501' using
      message = 'check_out_at cannot be cleared',
      hint = 'an update to this table must be a check-out';
  end if;

  -- Ensure check_out_at is strictly after check_in_at (handles edge case
  -- where now() returns the same value within a single transaction)
  if new.check_out_at <= old.check_in_at then
    new.check_out_at := old.check_in_at + interval '1 millisecond';
  end if;

  return new;
end;
$$;

create trigger attendance_records_enforce_own_checkout_trigger
  before update on public.attendance_records
  for each row execute function public.attendance_records_enforce_own_checkout();
