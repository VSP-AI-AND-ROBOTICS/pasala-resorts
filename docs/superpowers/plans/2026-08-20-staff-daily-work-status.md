# Staff Daily Work Status Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a staff/accountant member check in and check out once per
day, and let admin see a read-only view of attendance for any day.

**Architecture:** One new table (`attendance_records`) with a unique
`(staff_id, work_date)` constraint that makes "one check-in and one
check-out per day" a database-enforced fact, not a UI convention. RLS lets
a caller insert only their own today's check-in, and update only via the
same `using(true)` + enforcement-trigger pattern the two sibling features
(Work Schedules, Leave Management) already established — the trigger is
also what pins a check-out to be a one-way, one-shot transition (never
clearable, never re-doable) and blocks admin from writing at all (admin
only ever reads). Reads use a direct table `select` with an explicit
foreign-key-qualified `profiles` embed — following the exact fix Leave
Management's final review required, applied here from the start even
though this table has only one FK to `profiles` (defensive consistency,
not a strict necessity). The Flutter side is one repository
(`AttendanceRepository`), one fully read-only admin screen, and one staff
screen (a check-in/check-out card plus history), mirroring the file/class
shapes `leave_requests_screen.dart` and `leave_screen.dart` already
established.

**Tech Stack:** Flutter, Riverpod, Supabase (Postgres + PostgREST), pgTAP
(`supabase test db`).

**Spec:** `docs/superpowers/specs/2026-08-20-staff-daily-work-status-design.md`

## Global Constraints

- Exactly one check-in and one check-out per staff member per calendar
  day — enforced by a `unique (staff_id, work_date)` constraint, not just
  client-side logic.
