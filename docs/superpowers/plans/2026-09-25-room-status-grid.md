# Room Status Grid (REQ-06) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give duty managers a live grid of every active room (Available / Occupied / Cleaning / Maintenance) where they change a room's housekeeping state, send a housekeeper, and see cleaning-SLA overruns. Checkout marks a room for cleaning, and finishing the housekeeping task makes it Available again.

**Architecture:** A new table `unit_room_status` stores the state a person sets. The table is readable by the resort's Staff+ and written only by `security definer` functions that find the resort from the unit. Occupied is never stored: the definer function `room_status_board` works it out from checked-in reservations. Housekeeping reuses `tasks`, which gains `kind`, `unit_id` and `started_at`, so dispatched work shows up in the existing Assigned Work screen. On the app side, a `RoomBoardSource` seam sits behind Riverpod providers keyed by property id, feeding a new `/staff/rooms` screen, the admin dashboard, reception check-in and Assigned Work.

**Tech Stack:** Supabase Postgres 15 (plpgsql, RLS, pgTAP via `supabase test db`), Flutter 3.44 / Dart 3.10, Riverpod 3.3, go_router 17.

**Spec:** `docs/superpowers/specs/2026-09-25-room-status-grid-design.md`

## Global Constraints

- One migration: `supabase/migrations/0047_room_status.sql`. Tasks 1–4 each edit it. After every edit, rebuild with `supabase db reset` (this re-runs every migration and `supabase/seed.sql`), then run pgTAP. Before the first reset in this plan, dump local data if you need it: `mkdir -p ../pasala-db-backups && supabase db dump --local --data-only -f ../pasala-db-backups/local-before-room-status.sql`.
- New pgTAP file: `supabase/tests/39_room_status_test.sql`. It is built up section by section by Tasks 1–4, and each section relies on the state the earlier ones leave. Run one file with `supabase test db supabase/tests/39_room_status_test.sql` and the whole suite with `supabase test db`.
- New error codes: **P0030 `reason_required`**, **P0031 `already_dispatched`**. Raise them with `raise exception using errcode = 'P0030', message = 'reason_required'`. The existing codes keep their meaning: P0002 not found, P0005 bad input, P0020 not_a_member, P0021 resort_mismatch, P0022 resort_suspended.
- Every new `security definer` function has `set search_path = public, pg_temp`. Each is revoked from `public` and `anon`, is granted to `authenticated`, and is added to the definer allow-list in `supabase/tests/37_tenancy_isolation_test.sql`.
- When changing an existing function, copy its **latest** definition. `checkout_booking` and `tasks_enforce_write` are both latest in `0045_resort_functions.sql`.
- Role sets. Read the board: `owner, admin, staff, accountant`. Change status, dispatch, list housekeepers: `owner, admin, staff`. Can be dispatched: members with role `staff` at the unit's resort, and nobody else.
- Every write derives `property_id` from the unit or task row and asserts the caller's role at **that** resort, never at a resort id the client supplied.
- No existing policy on `units`, `tasks` or `reservations` is widened.
- Suspended resort: reads allowed, writes P0022. Archived resort: P0020.
- "Today" is the `Asia/Kolkata` calendar date, the same as `dashboard_summary`.
- pgTAP conventions (from `37_tenancy_isolation_test.sql`): switch users with `set local role authenticated; set local request.jwt.claims to '{"sub":"<uuid>","role":"authenticated"}';`. `reset role` does **not** clear the claims, so run `set local request.jwt.claims to '';` before any superuser change that a trigger checks against `auth.uid()` (resort status, task updates).
- Dart: repositories wrap every call in `_guard`, which maps errors through `mapPostgrestError` (`lib/core/errors.dart`). Providers are families keyed by `propertyId`, read from `currentResortProvider`. Widget tests use fakes from `test/support/` and never a real `SupabaseClient`.
- UI copy, exact:
  - Status labels: `Available`, `Occupied`, `Cleaning`, `Maintenance`.
  - Actions: `Needs cleaning`, `Send housekeeping`.
  - Tile lines: `Day use`, `Arriving today`, `Guest: <first name>`, `Housekeeping: <first name>, <n> min`, `Overdue`.
  - The `staff` role is "Staff / Incharge".
- A status is never shown by colour alone: every status chip carries its icon and its label.
- Commands: `flutter test <path>`, `flutter test`, and `flutter analyze` (no new issues beyond the baseline recorded in Task 1 Step 1). Never run `dart format` over whole directories, because the repo is not formatted with the current SDK. Format only the lines you write.

## Review Focus

1. **A room already in Maintenance must stay in Maintenance when housekeeping is sent to it or its guest checks out.** The spec says dispatch and checkout "mark the room dirty", and the out-of-order reason would be silently lost. Owning tests: Task 3 (dispatch to an out-of-order room, then the task finished), Task 4 (checkout of an out-of-order room).
2. **Two people sending housekeeping to the same room at the same moment** must give one task and one "already on its way" message, never two open tasks. The fix is a partial unique index, plus a `unique_violation` handler that maps to P0031. Owning test: Task 3 (a second open housekeeping task for a unit is refused by the index).
3. **A Staff / Incharge who is not the assignee marks a room Available.** The open housekeeping task must close without `tasks_enforce_write` rejecting the definer's update, and that same staff member must still be unable to update the task directly. Owning tests: Task 3 (Incharge marks Available and the task closes; the Incharge's direct update changes 0 rows).
4. **The room board fails to load at reception.** Check-in must still work: the warning is advice, never a gate (spec decision 10). Owning test: Task 10 (board error, Check In still shown and no warning).
5. **Deleting a unit that has housekeeping history.** The spec's pair "`unit_id … on delete set null`" and "`check ((kind = 'housekeeping') = (unit_id is not null))`" would make every such delete fail, so the check here is relaxed to `unit_id is null or kind = 'housekeeping'` (see Plan decisions). Owning test: Task 3 (an admin deletes the unit and its tasks are kept, unlinked).

## Plan decisions (where the spec is silent or contradicts itself)

- `tasks.completed_at` already exists (added in `0029`), and `tasks_enforce_write` already sets it. Only `started_at` is new. It is set the first time a task moves to `in_progress`.
- The check constraint is `tasks_unit_only_for_housekeeping check (unit_id is null or kind = 'housekeeping')` (Review Focus 5). `dispatch_housekeeping` is the only way the app creates a housekeeping task, and it always sets `unit_id`.
- Dispatch and checkout set `dirty` only when the room is not `out_of_order` (Review Focus 1).
- At most one open housekeeping task per unit, enforced by the partial unique index `tasks_one_open_housekeeping_per_unit` (Review Focus 2).
- `tasks_enforce_write` gains a "room writer" branch. On a `housekeeping` task, an owner, admin or staff member of the task's resort may change the status only. RLS (`tasks_update`) still admits only admins and the assignee to a direct table update, so this branch is reachable only through the definer functions (Review Focus 3).
- An unknown unit id raises P0002 before the role check, the same as `block_dates`.
- `set_room_status` returns `void`. `dispatch_housekeeping` returns the new task's `uuid`.
- `roomBoardProvider` and `dispatchableStaffProvider` are `autoDispose`, like `checkedInProvider`: opening the grid always fetches fresh data, whatever navigation path led there.
- The owner hub gets a "Rooms" tile. The spec names only the staff bar and the admin dashboard, but spec decision 4 makes owners writers too, and without the tile they have no way in.
- On the admin dashboard, only the "Rooms / Cottages" line and the Overall Status pill become real. Pool, Garden, Kitchen and Wi-Fi have no data anywhere in the app and stay a fixed checklist.
- On a tile, an occupied room with a stored state shows the badge `Needs cleaning` or `Out of order`. The housekeeping line shows the housekeeper's first name.

## Execution tracks

After Task 1, the database track and the app track share no files and can run in parallel, for example in two worktrees branched from Task 1's commit and merged back before Task 11. App tasks never need a database, because their tests use `FakeRoomBoardSource`.

| Task | Track | Depends on | Files it owns |
|---|---|---|---|
| 1 Interface contract | both | none | `0047` (schema + stubs), `39` (fixtures + contract), `37` (allow-list), `room_status.dart`, `room_status_repository.dart`, `fake_room_board_source.dart` |
| 2 Board and set_room_status | DB | 1 | `0047`, `39` |
| 3 Dispatch and housekeeping tasks | DB | 2 | `0047`, `39`, `37` |
| 4 Checkout, isolation, suspension | DB | 3 | `0047`, `39`, `37` |
| 5 Room grid screen | App | 1 | `room_status_screen.dart`, `room_tile.dart` |
| 6 Room actions sheet | App | 5 | `room_actions_sheet.dart`, `room_status_screen.dart`, `errors.dart` |
| 7 Navigation | App | 5 | `router.dart`, `app_shell.dart`, `owner_home_screen.dart` |
| 8 Admin dashboard | App | 1 | `admin_home_screen.dart` |
| 9 Assigned Work shows the room | App | 1 | `staff_task.dart`, `task_repository.dart`, `assigned_tasks_screen.dart` |
| 10 Reception warning and refresh | App | 1 | `reception_checkin_screen.dart`, `reception_checkout_screen.dart` |
| 11 Integration | both | 2–10 | none (verification) |

- The database track is strictly sequential: Tasks 2, 3 and 4 share one migration file, one test file and one local Postgres.
- In the app track, Tasks 6 and 7 wait for Task 5. Tasks 8, 9 and 10 can run alongside 5–7 and alongside each other.

---

## File Structure

**Database**
- Create `supabase/migrations/0047_room_status.sql`: the enums `room_state` and `task_kind`, `properties.housekeeping_sla_minutes`, the `unit_room_status` table with its RLS, the new `tasks` columns and rules, the four room functions, the trigger that marks a room ready, and `checkout_booking` marking the room dirty.
- Create `supabase/tests/39_room_status_test.sql`: fixtures, contract, role matrix, derivation, dispatch, task rules, checkout, suspension.
- Modify `supabase/tests/37_tenancy_isolation_test.sql`: definer allow-list, and cross-resort rows for the room functions.

**App**
- Create `lib/data/models/room_status.dart`: `RoomStatus` (label, icon, colour), `RoomState`, `RoomBoardEntry`, `DispatchableStaff`.
- Create `lib/data/repositories/room_status_repository.dart`: the `RoomBoardSource` seam, `RoomStatusRepository`, and providers.
- Create `lib/features/staff/room_status_screen.dart`: `/staff/rooms`, with summary chips, filter and grid.
- Create `lib/features/staff/room_tile.dart`: `StatusPill`, `RoomStatusChip`, `RoomTile`, `housekeepingLine`.
- Create `lib/features/staff/room_actions_sheet.dart`: the room sheet, the maintenance-reason dialog and the dispatch dialog.
- Modify `lib/core/errors.dart`: P0030 and P0031.
- Modify `lib/core/router.dart`: the `/staff/rooms` route.
- Modify `lib/features/shell/app_shell.dart`: the staff bar becomes Today, Rooms, Dashboard, Reports.
- Modify `lib/features/owner/owner_home_screen.dart`: a Rooms tile.
- Modify `lib/features/admin/admin_home_screen.dart`: real room readiness and a Rooms quick action.
- Modify `lib/data/models/staff_task.dart`, `lib/data/repositories/task_repository.dart` and `lib/features/staff/assigned_tasks_screen.dart`: the room name on housekeeping tasks.
- Modify `lib/features/admin/reception_checkin_screen.dart` and `lib/features/admin/reception_checkout_screen.dart`: the check-in warning and the board refresh.
- Create `test/support/fake_room_board_source.dart`, `test/data/room_status_test.dart`, `test/data/room_board_provider_test.dart` and `test/features/staff/room_status_screen_test.dart`. Modify the tests of every file listed above.

---

## Phase 0: Interface

### Task 1: Interface contract (schema, function signatures, Dart API)

**Track:** both. Every later task depends on it.

**Files:**
- Create: `supabase/migrations/0047_room_status.sql`
- Create: `supabase/tests/39_room_status_test.sql`
- Modify: `supabase/tests/37_tenancy_isolation_test.sql` (definer allow-list)
- Create: `lib/data/models/room_status.dart`
- Create: `lib/data/repositories/room_status_repository.dart`
- Create: `test/support/fake_room_board_source.dart`
- Test: `test/data/room_status_test.dart`, `test/data/room_board_provider_test.dart`

**Interfaces:**
- Consumes: `public.fill_property_id(parent_table, parent_col)`, `public.has_resort_role(uuid, boolean, variadic resort_role[])` (0043). `BookingMode` (`lib/data/models/unit.dart`), `TaskStatus` / `taskStatusFromDb` (`lib/data/models/staff_task.dart`), `mapPostgrestError`, `supabaseProvider`.
- Produces (SQL; later tasks replace only the stub bodies):
  - `public.room_status_board(p_property uuid) returns table (unit_id uuid, name text, booking_mode public.booking_mode, effective_status text, state public.room_state, reason text, occupied_reservation_id uuid, guest_first_name text, arriving_today boolean, housekeeping_task_id uuid, housekeeper_name text, housekeeping_status public.task_status, housekeeping_dispatched_at timestamptz, overdue boolean)`. `effective_status` is one of `available|occupied|cleaning|maintenance`.
  - `public.set_room_status(p_unit uuid, p_state public.room_state, p_reason text default null) returns void`
  - `public.dispatch_housekeeping(p_unit uuid, p_assignee uuid, p_note text default null) returns uuid`
  - `public.list_dispatchable_staff(p_property uuid) returns table (user_id uuid, full_name text)`
  - Enums `public.room_state ('ready','dirty','out_of_order')` and `public.task_kind ('general','housekeeping')`. Table `public.unit_room_status`. Columns `tasks.kind`, `tasks.unit_id`, `tasks.started_at`, `properties.housekeeping_sla_minutes`.
- Produces (Dart):
  - `enum RoomStatus { available, occupied, cleaning, maintenance }`, with `roomStatusFromDb(String)` and the extension `RoomStatusDisplay` (`label`, `icon`, `color`).
  - `enum RoomState { ready, dirty, outOfOrder }`, with `roomStateFromDb(String)` and `roomStateToDb(RoomState)`.
  - `class RoomBoardEntry`, with the fields `unitId, name, bookingMode, status, state, reason, occupiedReservationId, guestFirstName, arrivingToday, housekeepingTaskId, housekeeperName, housekeepingStatus, housekeepingDispatchedAt, overdue`, the getters `isDayUse` and `hasOpenHousekeeping`, and `int? minutesSinceDispatch(DateTime now)`.
  - `class DispatchableStaff { userId, fullName, displayName }`.
  - `abstract class RoomBoardSource`:
    - `Future<List<RoomBoardEntry>> board(String propertyId)`
    - `Future<void> setStatus(String unitId, RoomState state, {String? reason})`
    - `Future<String> dispatch(String unitId, String assigneeId, {String? note})`
    - `Future<List<DispatchableStaff>> dispatchableStaff(String propertyId)`
  - Providers: `roomStatusRepositoryProvider`, `roomBoardSourceProvider` (`Provider<RoomBoardSource>`), `roomBoardProvider` (`FutureProvider.autoDispose.family<List<RoomBoardEntry>, String>`) and `dispatchableStaffProvider` (`FutureProvider.autoDispose.family<List<DispatchableStaff>, String>`).
  - Test support: `FakeRoomBoardSource`, with the fields `entries`, `staff`, `boardError`, `setStatusError`, `dispatchError` and `staffError`, and the call logs `boardCalls`, `setStatusCalls`, `dispatchCalls` and `staffCalls`. Also `boardEntry({...})`.

- [ ] **Step 1: Record the baselines**

Run: `supabase db reset && supabase test db 2>&1 | tail -20`, then `flutter analyze 2>&1 | tail -5`, then `flutter test 2>&1 | tail -3`
Expected: write down the pgTAP failure count and names. The tenancy ledger records 3 pre-existing time-of-day failures around the Asia/Kolkata midnight boundary. Also write down the analyzer issue count and the Flutter pass count. Later tasks compare against these numbers.

- [ ] **Step 2: Write the failing pgTAP contract test**

Create `supabase/tests/39_room_status_test.sql`:

```sql
-- Room status grid (REQ-06), added in 0047_room_status.sql. See
-- docs/superpowers/specs/2026-09-25-room-status-grid-design.md.
--
-- One file, built up by the plan's database tasks in order: each section
-- relies on the state the sections before it leave behind.
--
-- Fixtures: resort R with an owner, an admin, two staff members (Indu the
-- Incharge, Hari the housekeeper) and an accountant; resort S with an owner
-- and one staff member (Sam); a guest (Gita) and an outsider with no
-- membership. R's units: Cottage 1 (Gita is checked in), Day Hut
-- (slot-only), Old Barn (inactive) and Cottage 4 (a confirmed arrival
-- today, Asia/Kolkata).
begin;
select plan(14);

-- Rows a statement changed, run as the current role (0 when RLS filters
-- it). Used by later sections.
create function pg_temp.rows_affected(p_sql text) returns int
language plpgsql as $f$
declare n int;
begin
  execute p_sql;
  get diagnostics n = row_count;
  return n;
end;
$f$;

insert into auth.users (id, email) values
  ('e0000000-0000-0000-0000-000000000001','r-owner@example.com'),
  ('e0000000-0000-0000-0000-000000000002','r-admin@example.com'),
  ('e0000000-0000-0000-0000-000000000003','r-incharge@example.com'),
  ('e0000000-0000-0000-0000-000000000004','r-housekeeper@example.com'),
  ('e0000000-0000-0000-0000-000000000005','r-accountant@example.com'),
  ('e0000000-0000-0000-0000-000000000006','s-owner@example.com'),
  ('e0000000-0000-0000-0000-000000000007','s-staff@example.com'),
  ('e0000000-0000-0000-0000-000000000008','guest@example.com'),
  ('e0000000-0000-0000-0000-000000000009','outsider@example.com');
update public.profiles set full_name = 'Indu Incharge'
  where id = 'e0000000-0000-0000-0000-000000000003';
update public.profiles set full_name = 'Hari Housekeeper'
  where id = 'e0000000-0000-0000-0000-000000000004';
update public.profiles set full_name = 'Sam Other'
  where id = 'e0000000-0000-0000-0000-000000000007';
update public.profiles set full_name = 'Gita Guest Rao'
  where id = 'e0000000-0000-0000-0000-000000000008';

insert into public.properties (id, name, slug) values
  ('eeeeeeee-0000-4000-8000-000000000001','Resort R','rooms-r'),
  ('eeeeeeee-0000-4000-8000-000000000002','Resort S','rooms-s');

insert into public.resort_members (property_id, user_id, role) values
  ('eeeeeeee-0000-4000-8000-000000000001','e0000000-0000-0000-0000-000000000001','owner'),
  ('eeeeeeee-0000-4000-8000-000000000001','e0000000-0000-0000-0000-000000000002','admin'),
  ('eeeeeeee-0000-4000-8000-000000000001','e0000000-0000-0000-0000-000000000003','staff'),
  ('eeeeeeee-0000-4000-8000-000000000001','e0000000-0000-0000-0000-000000000004','staff'),
  ('eeeeeeee-0000-4000-8000-000000000001','e0000000-0000-0000-0000-000000000005','accountant'),
  ('eeeeeeee-0000-4000-8000-000000000002','e0000000-0000-0000-0000-000000000006','owner'),
  ('eeeeeeee-0000-4000-8000-000000000002','e0000000-0000-0000-0000-000000000007','staff');

insert into public.units (id, property_id, name, capacity_base, capacity_max, booking_mode, is_active) values
  ('eeeeeeee-0000-4000-8000-000000000011','eeeeeeee-0000-4000-8000-000000000001','Cottage 1',2,4,'nightly',true),
  ('eeeeeeee-0000-4000-8000-000000000012','eeeeeeee-0000-4000-8000-000000000001','Day Hut',2,4,'slot',true),
  ('eeeeeeee-0000-4000-8000-000000000013','eeeeeeee-0000-4000-8000-000000000001','Old Barn',2,4,'nightly',false),
  ('eeeeeeee-0000-4000-8000-000000000014','eeeeeeee-0000-4000-8000-000000000001','Cottage 4',2,4,'nightly',true);

-- Gita is in Cottage 1 now; Cottage 4 has a confirmed arrival at 14:00
-- today, Asia/Kolkata (the same "today" room_status_board uses).
insert into public.reservations (id, unit_id, period, kind, status, customer_id, guests, checked_in_at) values
  ('eeeeeeee-0000-4000-8000-000000000031','eeeeeeee-0000-4000-8000-000000000011',
   tstzrange(now() - interval '1 day', now() + interval '1 day', '[)'),
   'booking','checked_in','e0000000-0000-0000-0000-000000000008',2, now() - interval '1 day'),
  ('eeeeeeee-0000-4000-8000-000000000032','eeeeeeee-0000-4000-8000-000000000014',
   tstzrange(((now() at time zone 'Asia/Kolkata')::date + time '14:00') at time zone 'Asia/Kolkata',
             ((now() at time zone 'Asia/Kolkata')::date + 1 + time '11:00') at time zone 'Asia/Kolkata', '[)'),
   'booking','confirmed','e0000000-0000-0000-0000-000000000008',2, null);

-- === Task 1: the contract ===================================================

select has_table('public', 'unit_room_status', 'unit_room_status exists');
select enum_has_labels('public', 'room_state', array['ready','dirty','out_of_order'],
  'room_state is ready, dirty, out_of_order');
select enum_has_labels('public', 'task_kind', array['general','housekeeping'],
  'task_kind is general, housekeeping');
select is((select array_agg(column_name::text order by column_name)
             from information_schema.columns
            where table_schema = 'public' and table_name = 'tasks'
              and column_name in ('kind','unit_id','started_at')),
  array['kind','started_at','unit_id'], 'tasks gains kind, unit_id and started_at');
select is((select column_default from information_schema.columns
            where table_schema = 'public' and table_name = 'properties'
              and column_name = 'housekeeping_sla_minutes'),
  '60', 'the cleaning SLA defaults to 60 minutes');
select throws_ok($$insert into public.unit_room_status (unit_id, state)
  values ('eeeeeeee-0000-4000-8000-000000000014', 'out_of_order')$$,
  '23514', null, 'an out-of-order row without a reason is refused by the table itself');
select is((select array_agg(p.parameter_name::text order by p.ordinal_position)
             from information_schema.parameters p
             join information_schema.routines r
               on r.specific_schema = p.specific_schema and r.specific_name = p.specific_name
            where r.routine_schema = 'public' and r.routine_name = 'room_status_board'
              and p.parameter_mode = 'OUT'),
  array['unit_id','name','booking_mode','effective_status','state','reason',
        'occupied_reservation_id','guest_first_name','arriving_today',
        'housekeeping_task_id','housekeeper_name','housekeeping_status',
        'housekeeping_dispatched_at','overdue'],
  'room_status_board returns the columns RoomBoardEntry.fromJson reads');
select is((select array_agg(p.parameter_name::text order by p.ordinal_position)
             from information_schema.parameters p
             join information_schema.routines r
               on r.specific_schema = p.specific_schema and r.specific_name = p.specific_name
            where r.routine_schema = 'public' and r.routine_name = 'list_dispatchable_staff'
              and p.parameter_mode = 'OUT'),
  array['user_id','full_name'], 'list_dispatchable_staff returns user_id and full_name');
select is((select array_agg(f::text order by f::text)
             from unnest(array[
               'public.room_status_board(uuid)',
               'public.set_room_status(uuid, public.room_state, text)',
               'public.dispatch_housekeeping(uuid, uuid, text)',
               'public.list_dispatchable_staff(uuid)']::regprocedure[]) f
            where has_function_privilege('anon', f, 'execute')),
  null, 'anon can execute none of the room functions');
select is((select count(*)::int
             from unnest(array[
               'public.room_status_board(uuid)',
               'public.set_room_status(uuid, public.room_state, text)',
               'public.dispatch_housekeeping(uuid, uuid, text)',
               'public.list_dispatchable_staff(uuid)']::regprocedure[]) f
            where has_function_privilege('authenticated', f, 'execute')),
  4, 'authenticated can execute all four room functions');

-- Reads: the resort's own members only; no direct writes for anyone. The
-- row goes on the inactive Old Barn so it never shows on the board.
insert into public.unit_room_status (unit_id, state)
  values ('eeeeeeee-0000-4000-8000-000000000013', 'dirty');
set local role authenticated;
set local request.jwt.claims to '{"sub":"e0000000-0000-0000-0000-000000000003","role":"authenticated"}';
select is((select count(*)::int from public.unit_room_status), 1,
  'staff read their resort''s room rows');
select throws_ok($$insert into public.unit_room_status (unit_id, state)
  values ('eeeeeeee-0000-4000-8000-000000000012', 'dirty')$$,
  '42501', null, 'staff cannot write room rows directly');
set local request.jwt.claims to '{"sub":"e0000000-0000-0000-0000-000000000007","role":"authenticated"}';
select is((select count(*)::int from public.unit_room_status), 0,
  'staff of another resort read none of them');
set local request.jwt.claims to '{"sub":"e0000000-0000-0000-0000-000000000008","role":"authenticated"}';
select is((select count(*)::int from public.unit_room_status), 0,
  'a guest reads none of them');
reset role;
set local request.jwt.claims to '';

select * from finish();
rollback;
```

