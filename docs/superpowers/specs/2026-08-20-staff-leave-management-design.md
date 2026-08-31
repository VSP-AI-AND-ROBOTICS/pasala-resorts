# Pasala Resorts — Staff Leave Management Design

Date: 2026-08-20
Builds on: the staff Work Schedules / Time Slots feature (commits
506b3d1..89689ff, spec `2026-08-19-staff-work-shifts-design.md`) — same
staff-operations hub, same admin/staff screen conventions, a sibling
feature with no data dependency on it (leave requests and shift
assignments are deliberately independent, see §7).
Status: approved by user in brainstorming session; ready for implementation
planning

## 1. What This Is

The second of the placeholder sections in the staff-operations hub to get
a real implementation: **Leave Management**. Staff submit a leave request
(a date range and an optional free-text reason); admin reviews the queue
and approves or rejects each one. There is currently no schema, no
repository, and no screen for any of this; it is built from scratch,
following the exact same conventions established by the Work Schedules /
Time Slots feature.

Scope, by role:

- **Staff/accountant** get `/staff/leave` wired to a real screen: their own
  request history plus a form to submit a new one.
- **Admin** gets a new screen to review, approve, and reject leave
  requests — defaulting to the pending queue, filterable to see
  everything.

## 2. Scope

**In scope:** a new `leave_requests` table + a new `leave_status` enum +
RLS policies (new migration `supabase/migrations/0022_leave_requests.sql`),
a new `LeaveRequestRepository`
(`lib/data/repositories/leave_request_repository.dart`) and
`LeaveRequest` model (`lib/data/models/leave_request.dart`), a new admin
screen (`lib/features/admin/leave_requests_screen.dart`, routed at
`/admin/leave-requests`, linked from `AdminHomeScreen`), and a real
implementation of the existing staff placeholder route `/staff/leave`
(replacing `PlaceholderSectionScreen` at that one route only).

**Out of scope:** Working Hours, Assigned Work/Tasks, and Daily Work
Status (the three remaining hub placeholders — separate future specs).
Leave types/categorization (free-text reason only, per the approved
design), staff-side cancellation or withdrawal of a pending request,
admin reversing an already-decided request, any interaction with
`staff_shifts` (no auto-flagging of overlapping shifts, no automatic
schedule changes), and any notification (push/email/outbox) when a
decision is made — all explicitly deferred, see §7.

## 3. Data Model

A new enum and one new table:

```sql
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
```

Notes on the design choices:

- **`end_date >= start_date`** allows a single-day request (`start_date ==
  end_date`) and rejects a backwards range at the database level.
- **No leave-type column.** Per the approved design, `reason` is a plain
  optional free-text field — no categorization, no dropdown-backed enum
  for type. This can be added later as a genuinely separate column if the
  business ever wants it; it is not modeled as a stringly-typed prefix or
  smuggled into `reason`.
- **`decided_by`/`decided_at`** are both `null` while `status = 'pending'`
  and both set together, atomically, the moment an admin decides — never
  independently. This is enforced by application code (the repository's
  `decide()` always sets both), not a database constraint; a constraint
  tying three columns together for a two-state transition was judged not
  worth the complexity for this scope.
- **No `updated_at`.** A request has exactly one state transition in its
  lifetime (`pending` → `approved` or `pending` → `rejected`, final — see
  §"Decision finality" in the brainstorming session), so `decided_at`
  already captures the one moment that matters. This mirrors
  `rate_rules`' own precedent of skipping `updated_at` for
  append/single-transition data.

RLS, following the same `is_admin()` / `is_staff_or_above()` convention as
every other table in this schema:

```sql
alter table public.leave_requests enable row level security;

grant select, insert, update on public.leave_requests to authenticated;

create policy leave_requests_admin_all on public.leave_requests
  for all to authenticated
  using (public.is_admin())
  with check (public.is_admin());

create policy leave_requests_own_read on public.leave_requests
  for select to authenticated
  using (staff_id = auth.uid());

create policy leave_requests_own_insert on public.leave_requests
  for insert to authenticated
  with check (staff_id = auth.uid() and status = 'pending');
```