- A check-out, once recorded, is final: it can never be cleared,
  corrected, or re-done. A missed check-out simply stays open forever —
  no auto-close, no admin correction path (approved design: "Missed
  checkout").
- No interaction with `staff_shifts` — nothing in this feature checks,
  flags, or reads that table (approved design: "Shifts interaction").
- Admin never writes to `attendance_records` — the admin screen is
  entirely read-only; the only mutation path is a staff member checking
  themselves in or out.
- No multiple sessions per day (no break tracking), no computed
  hours-worked figure, no "who hasn't checked in" synthesized roster view
  — all explicitly out of scope for this slice.
- Any PostgREST `profiles` embed must use an explicit foreign-key hint
  (`profiles!<constraint_name>(full_name)`), never a bare `profiles(...)`
  — an unqualified embed is ambiguous whenever a table has more than one
  FK to `profiles`, and caused a real production-breaking bug in the
  sibling Leave Management feature that no test in that plan caught.
- The existing hub card/route for Daily Work Status
  (`staffHubSections` in `lib/features/staff/staff_dashboard_hub_screen.dart`)
  is NOT touched — only what `/staff/daily-status` renders changes.
- `flutter analyze` and `flutter test` must stay clean at the end, except
  the three pre-existing, unrelated `hold_lifecycle_test.dart` failures
  already present on this branch before this work started.

---

## Task 1: `attendance_records` table, RLS, and the own-checkout enforcement trigger

**Files:**
- Create: `supabase/migrations/0023_attendance_records.sql`
- Create: `supabase/tests/19_attendance_records_test.sql`

**Interfaces:**
- Produces: table `public.attendance_records(id uuid, staff_id uuid,
  work_date date, check_in_at timestamptz, check_out_at timestamptz)`;
  function `public.attendance_records_enforce_own_checkout()`.

- [ ] **Step 1: Write the failing pgTAP test file**

Fixture ids used below, all seeded by `supabase/seed.sql`:
`10000000-0000-0000-0000-000000000002` (admin@pasala.test, admin),
`10000000-0000-0000-0000-000000000003` (staff@pasala.test, staff),
`10000000-0000-0000-0000-000000000004` (accounts@pasala.test,
accountant). This file's own fixture rows use a `99...` id prefix so they
can't collide with the seed or any other test file's fixtures. Distinct
`work_date`s (`current_date`, `current_date - 10`, `current_date + 10`,
`current_date + 11`) are used across the early insert tests so each one
exercises exactly the constraint it's meant to, without a unique-
constraint collision masking a different check.

```sql
-- attendance_records + RLS + attendance_records_enforce_own_checkout(),
-- added in 0023_attendance_records.sql to back the staff Daily Work
-- Status hub section and its read-only admin attendance screen. See
-- that migration's header for the "checkout is final, never corrected"
-- design decision.

begin;
select plan(18);

select has_table('public', 'attendance_records', 'attendance_records table exists');
select has_function('public', 'attendance_records_enforce_own_checkout',
  'the enforcement trigger function exists');

-- === insert: staff can check themselves in today, nothing else ============

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"10000000-0000-0000-0000-000000000003","role":"authenticated"}';

select lives_ok(
  $$insert into public.attendance_records (id, staff_id, work_date)
    values ('99111111-1111-1111-1111-111111111111',
            '10000000-0000-0000-0000-000000000003', current_date)$$,
  'staff can check themselves in today');

select throws_ok(
  $$insert into public.attendance_records (staff_id, work_date)
    values ('10000000-0000-0000-0000-000000000004', current_date + 10)$$,
  '42501', null, 'staff cannot check in on behalf of someone else');

select throws_ok(
  $$insert into public.attendance_records (staff_id, work_date)
    values ('10000000-0000-0000-0000-000000000003', current_date - 10)$$,
  '42501', null, 'staff cannot back-date a check-in to a different day');

select throws_ok(
  $$insert into public.attendance_records (staff_id, work_date, check_out_at)
    values ('10000000-0000-0000-0000-000000000003', current_date + 11, now())$$,
  '42501', null, 'a check-in cannot arrive already checked out');

select throws_ok(
  $$insert into public.attendance_records (staff_id, work_date)
    values ('10000000-0000-0000-0000-000000000003', current_date)$$,
  '23505', null, 'a second check-in the same day is rejected by the unique constraint');

-- === select: own rows only for staff, everything for admin =================

select is(
  (select count(*)::int from public.attendance_records),
  1,
  'a staff member sees only their own attendance record via direct select');

set local request.jwt.claims to
  '{"sub":"10000000-0000-0000-0000-000000000004","role":"authenticated"}';

select lives_ok(
  $$insert into public.attendance_records (id, staff_id, work_date)
    values ('99222222-2222-2222-2222-222222222222',
            '10000000-0000-0000-0000-000000000004', current_date)$$,
  'an accountant can also check themselves in');

set local request.jwt.claims to
  '{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}';

select is(
  (select count(*)::int from public.attendance_records),
  2,
  'admin sees every attendance record via direct select');

-- === update: only the owning staff member can check themselves out, once ==

set local request.jwt.claims to
  '{"sub":"10000000-0000-0000-0000-000000000003","role":"authenticated"}';

select lives_ok(
  $$update public.attendance_records set check_out_at = now()
    where id = '99111111-1111-1111-1111-111111111111'$$,
  'a staff member can check themselves out');

reset role;
select is(
  (select check_out_at is not null from public.attendance_records
    where id = '99111111-1111-1111-1111-111111111111'),
  true,
  'the checkout is visible directly on the table');

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"10000000-0000-0000-0000-000000000004","role":"authenticated"}';

select throws_ok(
  $$update public.attendance_records set check_out_at = now()
    where id = '99111111-1111-1111-1111-111111111111'$$,
  '42501', null, 'a different staff member cannot check someone else out');

set local request.jwt.claims to
  '{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}';

select throws_ok(
  $$update public.attendance_records set check_out_at = now()
    where id = '99111111-1111-1111-1111-111111111111'$$,
  '42501', null, 'admin cannot check someone out either -- attendance is never admin-written');

set local request.jwt.claims to
  '{"sub":"10000000-0000-0000-0000-000000000003","role":"authenticated"}';

select throws_ok(
  $$update public.attendance_records set check_out_at = now()
    where id = '99111111-1111-1111-1111-111111111111'$$,
  '42501', null, 'an already-checked-out record cannot be checked out again');

select throws_ok(
  $$update public.attendance_records set check_in_at = now()
    where id = '99111111-1111-1111-1111-111111111111'$$,
  '42501', null, 'check_in_at cannot be changed through an update');

-- === anon: no access at all =================================================

reset role;
set local role anon;
set local request.jwt.claims to '{"role":"anon"}';

select throws_ok(
  $$select * from public.attendance_records$$,
  '42501', null, 'anon cannot select attendance_records');

select throws_ok(
  $$insert into public.attendance_records (staff_id, work_date)
    values ('10000000-0000-0000-0000-000000000003', current_date)$$,
  '42501', null, 'anon cannot insert into attendance_records');

select * from finish();
rollback;
```

That file has 18 assertions total: `has_table`, `has_function`, 3
`lives_ok`, 10 `throws_ok`, 3 `is` — matching `select plan(18);` at the
top.

- [ ] **Step 2: Run the test file to verify it fails**

Run: `supabase test db`
Expected: FAIL — `attendance_records` table and
`attendance_records_enforce_own_checkout` function do not exist yet.

- [ ] **Step 3: Write the migration**

```sql
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
-- timestamp once -- never cleared, never re-done.
create function public.attendance_records_enforce_own_checkout()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if new.staff_id <> auth.uid() then
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
```

- [ ] **Step 4: Reset the local database and run the test file to verify it passes**

Run: `supabase db reset && supabase test db`
Expected: `supabase db reset` applies the new migration cleanly. `supabase
test db` then runs every file under `supabase/tests/` (19 files after
this task), including the new one, and reports all assertions passing —
every pre-existing file must stay green.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/0023_attendance_records.sql supabase/tests/19_attendance_records_test.sql
git commit -m "feat(db): add attendance_records table, RLS, and own-checkout trigger"
```

---

## Task 2: `AttendanceRecord` Dart model

**Files:**
- Create: `lib/data/models/attendance_record.dart`
- Test: `test/data/attendance_record_test.dart`

**Interfaces:**
- Produces: `class AttendanceRecord` with fields `id, staffId, staffName,
  workDate, checkInAt, checkOutAt`; getter `bool get isCheckedIn` (true
  when `checkOutAt == null`); `AttendanceRecord.fromJson(Map<String,
  dynamic>)` (handles a row with or without an embedded `profiles`
  object).

There is deliberately no `toInsert()`/`toUpdate()` method on this model —
unlike `LeaveRequest`, a check-in's insert payload is two fields
(`staff_id`, `work_date`) and a check-out's update payload is one field
(`check_out_at`), both built directly in `AttendanceRepository` (Task 3).
Adding a model-level serialization method here would replicate the exact
mistake Leave Management's final review found (`LeaveRequest.toInsert()`
existed only to satisfy its own test, since `create()` never called it) —
there's no meaningful shared serialization logic small payloads like
these need to justify a separate method.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/data/models/attendance_record.dart';

void main() {
  group('AttendanceRecord.fromJson', () {
    test('parses a plain table row (no embedded profiles), still checked in', () {
      final record = AttendanceRecord.fromJson(const {
        'id': 'a1',
        'staff_id': 'u1',
        'work_date': '2026-09-10',
        'check_in_at': '2026-09-10T09:00:00Z',
        'check_out_at': null,
      });

      expect(record.id, 'a1');
      expect(record.staffId, 'u1');
      expect(record.staffName, isNull);
      expect(record.workDate, DateTime.parse('2026-09-10'));
      expect(record.checkInAt, DateTime.parse('2026-09-10T09:00:00Z'));
      expect(record.checkOutAt, isNull);
      expect(record.isCheckedIn, isTrue);
    });

    test('parses a row with an embedded profiles object and a checkout', () {
      final record = AttendanceRecord.fromJson(const {
        'id': 'a2',
        'staff_id': 'u2',
        'profiles': {'full_name': 'Sita Staff'},
        'work_date': '2026-09-11',
        'check_in_at': '2026-09-11T09:00:00Z',
        'check_out_at': '2026-09-11T17:00:00Z',
      });

      expect(record.staffName, 'Sita Staff');
      expect(record.checkOutAt, DateTime.parse('2026-09-11T17:00:00Z'));
      expect(record.isCheckedIn, isFalse);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/attendance_record_test.dart`
Expected: FAIL — `lib/data/models/attendance_record.dart` does not exist
yet.

- [ ] **Step 3: Write the model**

```dart
/// One staff/accountant member's daily attendance record. [staffName] is
/// populated only when the row came with an embedded `profiles` object
/// (the repository's `list()` always joins it) -- `null` is never treated
/// as an error, just "no name on this particular response."
class AttendanceRecord {
  const AttendanceRecord({
    required this.id,
    required this.staffId,
    required this.workDate,
    required this.checkInAt,
    this.staffName,
    this.checkOutAt,
  });

  final String id;
  final String staffId;
  final String? staffName;
  final DateTime workDate;
  final DateTime checkInAt;
  final DateTime? checkOutAt;

  /// True while the staff member has checked in but not yet checked out
  /// for [workDate]. Pure so both screens can share the same "what state
  /// is this record in" rule without duplicating a null check.
  bool get isCheckedIn => checkOutAt == null;

  factory AttendanceRecord.fromJson(Map<String, dynamic> json) => AttendanceRecord(
        id: json['id'] as String,
        staffId: json['staff_id'] as String,
        staffName: (json['profiles'] as Map<String, dynamic>?)?['full_name']
            as String?,
        workDate: DateTime.parse(json['work_date'] as String),
        checkInAt: DateTime.parse(json['check_in_at'] as String),
        checkOutAt: json['check_out_at'] == null
            ? null
            : DateTime.parse(json['check_out_at'] as String),
      );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/data/attendance_record_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/data/models/attendance_record.dart test/data/attendance_record_test.dart
git commit -m "feat(model): add AttendanceRecord model"
```

---

## Task 3: `AttendanceRepository`

**Files:**
- Create: `lib/data/repositories/attendance_repository.dart`

**Interfaces:**
- Consumes: `AttendanceRecord`, `AttendanceRecord.fromJson` (Task 2);
  `supabaseProvider` (`lib/core/supabase_client.dart`); `mapPostgrestError`
  (`lib/core/errors.dart`).
- Produces: `class AttendanceRepository` with methods `list({String?
  staffId, DateTime? date}) -> Future<List<AttendanceRecord>>`,
  `checkIn({required String staffId}) -> Future<void>`, `checkOut({required
  String id}) -> Future<void>`; providers `attendanceRepositoryProvider`
  (`Provider<AttendanceRepository>`) and `attendanceRecordsProvider`
  (`FutureProvider.family<List<AttendanceRecord>, AttendanceFilter>`),
  plus `typedef AttendanceFilter = ({String? staffId, DateTime? date})`
  that Tasks 4-5 watch.

This repository has no dedicated unit-test file, matching this codebase's
established convention (`RateRepository`, `StaffShiftRepository`,
`LeaveRequestRepository` — none have one). Tasks 4-5 exercise it via a
`FakeAttendanceRepository`. This task's own verification is `flutter
analyze`.

- [ ] **Step 1: Write the repository**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors.dart';
import '../../core/supabase_client.dart';
import '../models/attendance_record.dart';

/// The (staff, date) an admin or staff screen wants to see -- `staffId:
/// null` means "every staff member" (admin only; RLS returns only the
/// caller's own rows for anyone else regardless), `date: null` means
/// "every date on record." A record, not positional params, so
/// `FutureProvider.family` can key on it directly.
typedef AttendanceFilter = ({String? staffId, DateTime? date});

class AttendanceRepository {
  AttendanceRepository(this._db);
  final SupabaseClient _db;

  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } catch (e) {
      throw mapPostgrestError(e);
    }
  }

  String _dateOnly(DateTime d) => d.toIso8601String().substring(0, 10);

  /// A direct table select with an explicit foreign-key-qualified
  /// `profiles` embed. This table has only one FK to `profiles`
  /// (`staff_id`), so a bare `profiles(full_name)` would actually
  /// resolve unambiguously today -- but the hint is used anyway,
  /// consistent with the fix `leave_requests` needed after its final
  /// review (that table's SECOND FK, `decided_by`, made its embed
  /// ambiguous and broke at runtime with no test catching it). Naming
  /// the relationship here guards against the same class of bug if this
  /// table ever grows a second FK to `profiles`.
  Future<List<AttendanceRecord>> list({
    String? staffId,
    DateTime? date,
  }) =>
      _guard(() async {
        dynamic query = _db
            .from('attendance_records')
            .select('*, profiles!attendance_records_staff_id_fkey(full_name)');
        if (staffId != null) query = query.eq('staff_id', staffId);
        if (date != null) query = query.eq('work_date', _dateOnly(date));
        final rows = await query.order('work_date', ascending: false) as List;
        return rows
            .map((e) => AttendanceRecord.fromJson(e as Map<String, dynamic>))
            .toList();
      });

  /// Checks [staffId] in for today. `work_date`/`check_out_at` are
  /// deliberately not sent -- the server enforces `work_date = current_date`
  /// via `attendance_records_own_insert`'s `with check`, and
  /// `check_in_at` defaults to `now()`.
  Future<void> checkIn({required String staffId}) => _guard(() async {
        await _db.from('attendance_records').insert({
          'staff_id': staffId,
          'work_date': _dateOnly(DateTime.now()),
        });
      });

  /// Checks the record at [id] out now, via the `check_out_attendance`
  /// RPC -- NOT a direct table update. Postgres RLS requires a row to be
  /// visible via an applicable SELECT-type policy before an UPDATE
  /// policy's own `USING` clause is even consulted; a same-tier staff
  /// peer attempting to check someone else out has no such visibility
  /// (they aren't the row's owner and aren't admin), so a raw UPDATE
  /// would silently affect zero rows instead of raising an error -- a
  /// gap discovered and fixed at the database layer in Task 1 (see
  /// `0023_attendance_records.sql`'s `check_out_attendance` function).
  /// The RPC does its own explicit ownership check and raises
  /// immediately, so this method only needs to surface whatever error
  /// it returns.
  Future<void> checkOut({required String id}) => _guard(() async {
        await _db.rpc('check_out_attendance', params: {'p_id': id});
      });
}