- [ ] **Step 3: Run it to verify it fails**

Run: `supabase test db supabase/tests/39_room_status_test.sql`
Expected: FAIL at the first `insert into public.units … booking_mode` fixture or at `has_table`. The error mentions `unit_room_status` or `room_state` not existing.

- [ ] **Step 4: Write the migration's schema and function stubs**

Create `supabase/migrations/0047_room_status.sql`:

```sql
-- Room status grid (REQ-06): the housekeeping state of each unit,
-- housekeeping tasks linked to a unit, and a per-resort cleaning SLA.
-- See docs/superpowers/specs/2026-09-25-room-status-grid-design.md.
--
-- Error codes: P0030 reason_required (Maintenance needs a reason), P0031
-- already_dispatched (the unit already has an open housekeeping task).
-- Also raised: P0002 (unknown unit), P0005 (missing state), P0020
-- not_a_member, P0021 resort_mismatch, P0022 resort_suspended.

create type public.room_state as enum ('ready', 'dirty', 'out_of_order');
create type public.task_kind as enum ('general', 'housekeeping');

-- ---------------------------------------------------------------------
-- The cleaning SLA: an open housekeeping task older than this many
-- minutes shows Overdue on the board.
alter table public.properties
  add column housekeeping_sla_minutes int not null default 60
    constraint properties_housekeeping_sla_positive
      check (housekeeping_sla_minutes > 0);

-- ---------------------------------------------------------------------
-- unit_room_status: the state a person set. A unit without a row is
-- `ready`. Occupied is never stored -- room_status_board derives it from
-- a checked-in reservation. Readable by the resort's Staff+; written only
-- by the security definer functions below (no write grant or policy).
create table public.unit_room_status (
  unit_id     uuid primary key references public.units(id) on delete cascade,
  property_id uuid not null references public.properties(id),
  state       public.room_state not null default 'ready',
  reason      text,
  updated_by  uuid default auth.uid(),
  updated_at  timestamptz not null default now(),
  -- coalesce: `length(trim(null)) > 0` is null, which a CHECK accepts,
  -- so without it a null reason would slip through.
  constraint unit_room_status_reason_required
    check (state <> 'out_of_order' or coalesce(length(btrim(reason)), 0) > 0)
);
create index unit_room_status_property_idx on public.unit_room_status (property_id);

create trigger unit_room_status_fill_property
  before insert or update on public.unit_room_status
  for each row execute function public.fill_property_id('units', 'unit_id');

alter table public.unit_room_status enable row level security;
revoke all on public.unit_room_status from anon, authenticated;
grant select on public.unit_room_status to authenticated;

create policy unit_room_status_read on public.unit_room_status
  for select to authenticated
  using (public.has_resort_role(property_id, false, 'owner','admin','staff','accountant'));

-- ---------------------------------------------------------------------
-- tasks: a housekeeping task points at a unit. completed_at already
-- exists (0029); started_at joins it.
alter table public.tasks
  add column kind       public.task_kind not null default 'general',
  add column unit_id    uuid references public.units(id) on delete set null,
  add column started_at timestamptz;
create index tasks_unit_idx on public.tasks (unit_id) where unit_id is not null;

-- ---------------------------------------------------------------------
-- Room functions. The signatures are the contract the app is built
-- against; Tasks 2 and 3 of the plan replace the stub bodies.

create function public.room_status_board(p_property uuid)
returns table (
  unit_id                    uuid,
  name                       text,
  booking_mode               public.booking_mode,
  effective_status           text,
  state                      public.room_state,
  reason                     text,
  occupied_reservation_id    uuid,
  guest_first_name           text,
  arriving_today             boolean,
  housekeeping_task_id       uuid,
  housekeeper_name           text,
  housekeeping_status        public.task_status,
  housekeeping_dispatched_at timestamptz,
  overdue                    boolean
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  raise exception 'room_status_board is not implemented yet' using errcode = '0A000';
end;
$$;

create function public.set_room_status(
  p_unit   uuid,
  p_state  public.room_state,
  p_reason text default null
) returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  raise exception 'set_room_status is not implemented yet' using errcode = '0A000';
end;
$$;

create function public.dispatch_housekeeping(
  p_unit     uuid,
  p_assignee uuid,
  p_note     text default null
) returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  raise exception 'dispatch_housekeeping is not implemented yet' using errcode = '0A000';
end;
$$;

create function public.list_dispatchable_staff(p_property uuid)
returns table (user_id uuid, full_name text)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  raise exception 'list_dispatchable_staff is not implemented yet' using errcode = '0A000';
end;
$$;

revoke execute on function public.room_status_board(uuid) from public, anon;
revoke execute on function public.set_room_status(uuid, public.room_state, text) from public, anon;
revoke execute on function public.dispatch_housekeeping(uuid, uuid, text) from public, anon;
revoke execute on function public.list_dispatchable_staff(uuid) from public, anon;
grant execute on function public.room_status_board(uuid) to authenticated;
grant execute on function public.set_room_status(uuid, public.room_state, text) to authenticated;
grant execute on function public.dispatch_housekeeping(uuid, uuid, text) to authenticated;
grant execute on function public.list_dispatchable_staff(uuid) to authenticated;
```

- [ ] **Step 5: Add the four functions to the definer allow-list**

In `supabase/tests/37_tenancy_isolation_test.sql`, replace:

```sql
        'platform_resorts','set_resort_status','create_resort',
```

with:

```sql
        'platform_resorts','set_resort_status','create_resort',
        -- 0047: room status. Each asserts the caller's role at the resort
        -- of the unit (or the resort) it is given.
        'room_status_board','set_room_status','dispatch_housekeeping',
        'list_dispatchable_staff',
```

- [ ] **Step 6: Run the database tests to verify they pass**

Run: `supabase db reset && supabase test db supabase/tests/39_room_status_test.sql supabase/tests/37_tenancy_isolation_test.sql`
Expected: PASS. 39 reports 14/14 and 37 reports 72/72.

- [ ] **Step 7: Write the failing Dart model and provider tests**

Create `test/data/room_status_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/data/models/room_status.dart';
import 'package:pasala/data/models/staff_task.dart';
import 'package:pasala/data/models/unit.dart';

void main() {
  group('RoomBoardEntry.fromJson', () {
    test('parses a full room_status_board row', () {
      final entry = RoomBoardEntry.fromJson(const {
        'unit_id': 'u1',
        'name': 'Cottage 1',
        'booking_mode': 'nightly',
        'effective_status': 'occupied',
        'state': 'dirty',
        'reason': null,
        'occupied_reservation_id': 'r1',
        'guest_first_name': 'Gita',
        'arriving_today': false,
        'housekeeping_task_id': 't1',
        'housekeeper_name': 'Hari Housekeeper',
        'housekeeping_status': 'in_progress',
        'housekeeping_dispatched_at': '2026-09-25T04:30:00+00:00',
        'overdue': true,
      });

      expect(entry.unitId, 'u1');
      expect(entry.name, 'Cottage 1');
      expect(entry.bookingMode, BookingMode.nightly);
      expect(entry.status, RoomStatus.occupied);
      expect(entry.state, RoomState.dirty);
      expect(entry.occupiedReservationId, 'r1');
      expect(entry.guestFirstName, 'Gita');
      expect(entry.arrivingToday, isFalse);
      expect(entry.housekeepingTaskId, 't1');
      expect(entry.housekeeperName, 'Hari Housekeeper');
      expect(entry.housekeepingStatus, TaskStatus.inProgress);
      expect(entry.housekeepingDispatchedAt, DateTime.utc(2026, 9, 25, 4, 30));
      expect(entry.overdue, isTrue);
      expect(entry.hasOpenHousekeeping, isTrue);
    });

    test('parses a ready room with nothing going on', () {
      final entry = RoomBoardEntry.fromJson(const {
        'unit_id': 'u2',
        'name': 'Day Hut',
        'booking_mode': 'slot',
        'effective_status': 'available',
        'state': 'ready',
        'reason': null,
        'occupied_reservation_id': null,
        'guest_first_name': null,
        'arriving_today': true,
        'housekeeping_task_id': null,
        'housekeeper_name': null,
        'housekeeping_status': null,
        'housekeeping_dispatched_at': null,
        'overdue': false,
      });

      expect(entry.status, RoomStatus.available);
      expect(entry.state, RoomState.ready);
      expect(entry.isDayUse, isTrue);
      expect(entry.arrivingToday, isTrue);
      expect(entry.hasOpenHousekeeping, isFalse);
      expect(entry.housekeepingStatus, isNull);
      expect(entry.housekeepingDispatchedAt, isNull);
    });

    test('an out-of-order room keeps its reason', () {
      final entry = RoomBoardEntry.fromJson(const {
        'unit_id': 'u4',
        'name': 'Cottage 4',
        'booking_mode': 'both',
        'effective_status': 'maintenance',
        'state': 'out_of_order',
        'reason': 'AC broken',
        'arriving_today': false,
        'overdue': false,
      });

      expect(entry.status, RoomStatus.maintenance);
      expect(entry.state, RoomState.outOfOrder);
      expect(entry.reason, 'AC broken');
      expect(entry.isDayUse, isFalse);
    });

    test('an unknown effective_status is rejected, not defaulted', () {
      expect(() => roomStatusFromDb('haunted'), throwsArgumentError);
    });
  });

  group('RoomState <-> db', () {
    test('round-trips every value', () {
      for (final state in RoomState.values) {
        expect(roomStateFromDb(roomStateToDb(state)), state);
      }
    });

    test('outOfOrder is out_of_order in the database', () {
      expect(roomStateToDb(RoomState.outOfOrder), 'out_of_order');
    });
  });

  test('every status has its own label and icon', () {
    expect(RoomStatus.values.map((s) => s.label).toList(),
        ['Available', 'Occupied', 'Cleaning', 'Maintenance']);
    expect(RoomStatus.values.map((s) => s.icon).toSet(), hasLength(4));
    expect(RoomStatus.values.map((s) => s.color).toSet(), hasLength(4));
  });

  test('minutesSinceDispatch counts whole minutes, null without a task', () {
    final dispatched = DateTime.utc(2026, 9, 25, 10);
    final entry = RoomBoardEntry(
      unitId: 'u1',
      name: 'Cottage 1',
      bookingMode: BookingMode.nightly,
      status: RoomStatus.cleaning,
      state: RoomState.dirty,
      housekeepingTaskId: 't1',
      housekeepingDispatchedAt: dispatched,
    );
    expect(entry.minutesSinceDispatch(dispatched.add(const Duration(minutes: 25, seconds: 40))), 25);

    const idle = RoomBoardEntry(
      unitId: 'u2',
      name: 'Cottage 2',
      bookingMode: BookingMode.nightly,
      status: RoomStatus.available,
      state: RoomState.ready,
    );
    expect(idle.minutesSinceDispatch(dispatched), isNull);
  });

  group('DispatchableStaff', () {
    test('parses a list_dispatchable_staff row', () {
      final s = DispatchableStaff.fromJson(const {'user_id': 's1', 'full_name': 'Hari Housekeeper'});
      expect(s.userId, 's1');
      expect(s.displayName, 'Hari Housekeeper');
    });

    test('a member without a name still gets a label', () {
      const s = DispatchableStaff(userId: 's2', fullName: '  ');
      expect(s.displayName, 'Unnamed staff member');
    });
  });
}
```

Create `test/data/room_board_provider_test.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/data/models/room_status.dart';
import 'package:pasala/data/repositories/room_status_repository.dart';

import '../support/fake_room_board_source.dart';

void main() {
  test('roomBoardProvider reads the board of the resort it is keyed by',
      () async {
    final source = FakeRoomBoardSource()..entries = [boardEntry(unitId: 'u1')];
    final container = ProviderContainer(
        overrides: [roomBoardSourceProvider.overrideWithValue(source)]);
    addTearDown(container.dispose);
    final sub = container.listen(roomBoardProvider('p1'), (_, _) {});
    addTearDown(sub.close);

    final rows = await container.read(roomBoardProvider('p1').future);

    expect(rows.single.unitId, 'u1');
    expect(source.boardCalls, ['p1']);
  });

  test('dispatchableStaffProvider asks for the roster of the resort it is '
      'keyed by', () async {
    final source = FakeRoomBoardSource()
      ..staff = [const DispatchableStaff(userId: 's1', fullName: 'Hari Housekeeper')];
    final container = ProviderContainer(
        overrides: [roomBoardSourceProvider.overrideWithValue(source)]);
    addTearDown(container.dispose);
    final sub = container.listen(dispatchableStaffProvider('p1'), (_, _) {});
    addTearDown(sub.close);

    final staff = await container.read(dispatchableStaffProvider('p1').future);

    expect(staff.single.userId, 's1');
    expect(source.staffCalls, ['p1']);
  });
}
```

- [ ] **Step 8: Run them to verify they fail**

Run: `flutter test test/data/room_status_test.dart test/data/room_board_provider_test.dart`
Expected: FAIL to compile with "Target of URI doesn't exist: 'package:pasala/data/models/room_status.dart'".

- [ ] **Step 9: Write the model**

Create `lib/data/models/room_status.dart`:

```dart
import 'package:flutter/material.dart';

import 'staff_task.dart';
import 'unit.dart';

/// What a room tile shows. Derived server-side by `room_status_board`
/// (0047_room_status.sql), in this order: a checked-in reservation makes a
/// room [occupied]; otherwise its stored [RoomState] decides -- `out_of_order`
/// is [maintenance], `dirty` is [cleaning], `ready` (or no stored row) is
/// [available]. Never stored and never sent back.
enum RoomStatus { available, occupied, cleaning, maintenance }

/// Unknown text is rejected rather than defaulted -- a silent fallback
/// would hide a server/app mismatch.
RoomStatus roomStatusFromDb(String raw) => switch (raw) {
      'available' => RoomStatus.available,
      'occupied' => RoomStatus.occupied,
      'cleaning' => RoomStatus.cleaning,
      'maintenance' => RoomStatus.maintenance,
      _ => throw ArgumentError('Unknown room status: $raw'),
    };

/// Label, icon and colour for a [RoomStatus]. The icon and the label always
/// travel with the colour: a status is never told by colour alone.
extension RoomStatusDisplay on RoomStatus {
  String get label => switch (this) {
        RoomStatus.available => 'Available',
        RoomStatus.occupied => 'Occupied',
        RoomStatus.cleaning => 'Cleaning',
        RoomStatus.maintenance => 'Maintenance',
      };

  IconData get icon => switch (this) {
        RoomStatus.available => Icons.check_circle_outline,
        RoomStatus.occupied => Icons.person_outline,
        RoomStatus.cleaning => Icons.cleaning_services_outlined,
        RoomStatus.maintenance => Icons.build_outlined,
      };

  Color get color => switch (this) {
        RoomStatus.available => const Color(0xFF2E7D32),
        RoomStatus.occupied => const Color(0xFF1565C0),
        RoomStatus.cleaning => const Color(0xFFB26A00),
        RoomStatus.maintenance => const Color(0xFFC62828),
      };
}

/// The housekeeping state a person sets (`unit_room_status.state`). A unit
/// with no stored row is [ready].
enum RoomState { ready, dirty, outOfOrder }

RoomState roomStateFromDb(String raw) => switch (raw) {
      'ready' => RoomState.ready,
      'dirty' => RoomState.dirty,
      'out_of_order' => RoomState.outOfOrder,
      _ => throw ArgumentError('Unknown room state: $raw'),
    };

/// Inverse of [roomStateFromDb] -- the Postgres `room_state` label.
String roomStateToDb(RoomState state) => switch (state) {
      RoomState.ready => 'ready',
      RoomState.dirty => 'dirty',
      RoomState.outOfOrder => 'out_of_order',
    };

/// One row of `room_status_board(p_property)`: one active unit of the
/// resort, with its derived [status], its stored [state] (so an occupied
/// room can still carry a needs-cleaning or out-of-order badge), and its
/// open housekeeping task, if any.
class RoomBoardEntry {
  const RoomBoardEntry({
    required this.unitId,
    required this.name,
    required this.bookingMode,
    required this.status,
    required this.state,
    this.reason,
    this.occupiedReservationId,
    this.guestFirstName,
    this.arrivingToday = false,
    this.housekeepingTaskId,
    this.housekeeperName,
    this.housekeepingStatus,
    this.housekeepingDispatchedAt,
    this.overdue = false,
  });

  factory RoomBoardEntry.fromJson(Map<String, dynamic> json) => RoomBoardEntry(
        unitId: json['unit_id'] as String,
        name: json['name'] as String,
        bookingMode: BookingMode.values.byName(json['booking_mode'] as String),
        status: roomStatusFromDb(json['effective_status'] as String),
        state: roomStateFromDb(json['state'] as String),
        reason: json['reason'] as String?,
        occupiedReservationId: json['occupied_reservation_id'] as String?,
        guestFirstName: json['guest_first_name'] as String?,
        arrivingToday: json['arriving_today'] as bool? ?? false,
        housekeepingTaskId: json['housekeeping_task_id'] as String?,
        housekeeperName: json['housekeeper_name'] as String?,
        housekeepingStatus: json['housekeeping_status'] == null
            ? null
            : taskStatusFromDb(json['housekeeping_status'] as String),
        housekeepingDispatchedAt: json['housekeeping_dispatched_at'] == null
            ? null
            : DateTime.parse(json['housekeeping_dispatched_at'] as String)
                .toUtc(),
        overdue: json['overdue'] as bool? ?? false,
      );

  final String unitId;
  final String name;
  final BookingMode bookingMode;
  final RoomStatus status;
  final RoomState state;

  /// Why the room is out of order; null unless [state] is
  /// [RoomState.outOfOrder].
  final String? reason;
  final String? occupiedReservationId;
  final String? guestFirstName;

  /// A confirmed booking starts today (Asia/Kolkata).
  final bool arrivingToday;
  final String? housekeepingTaskId;
  final String? housekeeperName;
  final TaskStatus? housekeepingStatus;

  /// When housekeeping was sent (the task's `created_at`).
  final DateTime? housekeepingDispatchedAt;

  /// The open housekeeping task is older than the resort's SLA.
  final bool overdue;

  /// Slot-only units are day-use rooms.
  bool get isDayUse => bookingMode == BookingMode.slot;

  bool get hasOpenHousekeeping => housekeepingTaskId != null;

  /// Whole minutes since housekeeping was sent, or null with no open task.
  int? minutesSinceDispatch(DateTime now) => housekeepingDispatchedAt == null
      ? null
      : now.difference(housekeepingDispatchedAt!).inMinutes;
}

/// One row of `list_dispatchable_staff(p_property)`: a `staff` member of
/// the resort who can be sent to clean a room.
class DispatchableStaff {
  const DispatchableStaff({required this.userId, this.fullName});

  factory DispatchableStaff.fromJson(Map<String, dynamic> json) =>
      DispatchableStaff(
        userId: json['user_id'] as String,
        fullName: json['full_name'] as String?,
      );

  final String userId;
  final String? fullName;

  String get displayName {
    final name = fullName?.trim() ?? '';
    return name.isEmpty ? 'Unnamed staff member' : name;
  }
}
```

