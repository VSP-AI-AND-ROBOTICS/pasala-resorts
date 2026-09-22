# Pasala Resorts — Staff Working Hours Design

Date: 2026-08-25
Builds on: the staff Daily Work Status feature (spec
`2026-08-20-staff-daily-work-status-design.md`), which introduced the
`attendance_records` table this feature reads. No new sibling data
dependency otherwise — this is the fifth and final placeholder in the
staff-operations hub to get a real implementation.
Status: approved by user in brainstorming session; ready for implementation
planning

## 1. What This Is

The last remaining placeholder section in the staff-operations hub:
**Working Hours**, a read-only screen showing the signed-in staff member's
full check-in/check-out history with a computed duration on each row —
"how many hours did I work that day." This closes a gap Daily Work
Status's own design spec explicitly deferred at the time: "No computed
hours-worked figure... a deliberate future enhancement."

Scope, by role:

- **Staff/accountant** get `/staff/working-hours` wired to a real screen:
  every attendance record on file for them, newest first, each showing
  the computed hours-worked duration alongside the existing check-in/
  check-out times.
- **Admin** gets nothing new here — no admin screen, per the approved
  design (admin already has the read-only Attendance screen from Daily
  Work Status, which is judged sufficient for oversight; a duplicate
  admin view of the same rows with an added duration column was
  explicitly declined).

## 2. Scope

**In scope:** a real implementation of the existing staff placeholder
route `/staff/working-hours` (replacing `PlaceholderSectionScreen` at
that one route only), and a pure duration-computation helper.

**Out of scope, and why:** no new database table, migration, or RLS
policy (this feature reads `attendance_records` exactly as Daily Work
Status already exposes it — see §3); no admin screen; no date filter or
history bound (approved as "everything on record, newest first"); no
weekly or monthly rollup/aggregate (approved as "daily list," not a
summary view); no editing or correction of any kind (attendance records
were already established as an "honest, unedited log" by Daily Work
Status, and this screen doesn't change that).

## 3. Data

No new schema. This feature is a pure UI layer over data Daily Work
Status's `attendance_records` table and `AttendanceRepository` already
expose in full:

```dart
// Already exists (lib/data/repositories/attendance_repository.dart):
Future<List<AttendanceRecord>> list({String? staffId, DateTime? date})
final attendanceRecordsProvider =
    FutureProvider.family<List<AttendanceRecord>, AttendanceFilter>(...);
```

The screen calls this exactly the way `DailyStatusScreen` already does
for its own history section — `attendanceRecordsProvider((staffId: self,
date: null))` — filtered server-side to the signed-in user's own records,
never a client-side filter over every staff member's rows.

The only new logic in this entire feature is a pure function:

```dart
/// Time worked for one completed record, or null if [record] has no
/// check-out yet (still checked in / a missed checkout that was never
/// closed -- see Daily Work Status's own "stays open indefinitely"
/// design decision, which this screen inherits unchanged).
Duration? durationOf(AttendanceRecord record) {
  final checkOutAt = record.checkOutAt;
  if (checkOutAt == null) return null;
  return checkOutAt.difference(record.checkInAt);
}
```

Kept as a standalone top-level function (not a method on
`AttendanceRecord`) so it's testable in isolation without a widget,
matching the exact convention `todayRecordFrom`/`pastRecordsFrom`
already established in `daily_status_screen.dart`.

## 4. Screen — `/staff/working-hours`

Replaces the existing `PlaceholderSectionScreen` route registration
only.

A single list, newest first, one row per attendance record:

- **Still checked in** (`checkOutAt == null`): date, check-in time,
  "Still checked in" — no duration shown (there is nothing to compute
  yet; showing a live-ticking duration was considered and rejected as
  scope creep for a screen whose only job is historical review).
- **Completed** (`checkOutAt` set): date, check-in time, check-out time,
  and the computed duration formatted as `"Xh Ym"` (e.g. "8h 45m"; a
  duration under an hour renders as `"Ym"` alone, e.g. "45m", rather
  than `"0h 45m"`).

`EmptyState` when the staff member has no attendance records at all
("No hours recorded yet"), matching the exact convention every sibling
staff screen uses for its own empty case.

No FAB, no filters, no per-row action of any kind — this is the first
staff-facing screen in the hub with zero interactivity beyond scrolling,
which is intentional: every other staff screen has a reason to write
(check in/out, submit leave, update a task's status), and this one's
entire purpose is looking, not doing.

## 5. Explicitly Deferred

- **No weekly/monthly totals.** Per the approved design, this is a
  daily list, not a rollup. If a "how many hours this week" summary
  becomes a real need later, it's an additive header/section on this
  same screen, not a redesign.
- **No admin view.** Per the approved design, admin's existing
  Attendance screen (Daily Work Status) is judged sufficient for
  oversight; adding a duration column there, if ever wanted, is a
  small addition to that existing screen, not a new one.
- **No date-range filter or history bound.** Per the approved design,
  the list shows everything on record. If this ever becomes a real
  performance concern for a long-tenured staff member, pagination or a
  bound is a future, additive change to the query — not something this
  slice needs to anticipate.
- **No live-ticking duration for an open (still-checked-in) day.** The
  screen is a historical review, not a live dashboard; Daily Work
  Status's own screen already owns "what's happening right now."
- **No correction, editing, or export of any kind.** Matches Daily
  Work Status's own "honest, unedited log" principle unchanged — this
  screen only ever reads.

## 6. Testing

- Pure logic: `durationOf` tested directly without a widget — a
  completed record returns the correct `Duration`, a record with no
  `checkOutAt` returns `null`.
- Pure logic: the "Xh Ym" / "Ym"-only formatting helper tested directly
  for both branches (e.g. `Duration(hours: 8, minutes: 45)` → "8h 45m",
  `Duration(minutes: 45)` → "45m").
- Widget tests: `EmptyState` when the staff member has no records;
  renders a still-checked-in row with no duration shown; renders a
  completed row with the correct formatted duration; confirms a staff
  member never sees another staff member's records even when seeded
  (matching every sibling screen's own coverage of this exact case).
- No dedicated repository test file needed — this feature adds no new
  repository code; `AttendanceRepository` is already covered by its own
  existing tests and by this screen's widget tests via
  `FakeAttendanceRepository`.
- `flutter test`, `flutter analyze`, and `supabase test db` all run
  clean at the end. `supabase test db` is unaffected by this feature
  (no new migration), so its assertion count is unchanged from the
  current baseline. The three pre-existing, unrelated
  `hold_lifecycle_test.dart` failures are expected to remain exactly
  those three, unchanged by this work.