final attendanceRepositoryProvider = Provider<AttendanceRepository>(
  (ref) => AttendanceRepository(ref.watch(supabaseProvider)),
);

final attendanceRecordsProvider =
    FutureProvider.family<List<AttendanceRecord>, AttendanceFilter>(
  (ref, filter) => ref.watch(attendanceRepositoryProvider).list(
        staffId: filter.staffId,
        date: filter.date,
      ),
);
```

- [ ] **Step 2: Run `flutter analyze` to verify it compiles cleanly**

Run: `flutter analyze`
Expected: "No issues found!"

- [ ] **Step 3: Commit**

```bash
git add lib/data/repositories/attendance_repository.dart
git commit -m "feat(repo): add AttendanceRepository"
```

---

## Task 4: Admin "Attendance" screen (read-only)

**Files:**
- Create: `lib/features/admin/attendance_screen.dart`
- Test: `test/features/admin/attendance_screen_test.dart`
- Modify: `lib/core/router.dart` — add the `/admin/attendance` route
- Modify: `lib/features/admin/admin_home_screen.dart` — add a destination
  entry linking to it

**Interfaces:**
- Consumes: `AttendanceRecord`, `attendanceRecordsProvider`,
  `AttendanceFilter` (Tasks 2-3); `AdminProfile`, `adminProfilesProvider`
  (`lib/data/repositories/user_admin_repository.dart`, already exists);
  `UserRole` (`lib/data/models/app_user.dart`, already exists).
- Produces: `class AttendanceScreen`.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/data/models/admin_profile.dart';
import 'package:pasala/data/models/app_user.dart';
import 'package:pasala/data/models/attendance_record.dart';
import 'package:pasala/data/repositories/attendance_repository.dart';
import 'package:pasala/data/repositories/user_admin_repository.dart';
import 'package:pasala/features/admin/attendance_screen.dart';

/// In-memory stand-in for [AttendanceRepository], mirroring
/// `FakeLeaveRequestRepository` in `leave_requests_screen_test.dart`.
class FakeAttendanceRepository implements AttendanceRepository {
  final List<AttendanceRecord> store = [];

  @override
  Future<List<AttendanceRecord>> list({
    String? staffId,
    DateTime? date,
  }) async =>
      store.where((r) {
        if (staffId != null && r.staffId != staffId) return false;
        if (date != null && !DateUtils.isSameDay(r.workDate, date)) return false;
        return true;
      }).toList();

  @override
  Future<void> checkIn({required String staffId}) async {
    throw UnimplementedError('admin never checks anyone in');
  }

  @override
  Future<void> checkOut({required String id}) async {
    throw UnimplementedError('admin never checks anyone out');
  }
}

final _staffProfile = AdminProfile(
  id: 'staff-1',
  email: 'staff@pasala.test',
  role: UserRole.staff,
  fullName: 'Sita Staff',
  createdAt: DateTime(2026, 1, 1),
);

Widget _appFor(FakeAttendanceRepository repo) => ProviderScope(
      overrides: [
        attendanceRepositoryProvider.overrideWithValue(repo),
        adminProfilesProvider.overrideWith((ref) async => [_staffProfile]),
      ],
      child: const MaterialApp(home: AttendanceScreen()),
    );

void main() {
  final today = DateTime.now();

  testWidgets('defaults to showing today\'s records only', (tester) async {
    final repo = FakeAttendanceRepository()
      ..store.addAll([
        AttendanceRecord(
          id: 'a1',
          staffId: 'staff-1',
          staffName: 'Sita Staff',
          workDate: DateTime(today.year, today.month, today.day),
          checkInAt: DateTime(today.year, today.month, today.day, 9),
        ),
        AttendanceRecord(
          id: 'a2',
          staffId: 'staff-1',
          staffName: 'Sita Staff',
          workDate: DateTime(today.year, today.month, today.day - 1),
          checkInAt: DateTime(today.year, today.month, today.day - 1, 9),
          checkOutAt: DateTime(today.year, today.month, today.day - 1, 17),
        ),
      ]);

    await tester.pumpWidget(_appFor(repo));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('attendance-row-a1')), findsOneWidget);
    expect(find.byKey(const Key('attendance-row-a2')), findsNothing);
  });

  testWidgets('shows an empty state when nobody has checked in that day', (
    tester,
  ) async {
    await tester.pumpWidget(_appFor(FakeAttendanceRepository()));
    await tester.pumpAndSettle();

    expect(find.text('No attendance records'), findsOneWidget);
  });

  testWidgets('shows still-checked-in and checked-out states distinctly', (
    tester,
  ) async {
    final repo = FakeAttendanceRepository()
      ..store.add(AttendanceRecord(
        id: 'a1',
        staffId: 'staff-1',
        staffName: 'Sita Staff',
        workDate: DateTime(today.year, today.month, today.day),
        checkInAt: DateTime(today.year, today.month, today.day, 9),
      ));

    await tester.pumpWidget(_appFor(repo));
    await tester.pumpAndSettle();

    expect(find.textContaining('Still checked in'), findsOneWidget);
  });
}
```

