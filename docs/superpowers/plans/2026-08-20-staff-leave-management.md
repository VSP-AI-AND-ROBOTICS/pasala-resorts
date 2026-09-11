# Staff Leave Management Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a staff/accountant member submit a leave request (date range +
optional reason) and let an admin approve or reject it, with staff seeing
their own request history and current statuses.

**Architecture:** One new table (`leave_requests`) with a `leave_status`
enum, RLS restricting reads to "admin sees all, everyone else sees only
their own row," inserts to "you may only insert your own pending request,"
and updates to admin-only via the same `using(true)` + enforcement-trigger
pattern the sibling Work Schedules feature already established (a plain
RLS `USING` clause on UPDATE silently no-ops for a denied caller instead of
raising an error). The same trigger also pins every column except
`status`/`decided_by`/`decided_at` so an admin's decision can never rewrite
a request's content. Reads use a direct table `select` with a `profiles`
embed (no RPC needed here, unlike Work Schedules — there is no
cross-staff-filter-leak concern to close, since neither screen ever lets a
caller choose someone else's id to filter by). The Flutter side is one
repository (`LeaveRequestRepository`), one admin screen (list + filter +
inline approve/reject, no separate form), and one staff screen (list +
a submit form), mirroring the file/class shapes `staff_shifts_screen.dart`
and `time_slots_screen.dart` already established.

**Tech Stack:** Flutter, Riverpod, Supabase (Postgres + PostgREST), pgTAP
(`supabase test db`).

**Spec:** `docs/superpowers/specs/2026-08-20-staff-leave-management-design.md`

## Global Constraints

- A leave request has exactly one state transition in its lifetime:
  `pending` → `approved` or `pending` → `rejected`. Both are terminal — no
  reversal, no re-deciding (approved design: "Decision finality").
- Staff cannot cancel, withdraw, or edit a submitted request in any way,
  at any status (approved design: "Cancellation").
- No interaction with `staff_shifts` — approving leave never touches,
  flags, or checks the `staff_shifts` table (approved design: "Shifts
  interaction").
- No leave-type categorization — `reason` is a plain optional free-text
  field, no dropdown-backed type enum (approved design: "Leave types").
- No rejection note/reason from admin — a rejected request shows only its
  status (approved design: "Rejection reason").
- Admin's screen defaults to the pending queue, with a filter to see
  everything (approved design: "Admin view").
- The existing hub card/route for Leave Management
  (`staffHubSections` in `lib/features/staff/staff_dashboard_hub_screen.dart`)
  is NOT touched — only what `/staff/leave` renders changes.
- `flutter analyze` and `flutter test` must stay clean at the end, except
  the three pre-existing, unrelated `hold_lifecycle_test.dart` failures
  already present on this branch before this work started.

---

## Task 1: `leave_requests` table, RLS, and the enforcement trigger

**Files:**
- Create: `supabase/migrations/0022_leave_requests.sql`
- Create: `supabase/tests/18_leave_requests_test.sql`

**Interfaces:**
- Produces: enum `public.leave_status` (`'pending'`, `'approved'`,
  `'rejected'`); table `public.leave_requests(id uuid, staff_id uuid,
  start_date date, end_date date, reason text, status leave_status,
  decided_by uuid, decided_at timestamptz, created_at timestamptz)`.

- [ ] **Step 1: Write the failing pgTAP test file**

Fixture ids used below, all seeded by `supabase/seed.sql`:
`10000000-0000-0000-0000-000000000002` (admin@pasala.test, admin),
`10000000-0000-0000-0000-000000000003` (staff@pasala.test, staff),
`10000000-0000-0000-0000-000000000004` (accounts@pasala.test,
accountant). This file's own fixture rows use a `98...` id prefix so they
can't collide with the seed or any other test file's fixtures.

```sql
-- leave_requests + RLS + leave_requests_enforce_admin_decision(), added
-- in 0022_leave_requests.sql to back the staff Leave Management hub
-- section and its admin approve/reject screen. See that migration's
-- header for the decision-finality and no-shift-interaction design
-- decisions.

begin;
select plan(16);

select has_table('public', 'leave_requests', 'leave_requests table exists');
select has_function('public', 'leave_requests_enforce_admin_decision',
  'the enforcement trigger function exists');

-- === insert: staff can request their own leave, nothing else ==============

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"10000000-0000-0000-0000-000000000003","role":"authenticated"}';

select lives_ok(
  $$insert into public.leave_requests (id, staff_id, start_date, end_date, reason)
    values ('98111111-1111-1111-1111-111111111111',
            '10000000-0000-0000-0000-000000000003','2026-09-10','2026-09-12',
            'Family trip')$$,
  'staff can insert their own pending leave request');

select throws_ok(
  $$insert into public.leave_requests (staff_id, start_date, end_date)
    values ('10000000-0000-0000-0000-000000000004','2026-09-15','2026-09-16')$$,
  '42501', null, 'staff cannot insert a leave request for someone else');

select throws_ok(
  $$insert into public.leave_requests (staff_id, start_date, end_date, status)
    values ('10000000-0000-0000-0000-000000000003','2026-09-20','2026-09-21',
            'approved')$$,
  '42501', null, 'staff cannot insert a request that is already approved');

-- === the date-order check constraint =======================================

select throws_ok(
  $$insert into public.leave_requests (staff_id, start_date, end_date)
    values ('10000000-0000-0000-0000-000000000003','2026-09-20','2026-09-10')$$,
  '23514', null, 'end_date before start_date is rejected');

-- === select: own rows only for staff, everything for admin =================

select is(
  (select count(*)::int from public.leave_requests),
  1,
  'a staff member sees only their own leave request via direct select');

set local request.jwt.claims to
  '{"sub":"10000000-0000-0000-0000-000000000004","role":"authenticated"}';

select lives_ok(
  $$insert into public.leave_requests (id, staff_id, start_date, end_date)
    values ('98222222-2222-2222-2222-222222222222',
            '10000000-0000-0000-0000-000000000004','2026-09-18','2026-09-18')$$,
  'an accountant can also insert their own pending leave request');

set local request.jwt.claims to
  '{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}';

select is(
  (select count(*)::int from public.leave_requests),
  2,
  'admin sees every leave request via direct select');

-- === update: admin-only, decision fields only ==============================

select lives_ok(
  $$update public.leave_requests
      set status = 'approved', decided_by = '10000000-0000-0000-0000-000000000002',
          decided_at = now()
    where id = '98111111-1111-1111-1111-111111111111'$$,
  'admin can approve a pending request');

reset role;
select is(
  (select status from public.leave_requests
    where id = '98111111-1111-1111-1111-111111111111'),
  'approved'::public.leave_status,
  'the approval is visible directly on the table');

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}';

select throws_ok(
  $$update public.leave_requests set reason = 'rewritten'
    where id = '98222222-2222-2222-2222-222222222222'$$,
  '42501', null,
  'admin cannot change a request''s content (reason) through an update -- '
  'only status/decided_by/decided_at may change');

set local request.jwt.claims to
  '{"sub":"10000000-0000-0000-0000-000000000003","role":"authenticated"}';

select throws_ok(
  $$update public.leave_requests set status = 'approved'
    where id = '98111111-1111-1111-1111-111111111111'$$,
  '42501', null, 'a staff member cannot approve their own request');

-- === delete: nobody, not even admin =========================================

set local request.jwt.claims to
  '{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}';

select throws_ok(
  $$delete from public.leave_requests where id = '98222222-2222-2222-2222-222222222222'$$,
  '42501', null, 'not even admin can delete a leave request -- no delete grant exists');

-- === anon: no access at all =================================================

reset role;
set local role anon;
set local request.jwt.claims to '{"role":"anon"}';

select throws_ok(
  $$select * from public.leave_requests$$,
  '42501', null, 'anon cannot select leave_requests');

select throws_ok(
  $$insert into public.leave_requests (staff_id, start_date, end_date)
    values ('10000000-0000-0000-0000-000000000003','2026-10-01','2026-10-02')$$,
  '42501', null, 'anon cannot insert into leave_requests');

select * from finish();
rollback;
```

That file has 16 assertions total: `has_table`, `has_function`, 3
`lives_ok`, 9 `throws_ok`, 2 `is` — matching `select plan(16);` at the top.

- [ ] **Step 2: Run the test file to verify it fails**

Run: `supabase test db`
Expected: FAIL — `leave_requests` table and
`leave_requests_enforce_admin_decision` function do not exist yet.

- [ ] **Step 3: Write the migration**

```sql
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
-- needed here for a clear error on denial.
create policy leave_requests_own_insert on public.leave_requests
  for insert to authenticated
  with check (staff_id = auth.uid() and status = 'pending');

-- `using (true)`, not `using (public.is_admin())`: a restrictive USING
-- clause here would let RLS silently exclude a denied caller's target
-- row before the trigger below ever runs, producing a silent
-- zero-rows-affected "success" instead of a clear 42501 -- the exact
-- problem `staff_shifts_admin_update` in 0021_staff_shifts.sql already
-- solved the same way. Enforcement is entirely the trigger's job.
create policy leave_requests_admin_update on public.leave_requests
  for update to authenticated
  using (true);

-- Enforces two things a plain RLS policy cannot express on its own:
-- (1) only admin may update a leave_requests row at all, and (2) even an
-- admin's update may only change status/decided_by/decided_at -- never
-- staff_id, the dates, or the reason. RLS policies compare a proposed
-- NEW row against a boolean expression; they have no OLD/NEW column
-- comparison the way a trigger does, so "only these three columns may
-- change" can only be expressed here.
create function public.leave_requests_enforce_admin_decision()
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

  return new;
end;
$$;

create trigger leave_requests_enforce_admin_decision_trigger
  before update on public.leave_requests
  for each row execute function public.leave_requests_enforce_admin_decision();
```

- [ ] **Step 4: Reset the local database and run the test file to verify it passes**

Run: `supabase db reset && supabase test db`
Expected: `supabase db reset` applies the new migration cleanly. `supabase
test db` then runs every file under `supabase/tests/` (18 files after this
task), including the new one, and reports all assertions passing — every
pre-existing file must stay green (this migration adds a table; it does
not touch anything they cover).

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/0022_leave_requests.sql supabase/tests/18_leave_requests_test.sql
git commit -m "feat(db): add leave_requests table, RLS, and admin-decision trigger"
```

---

## Task 2: `LeaveRequest` Dart model

**Files:**
- Create: `lib/data/models/leave_request.dart`
- Test: `test/data/leave_request_test.dart`

**Interfaces:**
- Produces: `enum LeaveStatus { pending, approved, rejected }`,
  `leaveStatusFromDb(String)`, `leaveStatusToDb(LeaveStatus)`; `class
  LeaveRequest` with fields `id, staffId, staffName, startDate, endDate,
  reason, status, decidedBy, decidedAt, createdAt`;
  `LeaveRequest.fromJson(Map<String, dynamic>)` (handles a row with or
  without an embedded `profiles` object — present when the repository's
  `list()` joins it, absent from a bare insert/update response);
  `.toInsert()` (payload for a new request: `staff_id`, `start_date`,
  `end_date`, `reason` only — never `id`, `status`, `decided_by`,
  `decided_at`, or `staff_name`, all of which are either server-assigned
  or read-only).

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/data/models/leave_request.dart';

void main() {
  group('leaveStatusFromDb / leaveStatusToDb', () {
    test('round-trips all three values', () {
      for (final status in LeaveStatus.values) {
        expect(leaveStatusFromDb(leaveStatusToDb(status)), status);
      }
    });
  });

  group('LeaveRequest.fromJson', () {
    test('parses a plain table row (no embedded profiles)', () {
      final request = LeaveRequest.fromJson(const {
        'id': 'l1',
        'staff_id': 'u1',
        'start_date': '2026-09-10',
        'end_date': '2026-09-12',
        'reason': 'Family trip',
        'status': 'pending',
        'decided_by': null,
        'decided_at': null,
        'created_at': '2026-08-20T10:00:00Z',
      });

      expect(request.id, 'l1');
      expect(request.staffId, 'u1');
      expect(request.staffName, isNull);
      expect(request.startDate, DateTime.parse('2026-09-10'));
      expect(request.endDate, DateTime.parse('2026-09-12'));
      expect(request.reason, 'Family trip');
      expect(request.status, LeaveStatus.pending);
      expect(request.decidedBy, isNull);
      expect(request.decidedAt, isNull);
    });

    test('parses a row with an embedded profiles object, including '
        'staff_name and a decided request', () {
      final request = LeaveRequest.fromJson(const {
        'id': 'l2',
        'staff_id': 'u2',
        'profiles': {'full_name': 'Sita Staff'},
        'start_date': '2026-09-18',
        'end_date': '2026-09-18',
        'reason': null,
        'status': 'approved',
        'decided_by': 'admin-1',
        'decided_at': '2026-08-21T09:00:00Z',
        'created_at': '2026-08-20T10:00:00Z',
      });

      expect(request.staffName, 'Sita Staff');
      expect(request.status, LeaveStatus.approved);
      expect(request.decidedBy, 'admin-1');
      expect(request.decidedAt, DateTime.parse('2026-08-21T09:00:00Z'));
    });
  });

  test('toInsert never includes id, status, decided_by, decided_at, or '
      'staff_name', () {
    final request = LeaveRequest.fromJson(const {
      'id': 'l1',
      'staff_id': 'u1',
      'profiles': {'full_name': 'Sita Staff'},
      'start_date': '2026-09-10',
      'end_date': '2026-09-12',
      'reason': 'Family trip',
      'status': 'pending',
      'decided_by': null,
      'decided_at': null,
      'created_at': '2026-08-20T10:00:00Z',
    });

    final payload = request.toInsert();
    expect(payload.keys.toSet(),
        {'staff_id', 'start_date', 'end_date', 'reason'});
    expect(payload['staff_id'], 'u1');
    expect(payload['start_date'], '2026-09-10');
    expect(payload['end_date'], '2026-09-12');
    expect(payload['reason'], 'Family trip');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/leave_request_test.dart`
Expected: FAIL — `lib/data/models/leave_request.dart` does not exist yet.

- [ ] **Step 3: Write the model**

```dart
enum LeaveStatus { pending, approved, rejected }

LeaveStatus leaveStatusFromDb(String raw) => switch (raw) {
      'pending' => LeaveStatus.pending,
      'approved' => LeaveStatus.approved,
      'rejected' => LeaveStatus.rejected,
      _ => throw ArgumentError('unknown leave status $raw'),
    };

String leaveStatusToDb(LeaveStatus status) => switch (status) {
      LeaveStatus.pending => 'pending',
      LeaveStatus.approved => 'approved',
      LeaveStatus.rejected => 'rejected',
    };

/// One staff/accountant member's leave request. [staffName] is populated
/// only when the row came with an embedded `profiles` object (the
/// repository's `list()` always joins it; a bare insert/update response
/// does not) -- `null` is never treated as an error, just "no name on
/// this particular response."
class LeaveRequest {
  const LeaveRequest({
    required this.id,
    required this.staffId,
    required this.startDate,
    required this.endDate,
    required this.status,
    this.staffName,
    this.reason,
    this.decidedBy,
    this.decidedAt,
    this.createdAt,
  });

  final String id;
  final String staffId;
  final String? staffName;
  final DateTime startDate;
  final DateTime endDate;
  final String? reason;
  final LeaveStatus status;
  final String? decidedBy;
  final DateTime? decidedAt;
  final DateTime? createdAt;

  factory LeaveRequest.fromJson(Map<String, dynamic> json) => LeaveRequest(
        id: json['id'] as String,
        staffId: json['staff_id'] as String,
        staffName: (json['profiles'] as Map<String, dynamic>?)?['full_name']
            as String?,
        startDate: DateTime.parse(json['start_date'] as String),
        endDate: DateTime.parse(json['end_date'] as String),
        reason: json['reason'] as String?,
        status: leaveStatusFromDb(json['status'] as String),
        decidedBy: json['decided_by'] as String?,
        decidedAt: json['decided_at'] == null
            ? null
            : DateTime.parse(json['decided_at'] as String),
        createdAt: json['created_at'] == null
            ? null
            : DateTime.parse(json['created_at'] as String),
      );

  /// Payload for a new request -- deliberately excludes `id`
  /// (server-assigned), `status` (server defaults to `pending`;
  /// `leave_requests_own_insert`'s `with check` requires it stay that
  /// way on insert), `decided_by`/`decided_at` (set only by
  /// [LeaveRequestRepository.decide]), and `staff_name` (a read-only
  /// join result, not a column).
  Map<String, dynamic> toInsert() => {
        'staff_id': staffId,
        'start_date': startDate.toIso8601String().substring(0, 10),
        'end_date': endDate.toIso8601String().substring(0, 10),
        'reason': reason,
      };
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/data/leave_request_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/data/models/leave_request.dart test/data/leave_request_test.dart
git commit -m "feat(model): add LeaveRequest model"
```

---

## Task 3: `LeaveRequestRepository`

**Files:**
- Create: `lib/data/repositories/leave_request_repository.dart`

**Interfaces:**
- Consumes: `LeaveRequest`, `LeaveRequest.fromJson`,
  `LeaveRequest.toInsert`, `LeaveStatus`, `leaveStatusToDb` (Task 2);
  `supabaseProvider` (`lib/core/supabase_client.dart`); `mapPostgrestError`
  (`lib/core/errors.dart`).
- Produces: `class LeaveRequestRepository` with methods `list({String?
  staffId, LeaveStatus? status}) -> Future<List<LeaveRequest>>`,
  `create({required String staffId, required DateTimeRange range, String?
  reason}) -> Future<void>`, `decide({required String id, required bool
  approved}) -> Future<void>`; providers `leaveRequestRepositoryProvider`
  (`Provider<LeaveRequestRepository>`) and `leaveRequestsProvider`
  (`FutureProvider.family<List<LeaveRequest>, LeaveRequestFilter>`), plus
  `typedef LeaveRequestFilter = ({String? staffId, LeaveStatus? status})`
  that Tasks 4-5 watch.

This repository has no dedicated unit-test file, matching this codebase's
established convention for simple CRUD repositories (`RateRepository`,
`StaffShiftRepository` — neither has one; their behaviour is exercised
through screen tests using a fake). Tasks 4-5 do the same here with a
`FakeLeaveRequestRepository`. This task's own verification is `flutter
analyze`.

- [ ] **Step 1: Write the repository**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors.dart';
import '../../core/supabase_client.dart';
import '../models/leave_request.dart';

/// The (staff, status) an admin or staff screen wants to see -- `staffId:
/// null` means "every staff member" (admin only; RLS returns only the
/// caller's own rows for anyone else regardless), `status: null` means
/// "every status." A record, not positional params, so
/// `FutureProvider.family` can key on it directly.
typedef LeaveRequestFilter = ({String? staffId, LeaveStatus? status});

class LeaveRequestRepository {
  LeaveRequestRepository(this._db);
  final SupabaseClient _db;

  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } catch (e) {
      throw mapPostgrestError(e);
    }
  }

  String _dateOnly(DateTime d) => d.toIso8601String().substring(0, 10);

  /// A direct table select with a `profiles` embed for `staff_name` --
  /// unlike Work Schedules' `list_staff_shifts()` RPC, no RPC is needed
  /// here: neither this method nor either screen ever lets a caller pick
  /// someone else's id to filter by (staff/accountant screens always pass
  /// their own id, admin passes whatever it likes since it can already
  /// see everything), so there is no filter-based leak for an RPC to
  /// close that plain RLS doesn't already close on its own.
  Future<List<LeaveRequest>> list({
    String? staffId,
    LeaveStatus? status,
  }) =>
      _guard(() async {
        dynamic query = _db.from('leave_requests').select('*, profiles(full_name)');
        if (staffId != null) query = query.eq('staff_id', staffId);
        if (status != null) query = query.eq('status', leaveStatusToDb(status));
        final rows = await query.order('created_at', ascending: false) as List;
        return rows
            .map((e) => LeaveRequest.fromJson(e as Map<String, dynamic>))
            .toList();
      });

  /// Submits one new request, always `pending` (the server column default
  /// and `leave_requests_own_insert`'s `with check` both enforce this --
  /// the client never sends a `status`).
  Future<void> create({
    required String staffId,
    required DateTimeRange range,
    String? reason,
  }) =>
      _guard(() async {
        await _db.from('leave_requests').insert({
          'staff_id': staffId,
          'start_date': _dateOnly(range.start),
          'end_date': _dateOnly(range.end),
          'reason': reason,
        });
      });

  /// Records an admin's decision. [decided_by] is the CALLING admin's own
  /// id (only an admin can reach this method's RLS-gated update path at
  /// all) -- set client-side, unlike `staff_shifts.created_by`'s
  /// `default auth.uid()`, because this single call must set `status` and
  /// `decided_by` together, and a column `default` only applies on
  /// insert, never on update.
  Future<void> decide({
    required String id,
    required bool approved,
  }) =>
      _guard(() async {
        final adminId = _db.auth.currentUser!.id;
        await _db.from('leave_requests').update({
          'status': leaveStatusToDb(approved ? LeaveStatus.approved : LeaveStatus.rejected),
          'decided_by': adminId,
          'decided_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('id', id);
      });
}

final leaveRequestRepositoryProvider = Provider<LeaveRequestRepository>(
  (ref) => LeaveRequestRepository(ref.watch(supabaseProvider)),
);

final leaveRequestsProvider =
    FutureProvider.family<List<LeaveRequest>, LeaveRequestFilter>(
  (ref, filter) => ref.watch(leaveRequestRepositoryProvider).list(
        staffId: filter.staffId,
        status: filter.status,
      ),
);
```

- [ ] **Step 2: Run `flutter analyze` to verify it compiles cleanly**

Run: `flutter analyze`
Expected: "No issues found!"

- [ ] **Step 3: Commit**

```bash
git add lib/data/repositories/leave_request_repository.dart
git commit -m "feat(repo): add LeaveRequestRepository"
```

---

## Task 4: Admin "Leave requests" screen

**Files:**
- Create: `lib/features/admin/leave_requests_screen.dart`
- Test: `test/features/admin/leave_requests_screen_test.dart`
- Modify: `lib/core/router.dart` — add the `/admin/leave-requests` route
- Modify: `lib/features/admin/admin_home_screen.dart` — add a destination
  entry linking to it

**Interfaces:**
- Consumes: `LeaveRequest`, `LeaveRequestRepository`,
  `leaveRequestRepositoryProvider`, `leaveRequestsProvider`,
  `LeaveRequestFilter`, `LeaveStatus` (Tasks 2-3); `AdminProfile`,
  `adminProfilesProvider` (`lib/data/repositories/user_admin_repository.dart`,
  already exists); `UserRole` (`lib/data/models/app_user.dart`, already
  exists).
- Produces: `class LeaveRequestsScreen`.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/data/models/admin_profile.dart';
import 'package:pasala/data/models/app_user.dart';
import 'package:pasala/data/models/leave_request.dart';
import 'package:pasala/data/repositories/leave_request_repository.dart';
import 'package:pasala/data/repositories/user_admin_repository.dart';
import 'package:pasala/features/admin/leave_requests_screen.dart';

/// In-memory stand-in for [LeaveRequestRepository], mirroring
/// `FakeStaffShiftRepository` in `staff_shifts_screen_test.dart`.
class FakeLeaveRequestRepository implements LeaveRequestRepository {
  final List<LeaveRequest> store = [];
  final List<String> decidedIds = [];

  @override
  Future<List<LeaveRequest>> list({
    String? staffId,
    LeaveStatus? status,
  }) async =>
      store.where((r) {
        if (staffId != null && r.staffId != staffId) return false;
        if (status != null && r.status != status) return false;
        return true;
      }).toList();

  @override
  Future<void> create({
    required String staffId,
    required DateTimeRange range,
    String? reason,
  }) async {
    throw UnimplementedError('admin never creates a leave request');
  }

  @override
  Future<void> decide({required String id, required bool approved}) async {
    decidedIds.add(id);
    final index = store.indexWhere((r) => r.id == id);
    final existing = store[index];
    store[index] = LeaveRequest(
      id: existing.id,
      staffId: existing.staffId,
      staffName: existing.staffName,
      startDate: existing.startDate,
      endDate: existing.endDate,
      reason: existing.reason,
      status: approved ? LeaveStatus.approved : LeaveStatus.rejected,
      decidedBy: 'admin-1',
      decidedAt: DateTime(2026, 8, 20),
    );
  }
}

const _staffProfile = AdminProfile(
  id: 'staff-1',
  email: 'staff@pasala.test',
  role: UserRole.staff,
  fullName: 'Sita Staff',
  createdAt: null,
);

Widget _appFor(FakeLeaveRequestRepository repo) => ProviderScope(
      overrides: [
        leaveRequestRepositoryProvider.overrideWithValue(repo),
        adminProfilesProvider.overrideWith((ref) async => const [_staffProfile]),
      ],
      child: const MaterialApp(home: LeaveRequestsScreen()),
    );

void main() {
  testWidgets('defaults to showing only pending requests', (tester) async {
    final repo = FakeLeaveRequestRepository()
      ..store.addAll([
        LeaveRequest(
          id: 'l1',
          staffId: 'staff-1',
          staffName: 'Sita Staff',
          startDate: DateTime(2026, 9, 10),
          endDate: DateTime(2026, 9, 12),
          status: LeaveStatus.pending,
        ),
        LeaveRequest(
          id: 'l2',
          staffId: 'staff-1',
          staffName: 'Sita Staff',
          startDate: DateTime(2026, 8, 1),
          endDate: DateTime(2026, 8, 2),
          status: LeaveStatus.approved,
        ),
      ]);

    await tester.pumpWidget(_appFor(repo));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('leave-row-l1')), findsOneWidget);
    expect(find.byKey(const Key('leave-row-l2')), findsNothing);
  });

  testWidgets('shows an empty state when there are no pending requests', (
    tester,
  ) async {
    await tester.pumpWidget(_appFor(FakeLeaveRequestRepository()));
    await tester.pumpAndSettle();

    expect(find.text('No pending requests'), findsOneWidget);
  });

  testWidgets('approving a pending request calls decide(approved: true) '
      'and it disappears from the pending view', (tester) async {
    final repo = FakeLeaveRequestRepository()
      ..store.add(LeaveRequest(
        id: 'l1',
        staffId: 'staff-1',
        staffName: 'Sita Staff',
        startDate: DateTime(2026, 9, 10),
        endDate: DateTime(2026, 9, 12),
        status: LeaveStatus.pending,
      ));

    await tester.pumpWidget(_appFor(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('approve-l1')));
    await tester.pumpAndSettle();

    expect(repo.decidedIds, ['l1']);
    expect(find.byKey(const Key('leave-row-l1')), findsNothing);
  });

  testWidgets('switching the status filter to All shows a decided request',
      (tester) async {
    final repo = FakeLeaveRequestRepository()
      ..store.add(LeaveRequest(
        id: 'l2',
        staffId: 'staff-1',
        staffName: 'Sita Staff',
        startDate: DateTime(2026, 8, 1),
        endDate: DateTime(2026, 8, 2),
        status: LeaveStatus.approved,
      ));

    await tester.pumpWidget(_appFor(repo));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('leave-row-l2')), findsNothing);

    await tester.tap(find.byKey(const Key('leave-status-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('All').last);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('leave-row-l2')), findsOneWidget);
  });
}
```

This test file has four `testWidgets` blocks in total.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/admin/leave_requests_screen_test.dart`
Expected: FAIL — `lib/features/admin/leave_requests_screen.dart` does not
exist yet.

- [ ] **Step 3: Write the screen**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/errors.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/failure_view.dart';
import '../../data/models/app_user.dart';
import '../../data/models/leave_request.dart';
import '../../data/repositories/leave_request_repository.dart';
import '../../data/repositories/user_admin_repository.dart';

final _dateFormat = DateFormat('d MMM yyyy');

String _statusLabel(LeaveStatus status) => switch (status) {
      LeaveStatus.pending => 'Pending',
      LeaveStatus.approved => 'Approved',
      LeaveStatus.rejected => 'Rejected',
    };

/// `/admin/leave-requests` -- admin-only (a write action, not the
/// staff-or-above carve-out `/admin/dashboard`/`/admin/reports` get).
/// Defaults to the pending queue (per the approved design); a status
/// filter switches to seeing everything.
class LeaveRequestsScreen extends ConsumerStatefulWidget {
  const LeaveRequestsScreen({super.key});

  @override
  ConsumerState<LeaveRequestsScreen> createState() => _LeaveRequestsScreenState();
}

class _LeaveRequestsScreenState extends ConsumerState<LeaveRequestsScreen> {
  String? _staffId;
  LeaveStatus? _statusFilter = LeaveStatus.pending;

  @override
  Widget build(BuildContext context) {
    final filter = (staffId: _staffId, status: _statusFilter);
    final requests = ref.watch(leaveRequestsProvider(filter));
    final profiles = ref.watch(adminProfilesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Leave requests')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(Spacing.md),
            child: Row(
              children: [
                Expanded(
                  child: profiles.when(
                    loading: () => const SizedBox.shrink(),
                    error: (_, _) => const SizedBox.shrink(),
                    data: (list) {
                      final staffOrAbove =
                          list.where((p) => p.role != UserRole.customer).toList();
                      return DropdownButtonFormField<String?>(
                        key: const Key('leave-staff-picker'),
                        initialValue: _staffId,
                        decoration: const InputDecoration(labelText: 'Staff member'),
                        items: [
                          const DropdownMenuItem(value: null, child: Text('All staff')),
                          for (final p in staffOrAbove)
                            DropdownMenuItem(
                              value: p.id,
                              child: Text(p.fullName ?? p.email),
                            ),
                        ],
                        onChanged: (value) => setState(() => _staffId = value),
                      );
                    },
                  ),
                ),
                const SizedBox(width: Spacing.sm),
                Expanded(
                  child: DropdownButtonFormField<LeaveStatus?>(
                    key: const Key('leave-status-filter'),
                    initialValue: _statusFilter,
                    decoration: const InputDecoration(labelText: 'Status'),
                    items: const [
                      DropdownMenuItem(value: null, child: Text('All')),
                      DropdownMenuItem(
                        value: LeaveStatus.pending,
                        child: Text('Pending'),
                      ),
                      DropdownMenuItem(
                        value: LeaveStatus.approved,
                        child: Text('Approved'),
                      ),
                      DropdownMenuItem(
                        value: LeaveStatus.rejected,
                        child: Text('Rejected'),
                      ),
                    ],
                    onChanged: (value) => setState(() => _statusFilter = value),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: AsyncView(
              value: requests,
              onRetry: () => ref.invalidate(leaveRequestsProvider(filter)),
              empty: () => EmptyState(
                icon: Icons.event_busy_outlined,
                title: _statusFilter == LeaveStatus.pending
                    ? 'No pending requests'
                    : 'No leave requests',
                message: _statusFilter == LeaveStatus.pending
                    ? 'Nothing needs a decision right now.'
                    : 'No requests match this filter.',
              ),
              data: (list) => ListView(
                children: [
                  for (final request in list)
                    Padding(
                      key: Key('leave-row-${request.id}'),
                      padding: const EdgeInsets.symmetric(
                        horizontal: Spacing.md,
                        vertical: Spacing.xs,
                      ),
                      child: Card(
                        child: ListTile(
                          title: Text(request.staffName ?? request.staffId),
                          subtitle: Text(
                            [
                              '${_dateFormat.format(request.startDate)} – '
                                  '${_dateFormat.format(request.endDate)}',
                              if (request.reason != null &&
                                  request.reason!.isNotEmpty)
                                request.reason!,
                              _statusLabel(request.status),
                            ].join(' · '),
                          ),
                          trailing: request.status == LeaveStatus.pending
                              ? Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      key: Key('approve-${request.id}'),
                                      icon: const Icon(Icons.check_circle_outline),
                                      tooltip: 'Approve',
                                      onPressed: () =>
                                          _decide(filter, request, approved: true),
                                    ),
                                    IconButton(
                                      key: Key('reject-${request.id}'),
                                      icon: const Icon(Icons.cancel_outlined),
                                      tooltip: 'Reject',
                                      onPressed: () =>
                                          _decide(filter, request, approved: false),
                                    ),
                                  ],
                                )
                              : null,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _decide(
    LeaveRequestFilter filter,
    LeaveRequest request, {
    required bool approved,
  }) async {
    try {
      await ref
          .read(leaveRequestRepositoryProvider)
          .decide(id: request.id, approved: approved);
      ref.invalidate(leaveRequestsProvider(filter));
    } on BookingFailure catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(FailureView.messageFor(e))));
      }
    }
  }
}
```

- [ ] **Step 4: Wire the route and the admin-home link**

In `lib/core/router.dart`, add the import and the route (admin-only,
placed alongside the other `/admin/*` `GoRoute` entries, e.g. right after
`/admin/staff-shifts`):

```dart
import '../features/admin/leave_requests_screen.dart';
```

```dart
          GoRoute(
            path: '/admin/leave-requests',
            builder: (_, _) => const LeaveRequestsScreen(),
          ),
```

In `lib/features/admin/admin_home_screen.dart`, add a new destination
tuple to `_destinations`, after the `'Staff shifts'` entry:

```dart
    (
      icon: Icons.event_available_outlined,
      title: 'Leave requests',
      subtitle: 'Review and decide staff leave requests',
      path: '/admin/leave-requests',
    ),
```

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/features/admin/leave_requests_screen_test.dart`
Expected: PASS (4 tests). Then run `flutter analyze` — expect "No issues
found!"

- [ ] **Step 6: Commit**

```bash
git add lib/features/admin/leave_requests_screen.dart lib/core/router.dart \
  lib/features/admin/admin_home_screen.dart \
  test/features/admin/leave_requests_screen_test.dart
git commit -m "feat(admin): add Leave requests screen (approve/reject)"
```

---

## Task 5: Staff Leave screen (list + submit)

**Files:**
- Create: `lib/features/staff/leave_screen.dart`
- Test: `test/features/staff/leave_screen_test.dart`
- Modify: `lib/core/router.dart` — replace the `PlaceholderSectionScreen`
  builder for `/staff/leave` with `LeaveScreen`

**Interfaces:**
- Consumes: `LeaveRequest`, `leaveRequestsProvider`,
  `leaveRequestRepositoryProvider`, `LeaveRequestFilter`, `LeaveStatus`
  (Tasks 2-3); `currentUserProvider`
  (`lib/data/repositories/auth_repository.dart`, already used identically
  by `TimeSlotsScreen`).
- Produces: `class LeaveScreen`, `class LeaveRequestFormScreen`.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/errors.dart';
import 'package:pasala/data/models/app_user.dart';
import 'package:pasala/data/models/leave_request.dart';
import 'package:pasala/data/repositories/auth_repository.dart';
import 'package:pasala/data/repositories/leave_request_repository.dart';
import 'package:pasala/features/staff/leave_screen.dart';

const _staff = AppUser(id: 'staff-1', email: 'staff@pasala.test', role: UserRole.staff);

/// In-memory stand-in for [LeaveRequestRepository], mirroring
/// `FakeStaffShiftRepository`.
class FakeLeaveRequestRepository implements LeaveRequestRepository {
  final List<LeaveRequest> store = [];
  final List<Map<String, dynamic>> createCalls = [];
  int _idCounter = 0;
  BookingFailure? createFailure;

  @override
  Future<List<LeaveRequest>> list({
    String? staffId,
    LeaveStatus? status,
  }) async =>
      store.where((r) {
        if (staffId != null && r.staffId != staffId) return false;
        if (status != null && r.status != status) return false;
        return true;
      }).toList();

  @override
  Future<void> create({
    required String staffId,
    required DateTimeRange range,
    String? reason,
  }) async {
    createCalls.add({'staffId': staffId, 'range': range, 'reason': reason});
    final failure = createFailure;
    if (failure != null) throw failure;
    store.add(LeaveRequest(
      id: 'leave-${_idCounter++}',
      staffId: staffId,
      startDate: range.start,
      endDate: range.end,
      reason: reason,
      status: LeaveStatus.pending,
    ));
  }

  @override
  Future<void> decide({required String id, required bool approved}) async {
    throw UnimplementedError('staff never decides a leave request');
  }
}

Widget _appFor(FakeLeaveRequestRepository repo) => ProviderScope(
      overrides: [
        currentUserProvider.overrideWith((ref) => Stream.value(_staff)),
        leaveRequestRepositoryProvider.overrideWithValue(repo),
      ],
      child: const MaterialApp(home: LeaveScreen()),
    );

void main() {
  testWidgets('shows an empty state when the staff member has no requests',
      (tester) async {
    await tester.pumpWidget(_appFor(FakeLeaveRequestRepository()));
    await tester.pumpAndSettle();

    expect(find.text('No leave requests yet'), findsOneWidget);
  });

  testWidgets('lists an existing request with its date range, reason, and '
      'status', (tester) async {
    final repo = FakeLeaveRequestRepository()
      ..store.add(LeaveRequest(
        id: 'l1',
        staffId: 'staff-1',
        startDate: DateTime(2026, 9, 10),
        endDate: DateTime(2026, 9, 12),
        reason: 'Family trip',
        status: LeaveStatus.pending,
      ));

    await tester.pumpWidget(_appFor(repo));
    await tester.pumpAndSettle();

    expect(find.text('Family trip'), findsOneWidget);
    expect(find.text('Pending'), findsOneWidget);
  });

  testWidgets('the FAB opens the submit-leave form', (tester) async {
    await tester.pumpWidget(_appFor(FakeLeaveRequestRepository()));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    expect(find.text('Request leave'), findsOneWidget);
    expect(find.byKey(const Key('leave-form-reason')), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/staff/leave_screen_test.dart`
Expected: FAIL — `lib/features/staff/leave_screen.dart` does not exist
yet.

- [ ] **Step 3: Write the screen**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/errors.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/failure_view.dart';
import '../../data/models/leave_request.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/leave_request_repository.dart';

final _dateFormat = DateFormat('d MMM yyyy');

String _statusLabel(LeaveStatus status) => switch (status) {
      LeaveStatus.pending => 'Pending',
      LeaveStatus.approved => 'Approved',
      LeaveStatus.rejected => 'Rejected',
    };

/// The status chip's tint -- pending reads as a neutral "awaiting a
/// decision" tone, approved as the brand colour, rejected as
/// muted/negative. Mirrors `BookingTile._statusColors`'s convention in
/// `my_bookings_screen.dart`.
(Color background, Color foreground) _statusColors(
  ColorScheme scheme,
  LeaveStatus status,
) =>
    switch (status) {
      LeaveStatus.pending => (scheme.tertiaryContainer, scheme.onTertiaryContainer),
      LeaveStatus.approved => (scheme.primaryContainer, scheme.onPrimaryContainer),
      LeaveStatus.rejected => (scheme.surfaceContainerHigh, scheme.onSurfaceVariant),
    };

/// `/staff/leave` -- the signed-in staff/accountant member's own leave
/// requests, newest first, with a form to submit a new one. No edit, no
/// cancel, no delete -- a submitted request is immutable from the staff
/// side (see the design spec's "Cancellation" decision).
class LeaveScreen extends ConsumerWidget {
  const LeaveScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider).value;
    final staffId = user?.id;
    final filter = (staffId: staffId, status: null);
    final requestsAsync = staffId == null
        ? AsyncValue<List<LeaveRequest>>.data(const [])
        : ref.watch(leaveRequestsProvider(filter));

    return Scaffold(
      appBar: AppBar(title: const Text('Leave Management')),
      body: AsyncView(
        value: requestsAsync,
        onRetry:
            staffId == null ? null : () => ref.invalidate(leaveRequestsProvider(filter)),
        empty: () => const EmptyState(
          icon: Icons.event_busy_outlined,
          title: 'No leave requests yet',
          message: 'Tap + to request time off.',
        ),
        data: (list) {
          final scheme = Theme.of(context).colorScheme;
          final sorted = [...list]
            ..sort((a, b) => b.startDate.compareTo(a.startDate));
          return ListView(
            padding: const EdgeInsets.all(Spacing.md),
            children: [
              for (final request in sorted)
                Card(
                  child: ListTile(
                    title: Text(
                      '${_dateFormat.format(request.startDate)} – '
                      '${_dateFormat.format(request.endDate)}',
                    ),
                    subtitle: request.reason != null && request.reason!.isNotEmpty
                        ? Text(request.reason!)
                        : null,
                    trailing: Builder(
                      builder: (context) {
                        final (background, foreground) =
                            _statusColors(scheme, request.status);
                        return Chip(
                          label: Text(_statusLabel(request.status)),
                          labelStyle: TextStyle(color: foreground),
                          backgroundColor: background,
                          side: BorderSide.none,
                        );
                      },
                    ),
                  ),
                ),
            ],
          );
        },
      ),
      floatingActionButton: staffId == null
          ? null
          : FloatingActionButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => LeaveRequestFormScreen(staffId: staffId),
                ),
              ),
              child: const Icon(Icons.add),
            ),
    );
  }
}