Admin has full read/write (subject to the same `before update or delete`
enforcement-trigger pattern Work Schedules established, since a plain RLS
`USING` clause on UPDATE silently no-ops rather than erroring for a denied
caller — see that feature's own migration for the precedent this repeats).
A staff/accountant user can `select` only their own rows and can `insert`
only a `pending` request for themselves — no `update`/`delete` grant
resolves to anything for them at all, matching "staff cannot cancel or
withdraw."

## 4. Repository & Model

`lib/data/models/leave_request.dart` — a plain model matching the table:
`id`, `staffId`, `staffName` (populated only on the admin-facing joined
read, `null` otherwise — same convention as `StaffShift.staffName`),
`startDate`, `endDate`, `reason`, `status` (a `LeaveStatus` enum:
`pending`, `approved`, `rejected`), `decidedBy`, `decidedAt`, `createdAt`.

`lib/data/repositories/leave_request_repository.dart` — follows
`StaffShiftRepository`'s shape exactly: constructed with a raw
`SupabaseClient`, wraps every call in the existing `_guard`/
`mapPostgrestError` pattern.

- `list({String? staffId, LeaveStatus? status})` — a direct table
  `select('*, profiles(full_name)')` (no RPC needed this time: there is no
  cross-role visibility rule beyond what RLS itself already handles via a
  plain select, unlike Work Schedules' `p_staff_id`-can't-leak-via-filter
  concern, since this repository never accepts an arbitrary caller-chosen
  id to filter by from the staff side — staff always call with their own
  id, and RLS's `leave_requests_own_read` policy backs that regardless).
  Optional `staffId`/`status` filters are applied server-side; `staffId:
  null` (admin only) means every staff member.
- `create({required String staffId, required DateTimeRange range, String?
  reason})` — a single-row insert (`status` defaults to `'pending'`
  server-side; the client never sends `status`).
- `decide({required String id, required bool approved})` — updates
  `status` to `'approved'`/`'rejected'`, `decided_by` to the caller's own
  id (read via `_db.auth.currentUser!.id`, the same way `created_by`
  self-populates via `auth.uid()` on the database side for Work
  Schedules — here it's set client-side since `decide()` needs to send
  both `status` and `decided_by` together in one `update` call, and
  `auth.uid()` as a column default only applies on `insert`, not
  `update`), `decided_at` to `now()`.

Providers, matching the established convention: a plain
`Provider<LeaveRequestRepository>`, plus a `FutureProvider.family` wrapper
(`leaveRequestsProvider`, keyed on a `LeaveRequestFilter` record `({String?
staffId, LeaveStatus? status})`) for the screens to watch.

## 5. Admin Screen — `/admin/leave-requests`

Routed from a new `AdminHomeScreen` destination ("Leave requests" /
`event_busy`-style icon / "Review and decide staff leave requests"),
gated admin-only like `/admin/staff-shifts` (a write action, not the
`/admin/dashboard`/`/admin/reports`/`/admin/outbox` staff-or-above
carve-out).

Structure, simpler than Staff Shifts since there's no create/edit form on
the admin side (nothing for admin to fill in — only a binary decision):

- Defaults to the `Pending` filter (per the approved design), with a
  segmented control or dropdown to switch to `All`/`Approved`/`Rejected`,
  plus a staff-member filter dropdown (same `adminProfilesProvider`
  filtered to staff-or-above, as Staff Shifts already established).
- Each row shows staff name, date range, reason (if present), and current
  status. A `Pending` row gets two inline buttons, `Approve` and `Reject`,
  each calling `decide()` directly (no confirmation dialog — unlike a
  destructive delete, an approve/reject mistake is correctable by asking
  admin to submit a new one and is a much lower-stakes action; matching
  the "no note, just the status" simplicity already chosen). A
  non-pending row shows its decided status as plain text, no actions.
- `EmptyState` when the current filter matches nothing (e.g. "No pending
  requests").

## 6. Staff Screen — `/staff/leave`

Replaces the existing `PlaceholderSectionScreen` route registration only.

A list (`AsyncView`/`EmptyState`, same shape as `TimeSlotsScreen`) of the
signed-in staff member's own requests, newest-first, each row showing the
date range, reason (if present), and a status chip (color-coded: pending
= neutral/tertiary, approved = primary, rejected = muted — reusing the
same `_statusColors`-style convention `BookingTile` already established
for reservation status chips). A `FloatingActionButton` opens a small
form (`LeaveRequestFormScreen`): a date-range picker
(`showDateRangePicker`, the established convention) and an optional notes
`TextField` for the reason. Submitting calls `create()` and pops back to
the list. No edit, no cancel, no delete — a submitted request is
immutable from the staff side, per the approved design.

## 7. Explicitly Deferred

- **No interaction with `staff_shifts`.** Approving a leave request does
  not check, flag, or touch any shift row. If a staff member is approved
  for leave during dates they're also scheduled to work, admin is
  responsible for noticing and manually adjusting the schedule — the two
  features are independent on purpose, per the approved design. A
  cross-referencing warning (or an automatic shift cancellation) is a
  deliberate future enhancement, not something this schema self-corrects
  into.
- **No staff-side cancellation or withdrawal.** Once submitted, a request
  can only be decided by admin; there is no `withdrawn` status and no
  staff-facing delete/cancel action.
- **No reversing a decision.** `approved`/`rejected` are both terminal —
  there is no admin action to flip a decided request back to `pending` or
  to the other terminal state. If circumstances change, that is handled
  outside this system (the same way this app already treats other
  one-way decisions).
- **No rejection reason/note.** Per the approved design, a rejected
  request shows only its status — no admin-authored explanation is
  stored or surfaced.
- **No leave-type categorization.** `reason` is free text; there is no
  fixed set of leave types (Sick/Casual/Vacation/etc.) to select from.
- **No notifications.** No push/email/outbox entry when a request is
  submitted or decided. A staff member finds out by opening the app; an
  admin finds out there's a new pending request the same way.
- **No leave-balance tracking.** This is a request/decision log only —
  there is no concept of an annual leave allowance, accrual, or remaining
  balance being decremented anywhere in this design.

## 8. Testing

- Pure logic: none of substance beyond the model's `fromJson`/`toInsert`
  round-trip — this feature has no calendar-day-classification or
  date-range-fanout logic comparable to Work Schedules' `hasShiftOn`/
  `createRange`, since a leave request is a single row, not a per-day
  expansion.
- `LeaveRequestRepository`: no dedicated unit-test file, matching the
  established convention (`RateRepository`, `StaffShiftRepository`) —
  exercised via a `FakeLeaveRequestRepository` in the screen widget tests.
- Widget tests: admin list+filter+approve/reject (mirroring
  `staff_shifts_screen_test.dart`'s coverage shape, adapted for the
  simpler no-form admin interaction), staff list+submit-form (mirroring
  `time_slots_screen_test.dart`'s shape), confirming a staff member never
  sees another staff member's requests even when seeded.
- pgTAP: table/enum/RLS coverage mirroring `17_staff_shifts_test.sql`'s
  shape — admin can insert/update any row, staff can insert only their
  own `pending` row and cannot update/delete at all, a staff member's
  `select` only ever returns their own rows, and the `end_date >=
  start_date` check rejects a backwards range. New file
  `supabase/tests/18_leave_requests_test.sql`.
- `flutter test`, `flutter analyze`, and `supabase test db` all run clean
  at the end. The three pre-existing, unrelated `hold_lifecycle_test.dart`
  failures are expected to remain exactly those three, unchanged by this
  work.