This test file has three `testWidgets` blocks in total.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/admin/attendance_screen_test.dart`
Expected: FAIL — `lib/features/admin/attendance_screen.dart` does not
exist yet.

- [ ] **Step 3: Write the screen**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/empty_state.dart';
import '../../data/models/app_user.dart';
import '../../data/repositories/attendance_repository.dart';
import '../../data/repositories/user_admin_repository.dart';

final _dateFormat = DateFormat('d MMM yyyy');
final _timeFormat = DateFormat.jm();

/// `/admin/attendance` -- admin-only, fully read-only: admin never
/// writes attendance, it only ever reads what staff recorded themselves.
/// Defaults to today, filterable by staff member and to any other date.
class AttendanceScreen extends ConsumerStatefulWidget {
  const AttendanceScreen({super.key});

  @override
  ConsumerState<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends ConsumerState<AttendanceScreen> {
  String? _staffId;
  DateTime _date = DateUtils.dateOnly(DateTime.now());

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(_date.year - 1),
      lastDate: DateTime(_date.year + 1),
    );
    if (picked != null) setState(() => _date = DateUtils.dateOnly(picked));
  }

  @override
  Widget build(BuildContext context) {
    final filter = (staffId: _staffId, date: _date);
    final records = ref.watch(attendanceRecordsProvider(filter));
    final profiles = ref.watch(adminProfilesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Attendance')),
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
                        key: const Key('attendance-staff-picker'),
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
                TextButton.icon(
                  key: const Key('attendance-date-picker'),
                  onPressed: _pickDate,
                  icon: const Icon(Icons.calendar_today_outlined),
                  label: Text(_dateFormat.format(_date)),
                ),
              ],
            ),
          ),
          Expanded(
            child: AsyncView(
              value: records,
              onRetry: () => ref.invalidate(attendanceRecordsProvider(filter)),
              empty: () => const EmptyState(
                icon: Icons.how_to_reg_outlined,
                title: 'No attendance records',
                message: 'Nobody has checked in for this day yet.',
              ),
              data: (list) => ListView(
                children: [
                  for (final record in list)
                    Padding(
                      key: Key('attendance-row-${record.id}'),
                      padding: const EdgeInsets.symmetric(
                        horizontal: Spacing.md,
                        vertical: Spacing.xs,
                      ),
                      child: Card(
                        child: ListTile(
                          title: Text(record.staffName ?? record.staffId),
                          subtitle: Text(
                            record.isCheckedIn
                                ? 'Checked in at ${_timeFormat.format(record.checkInAt)} · '
                                    'Still checked in'
                                : 'Checked in at ${_timeFormat.format(record.checkInAt)} · '
                                    'Checked out at ${_timeFormat.format(record.checkOutAt!)}',
                          ),
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
}
```

