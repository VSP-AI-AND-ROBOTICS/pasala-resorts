# Staff Work Schedules / Time Slots Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let an admin assign work shifts to staff/accountant users, and let each
staff/accountant user see their own shifts as a calendar (Work Schedules) and
as a chronological list (Time Slots).

**Architecture:** One new table (`staff_shifts`) with RLS restricting reads to
"admin sees all, everyone else sees only their own row" and writes to
admin-only. Reads go through a new `list_staff_shifts` RPC (matching this
codebase's convention of RPC-backed filtered reads, e.g. `report_revenue`)
so a single server-side query serves both the admin's filtered master list
and each staff member's own-shifts view, with RLS doing the actual
visibility enforcement underneath regardless of what filter a caller passes.
Writes (create/update/delete) are plain authenticated table operations
gated by RLS, matching how `rate_rules` already does writes. The Flutter
side is one repository (`StaffShiftRepository`), one admin screen
(list + filter + create/edit form, mirroring `rate_rules_screen.dart`), and
two staff screens (a calendar and a list) that share the same repository
method and pure day-shift logic.

**Tech Stack:** Flutter, Riverpod, Supabase (Postgres + PostgREST RPC),
go_router, pgTAP (`supabase test db`).

**Spec:** `docs/superpowers/specs/2026-08-19-staff-work-shifts-design.md`

## Global Constraints

- No overlap restriction on shifts (approved design: split shifts are
  allowed) — no exclusion constraint, only `end_time > start_time`.
- Overnight-spanning shifts are out of scope (§7 of the spec) — the check
  constraint makes this a hard limit for this slice, not a soft one.
- Staff/accountant see **only their own** shifts, never another staff
  member's (approved design, §"Staff visibility" in the brainstorming
  session).
- Admin write access only — staff/accountant have no insert/update/delete
  path, enforced by RLS, not just hidden in the UI.
- The two existing hub cards/routes (`/staff/schedules`, `/staff/time-slots`)
  and their labels/icons in `staffHubSections`
  (`lib/features/staff/staff_dashboard_hub_screen.dart`) are NOT touched —
  only what those two routes render changes.
- `flutter analyze` and `flutter test` must stay clean at the end, except
  the three pre-existing, unrelated `hold_lifecycle_test.dart` failures
  already present on this branch before this work started.

---

## Task 1: `staff_shifts` table, RLS, and the `list_staff_shifts` RPC

**Files:**
- Create: `supabase/migrations/0021_staff_shifts.sql`
- Create: `supabase/tests/17_staff_shifts_test.sql`

**Interfaces:**
- Produces: table `public.staff_shifts(id uuid, staff_id uuid, shift_date
  date, start_time time, end_time time, notes text, created_by uuid,
  created_at timestamptz)`; function `public.list_staff_shifts(p_staff_id
  uuid default null, p_from date default null, p_to date default null)
  returns table(id uuid, staff_id uuid, staff_name text, shift_date date,
  start_time time, end_time time, notes text, created_at timestamptz)`.

- [ ] **Step 1: Write the failing pgTAP test file**