- [ ] **Step 10: Write the repository, seam and providers**

Create `lib/data/repositories/room_status_repository.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors.dart';
import '../../core/supabase_client.dart';
import '../models/room_status.dart';

/// The slice of [RoomStatusRepository] the room grid, the admin dashboard,
/// reception check-in and Assigned Work need. Tests override
/// [roomBoardSourceProvider] with `FakeRoomBoardSource`
/// (test/support/fake_room_board_source.dart) instead of a real client.
abstract class RoomBoardSource {
  Future<List<RoomBoardEntry>> board(String propertyId);
  Future<void> setStatus(String unitId, RoomState state, {String? reason});

  /// Returns the new housekeeping task's id.
  Future<String> dispatch(String unitId, String assigneeId, {String? note});
  Future<List<DispatchableStaff>> dispatchableStaff(String propertyId);
}

/// Backs the room status grid through the four functions in
/// 0047_room_status.sql. Every one checks the caller's role at the unit's
/// (or given) resort server-side, so this repository checks nothing
/// itself; refusals arrive as P0020/P0022/P0030/P0031 through
/// [mapPostgrestError].
class RoomStatusRepository implements RoomBoardSource {
  RoomStatusRepository(this._db);
  final SupabaseClient _db;

  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } catch (e) {
      throw mapPostgrestError(e);
    }
  }

  @override
  Future<List<RoomBoardEntry>> board(String propertyId) => _guard(() async {
        final rows = await _db.rpc('room_status_board', params: {
          'p_property': propertyId,
        }) as List<dynamic>;
        return rows
            .map((e) => RoomBoardEntry.fromJson(e as Map<String, dynamic>))
            .toList();
      });

  @override
  Future<void> setStatus(String unitId, RoomState state, {String? reason}) =>
      _guard(() async {
        await _db.rpc('set_room_status', params: {
          'p_unit': unitId,
          'p_state': roomStateToDb(state),
          'p_reason': reason,
        });
      });

  @override
  Future<String> dispatch(String unitId, String assigneeId, {String? note}) =>
      _guard(() async {
        final id = await _db.rpc('dispatch_housekeeping', params: {
          'p_unit': unitId,
          'p_assignee': assigneeId,
          'p_note': note,
        });
        return id as String;
      });

  @override
  Future<List<DispatchableStaff>> dispatchableStaff(String propertyId) =>
      _guard(() async {
        final rows = await _db.rpc('list_dispatchable_staff', params: {
          'p_property': propertyId,
        }) as List<dynamic>;
        return rows
            .map((e) => DispatchableStaff.fromJson(e as Map<String, dynamic>))
            .toList();
      });
}

final roomStatusRepositoryProvider = Provider<RoomStatusRepository>(
  (ref) => RoomStatusRepository(ref.watch(supabaseProvider)),
);

/// The [RoomBoardSource] seam every screen calls through.
final roomBoardSourceProvider = Provider<RoomBoardSource>(
  (ref) => ref.watch(roomStatusRepositoryProvider),
);

/// The room board of one resort, keyed by property id so switching resort
/// never shows another resort's rooms. `autoDispose` (like
/// `checkedInProvider`): the grid refetches every time it is opened,
/// whatever path led there, and screens invalidate it after their own
/// writes and after check-in/out.
final roomBoardProvider =
    FutureProvider.autoDispose.family<List<RoomBoardEntry>, String>(
  (ref, propertyId) => ref.watch(roomBoardSourceProvider).board(propertyId),
);

/// The resort's `staff` members, for the Send housekeeping picker.
final dispatchableStaffProvider =
    FutureProvider.autoDispose.family<List<DispatchableStaff>, String>(
  (ref, propertyId) =>
      ref.watch(roomBoardSourceProvider).dispatchableStaff(propertyId),
);
```

- [ ] **Step 11: Write the test fake**

Create `test/support/fake_room_board_source.dart`:

```dart
import 'package:pasala/data/models/room_status.dart';
import 'package:pasala/data/models/staff_task.dart';
import 'package:pasala/data/models/unit.dart';
import 'package:pasala/data/repositories/room_status_repository.dart';

/// In-memory [RoomBoardSource]. Set [entries]/[staff] for what the server
/// would return, an `...Error` to make that call throw, and read the call
/// logs to assert what a screen asked for.
class FakeRoomBoardSource implements RoomBoardSource {
  List<RoomBoardEntry> entries = [];
  List<DispatchableStaff> staff = [];
  Object? boardError;
  Object? setStatusError;
  Object? dispatchError;
  Object? staffError;

  final List<String> boardCalls = [];
  final List<(String, RoomState, String?)> setStatusCalls = [];
  final List<(String, String, String?)> dispatchCalls = [];
  final List<String> staffCalls = [];

  @override
  Future<List<RoomBoardEntry>> board(String propertyId) async {
    boardCalls.add(propertyId);
    if (boardError != null) throw boardError!;
    return entries;
  }

  @override
  Future<void> setStatus(String unitId, RoomState state, {String? reason}) async {
    setStatusCalls.add((unitId, state, reason));
    if (setStatusError != null) throw setStatusError!;
  }

  @override
  Future<String> dispatch(String unitId, String assigneeId, {String? note}) async {
    dispatchCalls.add((unitId, assigneeId, note));
    if (dispatchError != null) throw dispatchError!;
    return 'task-new';
  }

  @override
  Future<List<DispatchableStaff>> dispatchableStaff(String propertyId) async {
    staffCalls.add(propertyId);
    if (staffError != null) throw staffError!;
    return staff;
  }
}

/// A board row with defaults for a plain, ready, available room; override
/// only what a test is about.
RoomBoardEntry boardEntry({
  String unitId = 'u1',
  String name = 'Cottage 1',
  BookingMode bookingMode = BookingMode.nightly,
  RoomStatus status = RoomStatus.available,
  RoomState state = RoomState.ready,
  String? reason,
  String? occupiedReservationId,
  String? guestFirstName,
  bool arrivingToday = false,
  String? housekeepingTaskId,
  String? housekeeperName,
  TaskStatus? housekeepingStatus,
  DateTime? housekeepingDispatchedAt,
  bool overdue = false,
}) =>
    RoomBoardEntry(
      unitId: unitId,
      name: name,
      bookingMode: bookingMode,
      status: status,
      state: state,
      reason: reason,
      occupiedReservationId: occupiedReservationId,
      guestFirstName: guestFirstName,
      arrivingToday: arrivingToday,
      housekeepingTaskId: housekeepingTaskId,
      housekeeperName: housekeeperName,
      housekeepingStatus: housekeepingStatus,
      housekeepingDispatchedAt: housekeepingDispatchedAt,
      overdue: overdue,
    );
```

- [ ] **Step 12: Run the Dart tests to verify they pass**

Run: `flutter test test/data/room_status_test.dart test/data/room_board_provider_test.dart && flutter analyze`
Expected: all tests PASS. The analyzer shows no issues beyond the Step 1 baseline.

- [ ] **Step 13: Commit**

```bash
git add supabase/migrations/0047_room_status.sql supabase/tests/39_room_status_test.sql \
  supabase/tests/37_tenancy_isolation_test.sql lib/data/models/room_status.dart \
  lib/data/repositories/room_status_repository.dart test/support/fake_room_board_source.dart \
  test/data/room_status_test.dart test/data/room_board_provider_test.dart
git commit -m "feat(rooms): fix the room status contract (schema, function signatures, Dart API)"
```

---

## Phase 1: Database track (Tasks 2 → 3 → 4, sequential)

### Task 2: `room_status_board` and `set_room_status`

**Track:** DB. **Depends on:** Task 1.

**Files:**
- Modify: `supabase/migrations/0047_room_status.sql` (replace two stubs)
- Test: `supabase/tests/39_room_status_test.sql` (append a section)

**Interfaces:**
- Consumes: the Task 1 signatures, `public.assert_resort_role(uuid, boolean, variadic resort_role[])`, and the fixtures in 39.
- Produces: working `room_status_board` and `set_room_status` with the behaviour listed in the contract. `set_room_status(…, 'ready')` closes the unit's open housekeeping tasks by setting `tasks.status = 'done'`. Task 3 relies on this.
- State left for Task 3:
  - Cottage 1 is occupied, with a `dirty` row.
  - Day Hut has a `ready` row and one done task titled "Clean Day Hut".
  - Old Barn has a `dirty` row.
  - Cottage 4 has a `ready` row.
  - R's SLA is 120.
  - The file ends with `reset role` and empty claims.

- [ ] **Step 1: Write the failing tests**

In `supabase/tests/39_room_status_test.sql`, change `select plan(14);` to `select plan(38);`. Then insert this section immediately before the final `select * from finish();`:

```sql
-- === Task 2: room_status_board and set_room_status =========================

set local role authenticated;
set local request.jwt.claims to '{"sub":"e0000000-0000-0000-0000-000000000003","role":"authenticated"}';
select is((select array_agg(name order by name)
             from public.room_status_board('eeeeeeee-0000-4000-8000-000000000001')),
  array['Cottage 1','Cottage 4','Day Hut'],
  'the board lists every active unit and no inactive one');
select is((select effective_status || '|' || guest_first_name || '|'
                  || (occupied_reservation_id = 'eeeeeeee-0000-4000-8000-000000000031')::text
             from public.room_status_board('eeeeeeee-0000-4000-8000-000000000001')
            where unit_id = 'eeeeeeee-0000-4000-8000-000000000011'),
  'occupied|Gita|true', 'a checked-in unit is Occupied, with the guest''s first name only');
select is((select booking_mode::text
             from public.room_status_board('eeeeeeee-0000-4000-8000-000000000001')
            where unit_id = 'eeeeeeee-0000-4000-8000-000000000012'),
  'slot', 'a slot-only unit comes back as slot (Day use)');
select is((select effective_status || '|' || arriving_today::text
             from public.room_status_board('eeeeeeee-0000-4000-8000-000000000001')
            where unit_id = 'eeeeeeee-0000-4000-8000-000000000014'),
  'available|true', 'a unit with a confirmed arrival today is Available and flagged');
select is((select state::text || '|' || overdue::text || '|' || coalesce(housekeeping_task_id::text, '-')
             from public.room_status_board('eeeeeeee-0000-4000-8000-000000000001')
            where unit_id = 'eeeeeeee-0000-4000-8000-000000000012'),
  'ready|false|-', 'a unit with no stored row is ready, with no housekeeping');

-- Role matrix.
set local request.jwt.claims to '{"sub":"e0000000-0000-0000-0000-000000000005","role":"authenticated"}';
select is((select count(*)::int from public.room_status_board('eeeeeeee-0000-4000-8000-000000000001')),
  3, 'an accountant reads the board');
select throws_ok($$select public.set_room_status('eeeeeeee-0000-4000-8000-000000000014', 'dirty')$$,
  'P0020', null, 'an accountant cannot change a room');
set local request.jwt.claims to '{"sub":"e0000000-0000-0000-0000-000000000008","role":"authenticated"}';
select throws_ok($$select * from public.room_status_board('eeeeeeee-0000-4000-8000-000000000001')$$,
  'P0020', null, 'a guest cannot read the board');
select throws_ok($$select public.set_room_status('eeeeeeee-0000-4000-8000-000000000014', 'dirty')$$,
  'P0020', null, 'a guest cannot change a room');
set local request.jwt.claims to '{"sub":"e0000000-0000-0000-0000-000000000007","role":"authenticated"}';
select throws_ok($$select * from public.room_status_board('eeeeeeee-0000-4000-8000-000000000001')$$,
  'P0020', null, 'staff of another resort cannot read the board');
select throws_ok($$select public.set_room_status('eeeeeeee-0000-4000-8000-000000000014', 'dirty')$$,
  'P0020', null, 'staff of another resort cannot change a room');
set local role anon;
select throws_ok($$select * from public.room_status_board('eeeeeeee-0000-4000-8000-000000000001')$$,
  '42501', null, 'anon cannot call the board');

-- Setting states.
set local role authenticated;
set local request.jwt.claims to '{"sub":"e0000000-0000-0000-0000-000000000003","role":"authenticated"}';
select throws_ok($$select public.set_room_status('eeeeeeee-0000-4000-8000-000000000014', 'out_of_order')$$,
  'P0030', 'reason_required', 'Maintenance without a reason is refused');
select throws_ok($$select public.set_room_status('eeeeeeee-0000-4000-8000-000000000014', 'out_of_order', '   ')$$,
  'P0030', 'reason_required', 'a blank reason is refused');
select lives_ok($$select public.set_room_status('eeeeeeee-0000-4000-8000-000000000014', 'out_of_order', ' AC broken ')$$,
  'staff marks a room out of order with a reason');
select is((select effective_status || '|' || reason
             from public.room_status_board('eeeeeeee-0000-4000-8000-000000000001')
            where unit_id = 'eeeeeeee-0000-4000-8000-000000000014'),
  'maintenance|AC broken', 'the board shows Maintenance with the trimmed reason');
set local request.jwt.claims to '{"sub":"e0000000-0000-0000-0000-000000000002","role":"authenticated"}';
select lives_ok($$select public.set_room_status('eeeeeeee-0000-4000-8000-000000000011', 'dirty')$$,
  'admin marks an occupied room as needing cleaning');
select is((select effective_status || '|' || state::text
             from public.room_status_board('eeeeeeee-0000-4000-8000-000000000001')
            where unit_id = 'eeeeeeee-0000-4000-8000-000000000011'),
  'occupied|dirty', 'an occupied room stays Occupied and keeps its needs-cleaning state');
set local request.jwt.claims to '{"sub":"e0000000-0000-0000-0000-000000000001","role":"authenticated"}';
select lives_ok($$select public.set_room_status('eeeeeeee-0000-4000-8000-000000000014', 'ready')$$,
  'owner returns a room to Available');
select is((select effective_status || '|' || coalesce(reason, '-')
             from public.room_status_board('eeeeeeee-0000-4000-8000-000000000001')
            where unit_id = 'eeeeeeee-0000-4000-8000-000000000014'),
  'available|-', 'Available clears the maintenance reason');

-- Housekeeping columns and the SLA, with a task inserted directly
-- (dispatching arrives in Task 3). `reset role` keeps the claims; clear them.
reset role;
set local request.jwt.claims to '';
insert into public.tasks (property_id, assignee_id, title, kind, unit_id, created_by, created_at) values
  ('eeeeeeee-0000-4000-8000-000000000001','e0000000-0000-0000-0000-000000000004','Clean Day Hut',
   'housekeeping','eeeeeeee-0000-4000-8000-000000000012','e0000000-0000-0000-0000-000000000003',
   now() - interval '61 minutes');
set local role authenticated;
set local request.jwt.claims to '{"sub":"e0000000-0000-0000-0000-000000000003","role":"authenticated"}';
select is((select housekeeper_name || '|' || housekeeping_status::text || '|' || overdue::text
             from public.room_status_board('eeeeeeee-0000-4000-8000-000000000001')
            where unit_id = 'eeeeeeee-0000-4000-8000-000000000012'),
  'Hari Housekeeper|todo|true', 'an open task older than the 60-minute SLA is Overdue, with its housekeeper');
reset role;
set local request.jwt.claims to '';
update public.properties set housekeeping_sla_minutes = 120
 where id = 'eeeeeeee-0000-4000-8000-000000000001';
set local role authenticated;
set local request.jwt.claims to '{"sub":"e0000000-0000-0000-0000-000000000003","role":"authenticated"}';
select is((select overdue
             from public.room_status_board('eeeeeeee-0000-4000-8000-000000000001')
            where unit_id = 'eeeeeeee-0000-4000-8000-000000000012'),
  false, 'the same task is on time under a 120-minute SLA');
set local request.jwt.claims to '{"sub":"e0000000-0000-0000-0000-000000000001","role":"authenticated"}';
select lives_ok($$select public.set_room_status('eeeeeeee-0000-4000-8000-000000000012', 'ready')$$,
  'owner marks the day hut Available');
reset role;
set local request.jwt.claims to '';
select is((select status::text from public.tasks
            where unit_id = 'eeeeeeee-0000-4000-8000-000000000012'),
  'done', 'marking a room Available closes its open housekeeping task');
```

- [ ] **Step 2: Run it to verify it fails**

Run: `supabase test db supabase/tests/39_room_status_test.sql`
Expected: FAIL from test 15 onwards, with `room_status_board is not implemented yet` (SQLSTATE 0A000).

- [ ] **Step 3: Replace the `room_status_board` stub**

In `0047_room_status.sql`, replace the whole block from `create function public.room_status_board(p_property uuid)` through its closing `$$;` with:

```sql
-- One row per active unit of the resort, for the room grid. Staff+ of the
-- resort (reads are allowed while it is suspended). effective_status:
-- occupied (a checked-in reservation) > maintenance (out_of_order) >
-- cleaning (dirty) > available. The stored state comes back too, so an
-- occupied room can still carry a needs-cleaning or out-of-order badge.
create function public.room_status_board(p_property uuid)
returns table (
  unit_id                    uuid,
  name                       text,
  booking_mode               public.booking_mode,
  effective_status           text,
  state                      public.room_state,
  reason                     text,
  occupied_reservation_id    uuid,
  guest_first_name           text,
  arriving_today             boolean,
  housekeeping_task_id       uuid,
  housekeeper_name           text,
  housekeeping_status        public.task_status,
  housekeeping_dispatched_at timestamptz,
  overdue                    boolean
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
#variable_conflict use_column
declare
  v_today date := (now() at time zone 'Asia/Kolkata')::date;
  v_sla   int;
begin
  perform public.assert_resort_role(p_property, false, 'owner','admin','staff','accountant');

  select p.housekeeping_sla_minutes into v_sla
    from public.properties p where p.id = p_property;

  return query
    select u.id,
           u.name,
           u.booking_mode,
           case
             when occ.id is not null then 'occupied'
             when s.state = 'out_of_order' then 'maintenance'
             when s.state = 'dirty' then 'cleaning'
             else 'available'
           end,
           coalesce(s.state, 'ready'::public.room_state),
           s.reason,
           occ.id,
           nullif(split_part(btrim(g.full_name), ' ', 1), ''),
           exists (select 1 from public.reservations a
                    where a.unit_id = u.id
                      and a.kind <> 'block'
                      and a.status = 'confirmed'
                      and (lower(a.period) at time zone 'Asia/Kolkata')::date = v_today),
           hk.id,
           hp.full_name,
           hk.status,
           hk.created_at,
           coalesce(hk.created_at < now() - make_interval(mins => v_sla), false)
      from public.units u
      left join public.unit_room_status s on s.unit_id = u.id
      left join lateral (
        select r.id, r.customer_id
          from public.reservations r
         where r.unit_id = u.id and r.status = 'checked_in'
         order by r.checked_in_at desc nulls last
         limit 1
      ) occ on true
      left join public.profiles g on g.id = occ.customer_id
      left join lateral (
        select t.id, t.assignee_id, t.status, t.created_at
          from public.tasks t
         where t.unit_id = u.id and t.kind = 'housekeeping' and t.status <> 'done'
         order by t.created_at desc
         limit 1
      ) hk on true
      left join public.profiles hp on hp.id = hk.assignee_id
     where u.property_id = p_property and u.is_active
     order by u.name, u.id;
end;
$$;
```

- [ ] **Step 4: Replace the `set_room_status` stub**

Replace the whole block from `create function public.set_room_status(` through its closing `$$;` with:

```sql
-- Owner/admin/staff of the unit's resort set its housekeeping state.
-- Maintenance needs a reason (P0030). Available also closes the unit's
-- open housekeeping task -- the room is clean, so the job is done.
create function public.set_room_status(
  p_unit   uuid,
  p_state  public.room_state,
  p_reason text default null
) returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_property uuid;
  v_reason   text := nullif(btrim(p_reason), '');
begin
  select u.property_id into v_property from public.units u where u.id = p_unit;
  if not found then
    raise exception 'unit not found' using errcode = 'P0002';
  end if;

  perform public.assert_resort_role(v_property, true, 'owner','admin','staff');

  if p_state is null then
    raise exception 'state is required' using errcode = 'P0005';
  end if;
  if p_state = 'out_of_order' and v_reason is null then
    raise exception using errcode = 'P0030', message = 'reason_required';
  end if;

  insert into public.unit_room_status as s
    (unit_id, property_id, state, reason, updated_by, updated_at)
  values (p_unit, v_property, p_state,
          case when p_state = 'out_of_order' then v_reason end,
          auth.uid(), now())
  on conflict (unit_id) do update
    set state      = excluded.state,
        reason     = excluded.reason,
        updated_by = excluded.updated_by,
        updated_at = excluded.updated_at;

  if p_state = 'ready' then
    update public.tasks
       set status = 'done'
     where unit_id = p_unit and kind = 'housekeeping' and status <> 'done';
  end if;
end;
$$;
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `supabase db reset && supabase test db supabase/tests/39_room_status_test.sql supabase/tests/37_tenancy_isolation_test.sql`
Expected: PASS, with 39 at 38/38 and 37 at 72/72.

- [ ] **Step 6: Commit**

```bash
git add supabase/migrations/0047_room_status.sql supabase/tests/39_room_status_test.sql
git commit -m "feat(db): derive the room board and let staff set a room's state"
```

---

### Task 3: Dispatching housekeeping, and the housekeeping task rules

**Track:** DB. **Depends on:** Task 2.

**Files:**
- Modify: `supabase/migrations/0047_room_status.sql` (task rules, `tasks_enforce_write`, done trigger, two stubs)
- Modify: `supabase/tests/37_tenancy_isolation_test.sql` (allow-list: `tasks_housekeeping_done`)
- Test: `supabase/tests/39_room_status_test.sql` (append a section)

**Interfaces:**
- Consumes: `set_room_status` from Task 2 (its task-closing update now goes through the new room-writer branch). `public.fill_property_id`. The latest `tasks_enforce_write` from `0045`.
- Produces:
  - Working `dispatch_housekeeping` and `list_dispatchable_staff`.
  - The trigger `tasks_housekeeping_done`: a housekeeping task entering `done` makes a `dirty` room `ready`.
  - `tasks.started_at` is set on the first move to `in_progress`.
  - The constraint `tasks_unit_only_for_housekeeping`, the unique index `tasks_one_open_housekeeping_per_unit` and the trigger `tasks_fill_property` (P0021).
- State left for Task 4:
  - Day Hut is deleted.
  - Cottage 4 is `dirty`, with one open housekeeping task assigned to Hari.
  - Cottage 1 is still occupied and `dirty`.
  - The file ends with `reset role` and empty claims.

- [ ] **Step 1: Write the failing tests**

In `supabase/tests/39_room_status_test.sql`, change `select plan(38);` to `select plan(69);`. Then insert this section immediately before the final `select * from finish();`:

```sql
-- === Task 3: dispatching housekeeping and the task rules ===================