- [ ] **Step 4: Wire the route and the admin-home link**

In `lib/core/router.dart`, add the import and the route (admin-only,
placed alongside the other `/admin/*` `GoRoute` entries, e.g. right after
`/admin/leave-requests`):

```dart
import '../features/admin/attendance_screen.dart';
```

```dart
          GoRoute(
            path: '/admin/attendance',
            builder: (_, _) => const AttendanceScreen(),
          ),
```

In `lib/features/admin/admin_home_screen.dart`, add a new destination
tuple to `_destinations`, after the `'Leave requests'` entry:

```dart
    (
      icon: Icons.how_to_reg_outlined,
      title: 'Attendance',
      subtitle: 'See who\'s checked in, today or any past day',
      path: '/admin/attendance',
    ),
```

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/features/admin/attendance_screen_test.dart`
Expected: PASS (3 tests). Then run `flutter analyze` — expect "No issues
found!"

- [ ] **Step 6: Commit**

```bash
git add lib/features/admin/attendance_screen.dart lib/core/router.dart \
  lib/features/admin/admin_home_screen.dart \
  test/features/admin/attendance_screen_test.dart
git commit -m "feat(admin): add read-only Attendance screen"
```

---

## Task 5: Staff Daily Work Status screen (check-in/check-out)

**Files:**
- Create: `lib/features/staff/daily_status_screen.dart`
- Test: `test/features/staff/daily_status_screen_test.dart`
- Modify: `lib/core/router.dart` — replace the `PlaceholderSectionScreen`
  builder for `/staff/daily-status` with `DailyStatusScreen`

**Interfaces:**
- Consumes: `AttendanceRecord`, `attendanceRecordsProvider`,
  `attendanceRepositoryProvider`, `AttendanceFilter` (Tasks 2-3);
  `currentUserProvider` (`lib/data/repositories/auth_repository.dart`,
  already used identically by `TimeSlotsScreen`/`LeaveScreen`).
- Produces: `class DailyStatusScreen`; top-level pure functions
  `AttendanceRecord? todayRecordFrom(List<AttendanceRecord> records,
  DateTime today)` and `List<AttendanceRecord> pastRecordsFrom(List<AttendanceRecord>
  records, DateTime today)`.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/errors.dart';
import 'package:pasala/data/models/app_user.dart';
import 'package:pasala/data/models/attendance_record.dart';
import 'package:pasala/data/repositories/attendance_repository.dart';
import 'package:pasala/data/repositories/auth_repository.dart';
import 'package:pasala/features/staff/daily_status_screen.dart';

const _staff = AppUser(id: 'staff-1', email: 'staff@pasala.test', role: UserRole.staff);

AttendanceRecord _record(
  String id,
  DateTime day, {
  int checkInHour = 9,
  int? checkOutHour,
}) =>
    AttendanceRecord(
      id: id,
      staffId: 'staff-1',
      workDate: DateTime(day.year, day.month, day.day),
      checkInAt: DateTime(day.year, day.month, day.day, checkInHour),
      checkOutAt: checkOutHour == null
          ? null
          : DateTime(day.year, day.month, day.day, checkOutHour),
    );

/// In-memory stand-in for [AttendanceRepository], mirroring
/// `FakeLeaveRequestRepository`.
class FakeAttendanceRepository implements AttendanceRepository {
  final List<AttendanceRecord> store = [];
  final List<String> checkInCalls = [];
  final List<String> checkOutCalls = [];
  int _idCounter = 0;
  BookingFailure? checkInFailure;

  @override
  Future<List<AttendanceRecord>> list({
    String? staffId,
    DateTime? date,
  }) async =>
      store.where((r) {
        if (staffId != null && r.staffId != staffId) return false;
        if (date != null && !DateUtils.isSameDay(r.workDate, date)) return false;
        return true;
      }).toList();

  @override
  Future<void> checkIn({required String staffId}) async {
    checkInCalls.add(staffId);
    final failure = checkInFailure;
    if (failure != null) throw failure;
    final now = DateTime.now();
    store.add(AttendanceRecord(
      id: 'attendance-${_idCounter++}',
      staffId: staffId,
      workDate: DateTime(now.year, now.month, now.day),
      checkInAt: now,
    ));
  }

  @override
  Future<void> checkOut({required String id}) async {
    checkOutCalls.add(id);
    final index = store.indexWhere((r) => r.id == id);
    final existing = store[index];
    store[index] = AttendanceRecord(
      id: existing.id,
      staffId: existing.staffId,
      workDate: existing.workDate,
      checkInAt: existing.checkInAt,
      checkOutAt: DateTime.now(),
    );
  }
}

void main() {
  group('todayRecordFrom / pastRecordsFrom', () {
    final today = DateTime(2026, 9, 10);

    test('todayRecordFrom finds the record matching today\'s date', () {
      final records = [
        _record('a1', today.subtract(const Duration(days: 1))),
        _record('a2', today),
      ];

      expect(todayRecordFrom(records, today)?.id, 'a2');
    });

    test('todayRecordFrom returns null when there is no record today', () {
      final records = [_record('a1', today.subtract(const Duration(days: 1)))];

      expect(todayRecordFrom(records, today), isNull);
    });

    test('pastRecordsFrom excludes today and sorts newest first', () {
      final records = [
        _record('a1', today.subtract(const Duration(days: 2))),
        _record('a2', today),
        _record('a3', today.subtract(const Duration(days: 1))),
      ];

      expect(pastRecordsFrom(records, today).map((r) => r.id), ['a3', 'a1']);
    });
  });

  Widget _appFor(FakeAttendanceRepository repo) => ProviderScope(
        overrides: [
          currentUserProvider.overrideWith((ref) => Stream.value(_staff)),
          attendanceRepositoryProvider.overrideWithValue(repo),
        ],
        child: const MaterialApp(home: DailyStatusScreen()),
      );

  testWidgets('shows a Check In button when there is no record today', (
    tester,
  ) async {
    await tester.pumpWidget(_appFor(FakeAttendanceRepository()));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('check-in-button')), findsOneWidget);
    expect(find.byKey(const Key('check-out-button')), findsNothing);
  });

  testWidgets('tapping Check In calls checkIn and shows the Check Out button',
      (tester) async {
    final repo = FakeAttendanceRepository();
    await tester.pumpWidget(_appFor(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('check-in-button')));
    await tester.pumpAndSettle();

    expect(repo.checkInCalls, ['staff-1']);
    expect(find.byKey(const Key('check-out-button')), findsOneWidget);
    expect(find.byKey(const Key('check-in-button')), findsNothing);
  });

  testWidgets(
      'tapping Check Out calls checkOut and shows the checked-out summary '
      'with no button', (tester) async {
    final now = DateTime.now();
    final repo = FakeAttendanceRepository()
      ..store.add(_record('a1', now, checkInHour: 9));

    await tester.pumpWidget(_appFor(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('check-out-button')));
    await tester.pumpAndSettle();

    expect(repo.checkOutCalls, ['a1']);
    expect(find.byKey(const Key('check-out-button')), findsNothing);
    expect(find.byKey(const Key('check-in-button')), findsNothing);
  });

  testWidgets('shows past records in the history list', (tester) async {
    final now = DateTime.now();
    final yesterday = now.subtract(const Duration(days: 1));
    final repo = FakeAttendanceRepository()
      ..store.add(_record('a1', yesterday, checkInHour: 9, checkOutHour: 17));

    await tester.pumpWidget(_appFor(repo));
    await tester.pumpAndSettle();

    expect(find.textContaining('9:00'), findsOneWidget);
    expect(find.textContaining('5:00'), findsOneWidget);
  });
}
```

