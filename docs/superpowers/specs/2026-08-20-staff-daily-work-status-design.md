# Pasala Resorts — Staff Daily Work Status (Check-in/Check-out) Design

Date: 2026-08-20
Builds on: the staff Work Schedules / Time Slots feature (spec
`2026-08-19-staff-work-shifts-design.md`) and the staff Leave Management
feature (spec `2026-08-20-staff-leave-management-design.md`) — same
staff-operations hub, same admin/staff screen conventions, a third sibling
feature with no data dependency on either (attendance is deliberately
independent of scheduled shifts, see §7).
Status: approved by user in brainstorming session; ready for implementation
planning

## 1. What This Is

The third of the placeholder sections in the staff-operations hub to get a
real implementation: **Daily Work Status**, meaning simple daily
check-in/check-out attendance. A staff member taps one button to check in
when they start their day and another to check out when they finish;
admin gets a read-only view of who's checked in today (and any past day).
There is currently no schema, no repository, and no screen for any of
this; it is built from scratch, following the exact same conventions
established by Work Schedules and Leave Management.

Scope, by role:

- **Staff/accountant** get `/staff/daily-status` wired to a real screen:
  a one-tap check-in/check-out control for today, plus their own history
  below it.
- **Admin** gets a new, fully read-only screen showing attendance for any
  day (defaulting to today), filterable by staff member.

## 2. Scope

**In scope:** a new `attendance_records` table + RLS policies + an
enforcement trigger (new migration
`supabase/migrations/0023_attendance_records.sql`), a new
`AttendanceRepository`
(`lib/data/repositories/attendance_repository.dart`) and
`AttendanceRecord` model (`lib/data/models/attendance_record.dart`), a
new admin screen (`lib/features/admin/attendance_screen.dart`, routed at
`/admin/attendance`, linked from `AdminHomeScreen`), and a real
implementation of the existing staff placeholder route
`/staff/daily-status` (replacing `PlaceholderSectionScreen` at that one
route only).

**Out of scope:** Working Hours and Assigned Work/Tasks (the two
remaining hub placeholders — separate future specs). Multiple
check-in/check-out sessions per day (breaks), any interaction with
`staff_shifts` (no comparison against scheduled shifts, no
late/mismatch flagging), any way to correct, edit, or auto-close a
still-open check-in, any computed "hours worked" figure, and any
notification — all explicitly deferred, see §7.

## 3. Data Model

One new table:

```sql
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
```

Notes on the design choices:

- **`unique (staff_id, work_date)`** is what makes "one check-in and one
  check-out per day" a database-enforced fact, not just a UI convention —
  a second check-in attempt the same day is rejected with a unique-
  violation, not silently duplicated. This directly encodes the
  approved design's "one check-in + one check-out per day" decision.
