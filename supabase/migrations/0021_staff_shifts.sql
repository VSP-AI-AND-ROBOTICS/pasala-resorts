-- Backs the admin "Staff shifts" screen and the staff Work
-- Schedules/Time Slots hub sections (see
-- docs/superpowers/specs/2026-08-19-staff-work-shifts-design.md).
--
-- Deliberately NOT modelled: overlapping shifts for one staff member on
-- one day are allowed (a real split shift, e.g. 6am-10am then 4pm-8pm) --
-- no exclusion constraint, unlike `reservations`. Overnight-spanning
-- shifts (crossing midnight) are also out of scope for this slice: the
-- `end_time > start_time` check below makes a night shift like
-- 22:00-02:00 an error, not silently wrong -- see the spec's "Explicitly
-- Deferred" section for the follow-up this implies if the business needs
-- it.
create table public.staff_shifts (
  id         uuid primary key default gen_random_uuid(),
  staff_id   uuid not null references public.profiles(id) on delete cascade,
  shift_date date not null,
  start_time time not null,
  end_time   time not null,
  notes      text,
  created_by uuid not null default auth.uid() references public.profiles(id),
  created_at timestamptz not null default now(),
  constraint staff_shifts_time_order check (end_time > start_time)
);

create index staff_shifts_staff_idx on public.staff_shifts(staff_id, shift_date);

grant select, insert, update, delete on public.staff_shifts to authenticated;

alter table public.staff_shifts enable row level security;

-- Admin has full read/write. Everyone else (staff, accountant -- and, for
-- that matter, a hypothetical shift row belonging to an admin/super_admin
-- account) can only read their OWN rows, and cannot write at all: there is
-- no policy granting insert/update/delete to anyone but is_admin(), so
-- Postgres's RLS default-deny takes over for a staff/accountant caller on
-- those commands, table-level GRANT above notwithstanding.
--
-- For SELECT and INSERT, RLS and triggers together enforce permissions.
-- For UPDATE/DELETE, the trigger (below) enforces the admin-only check,
-- while RLS allows authenticated access (else RLS denies access before
-- the trigger can run and provide a specific 42501 error).
create policy staff_shifts_admin_select on public.staff_shifts
  for select to authenticated
  using (public.is_admin());

create policy staff_shifts_admin_insert on public.staff_shifts
  for insert to authenticated
  with check (public.is_admin());

create policy staff_shifts_admin_update on public.staff_shifts
  for update to authenticated
  using (true);

create policy staff_shifts_admin_delete on public.staff_shifts
  for delete to authenticated
  using (true);

create policy staff_shifts_own_read on public.staff_shifts
  for select to authenticated
  using (staff_id = auth.uid());

-- === list_staff_shifts: the one read path both the admin screen and the ===
-- === two staff-facing screens use ===========================================
--
-- Deliberately NOT security definer -- unlike list_profiles() (which must
-- reach into auth.users), this only reads staff_shifts and profiles, both
-- of which the calling role already has its own RLS-scoped access to. It
-- runs as the caller, so `staff_shifts_own_read`/`staff_shifts_admin_all`
-- and `profiles_select_self`/`profiles_admin_select` all apply exactly as
-- they would to a hand-written query -- a staff member passing another
-- staff member's id as p_staff_id gets zero rows back, not an error and
-- not a leak, because the underlying staff_shifts row is invisible to
-- them regardless of what filter they asked for. The optional p_from/p_to
-- bounds are inclusive, matching `report_revenue`'s date-range convention.
create function public.list_staff_shifts(
  p_staff_id uuid default null,
  p_from     date default null,
  p_to       date default null
) returns table(
  id         uuid,
  staff_id   uuid,
  staff_name text,
  shift_date date,
  start_time time,
  end_time   time,
  notes      text,
  created_at timestamptz
)
language sql
stable
set search_path = public, pg_temp
as $$
  select s.id, s.staff_id, p.full_name, s.shift_date, s.start_time,
         s.end_time, s.notes, s.created_at
  from public.staff_shifts s
  join public.profiles p on p.id = s.staff_id
  where (p_staff_id is null or s.staff_id = p_staff_id)
    and (p_from is null or s.shift_date >= p_from)
    and (p_to is null or s.shift_date <= p_to)
  order by s.shift_date, s.start_time;
$$;

grant execute on function public.list_staff_shifts(uuid, date, date) to authenticated;
-- C1-sweep convention (see 0018_ical.sql / 0019_user_admin.sql): a `grant`
-- to `authenticated` never removes the default PUBLIC EXECUTE a function
-- holds since creation, so `anon` (and PUBLIC) must be revoked explicitly.
revoke execute on function public.list_staff_shifts(uuid, date, date) from public;
revoke execute on function public.list_staff_shifts(uuid, date, date) from anon;

-- Trigger to enforce permission checks for UPDATE and DELETE
-- (RLS USING clause doesn't throw an error when filtering out all rows,
-- so we need a trigger to enforce the permission check explicitly).
create function public.staff_shifts_enforce_admin_write()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if not public.is_admin() then
    raise sqlstate '42501' using
      message = 'permission denied for table staff_shifts',
      hint = 'only administrators can modify shift assignments';
  end if;

  if TG_OP = 'UPDATE' then
    return new;
  else  -- DELETE
    return old;
  end if;
end;
$$;

create trigger staff_shifts_enforce_admin_write_trigger
  before update or delete on public.staff_shifts
  for each row execute function public.staff_shifts_enforce_admin_write();