set local role authenticated;
set local request.jwt.claims to '{"sub":"e0000000-0000-0000-0000-000000000003","role":"authenticated"}';
select is((select array_agg(full_name order by full_name)
             from public.list_dispatchable_staff('eeeeeeee-0000-4000-8000-000000000001')),
  array['Hari Housekeeper','Indu Incharge'], 'only the resort''s staff members can be dispatched');
set local request.jwt.claims to '{"sub":"e0000000-0000-0000-0000-000000000005","role":"authenticated"}';
select throws_ok($$select * from public.list_dispatchable_staff('eeeeeeee-0000-4000-8000-000000000001')$$,
  'P0020', null, 'an accountant cannot list housekeepers');
select throws_ok($$select public.dispatch_housekeeping('eeeeeeee-0000-4000-8000-000000000014',
  'e0000000-0000-0000-0000-000000000004')$$, 'P0020', null, 'an accountant cannot dispatch');
set local request.jwt.claims to '{"sub":"e0000000-0000-0000-0000-000000000007","role":"authenticated"}';
select throws_ok($$select public.dispatch_housekeeping('eeeeeeee-0000-4000-8000-000000000014',
  'e0000000-0000-0000-0000-000000000007')$$, 'P0020', null, 'staff of another resort cannot dispatch');
set local request.jwt.claims to '{"sub":"e0000000-0000-0000-0000-000000000003","role":"authenticated"}';
select throws_ok($$select public.dispatch_housekeeping('eeeeeeee-0000-4000-8000-000000000014',
  'e0000000-0000-0000-0000-000000000007')$$, 'P0020', null, 'an assignee from another resort is refused');
select throws_ok($$select public.dispatch_housekeeping('eeeeeeee-0000-4000-8000-000000000014',
  'e0000000-0000-0000-0000-000000000005')$$, 'P0020', null, 'a member who is not staff cannot be dispatched');
select throws_ok($$select public.dispatch_housekeeping('eeeeeeee-0000-4000-8000-000000000014',
  'e0000000-0000-0000-0000-000000000009')$$, 'P0020', null, 'someone with no membership cannot be dispatched');
select lives_ok($$select public.dispatch_housekeeping('eeeeeeee-0000-4000-8000-000000000014',
  'e0000000-0000-0000-0000-000000000004', ' Deep clean ')$$, 'the Incharge dispatches housekeeping');
select is((select effective_status || '|' || housekeeper_name || '|' || housekeeping_status::text || '|' || overdue::text
             from public.room_status_board('eeeeeeee-0000-4000-8000-000000000001')
            where unit_id = 'eeeeeeee-0000-4000-8000-000000000014'),
  'cleaning|Hari Housekeeper|todo|false', 'the room shows Cleaning with the housekeeper and a fresh task');
select throws_ok($$select public.dispatch_housekeeping('eeeeeeee-0000-4000-8000-000000000014',
  'e0000000-0000-0000-0000-000000000004')$$, 'P0031', 'already_dispatched',
  'a second dispatch while one is open is refused');
reset role;
set local request.jwt.claims to '';
select is((select title || '|' || description || '|' || kind::text || '|' || assignee_id::text
                  || '|' || property_id::text || '|' || created_by::text
             from public.tasks where unit_id = 'eeeeeeee-0000-4000-8000-000000000014'),
  'Clean Cottage 4|Deep clean|housekeeping|e0000000-0000-0000-0000-000000000004|'
  || 'eeeeeeee-0000-4000-8000-000000000001|e0000000-0000-0000-0000-000000000003',
  'the task names the room, carries the note and records who dispatched it');

-- The housekeeper's side: Assigned Work, status only.
set local role authenticated;
set local request.jwt.claims to '{"sub":"e0000000-0000-0000-0000-000000000004","role":"authenticated"}';
select is((select count(*)::int from public.tasks where kind = 'housekeeping' and status <> 'done'),
  1, 'the housekeeper sees the open task');
select throws_ok($$update public.tasks set unit_id = 'eeeeeeee-0000-4000-8000-000000000011'
  where unit_id = 'eeeeeeee-0000-4000-8000-000000000014'$$,
  '42501', null, 'the assignee cannot move the task to another room');
select throws_ok($$update public.tasks set kind = 'general'
  where unit_id = 'eeeeeeee-0000-4000-8000-000000000014'$$,
  '42501', null, 'the assignee cannot change the task kind');
select throws_ok($$update public.tasks set started_at = now() - interval '1 day'
  where unit_id = 'eeeeeeee-0000-4000-8000-000000000014'$$,
  '42501', null, 'the assignee cannot backdate the start');
update public.tasks set status = 'in_progress'
 where unit_id = 'eeeeeeee-0000-4000-8000-000000000014';
select isnt((select started_at from public.tasks
              where unit_id = 'eeeeeeee-0000-4000-8000-000000000014'),
  null, 'moving to In Progress records the start time');
update public.tasks set status = 'done'
 where unit_id = 'eeeeeeee-0000-4000-8000-000000000014';
select is((select effective_status || '|' || coalesce(housekeeping_task_id::text, '-')
             from public.room_status_board('eeeeeeee-0000-4000-8000-000000000001')
            where unit_id = 'eeeeeeee-0000-4000-8000-000000000014'),
  'available|-', 'a finished housekeeping task returns the room to Available');

-- Review Focus 1: housekeeping never clears Maintenance.
set local request.jwt.claims to '{"sub":"e0000000-0000-0000-0000-000000000003","role":"authenticated"}';
select lives_ok($$select public.set_room_status('eeeeeeee-0000-4000-8000-000000000012', 'out_of_order', 'Roof leak')$$,
  'the Incharge marks the day hut out of order');
select lives_ok($$select public.dispatch_housekeeping('eeeeeeee-0000-4000-8000-000000000012',
  'e0000000-0000-0000-0000-000000000004')$$, 'housekeeping can still be sent to an out-of-order room');
select is((select state::text
             from public.room_status_board('eeeeeeee-0000-4000-8000-000000000001')
            where unit_id = 'eeeeeeee-0000-4000-8000-000000000012'),
  'out_of_order', 'dispatching does not clear the maintenance flag');
set local request.jwt.claims to '{"sub":"e0000000-0000-0000-0000-000000000004","role":"authenticated"}';
update public.tasks set status = 'done'
 where unit_id = 'eeeeeeee-0000-4000-8000-000000000012' and status <> 'done';
select is((select effective_status
             from public.room_status_board('eeeeeeee-0000-4000-8000-000000000001')
            where unit_id = 'eeeeeeee-0000-4000-8000-000000000012'),
  'maintenance', 'finishing housekeeping leaves an out-of-order room in Maintenance');

-- Review Focus 3: a Staff / Incharge who is not the assignee.
set local request.jwt.claims to '{"sub":"e0000000-0000-0000-0000-000000000003","role":"authenticated"}';
select lives_ok($$select public.dispatch_housekeeping('eeeeeeee-0000-4000-8000-000000000014',
  'e0000000-0000-0000-0000-000000000004')$$, 'a room can be dispatched again once its last task is done');
select lives_ok($$select public.set_room_status('eeeeeeee-0000-4000-8000-000000000014', 'ready')$$,
  'the Incharge (not the assignee) marks the room Available');
reset role;
set local request.jwt.claims to '';
select is((select count(*)::int from public.tasks
            where unit_id = 'eeeeeeee-0000-4000-8000-000000000014' and status <> 'done'),
  0, 'marking Available closes the open task even for a non-admin caller');
set local role authenticated;
set local request.jwt.claims to '{"sub":"e0000000-0000-0000-0000-000000000003","role":"authenticated"}';
select lives_ok($$select public.dispatch_housekeeping('eeeeeeee-0000-4000-8000-000000000014',
  'e0000000-0000-0000-0000-000000000004')$$, 'housekeeping is sent to Cottage 4 again');
select is(pg_temp.rows_affected($$update public.tasks set status = 'done'
  where unit_id = 'eeeeeeee-0000-4000-8000-000000000014' and status <> 'done'$$),
  0, 'a staff member who is not the assignee still cannot update the task directly');

-- Task rules, as the superuser with no authenticated caller.
reset role;
set local request.jwt.claims to '';
-- Review Focus 2: the index behind P0031 when two dispatches race.
select throws_ok($$insert into public.tasks (property_id, assignee_id, title, kind, unit_id, created_by)
  values ('eeeeeeee-0000-4000-8000-000000000001','e0000000-0000-0000-0000-000000000003',
          'Clean Cottage 4','housekeeping','eeeeeeee-0000-4000-8000-000000000014',
          'e0000000-0000-0000-0000-000000000002')$$,
  '23505', null, 'a unit can have only one open housekeeping task');
select throws_ok($$insert into public.tasks (property_id, assignee_id, title, kind, unit_id, created_by)
  values ('eeeeeeee-0000-4000-8000-000000000002','e0000000-0000-0000-0000-000000000007',
          'Clean','housekeeping','eeeeeeee-0000-4000-8000-000000000012',
          'e0000000-0000-0000-0000-000000000006')$$,
  'P0021', null, 'a task cannot point at another resort''s room');
select throws_ok($$insert into public.tasks (property_id, assignee_id, title, kind, unit_id, created_by)
  values ('eeeeeeee-0000-4000-8000-000000000001','e0000000-0000-0000-0000-000000000004',
          'Fix tap','general','eeeeeeee-0000-4000-8000-000000000012',
          'e0000000-0000-0000-0000-000000000003')$$,
  '23514', null, 'a general task cannot carry a room');

-- Review Focus 5: deleting a unit with housekeeping history.
set local role authenticated;
set local request.jwt.claims to '{"sub":"e0000000-0000-0000-0000-000000000002","role":"authenticated"}';
select lives_ok($$delete from public.units where id = 'eeeeeeee-0000-4000-8000-000000000012'$$,
  'an admin can still delete a unit with housekeeping history');
reset role;
set local request.jwt.claims to '';
select is((select count(*)::int from public.tasks
            where title = 'Clean Day Hut' and unit_id is null),
  2, 'its housekeeping tasks are kept, unlinked from the room');
```

- [ ] **Step 2: Run it to verify it fails**

Run: `supabase test db supabase/tests/39_room_status_test.sql`
Expected: FAIL from test 39 onwards, with `list_dispatchable_staff is not implemented yet` (0A000).

- [ ] **Step 3: Add the task rules**

In `0047_room_status.sql`, immediately after the line `create index tasks_unit_idx on public.tasks (unit_id) where unit_id is not null;`, insert:

```sql

-- A room belongs only on a housekeeping task. Not the spec's strict
-- `(kind = 'housekeeping') = (unit_id is not null)`: with
-- `on delete set null` above, that would refuse every delete of a unit
-- with housekeeping history. dispatch_housekeeping always sets unit_id.
alter table public.tasks
  add constraint tasks_unit_only_for_housekeeping
    check (unit_id is null or kind = 'housekeeping');

-- One open housekeeping task per unit. dispatch_housekeeping checks first
-- and raises P0031; this index settles two dispatches that race past that
-- check.
create unique index tasks_one_open_housekeeping_per_unit
  on public.tasks (unit_id)
  where kind = 'housekeeping' and status <> 'done';

-- The unit's resort must be the task's resort (P0021), as for every other
-- unit-linked table (0043). A general task (no unit) passes straight
-- through.
create trigger tasks_fill_property
  before insert or update on public.tasks
  for each row execute function public.fill_property_id('units', 'unit_id');

-- tasks_enforce_write, copied from 0045 with three changes:
--  * started_at is set the first time a task moves to in_progress;
--  * the assignee's status-only path also may not change kind, unit_id,
--    started_at or completed_at;
--  * on a housekeeping task, an owner/admin/staff member of its resort
--    may change the status only. RLS (tasks_update) still admits only
--    admins and the assignee to a direct update, so this "room writer"
--    path is reachable only through set_room_status.
create or replace function public.tasks_enforce_write()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_admin boolean := public.has_resort_role(old.property_id, true, 'owner','admin');
  v_room_writer boolean := old.kind = 'housekeeping'
    and public.has_resort_role(old.property_id, true, 'owner','admin','staff');
begin
  if TG_OP = 'DELETE' then
    if not v_admin then
      raise sqlstate '42501' using
        message = 'permission denied for table tasks',
        hint = 'only an administrator can delete a task';
    end if;
    return old;
  end if;

  if v_admin and public.has_resort_role(new.property_id, true, 'owner','admin') then
    new.updated_at := clock_timestamp();
    if new.status = 'in_progress' and old.started_at is null then
      new.started_at := clock_timestamp();
    end if;
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
      or new.created_at is distinct from old.created_at
      or new.property_id is distinct from old.property_id
      or new.kind is distinct from old.kind
      or new.unit_id is distinct from old.unit_id
      or new.started_at is distinct from old.started_at
      or new.completed_at is distinct from old.completed_at then
    raise sqlstate '42501' using
      message = 'permission denied for table tasks',
      hint = 'only an administrator can edit a task''s details';
  end if;

  if old.assignee_id <> auth.uid() and not v_room_writer then
    raise sqlstate '42501' using
      message = 'permission denied for table tasks',
      hint = 'you can only update the status of your own tasks';
  end if;

  new.updated_at := clock_timestamp();
  if new.status = 'in_progress' and old.started_at is null then
    new.started_at := clock_timestamp();
  end if;
  if new.status = 'done' and old.completed_at is null then
    new.completed_at := clock_timestamp();
  end if;
  return new;
end;
$$;

-- A finished housekeeping task makes a dirty room ready. An out-of-order
-- room stays in Maintenance: only a person clears that.
create function public.tasks_housekeeping_done()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  update public.unit_room_status
     set state = 'ready', reason = null, updated_by = auth.uid(), updated_at = now()
   where unit_id = new.unit_id
     and state = 'dirty';
  return null;
end;
$$;

create trigger tasks_housekeeping_done
  after update of status on public.tasks
  for each row
  when (new.kind = 'housekeeping' and new.unit_id is not null
        and new.status = 'done' and old.status is distinct from 'done')
  execute function public.tasks_housekeeping_done();