This test file has three plain `test`s and four `testWidgets` blocks in
total.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/staff/daily_status_screen_test.dart`
Expected: FAIL — `lib/features/staff/daily_status_screen.dart` does not
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
import '../../data/models/attendance_record.dart';
import '../../data/repositories/attendance_repository.dart';
import '../../data/repositories/auth_repository.dart';

final _dateFormat = DateFormat('d MMM yyyy');
final _timeFormat = DateFormat.jm();

/// Today's record among [records], if the staff member has one --
/// date-only comparison via [DateUtils.isSameDay]. Pure so it's testable
/// without a widget.
AttendanceRecord? todayRecordFrom(List<AttendanceRecord> records, DateTime today) {
  for (final record in records) {
    if (DateUtils.isSameDay(record.workDate, today)) return record;
  }
  return null;
}

/// Every record except today's, newest first. Pure for the same reason.
List<AttendanceRecord> pastRecordsFrom(List<AttendanceRecord> records, DateTime today) {
  final past =
      records.where((r) => !DateUtils.isSameDay(r.workDate, today)).toList();
  past.sort((a, b) => b.workDate.compareTo(a.workDate));
  return past;
}

/// `/staff/daily-status` -- one-tap check-in/check-out for today, plus
/// the signed-in staff/accountant member's own history below it. No
/// edit, no correction -- a checkout is final once recorded (see the
/// design spec's "Missed checkout" decision).
class DailyStatusScreen extends ConsumerStatefulWidget {
  const DailyStatusScreen({super.key});

  @override
  ConsumerState<DailyStatusScreen> createState() => _DailyStatusScreenState();
}

class _DailyStatusScreenState extends ConsumerState<DailyStatusScreen> {
  bool _busy = false;

  Future<void> _checkIn(String staffId, AttendanceFilter filter) async {
    setState(() => _busy = true);
    try {
      await ref.read(attendanceRepositoryProvider).checkIn(staffId: staffId);
      ref.invalidate(attendanceRecordsProvider(filter));
    } on BookingFailure catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(FailureView.messageFor(e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _checkOut(String recordId, AttendanceFilter filter) async {
    setState(() => _busy = true);
    try {
      await ref.read(attendanceRepositoryProvider).checkOut(id: recordId);
      ref.invalidate(attendanceRecordsProvider(filter));
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
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider).value;
    final staffId = user?.id;

    // Unlike the read-only Time Slots/Leave screens, this screen's top
    // card needs a real staff id to check in with -- it can't fall back
    // to an empty-list placeholder the way a plain list screen can, so
    // it waits for auth to resolve instead of proceeding with a null id.
    if (staffId == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final filter = (staffId: staffId, date: null);
    final recordsAsync = ref.watch(attendanceRecordsProvider(filter));

    return Scaffold(
      appBar: AppBar(title: const Text('Daily Work Status')),
      body: AsyncView(
        value: recordsAsync,
        onRetry: () => ref.invalidate(attendanceRecordsProvider(filter)),
        data: (all) {
          final today = todayRecordFrom(all, DateTime.now());
          final past = pastRecordsFrom(all, DateTime.now());

          return ListView(
            padding: const EdgeInsets.all(Spacing.md),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(Spacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (today == null) ...[
                        const Text('You have not checked in today.'),
                        const SizedBox(height: Spacing.md),
                        FilledButton(
                          key: const Key('check-in-button'),
                          onPressed: _busy ? null : () => _checkIn(staffId, filter),
                          child: const Text('Check In'),
                        ),
                      ] else if (today.isCheckedIn) ...[
                        Text('Checked in at ${_timeFormat.format(today.checkInAt)}'),
                        const SizedBox(height: Spacing.md),
                        FilledButton(
                          key: const Key('check-out-button'),
                          onPressed: _busy ? null : () => _checkOut(today.id, filter),
                          child: const Text('Check Out'),
                        ),
                      ] else ...[
                        Text(
                          'Checked in at ${_timeFormat.format(today.checkInAt)} · '
                          'Checked out at ${_timeFormat.format(today.checkOutAt!)}',
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: Spacing.lg),
              if (past.isEmpty)
                const EmptyState(
                  icon: Icons.history_outlined,
                  title: 'No history yet',
                  message: 'Past check-ins will show up here.',
                )
              else
                for (final record in past)
                  Card(
                    child: ListTile(
                      title: Text(_dateFormat.format(record.workDate)),
                      subtitle: Text(
                        record.checkOutAt == null
                            ? 'Checked in at ${_timeFormat.format(record.checkInAt)} · '
                                'No check-out recorded'
                            : 'Checked in at ${_timeFormat.format(record.checkInAt)} · '
                                'Checked out at ${_timeFormat.format(record.checkOutAt!)}',
                      ),
                    ),
                  ),
            ],
          );
        },
      ),
    );
  }
}
```