- **`check_out_at` stays `null` indefinitely if a staff member never
  checks out.** Per the approved design ("stays open indefinitely, admin
  can't fix it either"), there is no auto-close job and no admin
  correction path — the record is an honest, unedited log of what the
  app actually observed. A staff member who forgot to check out
  yesterday simply starts a new row today (a new `work_date`), since the
  unique constraint is scoped per day.
- **No `reason`/notes field.** Unlike Leave Management, there is nothing
  for a staff member to explain — a check-in/check-out is a timestamp
  event, not a request.
- **No `updated_at`.** `check_out_at` transitioning from `null` to a
  timestamp is the row's only mutation in its lifetime, and that moment
  is already captured by the value itself — an extra `updated_at` column
  would carry the identical information.

RLS for select/insert follows the same `is_admin()` convention
established by the sibling features. Checkout, however, does **not**
follow the two sibling features' `using(true)`-plus-trigger convention —
that shape was tried first and rejected once Task 1's own implementation
review worked through it: a same-tier staff peer attempting to check
someone else out has no applicable SELECT-policy visibility on that row
(they're neither its owner nor admin), and Postgres RLS requires that
visibility before an UPDATE policy's own `using` clause is even
consulted — so a raw client `UPDATE`, whatever its `using`/trigger logic,
silently affects zero rows for a denied caller instead of raising an
error. The shipped design closes that gap by removing the client-facing
UPDATE path entirely and routing checkout through a `SECURITY DEFINER`
RPC that does its own explicit ownership check and raises immediately:

```sql
alter table public.attendance_records enable row level security;

-- No update grant -- checkout goes through the check_out_attendance()
-- RPC below, not a direct client UPDATE.
grant select, insert on public.attendance_records to authenticated;

create policy attendance_records_admin_select on public.attendance_records
  for select to authenticated
  using (public.is_admin());

create policy attendance_records_own_read on public.attendance_records
  for select to authenticated
  using (staff_id = auth.uid());

-- A caller may only insert TODAY'S check-in for THEMSELVES, not yet
-- checked out (a fresh check-in never arrives pre-closed). Unlike
-- UPDATE, a failed INSERT `with check` genuinely raises an error, so no
-- trigger is needed here. "Today" is judged in the resort's own local
-- (IST) calendar day, not the database server's own configured
-- timezone -- see the migration for why.
create policy attendance_records_own_insert on public.attendance_records
  for insert to authenticated
  with check (
    staff_id = auth.uid()
    and work_date = (now() at time zone 'Asia/Kolkata')::date
    and check_out_at is null
  );

-- check_in_at is not client-writable in any meaningful sense either --
-- a BEFORE INSERT trigger unconditionally overwrites it to now(), so an
-- insert cannot arrive pre-backdated or post-dated, keeping the "honest,
-- unedited record" property intact end to end.
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

-- The sole checkout path. Runs as its own owner (bypassing RLS on its
-- internal queries, same as every other SECURITY DEFINER function in
-- this schema), does its own explicit ownership and already-checked-out
-- checks, and raises an immediate, clear error rather than depending on
-- RLS row-visibility to gate the caller -- the fix for the gap described
-- above.
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
```

Admin never writes to this table at all (no admin update/delete policy
or grant exists) — the only mutation path is a staff member checking
themselves out through `check_out_attendance`, and even that is a
one-way, one-shot transition enforced by the function's own checks.

## 4. Repository & Model

`lib/data/models/attendance_record.dart` — a plain model matching the
table: `id`, `staffId`, `staffName` (populated only on the admin-facing
joined read, `null` otherwise — same convention as `StaffShift.staffName`
and `LeaveRequest.staffName`), `workDate`, `checkInAt`, `checkOutAt`.
Also a pure derived getter, `bool get isCheckedIn => checkOutAt == null`,
used by both screens to decide button/label state without duplicating
the null-check.

`lib/data/repositories/attendance_repository.dart` — follows
`LeaveRequestRepository`'s shape exactly: constructed with a raw
`SupabaseClient`, wraps every call in the existing `_guard`/
`mapPostgrestError` pattern, uses a direct table `select` with a
`profiles` embed for reads (disambiguated with an explicit foreign-key
hint, `profiles!attendance_records_staff_id_fkey(full_name)` — this table
has only one FK to `profiles`, so the ambiguity that required this on
`leave_requests` doesn't strictly apply here, but the hint is included
anyway for consistency and to guard against a future second FK
repeating that exact class of bug).

- `list({String? staffId, DateTime? date}) -> Future<List<AttendanceRecord>>`
  — `staffId: null` means every staff member (admin only); `date: null`
  means every date on record. Both optional filters apply server-side.
- `checkIn({required String staffId}) -> Future<void>` — inserts today's
  row (`work_date` = today, `check_in_at` = `now()` via the column
  default, no `check_out_at`).
- `checkOut({required String id}) -> Future<void>` — calls the
  `check_out_attendance` RPC for the given row id, which sets
  `check_out_at` to `now()` server-side (not a direct table update — see
  §3 for why).

Providers, matching the established convention: a plain
`Provider<AttendanceRepository>`, plus a `FutureProvider.family`
(`attendanceRecordsProvider`, keyed on an `AttendanceFilter` record
`({String? staffId, DateTime? date})`) for the screens to watch.

## 5. Admin Screen — `/admin/attendance`

Routed from a new `AdminHomeScreen` destination ("Attendance" /
`how_to_reg`-style icon / "See who's checked in, today or any past day"),
gated admin-only like `/admin/staff-shifts` and `/admin/leave-requests`
(not the `/admin/dashboard`/`/admin/reports`/`/admin/outbox` staff-or-
above carve-out — though note this screen is read-only, so admin-only
gating here is a scope choice rather than a strict necessity; kept
consistent with the sibling admin screens rather than opened up).

- Defaults to today's date, with a date picker to look at any other day,
  plus a staff-member filter dropdown (the same `adminProfilesProvider`-
  filtered-to-staff-or-above pattern already established).
- One row per staff member for the selected day: name, check-in time,
  and either the check-out time or "Still checked in" / "Not checked in"
  if there's no record at all for that day. Rows for staff with no
  record simply don't appear if the query only returns existing rows —
  the design accepts this rather than synthesizing "absent" rows for
  every staff member, since building that view requires cross-
  referencing the full staff roster against attendance, which is a
  bigger feature than "read-only attendance viewer."
- Fully read-only — no buttons, no menu, no dialog. `EmptyState` when
  the current filter matches nothing (e.g. "No attendance records for
  this day").

## 6. Staff Screen — `/staff/daily-status`

Replaces the existing `PlaceholderSectionScreen` route registration only.

The top of the screen is today's status, front and center:
- No record yet today → a large "Check In" button.
- Checked in, not yet checked out → "Checked in at HH:mm" plus a large
  "Check Out" button.
- Checked out → "Checked in at HH:mm · Checked out at HH:mm", no button.

Below that, a scrollable list of past days' records (newest first),
each showing the date, check-in time, and check-out time (or "No
check-out recorded" for an open day) — read-only, same as the admin
list's per-row shape. `EmptyState` only covers the "no history at all"
case; today's status card always renders once the signed-in user's id
resolves.

## 7. Explicitly Deferred

- **No multiple sessions per day.** One check-in and one check-out per
  calendar day, enforced by the `unique (staff_id, work_date)`
  constraint. A lunch-break-style second session is out of scope.
- **No interaction with `staff_shifts`.** Checking in/out never
  compares against, flags, or reads `staff_shifts` — the two features
  are independent on purpose, matching the precedent already set by
  Leave Management's independence from Work Schedules.
- **No correction, editing, or auto-closing of a missed check-out.** A
  check-in with no check-out simply stays that way forever; there is no
  admin action, no scheduled job, and no staff-facing "fix my mistake"
  flow. If this becomes a real operational problem, it is a deliberate
  future enhancement, not something this schema quietly handles.
- **No computed hours-worked figure.** This is a raw timestamp log, not
  a payroll or hours-tracking system — there is no derived duration
  column, running total, or report built on top of it in this slice.
- **No "who hasn't checked in yet" synthesized view.** The admin screen
  shows only rows that exist; it does not cross-reference the full
  staff roster to highlight absences.
- **No notifications.** No push/email/outbox entry on check-in, check-
  out, or a missed day.

## 8. Testing

- Pure logic: `AttendanceRecord.isCheckedIn`'s null-check, tested
  directly without a widget.
- `AttendanceRepository`: no dedicated unit-test file, matching the
  established convention (`RateRepository`, `StaffShiftRepository`,
  `LeaveRequestRepository`) — exercised via a `FakeAttendanceRepository`
  in the screen widget tests.
- Widget tests: admin list+filter (mirroring the sibling admin screens'
  coverage shape, adapted for a fully read-only screen — no action
  tests needed), staff check-in/check-out button-state transitions
  (no record → Check In button → tap → Checked-in state with Check Out
  button → tap → Checked-out state with no button) and history list
  rendering, confirming a staff member never sees another staff
  member's records even when seeded.
- pgTAP: table/RLS/trigger coverage mirroring
  `18_leave_requests_test.sql`'s shape — a staff member can check
  themselves in once per day, a second same-day check-in is rejected by
  the unique constraint, a staff member can check themselves out (and
  only themselves, only once, only setting `check_out_at`), admin can
  read all records but cannot write any, and a staff member's `select`
  only ever returns their own rows. New file
  `supabase/tests/19_attendance_records_test.sql`.
- `flutter test`, `flutter analyze`, and `supabase test db` all run
  clean at the end. The three pre-existing, unrelated
  `hold_lifecycle_test.dart` failures are expected to remain exactly
  those three, unchanged by this work.