Fixture ids used below (all seeded by `supabase/seed.sql`, present before
this file's transaction starts): `10000000-0000-0000-0000-000000000002`
(admin@pasala.test, admin), `10000000-0000-0000-0000-000000000003`
(staff@pasala.test, staff), `10000000-0000-0000-0000-000000000004`
(accounts@pasala.test, accountant). This file's own fixture rows use a
`97...` id prefix so they can't collide with the seed or any other test
file's fixtures.

```sql
-- staff_shifts + list_staff_shifts(), added in 0021_staff_shifts.sql to
-- back the admin shift-assignment screen and the staff Work
-- Schedules/Time Slots views. See that migration's header for the
-- no-overlap-restriction and no-overnight-shift decisions.

begin;
select plan(18);

select has_table('public', 'staff_shifts', 'staff_shifts table exists');
select has_function('public', 'list_staff_shifts', 'list_staff_shifts() exists');

-- === writes: admin-only =====================================================

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"10000000-0000-0000-0000-000000000003","role":"authenticated"}';

select throws_ok(
  $$insert into public.staff_shifts
      (staff_id, shift_date, start_time, end_time, created_by)
    values ('10000000-0000-0000-0000-000000000003','2026-09-01','09:00','17:00',
            '10000000-0000-0000-0000-000000000003')$$,
  '42501', null, 'a staff member cannot insert their own shift');

set local request.jwt.claims to
  '{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}';

select lives_ok(
  $$insert into public.staff_shifts
      (id, staff_id, shift_date, start_time, end_time, created_by)
    values ('97111111-1111-1111-1111-111111111111',
            '10000000-0000-0000-0000-000000000003','2026-09-01','09:00','17:00',
            '10000000-0000-0000-0000-000000000002')$$,
  'admin can insert a shift for a staff member');

select lives_ok(
  $$insert into public.staff_shifts
      (id, staff_id, shift_date, start_time, end_time, created_by)
    values ('97222222-2222-2222-2222-222222222222',
            '10000000-0000-0000-0000-000000000004','2026-09-02','10:00','18:00',
            '10000000-0000-0000-0000-000000000002')$$,
  'admin can insert a shift for an accountant');

select lives_ok(
  $$update public.staff_shifts set notes = 'cover shift'
    where id = '97111111-1111-1111-1111-111111111111'$$,
  'admin can update any shift');

reset role;
select is(
  (select notes from public.staff_shifts
    where id = '97111111-1111-1111-1111-111111111111'),
  'cover shift',
  'the update is visible directly on the table');

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"10000000-0000-0000-0000-000000000003","role":"authenticated"}';

select throws_ok(
  $$update public.staff_shifts set notes = 'nope'
    where id = '97111111-1111-1111-1111-111111111111'$$,
  '42501', null, 'a staff member cannot update their own shift row');

select throws_ok(
  $$delete from public.staff_shifts
    where id = '97111111-1111-1111-1111-111111111111'$$,
  '42501', null, 'a staff member cannot delete their own shift row');

-- === the time-order check constraint ========================================

reset role;
select throws_like(
  $$insert into public.staff_shifts
      (staff_id, shift_date, start_time, end_time, created_by)
    values ('10000000-0000-0000-0000-000000000003','2026-09-03','17:00','09:00',
            '10000000-0000-0000-0000-000000000002')$$,
  '%staff_shifts_time_order%',
  'a shift with end_time before start_time is rejected');

-- === reads: own-row only for staff/accountant, everything for admin ========

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"10000000-0000-0000-0000-000000000003","role":"authenticated"}';

select is(
  (select count(*)::int from public.staff_shifts),
  1,
  'a staff member sees only their own shift row via direct select');

set local request.jwt.claims to
  '{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}';

select is(
  (select count(*)::int from public.staff_shifts),
  2,
  'admin sees every shift row via direct select');

-- === list_staff_shifts(): same visibility rules, plus filtering ============

set local request.jwt.claims to
  '{"sub":"10000000-0000-0000-0000-000000000003","role":"authenticated"}';

select is(
  (select count(*)::int from public.list_staff_shifts()),
  1,
  'a staff member calling list_staff_shifts() with no filter sees only '
  'their own shift');

select is(
  (select count(*)::int from public.list_staff_shifts(
    p_staff_id => '10000000-0000-0000-0000-000000000004')),
  0,
  'passing another staff member''s id does not leak their shift -- RLS, '
  'not the function''s own filter, decides visibility');

select is(
  (select staff_name from public.list_staff_shifts()
    where id = '97111111-1111-1111-1111-111111111111'),
  'Sita Staff',
  'list_staff_shifts joins in the staff member''s full_name from profiles');

set local request.jwt.claims to
  '{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}';

select is(
  (select count(*)::int from public.list_staff_shifts(
    p_staff_id => '10000000-0000-0000-0000-000000000004')),
  1,
  'admin filtering by staff_id sees exactly that staff member''s shift');

select is(
  (select count(*)::int from public.list_staff_shifts(p_from => '2026-09-02')),
  1,
  'admin filtering by p_from excludes earlier shifts');

reset role;
set local role anon;
set local request.jwt.claims to '{"role":"anon"}';

select throws_ok(
  $$select * from public.list_staff_shifts()$$,
  '42501', null, 'anon cannot call list_staff_shifts');

select * from finish();
rollback;
```

That file has 18 assertions total: `has_table`, `has_function`, 4
`throws_ok`, 3 `lives_ok`, 1 `throws_like`, and 8 `is` calls — matching
`select plan(18);` at the top.

- [ ] **Step 2: Run the test file to verify it fails**

Run: `supabase test db`
Expected: FAIL — `staff_shifts` table and `list_staff_shifts` function do
not exist yet (`has_table`/`has_function` report not-ok, and every
subsequent statement in the file errors out because the table/function
it references doesn't exist).

- [ ] **Step 3: Write the migration**

```sql
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
  created_by uuid not null references public.profiles(id),
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
create policy staff_shifts_admin_all on public.staff_shifts
  for all to authenticated
  using (public.is_admin())
  with check (public.is_admin());

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
```

- [ ] **Step 4: Reset the local database and run the test file to verify it passes**

Run: `supabase db reset && supabase test db`
Expected: `supabase db reset` applies the new migration cleanly (it also
re-runs `seed.sql`, so the fixture ids referenced above exist). `supabase
test db` then runs every file under `supabase/tests/`, including the new
one, and reports all assertions passing — including the 12 pre-existing
test files, which must stay green (this migration adds a table; it does
not touch anything they cover).

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/0021_staff_shifts.sql supabase/tests/17_staff_shifts_test.sql
git commit -m "feat(db): add staff_shifts table, RLS, and list_staff_shifts RPC"
```

---

## Task 2: `StaffShift` Dart model

**Files:**
- Create: `lib/data/models/staff_shift.dart`
- Test: `test/data/staff_shift_test.dart`

**Interfaces:**
- Consumes: nothing new (uses `TimeOfDay` from `package:flutter/material.dart`).
- Produces: `class StaffShift` with fields `id, staffId, staffName, shiftDate,
  startTime, endTime, notes, createdAt`; `StaffShift.fromJson(Map<String,
  dynamic>)` (parses a `list_staff_shifts()` row — `staff_name` present, or a
  plain `staff_shifts` table row — `staff_name` absent, both handled);
  `.toInsert()` (payload for a table insert/update, no `id`/`created_at`/
  `staff_name`); top-level `String formatTimeOfDay(TimeOfDay)` and
  `TimeOfDay parseTimeOfDay(String)`, matching `property_form_screen.dart`'s
  `HH:mm` convention exactly so the two features never disagree on format.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/data/models/staff_shift.dart';

void main() {
  group('formatTimeOfDay / parseTimeOfDay', () {
    test('formats and round-trips a morning time', () {
      const time = TimeOfDay(hour: 9, minute: 5);
      expect(formatTimeOfDay(time), '09:05');
      expect(parseTimeOfDay('09:05'), time);
    });

    test('parses a value with seconds, as Postgrest returns for `time`', () {
      expect(parseTimeOfDay('17:30:00'), const TimeOfDay(hour: 17, minute: 30));
    });
  });

  group('StaffShift.fromJson', () {
    test('parses a plain staff_shifts table row (no staff_name)', () {
      final shift = StaffShift.fromJson(const {
        'id': 's1',
        'staff_id': 'u1',
        'shift_date': '2026-09-01',
        'start_time': '09:00:00',
        'end_time': '17:00:00',
        'notes': null,
        'created_at': '2026-08-19T10:00:00Z',
      });

      expect(shift.id, 's1');
      expect(shift.staffId, 'u1');
      expect(shift.staffName, isNull);
      expect(shift.shiftDate, DateTime.parse('2026-09-01'));
      expect(shift.startTime, const TimeOfDay(hour: 9, minute: 0));
      expect(shift.endTime, const TimeOfDay(hour: 17, minute: 0));
    });

    test('parses a list_staff_shifts() row, including staff_name', () {
      final shift = StaffShift.fromJson(const {
        'id': 's2',
        'staff_id': 'u2',
        'staff_name': 'Sita Staff',
        'shift_date': '2026-09-02',
        'start_time': '10:00:00',
        'end_time': '18:00:00',
        'notes': 'cover shift',
        'created_at': '2026-08-19T10:00:00Z',
      });

      expect(shift.staffName, 'Sita Staff');
      expect(shift.notes, 'cover shift');
    });
  });

  test('toInsert never includes id, staff_name, or created_at', () {
    final shift = StaffShift.fromJson(const {
      'id': 's1',
      'staff_id': 'u1',
      'staff_name': 'Sita Staff',
      'shift_date': '2026-09-01',
      'start_time': '09:00:00',
      'end_time': '17:00:00',
      'notes': null,
      'created_at': '2026-08-19T10:00:00Z',
    });

    final payload = shift.toInsert();
    expect(payload.containsKey('id'), isFalse);
    expect(payload.containsKey('staff_name'), isFalse);
    expect(payload.containsKey('created_at'), isFalse);
    expect(payload['staff_id'], 'u1');
    expect(payload['shift_date'], '2026-09-01');
    expect(payload['start_time'], '09:00');
    expect(payload['end_time'], '17:00');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/staff_shift_test.dart`
Expected: FAIL — `lib/data/models/staff_shift.dart` does not exist yet
(compilation error: "Error when reading ... staff_shift.dart").

- [ ] **Step 3: Write the model**

```dart
import 'package:flutter/material.dart';

/// `HH:mm` (24-hour, no seconds) -- the exact convention
/// `property_form_screen.dart` already uses for `Property.checkInTime`/
/// `checkOutTime`, kept identical here so the app never has two different
/// time-of-day text formats.
String formatTimeOfDay(TimeOfDay t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// Parses either `HH:mm` or `HH:mm:ss` (Postgrest serialises a Postgres
/// `time` column with seconds) into a [TimeOfDay] -- only the first two
/// components are read, so a `:00` seconds suffix is silently ignored
/// rather than crashing `int.parse`.
TimeOfDay parseTimeOfDay(String raw) {
  final parts = raw.split(':');
  return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
}

/// One assigned shift. [staffName] is populated only when this came from
/// `list_staff_shifts()` (the RPC every screen actually reads through) --
/// `null` is never treated as an error, just "not fetched with a name."
class StaffShift {
  const StaffShift({
    required this.id,
    required this.staffId,
    required this.shiftDate,
    required this.startTime,
    required this.endTime,
    this.staffName,
    this.notes,
    this.createdAt,
  });

  final String id;
  final String staffId;
  final String? staffName;
  final DateTime shiftDate;
  final TimeOfDay startTime;
  final TimeOfDay endTime;
  final String? notes;
  final DateTime? createdAt;

  factory StaffShift.fromJson(Map<String, dynamic> json) => StaffShift(
        id: json['id'] as String,
        staffId: json['staff_id'] as String,
        staffName: json['staff_name'] as String?,
        shiftDate: DateTime.parse(json['shift_date'] as String),
        startTime: parseTimeOfDay(json['start_time'] as String),
        endTime: parseTimeOfDay(json['end_time'] as String),
        notes: json['notes'] as String?,
        createdAt: json['created_at'] == null
            ? null
            : DateTime.parse(json['created_at'] as String),
      );

  /// Payload for an insert/update -- deliberately excludes `id` (server-
  /// assigned on insert, unchanged on update via a separate `.eq('id', ...)`
  /// clause), `staff_name` (a read-only join result, not a column), and
  /// `created_at` (server-assigned default).
  Map<String, dynamic> toInsert() => {
        'staff_id': staffId,
        'shift_date': shiftDate.toIso8601String().substring(0, 10),
        'start_time': formatTimeOfDay(startTime),
        'end_time': formatTimeOfDay(endTime),
        'notes': notes,
      };
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/data/staff_shift_test.dart`
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/data/models/staff_shift.dart test/data/staff_shift_test.dart
git commit -m "feat(model): add StaffShift, matching list_staff_shifts()"
```

---

## Task 3: `StaffShiftRepository`

**Files:**
- Create: `lib/data/repositories/staff_shift_repository.dart`

**Interfaces:**
- Consumes: `StaffShift`, `StaffShift.fromJson`, `StaffShift.toInsert`
  (Task 2); `supabaseProvider` (`lib/core/supabase_client.dart`);
  `mapPostgrestError` (`lib/core/errors.dart`).
- Produces: `class StaffShiftRepository` with methods `list({String?
  staffId, DateTime? from, DateTime? to}) -> Future<List<StaffShift>>`,
  `createRange({required String staffId, required DateTimeRange range,
  required TimeOfDay start, required TimeOfDay end, String? notes}) ->
  Future<void>`, `updateOne(StaffShift shift) -> Future<StaffShift>`,
  `delete(String id) -> Future<void>`; providers
  `staffShiftRepositoryProvider` (`Provider<StaffShiftRepository>`) and
  `staffShiftsProvider` (`FutureProvider.family<List<StaffShift>,
  StaffShiftFilter>`), plus the `typedef StaffShiftFilter = ({String?
  staffId, DateTime? from, DateTime? to})` record type Tasks 4-6 watch.

This repository has no dedicated unit-test file, matching this codebase's
existing convention for simple CRUD repositories: `RateRepository`
(`lib/data/repositories/rate_repository.dart`) has none either — its
behaviour is exercised through `rate_rules_screen_test.dart`'s
`FakeRateRepository`, and the database-level behaviour (RLS, the RPC) is
already covered by Task 1's pgTAP file. Tasks 4-6 do the same here with a
`FakeStaffShiftRepository`. This task's own verification is `flutter
analyze` — there is no branching logic in this file worth a unit test on
its own; it is a thin, direct wrapper.

- [ ] **Step 1: Write the repository**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors.dart';
import '../../core/supabase_client.dart';
import '../models/staff_shift.dart';

/// The (staff, date-range) an admin or staff screen wants to see --
/// `staffId: null` means "every staff member" (admin only; RLS returns
/// nothing useful for a non-admin regardless), `from`/`to: null` means "no
/// bound on that side." A record, not positional params, so
/// `FutureProvider.family` can key on it directly.
typedef StaffShiftFilter = ({String? staffId, DateTime? from, DateTime? to});

class StaffShiftRepository {
  StaffShiftRepository(this._db);
  final SupabaseClient _db;

  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } catch (e) {
      throw mapPostgrestError(e);
    }
  }

  String _dateOnly(DateTime d) => d.toIso8601String().substring(0, 10);

  /// Reads through `list_staff_shifts()` (not a direct table select) --
  /// see that function's own comment in `0021_staff_shifts.sql` for why:
  /// it joins in `profiles.full_name` and applies exactly the same RLS a
  /// hand-written query would, so a staff/accountant caller passing
  /// [staffId] for someone else simply gets zero rows back, never an error
  /// and never someone else's shift.
  Future<List<StaffShift>> list({
    String? staffId,
    DateTime? from,
    DateTime? to,
  }) =>
      _guard(() async {
        final rows = await _db.rpc('list_staff_shifts', params: {
          'p_staff_id': staffId,
          'p_from': from == null ? null : _dateOnly(from),
          'p_to': to == null ? null : _dateOnly(to),
        }) as List<dynamic>;
        return rows
            .map((e) => StaffShift.fromJson(e as Map<String, dynamic>))
            .toList();
      });

  /// Inserts one row per calendar day in [range] (inclusive of both ends),
  /// all carrying the same [start]/[end]/[notes] -- a single day is simply
  /// a range whose start equals its end. One batched `insert` call, not
  /// one round trip per day.
  Future<void> createRange({
    required String staffId,
    required DateTimeRange range,
    required TimeOfDay start,
    required TimeOfDay end,
    String? notes,
  }) =>
      _guard(() async {
        final rows = <Map<String, dynamic>>[];
        for (var d = range.start;
            !d.isAfter(range.end);
            d = d.add(const Duration(days: 1))) {
          rows.add({
            'staff_id': staffId,
            'shift_date': _dateOnly(d),
            'start_time': formatTimeOfDay(start),
            'end_time': formatTimeOfDay(end),
            'notes': notes,
          });
        }
        await _db.from('staff_shifts').insert(rows);
      });

  /// Edits one already-created shift row in place (date, time, notes --
  /// not a bulk range operation; that's [createRange]'s job for new
  /// assignments only).
  Future<StaffShift> updateOne(StaffShift shift) => _guard(() async {
        final row = await _db
            .from('staff_shifts')
            .update(shift.toInsert())
            .eq('id', shift.id)
            .select()
            .single();
        return StaffShift.fromJson(row);
      });

  Future<void> delete(String id) => _guard(() async {
        await _db.from('staff_shifts').delete().eq('id', id);
      });
}

final staffShiftRepositoryProvider = Provider<StaffShiftRepository>(
  (ref) => StaffShiftRepository(ref.watch(supabaseProvider)),
);

final staffShiftsProvider =
    FutureProvider.family<List<StaffShift>, StaffShiftFilter>(
  (ref, filter) => ref.watch(staffShiftRepositoryProvider).list(
        staffId: filter.staffId,
        from: filter.from,
        to: filter.to,
      ),
);
```

- [ ] **Step 2: Run `flutter analyze` to verify it compiles cleanly**

Run: `flutter analyze`
Expected: "No issues found!" — this file introduces no new lint or type
errors. (There is no test-fail/test-pass cycle for this task; see the
rationale above the steps.)

- [ ] **Step 3: Commit**

```bash
git add lib/data/repositories/staff_shift_repository.dart
git commit -m "feat(repo): add StaffShiftRepository over list_staff_shifts()"
```

---

## Task 4: Admin "Staff shifts" screen

**Files:**
- Create: `lib/features/admin/staff_shifts_screen.dart`
- Test: `test/features/admin/staff_shifts_screen_test.dart`
- Modify: `lib/core/router.dart` — add the `/admin/staff-shifts` route
- Modify: `lib/features/admin/admin_home_screen.dart` — add a destination
  entry linking to it

**Interfaces:**
- Consumes: `StaffShift`, `StaffShiftRepository`,
  `staffShiftRepositoryProvider`, `staffShiftsProvider`, `StaffShiftFilter`,
  `formatTimeOfDay` (Tasks 2-3); `AdminProfile`, `adminProfilesProvider`
  (`lib/data/repositories/user_admin_repository.dart`, already exists);
  `UserRole` (`lib/data/models/app_user.dart`, already exists).
- Produces: `class StaffShiftsScreen` (the list+filter screen) and `class
  StaffShiftFormScreen` (the create/edit form, pushed imperatively — same
  shape as `RateRuleFormScreen`).

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/data/models/admin_profile.dart';
import 'package:pasala/data/models/app_user.dart';
import 'package:pasala/data/models/staff_shift.dart';
import 'package:pasala/data/repositories/staff_shift_repository.dart';
import 'package:pasala/data/repositories/user_admin_repository.dart';
import 'package:pasala/features/admin/staff_shifts_screen.dart';

/// In-memory stand-in for [StaffShiftRepository], mirroring
/// `FakeRateRepository` in `rate_rules_screen_test.dart`.
class FakeStaffShiftRepository implements StaffShiftRepository {
  final List<StaffShift> store = [];
  final List<String> deletedIds = [];
  int _idCounter = 0;

  @override
  Future<List<StaffShift>> list({
    String? staffId,
    DateTime? from,
    DateTime? to,
  }) async =>
      store.where((s) {
        if (staffId != null && s.staffId != staffId) return false;
        if (from != null && s.shiftDate.isBefore(from)) return false;
        if (to != null && s.shiftDate.isAfter(to)) return false;
        return true;
      }).toList();

  @override
  Future<void> createRange({
    required String staffId,
    required DateTimeRange range,
    required TimeOfDay start,
    required TimeOfDay end,
    String? notes,
  }) async {
    for (var d = range.start; !d.isAfter(range.end); d = d.add(const Duration(days: 1))) {
      store.add(StaffShift(
        id: 'shift-${_idCounter++}',
        staffId: staffId,
        staffName: staffId == 'staff-1' ? 'Sita Staff' : 'Anil Accounts',
        shiftDate: d,
        startTime: start,
        endTime: end,
        notes: notes,
      ));
    }
  }

  @override
  Future<StaffShift> updateOne(StaffShift shift) async {
    store.removeWhere((s) => s.id == shift.id);
    store.add(shift);
    return shift;
  }

  @override
  Future<void> delete(String id) async {
    deletedIds.add(id);
    store.removeWhere((s) => s.id == id);
  }
}

const _staffProfile = AdminProfile(
  id: 'staff-1',
  email: 'staff@pasala.test',
  role: UserRole.staff,
  fullName: 'Sita Staff',
  createdAt: DateTime.utc(2026, 1, 1),
);

Widget _appFor(FakeStaffShiftRepository repo) => ProviderScope(
      overrides: [
        staffShiftRepositoryProvider.overrideWithValue(repo),
        adminProfilesProvider.overrideWith((ref) async => const [_staffProfile]),
      ],
      child: const MaterialApp(home: StaffShiftsScreen()),
    );

void main() {
  testWidgets('shows an empty state when no shifts exist yet', (tester) async {
    await tester.pumpWidget(_appFor(FakeStaffShiftRepository()));
    await tester.pumpAndSettle();

    expect(find.text('No shifts assigned yet'), findsOneWidget);
  });

  // `showDateRangePicker` opens a real OS-level calendar dialog, not a
  // plain widget, so a widget test cannot drive an end-to-end "tap Save"
  // flow for the range-creation form without a much heavier interaction
  // harness. This test instead covers the two things that ARE meaningfully
  // testable at each end: the FAB actually opens the form (below), and the
  // fake's `createRange` fans one range out into one row per day, which is
  // the exact contract `StaffShiftFormScreen._save()` depends on --
  // covered here as a plain unit test against the fake, not a widget test.
  test(
      'FakeStaffShiftRepository.createRange creates one row per day in the '
      'range, all with the same time', () async {
    final repo = FakeStaffShiftRepository();

    await repo.createRange(
      staffId: 'staff-1',
      range: DateTimeRange(start: DateTime(2026, 9, 1), end: DateTime(2026, 9, 2)),
      start: const TimeOfDay(hour: 9, minute: 0),
      end: const TimeOfDay(hour: 17, minute: 0),
    );

    expect(repo.store, hasLength(2));
    expect(repo.store.map((s) => s.shiftDate),
        [DateTime(2026, 9, 1), DateTime(2026, 9, 2)]);
    expect(repo.store.every((s) => s.startTime == const TimeOfDay(hour: 9, minute: 0)),
        isTrue);
  });

  testWidgets('the FAB opens the assign-shift form with a staff picker', (
    tester,
  ) async {
    await tester.pumpWidget(_appFor(FakeStaffShiftRepository()));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    expect(find.text('Assign shift'), findsOneWidget);
    expect(find.byKey(const Key('shift-form-staff-picker')), findsOneWidget);
  });

  testWidgets('lists an existing shift with staff name, date, and time range',
      (tester) async {
    final repo = FakeStaffShiftRepository()
      ..store.add(const StaffShift(
        id: 's1',
        staffId: 'staff-1',
        staffName: 'Sita Staff',
        shiftDate: DateTime(2026, 9, 1),
        startTime: TimeOfDay(hour: 9, minute: 0),
        endTime: TimeOfDay(hour: 17, minute: 0),
      ));

    await tester.pumpWidget(_appFor(repo));
    await tester.pumpAndSettle();

    expect(find.text('Sita Staff'), findsOneWidget);
    expect(find.textContaining('09:00'), findsOneWidget);
    expect(find.textContaining('17:00'), findsOneWidget);
  });

  testWidgets('confirming delete removes the shift', (tester) async {
    final repo = FakeStaffShiftRepository()
      ..store.add(StaffShift(
        id: 's1',
        staffId: 'staff-1',
        staffName: 'Sita Staff',
        shiftDate: DateTime(2026, 9, 1),
        startTime: const TimeOfDay(hour: 9, minute: 0),
        endTime: const TimeOfDay(hour: 17, minute: 0),
      ));

    await tester.pumpWidget(_appFor(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(repo.deletedIds, ['s1']);
    expect(find.text('Sita Staff'), findsNothing);
  });
}
```

This test file has one plain `test` and four `testWidgets` blocks in total.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/admin/staff_shifts_screen_test.dart`
Expected: FAIL — `lib/features/admin/staff_shifts_screen.dart` does not
exist yet (compilation error).

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
import '../../data/models/admin_profile.dart';
import '../../data/models/app_user.dart';
import '../../data/models/staff_shift.dart';
import '../../data/repositories/staff_shift_repository.dart';
import '../../data/repositories/user_admin_repository.dart';

final _dateFormat = DateFormat('d MMM yyyy');

/// `/admin/staff-shifts` -- admin-only (gated the same way every other
/// `/admin/*` management route is, not the staff-or-above carve-out
/// `/admin/dashboard`/`/admin/reports` get, since assigning a shift is a
/// write action). Lists every shift across every staff/accountant member,
/// filterable by staff member and date range.
class StaffShiftsScreen extends ConsumerStatefulWidget {
  const StaffShiftsScreen({super.key});

  @override
  ConsumerState<StaffShiftsScreen> createState() => _StaffShiftsScreenState();
}

class _StaffShiftsScreenState extends ConsumerState<StaffShiftsScreen> {
  String? _staffId;
  DateTimeRange? _dateRange;

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(DateTime.now().year - 1),
      lastDate: DateTime(DateTime.now().year + 2),
      initialDateRange: _dateRange,
    );
    if (picked != null) setState(() => _dateRange = picked);
  }

  @override
  Widget build(BuildContext context) {
    final filter = (staffId: _staffId, from: _dateRange?.start, to: _dateRange?.end);
    final shifts = ref.watch(staffShiftsProvider(filter));
    final profiles = ref.watch(adminProfilesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Staff shifts')),
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
                        key: const Key('shift-staff-picker'),
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
                IconButton(
                  key: const Key('shift-date-filter'),
                  icon: const Icon(Icons.date_range_outlined),
                  tooltip: 'Filter by date range',
                  onPressed: _pickDateRange,
                ),
                if (_dateRange != null)
                  IconButton(
                    icon: const Icon(Icons.clear),
                    tooltip: 'Clear date filter',
                    onPressed: () => setState(() => _dateRange = null),
                  ),
              ],
            ),
          ),
          Expanded(
            child: AsyncView(
              value: shifts,
              onRetry: () => ref.invalidate(staffShiftsProvider(filter)),
              empty: () => const EmptyState(
                icon: Icons.event_busy_outlined,
                title: 'No shifts assigned yet',
                message: 'Tap + to assign a staff member their first shift.',
              ),
              data: (list) => ListView(
                children: [
                  for (final shift in list)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: Spacing.md,
                        vertical: Spacing.xs,
                      ),
                      child: Card(
                        child: ListTile(
                          title: Text(shift.staffName ?? shift.staffId),
                          subtitle: Text(
                            [
                              _dateFormat.format(shift.shiftDate),
                              '${formatTimeOfDay(shift.startTime)} – '
                                  '${formatTimeOfDay(shift.endTime)}',
                              if (shift.notes != null && shift.notes!.isNotEmpty)
                                shift.notes!,
                            ].join(' · '),
                          ),
                          trailing: PopupMenuButton<String>(
                            onSelected: (value) =>
                                _onMenuSelected(context, filter, shift, value),
                            itemBuilder: (context) => const [
                              PopupMenuItem(value: 'edit', child: Text('Edit')),
                              PopupMenuItem(value: 'delete', child: Text('Delete')),
                            ],
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
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const StaffShiftFormScreen()),
        ),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _onMenuSelected(
    BuildContext context,
    StaffShiftFilter filter,
    StaffShift shift,
    String value,
  ) {
    switch (value) {
      case 'edit':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => StaffShiftFormScreen(existing: shift),
          ),
        );
      case 'delete':
        _delete(context, filter, shift);
    }
  }

  Future<void> _delete(
    BuildContext context,
    StaffShiftFilter filter,
    StaffShift shift,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Delete this shift for ${shift.staffName ?? shift.staffId}?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      await ref.read(staffShiftRepositoryProvider).delete(shift.id);
      ref.invalidate(staffShiftsProvider(filter));
    } on BookingFailure catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(FailureView.messageFor(e))));
      }
    }
  }
}

