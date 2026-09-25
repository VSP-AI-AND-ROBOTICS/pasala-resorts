# Room Status Grid (REQ-06) — Design

## Why

The client's requirement REQ-06 (`docs/requirements/ResortHub_Requirements_For_Manager.pdf`)
asks that duty managers (the Incharge, which is the `staff` resort role)
"transition room statuses (Available, Occupied, Cleaning, Maintenance), and
dispatch housekeeping staff", and that the system "track housekeeping cleaning
SLAs".

Today nothing records a room's housekeeping state:
- `units` has no status column. Its policies expose active units to anonymous
  users and let only owner/admin write, so a status column there would be
  public and unwritable by staff.
- The admin dashboard's "Farmhouse ready" card is hard-coded.
- `tasks` has no link to a unit, no kind, and no completion time. Staff cannot
  create tasks.

The front desk's check-in/out screens, the QR pass and guest service tabs
already exist and are out of scope.

## Decisions (agreed 2026-09-25)

1. **Occupied is derived**, never stored: a unit is occupied when it has a
   reservation with status `checked_in`. The existing exclusion constraint
   guarantees at most one per unit.
2. **Checkout marks the room Cleaning** automatically.
3. **Dispatching housekeeping creates a task** (kind `housekeeping`, linked to
   the unit) for one person. It appears in their existing Assigned Work
   screen; marking it done returns the room to Available.
4. **Owner, admin and staff** change room status and dispatch. Accountants see
   the grid read-only.
5. **Housekeepers** are members of the resort with the `staff` role.
6. **Maintenance** is a manual out-of-order flag with a required reason. It
   warns at check-in and does not block bookings (admins keep Block Dates).
7. **Cleaning SLA**: dispatched, started and completed times are recorded; each
   resort has a target in minutes (default 60); a room whose open housekeeping
   task is older than the target shows **Overdue**.
8. **All active units** appear, with day-use (slot-only) units labelled.
9. **Refresh**: pull-to-refresh and a refetch after your own actions and after
   check-in/out. Realtime updates are a later follow-up.
10. **Check-in into a Cleaning or Maintenance room** shows a warning and is not
    blocked.

## Data model — `supabase/migrations/0047_room_status.sql`

- Enum `public.room_state`: `ready`, `dirty`, `out_of_order`.
- Table `public.unit_room_status`:
  - `unit_id uuid primary key references units(id) on delete cascade`
  - `property_id uuid not null references properties(id)`, filled and checked
    against the unit by the existing `fill_property_id('units','unit_id')`
    trigger
  - `state public.room_state not null default 'ready'`
  - `reason text`, with `check (state <> 'out_of_order' or length(trim(reason)) > 0)`
  - `updated_by uuid default auth.uid()`, `updated_at timestamptz default now()`
  - A missing row means `ready`.
  - RLS read: `has_resort_role(property_id, false, 'owner','admin','staff','accountant')`.
    `select` granted to `authenticated`; no insert/update/delete grants or
    policies — writes only through the functions below.
- `tasks` gains:
  - enum `public.task_kind` (`general`, `housekeeping`), column `kind` default `general`
  - `unit_id uuid references units(id) on delete set null`
  - `started_at`, `completed_at timestamptz`, set by trigger when status moves
    to `in_progress` / `done`
  - `check ((kind = 'housekeeping') = (unit_id is not null))`
  - a trigger check that the unit's `property_id` equals the task's (raises P0021)
  - `tasks_enforce_write` is updated so an assignee still changes only
    `status` and cannot change `kind`, `unit_id` or the timestamps.
- `properties` gains `housekeeping_sla_minutes int not null default 60 check (> 0)`.

## Functions (security definer, `search_path = public, pg_temp`, revoked from public and anon, granted to authenticated)

- `room_status_board(p_property uuid)` — asserts read access for Staff+
  (`owner, admin, staff, accountant`). One row per active unit:
  `unit_id, name, booking_mode, effective_status, state, reason,
  occupied_reservation_id, guest_first_name, arriving_today,
  housekeeping_task_id, housekeeper_name, housekeeping_status,
  housekeeping_dispatched_at, overdue`.
  `effective_status` precedence: `occupied` (checked_in reservation) →
  `maintenance` (out_of_order) → `cleaning` (dirty) → `available`. The stored
  `state` is returned too, so an occupied room can still show a maintenance or
  needs-cleaning badge. `overdue` = open housekeeping task older than
  `housekeeping_sla_minutes`.
