# Pasala Resorts — Staff Work Schedules / Time Slots Design

Date: 2026-08-19
Builds on: the staff nav/dashboard-hub slice (commit `5ac9391`, no separate
spec — implemented as a bounded change): Browse removed for staff/
accountant, `/staff/dashboard` hub added with placeholder sections for
Working Hours, Leave Management, Assigned Work, Work Schedules, Time Slots,
Daily Work Status
Status: approved by user in brainstorming session; ready for implementation
planning

## 1. What This Is

This is the first of the placeholder sections in the staff-operations hub to
get a real implementation: **Work Schedules** and **Time Slots**. Both
sections surface the same underlying data — shifts an admin assigns to a
staff member — just presented two ways: a calendar for Work Schedules, a
chronological list for Time Slots. There is currently no schema, no
repository, and no screen for any of this; it is built from scratch.

Scope, by role:

- **Admin** gets a new screen to assign, view, edit, and delete staff
  shifts — one master list across all staff, filterable by staff member and
  date range.
- **Staff/accountant** get their own two hub sections wired to real data —
  Work Schedules (calendar) and Time Slots (list) — both scoped to the
  signed-in user's own shifts only.

## 2. Scope

**In scope:** a new `staff_shifts` table + RLS policies (new migration
`supabase/migrations/0021_staff_shifts.sql`), a new `StaffShiftRepository`
(`lib/data/repositories/staff_shift_repository.dart`) and `StaffShift` model
(`lib/data/models/staff_shift.dart`), a new admin screen
(`lib/features/admin/staff_shifts_screen.dart`, routed at
`/admin/staff-shifts`, linked from `AdminHomeScreen`), and real
implementations of the two existing staff placeholder routes,
`/staff/schedules` and `/staff/time-slots` (replacing
`PlaceholderSectionScreen` at those two routes only — the other four
placeholders are untouched).

**Out of scope:** Working Hours, Leave Management, Assigned Work, and Daily
Work Status (the other four hub placeholders — separate future specs).
Recurring/templated shifts, shift swapping, clock-in/clock-out, and
overnight-spanning shifts (a shift that crosses midnight) are all explicitly
deferred (§7). No changes to booking, payments, reports, or any other
existing feature.

## 3. Data Model

One new table:

```sql
create table public.staff_shifts (
  id uuid primary key default gen_random_uuid(),
  staff_id uuid not null references public.profiles(id) on delete cascade,
  shift_date date not null,
  start_time time not null,
  end_time time not null,
  notes text,
  created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now(),
  constraint staff_shifts_time_order check (end_time > start_time)
);
```

Notes on the design choices:

- **No exclusion constraint.** Per the approved design, overlapping shifts
  for the same staff member on the same day are allowed (e.g. a legitimate
  split shift) — there is no uniqueness/overlap enforcement, unlike
  `reservations`' double-booking guard.
- **`end_time > start_time`** rules out zero-length and backwards shifts at
  the database level, cheaply. It also rules out a shift that spans
  midnight (e.g. 22:00–02:00) — see §7 for how that's handled today.
- **`created_by`** records which admin made the assignment, for
  accountability; it is not surfaced in the UI in this slice, only stored.
- **`staff_id` accepts any `profiles.id`**, not just `role = 'staff'` — the
  same table serves accountant shifts too (accountant shares the staff hub
  today), and a future admin/super_admin shift is not something the schema
  needs to reject. The admin screen's staff picker is what actually narrows
  the choice to staff-or-above (§5).

RLS, following the `is_admin()` / `is_staff_or_above()` helper-function
convention already used throughout (e.g. `rate_rules`):

```sql
alter table public.staff_shifts enable row level security;

grant select, insert, update, delete on public.staff_shifts to authenticated;

create policy staff_shifts_admin_all on public.staff_shifts
  for all to authenticated
  using (public.is_admin())
  with check (public.is_admin());

create policy staff_shifts_own_read on public.staff_shifts
  for select to authenticated
  using (staff_id = auth.uid());
```

Admin has full read/write; a staff/accountant user can only `select` rows
where `staff_id` is their own `auth.uid()` — no insert/update/delete access,
matching "admin assigns, staff views only." Postgres evaluates the two
`select`-eligible policies as OR'd, so admin still sees everyone's rows and
a staff member sees just their own.

## 4. Repository & Model

`lib/data/models/staff_shift.dart` — a plain model matching the table:
`id`, `staffId`, `shiftDate`, `startTime`, `endTime`, `notes`, `createdAt`,
plus `staffName`/`staffEmail` populated only when the admin list joins
against `profiles` (see below) — `null` on the staff-facing fetch, which
doesn't need them.

`lib/data/repositories/staff_shift_repository.dart` — follows the
`RateRepository` shape exactly: constructed with a raw `SupabaseClient`,
wraps every call in the existing `_guard`/`mapPostgrestError` pattern.