```

- [ ] **Step 4: Replace the `dispatch_housekeeping` stub**

Replace the whole block from `create function public.dispatch_housekeeping(` through its closing `$$;` with:

```sql
-- Owner/admin/staff of the unit's resort send one `staff` member of that
-- same resort (else P0020) to clean the unit. Refused with P0031 while an
-- open housekeeping task exists. Marks the room dirty unless it is out of
-- order -- sending housekeeping never clears Maintenance. Returns the new
-- task's id.
create function public.dispatch_housekeeping(
  p_unit     uuid,
  p_assignee uuid,
  p_note     text default null
) returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_unit public.units;
  v_task uuid;
begin
  select * into v_unit from public.units where id = p_unit;
  if not found then
    raise exception 'unit not found' using errcode = 'P0002';
  end if;

  perform public.assert_resort_role(v_unit.property_id, true, 'owner','admin','staff');

  if not exists (select 1 from public.resort_members m
                  where m.property_id = v_unit.property_id
                    and m.user_id = p_assignee
                    and m.role = 'staff') then
    raise exception using errcode = 'P0020', message = 'not_a_member';
  end if;

  if exists (select 1 from public.tasks t
              where t.unit_id = p_unit and t.kind = 'housekeeping' and t.status <> 'done') then
    raise exception using errcode = 'P0031', message = 'already_dispatched';
  end if;

  begin
    insert into public.tasks
      (property_id, assignee_id, title, description, kind, unit_id, created_by)
    values
      (v_unit.property_id, p_assignee, 'Clean ' || v_unit.name,
       coalesce(btrim(p_note), ''), 'housekeeping', p_unit, auth.uid())
    returning id into v_task;
  exception when unique_violation then
    -- Lost a race with another dispatch (tasks_one_open_housekeeping_per_unit).
    raise exception using errcode = 'P0031', message = 'already_dispatched';
  end;

  insert into public.unit_room_status as s
    (unit_id, property_id, state, reason, updated_by, updated_at)
  values (p_unit, v_unit.property_id, 'dirty', null, auth.uid(), now())
  on conflict (unit_id) do update
    set state      = 'dirty',
        reason     = null,
        updated_by = excluded.updated_by,
        updated_at = excluded.updated_at
    where s.state <> 'out_of_order';

  return v_task;
end;
$$;
```

- [ ] **Step 5: Replace the `list_dispatchable_staff` stub**

Replace the whole block from `create function public.list_dispatchable_staff(p_property uuid)` through its closing `$$;` with:

```sql
-- The resort's `staff` members, for the Send housekeeping picker. Needed
-- because staff cannot read the roster (resort_members_read is owner/admin
-- or self); returns only the id and name.
create function public.list_dispatchable_staff(p_property uuid)
returns table (user_id uuid, full_name text)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
#variable_conflict use_column
begin
  perform public.assert_resort_role(p_property, false, 'owner','admin','staff');

  return query
    select m.user_id, p.full_name
      from public.resort_members m
      join public.profiles p on p.id = m.user_id
     where m.property_id = p_property and m.role = 'staff'
     order by p.full_name nulls last, m.user_id;
end;
$$;
```

- [ ] **Step 6: Allow-list the trigger function**

In `supabase/tests/37_tenancy_isolation_test.sql`, replace:

```sql
        'room_status_board','set_room_status','dispatch_housekeeping',
        'list_dispatchable_staff',
```

with:

```sql
        'room_status_board','set_room_status','dispatch_housekeeping',
        'list_dispatchable_staff',
        -- 0047: tasks_housekeeping_done is a trigger function (not callable
        -- as an RPC); it fires only on a task update that tasks_update RLS
        -- and tasks_enforce_write already allowed.
        'tasks_housekeeping_done',
```

- [ ] **Step 7: Run the whole database suite to verify it passes**

Run: `supabase db reset && supabase test db`
Expected: 39 at 69/69 and 37 at 72/72. `20_tasks_test.sql` and `25_staff_performance_test.sql` still pass, because the `tasks_enforce_write` changes keep their behaviour. The only failures are the baseline failures recorded in Task 1 Step 1.

- [ ] **Step 8: Commit**

```bash
git add supabase/migrations/0047_room_status.sql supabase/tests/39_room_status_test.sql \
  supabase/tests/37_tenancy_isolation_test.sql
git commit -m "feat(db): dispatch housekeeping as a unit-linked task that readies the room when done"
```

---

### Task 4: Checkout marks the room, cross-resort isolation, suspended resorts

**Track:** DB. **Depends on:** Task 3.

**Files:**
- Modify: `supabase/migrations/0047_room_status.sql` (append `checkout_booking`)
- Modify: `supabase/tests/37_tenancy_isolation_test.sql` (plan 72 → 77, room rows)
- Test: `supabase/tests/39_room_status_test.sql` (append a section)

**Interfaces:**
- Consumes: the latest `checkout_booking(p_reservation_id uuid, p_payment_ref text, p_amount numeric)` from `0045_resort_functions.sql`, and the Task 2/3 functions.
- Produces: `checkout_booking` upserts the unit's row to `dirty` unless it is `out_of_order`. The signature and return type are unchanged.

- [ ] **Step 1: Write the failing tests in 39**

In `supabase/tests/39_room_status_test.sql`, change `select plan(69);` to `select plan(81);`. Then insert this section immediately before the final `select * from finish();`:

```sql
-- === Task 4: checkout, suspended and archived resorts =====================

set local role authenticated;
set local request.jwt.claims to '{"sub":"e0000000-0000-0000-0000-000000000001","role":"authenticated"}';
select lives_ok($$select public.set_room_status('eeeeeeee-0000-4000-8000-000000000011', 'ready')$$,
  'owner marks the occupied room ready before checkout');
set local request.jwt.claims to '{"sub":"e0000000-0000-0000-0000-000000000003","role":"authenticated"}';
select lives_ok($$select public.checkout_booking('eeeeeeee-0000-4000-8000-000000000031', null, null)$$,
  'reception checks the guest out');
select is((select effective_status || '|' || state::text
             from public.room_status_board('eeeeeeee-0000-4000-8000-000000000001')
            where unit_id = 'eeeeeeee-0000-4000-8000-000000000011'),
  'cleaning|dirty', 'checkout marks the room Cleaning');

-- Review Focus 1: checkout never clears Maintenance.
select lives_ok($$select public.check_in_booking('eeeeeeee-0000-4000-8000-000000000032')$$,
  'the arriving guest checks in to Cottage 4');
select lives_ok($$select public.set_room_status('eeeeeeee-0000-4000-8000-000000000014', 'out_of_order', 'Geyser')$$,
  'the Incharge marks the occupied room out of order');
select lives_ok($$select public.checkout_booking('eeeeeeee-0000-4000-8000-000000000032', null, null)$$,
  'the guest checks out');
select is((select effective_status || '|' || reason
             from public.room_status_board('eeeeeeee-0000-4000-8000-000000000001')
            where unit_id = 'eeeeeeee-0000-4000-8000-000000000014'),
  'maintenance|Geyser', 'checkout leaves an out-of-order room in Maintenance');

-- Suspended: reads work, writes P0022. `reset role` keeps the claims;
-- clear them so the status change runs with no authenticated caller.
reset role;
set local request.jwt.claims to '';
update public.properties set status = 'suspended'
 where id = 'eeeeeeee-0000-4000-8000-000000000001';
set local role authenticated;
set local request.jwt.claims to '{"sub":"e0000000-0000-0000-0000-000000000003","role":"authenticated"}';
select is((select count(*)::int from public.room_status_board('eeeeeeee-0000-4000-8000-000000000001')),
  2, 'staff of a suspended resort still read the board');
select throws_ok($$select public.set_room_status('eeeeeeee-0000-4000-8000-000000000011', 'ready')$$,
  'P0022', null, 'no room changes at a suspended resort');
select throws_ok($$select public.dispatch_housekeeping('eeeeeeee-0000-4000-8000-000000000011',
  'e0000000-0000-0000-0000-000000000004')$$, 'P0022', null, 'no dispatching at a suspended resort');
select is((select count(*)::int from public.list_dispatchable_staff('eeeeeeee-0000-4000-8000-000000000001')),
  2, 'the housekeeper list still reads at a suspended resort');

-- Archived: closed.
reset role;
set local request.jwt.claims to '';
update public.properties set status = 'archived'
 where id = 'eeeeeeee-0000-4000-8000-000000000001';
set local role authenticated;
set local request.jwt.claims to '{"sub":"e0000000-0000-0000-0000-000000000003","role":"authenticated"}';
select throws_ok($$select * from public.room_status_board('eeeeeeee-0000-4000-8000-000000000001')$$,
  'P0020', null, 'an archived resort''s board is closed to its staff');
reset role;
set local request.jwt.claims to '';
```

- [ ] **Step 2: Write the failing isolation rows in 37**

In `supabase/tests/37_tenancy_isolation_test.sql`, change `select plan(72);` to `select plan(77);`. Then replace:

```sql
-- Catalog guards: fail the suite when a future table, policy or security
-- definer function is added without resort scoping.
```

with:

```sql
-- Room status (0047): nothing at A reaches B's rooms. Fixture as the
-- superuser with no authenticated caller.
reset role;
set local request.jwt.claims to '';
insert into public.unit_room_status (unit_id, state)
  values ('bbbbbbbb-0000-4000-8000-000000000011', 'dirty');
set local role authenticated;
set local request.jwt.claims to '{"sub":"a0000000-0000-0000-0000-00000000000c","role":"authenticated"}';
select throws_ok($$select * from public.room_status_board('bbbbbbbb-0000-4000-8000-000000000001')$$,
  'P0020', null, 'A staff cannot read B''s room board');
select throws_ok($$select public.set_room_status('bbbbbbbb-0000-4000-8000-000000000011', 'ready')$$,
  'P0020', null, 'A staff cannot change a B room');
select throws_ok($$select public.dispatch_housekeeping('bbbbbbbb-0000-4000-8000-000000000011',
  'a0000000-0000-0000-0000-00000000000c')$$, 'P0020', null, 'A staff cannot send housekeeping to a B room');
select throws_ok($$select * from public.list_dispatchable_staff('bbbbbbbb-0000-4000-8000-000000000001')$$,
  'P0020', null, 'A staff cannot list B''s housekeepers');
set local request.jwt.claims to '{"sub":"a0000000-0000-0000-0000-00000000000a","role":"authenticated"}';
select is((select count(*)::int from public.unit_room_status), 0,
  'A owner reads none of B''s room rows');

-- Catalog guards: fail the suite when a future table, policy or security
-- definer function is added without resort scoping.
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `supabase test db supabase/tests/39_room_status_test.sql supabase/tests/37_tenancy_isolation_test.sql`
Expected: 39 fails test 72 (`checkout marks the room Cleaning`: got `available|ready`, expected `cleaning|dirty`), because checkout does not touch the room yet. The five new tests in 37 already pass: the room functions refuse other resorts since Tasks 2–3, and these rows pin that behaviour.

- [ ] **Step 4: Append the new `checkout_booking`**

Append to the end of `0047_room_status.sql`:

```sql

-- ---------------------------------------------------------------------
-- checkout_booking, copied from 0045 with one step added: after checkout
-- the unit needs cleaning, unless it is out of order (checkout never
-- clears Maintenance). The idempotent early return for an
-- already-checked-out booking does not touch the room again.
create or replace function public.checkout_booking(
  p_reservation_id uuid,
  p_payment_ref    text,
  p_amount         numeric
) returns public.reservations
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid     uuid := auth.uid();
  v_row     public.reservations;
  v_charges jsonb;
  v_balance numeric(12,2);
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode = 'P0008';
  end if;

  select * into v_row from public.reservations
  where id = p_reservation_id for update;

  if not found then
    raise exception 'reservation not found' using errcode = 'P0002';
  end if;

  if v_row.customer_id is distinct from v_uid then
    perform public.assert_resort_role(v_row.property_id, true, 'owner','admin','staff','accountant');
  end if;

  if v_row.status = 'checked_out' then
    return v_row;   -- idempotent: a retried checkout must not double-charge
  end if;

  if v_row.status <> 'checked_in' then
    raise exception 'reservation is %', v_row.status using errcode = 'P0009';
  end if;

  v_charges := public.current_charges(p_reservation_id);
  v_balance := (v_charges ->> 'balance')::numeric;

  if v_balance > 0 and (p_amount is null or p_amount is distinct from v_balance) then
    raise exception 'payment amount % does not match balance due %',
      p_amount, v_balance
      using errcode = 'P0009';
  end if;

  if v_balance > 0 then
    insert into public.payments
      (reservation_id, amount, kind, status, gateway, gateway_ref)
    values (p_reservation_id, v_balance, 'balance', 'succeeded', 'mock', p_payment_ref);
  end if;

  update public.reservations
     set status = 'checked_out', checked_out_at = clock_timestamp()
   where id = p_reservation_id
  returning * into v_row;

  -- 0047: the room needs cleaning now.
  insert into public.unit_room_status as s
    (unit_id, property_id, state, reason, updated_by, updated_at)
  values (v_row.unit_id, v_row.property_id, 'dirty', null, v_uid, now())
  on conflict (unit_id) do update
    set state      = 'dirty',
        reason     = null,
        updated_by = excluded.updated_by,
        updated_at = excluded.updated_at
    where s.state <> 'out_of_order';

  return v_row;
end;
$$;
```

- [ ] **Step 5: Run the whole database suite to verify it passes**

Run: `supabase db reset && supabase test db`
Expected: 39 at 81/81 and 37 at 77/77. `33_stay_checkout_test.sql` and `35_customer_checkout_test.sql` still pass. The only failures are the baseline failures recorded in Task 1 Step 1.

- [ ] **Step 6: Commit**

```bash
git add supabase/migrations/0047_room_status.sql supabase/tests/39_room_status_test.sql \
  supabase/tests/37_tenancy_isolation_test.sql
git commit -m "feat(db): checkout marks the room for cleaning; room status isolation and suspension tests"
```

---

## Phase 2: App track (after Task 1; 5 → 6, 5 → 7; 8, 9, 10 independent)

### Task 5: The room grid screen

**Track:** App. **Depends on:** Task 1.

**Files:**
- Create: `lib/features/staff/room_tile.dart`
- Create: `lib/features/staff/room_status_screen.dart`
- Test: `test/features/staff/room_status_screen_test.dart`

**Interfaces:**
- Consumes: `RoomBoardEntry`, `RoomStatus` / `RoomStatusDisplay`, `RoomState`, `roomBoardProvider`, `roomBoardSourceProvider`, `currentResortProvider`, `FakeRoomBoardSource`, `boardEntry` (Task 1). `AsyncView`, `EmptyState`.
- Produces:
  - `class RoomStatusScreen extends ConsumerStatefulWidget { const RoomStatusScreen({super.key, this.clock = DateTime.now}); final DateTime Function() clock; }`
  - `Map<RoomStatus, int> roomStatusCounts(List<RoomBoardEntry>)` and `int roomGridColumns(double width)`.
  - In `room_tile.dart`: `StatusPill({icon, label, color})`, `RoomStatusChip({status})`, `String housekeepingLine(RoomBoardEntry, DateTime now)` and `RoomTile({entry, now, onTap})`. Tile key: `room-tile-<unitId>`. Filter chip keys: `room-filter-<status.name>`.
  - Task 6 edits `_RoomStatusScreenState.build` to pass an `onTap` to `_RoomGrid`.

- [ ] **Step 1: Write the failing tests**

Create `test/features/staff/room_status_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pasala/core/current_resort.dart';
import 'package:pasala/core/errors.dart';
import 'package:pasala/data/models/resort_membership.dart';
import 'package:pasala/data/models/room_status.dart';
import 'package:pasala/data/models/unit.dart';
import 'package:pasala/data/repositories/room_status_repository.dart';
import 'package:pasala/features/staff/room_status_screen.dart';
import 'package:pasala/features/staff/room_tile.dart';

import '../../support/fake_room_board_source.dart';

class _FixedResort extends CurrentResort {
  _FixedResort(this._value);
  final ResortMembership _value;
  @override
  ResortMembership? build() => _value;
}

const _staffM =
    ResortMembership(propertyId: 'p1', resortName: 'Pasala', role: ResortRole.staff);
const _accountantM = ResortMembership(
    propertyId: 'p1', resortName: 'Pasala', role: ResortRole.accountant);

final _now = DateTime.utc(2026, 9, 25, 10);

final _rooms = [
  boardEntry(unitId: 'u1', name: 'Cottage 1'),
  boardEntry(
    unitId: 'u2',
    name: 'Cottage 2',
    status: RoomStatus.occupied,
    occupiedReservationId: 'r1',
    guestFirstName: 'Gita',
  ),
  boardEntry(
    unitId: 'u3',
    name: 'Day Hut',
    bookingMode: BookingMode.slot,
    status: RoomStatus.cleaning,
    state: RoomState.dirty,
    housekeepingTaskId: 't1',
    housekeeperName: 'Hari Housekeeper',
    housekeepingDispatchedAt: _now.subtract(const Duration(minutes: 75)),
    overdue: true,
  ),
  boardEntry(
    unitId: 'u4',
    name: 'Cottage 4',
    status: RoomStatus.maintenance,
    state: RoomState.outOfOrder,
    reason: 'AC broken',
    arrivingToday: true,
  ),
];

Future<void> _pump(
  WidgetTester tester,
  FakeRoomBoardSource source, {
  ResortMembership resort = _staffM,
}) async {
  final router = GoRouter(
    initialLocation: '/staff/rooms',
    routes: [
      GoRoute(
          path: '/staff/rooms',
          builder: (_, _) => RoomStatusScreen(clock: () => _now)),
      GoRoute(
          path: '/admin/check-in',
          builder: (_, _) => const Text('CHECK-IN SCREEN')),
      GoRoute(
          path: '/admin/check-out',
          builder: (_, _) => const Text('CHECK-OUT SCREEN')),
    ],
  );
  await tester.pumpWidget(ProviderScope(
    overrides: [
      roomBoardSourceProvider.overrideWithValue(source),
      currentResortProvider.overrideWith(() => _FixedResort(resort)),
    ],
    child: MaterialApp.router(routerConfig: router),
  ));
  await tester.pumpAndSettle();
}

Finder _inTile(String unitId, Finder matching) =>
    find.descendant(of: find.byKey(Key('room-tile-$unitId')), matching: matching);

void main() {
  group('pure helpers', () {
    test('roomGridColumns: two on a phone, four to six on wide screens', () {
      expect(roomGridColumns(375), 2);
      expect(roomGridColumns(599), 2);
      expect(roomGridColumns(700), 4);
      expect(roomGridColumns(1000), 5);
      expect(roomGridColumns(1600), 6);
    });

    test('roomStatusCounts counts every status, zero included', () {
      expect(roomStatusCounts([boardEntry()]), {
        RoomStatus.available: 1,
        RoomStatus.occupied: 0,
        RoomStatus.cleaning: 0,
        RoomStatus.maintenance: 0,
      });
    });

    test('housekeepingLine uses the first name and whole minutes', () {
      expect(housekeepingLine(_rooms[2], _now), 'Housekeeping: Hari, 75 min');
      expect(
        housekeepingLine(
          boardEntry(housekeepingTaskId: 't9', housekeepingDispatchedAt: _now),
          _now,
        ),
        'Housekeeping: unassigned, 0 min',
      );
    });
  });

  testWidgets('asks for the current resort\'s board', (tester) async {
    final source = FakeRoomBoardSource()..entries = _rooms;
    await _pump(tester, source);

    expect(source.boardCalls, isNotEmpty);
    expect(source.boardCalls, everyElement('p1'));
  });

  testWidgets('every tile shows its status as an icon and a label',
      (tester) async {
    await _pump(tester, FakeRoomBoardSource()..entries = _rooms);

    for (final (unitId, status) in [
      ('u1', RoomStatus.available),
      ('u2', RoomStatus.occupied),
      ('u3', RoomStatus.cleaning),
      ('u4', RoomStatus.maintenance),
    ]) {
      expect(_inTile(unitId, find.text(status.label)), findsOneWidget,
          reason: unitId);
      expect(_inTile(unitId, find.byIcon(status.icon)), findsOneWidget,
          reason: unitId);
    }
  });

  testWidgets('tiles carry guest, arrival, day use, reason and housekeeping',
      (tester) async {
    await _pump(tester, FakeRoomBoardSource()..entries = _rooms);

    expect(_inTile('u2', find.text('Guest: Gita')), findsOneWidget);
    expect(_inTile('u3', find.text('Day use')), findsOneWidget);
    expect(_inTile('u3', find.text('Housekeeping: Hari, 75 min')), findsOneWidget);
    expect(_inTile('u3', find.text('Overdue')), findsOneWidget);
    expect(_inTile('u4', find.text('Arriving today')), findsOneWidget);
    expect(_inTile('u4', find.text('AC broken')), findsOneWidget);
    expect(_inTile('u1', find.text('Overdue')), findsNothing);
  });

  testWidgets('an occupied room with a stored state carries a badge',
      (tester) async {
    await _pump(
      tester,
      FakeRoomBoardSource()
        ..entries = [
          boardEntry(unitId: 'u1', status: RoomStatus.occupied, state: RoomState.dirty),
          boardEntry(
              unitId: 'u2',
              name: 'Cottage 2',
              status: RoomStatus.occupied,
              state: RoomState.outOfOrder,
              reason: 'Leak'),
        ],
    );

    expect(_inTile('u1', find.text('Needs cleaning')), findsOneWidget);
    expect(_inTile('u2', find.text('Out of order')), findsOneWidget);
  });

  testWidgets('summary chips count each status and filter the grid',
      (tester) async {
    await _pump(tester, FakeRoomBoardSource()..entries = _rooms);

    expect(find.text('Available (1)'), findsOneWidget);
    expect(find.text('Occupied (1)'), findsOneWidget);
    expect(find.text('Cleaning (1)'), findsOneWidget);
    expect(find.text('Maintenance (1)'), findsOneWidget);

    await tester.tap(find.byKey(const Key('room-filter-occupied')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('room-tile-u2')), findsOneWidget);
    expect(find.byKey(const Key('room-tile-u1')), findsNothing);

    await tester.tap(find.byKey(const Key('room-filter-occupied')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('room-tile-u1')), findsOneWidget);
  });

  testWidgets('a filter with no rooms says so', (tester) async {
    await _pump(tester, FakeRoomBoardSource()..entries = [boardEntry()]);

    await tester.tap(find.byKey(const Key('room-filter-maintenance')));
    await tester.pumpAndSettle();

    expect(find.text('No Maintenance rooms right now.'), findsOneWidget);
  });

  testWidgets('a resort with no active units shows an empty state',
      (tester) async {
    await _pump(tester, FakeRoomBoardSource());

    expect(find.text('No rooms yet'), findsOneWidget);
  });

  testWidgets('a failed load goes through FailureView', (tester) async {
    await _pump(tester, FakeRoomBoardSource()..boardError = const NetworkFailure());

    expect(find.text('Cannot reach the server. Check your connection.'),
        findsOneWidget);
  });

  testWidgets('pull to refresh fetches the board again', (tester) async {
    final source = FakeRoomBoardSource()..entries = _rooms;
    await _pump(tester, source);
    final before = source.boardCalls.length;

    await tester.fling(find.byType(ListView), const Offset(0, 400), 1000);
    await tester.pumpAndSettle();

    expect(source.boardCalls.length, greaterThan(before));
  });
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `flutter test test/features/staff/room_status_screen_test.dart`
Expected: FAIL to compile with "Target of URI doesn't exist: 'package:pasala/features/staff/room_status_screen.dart'".

- [ ] **Step 3: Write the tile widgets**

Create `lib/features/staff/room_tile.dart`:

```dart
import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../data/models/room_status.dart';

/// An icon and a label in a tinted pill. The label always travels with the
/// colour, so a status is never told by colour alone.
class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: Spacing.sm, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: Spacing.xs),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
          ],
        ),
      );
}

/// The derived [RoomStatus] as a pill.
class RoomStatusChip extends StatelessWidget {
  const RoomStatusChip({super.key, required this.status});
  final RoomStatus status;

  @override
  Widget build(BuildContext context) =>
      StatusPill(icon: status.icon, label: status.label, color: status.color);
}

/// "Housekeeping: Hari, 25 min" -- the housekeeper's first name and the
/// whole minutes since housekeeping was sent.
String housekeepingLine(RoomBoardEntry entry, DateTime now) {
  final fullName = entry.housekeeperName?.trim() ?? '';
  final name = fullName.isEmpty ? 'unassigned' : fullName.split(' ').first;
  return 'Housekeeping: $name, ${entry.minutesSinceDispatch(now) ?? 0} min';
}

/// One room on the grid. [onTap] is null for a read-only viewer.
class RoomTile extends StatelessWidget {
  const RoomTile({super.key, required this.entry, required this.now, this.onTap});

  final RoomBoardEntry entry;
  final DateTime now;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final muted = textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    final occupied = entry.status == RoomStatus.occupied;

    Widget gap(Widget child) => Padding(
          padding: const EdgeInsets.only(top: Spacing.xs),
          child: child,
        );