/// Submit-leave form. Always creates a new request via
/// [LeaveRequestRepository.create] -- there is no edit mode, since a
/// submitted request can never be changed by the staff member who made
/// it.
class LeaveRequestFormScreen extends ConsumerStatefulWidget {
  const LeaveRequestFormScreen({super.key, required this.staffId});

  final String staffId;

  @override
  ConsumerState<LeaveRequestFormScreen> createState() =>
      _LeaveRequestFormScreenState();
}

class _LeaveRequestFormScreenState extends ConsumerState<LeaveRequestFormScreen> {
  final _reason = TextEditingController();
  DateTimeRange? _range;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showDateRangePicker(
      context: context,
      firstDate: today,
      lastDate: DateTime(today.year + 2),
      initialDateRange: _range,
    );
    if (picked != null) setState(() => _range = picked);
  }

  Future<void> _submit() async {
    final range = _range;
    if (range == null) {
      setState(() => _error = 'Pick a date range.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final reason = _reason.text.trim();
      await ref.read(leaveRequestRepositoryProvider).create(
            staffId: widget.staffId,
            range: range,
            reason: reason.isEmpty ? null : reason,
          );
      ref.invalidate(leaveRequestsProvider);
      if (mounted) Navigator.of(context).pop();
    } on BookingFailure catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(FailureView.messageFor(e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Request leave')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(Spacing.lg),
              children: [
                ListTile(
                  key: const Key('leave-form-date-range'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Date range'),
                  subtitle: Text(
                    _range == null
                        ? 'Required'
                        : '${_dateFormat.format(_range!.start)} – '
                            '${_dateFormat.format(_range!.end)}',
                  ),
                  onTap: _pickRange,
                ),
                const SizedBox(height: Spacing.sm),
                TextField(
                  key: const Key('leave-form-reason'),
                  controller: _reason,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Reason',
                    helperText: 'Optional',
                  ),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: Spacing.sm),
                    child: Text(
                      _error!,
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ),
                const SizedBox(height: Spacing.lg),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: const Text('Submit'),
                ),
              ],
            ),
          ),
        ),
      );
}
```

- [ ] **Step 4: Wire the route**

In `lib/core/router.dart`, replace the existing `/staff/leave` `GoRoute`
(currently a `PlaceholderSectionScreen`) with:

```dart
          GoRoute(
            path: '/staff/leave',
            builder: (_, _) => const LeaveScreen(),
          ),