- `listForStaff(String staffId)` — `select` filtered to `staff_id`, ordered
  by `shift_date`. Used by both staff-facing screens (implicitly the
  signed-in user's own id) and the admin screen's per-staff filter.
- `listAll({DateTimeRange? dateRange})` — admin-only in practice (RLS would
  return nothing useful for a non-admin anyway); joins `profiles` for
  `full_name`/`email` via a `select('*, profiles(full_name, email)')`
  embed, so the admin list can show staff names without a second query.
  Optional `dateRange` filters `shift_date` between the two bounds
  server-side.
- `createRange({required staffId, required DateTimeRange range, required
  TimeOfDay start, required TimeOfDay end, String? notes})` — inserts one
  row per calendar day in `range`, all with the same `start`/`end`/`notes`.
  A single-day assignment is just a range of one day, so there is no
  separate single-shift create method.
- `update(StaffShift shift)` — updates one row by id (used for editing a
  single day's shift after the fact; editing a whole previously-created
  range as a batch is not supported — each day is independently editable
  once created).
- `delete(String id)` — deletes one row.

Providers, matching `rate_repository.dart`'s convention: a plain
`Provider<StaffShiftRepository>`, plus `FutureProvider.family` wrappers
(`staffShiftsForProvider(staffId)`, `allStaffShiftsProvider(filter)`) for
the screens to watch.

## 5. Admin Screen — `/admin/staff-shifts`

Routed from a new `AdminHomeScreen` destination ("Staff shifts" /
`task_alt`-style icon / "Assign and manage staff work shifts"), gated
admin-only like every other `/admin/*` management route (not staff-or-above
— assigning shifts is a write action, unlike the read-only
`/admin/dashboard`/`/admin/reports` carve-out).

Structure mirrors `rate_rules_screen.dart`:

- A list of all shifts (staff name · date · start–end time · notes),
  sorted by date, with two filter controls up top: a staff-member dropdown
  (populated from `list_profiles()`, filtered client-side to
  staff-or-above — matching how the survey found no server-side
  staff-only listing RPC exists yet) and a date-range filter
  (`showDateRangePicker`).
- A `FloatingActionButton` opens a separate form screen
  (`StaffShiftFormScreen`, pushed via `Navigator.push`, not a bottom
  sheet): staff-member dropdown, `showDateRangePicker` for the date range,
  two `showTimePicker` fields for start/end, an optional notes field.
  Submitting calls `createRange(...)` and pops back to the list.
- Each list row has edit (pushes the same form screen pre-filled for that
  one row, editing in place via `update`) and delete (confirmation
  `AlertDialog`, then `delete`) actions, exactly like Rate Rules' row
  actions.
- Empty state (`EmptyState`) when no shifts exist yet or a filter matches
  nothing.

## 6. Staff Screens

Both replace their current `PlaceholderSectionScreen` route registration
only — the hub card labels/icons/order are unchanged.

**`/staff/schedules` (Work Schedules) — calendar view.** A month calendar,
visually following `AvailabilityCalendar`'s grid/legend structure (month
header with prev/next chevrons, Monday-first 7-column grid) but driven by
`statusFor`-equivalent logic over the signed-in user's own shifts instead
of reservations: a day either "has a shift" (highlighted, tap shows that
day's shift details in a small dialog/bottom sheet — date, time, notes) or
doesn't. This is a new, standalone widget (not a reuse of
`AvailabilityCalendar` itself, which is reservation-shaped and booking-tap
oriented) — but intentionally mirrors its visual conventions so the app's
two calendars feel consistent.

**`/staff/time-slots` (Time Slots) — list view.** A simple
`ListView`/`AsyncView` of the same `listForStaff(currentUserId)` data,
sorted chronologically, upcoming-first, each row showing date, start–end
time, and notes if present. `EmptyState` when the staff member has no
shifts assigned yet.

Both screens read `currentUserProvider` for the signed-in user's id, same
pattern as `StaffProfileScreen`.

## 7. Explicitly Deferred

- **Overnight-spanning shifts** (e.g. 22:00 today to 06:00 tomorrow): the
  `end_time > start_time` check means a night shift must be entered as a
  same-day range (e.g. 22:00–23:59) or as two adjacent rows if the business
  genuinely needs the post-midnight hours tracked. A real wraparound model
  (shift date + duration, or two timestamps instead of a date + two times)
  is a deliberate follow-up if this turns out to matter in practice — not
  something this schema silently handles today.
- **Recurring shifts** (e.g. "every Monday, 9–5, indefinitely") — every
  shift is a concrete dated row; there is no template/recurrence concept.
  `createRange` gives admin a fast way to fill in a known date range, but
  there's no "repeat weekly forever" affordance.
- **Shift swapping / staff self-service changes** — staff have read-only
  access; any change still requires admin.
- **Notifications** — no push/email/outbox entry is generated when a shift
  is assigned, edited, or deleted. A staff member finds out by opening the
  app.
- **Clock-in/clock-out or actual-hours-worked tracking** — this is a
  *planned* schedule only, not an attendance system. That's Daily Work
  Status's territory, a separate future spec.
- **A server-side "list staff-only profiles" RPC** — the admin staff-picker
  filters `list_profiles()`'s full result client-side to staff-or-above
  roles. If that list ever grows large enough for pagination to matter, a
  dedicated RPC (mirroring `is_staff_or_above()`) is the natural follow-up.

## 8. Testing

- Pure logic: a `shiftStatusFor`-style day-classification helper (or
  equivalent) for the calendar view, tested the same way
  `availability_calendar_test.dart` tests `statusFor` — without a widget.
- `StaffShiftRepository`: tested against a fake/mocked Supabase client
  seam, following `rate_repository_test.dart`'s pattern if one exists, or
  `user_admin_repository.dart`'s `XSource` abstract-interface seam if the
  RPC-embed query needs substituting for a widget test's provider override.
- Widget tests: admin list+form+filter (mirroring
  `rate_rules_screen_test.dart`'s coverage shape), staff calendar view
  (own shifts highlighted, tapping a shift day shows its details, no
  other staff member's shifts ever appear even if seeded), staff list view
  (chronological order, empty state).
- RLS is exercised at the repository/integration level exactly as
  existing features do — no new test infrastructure needed beyond what
  `rate_repository`/`user_admin_repository` already establish.
- `flutter test` and `flutter analyze` run clean at the end; the three
  pre-existing, unrelated `hold_lifecycle_test.dart` failures are expected
  to remain exactly those three, unchanged by this work.
