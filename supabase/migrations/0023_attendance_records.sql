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
  check_in_at   timestamptz not null default now(),
  check_out_at  timestamptz,
  constraint attendance_records_unique_per_day unique (staff_id, work_date),
  constraint attendance_records_checkout_after_checkin
    check (check_out_at is null or check_out_at > check_in_at)
);

create index attendance_records_staff_idx on public.attendance_records(staff_id, work_date);

-- No delete grant -- an attendance record is never deleted by anyone.
-- No update grant either -- checkout goes through the check_out_attendance()
-- RPC below, not a direct client UPDATE (see that function's comment).
grant select, insert on public.attendance_records to authenticated;

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
-- work_date is compared against the resort's own local calendar day
-- (India Standard Time), not `current_date` (the database server's own
-- configured timezone, UTC on this instance). The resort operates in
-- IST, and a device physically at the resort naturally represents
-- "today" in IST -- if this check instead used the server's UTC
-- `current_date`, a check-in attempted between local midnight and
-- 5:30 AM IST would send a `work_date` one day ahead of the server's
-- UTC date and be silently rejected by this `with check`.
create policy attendance_records_own_insert on public.attendance_records
  for insert to authenticated
  with check (
    staff_id = auth.uid()
    and work_date = (now() at time zone 'Asia/Kolkata')::date
    and check_out_at is null
  );

-- Enforces everything a plain RLS policy cannot express on its own:
-- (1) only the record's OWNER may update it (never admin -- admin only
-- reads attendance, it never writes), (2) the only column that may
-- change is check_out_at, and (3) it can only move from null to a real
-- timestamp once -- never cleared, never re-done.
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

  return new;
end;
$$;

create trigger attendance_records_enforce_own_checkout_trigger
  before update on public.attendance_records
  for each row execute function public.attendance_records_enforce_own_checkout();

-- Client checkout goes through this function, not a direct table UPDATE --
-- see the migration's own note above the (now-removed)
-- attendance_records_own_update policy for why a raw client UPDATE cannot
-- reliably deny a same-tier staff peer: Postgres RLS requires SELECT-policy
-- visibility before an UPDATE policy's own USING clause is even consulted,
-- and a non-owner, non-admin caller has none. This function runs as its
-- owner (bypassing RLS on its own internal queries, the same as every other
-- SECURITY DEFINER function in this schema), does its own explicit ownership
-- and already-checked-out check, and raises an immediate, clear error rather
-- than depending on RLS row-visibility to gate the caller. The BEFORE UPDATE
-- trigger still fires on this function's internal UPDATE and remains a
-- harmless defense-in-depth backstop.
create function public.check_out_attendance(p_id uuid)
returns public.attendance_records
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_record public.attendance_records;
begin
  select * into v_record from public.attendance_records where id = p_id;
  if not found then
    raise sqlstate 'P0002' using message = 'attendance record not found';
  end if;

  if v_record.staff_id <> auth.uid() then
    raise sqlstate '42501' using
      message = 'permission denied for table attendance_records',
      hint = 'only the staff member who checked in may check themselves out';
  end if;

  if v_record.check_out_at is not null then
    raise sqlstate '42501' using
      message = 'this record is already checked out',
      hint = 'a check-out cannot be changed once recorded';
  end if;

  update public.attendance_records
    set check_out_at = clock_timestamp()
    where id = p_id;

  select * into v_record from public.attendance_records where id = p_id;
  return v_record;
end;
$$;

grant execute on function public.check_out_attendance(uuid) to authenticated;
revoke execute on function public.check_out_attendance(uuid) from public;
revoke execute on function public.check_out_attendance(uuid) from anon;

-- Forces check_in_at to the server's own clock on every insert,
-- regardless of what the client sends -- this is the timestamp the
-- table's entire design principle ("an honest, unedited record of what
-- actually happened") depends on, and it must not be client-forgeable
-- the way an unconstrained insert column otherwise would be.
create function public.attendance_records_force_checkin_time()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  new.check_in_at := now();
  return new;
end;
$$;

create trigger attendance_records_force_checkin_time_trigger
  before insert on public.attendance_records
  for each row execute function public.attendance_records_force_checkin_time();