    return Card(
      key: Key('room-tile-${entry.unitId}'),
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(Spacing.sm + Spacing.xs),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(entry.name,
                  style: textTheme.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              gap(RoomStatusChip(status: entry.status)),
              if (occupied && entry.state == RoomState.dirty)
                gap(StatusPill(
                  icon: RoomStatus.cleaning.icon,
                  label: 'Needs cleaning',
                  color: RoomStatus.cleaning.color,
                )),
              if (occupied && entry.state == RoomState.outOfOrder)
                gap(StatusPill(
                  icon: RoomStatus.maintenance.icon,
                  label: 'Out of order',
                  color: RoomStatus.maintenance.color,
                )),
              if (entry.state == RoomState.outOfOrder && entry.reason != null)
                gap(Text(entry.reason!,
                    style: muted, maxLines: 2, overflow: TextOverflow.ellipsis)),
              if (occupied && entry.guestFirstName != null)
                gap(Text('Guest: ${entry.guestFirstName}', style: muted)),
              if (entry.arrivingToday) gap(Text('Arriving today', style: muted)),
              if (entry.isDayUse) gap(Text('Day use', style: muted)),
              if (entry.hasOpenHousekeeping)
                gap(Text(housekeepingLine(entry, now),
                    style: muted, maxLines: 2, overflow: TextOverflow.ellipsis)),
              if (entry.overdue)
                gap(StatusPill(
                  icon: Icons.warning_amber_outlined,
                  label: 'Overdue',
                  color: scheme.error,
                )),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Write the screen**

Create `lib/features/staff/room_status_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/current_resort.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/empty_state.dart';
import '../../data/models/room_status.dart';
import '../../data/repositories/room_status_repository.dart';
import 'room_tile.dart';

/// How many rooms have each [RoomStatus]. Every status is present (zero
/// when no room has it), so the summary chips never jump around.
Map<RoomStatus, int> roomStatusCounts(List<RoomBoardEntry> entries) => {
      for (final status in RoomStatus.values)
        status: entries.where((e) => e.status == status).length,
    };

/// Grid columns for [width] logical pixels: two on a phone, four to six on
/// wider screens.
int roomGridColumns(double width) =>
    width < 600 ? 2 : (width ~/ 200).clamp(4, 6);

/// `/staff/rooms` -- the room status grid (REQ-06) of the current resort:
/// summary chips that count and filter, then one tile per active unit.
/// Every member of the resort can open it; pull to refresh.
class RoomStatusScreen extends ConsumerStatefulWidget {
  const RoomStatusScreen({super.key, this.clock = DateTime.now});

  /// What "n min" on a housekeeping line is measured against; injectable
  /// so tests do not depend on the wall clock.
  final DateTime Function() clock;

  @override
  ConsumerState<RoomStatusScreen> createState() => _RoomStatusScreenState();
}

class _RoomStatusScreenState extends ConsumerState<RoomStatusScreen> {
  RoomStatus? _filter;

  @override
  Widget build(BuildContext context) {
    final resort = ref.watch(currentResortProvider);
    if (resort == null) {
      // The router only opens /staff/* with a current resort; this covers
      // the moment after sign-out, before the redirect fires.
      return const Scaffold(body: SizedBox.shrink());
    }
    final propertyId = resort.propertyId;
    final boardAsync = ref.watch(roomBoardProvider(propertyId));

    Future<void> refresh() => ref.refresh(roomBoardProvider(propertyId).future);

    return Scaffold(
      appBar: AppBar(title: const Text('Rooms')),
      body: AsyncView(
        value: boardAsync,
        onRetry: () => ref.invalidate(roomBoardProvider(propertyId)),
        empty: () => RefreshIndicator(
          onRefresh: refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: const [
              EmptyState(
                icon: Icons.meeting_room_outlined,
                title: 'No rooms yet',
                message: 'Active units of this resort show up here.',
              ),
            ],
          ),
        ),
        data: (entries) => RefreshIndicator(
          onRefresh: refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(Spacing.md),
            children: [
              _SummaryChips(
                counts: roomStatusCounts(entries),
                selected: _filter,
                onSelected: (status) =>
                    setState(() => _filter = _filter == status ? null : status),
              ),
              const SizedBox(height: Spacing.md),
              _RoomGrid(
                entries: [
                  for (final e in entries)
                    if (_filter == null || e.status == _filter) e,
                ],
                emptyLabel: _filter == null
                    ? ''
                    : 'No ${_filter!.label} rooms right now.',
                now: widget.clock(),
                onTap: null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryChips extends StatelessWidget {
  const _SummaryChips({
    required this.counts,
    required this.selected,
    required this.onSelected,
  });

  final Map<RoomStatus, int> counts;
  final RoomStatus? selected;
  final ValueChanged<RoomStatus> onSelected;

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: Spacing.sm,
        runSpacing: Spacing.sm,
        children: [
          for (final status in RoomStatus.values)
            FilterChip(
              key: Key('room-filter-${status.name}'),
              avatar: Icon(status.icon, size: 18, color: status.color),
              label: Text('${status.label} (${counts[status] ?? 0})'),
              selected: selected == status,
              showCheckmark: false,
              onSelected: (_) => onSelected(status),
            ),
        ],
      );
}

class _RoomGrid extends StatelessWidget {
  const _RoomGrid({
    required this.entries,
    required this.emptyLabel,
    required this.now,
    required this.onTap,
  });

  final List<RoomBoardEntry> entries;
  final String emptyLabel;
  final DateTime now;

  /// Null for a read-only viewer: tiles are not tappable.
  final void Function(RoomBoardEntry entry)? onTap;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: Spacing.lg),
        child: Text(emptyLabel,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium),
      );
    }
    return LayoutBuilder(builder: (context, constraints) {
      final columns = roomGridColumns(constraints.maxWidth);
      final width =
          ((constraints.maxWidth - Spacing.sm * (columns - 1)) / columns)
              .floorToDouble();
      return Wrap(
        spacing: Spacing.sm,
        runSpacing: Spacing.sm,
        children: [
          for (final entry in entries)
            SizedBox(
              width: width,
              child: RoomTile(
                entry: entry,
                now: now,
                onTap: onTap == null ? null : () => onTap!(entry),
              ),
            ),
        ],
      );
    });
  }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `flutter test test/features/staff/room_status_screen_test.dart && flutter analyze`
Expected: all PASS. No new analyzer issues.

- [ ] **Step 6: Commit**

```bash
git add lib/features/staff/room_tile.dart lib/features/staff/room_status_screen.dart \
  test/features/staff/room_status_screen_test.dart
git commit -m "feat(rooms): room status grid with summary chips, filter and refresh"
```

---

### Task 6: The room actions sheet

**Track:** App. **Depends on:** Task 5.

**Files:**
- Create: `lib/features/staff/room_actions_sheet.dart`
- Modify: `lib/features/staff/room_status_screen.dart`
- Modify: `lib/core/errors.dart`
- Test: `test/features/staff/room_status_screen_test.dart` (append), `test/core/errors_test.dart` (append)

**Interfaces:**
- Consumes: `RoomBoardSource.setStatus` / `dispatch`, `dispatchableStaffProvider`, `roomBoardProvider`, `RoomStatusChip` (Task 5), `FailureView.messageFor`.
- Produces:
  - `sealed class RoomAction`, with the subclasses `SetRoomStateAction(RoomState state, {String? reason})`, `DispatchAction(String assigneeId, {String? note})` and `OpenPathAction(String path)`.
  - `Future<RoomAction?> showRoomActionsSheet(BuildContext, {required RoomBoardEntry entry, required String propertyId})`.
  - `MaintenanceReasonDialog`, which returns `String?`, and `DispatchDialog({propertyId, unitName})`, which returns `DispatchAction?`.
  - Keys: `room-action-occupied|available|dirty|maintenance|dispatch`, `room-link-check-in|check-out`, `maintenance-reason`, `maintenance-submit`, `dispatch-assignee`, `dispatch-note`, `dispatch-submit`.
  - In `errors.dart`: `class ReasonRequired extends BookingFailure` (P0030) and `class AlreadyDispatched extends BookingFailure` (P0031).

- [ ] **Step 1: Write the failing tests**

Append to `test/core/errors_test.dart`, inside `main()` after the `P0022` test:

```dart
  test('P0030 maps to ReasonRequired with readable copy', () {
    final failure = map('P0030', 'reason_required');
    expect(failure, isA<ReasonRequired>());
    expect(failure.message, 'Enter a reason to mark a room as Maintenance.');
  });

  test('P0031 maps to AlreadyDispatched with readable copy', () {
    final failure = map('P0031', 'already_dispatched');
    expect(failure, isA<AlreadyDispatched>());
    expect(failure.message, 'Housekeeping is already on its way to this room.');
  });
```

Append these tests inside `main()` of `test/features/staff/room_status_screen_test.dart`:

```dart
  group('room actions', () {
    Future<void> openSheet(WidgetTester tester, String unitId) async {
      await tester.tap(find.byKey(Key('room-tile-$unitId')));
      await tester.pumpAndSettle();
    }

    testWidgets('tapping a tile opens the sheet with every action',
        (tester) async {
      await _pump(tester, FakeRoomBoardSource()..entries = [boardEntry()]);
      await openSheet(tester, 'u1');

      for (final key in [
        'room-action-occupied',
        'room-action-available',
        'room-action-dirty',
        'room-action-maintenance',
        'room-action-dispatch',
        'room-link-check-in',
        'room-link-check-out',
      ]) {
        expect(find.byKey(Key(key)), findsOneWidget, reason: key);
      }
    });

    testWidgets('Needs cleaning sets the room dirty and refetches the board',
        (tester) async {
      final source = FakeRoomBoardSource()..entries = [boardEntry()];
      await _pump(tester, source);
      final before = source.boardCalls.length;
      await openSheet(tester, 'u1');

      await tester.tap(find.byKey(const Key('room-action-dirty')));
      await tester.pumpAndSettle();

      expect(source.setStatusCalls, [('u1', RoomState.dirty, null)]);
      expect(source.boardCalls.length, greaterThan(before));
      expect(find.text('Cottage 1 updated'), findsOneWidget);
    });

    testWidgets('Maintenance asks for a reason and refuses a blank one',
        (tester) async {
      final source = FakeRoomBoardSource()..entries = [boardEntry()];
      await _pump(tester, source);
      await openSheet(tester, 'u1');

      await tester.tap(find.byKey(const Key('room-action-maintenance')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('maintenance-reason')), '   ');
      await tester.tap(find.byKey(const Key('maintenance-submit')));
      await tester.pumpAndSettle();

      expect(find.text('Enter a reason'), findsOneWidget);
      expect(source.setStatusCalls, isEmpty);

      await tester.enterText(
          find.byKey(const Key('maintenance-reason')), 'AC broken');
      await tester.tap(find.byKey(const Key('maintenance-submit')));
      await tester.pumpAndSettle();

      expect(source.setStatusCalls, [('u1', RoomState.outOfOrder, 'AC broken')]);
    });

    testWidgets('Send housekeeping picks a staff member and passes the note',
        (tester) async {
      final source = FakeRoomBoardSource()
        ..entries = [boardEntry()]
        ..staff = const [
          DispatchableStaff(userId: 's1', fullName: 'Hari Housekeeper'),
          DispatchableStaff(userId: 's2', fullName: 'Indu Incharge'),
        ];
      await _pump(tester, source);
      await openSheet(tester, 'u1');

      await tester.tap(find.byKey(const Key('room-action-dispatch')));
      await tester.pumpAndSettle();
      expect(source.staffCalls, ['p1']);

      await tester.tap(find.byKey(const Key('dispatch-assignee')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hari Housekeeper').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('dispatch-note')), 'Fresh towels');
      await tester.tap(find.byKey(const Key('dispatch-submit')));
      await tester.pumpAndSettle();

      expect(source.dispatchCalls, [('u1', 's1', 'Fresh towels')]);
      expect(find.text('Housekeeping sent to Cottage 1'), findsOneWidget);
    });

    testWidgets('Send stays disabled until a housekeeper is picked',
        (tester) async {
      final source = FakeRoomBoardSource()
        ..entries = [boardEntry()]
        ..staff = const [DispatchableStaff(userId: 's1', fullName: 'Hari Housekeeper')];
      await _pump(tester, source);
      await openSheet(tester, 'u1');
      await tester.tap(find.byKey(const Key('room-action-dispatch')));
      await tester.pumpAndSettle();

      expect(
        tester.widget<FilledButton>(find.byKey(const Key('dispatch-submit'))).onPressed,
        isNull,
      );
    });

    testWidgets('with no staff members the dialog explains how to add one',
        (tester) async {
      await _pump(tester, FakeRoomBoardSource()..entries = [boardEntry()]);
      await openSheet(tester, 'u1');
      await tester.tap(find.byKey(const Key('room-action-dispatch')));
      await tester.pumpAndSettle();

      expect(
          find.text('No Staff / Incharge members yet. An owner can add one in Team.'),
          findsOneWidget);
    });

    testWidgets('an open housekeeping task disables Send housekeeping',
        (tester) async {
      await _pump(
        tester,
        FakeRoomBoardSource()
          ..entries = [
            boardEntry(
              status: RoomStatus.cleaning,
              state: RoomState.dirty,
              housekeepingTaskId: 't1',
              housekeeperName: 'Hari Housekeeper',
              housekeepingDispatchedAt: _now,
            ),
          ],
      );
      await openSheet(tester, 'u1');

      expect(
        tester.widget<ListTile>(find.byKey(const Key('room-action-dispatch'))).enabled,
        isFalse,
      );
      expect(find.text('Already sent to Hari Housekeeper'), findsOneWidget);
    });

    testWidgets('a dispatch refused as already sent shows the readable message',
        (tester) async {
      final source = FakeRoomBoardSource()
        ..entries = [boardEntry()]
        ..staff = const [DispatchableStaff(userId: 's1', fullName: 'Hari Housekeeper')]
        ..dispatchError = const AlreadyDispatched();
      await _pump(tester, source);
      await openSheet(tester, 'u1');
      await tester.tap(find.byKey(const Key('room-action-dispatch')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('dispatch-assignee')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hari Housekeeper').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('dispatch-submit')));
      await tester.pumpAndSettle();

      expect(find.text('Housekeeping is already on its way to this room.'),
          findsOneWidget);
    });

    testWidgets('Occupied is shown but not settable; the sheet links to '
        'check-out', (tester) async {
      await _pump(
        tester,
        FakeRoomBoardSource()
          ..entries = [boardEntry(status: RoomStatus.occupied, guestFirstName: 'Gita')],
      );
      await openSheet(tester, 'u1');

      expect(
        tester.widget<ListTile>(find.byKey(const Key('room-action-occupied'))).enabled,
        isFalse,
      );

      await tester.tap(find.byKey(const Key('room-link-check-out')));
      await tester.pumpAndSettle();

      expect(find.text('CHECK-OUT SCREEN'), findsOneWidget);
    });

    testWidgets('an accountant sees the grid but no actions', (tester) async {
      await _pump(tester, FakeRoomBoardSource()..entries = [boardEntry()],
          resort: _accountantM);
      await openSheet(tester, 'u1');

      expect(find.byKey(const Key('room-action-available')), findsNothing);
      expect(find.text('Cottage 1'), findsOneWidget);
    });
  });
```

- [ ] **Step 2: Run them to verify they fail**

Run: `flutter test test/core/errors_test.dart test/features/staff/room_status_screen_test.dart`
Expected: FAIL to compile with "Undefined name 'ReasonRequired'" / "'AlreadyDispatched' isn't a type".

- [ ] **Step 3: Map P0030 and P0031**

In `lib/core/errors.dart`, add these classes immediately before `class InvalidCredentials`:

```dart
/// P0030 -- `set_room_status` refused Maintenance without a reason. The
/// room sheet asks for one first, so this is a backstop.
class ReasonRequired extends BookingFailure {
  const ReasonRequired()
      : super('Enter a reason to mark a room as Maintenance.');
}

/// P0031 -- `dispatch_housekeeping` found an open housekeeping task for the
/// room (someone else sent housekeeping a moment ago).
class AlreadyDispatched extends BookingFailure {
  const AlreadyDispatched()
      : super('Housekeeping is already on its way to this room.');
}
```

In `mapPostgrestError`, replace:

```dart
    'P0023' => InvalidState(message),
```

with:

```dart
    'P0023' => InvalidState(message),
    // P0030/P0031: room status (0047). The server sends bare codes
    // (`reason_required`, `already_dispatched`), so the copy lives here.
    'P0030' => const ReasonRequired(),
    'P0031' => const AlreadyDispatched(),
```

- [ ] **Step 4: Write the sheet and dialogs**

Create `lib/features/staff/room_actions_sheet.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/failure_view.dart';
import '../../data/models/room_status.dart';
import '../../data/repositories/room_status_repository.dart';
import 'room_tile.dart';

/// What the person chose in the room sheet. The sheet only decides; the
/// grid screen carries it out, so every call and its error handling live
/// in one place.
sealed class RoomAction {
  const RoomAction();
}

class SetRoomStateAction extends RoomAction {
  const SetRoomStateAction(this.state, {this.reason});
  final RoomState state;
  final String? reason;
}

class DispatchAction extends RoomAction {
  const DispatchAction(this.assigneeId, {this.note});
  final String assigneeId;
  final String? note;
}

class OpenPathAction extends RoomAction {
  const OpenPathAction(this.path);
  final String path;
}

Future<RoomAction?> showRoomActionsSheet(
  BuildContext context, {
  required RoomBoardEntry entry,
  required String propertyId,
}) =>
    showModalBottomSheet<RoomAction>(
      context: context,
      isScrollControlled: true,
      builder: (_) => RoomActionsSheet(entry: entry, propertyId: propertyId),
    );

/// The actions for one room: its stored state (Available / Needs cleaning /
/// Maintenance), Send housekeeping, and links to check-in and check-out.
/// Occupied is shown for completeness but is set only by check-in/out.
class RoomActionsSheet extends StatelessWidget {
  const RoomActionsSheet({
    super.key,
    required this.entry,
    required this.propertyId,
  });

  final RoomBoardEntry entry;
  final String propertyId;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    Widget? tick(RoomState state) =>
        entry.state == state ? const Icon(Icons.check) : null;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: Spacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
              child: Row(
                children: [
                  Expanded(child: Text(entry.name, style: textTheme.titleMedium)),
                  RoomStatusChip(status: entry.status),
                ],
              ),
            ),
            const SizedBox(height: Spacing.sm),
            ListTile(
              key: const Key('room-action-occupied'),
              enabled: false,
              leading: Icon(RoomStatus.occupied.icon),
              title: const Text('Occupied'),
              subtitle: const Text('Set by check-in and check-out'),
              trailing: entry.status == RoomStatus.occupied
                  ? const Icon(Icons.check)
                  : null,
            ),
            ListTile(
              key: const Key('room-action-available'),
              leading: Icon(RoomStatus.available.icon,
                  color: RoomStatus.available.color),
              title: const Text('Available'),
              subtitle: const Text('Clean and ready'),
              trailing: tick(RoomState.ready),
              onTap: () => Navigator.of(context)
                  .pop(const SetRoomStateAction(RoomState.ready)),
            ),
            ListTile(
              key: const Key('room-action-dirty'),
              leading: Icon(RoomStatus.cleaning.icon,
                  color: RoomStatus.cleaning.color),
              title: const Text('Needs cleaning'),
              trailing: tick(RoomState.dirty),
              onTap: () => Navigator.of(context)
                  .pop(const SetRoomStateAction(RoomState.dirty)),
            ),
            ListTile(
              key: const Key('room-action-maintenance'),
              leading: Icon(RoomStatus.maintenance.icon,
                  color: RoomStatus.maintenance.color),
              title: const Text('Maintenance'),
              subtitle: Text(entry.state == RoomState.outOfOrder &&
                      entry.reason != null
                  ? entry.reason!
                  : 'Out of order, with a reason'),
              trailing: tick(RoomState.outOfOrder),
              onTap: () async {
                final reason = await showDialog<String>(
                  context: context,
                  builder: (_) => const MaintenanceReasonDialog(),
                );
                if (reason != null && context.mounted) {
                  Navigator.of(context).pop(
                      SetRoomStateAction(RoomState.outOfOrder, reason: reason));
                }
              },
            ),
            const Divider(),
            ListTile(
              key: const Key('room-action-dispatch'),
              enabled: !entry.hasOpenHousekeeping,
              leading: const Icon(Icons.send_outlined),
              title: const Text('Send housekeeping'),
              subtitle: entry.hasOpenHousekeeping
                  ? Text(
                      'Already sent to ${entry.housekeeperName ?? 'a staff member'}')
                  : null,
              onTap: () async {
                final action = await showDialog<DispatchAction>(
                  context: context,
                  builder: (_) => DispatchDialog(
                      propertyId: propertyId, unitName: entry.name),
                );
                if (action != null && context.mounted) {
                  Navigator.of(context).pop(action);
                }
              },
            ),
            const Divider(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.sm),
              child: Wrap(
                spacing: Spacing.sm,
                children: [
                  TextButton.icon(
                    key: const Key('room-link-check-in'),
                    icon: const Icon(Icons.login_outlined),
                    label: const Text('Check-in'),
                    onPressed: () => Navigator.of(context)
                        .pop(const OpenPathAction('/admin/check-in')),
                  ),
                  TextButton.icon(
                    key: const Key('room-link-check-out'),
                    icon: const Icon(Icons.logout_outlined),
                    label: const Text('Check-out'),
                    onPressed: () => Navigator.of(context)
                        .pop(const OpenPathAction('/admin/check-out')),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Asks why a room is out of order. Returns the trimmed reason, or null
/// when cancelled. A blank reason is refused here, before the server's
/// P0030 would.
class MaintenanceReasonDialog extends StatefulWidget {
  const MaintenanceReasonDialog({super.key});

  @override
  State<MaintenanceReasonDialog> createState() =>
      _MaintenanceReasonDialogState();
}

class _MaintenanceReasonDialogState extends State<MaintenanceReasonDialog> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final reason = _controller.text.trim();
    if (reason.isEmpty) {
      setState(() => _error = 'Enter a reason');
      return;
    }
    Navigator.of(context).pop(reason);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Why is it out of order?'),
        content: TextField(
          key: const Key('maintenance-reason'),
          controller: _controller,
          autofocus: true,
          maxLength: 200,
          decoration: InputDecoration(
            labelText: 'Reason',
            hintText: 'e.g. AC not cooling',
            errorText: _error,
          ),
          onSubmitted: (_) => _submit(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('maintenance-submit'),
            onPressed: _submit,
            child: const Text('Mark Maintenance'),
          ),
        ],
      );
}

/// Picks one of the resort's `staff` members and an optional note.
/// Returns the choice, or null when cancelled.
class DispatchDialog extends ConsumerStatefulWidget {
  const DispatchDialog({
    super.key,
    required this.propertyId,
    required this.unitName,
  });

  final String propertyId;
  final String unitName;

  @override
  ConsumerState<DispatchDialog> createState() => _DispatchDialogState();
}

class _DispatchDialogState extends ConsumerState<DispatchDialog> {
  final _note = TextEditingController();
  String? _assigneeId;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final staffAsync = ref.watch(dispatchableStaffProvider(widget.propertyId));
    final note = _note.text.trim();

    return AlertDialog(
      title: Text('Send housekeeping to ${widget.unitName}'),
      content: SizedBox(
        width: 360,
        child: staffAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(Spacing.md),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) => Text(FailureView.messageFor(error)),
          data: (staff) => staff.isEmpty
              ? const Text(
                  'No Staff / Incharge members yet. An owner can add one in Team.')
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      key: const Key('dispatch-assignee'),
                      initialValue: _assigneeId,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Housekeeper'),
                      items: [
                        for (final s in staff)
                          DropdownMenuItem(
                              value: s.userId, child: Text(s.displayName)),
                      ],
                      onChanged: (value) => setState(() => _assigneeId = value),
                    ),
                    const SizedBox(height: Spacing.sm),
                    TextField(
                      key: const Key('dispatch-note'),
                      controller: _note,
                      maxLines: 2,
                      decoration:
                          const InputDecoration(labelText: 'Note (optional)'),
                      onChanged: (_) => setState(() {}),
                    ),
                  ],
                ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('dispatch-submit'),
          onPressed: _assigneeId == null
              ? null
              : () => Navigator.of(context).pop(DispatchAction(
                    _assigneeId!,
                    note: note.isEmpty ? null : note,
                  )),
          child: const Text('Send'),
        ),
      ],
    );
  }
}
```

- [ ] **Step 5: Wire the sheet into the grid**

In `lib/features/staff/room_status_screen.dart`:

Add these imports next to the existing ones:

```dart
import 'package:go_router/go_router.dart';

import '../../core/errors.dart';
import '../../core/widgets/failure_view.dart';
import '../../data/models/resort_membership.dart';
import 'room_actions_sheet.dart';
```

Replace the class doc comment line `/// Every member of the resort can open it; pull to refresh.` with:

```dart
/// Every member of the resort can open it; owners, admins and staff tap a
/// tile for its actions, while accountants see the grid read-only. Pull to
/// refresh; the board is also refetched after every action.
```

In `_RoomStatusScreenState.build`, replace:

```dart
    final propertyId = resort.propertyId;
    final boardAsync = ref.watch(roomBoardProvider(propertyId));
```

with:

```dart
    final propertyId = resort.propertyId;
    final boardAsync = ref.watch(roomBoardProvider(propertyId));
    final canAct = resort.role != ResortRole.accountant;
```

Then replace:

```dart
                now: widget.clock(),
                onTap: null,
```

with:

```dart
                now: widget.clock(),
                onTap: canAct ? (entry) => _openActions(entry, propertyId) : null,
```

Then add this method to `_RoomStatusScreenState`, after `build`:

```dart
  Future<void> _openActions(RoomBoardEntry entry, String propertyId) async {
    final action = await showRoomActionsSheet(context,
        entry: entry, propertyId: propertyId);
    if (action == null || !mounted) return;
    final source = ref.read(roomBoardSourceProvider);
    final messenger = ScaffoldMessenger.of(context);
    try {
      switch (action) {
        case SetRoomStateAction(:final state, :final reason):
          await source.setStatus(entry.unitId, state, reason: reason);
          messenger.showSnackBar(
              SnackBar(content: Text('${entry.name} updated')));
        case DispatchAction(:final assigneeId, :final note):
          await source.dispatch(entry.unitId, assigneeId, note: note);
          messenger.showSnackBar(
              SnackBar(content: Text('Housekeeping sent to ${entry.name}')));
        case OpenPathAction(:final path):
          await context.push(path);
      }
    } on BookingFailure catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text(FailureView.messageFor(e))));
    }
    if (mounted) ref.invalidate(roomBoardProvider(propertyId));
  }
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `flutter test test/core/errors_test.dart test/features/staff/room_status_screen_test.dart && flutter analyze`
Expected: all PASS. No new analyzer issues.

- [ ] **Step 7: Commit**

```bash
git add lib/features/staff/room_actions_sheet.dart lib/features/staff/room_status_screen.dart \
  lib/core/errors.dart test/features/staff/room_status_screen_test.dart test/core/errors_test.dart
git commit -m "feat(rooms): room sheet to set status, send housekeeping and jump to check-in/out"
```

---

### Task 7: Navigation to the grid

**Track:** App. **Depends on:** Task 5.

**Files:**
- Modify: `lib/core/router.dart`
- Modify: `lib/features/shell/app_shell.dart`
- Modify: `lib/features/owner/owner_home_screen.dart`
- Test: `test/core/router_test.dart`, `test/features/shell/app_shell_test.dart`, `test/features/owner/owner_home_screen_test.dart`

**Interfaces:**
- Consumes: `RoomStatusScreen` (Task 5), `redirectFor`, `routerProvider`.
- Produces: the route `/staff/rooms`, which is open to every role at the current resort (the existing `/staff/*` rule). The staff and accountant bar becomes Today, Rooms, Dashboard, Reports. The owner hub gets a "Rooms" tile.

- [ ] **Step 1: Write the failing tests**

In `test/core/router_test.dart`, add these imports:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pasala/core/current_resort.dart';
import 'package:pasala/data/repositories/auth_repository.dart';
```

Add these top-level declarations after `_to`:

```dart
Iterable<String> _paths(List<RouteBase> routes) sync* {
  for (final route in routes) {
    if (route is GoRoute) yield route.path;
    yield* _paths(route.routes);
  }
}

class _NoResort extends CurrentResort {
  @override
  ResortMembership? build() => null;
}
```

Append this group at the end of `main()`:

```dart
  group('room status grid', () {
    test('the app router registers /staff/rooms', () {
      TestWidgetsFlutterBinding.ensureInitialized();
      final container = ProviderContainer(overrides: [
        currentUserProvider.overrideWith((ref) => Stream.value(null)),
        currentResortProvider.overrideWith(_NoResort.new),
      ]);
      addTearDown(container.dispose);

      final router = container.read(routerProvider);

      expect(_paths(router.configuration.routes), contains('/staff/rooms'));
    });

    test('/staff/rooms opens for every role at the current resort', () {
      expect(_to(_superAdmin, _ownerM, '/staff/rooms'), null);
      expect(_to(_admin, _adminM, '/staff/rooms'), null);
      expect(_to(_staff, _staffM, '/staff/rooms'), null);
      expect(_to(_accountant, _accountantM, '/staff/rooms'), null);
    });

    test('/staff/rooms is closed to customers', () {
      expect(_to(_customer, null, '/staff/rooms'), '/404');
    });
  });
```

In `test/features/shell/app_shell_test.dart`, add a route to `_appFor`'s router, after the `/admin/more` route:

```dart
          GoRoute(path: '/staff/rooms', builder: (_, _) => const SizedBox()),
```

Then append these tests at the end of `main()`:

```dart
  testWidgets('staff destinations are Today, Rooms, Dashboard, Reports, '
      'in that order', (tester) async {
    await tester.pumpWidget(_appFor(_staff));
    await tester.pumpAndSettle();

    final xs = [
      for (final label in ['Today', 'Rooms', 'Dashboard', 'Reports'])
        tester.getCenter(find.text(label)).dx,
    ];
    expect(xs, [...xs]..sort());
  });

  testWidgets('an accountant also gets the Rooms destination', (tester) async {
    await tester.pumpWidget(_appFor(_accountant));
    await tester.pumpAndSettle();

    expect(find.text('Rooms'), findsOneWidget);
  });

  testWidgets("staff's Rooms destination opens /staff/rooms", (tester) async {
    await tester.pumpWidget(_appFor(_staff));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Rooms'));
    await tester.pumpAndSettle();

    final router = GoRouter.of(tester.element(find.text('Rooms')));
    expect(router.routerDelegate.currentConfiguration.uri.path, '/staff/rooms');
  });
```

In `test/features/owner/owner_home_screen_test.dart`, add a route to `_appFor`'s router, after `/admin/bookings`:

```dart
      GoRoute(path: '/staff/rooms', builder: (_, _) => const Text('Rooms screen')),
```

In the test `'shows a tile for every step of the Owner flow'`, add `'Rooms',` after `'Bookings',` in the title list. Then append:

```dart
  testWidgets('the Rooms tile opens the room status grid', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_appFor());
    await tester.pumpAndSettle();

    final roomsTile = find.text('Rooms');
    await tester.ensureVisible(roomsTile);
    await tester.pumpAndSettle();
    await tester.tap(roomsTile);
    await tester.pumpAndSettle();

    expect(find.text('Rooms screen'), findsOneWidget);
  });
```

- [ ] **Step 2: Run them to verify they fail**

Run: `flutter test test/core/router_test.dart test/features/shell/app_shell_test.dart test/features/owner/owner_home_screen_test.dart`
Expected: FAIL on `the app router registers /staff/rooms` (the path is missing), `staff destinations are Today, Rooms, …` and `an accountant also gets …` (no 'Rooms' text), and the owner Rooms tests. The two `redirectFor` matrix tests already PASS: `/staff/*` is open to any member today, and they pin that.

- [ ] **Step 3: Register the route**

In `lib/core/router.dart`, add the import next to the other `features/staff` imports:

```dart
import '../features/staff/room_status_screen.dart';
```

In the `ShellRoute` routes, immediately after the `/staff/maintenance` route, add:

```dart
          // Room status grid (REQ-06). Open to every role at the current
          // resort through the `/staff/*` rule in redirectFor; the screen
          // hides actions from accountants, and set_room_status /
          // dispatch_housekeeping enforce the roles in Postgres.
          GoRoute(
            path: '/staff/rooms',
            builder: (_, _) => const RoomStatusScreen(),
          ),
```

- [ ] **Step 4: Add Rooms to the staff bar**

In `lib/features/shell/app_shell.dart`, replace:

```dart
  static const _staffDestinations = [
    (path: '/staff', icon: Icons.task_alt_outlined, label: 'Today'),
```

with:

```dart
  // Rooms (the room status grid) sits second: duty managers change room
  // states and send housekeeping all day. Accountants get it too, read-only.
  static const _staffDestinations = [
    (path: '/staff', icon: Icons.task_alt_outlined, label: 'Today'),
    (path: '/staff/rooms', icon: Icons.meeting_room_outlined, label: 'Rooms'),
```

- [ ] **Step 5: Add Rooms to the owner hub**

In `lib/features/owner/owner_home_screen.dart`, in `_destinations`, immediately after the entry whose `title` is `'Bookings'`, add:

```dart
    (
      icon: Icons.meeting_room_outlined,
      title: 'Rooms',
      subtitle: 'Room status, housekeeping and maintenance',
      path: '/staff/rooms',
    ),
```

Change the class doc sentence `The 9 destination tiles below are unchanged.` to `The destination tiles follow, including Rooms (the room status grid).`

- [ ] **Step 6: Run the tests to verify they pass**

Run: `flutter test test/core/router_test.dart test/features/shell/app_shell_test.dart test/features/owner/owner_home_screen_test.dart && flutter analyze`
Expected: all PASS. No new analyzer issues.

- [ ] **Step 7: Commit**

```bash
git add lib/core/router.dart lib/features/shell/app_shell.dart lib/features/owner/owner_home_screen.dart \
  test/core/router_test.dart test/features/shell/app_shell_test.dart test/features/owner/owner_home_screen_test.dart
git commit -m "feat(rooms): reach the room grid from the staff bar and the owner hub"
```

---

### Task 8: Admin dashboard reads the real board

**Track:** App. **Depends on:** Task 1.

**Files:**
- Modify: `lib/features/admin/admin_home_screen.dart`
- Test: `test/features/admin/admin_home_screen_test.dart`

**Interfaces:**
- Consumes: `roomBoardProvider`, `RoomBoardEntry`, `RoomState`, `RoomStatus`, `FakeRoomBoardSource`, `boardEntry` (Task 1).
- Produces: `String roomReadinessLabel(List<RoomBoardEntry>)` and `bool allRoomsReady(List<RoomBoardEntry>)` as top-level functions in `admin_home_screen.dart`. Widget keys `preparation-rooms`, `readiness-rooms` and `readiness-overall`. The quick action `quick-action-Rooms` goes to `/staff/rooms`.

- [ ] **Step 1: Write the failing tests**

In `test/features/admin/admin_home_screen_test.dart`, add these imports:

```dart
import 'package:pasala/data/models/room_status.dart';
import 'package:pasala/data/repositories/room_status_repository.dart';

import '../../support/fake_room_board_source.dart';
```

Add this group inside `main()`, before `group('AdminHomeScreen', …)`:

```dart
  group('roomReadinessLabel', () {
    test('every room ready, occupied ones included', () {
      expect(
        roomReadinessLabel([
          boardEntry(),
          boardEntry(unitId: 'u2', status: RoomStatus.occupied),
        ]),
        'All rooms ready ✓',
      );
      expect(allRoomsReady([boardEntry()]), isTrue);
    });

    test('counts rooms to clean and rooms in maintenance', () {
      final rooms = [
        boardEntry(state: RoomState.dirty, status: RoomStatus.cleaning),
        boardEntry(
            unitId: 'u2',
            state: RoomState.outOfOrder,
            status: RoomStatus.maintenance,
            reason: 'Leak'),
        boardEntry(unitId: 'u3', state: RoomState.dirty, status: RoomStatus.occupied),
      ];
      expect(roomReadinessLabel(rooms), '2 to clean · 1 in maintenance');
      expect(allRoomsReady(rooms), isFalse);
    });

    test('a resort with no rooms says so', () {
      expect(roomReadinessLabel(const []), 'No rooms set up');
    });
  });
```

In `group('AdminHomeScreen', …)`, change the `app` signature to:

```dart
    Widget app({
      List<Reservation> bookings = const [],
      List<Review> reviews = const [],
      List<RoomBoardEntry> rooms = const [],
    }) {
```

Add this route after the `/admin/outbox` route:

```dart
          GoRoute(
              path: '/staff/rooms',
              builder: (_, _) => const Text('ROOMS SCREEN')),
```

Add this override as the last entry of the `overrides:` list:

```dart
          roomBoardSourceProvider
              .overrideWithValue(FakeRoomBoardSource()..entries = rooms),
```

Append these tests at the end of `group('AdminHomeScreen', …)`:

```dart
    testWidgets('Preparation and the readiness card show the real rooms',
        (tester) async {
      await useTallSurface(tester);
      await tester.pumpWidget(app(rooms: [
        boardEntry(state: RoomState.dirty, status: RoomStatus.cleaning),
        boardEntry(
            unitId: 'u2',
            name: 'Cottage 2',
            state: RoomState.outOfOrder,
            status: RoomStatus.maintenance,
            reason: 'Leak'),
      ]));
      await tester.pumpAndSettle();

      expect(
        tester.widget<Text>(find.byKey(const Key('preparation-rooms'))).data,
        '1 to clean · 1 in maintenance',
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('readiness-overall'))).data,
        'ATTENTION',
      );
      expect(
        find.descendant(
            of: find.byKey(const Key('readiness-rooms')),
            matching: find.byIcon(Icons.error_outline)),
        findsOneWidget,
      );
    });

    testWidgets('all rooms ready reads READY', (tester) async {
      await useTallSurface(tester);
      await tester.pumpWidget(app(rooms: [boardEntry()]));
      await tester.pumpAndSettle();

      expect(
        tester.widget<Text>(find.byKey(const Key('preparation-rooms'))).data,
        'All rooms ready ✓',
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('readiness-overall'))).data,
        'READY',
      );
    });

    testWidgets('tapping Rooms navigates to the room grid', (tester) async {
      await useTallSurface(tester);
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('quick-action-Rooms')));
      await tester.pumpAndSettle();

      expect(find.text('ROOMS SCREEN'), findsOneWidget);
    });
```

- [ ] **Step 2: Run them to verify they fail**

Run: `flutter test test/features/admin/admin_home_screen_test.dart`
Expected: FAIL to compile with "The function 'roomReadinessLabel' isn't defined".

- [ ] **Step 3: Implement**

In `lib/features/admin/admin_home_screen.dart`, add these imports:

```dart
import '../../data/models/room_status.dart';
import '../../data/repositories/room_status_repository.dart';
```

Insert immediately before the doc comment `/// This screen shows exactly one resort -- the signed-in admin's current`:

```dart
/// Whether every room's stored state is `ready` -- an occupied room counts
/// as ready unless someone marked it for cleaning or maintenance.
bool allRoomsReady(List<RoomBoardEntry> rooms) =>
    rooms.every((r) => r.state == RoomState.ready);

/// The Preparation line of Today's Focus, from the room board's stored
/// states (not the derived status, so an occupied room that needs cleaning
/// still counts).
String roomReadinessLabel(List<RoomBoardEntry> rooms) {
  if (rooms.isEmpty) return 'No rooms set up';
  final toClean = rooms.where((r) => r.state == RoomState.dirty).length;
  final maintenance = rooms.where((r) => r.state == RoomState.outOfOrder).length;
  if (toClean == 0 && maintenance == 0) return 'All rooms ready ✓';
  return [
    if (toClean > 0) '$toClean to clean',
    if (maintenance > 0) '$maintenance in maintenance',
  ].join(' · ');
}

```

In `_TodaysFocus`, replace the doc sentence `/// Preparation is the one deliberately decorative line here, matching` and the line after it, `/// [_FarmhouseReadinessCard]'s always-ready state.`, with:

```dart
/// Preparation reads the room board -- see [roomReadinessLabel].
```

In `_TodaysFocus.build`, after `final arrival = nextArrival(bookings, DateTime.now());`, add:

```dart
    final preparation = ref.watch(roomBoardProvider(propertyId)).when(
          data: roomReadinessLabel,
          loading: () => 'Checking rooms…',
          error: (_, _) => 'Room status unavailable',
        );
```

Then replace:

```dart
                content: Text('Farmhouse ready ✓', style: textTheme.bodySmall),
```

with:

```dart
                content: Text(preparation,
                    key: const Key('preparation-rooms'),
                    style: textTheme.bodySmall),
```

In `_QuickActions.build`, immediately after the `Check-out` action entry (the one ending `() => context.push('/admin/check-out'),` followed by `),`), add:

```dart
      (
        (icon: Icons.meeting_room_outlined, label: 'Rooms', color: Colors.teal),
        () => context.push('/staff/rooms'),
      ),
```

Replace the whole `_FarmhouseReadinessCard` class, including its doc comment (from `/// A fixed, always-ready checklist` through the class's closing `}`), with:

```dart
/// A readiness checklist. Only "Rooms / Cottages" is backed by data -- the
/// room board's stored states (see [allRoomsReady]); Pool, Garden, Kitchen
/// and Wi-Fi have no status anywhere in the app and stay a fixed checklist.
/// The Overall Status pill follows the rooms line: READY, ATTENTION when a
/// room needs cleaning or is out of order, or a dash while the board is
/// loading or unavailable.
class _FarmhouseReadinessCard extends ConsumerWidget {
  const _FarmhouseReadinessCard();

  static const _fixedItems = ['Pool', 'Garden', 'Kitchen', 'Wi-Fi'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final propertyId = ref.watch(currentResortProvider)!.propertyId;
    final rooms = ref.watch(roomBoardProvider(propertyId)).value;
    final roomsReady = rooms == null ? null : allRoomsReady(rooms);

    Widget row(String item, IconData icon, Color color, {Key? key}) => Padding(
          key: key,
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Expanded(
                  child: Text(item,
                      style: textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis)),
              Icon(icon, size: 16, color: color),
            ],
          ),
        );

    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _eyebrow(context, 'FARMHOUSE READINESS'),
          const SizedBox(height: Spacing.sm),
          row(
            'Rooms / Cottages',
            switch (roomsReady) {
              true => Icons.check_circle,
              false => Icons.error_outline,
              null => Icons.remove_circle_outline,
            },
            switch (roomsReady) {
              true => scheme.primary,
              false => RoomStatus.cleaning.color,
              null => scheme.onSurfaceVariant,
            },
            key: const Key('readiness-rooms'),
          ),
          for (final item in _fixedItems)
            row(item, Icons.check_circle, scheme.primary),
          const SizedBox(height: Spacing.sm),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: Spacing.sm, vertical: 4),
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Overall Status',
                    style: textTheme.labelSmall
                        ?.copyWith(color: scheme.onPrimaryContainer)),
                const Spacer(),
                Text(
                  switch (roomsReady) {
                    true => 'READY',
                    false => 'ATTENTION',
                    null => '—',
                  },
                  key: const Key('readiness-overall'),
                  style: textTheme.labelSmall?.copyWith(
                      color: scheme.onPrimaryContainer,
                      fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/features/admin/admin_home_screen_test.dart && flutter analyze`
Expected: all PASS, including the existing tests, which now get an empty board ('No rooms set up', 'READY'). No new analyzer issues.

- [ ] **Step 5: Commit**

```bash
git add lib/features/admin/admin_home_screen.dart test/features/admin/admin_home_screen_test.dart
git commit -m "feat(rooms): admin dashboard readiness reads the real room board"
```

---

### Task 9: Assigned Work shows the room

**Track:** App. **Depends on:** Task 1.

**Files:**
- Modify: `lib/data/models/staff_task.dart`
- Modify: `lib/data/repositories/task_repository.dart`
- Modify: `lib/features/staff/assigned_tasks_screen.dart`
- Test: `test/data/staff_task_test.dart`, `test/features/staff/assigned_tasks_screen_test.dart`

**Interfaces:**
- Consumes: `tasks.unit_id → units` (the Task 1 schema), `roomBoardProvider`, `roomBoardSourceProvider`, `FakeRoomBoardSource`.
- Produces: `StaffTask.unitName` (a `String?` read from the `units(name)` embed). `TaskRepository.list` selects `units(name)`. Changing a task's status invalidates `roomBoardProvider(propertyId)`.

- [ ] **Step 1: Write the failing tests**

Append inside `group('StaffTask.fromJson', …)` in `test/data/staff_task_test.dart`:

```dart
    test('reads the room name from an embedded units object', () {
      final task = StaffTask.fromJson(const {
        'id': 't3',
        'assignee_id': 'u1',
        'units': {'name': 'Cottage 4'},
        'title': 'Clean Cottage 4',
        'description': '',
        'status': 'todo',
      });

      expect(task.unitName, 'Cottage 4');
    });

    test('a general task has no room', () {
      final task = StaffTask.fromJson(const {
        'id': 't4',
        'assignee_id': 'u1',
        'units': null,
        'title': 'Restock minibar',
        'description': '',
        'status': 'todo',
      });

      expect(task.unitName, isNull);
    });
```

In `test/features/staff/assigned_tasks_screen_test.dart`, add these imports:

```dart
import 'package:pasala/data/repositories/room_status_repository.dart';

import '../../support/fake_room_board_source.dart';
```

In `FakeTaskRepository.updateStatus`, replace the `store[i] = StaffTask(...)` construction with:

```dart
    store[i] = StaffTask(
      id: existing.id,
      assigneeId: existing.assigneeId,
      assigneeName: existing.assigneeName,
      title: existing.title,
      description: existing.description,
      status: status,
      unitName: existing.unitName,
    );
```

Append inside `main()`:

```dart
  testWidgets('a housekeeping task shows its room', (tester) async {
    final repo = FakeTaskRepository()
      ..store.add(const StaffTask(
        id: 't1',
        assigneeId: 'staff-1',
        title: 'Clean Cottage 4',
        description: 'Deep clean',
        status: TaskStatus.todo,
        unitName: 'Cottage 4',
      ));

    await tester.pumpWidget(_appFor(repo));
    await tester.pumpAndSettle();

    expect(find.text('Room: Cottage 4'), findsOneWidget);
    expect(find.byKey(const Key('task-unit-t1')), findsOneWidget);
  });

  testWidgets('changing a task status refetches the room board',
      (tester) async {
    final repo = FakeTaskRepository()
      ..store.add(const StaffTask(
        id: 't1',
        assigneeId: 'staff-1',
        title: 'Clean Cottage 4',
        description: '',
        status: TaskStatus.todo,
        unitName: 'Cottage 4',
      ));
    final board = FakeRoomBoardSource();

    await tester.pumpWidget(ProviderScope(
      overrides: [
        currentUserProvider.overrideWith((ref) => Stream.value(_staff)),
        currentResortProvider.overrideWith(_FixedResort.new),
        taskRepositoryProvider.overrideWithValue(repo),
        roomBoardSourceProvider.overrideWithValue(board),
      ],
      child: MaterialApp(
        home: Column(
          children: [
            const Expanded(child: AssignedTasksScreen()),
            // Stands in for an open Rooms tab, which keeps the board alive.
            Consumer(builder: (_, ref, _) {
              ref.watch(roomBoardProvider('p1'));
              return const SizedBox.shrink();
            }),
          ],
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final before = board.boardCalls.length;

    await tester.tap(find.byKey(const Key('task-status-t1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done').last);
    await tester.pumpAndSettle();

    expect(board.boardCalls.length, greaterThan(before));
  });
```

- [ ] **Step 2: Run them to verify they fail**

Run: `flutter test test/data/staff_task_test.dart test/features/staff/assigned_tasks_screen_test.dart`
Expected: FAIL to compile with "The named parameter 'unitName' isn't defined".

- [ ] **Step 3: Implement**

In `lib/data/models/staff_task.dart`, add `this.unitName,` to the constructor after `this.assigneeName,`. Add this field after `final String? assigneeName;`:

```dart
  /// The room a housekeeping task is for, from the `units(name)` embed that
  /// [TaskRepository.list] requests -- null for a general task, or for a
  /// response without that embed.
  final String? unitName;
```

In `StaffTask.fromJson`, after the `assigneeName:` entry, add:

```dart
        unitName: (json['units'] as Map<String, dynamic>?)?['name'] as String?,
```

In `lib/data/repositories/task_repository.dart`, in `list`, replace:

```dart
            .select('*, profiles!tasks_assignee_id_fkey(full_name)')
```

with:

```dart
            .select('*, profiles!tasks_assignee_id_fkey(full_name), units(name)')
```

Then add this line to that method's doc comment: `/// `units(name)` names the room of a housekeeping task (0047).`

In `lib/features/staff/assigned_tasks_screen.dart`, add:

```dart
import '../../data/repositories/room_status_repository.dart';
```

After the title `Text(task.title, …),` line, add:

```dart
                      if (task.unitName != null) ...[
                        const SizedBox(height: Spacing.xs),
                        Row(
                          key: Key('task-unit-${task.id}'),
                          children: [
                            const Icon(Icons.meeting_room_outlined, size: 16),
                            const SizedBox(width: Spacing.xs),
                            Text('Room: ${task.unitName}'),
                          ],
                        ),
                      ],
```

In `_updateStatus`, replace:

```dart
      ref.invalidate(tasksProvider(filter));
```

with:

```dart
      ref.invalidate(tasksProvider(filter));
      // Finishing a housekeeping task makes the room Available server-side
      // (tasks_housekeeping_done); refetch the board if it is showing.
      ref.invalidate(roomBoardProvider(filter.propertyId));
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/data/staff_task_test.dart test/features/staff/assigned_tasks_screen_test.dart test/features/admin/tasks_screen_test.dart && flutter analyze`
Expected: all PASS. No new analyzer issues.

- [ ] **Step 5: Commit**

```bash
git add lib/data/models/staff_task.dart lib/data/repositories/task_repository.dart \
  lib/features/staff/assigned_tasks_screen.dart test/data/staff_task_test.dart \
  test/features/staff/assigned_tasks_screen_test.dart
git commit -m "feat(rooms): Assigned Work names the room of a housekeeping task"
```

---

### Task 10: Reception warning and board refresh after check-in/out

**Track:** App. **Depends on:** Task 1.

**Files:**
- Modify: `lib/features/admin/reception_checkin_screen.dart`
- Modify: `lib/features/admin/reception_checkout_screen.dart`
- Test: `test/features/admin/reception_checkin_screen_test.dart`, `test/features/admin/reception_checkout_screen_test.dart`

**Interfaces:**
- Consumes: `roomBoardProvider`, `roomBoardSourceProvider`, `RoomBoardEntry`, `RoomState`, `RoomStatus`, `FakeRoomBoardSource`, `boardEntry`, and `StayRepository.checkIn` / `stayRepositoryProvider`.
- Produces: `String? roomWarningFor(RoomBoardEntry?)` in `reception_checkin_screen.dart`, and the chip key `room-warning-<reservationId>`. Both reception screens invalidate `roomBoardProvider(propertyId)` after check-in or checkout.

- [ ] **Step 1: Write the failing tests**

Replace `test/features/admin/reception_checkin_screen_test.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/current_resort.dart';
import 'package:pasala/core/errors.dart';
import 'package:pasala/data/models/reservation.dart';
import 'package:pasala/data/models/resort_membership.dart';
import 'package:pasala/data/models/room_status.dart';
import 'package:pasala/data/repositories/room_status_repository.dart';
import 'package:pasala/data/repositories/stay_repository.dart';
import 'package:pasala/features/admin/reception_checkin_screen.dart';

import '../../support/fake_room_board_source.dart';

const _resort =
    ResortMembership(propertyId: 'p1', resortName: 'Pasala', role: ResortRole.admin);

const _bookingId = '3f2a1b9c-0000-0000-0000-000000000000';

class _FixedResort extends CurrentResort {
  @override
  ResortMembership? build() => _resort;
}

Reservation _booking({String? customerName}) => Reservation(
      id: _bookingId,
      unitId: 'u1',
      start: DateTime(2026, 9, 14),
      end: DateTime(2026, 9, 16),
      kind: ReservationKind.booking,
      status: ReservationStatus.confirmed,
      customerName: customerName,
      guests: 2,
    );

/// Only [checkIn] is reached from this screen.
class _FakeStayRepository implements StayRepository {
  final checkIns = <String>[];

  @override
  Future<Reservation> checkIn(String reservationId) async {
    checkIns.add(reservationId);
    return _booking(customerName: 'Ravi Kumar');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final listedPropertyIds = <String>[];

  Widget appFor(
    List<Reservation> arrivals, {
    FakeRoomBoardSource? board,
    _FakeStayRepository? stay,
  }) =>
      ProviderScope(
        overrides: [
          todaysArrivalsProvider.overrideWith((ref, propertyId) async {
            listedPropertyIds.add(propertyId);
            return arrivals;
          }),
          currentResortProvider.overrideWith(_FixedResort.new),
          roomBoardSourceProvider
              .overrideWithValue(board ?? FakeRoomBoardSource()),
          if (stay != null) stayRepositoryProvider.overrideWithValue(stay),
        ],
        child: const MaterialApp(home: ReceptionCheckinScreen()),
      );

  // I9: this screen previously showed only a date range and an internal
  // booking id -- reception had no way to identify WHO they were checking
  // in without cross-referencing a booking id by hand. Reproduced live: a
  // real guest ("Ravi Kumar") appeared here as an anonymous date range.
  testWidgets('shows the guest\'s real name when the query returns one',
      (tester) async {
    await tester.pumpWidget(appFor([_booking(customerName: 'Ravi Kumar')]));
    await tester.pumpAndSettle();

    expect(find.text('Ravi Kumar'), findsOneWidget);
    // Review Focus #1: the screen must pass the current resort's id
    // through to the repository, not rely on RLS alone.
    expect(listedPropertyIds, everyElement('p1'));
  });

  testWidgets('falls back to "Guest" only when no name is available',
      (tester) async {
    await tester.pumpWidget(appFor([_booking(customerName: null)]));
    await tester.pumpAndSettle();

    expect(find.text('Guest'), findsOneWidget);
  });

  testWidgets('the date range and guest count still show in the subtitle',
      (tester) async {
    await tester.pumpWidget(appFor([_booking(customerName: 'Ravi Kumar')]));
    await tester.pumpAndSettle();

    expect(find.textContaining('14 Sep'), findsOneWidget);
    expect(find.textContaining('2 guests'), findsOneWidget);
  });

  group('roomWarningFor', () {
    test('warns about a dirty room and a room in maintenance', () {
      expect(roomWarningFor(boardEntry(state: RoomState.dirty)),
          'Room not cleaned yet');
      expect(
          roomWarningFor(
              boardEntry(state: RoomState.outOfOrder, reason: 'AC broken')),
          'Maintenance: AC broken');
    });

    test('says nothing for a ready room or an unknown one', () {
      expect(roomWarningFor(boardEntry()), isNull);
      expect(roomWarningFor(null), isNull);
    });
  });

  testWidgets('warns, without blocking, when the room still needs cleaning',
      (tester) async {
    await tester.pumpWidget(appFor(
      [_booking(customerName: 'Ravi Kumar')],
      board: FakeRoomBoardSource()
        ..entries = [
          boardEntry(unitId: 'u1', state: RoomState.dirty, status: RoomStatus.cleaning),
        ],
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('room-warning-$_bookingId')), findsOneWidget);
    expect(find.text('Room not cleaned yet'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Check In'), findsOneWidget);
  });

  testWidgets('shows the maintenance reason', (tester) async {
    await tester.pumpWidget(appFor(
      [_booking(customerName: 'Ravi Kumar')],
      board: FakeRoomBoardSource()
        ..entries = [
          boardEntry(
              unitId: 'u1',
              state: RoomState.outOfOrder,
              status: RoomStatus.maintenance,
              reason: 'AC broken'),
        ],
    ));
    await tester.pumpAndSettle();

    expect(find.text('Maintenance: AC broken'), findsOneWidget);
  });

  testWidgets('a ready room shows no warning', (tester) async {
    await tester.pumpWidget(appFor(
      [_booking(customerName: 'Ravi Kumar')],
      board: FakeRoomBoardSource()..entries = [boardEntry(unitId: 'u1')],
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('room-warning-$_bookingId')), findsNothing);
  });

  // Review Focus 4: the warning is advice; a board that fails to load must
  // not take check-in down with it.
  testWidgets('a room board that fails to load does not block check-in',
      (tester) async {
    await tester.pumpWidget(appFor(
      [_booking(customerName: 'Ravi Kumar')],
      board: FakeRoomBoardSource()..boardError = const NetworkFailure(),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Ravi Kumar'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Check In'), findsOneWidget);
    expect(find.byKey(const Key('room-warning-$_bookingId')), findsNothing);
  });

  testWidgets('checking in refetches the room board', (tester) async {
    final board = FakeRoomBoardSource()..entries = [boardEntry(unitId: 'u1')];
    final stay = _FakeStayRepository();
    await tester.pumpWidget(
        appFor([_booking(customerName: 'Ravi Kumar')], board: board, stay: stay));
    await tester.pumpAndSettle();
    final before = board.boardCalls.length;

    await tester.tap(find.widgetWithText(FilledButton, 'Check In'));
    await tester.pumpAndSettle();

    expect(stay.checkIns, [_bookingId]);
    expect(board.boardCalls.length, greaterThan(before));
  });
}
```

In `test/features/admin/reception_checkout_screen_test.dart`, add these imports:

```dart
import 'package:pasala/data/repositories/room_status_repository.dart';

import '../../support/fake_room_board_source.dart';
```

Then append inside `main()`:

```dart
  testWidgets('returning from checkout refetches the room board',
      (tester) async {
    final board = FakeRoomBoardSource();
    final router = GoRouter(
      initialLocation: '/admin/check-out',
      routes: [
        GoRoute(
            path: '/admin/check-out',
            builder: (_, _) => const ReceptionCheckoutScreen()),
        GoRoute(
            path: '/my-stay/checkout',
            builder: (_, _) => const Text('CHECKOUT SCREEN')),
      ],
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [
        checkedInProvider.overrideWith(
            (ref, propertyId) async => [_checkedIn('r1', customerName: 'Ravi Kumar')]),
        currentResortProvider.overrideWith(_FixedResort.new),
        roomBoardSourceProvider.overrideWithValue(board),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        // Stands in for an open Rooms tab, which keeps the board alive.
        builder: (context, child) => Stack(children: [
          child!,
          Consumer(builder: (_, ref, _) {
            ref.watch(roomBoardProvider('p1'));
            return const SizedBox.shrink();
          }),
        ]),
      ),
    ));
    await tester.pumpAndSettle();
    final before = board.boardCalls.length;

    await tester.tap(find.widgetWithText(FilledButton, 'Check Out'));
    await tester.pumpAndSettle();
    GoRouter.of(tester.element(find.text('CHECKOUT SCREEN'))).pop();
    await tester.pumpAndSettle();

    expect(board.boardCalls.length, greaterThan(before));
  });
```

- [ ] **Step 2: Run them to verify they fail**

Run: `flutter test test/features/admin/reception_checkin_screen_test.dart test/features/admin/reception_checkout_screen_test.dart`
Expected: FAIL to compile with "The function 'roomWarningFor' isn't defined". After a stub, the new widget tests fail on the missing warning and on the unchanged `boardCalls`.

- [ ] **Step 3: Implement the check-in warning**

Replace `lib/features/admin/reception_checkin_screen.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/current_resort.dart';
import '../../core/errors.dart';
import '../../core/format.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/failure_view.dart';
import '../../data/models/room_status.dart';
import '../../data/repositories/room_status_repository.dart';
import '../../data/repositories/stay_repository.dart';
import '../staff/providers.dart' show allBookingsProvider;

/// The warning reception sees on a booking whose room is not ready. A
/// warning only: check-in is never blocked on room state (room status
/// spec, decision 10). Null when the room is ready or its state is
/// unknown.
String? roomWarningFor(RoomBoardEntry? room) => switch (room?.state) {
      RoomState.dirty => 'Room not cleaned yet',
      RoomState.outOfOrder => 'Maintenance: ${room?.reason ?? 'out of order'}',
      _ => null,
    };

/// `/admin/check-in` -- every `confirmed` booking, one-tap Check In. The
/// doc's own accepted method: reception looks up the booking (by name or
/// the guest's QR/booking-id) and taps Check In -- no camera scanning.
/// A booking whose room still needs cleaning or is in maintenance carries
/// a warning chip (see [roomWarningFor]).
class ReceptionCheckinScreen extends ConsumerWidget {
  const ReceptionCheckinScreen({super.key});

  Future<void> _checkIn(
    WidgetRef ref,
    BuildContext context,
    String id,
    String propertyId,
  ) async {
    try {
      await ref.read(stayRepositoryProvider).checkIn(id);
      ref.invalidate(todaysArrivalsProvider(propertyId));
      ref.invalidate(checkedInProvider(propertyId));
      // The admin dashboard's Farmhouse Status / Today's Focus cards read
      // from this same list -- without invalidating it here, a fresh
      // check-in never shows as OCCUPIED until something else happens to
      // refetch it.
      ref.invalidate(allBookingsProvider);
      // The room is Occupied now.
      ref.invalidate(roomBoardProvider(propertyId));
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Checked in')));
      }
    } on BookingFailure catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(FailureView.messageFor(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final propertyId = ref.watch(currentResortProvider)!.propertyId;
    final arrivalsAsync = ref.watch(todaysArrivalsProvider(propertyId));
    // The board only adds warnings: while it loads, or if it fails, the
    // list shows without them and check-in works as before.
    final rooms = ref.watch(roomBoardProvider(propertyId)).value ??
        const <RoomBoardEntry>[];
    final roomByUnit = {for (final r in rooms) r.unitId: r};

    return Scaffold(
      appBar: AppBar(title: const Text('Check-In')),
      body: AsyncView(
        value: arrivalsAsync,
        onRetry: () => ref.invalidate(todaysArrivalsProvider(propertyId)),
        empty: () => const EmptyState(
          icon: Icons.how_to_reg_outlined,
          title: 'No bookings waiting to check in',
        ),
        data: (bookings) => ListView.builder(
          padding: const EdgeInsets.all(Spacing.md),
          itemCount: bookings.length,
          itemBuilder: (context, i) {
            final b = bookings[i];
            final warning = roomWarningFor(roomByUnit[b.unitId]);
            return Card(
              margin: const EdgeInsets.only(bottom: Spacing.sm),
              child: ListTile(
                title: Text(b.customerName ?? 'Guest'),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${formatDay(b.start.toLocal())} → ${formatDay(b.end.toLocal())} · '
                      '${b.guests ?? '—'} guests · Booking ${b.id.substring(0, 8)}',
                    ),
                    if (warning != null)
                      Padding(
                        padding: const EdgeInsets.only(top: Spacing.xs),
                        child: Chip(
                          key: Key('room-warning-${b.id}'),
                          visualDensity: VisualDensity.compact,
                          avatar: Icon(Icons.warning_amber_outlined,
                              size: 18, color: RoomStatus.cleaning.color),
                          label: Text(warning),
                        ),
                      ),
                  ],
                ),
                trailing: FilledButton(
                  onPressed: () => _checkIn(ref, context, b.id, propertyId),
                  child: const Text('Check In'),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Refresh the board after checkout**

In `lib/features/admin/reception_checkout_screen.dart`, add:

```dart
import '../../data/repositories/room_status_repository.dart';
```

Then replace:

```dart
                      ref.invalidate(allBookingsProvider);
```

with:

```dart
                      ref.invalidate(allBookingsProvider);
                      // checkout_booking marks the room for cleaning.
                      ref.invalidate(roomBoardProvider(propertyId));
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `flutter test test/features/admin/reception_checkin_screen_test.dart test/features/admin/reception_checkout_screen_test.dart && flutter analyze`
Expected: all PASS. No new analyzer issues.

- [ ] **Step 6: Commit**

```bash
git add lib/features/admin/reception_checkin_screen.dart lib/features/admin/reception_checkout_screen.dart \
  test/features/admin/reception_checkin_screen_test.dart test/features/admin/reception_checkout_screen_test.dart
git commit -m "feat(rooms): warn at check-in about unready rooms; refresh the board after check-in/out"
```

---

## Phase 3: Integration

### Task 11: Merge the tracks and verify end to end

**Track:** both. **Depends on:** Tasks 2–10.

**Files:**
- None created. This task only verifies; a fix belongs to the task that owns the file, and gets its own commit.

**Interfaces:**
- Consumes: everything above.
- Produces: a branch where the database and app agree on names and shapes, with both suites green.

- [ ] **Step 1: Merge**

If the tracks ran in separate worktrees, merge the database branch and the app branch into `feat/room-status`. The tracks own disjoint files, so no conflicts are expected. If one appears, keep both sides' additions.

- [ ] **Step 2: Check the contract by name**

Run: `grep -n "'p_property'\|'p_unit'\|'p_state'\|'p_reason'\|'p_assignee'\|'p_note'\|rpc('" lib/data/repositories/room_status_repository.dart`
Expected: exactly the RPC names `room_status_board`, `set_room_status`, `dispatch_housekeeping` and `list_dispatchable_staff`, with the parameter names `p_property`, `p_unit`, `p_state`, `p_reason`, `p_assignee` and `p_note`. Each must match a signature in `0047_room_status.sql`, which you can list with `grep -n "create function public\.\(room_status_board\|set_room_status\|dispatch_housekeeping\|list_dispatchable_staff\)" -A4 supabase/migrations/0047_room_status.sql`.

- [ ] **Step 3: Run the full suites**

Run: `supabase db reset && supabase test db`, then `flutter test`, then `flutter analyze`
Expected:
- pgTAP: 39 at 81/81, 37 at 77/77, and every other file as in the Task 1 Step 1 baseline.
- Flutter: all tests pass, with the count equal to the baseline plus the tests this plan added.
- Analyzer: no issues beyond the baseline.

- [ ] **Step 4: Manual smoke test against the local stack**

Run: `make run-web`, then sign in as a seeded `staff` member of a resort that has at least one active unit and a checked-in booking. Confirm:
1. The bottom bar reads Today, Rooms, Dashboard, Reports, and Rooms shows every active unit. The checked-in unit is Occupied with the guest's first name.
2. Mark a unit Maintenance: the dialog refuses a blank reason, and after a real reason the tile shows Maintenance and the reason.
3. Send housekeeping to a ready unit: the tile turns Cleaning with "Housekeeping: <name>, 0 min".
4. Sign in as that housekeeper, open Assigned Work, and see "Room: <unit>". Set the task to Done.
5. Back on Rooms, pull to refresh: the unit is Available.
6. Check a guest out from Check-Out: back on Rooms, their unit is Cleaning.
7. Sign in as an accountant: Rooms shows the grid, and tapping a tile does nothing.

- [ ] **Step 5: Commit any fixes**

For each fix, run `git add <the fixed files>` and then `git commit -m "fix(rooms): <what was wrong>"`. If nothing needed fixing, there is nothing to commit.

---

## Self-Review

**1. Spec coverage**

| Spec requirement | Task |
|---|---|
| Enum `room_state`, table `unit_room_status` (FK cascade, `fill_property_id`, reason check, `updated_by`/`updated_at`, missing row = ready, Staff+ read, no write grants) | 1 (schema, RLS), 2 (missing row = ready) |
| `tasks.kind` / `unit_id` / `started_at` | 1 |
| `completed_at` (already exists), timestamps set by trigger | 3 |
| Kind/unit check | 3 (relaxed; see Plan decisions) |
| P0021 trigger | 3 |
| Assignee limited to status | 3 |
| `properties.housekeeping_sla_minutes` | 1 |
| `room_status_board`: columns, precedence, badges, overdue vs SLA, inactive excluded | 1 (signature), 2 |
| `set_room_status`: roles, P0022, P0030, upsert, ready closes task | 2 (P0022 in 4) |
| `dispatch_housekeeping`: roles, staff-only assignee P0020, P0031, title/description, dirty | 3 |
| `list_dispatchable_staff` | 3 |
| `checkout_booking` → dirty, latest body copied | 4 |
| After-update trigger: done → ready unless out_of_order | 3 |
| Definer allow-list | 1, 3 |
| Isolation rows in 37 | 4 |
| Model (`RoomStatus` label/icon/colour, `fromJson`) and repository (4 methods, `_guard`, P0030/P0031, seam, family provider) | 1, 6 |
| Screen: chips + filter | 5 |
| Screen: responsive grid (2 / 4–6) | 5 |
| Screen: tile contents, not colour alone | 5 |
| Screen: sheet actions with reason and picker | 6 |
| Screen: Occupied not settable, check-in/out links | 6 |
| Screen: accountant read-only | 6 |
| Screen: pull-to-refresh, invalidate after actions | 5, 6 |
| Invalidate after check-in/out | 10 |
| Navigation: staff bar, admin dashboard, owner hub, router matrix | 7, 8 |
| Assigned Work shows unit | 9 |
| Reception warning | 10 |
| Admin dashboard real card | 8 |
| pgTAP list in the spec's Testing section | 1–4 |
| Flutter list in the spec's Testing section | 1, 5–10 |

**2. Placeholder scan:** no "TBD", "TODO" or "similar to Task N". Every code step shows its code, and every SQL test uses literal ids.

**3. Type consistency:**
- `RoomBoardSource.setStatus(String, RoomState, {String? reason})` and `dispatch(String, String, {String? note}) → Future<String>` are used the same way in the repository, the fake, the screen (Task 6) and the tests.
- The fake's call logs are `(String, RoomState, String?)` and `(String, String, String?)`.
- The OUT columns pinned in 39 match `RoomBoardEntry.fromJson`'s keys.
- The P0030/P0031 classes are named `ReasonRequired` and `AlreadyDispatched` everywhere.
- `roomBoardProvider` is `autoDispose.family<…, String>` in every override and watcher.

**4. Review Focus:** each of the five lines has a test in its owning task: 1 in Tasks 3 and 4, 2 in Task 3, 3 in Task 3, 4 in Task 10, 5 in Task 3. Inputs the spec implies that are already covered elsewhere:
- A blank maintenance reason: Task 2 (server) and Task 6 (dialog).
- An assignee from another resort: Tasks 3 and 4.
- An occupied room with a badge: Tasks 2 and 5.
