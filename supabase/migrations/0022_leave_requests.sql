-- Backs the admin "Leave requests" screen and the staff Leave Management
-- hub section (see
-- docs/superpowers/specs/2026-08-20-staff-leave-management-design.md).
--
-- Deliberately NOT modelled: no interaction with staff_shifts (approving
-- leave never checks, flags, or touches a shift row -- the two features
-- are independent by design). No leave-type categorization (`reason` is
-- plain free text). No staff-side cancellation once submitted. No
-- reversing an already-decided request -- `pending` -> `approved` or
-- `pending` -> `rejected` is final. See the spec's "Explicitly Deferred"
-- section for the reasoning behind each of these.
create type public.leave_status as enum ('pending', 'approved', 'rejected');

create table public.leave_requests (
  id          uuid primary key default gen_random_uuid(),
  staff_id    uuid not null references public.profiles(id) on delete cascade,
  start_date  date not null,
  end_date    date not null,
  reason      text,
  status      public.leave_status not null default 'pending',
  decided_by  uuid references public.profiles(id),
  decided_at  timestamptz,
  created_at  timestamptz not null default now(),
  constraint leave_requests_date_order check (end_date >= start_date)
);

create index leave_requests_staff_idx on public.leave_requests(staff_id, start_date);

-- No delete grant at all -- a leave request is never deleted by anyone,
-- not even admin. It is either pending, or decided (approved/rejected),
-- permanently.
grant select, insert, update on public.leave_requests to authenticated;

alter table public.leave_requests enable row level security;

create policy leave_requests_admin_select on public.leave_requests
  for select to authenticated
  using (public.is_admin());

create policy leave_requests_own_read on public.leave_requests
  for select to authenticated
  using (staff_id = auth.uid());

-- A caller may only insert a PENDING request for THEMSELVES -- unlike
-- UPDATE/DELETE, a failed INSERT `with check` genuinely raises 42501
-- (Postgres does not silently drop a rejected insert the way it silently
-- excludes a row from an UPDATE/DELETE target set), so no trigger is
-- needed here for a clear error on denial. Also guard decided_by and
-- decided_at to prevent a staff member's own insert from creating a
-- nonsensical "decided-looking" pending row.
create policy leave_requests_own_insert on public.leave_requests
  for insert to authenticated
  with check (staff_id = auth.uid() and status = 'pending' and decided_by is null
    and decided_at is null and public.is_staff_or_above());

-- `using (true)`, not `using (public.is_admin())`: a restrictive USING
-- clause here would let RLS silently exclude a denied caller's target
-- row before the trigger below ever runs, producing a silent
-- zero-rows-affected "success" instead of a clear 42501 -- the exact
-- problem `staff_shifts_admin_update` in 0021_staff_shifts.sql already
-- solved the same way. Enforcement is entirely the trigger's job.
create policy leave_requests_admin_update on public.leave_requests
  for update to authenticated
  using (true);

-- Enforces three things a plain RLS policy cannot express on its own:
-- (1) only admin may update a leave_requests row at all, (2) even an
-- admin's update may only change status/decided_by/decided_at -- never
-- staff_id, the dates, or the reason, and (3) a decision, once made
-- (old.status != 'pending'), is final and can never be revisited.
-- RLS policies compare a proposed NEW row against a boolean expression;
-- they have no OLD/NEW column comparison the way a trigger does, so
-- "only these three columns may change" and "no status reversals" can
-- only be expressed here.
create or replace function public.leave_requests_enforce_admin_decision()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if not public.is_admin() then
    raise sqlstate '42501' using
      message = 'permission denied for table leave_requests',
      hint = 'only administrators can decide leave requests';
  end if;

  if new.staff_id is distinct from old.staff_id
      or new.start_date is distinct from old.start_date
      or new.end_date is distinct from old.end_date
      or new.reason is distinct from old.reason then
    raise sqlstate '42501' using
      message = 'only status, decided_by, and decided_at may be changed',
      hint = 'admins decide requests, they do not edit their content';
  end if;

  if old.status <> 'pending' then
    raise sqlstate '42501' using
      message = 'a decided leave request cannot be changed',
      hint = 'once approved or rejected, a decision is final';
  end if;

  if new.status not in ('approved', 'rejected') then
    raise sqlstate '42501' using
      message = 'leave request status must be approved or rejected',
      hint = 'a decision must decide: approved or rejected, not pending or any other value';
  end if;

  return new;
end;
$$;

create trigger leave_requests_enforce_admin_decision_trigger
  before update on public.leave_requests
  for each row execute function public.leave_requests_enforce_admin_decision();