/// Create/edit form for a [StaffShift]. Creating always assigns a date
/// RANGE (one row per day, via [StaffShiftRepository.createRange]);
/// editing an existing row changes just that one day in place (via
/// [StaffShiftRepository.updateOne]) -- the date-range picker is hidden
/// once [existing] is set, since an existing row is already a single day.
class StaffShiftFormScreen extends ConsumerStatefulWidget {
  const StaffShiftFormScreen({super.key, this.existing});

  final StaffShift? existing;

  @override
  ConsumerState<StaffShiftFormScreen> createState() => _StaffShiftFormScreenState();
}

class _StaffShiftFormScreenState extends ConsumerState<StaffShiftFormScreen> {
  late final TextEditingController _notes;
  String? _staffId;
  DateTimeRange? _range;
  TimeOfDay _start = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _end = const TimeOfDay(hour: 17, minute: 0);
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _notes = TextEditingController(text: existing?.notes ?? '');
    _staffId = existing?.staffId;
    if (existing != null) {
      _range = DateTimeRange(start: existing.shiftDate, end: existing.shiftDate);
      _start = existing.startTime;
      _end = existing.endTime;
    }
  }

  @override
  void dispose() {
    _notes.dispose();
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

  Future<void> _pickStart() async {
    final picked = await showTimePicker(context: context, initialTime: _start);
    if (picked != null) setState(() => _start = picked);
  }

  Future<void> _pickEnd() async {
    final picked = await showTimePicker(context: context, initialTime: _end);
    if (picked != null) setState(() => _end = picked);
  }

  Future<void> _save() async {
    final staffId = _staffId;
    final range = _range;
    if (staffId == null || range == null) {
      setState(() => _error = 'Pick a staff member and a date range.');
      return;
    }
    if (_endBeforeOrEqualStart) {
      setState(() => _error = 'End time must be after start time.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final existing = widget.existing;
      final notes = _notes.text.trim();
      if (existing == null) {
        await ref.read(staffShiftRepositoryProvider).createRange(
              staffId: staffId,
              range: range,
              start: _start,
              end: _end,
              notes: notes.isEmpty ? null : notes,
            );
      } else {
        await ref.read(staffShiftRepositoryProvider).updateOne(StaffShift(
              id: existing.id,
              staffId: staffId,
              shiftDate: range.start,
              startTime: _start,
              endTime: _end,
              notes: notes.isEmpty ? null : notes,
            ));
      }
      ref.invalidate(staffShiftsProvider);
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

  bool get _endBeforeOrEqualStart =>
      (_end.hour * 60 + _end.minute) <= (_start.hour * 60 + _start.minute);

  @override
  Widget build(BuildContext context) {
    final profiles = ref.watch(adminProfilesProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? 'Assign shift' : 'Edit shift'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(Spacing.lg),
            children: [
              profiles.when(
                loading: () => const SizedBox.shrink(),
                error: (_, _) => const SizedBox.shrink(),
                data: (list) {
                  final staffOrAbove =
                      list.where((p) => p.role != UserRole.customer).toList();
                  return DropdownButtonFormField<String>(
                    key: const Key('shift-form-staff-picker'),
                    initialValue: _staffId,
                    decoration: const InputDecoration(labelText: 'Staff member'),
                    items: [
                      for (final p in staffOrAbove)
                        DropdownMenuItem(value: p.id, child: Text(p.fullName ?? p.email)),
                    ],
                    onChanged: widget.existing == null
                        ? (value) => setState(() => _staffId = value)
                        : null,
                  );
                },
              ),
              const SizedBox(height: Spacing.md),
              ListTile(
                key: const Key('shift-form-date-range'),
                contentPadding: EdgeInsets.zero,
                title: Text(widget.existing == null ? 'Date range' : 'Date'),
                subtitle: Text(
                  _range == null
                      ? 'Required'
                      : widget.existing == null
                          ? '${_dateFormat.format(_range!.start)} – '
                              '${_dateFormat.format(_range!.end)}'
                          : _dateFormat.format(_range!.start),
                ),
                onTap: widget.existing == null ? _pickRange : null,
              ),
              const SizedBox(height: Spacing.sm),
              ListTile(
                key: const Key('shift-form-start-time'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Start time'),
                subtitle: Text(formatTimeOfDay(_start)),
                onTap: _pickStart,
              ),
              ListTile(
                key: const Key('shift-form-end-time'),
                contentPadding: EdgeInsets.zero,
                title: const Text('End time'),
                subtitle: Text(formatTimeOfDay(_end)),
                onTap: _pickEnd,
              ),
              const SizedBox(height: Spacing.sm),
              TextField(
                key: const Key('shift-form-notes'),
                controller: _notes,
                decoration: const InputDecoration(
                  labelText: 'Notes',
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
                onPressed: _busy ? null : _save,
                child: const Text('Save'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

Note: `_dateFormat` inside `StaffShiftFormScreen.build` refers to the
top-level `_dateFormat` already declared once at the top of this file
(shared with `StaffShiftsScreen`) — do not declare it a second time.

- [ ] **Step 4: Wire the route and the admin-home link**

In `lib/core/router.dart`, add the import and the route (admin-only —
`/admin/staff-shifts` is not in `redirectFor`'s staff-or-above carve-out
list, so it is admin-only automatically, same as `/admin/properties`):

```dart
import '../features/admin/staff_shifts_screen.dart';
```

```dart
          GoRoute(
            path: '/admin/staff-shifts',
            builder: (_, _) => const StaffShiftsScreen(),
          ),
```

(placed alongside the other `/admin/*` `GoRoute` entries, e.g. right after
the existing `/admin/users` route).

In `lib/features/admin/admin_home_screen.dart`, add a new destination
tuple to `_destinations`, after the `'Users'` entry:

```dart
    (
      icon: Icons.event_busy_outlined,
      title: 'Staff shifts',
      subtitle: 'Assign and manage staff work shifts',
      path: '/admin/staff-shifts',
    ),
```

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/features/admin/staff_shifts_screen_test.dart`
Expected: PASS (5 tests). Then run `flutter analyze` — expect "No issues
found!"

- [ ] **Step 6: Commit**

```bash
git add lib/features/admin/staff_shifts_screen.dart lib/core/router.dart \
  lib/features/admin/admin_home_screen.dart \
  test/features/admin/staff_shifts_screen_test.dart
git commit -m "feat(admin): add Staff shifts screen (assign/edit/delete)"
```

---

## Task 5: Staff Time Slots screen (list)

**Files:**
- Create: `lib/features/staff/time_slots_screen.dart`
- Test: `test/features/staff/time_slots_screen_test.dart`
- Modify: `lib/core/router.dart` — replace the `PlaceholderSectionScreen`
  builder for `/staff/time-slots` with `TimeSlotsScreen`

**Interfaces:**
- Consumes: `StaffShift`, `staffShiftsProvider`, `StaffShiftFilter`,
  `formatTimeOfDay` (Tasks 2-3); `currentUserProvider`
  (`lib/data/repositories/auth_repository.dart`, already exists, as used
  by `StaffProfileScreen`).
- Produces: `class TimeSlotsScreen`; top-level pure function
  `List<StaffShift> upcomingShiftsFrom(List<StaffShift> shifts, DateTime
  today)` (filters to `shiftDate >= today`, sorted ascending by date).

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/data/models/app_user.dart';
import 'package:pasala/data/models/staff_shift.dart';
import 'package:pasala/data/repositories/auth_repository.dart';
import 'package:pasala/data/repositories/staff_shift_repository.dart';
import 'package:pasala/features/staff/time_slots_screen.dart';

const _staff = AppUser(id: 'staff-1', email: 'staff@pasala.test', role: UserRole.staff);

StaffShift _shift(String id, DateTime date, {int hour = 9}) => StaffShift(
      id: id,
      staffId: 'staff-1',
      staffName: 'Sita Staff',
      shiftDate: date,
      startTime: TimeOfDay(hour: hour, minute: 0),
      endTime: TimeOfDay(hour: hour + 8, minute: 0),
    );

void main() {
  group('upcomingShiftsFrom', () {
    test('drops shifts before today and sorts the rest ascending', () {
      final today = DateTime(2026, 9, 5);
      final shifts = [
        _shift('s1', DateTime(2026, 9, 10)),
        _shift('s2', DateTime(2026, 9, 1)), // in the past
        _shift('s3', DateTime(2026, 9, 5)), // today counts as upcoming
        _shift('s4', DateTime(2026, 9, 7)),
      ];

      final result = upcomingShiftsFrom(shifts, today);

      expect(result.map((s) => s.id), ['s3', 's4', 's1']);
    });
  });

  Widget _appFor(List<StaffShift> shifts) => ProviderScope(
        overrides: [
          currentUserProvider.overrideWith((ref) => Stream.value(_staff)),
          staffShiftsProvider.overrideWith((ref, filter) async => shifts),
        ],
        child: const MaterialApp(home: TimeSlotsScreen()),
      );

  testWidgets('shows an empty state when the staff member has no shifts', (
    tester,
  ) async {
    await tester.pumpWidget(_appFor(const []));
    await tester.pumpAndSettle();

    expect(find.text('No shifts assigned yet'), findsOneWidget);
  });

  testWidgets('lists each shift with its date and time range', (tester) async {
    await tester.pumpWidget(_appFor([
      _shift('s1', DateTime(2026, 12, 1), hour: 9),
    ]));
    await tester.pumpAndSettle();

    expect(find.textContaining('09:00'), findsOneWidget);
    expect(find.textContaining('17:00'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/staff/time_slots_screen_test.dart`
Expected: FAIL — `lib/features/staff/time_slots_screen.dart` does not
exist yet.

- [ ] **Step 3: Write the screen**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/empty_state.dart';
import '../../data/models/staff_shift.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/staff_shift_repository.dart';

final _dateFormat = DateFormat('EEE, d MMM yyyy');

/// Upcoming-first: drops anything before [today] and sorts the rest by
/// date ascending. Pure so the ordering rule is testable without a
/// widget. `today` itself counts as upcoming -- a shift later this same
/// day is still something the staff member needs to see.
List<StaffShift> upcomingShiftsFrom(List<StaffShift> shifts, DateTime today) {
  final day = DateUtils.dateOnly(today);
  final upcoming = shifts.where((s) => !s.shiftDate.isBefore(day)).toList();
  upcoming.sort((a, b) => a.shiftDate.compareTo(b.shiftDate));
  return upcoming;
}

/// `/staff/time-slots` -- the signed-in staff/accountant member's own
/// upcoming shifts, as a plain chronological list. Same underlying data as
/// `WorkSchedulesScreen`'s calendar; this is the list presentation (see
/// the design spec's "same shift data, two views" decision).
class TimeSlotsScreen extends ConsumerWidget {
  const TimeSlotsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider).value;
    final staffId = user?.id;
    final shiftsAsync = staffId == null
        ? AsyncValue<List<StaffShift>>.data(const [])
        : ref.watch(staffShiftsProvider((staffId: staffId, from: null, to: null)));

    return Scaffold(
      appBar: AppBar(title: const Text('Time Slots')),
      body: AsyncView(
        value: shiftsAsync,
        onRetry: staffId == null
            ? null
            : () => ref.invalidate(
                staffShiftsProvider((staffId: staffId, from: null, to: null))),
        empty: () => const EmptyState(
          icon: Icons.access_time_outlined,
          title: 'No shifts assigned yet',
          message: 'Your admin hasn\'t assigned you a shift yet.',
        ),
        data: (all) {
          final upcoming = upcomingShiftsFrom(all, DateTime.now());
          if (upcoming.isEmpty) {
            return const EmptyState(
              icon: Icons.access_time_outlined,
              title: 'No shifts assigned yet',
              message: 'Your admin hasn\'t assigned you a shift yet.',
            );
          }
          return ListView(
            padding: const EdgeInsets.all(Spacing.md),
            children: [
              for (final shift in upcoming)
                Card(
                  child: ListTile(
                    title: Text(_dateFormat.format(shift.shiftDate)),
                    subtitle: Text(
                      [
                        '${formatTimeOfDay(shift.startTime)} – '
                            '${formatTimeOfDay(shift.endTime)}',
                        if (shift.notes != null && shift.notes!.isNotEmpty)
                          shift.notes!,
                      ].join(' · '),
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

In `lib/core/router.dart`, replace the existing `/staff/time-slots`
`GoRoute` (which currently builds a `PlaceholderSectionScreen`) with:

```dart
          GoRoute(
            path: '/staff/time-slots',
            builder: (_, _) => const TimeSlotsScreen(),
          ),
```

Add the import:

```dart
import '../features/staff/time_slots_screen.dart';
```

Leave every other `/staff/*` placeholder route (`working-hours`, `leave`,
`tasks`, `schedules` — Task 6 handles `schedules`, `daily-status`)
untouched.

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/features/staff/time_slots_screen_test.dart`
Expected: PASS (3 tests). Then run `flutter analyze` — expect "No issues
found!"

- [ ] **Step 6: Commit**

```bash
git add lib/features/staff/time_slots_screen.dart lib/core/router.dart \
  test/features/staff/time_slots_screen_test.dart
git commit -m "feat(staff): wire /staff/time-slots to a real shift list"
```

---

## Task 6: Staff Work Schedules screen (calendar)

**Files:**
- Create: `lib/features/staff/work_schedules_screen.dart`
- Test: `test/features/staff/work_schedules_screen_test.dart`
- Modify: `lib/core/router.dart` — replace the `PlaceholderSectionScreen`
  builder for `/staff/schedules` with `WorkSchedulesScreen`

**Interfaces:**
- Consumes: same as Task 5, plus `StaffShift.shiftDate`.
- Produces: `class WorkSchedulesScreen`; top-level pure function `bool
  hasShiftOn(DateTime day, List<StaffShift> shifts)`.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/data/models/app_user.dart';
import 'package:pasala/data/models/staff_shift.dart';
import 'package:pasala/data/repositories/auth_repository.dart';
import 'package:pasala/data/repositories/staff_shift_repository.dart';
import 'package:pasala/features/staff/work_schedules_screen.dart';

const _staff = AppUser(id: 'staff-1', email: 'staff@pasala.test', role: UserRole.staff);

void main() {
  group('hasShiftOn', () {
    final shifts = [
      StaffShift(
        id: 's1',
        staffId: 'staff-1',
        shiftDate: DateTime(2026, 9, 10),
        startTime: const TimeOfDay(hour: 9, minute: 0),
        endTime: const TimeOfDay(hour: 17, minute: 0),
      ),
    ];

    test('true for a day with a shift', () {
      expect(hasShiftOn(DateTime(2026, 9, 10), shifts), isTrue);
    });

    test('false for a day with no shift', () {
      expect(hasShiftOn(DateTime(2026, 9, 11), shifts), isFalse);
    });

    test('ignores time-of-day when comparing the calendar date', () {
      expect(hasShiftOn(DateTime(2026, 9, 10, 23, 59), shifts), isTrue);
    });
  });

  Widget _appFor(List<StaffShift> shifts) => ProviderScope(
        overrides: [
          currentUserProvider.overrideWith((ref) => Stream.value(_staff)),
          staffShiftsProvider.overrideWith((ref, filter) async => shifts),
        ],
        child: const MaterialApp(home: WorkSchedulesScreen()),
      );

  testWidgets('a day with a shift is tappable and shows its details', (
    tester,
  ) async {
    final today = DateTime.now();
    final shiftDay = DateTime(today.year, today.month, 15);
    await tester.pumpWidget(_appFor([
      StaffShift(
        id: 's1',
        staffId: 'staff-1',
        shiftDate: shiftDay,
        startTime: const TimeOfDay(hour: 9, minute: 0),
        endTime: const TimeOfDay(hour: 17, minute: 0),
        notes: 'Front desk',
      ),
    ]));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(Key('shift-day-${shiftDay.day}')));
    await tester.pumpAndSettle();

    expect(find.text('Front desk'), findsOneWidget);
    expect(find.textContaining('09:00'), findsOneWidget);
  });

  testWidgets('a day with no shift is not tappable', (tester) async {
    await tester.pumpWidget(_appFor(const []));
    await tester.pumpAndSettle();

    final today = DateTime.now();
    await tester.tap(find.byKey(Key('shift-day-${today.day}')));
    await tester.pumpAndSettle();

    // No dialog opened -- nothing to show for a shift-free day.
    expect(find.byType(AlertDialog), findsNothing);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/staff/work_schedules_screen_test.dart`
Expected: FAIL — `lib/features/staff/work_schedules_screen.dart` does not
exist yet.

- [ ] **Step 3: Write the screen**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/async_view.dart';
import '../../data/models/staff_shift.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/staff_shift_repository.dart';

final _dateFormat = DateFormat('EEE, d MMM yyyy');

/// True when [shifts] contains a shift on [day] -- calendar-date equality
/// only, time-of-day ignored. Pure so it's testable without a widget, the
/// same way `statusFor` in `availability_calendar.dart` is.
bool hasShiftOn(DateTime day, List<StaffShift> shifts) =>
    shifts.any((s) => DateUtils.isSameDay(s.shiftDate, day));

/// `/staff/schedules` -- a month calendar of the signed-in staff/
/// accountant member's own shifts. Visually mirrors
/// `AvailabilityCalendar`'s grid (Monday-first, prev/next chevrons) without
/// reusing that widget directly -- it is reservation-shaped and
/// booking-tap oriented, not a fit for "does this day have a shift."
class WorkSchedulesScreen extends ConsumerStatefulWidget {
  const WorkSchedulesScreen({super.key});

  @override
  ConsumerState<WorkSchedulesScreen> createState() => _WorkSchedulesScreenState();
}

class _WorkSchedulesScreenState extends ConsumerState<WorkSchedulesScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  void _showShiftsFor(DateTime day, List<StaffShift> shifts) {
    final dayShifts = shifts.where((s) => DateUtils.isSameDay(s.shiftDate, day)).toList();
    if (dayShifts.isEmpty) return;
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(_dateFormat.format(day)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final shift in dayShifts) ...[
              Text('${formatTimeOfDay(shift.startTime)} – '
                  '${formatTimeOfDay(shift.endTime)}'),
              if (shift.notes != null && shift.notes!.isNotEmpty)
                Text(shift.notes!),
              const SizedBox(height: Spacing.sm),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider).value;
    final staffId = user?.id;
    final shiftsAsync = staffId == null
        ? AsyncValue<List<StaffShift>>.data(const [])
        : ref.watch(staffShiftsProvider((staffId: staffId, from: null, to: null)));
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Work Schedules')),
      body: AsyncView(
        value: shiftsAsync,
        onRetry: staffId == null
            ? null
            : () => ref.invalidate(
                staffShiftsProvider((staffId: staffId, from: null, to: null))),
        data: (shifts) {
          final first = DateTime(_month.year, _month.month, 1);
          final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
          final leadingBlanks = first.weekday - 1;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(Spacing.md),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left),
                      onPressed: () => setState(
                        () => _month = DateTime(_month.year, _month.month - 1),
                      ),
                    ),
                    Text(
                      DateFormat.yMMMM().format(_month),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right),
                      onPressed: () => setState(
                        () => _month = DateTime(_month.year, _month.month + 1),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
                child: GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 7,
                    mainAxisSpacing: Spacing.xs,
                    crossAxisSpacing: Spacing.xs,
                  ),
                  itemCount: leadingBlanks + daysInMonth,
                  itemBuilder: (context, i) {
                    if (i < leadingBlanks) return const SizedBox.shrink();
                    final day =
                        DateTime(_month.year, _month.month, i - leadingBlanks + 1);
                    final hasShift = hasShiftOn(day, shifts);

                    return InkWell(
                      key: Key('shift-day-${day.day}'),
                      onTap: hasShift ? () => _showShiftsFor(day, shifts) : null,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: hasShift
                              ? scheme.primaryContainer
                              : scheme.surface,
                          borderRadius:
                              BorderRadius.circular(PasalaTokens.radiusSm),
                          border: Border.all(color: scheme.outlineVariant),
                        ),
                        child: Center(child: Text('${day.day}')),
                      ),
                    );
                  },
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

In `lib/core/router.dart`, replace the existing `/staff/schedules`
`GoRoute` (currently a `PlaceholderSectionScreen`) with:

```dart
          GoRoute(
            path: '/staff/schedules',
            builder: (_, _) => const WorkSchedulesScreen(),
          ),
```

Add the import:

```dart
import '../features/staff/work_schedules_screen.dart';
```

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/features/staff/work_schedules_screen_test.dart`
Expected: PASS (5 tests). Then run `flutter analyze` — expect "No issues
found!"

- [ ] **Step 6: Commit**

```bash
git add lib/features/staff/work_schedules_screen.dart lib/core/router.dart \
  test/features/staff/work_schedules_screen_test.dart
git commit -m "feat(staff): wire /staff/schedules to a real shift calendar"
```

---

## Task 7: Full-suite verification

**Files:** none created or modified — verification only.

**Interfaces:** none.

- [ ] **Step 1: Reset the local database and run the pgTAP suite**

Run: `supabase db reset && supabase test db`
Expected: every file under `supabase/tests/` (13 files after Task 1)
passes.

- [ ] **Step 2: Run the full Flutter analyzer**

Run: `flutter analyze`
Expected: "No issues found!"

- [ ] **Step 3: Run the full Flutter test suite**

Run: `flutter test`
Expected: every test passes except the three pre-existing, unrelated
`hold_lifecycle_test.dart` failures (present on this branch before this
plan's work started — a `pay-button` key-finder issue unrelated to staff
shifts). If any other test fails, or if those three tests newly pass
(meaning something in this work accidentally fixed unrelated code) or a
*different* set of tests fails, stop and investigate before considering
this task done — don't assume either change is fine without checking.

- [ ] **Step 4: Manual walkthrough note**

This plan's UI cannot be verified end-to-end without a running app and a
browser (per this project's own established practice for UI work). Note
in the final report to the user that automated coverage (pgTAP + widget
tests) is complete and clean, but a manual click-through — sign in as
admin, assign a shift, sign in as the staff member, confirm it shows on
both `/staff/schedules` and `/staff/time-slots` — has not been done, and
offer to run the app for that walkthrough if the user wants it before
considering this feature fully verified.

- [ ] **Step 5: Commit (if Step 1-3 required any fixes)**

Only if any fix was needed to make the suite clean:

```bash
git add -A
git commit -m "fix: address full-suite verification findings for staff shifts"
```

If no fixes were needed, skip this step — there is nothing to commit.