```

Add the import:

```dart
import '../features/staff/leave_screen.dart';
```

Leave every other `/staff/*` placeholder route (`working-hours`, `tasks`,
`daily-status`) untouched, and do not remove the `PlaceholderSectionScreen`
import — it's still needed by those three.

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/features/staff/leave_screen_test.dart`
Expected: PASS (3 tests). Then run `flutter analyze` — expect "No issues
found!"

- [ ] **Step 6: Commit**

```bash
git add lib/features/staff/leave_screen.dart lib/core/router.dart \
  test/features/staff/leave_screen_test.dart
git commit -m "feat(staff): wire /staff/leave to a real submit/view screen"
```

---

## Task 6: Full-suite verification

**Files:** none created or modified — verification only.

**Interfaces:** none.

- [ ] **Step 1: Reset the local database and run the pgTAP suite**

Run: `supabase db reset && supabase test db`
Expected: every file under `supabase/tests/` (18 files after this plan)
passes.

- [ ] **Step 2: Run the full Flutter analyzer**

Run: `flutter analyze`
Expected: "No issues found!"

- [ ] **Step 3: Run the full Flutter test suite**

Run: `flutter test`
Expected: every test passes except the three pre-existing, unrelated
`hold_lifecycle_test.dart` failures (a `pay-button` key-finder issue,
present on this branch before this plan's work started). If any other
test fails, or if those three tests newly pass, or a *different* set of
tests fails, stop and investigate before considering this task done.

- [ ] **Step 4: Manual walkthrough note**

Note in the final report to the user that automated coverage (pgTAP +
widget tests) is complete and clean, but a manual click-through — sign in
as staff, submit a leave request, sign in as admin, approve or reject it,
confirm the staff member sees the updated status — has not been done, and
offer to run the app for that walkthrough if the user wants it.

- [ ] **Step 5: Commit (if Step 1-3 required any fixes)**

Only if any fix was needed to make the suite clean:

```bash
git add -A
git commit -m "fix: address full-suite verification findings for leave management"
```

If no fixes were needed, skip this step.