- `set_room_status(p_unit uuid, p_state public.room_state, p_reason text default null)`
  — reads the unit's `property_id`, asserts write access for
  `owner, admin, staff` (suspended resort → P0022); `out_of_order` without a
  reason raises **P0030 `reason_required`**; upserts the row; setting `ready`
  also marks any open housekeeping task for the unit `done`.
- `dispatch_housekeeping(p_unit uuid, p_assignee uuid, p_note text default null)`
  — asserts write access for `owner, admin, staff` at the unit's resort; the
  assignee must be a `staff` member of the same resort (else P0020); an
  existing open housekeeping task for the unit raises **P0031
  `already_dispatched`**; inserts the task (title `Clean <unit name>`,
  description = note) and marks the room `dirty`.
- `list_dispatchable_staff(p_property uuid)` — asserts read access for
  `owner, admin, staff`; returns only `user_id, full_name` of `staff` members.
- `checkout_booking` (0045) — after checkout, upserts the unit's row to `dirty`.
  The body is copied from its latest definition; only this step is added.
- New after-update trigger on `tasks`: when a housekeeping task becomes `done`
  and the room is not `out_of_order`, set the room `ready`.
- The definer allow-list in `37_tenancy_isolation_test.sql` gains the new
  function names.

## App

- `lib/data/models/room_status.dart`: `RoomStatus` enum (available, occupied,
  cleaning, maintenance) with label, icon and colour; `RoomBoardEntry.fromJson`.
- `lib/data/repositories/room_status_repository.dart`: `board(propertyId)`,
  `setStatus(unitId, state, reason)`, `dispatch(unitId, assigneeId, note)`,
  `dispatchableStaff(propertyId)`, errors through `_guard`/`mapPostgrestError`
  (map P0030 and P0031 to readable messages). A `RoomBoardSource` seam and
  `roomBoardProvider.family` keyed by property id.
- `lib/features/staff/room_status_screen.dart` at `/staff/rooms`:
  - summary chips with counts per status, which also filter the grid
  - responsive grid (2 columns on a phone, 4–6 on wide screens); each tile
    shows the unit name, a status chip with icon and label (not colour alone),
    the guest's first name if occupied, "Arriving today", "Day use" for
    slot-only units, and "Housekeeping: <name>, <n> min" with an "Overdue" badge
  - tapping a tile opens a sheet: Available / Needs cleaning / Maintenance
    (asks for a reason) and "Send housekeeping" (staff picker + optional note).
    Occupied is shown but not settable, with links to Check-in/Check-out.
  - accountants see the grid without actions
  - pull-to-refresh; the board is invalidated after every action and after
    check-in/out in the reception screens
- Navigation: "Rooms" added to the staff bottom bar (Today, Rooms, Dashboard,
  Reports) and to the admin dashboard; `/staff/rooms` is open to every member
  of the current resort (router role matrix updated).
- Assigned Work shows the unit name on housekeeping tasks.
- Reception check-in shows a warning chip when the booking's unit is Cleaning
  or Maintenance.
- Admin dashboard's hard-coded "Farmhouse ready" card uses the real board.

## Rules

- Every write goes through a definer function that takes a unit or task id,
  derives `property_id` from that row and asserts the role at that resort —
  never at a client-supplied resort.
- No existing policy on `units`, `tasks` or `reservations` is widened.
- Suspended resort: reads allowed, writes P0022. Archived: P0020.

## Testing

- pgTAP `supabase/tests/39_room_status_test.sql` (~40 assertions): role matrix
  (staff/admin/owner write, accountant read-only, customer/anon nothing);
  cross-resort isolation (also rows in 37's matrix); suspended resort; P0030;
  P0020 for a non-member or other-resort assignee; P0031; checkout → dirty;
  task done → ready, but not when out_of_order; board derivation (occupied with
  badges, overdue against the SLA, inactive units excluded); assignee cannot
  change `unit_id`/`kind`; definer allow-list guard passes.
- Flutter: `RoomBoardEntry.fromJson` and status mapping; `RoomStatusScreen`
  with a fake source (tiles and counts, sheet actions call the source, reason
  required, accountant has no actions, empty and error states); router matrix
  for `/staff/rooms`; app shell destinations; reception check-in warning;
  admin dashboard card.

## Out of scope

Realtime grid updates; deriving Maintenance from `maintenance_issues` (needs
`unit_id` on issues); a cleaning-SLA report; blocking check-in or bookings on
room state; QR scanning and guest service tabs.