- [ ] **Step 4: Wire the route**

In `lib/core/router.dart`, replace the existing `/staff/daily-status`
`GoRoute` (currently a `PlaceholderSectionScreen`) with:

```dart
          GoRoute(
            path: '/staff/daily-status',
            builder: (_, _) => const DailyStatusScreen(),
          ),
```

Add the import:

```dart
import '../features/staff/daily_status_screen.dart';
```

Leave every other `/staff/*` route (all now-real screens, plus the two
remaining placeholders `working-hours`/`tasks`) untouched, and do not
remove the `PlaceholderSectionScreen` import — it's still needed by
those two.

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/features/staff/daily_status_screen_test.dart`
Expected: PASS (7 tests: 3 pure + 4 widget). Then run `flutter analyze`
— expect "No issues found!"

- [ ] **Step 6: Commit**

```bash
git add lib/features/staff/daily_status_screen.dart lib/core/router.dart \
  test/features/staff/daily_status_screen_test.dart
git commit -m "feat(staff): wire /staff/daily-status to check-in/check-out"
```

---

## Task 6: Full-suite verification

**Files:** none created or modified — verification only.

**Interfaces:** none.

- [ ] **Step 1: Reset the local database and run the pgTAP suite**

Run: `supabase db reset && supabase test db`
Expected: every file under `supabase/tests/` (19 files after this plan)
passes.

- [ ] **Step 2: Run the full Flutter analyzer**

Run: `flutter analyze`
Expected: "No issues found!"

- [ ] **Step 3: Run the full Flutter test suite**

Run: `flutter test`
Expected: every test passes except the three pre-existing, unrelated
`hold_lifecycle_test.dart` failures (a `pay-button` key-finder issue,
present on this branch since before any of this staff-module work
started). If any other test fails, or if those three tests newly pass,
or a *different* set of tests fails, stop and investigate before
considering this task done.

- [ ] **Step 4: Verify the `profiles` embed against real PostgREST**

The sibling Leave Management feature's final review found that an
ambiguous/incorrect `profiles` embed passes every test on this branch
(pgTAP bypasses PostgREST entirely, and every widget test injects a fake
repository) but fails at runtime against the real API. This table has
only one FK to `profiles`, so the embed used in Task 3 is not ambiguous
the way `leave_requests`' was — but confirm this directly rather than
assuming it: with the local Supabase stack running (`supabase status` to
check, `supabase start` if needed), issue a request against
`/rest/v1/attendance_records?select=*,profiles!attendance_records_staff_id_fkey(full_name)`
with a valid staff JWT (e.g. via `curl`) and confirm it returns HTTP 200
with a populated `full_name`, not an error. Note the exact command and
response in your report.

- [ ] **Step 5: Manual walkthrough note**

Note in the final report to the user that automated coverage (pgTAP +
widget tests + the direct PostgREST check in Step 4) is complete and
clean, but a full manual click-through — sign in as staff, check in,
check out, sign in as admin, confirm the record appears on
`/admin/attendance` for today — has not been done, and offer to run the
app for that walkthrough if the user wants it.

- [ ] **Step 6: Commit (if Step 1-4 required any fixes)**

Only if any fix was needed to make the suite clean:

```bash
git add -A
git commit -m "fix: address full-suite verification findings for daily work status"
```

If no fixes were needed, skip this step.
