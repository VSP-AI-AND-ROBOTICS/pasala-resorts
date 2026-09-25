# OTA Sync Reliability (P9) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make each unit's iCal sync with Airbnb and Booking.com work with the formats those OTAs really publish, and show whether it worked. Each feed shows "Last sync 5 min ago · 3 events" or its error in red, and has a Sync now button that waits for fresh data. The export link is one an OTA can read. The README walks an owner through linking a real listing.

**Architecture:** One migration, `0058_ota_sync_status.sql`, adds status columns to `ical_feeds` and four internal SQL helpers. The helpers parse a feed (`ical_parse_feed`), read one date value (`ical_parse_when`), turn an all-day event into the resort's check-in/check-out period (`ical_event_period`, through `build_period`), and recognise an OTA echoing our own booking back (`ical_event_is_echo`). The migration also redefines `ical_poll_feed`, `ical_poll_all_feeds` and `ical_parse_events` on top of these helpers, and adds a URL trigger that raises P0039. No security definer function is added. A new Deno Edge Function, `ical-export`, serves the export link as `text/calendar`. In the app, `IcalSyncRunner` runs Sync now over the existing `IcalSource` seam, pure functions in `feed_sync_status.dart` turn a feed into status lines, and the OTA screen shows those lines.

**Tech Stack:** Supabase Postgres 15 (plpgsql, RLS, pg_net, pg_cron, pgTAP via `supabase test db`), Supabase Edge Functions on Deno 2 (`deno test`), Flutter 3.44 / Dart 3.10, Riverpod 3.3.

**Spec:** `docs/superpowers/specs/2026-09-25-p9-ota-sync-reliability-design.md`

## Global Constraints

- One migration: `supabase/migrations/0058_ota_sync_status.sql`. Tasks 1–4 each edit it. After every edit, rebuild with `supabase db reset` (re-runs every migration and `supabase/seed.sql`), then run pgTAP. Before the first reset, dump local data if you need it: `mkdir -p ../pasala-db-backups && supabase db dump --local --data-only -f ../pasala-db-backups/local-before-p9.sql`.
- New pgTAP file: `supabase/tests/48_ota_sync_test.sql`. Tasks 1–4 build it up section by section, and each section relies on the state the earlier ones leave. Run one file with `supabase test db supabase/tests/48_ota_sync_test.sql`, and the whole suite with `supabase test db`. `supabase/tests/14_ical_test.sql` and `supabase/tests/37_tenancy_isolation_test.sql` must keep passing unchanged.
- New error code **P0039**, with messages `invalid_feed_url` and `duplicate_feed`. Raise it with `raise exception using errcode = 'P0039', message = 'invalid_feed_url'`. Existing codes keep their meanings: P0002 not found, P0005 bad input, P0020 not_a_member, P0022 resort_suspended.
- No new `security definer` function. The four new helpers are `stable`, have `set search_path = public, pg_temp`, and are revoked from `public`, `anon` and `authenticated`. The definer allow-list in `37_tenancy_isolation_test.sql` does not change.
- When changing an existing function, copy its **latest** definition. `ical_poll_feed` is latest in `0045_resort_functions.sql`. `ical_poll_all_feeds` and `ical_parse_events` are latest in `0018_ical.sql`.
- pgTAP conventions (from `37_tenancy_isolation_test.sql` and `14_ical_test.sql`):
  - Switch users with `set local role authenticated; set local request.jwt.claims to '{"sub":"<uuid>","role":"authenticated"}';`.
  - Run as the cron job (no JWT) with `reset role; set local request.jwt.claims to '';`.
  - `now()` is fixed for the whole test transaction.
  - `\gset` stores a query result in a psql variable, which is read back as `:'name'`.
- Deno: the function lives in `supabase/functions/ical-export/`, with `index.ts` (wiring only), `handler.ts` (all logic), `types.ts` (contract), `handler_test.ts` and `deno.json`, the same layout P6 uses. The test imports `jsr:@std/assert@1` by full specifier and never imports `index.ts`. Run `deno test supabase/functions/ical-export/`.
- Dart: repositories map every error through `mapPostgrestError` (`lib/core/errors.dart`). Widget and unit tests use `test/support/fake_ical_source.dart` and never a real `SupabaseClient`.
- UI copy, exact:
  - `Never synced`
  - `Last sync <ago> · <n> event(s)`, where `<ago>` is `just now`, `5 min ago`, `3 h ago`, `1 day ago` or `2 days ago`, and the count is `1 event` or `3 events`
  - `Sync failed <ago>: <error>`
  - `Last good sync <ago>`
  - `No successful sync yet`
  - `Automatic sync has not run for over an hour. Press Sync now.`
  - `The OTA no longer serves this link. Copy the export link from the OTA again and replace this feed.`
  - `Check that you pasted the calendar export link, not the listing page.`
  - Buttons: `Sync now`, `Remove`, `Syncing…`
  - Snackbars:
    - `Synced -- <n> event(s)`, followed by `, <n> conflict(s) skipped` and `, <n> unreadable event(s) skipped` when those counts are not zero
    - `Sync failed: <error>`
    - `Still syncing -- the result will show here shortly.`
  - Form error: `Paste the calendar link (starts with https:// or webcal://).`
  - P0039:
    - `invalid_feed_url`: `That is not a calendar link. Paste the link that starts with https:// or webcal://.`
    - `duplicate_feed`: `This calendar is already added to this unit.`
  - Server error texts, written by `ical_poll_feed`:
    - `not a calendar: the link did not return iCal data`
    - `HTTP <code>`
    - `request timed out`
    - `fetch failed: <reason>`
- A status is never shown by colour alone. Warning lines carry `Icons.warning_amber_outlined` and error lines carry `Icons.error_outline`.
- Commands:
  - `flutter test <path>`, `flutter test`, and `flutter analyze`. The analyzer baseline is 2 infos in `service_request_screen.dart`; add no new issues.
  - Never run `dart format` on whole directories or on existing files. Format only the lines you write.
  - Revert `pubspec.lock` changes that only bump the SDK.
  - `deno fmt supabase/functions/ical-export/` is fine, because it touches only the new files.
- Commits: every message ends with a blank line and then `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Do not push.

## Review Focus

1. **An OTA returns a valid but empty calendar**, for example during an OTA outage or after an owner clears the listing by mistake. The expected result is an `ok` sync with `0 events`. Nothing already imported is cancelled or moved. Owning test: Task 3, the empty-calendar assertions.
2. **A resort outside India, with its own check-in and check-out times.** All-day events must use that resort's zone and times, including summer time, and never Asia/Kolkata or UTC. Owning test: Task 3, the Europe/London resort, 15:00/10:00 in July.
3. **A link pasted with spaces or a newline around it, or in upper-case `WEBCAL://`.** The expected result is a stored normalised `https://` link, and a later paste of the same calendar in another form is still caught as a duplicate. Owning tests: Task 4 (a newline plus `WEBCAL://` is trimmed and rewritten; the `webcal://` form of a stored `https://` link is a duplicate).
4. **The phone's clock is behind the server's**, so `last_synced_at` is in the future. The status line must read `just now`, never a negative count or `-3 min ago`. Owning test: Task 7, `syncAgo` with a time 3 minutes ahead.
5. **The feed is removed, in another tab or by another admin, while Sync now is polling.** `ical_poll_feed` raises P0002, which is shown as the readable `That item no longer exists.` and followed by a reload of the list. It must not appear as a spinner that never stops or a raw error. Owning test: Task 7, the widget test for a feed removed while Sync now runs.

## Plan decisions (where the spec is silent or leaves a choice)

- `ical_parse_feed` returns every non-cancelled `VEVENT`, including unreadable ones, which carry `error`. `ical_poll_feed` counts an unreadable event as `failed` and puts it in the `N event(s) failed to import and were skipped (last error: …)` note. That keeps the note format `14_ical_test.sql` asserts.
- `ical_parse_events` keeps its signature and becomes a SQL wrapper that returns the error-free rows of `ical_parse_feed(p_ics, 'UTC')`. It is redefined in **Task 3**, together with `ical_poll_feed`, not in Task 2. Doing it earlier would make the old poller skip the blank-UID event that `14_ical_test.sql` expects to be counted as failed.
- For an all-day event, `dtstart`/`dtend` are midnight of `start_date`/`end_date` in the zone passed in. The poller never uses them. It calls `ical_event_period`, which uses `build_period`. The wrapper passes `'UTC'`, so its results are the same as before for all-day events.
- `ical_event_is_echo` checks each night by the resort-local midnight that ends it (`(d + 1) at time zone <resort tz>`). A native nightly stay covering night `d` always contains that instant, and a day-use slot never does.
- `last_synced_at` is set to the collected request's `pending_since`, which is when the data was fetched. `last_ok_at` is set to the same value on an `ok` sync.
- On a failed fetch after a response was collected in the same call, the collected result stands and nothing more is written. On a failed fetch with nothing collected, the call records `last_status = 'error'` and `last_error = 'fetch failed: …'`.
- `IcalSyncRunner` calls `syncFeed` once to start, then up to 7 more times, 2 seconds apart. It returns the first finished result from those later calls, or `IcalSyncResult(status: 'pending')` after 8 calls in all. Its dependencies are public fields, `source` and `wait`, so the Task 1 stub has no unused private fields.
- `FakeIcalSource` moves from `ical_screen_test.dart` to `test/support/fake_ical_source.dart`, and gains `syncScript`, `syncCalls`, `feedsCalls`, `addError` and `syncError`. Its `exportUrl` mirrors the new link shape, `https://fake.supabase.test/functions/v1/ical-export/<token>.ics`.
- The OTA screen's buttons become labelled `TextButton.icon`s in a `Wrap` under the status lines, so a long error wraps at phone width. They keep their keys, `ical-sync-feed` and `ical-remove-feed`.
- The URL trigger is invoker, not definer. Its duplicate check reads `ical_feeds` through the caller's RLS, and owners and admins see every feed of their resort. There is no unique index, because an existing duplicate would make the migration fail.
- The Edge Function reads the calendar with the anon key through the existing `ical_export_public`, which is granted to `anon`. It does not use the service role.

## Execution tracks

After Task 1, the database track and the other tracks share no files and can run in parallel, for example in separate worktrees branched from Task 1's commit and merged back before Task 9. The Flutter tasks never need a database, because their tests use `FakeIcalSource`. The Deno task never needs one either, because its tests use a fake store and a fake `fetch`.

| Task | Track | Depends on | Files it owns |
|---|---|---|---|
| 1 Interface contract | both | none | `0058` (schema + stubs), `48` (fixtures + contract), `ical_feed.dart`, `ical_repository.dart` (`IcalSyncResult`), `ical_sync_runner.dart` (stub), `fake_ical_source.dart`, `ical_screen_test.dart` (fake moved), `ical_feed_test.dart`, `ical-export/types.ts` |
| 2 Parser | DB | 1 | `0058`, `48` |
| 3 Polling | DB | 2 | `0058`, `48` |
| 4 Feed URL rules | DB | 3 | `0058`, `48` |
| 5 `ical-export` Edge Function | Track (Deno) | 1 | `ical-export/{handler.ts,handler_test.ts,index.ts,deno.json}`, `supabase/config.toml` |
| 6 Sync runner and export link | Track (Flutter) | 1 | `ical_sync_runner.dart`, `ical_repository.dart` (export link), `ical_sync_runner_test.dart`, `ical_export_url_test.dart` |
| 7 OTA screen | Track (Flutter) | 6 | `feed_sync_status.dart`, `ical_screen.dart`, `errors.dart`, `feed_sync_status_test.dart`, `ical_screen_test.dart`, `errors_test.dart` |
| 8 README and STATUS | Track (docs) | 1 | `README.md`, `docs/STATUS.md` |
| 9 Integration | both | 2–8 | none (verification) |

- The database track is strictly sequential: Tasks 2, 3 and 4 share one migration, one test file and one local Postgres.
- Task 7 waits for Task 6, because its widget tests run the real runner. Tasks 5, 6 and 8 can run alongside each other and alongside the database track.

---

## File Structure

**Database**
- Create `supabase/migrations/0058_ota_sync_status.sql`, with these sections:
  1. The status columns and their backfill.
  2. `ical_parse_when` and `ical_parse_feed`.
  3. `ical_event_period` and `ical_event_is_echo`, their revokes, and the redefined `ical_parse_events`, `ical_poll_feed` and `ical_poll_all_feeds`.
  4. The URL rules trigger.
- Create `supabase/tests/48_ota_sync_test.sql`: fixtures, contract, parser fixtures, poll fixtures and URL rules.

**Edge Function**
- Create `supabase/functions/ical-export/types.ts`: `CalendarLookup`, `CalendarStore`, `ICS_CONTENT_TYPE` and `TOKEN_PATTERN`.
- Create `supabase/functions/ical-export/handler.ts`: `tokenFrom`, `handle` and `restStore`.
- Create `supabase/functions/ical-export/handler_test.ts`, `index.ts` and `deno.json`.
- Modify `supabase/config.toml`: `[functions.ical-export] verify_jwt = false`.

**App**
- Modify `lib/data/models/ical_feed.dart`: `FeedSyncStatus`, `feedSyncStatusFromDb`, and the new `IcalFeed` fields.
- Modify `lib/data/repositories/ical_repository.dart`: the new `IcalSyncResult` fields and `isFinal` (Task 1), and `icalExportUrl` with `exportUrl` using it (Task 6).
- Create `lib/data/repositories/ical_sync_runner.dart`: `SyncWait`, `IcalSyncRunner` and `icalSyncRunnerProvider`.
- Create `lib/features/ota/feed_sync_status.dart`:
  - `FeedLineTone` and `FeedLine`
  - `syncAgo`, `eventCount`, `feedErrorHint`, `feedStatusLines` and `syncOutcomeMessage`
  - the copy constants `staleAfter`, `hintRelink`, `hintNotCalendar` and `staleWarning`
- Modify `lib/features/ota/ical_screen.dart`: the status lines, Sync now through the runner, the form's validation and `clock`.
- Modify `lib/core/errors.dart`: `FeedUrlRejected` and P0039.
- Create `test/support/fake_ical_source.dart`, `test/data/ical_sync_runner_test.dart`, `test/data/ical_export_url_test.dart` and `test/features/ota/feed_sync_status_test.dart`.
- Modify `test/data/ical_feed_test.dart`, `test/features/ota/ical_screen_test.dart` and `test/core/errors_test.dart`.

**Docs**
- Modify `README.md`: the OTA paragraph, the new section "Linking a real Airbnb or Booking.com listing", and the out-of-scope bullet.
- Modify `docs/STATUS.md`: the phase 2 iCal bullet, item 5, and the known-limitations bullet.

---

## Phase 0: Interface

### Task 1: Interface contract (schema, helper signatures, Dart and TS types)

**Track:** both. Every later task depends on it.

**Files:**
- Create: `supabase/migrations/0058_ota_sync_status.sql`
- Create: `supabase/tests/48_ota_sync_test.sql`
- Create: `supabase/functions/ical-export/types.ts`
- Modify: `lib/data/models/ical_feed.dart`
- Modify: `lib/data/repositories/ical_repository.dart` (`IcalSyncResult` only)
- Create: `lib/data/repositories/ical_sync_runner.dart`
- Create: `test/support/fake_ical_source.dart`
- Modify: `test/features/ota/ical_screen_test.dart` (uses the moved fake)
- Test: `test/data/ical_feed_test.dart`

**Interfaces:**
- Consumes:
  - `public.ical_feeds` (0018, with `property_id` from 0043)
  - `public.build_period(uuid, date, date, uuid default null)` (0005)
  - `public.ical_import_event(uuid, text, timestamptz, timestamptz)` and `public.ical_poll_feed(uuid)` (both latest in 0045)
  - `IcalSource`, `icalSourceProvider` and `IcalSyncResult` (`lib/data/repositories/ical_repository.dart`)
  - `IcalFeed` (`lib/data/models/ical_feed.dart`)
- Produces (SQL; later tasks replace only the stub bodies):
  - Columns `ical_feeds.last_status text` (`ok`, `error` or null), `ical_feeds.last_event_count int` (`>= 0`) and `ical_feeds.last_ok_at timestamptz`.
  - `public.ical_parse_when(p_value text, p_params text, p_tz text, out at_ts timestamptz, out on_date date)`
  - `public.ical_parse_feed(p_ics text, p_tz text default 'UTC') returns table (uid text, dtstart timestamptz, dtend timestamptz, start_date date, end_date date, summary text, error text)`
  - `public.ical_event_period(p_unit_id uuid, p_dtstart timestamptz, p_dtend timestamptz, p_start_date date, p_end_date date) returns tstzrange`
  - `public.ical_event_is_echo(p_unit_id uuid, p_start_date date, p_end_date date) returns boolean`
  - The `ical_poll_feed` result gains `events` and `echoes` (Task 3): `{status:'ok', events, created, updated, unchanged, conflicts, echoes, failed}`.
- Produces (Dart):
  - `enum FeedSyncStatus { ok, error }` and `FeedSyncStatus? feedSyncStatusFromDb(String?)`.
  - `IcalFeed` gains `FeedSyncStatus? lastStatus`, `int? lastEventCount` and `DateTime? lastOkAt`.
  - `IcalSyncResult` gains `int? events`, `created`, `updated`, `unchanged`, `echoes` and `failed`, together with the existing `conflicts`. It also gains `bool get isFinal`, which is true for `ok` and `error`.
  - `typedef SyncWait = Future<void> Function(Duration delay)`.
  - `class IcalSyncRunner(IcalSource source, {SyncWait? wait, int maxCalls = 8, Duration interval = 2 s})`, with public fields `source`, `wait`, `maxCalls` and `interval`, and `Future<IcalSyncResult> syncNow(String feedId)`. The body is a stub until Task 6.
  - `final icalSyncRunnerProvider = Provider<IcalSyncRunner>`.
  - Test support: `FakeIcalSource`, with the fields `rows`, `token`, `feedsError`, `addError`, `syncError` and `syncScript`, the `syncResult` setter, the logs `feedsCalls`, `syncCalls`, `added` and `removed`, and `rotated`. Also `icalFeed({...})`.
- Produces (TS, `supabase/functions/ical-export/types.ts`):
  - `CalendarLookup = {kind:'ok', ics} | {kind:'not_found'} | {kind:'unavailable', detail}`
  - `interface CalendarStore { lookup(token): Promise<CalendarLookup> }`
  - `ICS_CONTENT_TYPE`
  - `TOKEN_PATTERN`

- [ ] **Step 1: Record the baselines**

Run: `supabase db reset && supabase test db 2>&1 | tail -20`, then `flutter analyze 2>&1 | tail -3`, then `flutter test 2>&1 | tail -1`, then `deno --version`
Expected: write down the pgTAP failure count and names. The tenancy ledger records 3 pre-existing time-of-day failures around the Asia/Kolkata midnight boundary. Also write down the analyzer count (2 infos) and the Flutter pass count. Later tasks compare against these. Deno must be version 2 or later.

- [ ] **Step 2: Write the failing pgTAP contract test**

Create `supabase/tests/48_ota_sync_test.sql`:

```sql
-- OTA sync reliability (P9), added in 0058_ota_sync_status.sql. See
-- docs/superpowers/specs/2026-09-25-p9-ota-sync-reliability-design.md.
--
-- One file, built up by the plan's database tasks in order: each section
-- relies on the state the sections before it leave behind.
--
-- Fixtures: resort R (Asia/Kolkata, check-in 14:00, check-out 11:00 -- the
-- column defaults) with an admin (Asha) and a staff member (Sunil); units
-- Cottage A and Cottage B; an inactive contract feed on Cottage B.
begin;
select plan(12);

insert into auth.users (id, email) values
  ('f9000000-0000-4000-8000-000000000001','ota-admin@example.com'),
  ('f9000000-0000-4000-8000-000000000002','ota-staff@example.com');

insert into public.properties (id, name, slug) values
  ('f9000000-0000-4000-8000-000000000010','Resort R','ota-r');

insert into public.resort_members (property_id, user_id, role) values
  ('f9000000-0000-4000-8000-000000000010','f9000000-0000-4000-8000-000000000001','admin'),
  ('f9000000-0000-4000-8000-000000000010','f9000000-0000-4000-8000-000000000002','staff');

insert into public.units (id, property_id, name, capacity_base, capacity_max) values
  ('f9000000-0000-4000-8000-000000000011','f9000000-0000-4000-8000-000000000010','Cottage A',2,4),
  ('f9000000-0000-4000-8000-000000000012','f9000000-0000-4000-8000-000000000010','Cottage B',2,4);

insert into public.ical_feeds (id, unit_id, url, label, is_active) values
  ('f9000000-0000-4000-8000-000000000030','f9000000-0000-4000-8000-000000000012',
   'https://example.invalid/contract.ics','Contract',false);

-- === Task 1: the contract ===================================================

select has_column('public', 'ical_feeds', 'last_status', 'ical_feeds has last_status');
select has_column('public', 'ical_feeds', 'last_event_count',
  'ical_feeds has last_event_count');
select has_column('public', 'ical_feeds', 'last_ok_at', 'ical_feeds has last_ok_at');
select throws_ok($$update public.ical_feeds set last_status = 'maybe'
  where id = 'f9000000-0000-4000-8000-000000000030'$$,
  '23514', null, 'last_status is ok, error or null');
select throws_ok($$update public.ical_feeds set last_event_count = -1
  where id = 'f9000000-0000-4000-8000-000000000030'$$,
  '23514', null, 'last_event_count is never negative');
select is((select count(*)::int from unnest(array[
    to_regprocedure('public.ical_parse_when(text, text, text)'),
    to_regprocedure('public.ical_parse_feed(text, text)'),
    to_regprocedure('public.ical_event_period(uuid, timestamptz, timestamptz, date, date)'),
    to_regprocedure('public.ical_event_is_echo(uuid, date, date)')]) f
   where f is not null),
  4, 'the four parser helpers exist with these signatures');
select is((select array_agg(p.parameter_name::text order by p.ordinal_position)
             from information_schema.parameters p
             join information_schema.routines r
               on r.specific_schema = p.specific_schema and r.specific_name = p.specific_name
            where r.routine_schema = 'public' and r.routine_name = 'ical_parse_feed'
              and p.parameter_mode = 'OUT'),
  array['uid','dtstart','dtend','start_date','end_date','summary','error'],
  'ical_parse_feed returns the columns ical_poll_feed reads');
select is((select array_agg(p.parameter_name::text order by p.ordinal_position)
             from information_schema.parameters p
             join information_schema.routines r
               on r.specific_schema = p.specific_schema and r.specific_name = p.specific_name
            where r.routine_schema = 'public' and r.routine_name = 'ical_parse_when'
              and p.parameter_mode = 'OUT'),
  array['at_ts','on_date'], 'ical_parse_when returns at_ts and on_date');
select is((select count(*)::int from pg_proc
            where oid in ('public.ical_parse_when(text, text, text)'::regprocedure,
                          'public.ical_parse_feed(text, text)'::regprocedure,
                          'public.ical_event_period(uuid, timestamptz, timestamptz, date, date)'::regprocedure,
                          'public.ical_event_is_echo(uuid, date, date)'::regprocedure)
              and prosecdef),
  0, 'none of them is security definer, so the definer allow-list does not change');
select is((select array_agg(f::text order by f::text)
             from unnest(array[
               'public.ical_parse_when(text, text, text)',
               'public.ical_parse_feed(text, text)',
               'public.ical_event_period(uuid, timestamptz, timestamptz, date, date)',
               'public.ical_event_is_echo(uuid, date, date)']::regprocedure[]) f
            where has_function_privilege('anon', f, 'execute')),
  null, 'anon can execute none of the parser helpers');
select is((select array_agg(f::text order by f::text)
             from unnest(array[
               'public.ical_parse_when(text, text, text)',
               'public.ical_parse_feed(text, text)',
               'public.ical_event_period(uuid, timestamptz, timestamptz, date, date)',
               'public.ical_event_is_echo(uuid, date, date)']::regprocedure[]) f
            where has_function_privilege('authenticated', f, 'execute')),
  null, 'authenticated cannot either -- they run only inside ical_poll_feed');
select ok(to_regprocedure('public.ical_poll_feed(uuid)') is not null
      and to_regprocedure('public.ical_parse_events(text)') is not null,
  'ical_poll_feed and ical_parse_events keep their signatures');

select * from finish();
rollback;
```

- [ ] **Step 3: Run it to verify it fails**

Run: `supabase test db supabase/tests/48_ota_sync_test.sql`
Expected: FAIL. `has_column … last_status` fails, and the first `throws_ok` reports `column "last_status" … does not exist` instead of 23514.

- [ ] **Step 4: Write the migration's schema and stubs**

Create `supabase/migrations/0058_ota_sync_status.sql`:

```sql
-- OTA sync reliability (P9): per-feed sync status, a parser that reads
-- real Airbnb and Booking.com exports, all-day events placed at the
-- resort's check-in/check-out times, echoes told apart from conflicts,
-- and rules for feed URLs.
-- See docs/superpowers/specs/2026-09-25-p9-ota-sync-reliability-design.md.
--
-- Error code: P0039 -- `invalid_feed_url` / `duplicate_feed` (the
-- ical_feeds URL rules, section 4). Also raised: P0005 (an unreadable
-- event; ical_poll_feed catches it per event and counts it as failed).
--
-- No security definer function is added: the helpers below are internal
-- and run inside the existing ical_poll_feed.

-- ---------------------------------------------------------------------
-- 1. Sync status on each feed. last_synced_at and last_error exist (0018):
--    last_synced_at is when the collected data was fetched; last_error is
--    the feed-level error when last_status = 'error', otherwise a note
--    about skipped events (or null).

alter table public.ical_feeds
  add column last_status text
    constraint ical_feeds_last_status_check
      check (last_status in ('ok', 'error')),
  add column last_event_count int
    constraint ical_feeds_last_event_count_check
      check (last_event_count >= 0),
  add column last_ok_at timestamptz;

-- Feeds that synced before this migration: a recorded error reads as an
-- error until the next poll (at most 15 minutes) rewrites it.
update public.ical_feeds
   set last_status = case when last_error is null then 'ok' else 'error' end,
       last_ok_at  = case when last_error is null then last_synced_at end
 where last_synced_at is not null;

-- ---------------------------------------------------------------------
-- 2. Parsing a feed. Internal: reached only through ical_poll_feed (and,
--    for ical_parse_feed, the ical_parse_events wrapper). Task 2 of the
--    plan replaces these stub bodies.

create function public.ical_parse_when(
  p_value  text,
  p_params text,
  p_tz     text,
  out at_ts   timestamptz,
  out on_date date
)
language plpgsql
stable
set search_path = public, pg_temp
as $$
begin
  raise exception 'ical_parse_when is not implemented yet' using errcode = '0A000';
end;
$$;

create function public.ical_parse_feed(p_ics text, p_tz text default 'UTC')
returns table (
  uid        text,
  dtstart    timestamptz,
  dtend      timestamptz,
  start_date date,
  end_date   date,
  summary    text,
  error      text
)
language plpgsql
stable
set search_path = public, pg_temp
as $$
begin
  raise exception 'ical_parse_feed is not implemented yet' using errcode = '0A000';
end;
$$;

-- ---------------------------------------------------------------------
-- 3. Importing. Task 3 of the plan replaces these stub bodies and then
--    redefines ical_parse_events, ical_poll_feed and ical_poll_all_feeds
--    below the revoke block.

create function public.ical_event_period(
  p_unit_id    uuid,
  p_dtstart    timestamptz,
  p_dtend      timestamptz,
  p_start_date date,
  p_end_date   date
) returns tstzrange
language plpgsql
stable
set search_path = public, pg_temp
as $$
begin
  raise exception 'ical_event_period is not implemented yet' using errcode = '0A000';
end;
$$;

create function public.ical_event_is_echo(
  p_unit_id    uuid,
  p_start_date date,
  p_end_date   date
) returns boolean
language plpgsql
stable
set search_path = public, pg_temp
as $$
begin
  raise exception 'ical_event_is_echo is not implemented yet' using errcode = '0A000';
end;
$$;

-- Internal helpers, same convention as ical_build_document (0018): never
-- callable through PostgREST.
revoke execute on function public.ical_parse_when(text, text, text)
  from public, anon, authenticated;
revoke execute on function public.ical_parse_feed(text, text)
  from public, anon, authenticated;
revoke execute on function
  public.ical_event_period(uuid, timestamptz, timestamptz, date, date)
  from public, anon, authenticated;
revoke execute on function public.ical_event_is_echo(uuid, date, date)
  from public, anon, authenticated;
```

- [ ] **Step 5: Run the database tests**

Run: `supabase db reset && supabase test db supabase/tests/48_ota_sync_test.sql supabase/tests/14_ical_test.sql supabase/tests/37_tenancy_isolation_test.sql`
Expected: PASS. 48 passes 12/12, and 14 and 37 are unchanged.

- [ ] **Step 6: Write the failing Dart model tests**

Append to `test/data/ical_feed_test.dart`, inside `main()` after the last test:

```dart
  test('parses the sync status columns added in 0058', () {
    final feed = IcalFeed.fromJson(const {
      'id': 'f4',
      'unit_id': 'u1',
      'url': 'https://www.airbnb.com/calendar/ical/1.ics',
      'label': 'Airbnb',
      'is_active': true,
      'last_synced_at': '2027-01-01T11:55:00Z',
      'last_error': null,
      'last_status': 'ok',
      'last_event_count': 3,
      'last_ok_at': '2027-01-01T11:55:00+00:00',
    });

    expect(feed.lastStatus, FeedSyncStatus.ok);
    expect(feed.lastEventCount, 3);
    expect(feed.lastOkAt, DateTime.utc(2027, 1, 1, 11, 55));
  });

  test('a feed that never synced has no status, count or last good sync', () {
    final feed = IcalFeed.fromJson(const {
      'id': 'f5',
      'unit_id': 'u1',
      'url': 'https://example.com/1.ics',
      'label': null,
      'last_synced_at': null,
      'last_error': null,
      'last_status': null,
      'last_event_count': null,
      'last_ok_at': null,
    });

    expect(feed.lastStatus, isNull);
    expect(feed.lastEventCount, isNull);
    expect(feed.lastOkAt, isNull);
  });

  test('feedSyncStatusFromDb reads ok and error, and nothing else', () {
    expect(feedSyncStatusFromDb('ok'), FeedSyncStatus.ok);
    expect(feedSyncStatusFromDb('error'), FeedSyncStatus.error);
    expect(feedSyncStatusFromDb('pending'), isNull);
    expect(feedSyncStatusFromDb(null), isNull);
  });

  test('IcalSyncResult reads every count ical_poll_feed returns', () {
    final ok = IcalSyncResult.fromJson(const {
      'status': 'ok',
      'events': 4,
      'created': 2,
      'updated': 0,
      'unchanged': 0,
      'conflicts': 1,
      'echoes': 1,
      'failed': 0,
    });

    expect(ok.events, 4);
    expect(ok.created, 2);
    expect(ok.updated, 0);
    expect(ok.unchanged, 0);
    expect(ok.conflicts, 1);
    expect(ok.echoes, 1);
    expect(ok.failed, 0);
  });

  test('isFinal is true only once a response was collected', () {
    expect(const IcalSyncResult(status: 'ok').isFinal, isTrue);
    expect(const IcalSyncResult(status: 'error').isFinal, isTrue);
    expect(const IcalSyncResult(status: 'requested').isFinal, isFalse);
    expect(const IcalSyncResult(status: 'pending').isFinal, isFalse);
  });
```

- [ ] **Step 7: Run them to verify they fail**

Run: `flutter test test/data/ical_feed_test.dart`
Expected: FAIL to compile. The output names `FeedSyncStatus`, `lastStatus`, `events` and `isFinal` as undefined.

- [ ] **Step 8: Write the Dart contract**

Replace the whole of `lib/data/models/ical_feed.dart` with:

```dart
/// How the last collected response of a feed went (`ical_feeds.last_status`,
/// 0058). [error] is a feed-level failure -- an HTTP error, a timeout, a
/// failed fetch, or a page that is not a calendar. Conflicts and unreadable
/// events are still [ok], with their note in `last_error`.
enum FeedSyncStatus { ok, error }

/// Null for a feed that has never synced (or any label this build does not
/// know).
FeedSyncStatus? feedSyncStatusFromDb(String? value) => switch (value) {
  'ok' => FeedSyncStatus.ok,
  'error' => FeedSyncStatus.error,
  _ => null,
};

/// One row of `public.ical_feeds`: a subscription this unit imports
/// occupancy FROM (e.g. an Airbnb or Booking.com calendar URL), with the
/// sync bookkeeping the OTA screen shows. `last_error` is shown verbatim
/// when present, never hidden or softened.
class IcalFeed {
  const IcalFeed({
    required this.id,
    required this.unitId,
    required this.url,
    required this.isActive,
    this.label,
    this.lastSyncedAt,
    this.lastError,
    this.lastStatus,
    this.lastEventCount,
    this.lastOkAt,
  });

  final String id;
  final String unitId;
  final String url;
  final String? label;
  final bool isActive;

  /// When the data of the last collected response was fetched.
  final DateTime? lastSyncedAt;

  /// The feed-level error when [lastStatus] is [FeedSyncStatus.error];
  /// otherwise a note about skipped events, or null.
  final String? lastError;
  final FeedSyncStatus? lastStatus;

  /// Events read from the feed on the last successful sync.
  final int? lastEventCount;

  /// When the last successful sync's data was fetched.
  final DateTime? lastOkAt;

  factory IcalFeed.fromJson(Map<String, dynamic> json) => IcalFeed(
        id: json['id'] as String,
        unitId: json['unit_id'] as String,
        url: json['url'] as String,
        label: json['label'] as String?,
        isActive: json['is_active'] as bool? ?? true,
        lastSyncedAt: _utc(json['last_synced_at']),
        lastError: json['last_error'] as String?,
        lastStatus: feedSyncStatusFromDb(json['last_status'] as String?),
        lastEventCount: (json['last_event_count'] as num?)?.toInt(),
        lastOkAt: _utc(json['last_ok_at']),
      );
}

DateTime? _utc(Object? value) =>
    value == null ? null : DateTime.parse(value as String).toUtc();
```

In `lib/data/repositories/ical_repository.dart`, replace the whole `IcalSyncResult` class together with its doc comment, from `/// One \`ical_poll_feed\` outcome` down to its closing `}`, with:

```dart
/// One `ical_poll_feed` outcome, as returned by the RPC: `status` is one
/// of `requested` (a fetch was fired; pg_net is asynchronous, see 0018),
/// `pending` (still waiting on a fetch fired earlier), `ok` (a response was
/// collected and processed -- the counts describe its events) or `error`
/// (the fetch or the feed itself failed -- `error` carries why). Never
/// thrown -- a failing feed is what the OTA screen exists to show.
class IcalSyncResult {
  const IcalSyncResult({
    required this.status,
    this.error,
    this.events,
    this.created,
    this.updated,
    this.unchanged,
    this.conflicts,
    this.echoes,
    this.failed,
  });

  final String status;
  final String? error;

  /// Events read from the feed (cancelled ones excluded).
  final int? events;
  final int? created;
  final int? updated;
  final int? unchanged;

  /// Events that overlap a booking here and were skipped.
  final int? conflicts;

  /// Events that only repeat our own bookings back (0058) -- not a problem.
  final int? echoes;

  /// Events that could not be read or imported.
  final int? failed;

  /// A response was collected (`ok` or `error`), as opposed to a fetch
  /// still being on its way (`requested`, `pending`).
  bool get isFinal => status == 'ok' || status == 'error';

  factory IcalSyncResult.fromJson(Map<String, dynamic> json) => IcalSyncResult(
        status: json['status'] as String,
        error: json['error'] as String?,
        events: (json['events'] as num?)?.toInt(),
        created: (json['created'] as num?)?.toInt(),
        updated: (json['updated'] as num?)?.toInt(),
        unchanged: (json['unchanged'] as num?)?.toInt(),
        conflicts: (json['conflicts'] as num?)?.toInt(),
        echoes: (json['echoes'] as num?)?.toInt(),
        failed: (json['failed'] as num?)?.toInt(),
      );
}
```

Create `lib/data/repositories/ical_sync_runner.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ical_repository.dart';

/// How [IcalSyncRunner] waits between calls; tests pass one that returns
/// at once.
typedef SyncWait = Future<void> Function(Duration delay);

/// Drives the OTA screen's "Sync now" (spec decision 13).
///
/// `ical_poll_feed` is a two-call state machine (0018): one call fires a
/// fetch, a later call collects it. A response collected by the FIRST call
/// was fetched before the press (by the 15-minute job), so the runner keeps
/// calling every [interval] and returns the first finished result
/// ([IcalSyncResult.isFinal]) from any later call. After [maxCalls] calls
/// without one it returns `IcalSyncResult(status: 'pending')`.
class IcalSyncRunner {
  IcalSyncRunner(
    this.source, {
    SyncWait? wait,
    this.maxCalls = 8,
    this.interval = const Duration(seconds: 2),
  }) : wait = wait ?? ((delay) => Future<void>.delayed(delay));

  final IcalSource source;
  final SyncWait wait;
  final int maxCalls;
  final Duration interval;

  Future<IcalSyncResult> syncNow(String feedId) {
    throw UnimplementedError('IcalSyncRunner.syncNow is built in Task 6');
  }
}

final icalSyncRunnerProvider = Provider<IcalSyncRunner>(
  (ref) => IcalSyncRunner(ref.watch(icalSourceProvider)),
);
```

- [ ] **Step 9: Move the fake to test support**

Create `test/support/fake_ical_source.dart`:

```dart
import 'package:pasala/data/models/ical_feed.dart';
import 'package:pasala/data/repositories/ical_repository.dart';

/// In-memory [IcalSource] for widget and unit tests. Never touches `Env`:
/// [exportUrl] returns a fixed test string (`flutter test` runs with no
/// `--dart-define`, so the real URL builder would assert).
class FakeIcalSource implements IcalSource {
  List<IcalFeed> rows = [];
  String token = 'faketoken123';
  Object? feedsError;
  Object? addError;
  Object? syncError;

  /// What successive [syncFeed] calls return, in order; the last entry
  /// repeats once the list runs out.
  List<IcalSyncResult> syncScript = [
    const IcalSyncResult(status: 'ok', events: 0, conflicts: 0),
  ];

  /// Shorthand for a script whose every call returns [result].
  set syncResult(IcalSyncResult result) => syncScript = [result];

  int feedsCalls = 0;
  final syncCalls = <String>[];
  final added = <String>[];
  final removed = <String>[];
  bool rotated = false;

  @override
  Future<List<IcalFeed>> feeds(String unitId) async {
    feedsCalls++;
    if (feedsError != null) throw feedsError!;
    return rows;
  }

  @override
  Future<void> addFeed({
    required String unitId,
    required String url,
    String? label,
  }) async {
    if (addError != null) throw addError!;
    added.add(url);
    rows = [
      ...rows,
      IcalFeed(
        id: 'new-${rows.length}',
        unitId: unitId,
        url: url,
        label: label,
        isActive: true,
      ),
    ];
  }

  @override
  Future<void> removeFeed(String feedId) async {
    removed.add(feedId);
    rows = rows.where((f) => f.id != feedId).toList();
  }

  @override
  Future<IcalSyncResult> syncFeed(String feedId) async {
    syncCalls.add(feedId);
    if (syncError != null) throw syncError!;
    final i = syncCalls.length - 1;
    return i < syncScript.length ? syncScript[i] : syncScript.last;
  }

  @override
  Future<String> exportToken(String unitId) async => token;

  @override
  Future<String> rotateExportToken(String unitId) async {
    rotated = true;
    token = 'rotated-token';
    return token;
  }

  @override
  String exportUrl(String token) =>
      'https://fake.supabase.test/functions/v1/ical-export/$token.ics';
}

/// An [IcalFeed] with test defaults.
IcalFeed icalFeed({
  String id = 'f1',
  String unitId = 'u1',
  String url = 'https://www.airbnb.com/calendar/ical/1.ics',
  String? label = 'Airbnb',
  bool isActive = true,
  DateTime? lastSyncedAt,
  String? lastError,
  FeedSyncStatus? lastStatus,
  int? lastEventCount,
  DateTime? lastOkAt,
}) =>
    IcalFeed(
      id: id,
      unitId: unitId,
      url: url,
      label: label,
      isActive: isActive,
      lastSyncedAt: lastSyncedAt,
      lastError: lastError,
      lastStatus: lastStatus,
      lastEventCount: lastEventCount,
      lastOkAt: lastOkAt,
    );
```

In `test/features/ota/ical_screen_test.dart`:
1. Replace everything above `void main() {` (the imports, the inline `FakeIcalSource` class and the `_feed` helper) with:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/data/repositories/ical_repository.dart';
import 'package:pasala/features/ota/ical_screen.dart';

import '../../support/fake_ical_source.dart';

```

2. Replace every `_feed(` with `icalFeed(`: `sed -i '' 's/_feed(/icalFeed(/g' test/features/ota/ical_screen_test.dart`.
3. The fake's export link changed shape, so update the five expectations:
   - `'https://fake.supabase.test/rest/v1/rpc/ical_export_public'` followed by `'?token=abc123&apikey=fake-anon-key',` becomes the single line `'https://fake.supabase.test/functions/v1/ical-export/abc123.ics',`
   - `contains('token=copytoken')` becomes `contains('/copytoken.ics')`
   - `textContaining('token=old-token')` becomes `textContaining('/old-token.ics')`
   - `textContaining('token=rotated-token')` becomes `textContaining('/rotated-token.ics')`
   - `textContaining('token=stays-the-same')` becomes `textContaining('/stays-the-same.ics')`

- [ ] **Step 10: Run the Dart tests and the analyzer**

Run: `flutter test test/data/ical_feed_test.dart test/features/ota/ical_screen_test.dart && flutter analyze lib/data test/support test/features/ota test/data`
Expected: PASS: 9 model tests and 14 screen tests. The screen is unchanged and still calls `syncFeed` once. The analyzer reports `No issues found!`.

- [ ] **Step 11: Write the Edge Function contract**

Create `supabase/functions/ical-export/types.ts`:

```ts
// Contract for the `ical-export` Edge Function (P9). See
// docs/superpowers/specs/2026-09-25-p9-ota-sync-reliability-design.md.
//
// Request:  GET or HEAD /functions/v1/ical-export/<token>.ics
//           (also accepted: /functions/v1/ical-export?token=<token>)
// Response: 200 text/calendar; charset=utf-8 -- the unit's busy dates
//           404 text/plain -- unknown token, or the resort is not active
//           405 text/plain -- any other method (Allow: GET, HEAD)
//           502 text/plain -- the database could not be read

/** What looking a token up in the database can give. */
export type CalendarLookup =
  | { kind: "ok"; ics: string }
  | { kind: "not_found" }
  | { kind: "unavailable"; detail: string };

/** Where the handler reads a calendar from; faked in tests. */
export interface CalendarStore {
  lookup(token: string): Promise<CalendarLookup>;
}

export const ICS_CONTENT_TYPE = "text/calendar; charset=utf-8";

/** `encode(gen_random_bytes(24), 'hex')` -- see 0018_ical.sql. */
export const TOKEN_PATTERN = /^[0-9a-f]{48}$/;
```

Run: `deno check supabase/functions/ical-export/types.ts`
Expected: `Check …/types.ts` with no errors.

- [ ] **Step 12: Commit**

```bash
git add supabase/migrations/0058_ota_sync_status.sql supabase/tests/48_ota_sync_test.sql \
  supabase/functions/ical-export/types.ts lib/data/models/ical_feed.dart \
  lib/data/repositories/ical_repository.dart lib/data/repositories/ical_sync_runner.dart \
  test/support/fake_ical_source.dart test/features/ota/ical_screen_test.dart \
  test/data/ical_feed_test.dart
git commit -m "$(cat <<'EOF'
feat(ota): P9 contract -- feed sync status columns, parser helper stubs, Dart and TS types

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

## Phase 1: Database track (Tasks 2 → 3 → 4, sequential)

### Task 2: Parsing real Airbnb and Booking.com exports

**Track:** DB. Depends on Task 1.

**Files:**
- Modify: `supabase/migrations/0058_ota_sync_status.sql` (section 2 stub bodies)
- Test: `supabase/tests/48_ota_sync_test.sql`

**Interfaces:**
- Consumes: the Task 1 signatures of `ical_parse_when` and `ical_parse_feed`.
- Produces:
  - `ical_parse_when` reads `YYYYMMDD` as a date (`on_date` set, `at_ts` = midnight in `p_tz`), `YYYYMMDDTHHMMSSZ` as UTC, and `YYYYMMDDTHHMMSS` in the `TZID` zone (quotes and a leading `/` removed). An unknown zone or no `TZID` means `p_tz`. Anything else raises P0005 `unreadable date "<value>"`.
  - `ical_parse_feed` returns one row per non-cancelled `VEVENT`. Unreadable events carry `error` (`missing UID`, `missing DTSTART`, `missing DTEND`, `DTEND is before DTSTART`, `DTEND is not after DTSTART`, `DTEND is a time but DTSTART is a date`, or Postgres's own message for an impossible date), with null times.
  - `ical_poll_feed` still uses the old parser until Task 3.

- [ ] **Step 1: Write the failing parser tests**

In `supabase/tests/48_ota_sync_test.sql`, change `select plan(12);` to `select plan(49);`, and insert this section just above `select * from finish();`:

```sql
-- === Task 2: parsing real OTA exports ======================================
--
-- Shapes copied from real exports: Airbnb (CRLF, folded lines, all-day
-- VALUE=DATE events named "Reserved" and "Airbnb (Not available)");
-- Booking.com (bare LF, "CLOSED - Not available"); timezone variants; and
-- edge cases. The helpers are revoked from every API role, so this section
-- runs as the owner. 'Asia/Kolkata' stands in for the resort zone that
-- ical_poll_feed passes.
--
-- The fixtures are written with LF inside $ics$ quotes; replace(..., E'\n',
-- E'\r\n') makes the CRLF ones. A line starting with one space is a fold.

create temp table ics (name text primary key, body text not null);

insert into ics values ('airbnb', replace($ics$BEGIN:VCALENDAR
PRODID;X-RICAL-TZSOURCE=TZINFO:-//Airbnb Inc//Hosting Calendar 1.0//EN
CALSCALE:GREGORIAN
VERSION:2.0
BEGIN:VEVENT
DTEND;VALUE=DATE:20271012
DTSTART;VALUE=DATE:20271009
UID:1418fb94e984-0a1b2c3d4e5f6071
 8293a4b5c6d7e8f9@airbnb.com
DESCRIPTION:Reservation URL: https://www.airbnb.com/hosting/reservations/d
 etails/HMABCD1234\nPhone Number (Last 4 Digits): 4321
SUMMARY:Reserved
END:VEVENT
BEGIN:VEVENT
DTEND;VALUE=DATE:20271101
DTSTART;VALUE=DATE:20271025
UID:7f3e8a1c9d2b-11223344556677889900aabbccddeeff@airbnb.com
SUMMARY:Airbnb (Not available)
END:VEVENT
END:VCALENDAR
$ics$, E'\n', E'\r\n'));

insert into ics values ('booking', $ics$BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//admin.booking.com//EN
CALSCALE:GREGORIAN
METHOD:PUBLISH
BEGIN:VEVENT
UID:9d3c5e0f2a7b4c18a0e1@booking.com
DTSTAMP:20270901T060000Z
DTSTART;VALUE=DATE:20271115
DTEND;VALUE=DATE:20271118
SUMMARY:CLOSED - Not available
END:VEVENT
BEGIN:VEVENT
UID:5b7a1c3e9f0d2468b1c3@booking.com
DTSTAMP:20270901T060000Z
DTSTART;VALUE=DATE:20271201
DTEND;VALUE=DATE:20271202
SUMMARY:CLOSED - Not available
END:VEVENT
END:VCALENDAR
$ics$);
insert into ics
  select 'booking_crlf', replace(body, E'\n', E'\r\n') from ics where name = 'booking';

insert into ics values ('timezones', replace($ics$BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VEVENT
UID:tz-kolkata
DTSTART;TZID=Asia/Kolkata:20271205T140000
DTEND;TZID=Asia/Kolkata:20271207T110000
END:VEVENT
BEGIN:VEVENT
UID:tz-quoted
DTSTART;TZID="Europe/London":20271210T150000
DTEND;TZID="Europe/London":20271211T100000
END:VEVENT
BEGIN:VEVENT
UID:tz-windows
DTSTART;TZID=India Standard Time:20271212T140000
DTEND;TZID=India Standard Time:20271213T110000
END:VEVENT
BEGIN:VEVENT
UID:tz-floating
DTSTART:20271215T140000
DTEND:20271216T110000
END:VEVENT
BEGIN:VEVENT
UID:tz-utc
DTSTART:20271220T083000Z
DTEND:20271222T053000Z
END:VEVENT
END:VCALENDAR
$ics$, E'\n', E'\r\n'));

insert into ics values ('edge', chr(65279) || replace($ics$BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VEVENT
UID:one-day
DTSTART;VALUE=DATE:20280105
SUMMARY:Blocked
END:VEVENT
BEGIN:VEVENT
UID:plain-date
DTSTART:20280110
DTEND:20280112
END:VEVENT
BEGIN:VEVENT
UID:same-day-end
DTSTART;VALUE=DATE:20280115
DTEND;VALUE=DATE:20280115
END:VEVENT
BEGIN:VEVENT
UID:two-days
DTSTART;VALUE=DATE:20280120
DURATION:P2D
END:VEVENT
begin:vevent
uid:lower-case
dtstart;value=date:20280125
dtend;value=date:20280127
end:vevent
BEGIN:VEVENT
UID:with-alarm
DTSTART;VALUE=DATE:20280201
DTEND;VALUE=DATE:20280203
BEGIN:VALARM
ACTION:DISPLAY
UID:alarm-uid-must-not-win
DTSTART:20280101T000000Z
END:VALARM
END:VEVENT
BEGIN:VEVENT
UID:cancelled-one
STATUS:CANCELLED
DTSTART;VALUE=DATE:20280205
DTEND;VALUE=DATE:20280207
END:VEVENT
BEGIN:VEVENT
DTSTART;VALUE=DATE:20280210
DTEND;VALUE=DATE:20280212
SUMMARY:No uid here
END:VEVENT
BEGIN:VEVENT
UID:bad-date
DTSTART;VALUE=DATE:20281345
DTEND;VALUE=DATE:20281347
END:VEVENT
BEGIN:VEVENT
UID:backwards
DTSTART;VALUE=DATE:20280220
DTEND;VALUE=DATE:20280218
END:VEVENT
END:VCALENDAR
$ics$, E'\n', E'\r\n'));

-- Airbnb.
select is((select count(*)::int from public.ical_parse_feed(
    (select body from ics where name = 'airbnb'), 'Asia/Kolkata')),
  2, 'Airbnb: both events are read');
select is((select count(*)::int from public.ical_parse_feed(
    (select body from ics where name = 'airbnb'), 'Asia/Kolkata')
   where uid = '1418fb94e984-0a1b2c3d4e5f60718293a4b5c6d7e8f9@airbnb.com'),
  1, 'Airbnb: a UID folded over two lines is unfolded');
select is((select array[start_date, end_date] from public.ical_parse_feed(
    (select body from ics where name = 'airbnb'), 'Asia/Kolkata')
   where summary = 'Reserved'),
  array['2027-10-09','2027-10-12']::date[],
  'Airbnb: a reservation is all day, check-in date to check-out date');
select is((select array_agg(summary order by summary) from public.ical_parse_feed(
    (select body from ics where name = 'airbnb'), 'Asia/Kolkata')),
  array['Airbnb (Not available)','Reserved'],
  'Airbnb: both summaries are read, and a folded DESCRIPTION does not get in the way');
select is((select count(*)::int from public.ical_parse_feed(
    (select body from ics where name = 'airbnb'), 'Asia/Kolkata')
   where error is not null),
  0, 'Airbnb: nothing is unreadable');
select is((select dtstart from public.ical_parse_feed(
    (select body from ics where name = 'airbnb'), 'Asia/Kolkata')
   where summary = 'Reserved'),
  '2027-10-09 00:00:00+05:30'::timestamptz,
  'Airbnb: an all-day start is midnight in the zone passed in');

-- Booking.com.
select is((select array_agg(uid || ' ' || start_date || ' ' || end_date order by start_date)
             from public.ical_parse_feed((select body from ics where name = 'booking'),
                                         'Asia/Kolkata')),
  array['9d3c5e0f2a7b4c18a0e1@booking.com 2027-11-15 2027-11-18',
        '5b7a1c3e9f0d2468b1c3@booking.com 2027-12-01 2027-12-02'],
  'Booking.com (bare LF): both closed periods are read');
select is((select array_agg(f::text order by f.uid) from public.ical_parse_feed(
    (select body from ics where name = 'booking_crlf'), 'Asia/Kolkata') f),
  (select array_agg(f::text order by f.uid) from public.ical_parse_feed(
    (select body from ics where name = 'booking'), 'Asia/Kolkata') f),
  'Booking.com: the same file with CRLF line endings gives the same rows');
select is((select count(*)::int from public.ical_parse_feed(
    (select body from ics where name = 'booking'), 'Asia/Kolkata')
   where summary = 'CLOSED - Not available'),
  2, 'Booking.com: the "CLOSED - Not available" summary is read');

-- Time zones.
create temp table tz as
  select * from public.ical_parse_feed((select body from ics where name = 'timezones'),
                                       'Asia/Kolkata');
select is((select dtstart from tz where uid = 'tz-kolkata'),
  '2027-12-05 08:30:00+00'::timestamptz, 'TZID=Asia/Kolkata: 14:00 there is 08:30 UTC');
select is((select dtend from tz where uid = 'tz-kolkata'),
  '2027-12-07 05:30:00+00'::timestamptz, 'TZID=Asia/Kolkata: 11:00 there is 05:30 UTC');
select is((select dtstart from tz where uid = 'tz-quoted'),
  '2027-12-10 15:00:00+00'::timestamptz, 'a quoted TZID ("Europe/London") is read');
select is((select dtstart from tz where uid = 'tz-windows'),
  '2027-12-12 08:30:00+00'::timestamptz,
  'a zone Postgres does not know (Windows "India Standard Time") falls back to the resort zone');
select is((select dtstart from tz where uid = 'tz-floating'),
  '2027-12-15 08:30:00+00'::timestamptz, 'a floating time is resort-local, not UTC');
select is((select dtstart from tz where uid = 'tz-utc'),
  '2027-12-20 08:30:00+00'::timestamptz, 'a ...Z time is UTC');
select is((select count(*)::int from tz where start_date is not null),
  0, 'timed events are not all-day');

-- Edge cases.
create temp table edge as
  select * from public.ical_parse_feed((select body from ics where name = 'edge'),
                                       'Asia/Kolkata');
select is((select count(*)::int from edge), 9,
  'a byte-order mark is skipped and every non-cancelled event is returned, readable or not');
select is((select count(*)::int from edge where uid = 'cancelled-one'), 0,
  'a STATUS:CANCELLED event is skipped');
select is((select end_date from edge where uid = 'one-day'), '2028-01-06'::date,
  'an all-day event with no DTEND lasts one night');
select is((select array[start_date, end_date] from edge where uid = 'plain-date'),
  array['2028-01-10','2028-01-12']::date[],
  'a date without VALUE=DATE is still a date');
select is((select end_date from edge where uid = 'same-day-end'), '2028-01-16'::date,
  'an all-day event whose DTEND equals DTSTART lasts one night');
select is((select end_date from edge where uid = 'two-days'), '2028-01-22'::date,
  'DURATION:P2D on an all-day event is two nights');
select is((select array[start_date, end_date] from edge where uid = 'lower-case'),
  array['2028-01-25','2028-01-27']::date[], 'property names are case-insensitive');
select is((select start_date from edge where uid = 'with-alarm'), '2028-02-01'::date,
  'properties inside a VALARM do not overwrite the event''s own');
select is((select error from edge where summary = 'No uid here'), 'missing UID',
  'an event without a UID is returned with an error');
select ok((select error is not null and dtstart is null from edge where uid = 'bad-date'),
  'an impossible date is an error on that event, not on the feed');
select is((select error from edge where uid = 'backwards'), 'DTEND is before DTSTART',
  'an end before the start is an error');
select is((select uid || ' ' || start_date || ' ' || end_date from public.ical_parse_feed(
    E'BEGIN:VCALENDAR\r\nBEGIN:VEVENT \r\nUID:padded   \r\nDTSTART;VALUE=DATE:20280301\r\n'
    'END:VEVENT\t\r\nEND:VCALENDAR\r\n', 'Asia/Kolkata')),
  'padded 2028-03-01 2028-03-02', 'trailing spaces and tabs are ignored');
select is((select error from public.ical_parse_feed(
    E'BEGIN:VEVENT\r\nUID:no-end\r\nDTSTART:20280305T100000Z\r\nEND:VEVENT\r\n',
    'Asia/Kolkata')),
  'missing DTEND', 'a timed event with no DTEND or DURATION is an error');
select is((select error from public.ical_parse_feed(
    E'BEGIN:VEVENT\r\nUID:zero\r\nDTSTART:20280305T100000Z\r\n'
    'DTEND:20280305T100000Z\r\nEND:VEVENT\r\n', 'Asia/Kolkata')),
  'DTEND is not after DTSTART', 'a zero-length timed event is an error');
select is((select dtend from public.ical_parse_feed(
    E'BEGIN:VEVENT\r\nUID:three-hours\r\nDTSTART:20280306T100000Z\r\n'
    'DURATION:PT3H\r\nEND:VEVENT\r\n', 'Asia/Kolkata')),
  '2028-03-06 13:00:00+00'::timestamptz, 'DURATION on a timed event sets its end');
select is((select error from public.ical_parse_feed(
    E'BEGIN:VEVENT\r\nUID:mixed\r\nDTSTART;VALUE=DATE:20280306\r\n'
    'DTEND:20280307T100000Z\r\nEND:VEVENT\r\n', 'Asia/Kolkata')),
  'DTEND is a time but DTSTART is a date', 'a date start with a timed end is an error');
select is((select count(*)::int from public.ical_parse_feed(
    '<!DOCTYPE html><html><body>Sign in</body></html>', 'Asia/Kolkata')),
  0, 'a web page has no events (ical_poll_feed reports it as not a calendar)');
select is((select count(*)::int from public.ical_parse_feed(null, 'Asia/Kolkata')),
  0, 'an empty body has no events');

-- One value.
select throws_ok($$select public.ical_parse_when('2027-12-05', '', 'Asia/Kolkata')$$,
  'P0005', 'unreadable date "2027-12-05"', 'a date with dashes is not an iCal date');
select is((select at_ts from public.ical_parse_when(
    '20271205T140000', ';TZID=Nowhere/Land', 'Asia/Kolkata')),
  '2027-12-05 08:30:00+00'::timestamptz, 'an unknown TZID falls back to the resort zone');
select is((select at_ts from public.ical_parse_when(
    '20271205T140000', ';TZID=/Asia/Kolkata', 'UTC')),
  '2027-12-05 08:30:00+00'::timestamptz, 'a TZID with a leading slash is read');
```

- [ ] **Step 2: Run it to verify it fails**

Run: `supabase test db supabase/tests/48_ota_sync_test.sql`
Expected: FAIL. The first new assertion stops the file with `ical_parse_feed is not implemented yet` (SQLSTATE 0A000).

- [ ] **Step 3: Implement the parser**

In `supabase/migrations/0058_ota_sync_status.sql`, replace the stub definition of `public.ical_parse_when`, from `create function public.ical_parse_when(` through its closing `$$;`, with:

```sql
create function public.ical_parse_when(
  p_value  text,
  p_params text,
  p_tz     text,
  out at_ts   timestamptz,
  out on_date date
)
language plpgsql
stable
set search_path = public, pg_temp
as $$
declare
  v    text := btrim(coalesce(p_value, ''));
  v_tz text;
  v_ts timestamp;
begin
  -- A date, with or without VALUE=DATE: 20271009.
  if v ~ '^[0-9]{8}$' then
    on_date := make_date(substr(v, 1, 4)::int, substr(v, 5, 2)::int,
                         substr(v, 7, 2)::int);
    at_ts := on_date::timestamp at time zone p_tz;
    return;
  end if;

  if v !~ '^[0-9]{8}T[0-9]{6}Z?$' then
    raise exception using errcode = 'P0005',
      message = 'unreadable date "' || v || '"';
  end if;

  v_ts := make_timestamp(substr(v, 1, 4)::int, substr(v, 5, 2)::int,
                         substr(v, 7, 2)::int, substr(v, 10, 2)::int,
                         substr(v, 12, 2)::int, substr(v, 14, 2)::int);

  if right(v, 1) = 'Z' then
    at_ts := v_ts at time zone 'UTC';
    return;
  end if;

  -- TZID=Asia/Kolkata, TZID="Europe/London" or TZID=/Europe/London. A zone
  -- Postgres does not know (a Windows name such as "India Standard Time")
  -- and floating time both mean the resort's own zone.
  v_tz := btrim(substring(coalesce(p_params, '')
                          from '(?i);TZID=("[^"]*"|[^;]*)'), '"/ ');
  if v_tz is not null and v_tz <> '' then
    begin
      at_ts := v_ts at time zone v_tz;
      return;
    exception when invalid_parameter_value then
      null;
    end;
  end if;

  at_ts := v_ts at time zone p_tz;
end;
$$;
```

Replace the stub definition of `public.ical_parse_feed`, from `create function public.ical_parse_feed(` through its closing `$$;`, with:

```sql
create function public.ical_parse_feed(p_ics text, p_tz text default 'UTC')
returns table (
  uid        text,
  dtstart    timestamptz,
  dtend      timestamptz,
  start_date date,
  end_date   date,
  summary    text,
  error      text
)
language plpgsql
stable
set search_path = public, pg_temp
as $$
declare
  v_text      text;
  v_line      text;
  v_upper     text;
  v_match     text[];
  v_depth     int := 0;   -- 0 outside, 1 in a VEVENT, >1 in a component inside it
  v_uid       text;
  v_start_val text;
  v_start_par text;
  v_end_val   text;
  v_end_par   text;
  v_duration  text;
  v_summary   text;
  v_status    text;
  v_s         record;
  v_e         record;
begin
  -- A byte-order mark, then RFC 5545 unfolding: a line break followed by
  -- one space or tab continues the previous line.
  v_text := ltrim(coalesce(p_ics, ''), chr(65279));
  v_text := regexp_replace(v_text, E'\r?\n[ \t]', '', 'g');

  for v_line in
    select rtrim(t, E' \t\r') from regexp_split_to_table(v_text, E'\r?\n') as t
  loop
    continue when v_line = '';
    v_upper := upper(v_line);

    if v_depth = 0 then
      if v_upper = 'BEGIN:VEVENT' then
        v_depth := 1;
        v_uid := null; v_start_val := null; v_start_par := null;
        v_end_val := null; v_end_par := null; v_duration := null;
        v_summary := null; v_status := null;
      end if;
      continue;
    end if;

    -- A component nested in the event (VALARM): skip everything inside it.
    if v_upper like 'BEGIN:%' then
      v_depth := v_depth + 1;
      continue;
    end if;
    if v_upper like 'END:%' and v_depth > 1 then
      v_depth := v_depth - 1;
      continue;
    end if;
    continue when v_depth > 1;

    if v_upper = 'END:VEVENT' then
      v_depth := 0;
      continue when upper(coalesce(v_status, '')) = 'CANCELLED';

      uid := v_uid;
      summary := v_summary;
      dtstart := null; dtend := null; start_date := null; end_date := null;
      error := null;
      begin
        if v_uid is null or v_uid = '' then
          raise exception using errcode = 'P0005', message = 'missing UID';
        end if;
        if v_start_val is null then
          raise exception using errcode = 'P0005', message = 'missing DTSTART';
        end if;
        v_s := public.ical_parse_when(v_start_val, v_start_par, p_tz);
        if v_end_val is not null then
          v_e := public.ical_parse_when(v_end_val, v_end_par, p_tz);
        end if;

        if v_s.on_date is not null then
          -- All day: nights from start_date up to (not including) end_date.
          start_date := v_s.on_date;
          if v_end_val is not null then
            if v_e.on_date is null then
              raise exception using errcode = 'P0005',
                message = 'DTEND is a time but DTSTART is a date';
            end if;
            end_date := v_e.on_date;
          elsif v_duration is not null then
            end_date := (v_s.on_date + v_duration::interval)::date;
          else
            end_date := v_s.on_date + 1;
          end if;
          if end_date = start_date then
            end_date := start_date + 1;
          elsif end_date < start_date then
            raise exception using errcode = 'P0005',
              message = 'DTEND is before DTSTART';
          end if;
          dtstart := start_date::timestamp at time zone p_tz;
          dtend   := end_date::timestamp at time zone p_tz;
        else
          dtstart := v_s.at_ts;
          if v_end_val is not null then
            dtend := v_e.at_ts;
          elsif v_duration is not null then
            dtend := dtstart + v_duration::interval;
          else
            raise exception using errcode = 'P0005', message = 'missing DTEND';
          end if;
          if dtend <= dtstart then
            raise exception using errcode = 'P0005',
              message = 'DTEND is not after DTSTART';
          end if;
        end if;
      exception when others then
        dtstart := null; dtend := null; start_date := null; end_date := null;
        error := sqlerrm;
      end;
      return next;
      continue;
    end if;

    -- NAME;PARAM=a;PARAM="b:c":value -- the value starts at the first colon
    -- outside double quotes.
    v_match := regexp_match(v_line,
      '^([A-Za-z0-9-]+)((?:;(?:[^";:]|"[^"]*")*)*):(.*)$');
    continue when v_match is null;

    case upper(v_match[1])
      when 'UID'      then v_uid := btrim(v_match[3]);
      when 'DTSTART'  then v_start_val := v_match[3]; v_start_par := v_match[2];
      when 'DTEND'    then v_end_val := v_match[3];   v_end_par := v_match[2];
      when 'DURATION' then v_duration := btrim(v_match[3]);
      when 'SUMMARY'  then v_summary := btrim(v_match[3]);
      when 'STATUS'   then v_status := btrim(v_match[3]);
      else null;
    end case;
  end loop;

  return;
end;
$$;
```

- [ ] **Step 4: Run the tests**

Run: `supabase db reset && supabase test db supabase/tests/48_ota_sync_test.sql supabase/tests/14_ical_test.sql`
Expected: PASS. 48 passes 49/49, and 14 is unchanged because the poller still uses the old `ical_parse_events`.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/0058_ota_sync_status.sql supabase/tests/48_ota_sync_test.sql
git commit -m "$(cat <<'EOF'
feat(ota): parse real Airbnb and Booking.com iCal exports

All-day, folded, CRLF/LF, TZID variants, DURATION, VALARM, cancelled and
unreadable events, with fixture tests.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

### Task 3: Polling -- status columns, resort times, echoes

**Track:** DB. Depends on Task 2.

**Files:**
- Modify: `supabase/migrations/0058_ota_sync_status.sql` (section 3 stub bodies, plus the redefined functions)
- Test: `supabase/tests/48_ota_sync_test.sql`

**Interfaces:**
- Consumes:
  - `ical_parse_feed` (Task 2)
  - `build_period` (0005)
  - `ical_import_event` (0045), whose result is `{status: created|updated|unchanged|conflict, ...}`
  - `net._http_response(id, status_code, content, timed_out, error_msg)` and `net.http_get(url, timeout_milliseconds)` (pg_net)
- Produces:
  - `ical_event_period(...)` returns `build_period(unit, start_date, coalesce(end_date, start_date + 1))` for all-day events. For timed events it returns `[dtstart, dtend)`, or raises P0005 `invalid event period`.
  - `ical_event_is_echo(...)` returns a boolean.
  - `ical_parse_events(text)` is the wrapper.
  - `ical_poll_feed(uuid)` returns:
    - `{status:'ok', events, created, updated, unchanged, conflicts, echoes, failed}`
    - `{status:'error', error}`
    - `{status:'pending'}`
    - `{status:'requested'}`

    It also writes `last_synced_at`, `last_status`, `last_error`, `last_event_count` and `last_ok_at`.
  - `ical_poll_all_feeds()` records `last_status = 'error'` on a per-feed failure.

- [ ] **Step 1: Write the failing poll tests**

In `supabase/tests/48_ota_sync_test.sql`, change `select plan(49);` to `select plan(91);`, and insert this section just above `select * from finish();`:

```sql
-- === Task 3: polling -- status columns, resort times, echoes ===============
--
-- ical_poll_feed collects a fetched response from net._http_response
-- (0018's two-call state machine), so a response is faked the way a real
-- one lands: point the feed's pending_request_id at a row written there.
-- Request ids are far above pg_net's own so they never collide. Polls run
-- with no JWT, like the pg_cron job, unless a test says otherwise.

set local request.jwt.claims to '';

insert into ics values ('booking_echo', $ics$BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//admin.booking.com//EN
BEGIN:VEVENT
UID:9d3c5e0f2a7b4c18a0e1@booking.com
DTSTART;VALUE=DATE:20271115
DTEND;VALUE=DATE:20271118
SUMMARY:CLOSED - Not available
END:VEVENT
BEGIN:VEVENT
UID:5b7a1c3e9f0d2468b1c3@booking.com
DTSTART;VALUE=DATE:20271201
DTEND;VALUE=DATE:20271202
SUMMARY:CLOSED - Not available
END:VEVENT
BEGIN:VEVENT
UID:echo-of-our-block@booking.com
DTSTART;VALUE=DATE:20271120
DTEND;VALUE=DATE:20271123
SUMMARY:CLOSED - Not available
END:VEVENT
BEGIN:VEVENT
UID:overlaps-our-block@booking.com
DTSTART;VALUE=DATE:20271122
DTEND;VALUE=DATE:20271125
SUMMARY:CLOSED - Not available
END:VEVENT
END:VCALENDAR
$ics$);

-- On Cottage A: our own block ending 25 Oct 11:00 (the Airbnb block starts
-- that day), our own block 20-23 Nov (Booking.com echoes it back), and an
-- Airbnb stay imported before P9, at midnight UTC.
insert into public.reservations
  (unit_id, period, kind, status, block_reason, external_uid, source) values
  ('f9000000-0000-4000-8000-000000000011',
   tstzrange('2027-10-22 08:30+00','2027-10-25 05:30+00','[)'),
   'block','confirmed','Owner stay', null, 'app'),
  ('f9000000-0000-4000-8000-000000000011',
   tstzrange('2027-11-20 08:30+00','2027-11-23 05:30+00','[)'),
   'block','confirmed','Owner stay', null, 'app'),
  ('f9000000-0000-4000-8000-000000000011',
   tstzrange('2027-10-09 00:00+00','2027-10-12 00:00+00','[)'),
   'ota','confirmed', null,
   '1418fb94e984-0a1b2c3d4e5f60718293a4b5c6d7e8f9@airbnb.com', 'ical');

insert into public.ical_feeds (id, unit_id, url, label) values
  ('f9000000-0000-4000-8000-000000000021','f9000000-0000-4000-8000-000000000011',
   'https://example.invalid/airbnb.ics','Airbnb'),
  ('f9000000-0000-4000-8000-000000000022','f9000000-0000-4000-8000-000000000011',
   'https://example.invalid/booking.ics','Booking.com'),
  ('f9000000-0000-4000-8000-000000000023','f9000000-0000-4000-8000-000000000012',
   'https://example.invalid/broken.ics','Broken');

-- Resort L, in London with its own check-in/check-out times.
insert into public.properties (id, name, slug, timezone, check_in_time, check_out_time)
values ('f9000000-0000-4000-8000-000000000050','Resort L','ota-l',
        'Europe/London','15:00','10:00');
insert into public.units (id, property_id, name, capacity_base, capacity_max) values
  ('f9000000-0000-4000-8000-000000000051','f9000000-0000-4000-8000-000000000050','Loft',2,4);
insert into public.ical_feeds (id, unit_id, url, label) values
  ('f9000000-0000-4000-8000-000000000052','f9000000-0000-4000-8000-000000000051',
   'https://example.invalid/london.ics','Airbnb');

-- Point a feed at a faked response fetched p_age ago.
create function pg_temp.deliver(p_feed uuid, p_req bigint, p_status int, p_body text,
                                p_age interval default '0',
                                p_timed_out boolean default false)
returns void language plpgsql as $f$
begin
  update public.ical_feeds
     set pending_request_id = p_req, pending_since = now() - p_age
   where id = p_feed;
  insert into net._http_response (id, status_code, content, timed_out, error_msg)
  values (p_req, p_status, p_body, p_timed_out, null);
end;
$f$;

-- Airbnb, fetched 10 minutes ago.
select pg_temp.deliver('f9000000-0000-4000-8000-000000000021', 948000001, 200,
  (select body from ics where name = 'airbnb'), '10 minutes');
select public.ical_poll_feed('f9000000-0000-4000-8000-000000000021')::text as r1 \gset

select is(:'r1'::jsonb ->> 'status', 'ok', 'a collected Airbnb export syncs ok');
select is((:'r1'::jsonb ->> 'events')::int, 2, 'events counts what the feed lists');
select is((:'r1'::jsonb ->> 'created')::int, 1, 'the Not available block is created');
select is((:'r1'::jsonb ->> 'updated')::int, 1,
  'the stay imported before P9 at midnight UTC is moved, not duplicated');
select is((:'r1'::jsonb ->> 'conflicts')::int, 0,
  'back to back with our own block is not a conflict');
select is((select period from public.reservations
            where external_uid = '1418fb94e984-0a1b2c3d4e5f60718293a4b5c6d7e8f9@airbnb.com'),
  tstzrange('2027-10-09 08:30+00','2027-10-12 05:30+00','[)'),
  'an all-day stay runs from check-in 14:00 to check-out 11:00, Asia/Kolkata');
select is((select period from public.reservations
            where external_uid = '7f3e8a1c9d2b-11223344556677889900aabbccddeeff@airbnb.com'),
  tstzrange('2027-10-25 08:30+00','2027-11-01 05:30+00','[)'),
  'the Not available block starts at check-in on the day our block ends');
select is((select array[last_status, last_event_count::text, coalesce(last_error, '-')]
             from public.ical_feeds where id = 'f9000000-0000-4000-8000-000000000021'),
  array['ok','2','-'], 'the feed records ok, 2 events and no note');
select is((select last_synced_at from public.ical_feeds
            where id = 'f9000000-0000-4000-8000-000000000021'),
  now() - interval '10 minutes',
  'last_synced_at is when the data was fetched, not when it was processed');
select is((select last_ok_at from public.ical_feeds
            where id = 'f9000000-0000-4000-8000-000000000021'),
  now() - interval '10 minutes', 'last_ok_at moves with a successful sync');
select isnt((select pending_request_id from public.ical_feeds
              where id = 'f9000000-0000-4000-8000-000000000021'),
  948000001::bigint, 'a fresh fetch was fired after collecting');

-- The same export again.
select pending_request_id as fa_next from public.ical_feeds
 where id = 'f9000000-0000-4000-8000-000000000021' \gset
select pg_temp.deliver('f9000000-0000-4000-8000-000000000021', :fa_next, 200,
  (select body from ics where name = 'airbnb'));
select public.ical_poll_feed('f9000000-0000-4000-8000-000000000021')::text as r2 \gset
select is((:'r2'::jsonb ->> 'unchanged')::int, 2, 'a re-import changes nothing');
select is((:'r2'::jsonb ->> 'created')::int, 0, 'and creates nothing');

-- Booking.com echoing our block back, plus one real overlap.
select pg_temp.deliver('f9000000-0000-4000-8000-000000000022', 948000002, 200,
  (select body from ics where name = 'booking_echo'), '5 minutes');
select public.ical_poll_feed('f9000000-0000-4000-8000-000000000022')::text as r3 \gset
select is((:'r3'::jsonb ->> 'events')::int, 4, 'Booking.com: four events read');
select is((:'r3'::jsonb ->> 'created')::int, 2, 'the two closed periods are created');
select is((:'r3'::jsonb ->> 'echoes')::int, 1,
  'Booking.com listing our own block back is an echo');
select is((:'r3'::jsonb ->> 'conflicts')::int, 1,
  'a closed period that overlaps our block for only some nights is a conflict');
select is((select count(*)::int from public.reservations
            where external_uid in ('echo-of-our-block@booking.com',
                                   'overlaps-our-block@booking.com')),
  0, 'neither is imported');
select is((select array[last_status, last_error] from public.ical_feeds
            where id = 'f9000000-0000-4000-8000-000000000022'),
  array['ok','1 event(s) conflicted with an existing booking and were skipped'],
  'a conflict is a note on an ok sync, and the echo adds nothing');

-- A web page instead of a calendar.
select pg_temp.deliver('f9000000-0000-4000-8000-000000000023', 948000003, 200,
  '<!DOCTYPE html><html><body>Log in</body></html>');
select public.ical_poll_feed('f9000000-0000-4000-8000-000000000023')::text as r4 \gset
select is(:'r4'::jsonb ->> 'status', 'error', 'a 200 that is not a calendar is an error');
select is((select array[last_status, last_error] from public.ical_feeds
            where id = 'f9000000-0000-4000-8000-000000000023'),
  array['error','not a calendar: the link did not return iCal data'],
  'and says so');
select ok((select last_ok_at is null and last_event_count is null from public.ical_feeds
            where id = 'f9000000-0000-4000-8000-000000000023'),
  'a feed that never worked has no last good sync and no count');

-- It works once (fetched 20 minutes ago), then the link dies.
select pg_temp.deliver('f9000000-0000-4000-8000-000000000023', 948000004, 200,
  (select body from ics where name = 'booking'), '20 minutes');
select public.ical_poll_feed('f9000000-0000-4000-8000-000000000023')::text as r5 \gset
select is(:'r5'::jsonb ->> 'status', 'ok', 'the feed recovers');
select pg_temp.deliver('f9000000-0000-4000-8000-000000000023', 948000005, 404, 'Not Found');
select public.ical_poll_feed('f9000000-0000-4000-8000-000000000023');
select is((select array[last_status, last_error] from public.ical_feeds
            where id = 'f9000000-0000-4000-8000-000000000023'),
  array['error','HTTP 404'], 'an HTTP error is an error');
select ok((select last_ok_at = now() - interval '20 minutes' and last_event_count = 2
             from public.ical_feeds where id = 'f9000000-0000-4000-8000-000000000023'),
  'a failure keeps the last good sync and its count');
select is((select last_synced_at from public.ical_feeds
            where id = 'f9000000-0000-4000-8000-000000000023'),
  now(), 'last_synced_at records the failed attempt');

-- A timeout, then a poll that finds nothing yet.
select pg_temp.deliver('f9000000-0000-4000-8000-000000000023', 948000006, null, null,
  '0', true);
select public.ical_poll_feed('f9000000-0000-4000-8000-000000000023')::text as r7 \gset
select is(:'r7'::jsonb ->> 'error', 'request timed out', 'a timeout is an error');
update public.ical_feeds set pending_request_id = 948999999, pending_since = now()
 where id = 'f9000000-0000-4000-8000-000000000023';
select public.ical_poll_feed('f9000000-0000-4000-8000-000000000023')::text as r8 \gset
select is(:'r8'::jsonb ->> 'status', 'pending', 'a response not there yet is pending');
select is((select last_error from public.ical_feeds
            where id = 'f9000000-0000-4000-8000-000000000023'),
  'request timed out', 'and a pending poll changes nothing');

-- Another resort's zone and times.
select pg_temp.deliver('f9000000-0000-4000-8000-000000000052', 948000007, 200,
  E'BEGIN:VCALENDAR\r\nVERSION:2.0\r\nBEGIN:VEVENT\r\nUID:london-stay@airbnb.com\r\n'
  'DTSTART;VALUE=DATE:20270705\r\nDTEND;VALUE=DATE:20270707\r\nSUMMARY:Reserved\r\n'
  'END:VEVENT\r\nEND:VCALENDAR\r\n');
select public.ical_poll_feed('f9000000-0000-4000-8000-000000000052');
select is((select period from public.reservations where external_uid = 'london-stay@airbnb.com'),
  tstzrange('2027-07-05 14:00+00','2027-07-07 09:00+00','[)'),
  'another resort''s zone and times are used (Europe/London, 15:00/10:00, summer time)');

-- A valid but empty calendar (an OTA glitch) cancels nothing.
select pending_request_id as fa_next from public.ical_feeds
 where id = 'f9000000-0000-4000-8000-000000000021' \gset
select pg_temp.deliver('f9000000-0000-4000-8000-000000000021', :fa_next, 200,
  E'BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//Airbnb Inc//Hosting Calendar 1.0//EN\r\n'
  'END:VCALENDAR\r\n');
select public.ical_poll_feed('f9000000-0000-4000-8000-000000000021')::text as r9 \gset
select is((:'r9'::jsonb ->> 'events')::int, 0, 'an empty calendar has 0 events');
select is((select array[last_status, last_event_count::text] from public.ical_feeds
            where id = 'f9000000-0000-4000-8000-000000000021'),
  array['ok','0'], 'and is an ok sync');
select is((select count(*)::int from public.reservations
            where external_uid like '%@airbnb.com' and unit_id = 'f9000000-0000-4000-8000-000000000011'
              and status = 'confirmed'),
  2, 'nothing imported earlier is cancelled');

-- Sync now: an admin of the resort may; a staff member may not.
select pending_request_id as fa_next from public.ical_feeds
 where id = 'f9000000-0000-4000-8000-000000000021' \gset
select pg_temp.deliver('f9000000-0000-4000-8000-000000000021', :fa_next, 200,
  (select body from ics where name = 'airbnb'));
set local role authenticated;
set local request.jwt.claims to '{"sub":"f9000000-0000-4000-8000-000000000001","role":"authenticated"}';
select is((select public.ical_poll_feed('f9000000-0000-4000-8000-000000000021') ->> 'status'),
  'ok', 'an admin''s Sync now collects and imports');
set local request.jwt.claims to '{"sub":"f9000000-0000-4000-8000-000000000002","role":"authenticated"}';
select throws_ok($$select public.ical_poll_feed('f9000000-0000-4000-8000-000000000021')$$,
  'P0020', null, 'a staff member cannot trigger a sync');
reset role;
set local request.jwt.claims to '';

-- The wrapper and the helpers.
select is((select count(*)::int from public.ical_parse_events(
    (select body from ics where name = 'edge'))),
  6, 'ical_parse_events returns only the readable events');
select is((select dtstart from public.ical_parse_events(
    (select body from ics where name = 'airbnb')) order by dtstart limit 1),
  '2027-10-09 00:00:00+00'::timestamptz,
  'ical_parse_events keeps its UTC-midnight reading of all-day events');
select is(public.ical_event_period('f9000000-0000-4000-8000-000000000011',
    null, null, '2027-10-09', '2027-10-12'),
  tstzrange('2027-10-09 08:30+00','2027-10-12 05:30+00','[)'),
  'ical_event_period places all-day dates at the resort''s times');
select throws_ok($$select public.ical_event_period('f9000000-0000-4000-8000-000000000011',
    '2028-01-01 10:00+00', '2028-01-01 10:00+00', null, null)$$,
  'P0005', 'invalid event period', 'an empty timed period is refused');
select ok(public.ical_event_is_echo('f9000000-0000-4000-8000-000000000011',
    '2027-11-20', '2027-11-23'),
  'every night taken by our own block: an echo');
select ok(not public.ical_event_is_echo('f9000000-0000-4000-8000-000000000011',
    '2027-11-22', '2027-11-25'),
  'some nights free: not an echo');
select ok(not public.ical_event_is_echo('f9000000-0000-4000-8000-000000000011',
    '2027-11-23', '2027-11-23'),
  'no nights at all: not an echo');
```

- [ ] **Step 2: Run it to verify it fails**

Run: `supabase test db supabase/tests/48_ota_sync_test.sql`
Expected: FAIL. `r1` is still the old result shape (no `events`), so `events counts what the feed lists` fails. Later, the helper assertions stop with `ical_event_period is not implemented yet`.

- [ ] **Step 3: Implement the import helpers**

In `supabase/migrations/0058_ota_sync_status.sql`, replace the stub definition of `public.ical_event_period`, from `create function public.ical_event_period(` through its `$$;`, with:

```sql
create function public.ical_event_period(
  p_unit_id    uuid,
  p_dtstart    timestamptz,
  p_dtend      timestamptz,
  p_start_date date,
  p_end_date   date
) returns tstzrange
language plpgsql
stable
set search_path = public, pg_temp
as $$
begin
  -- An all-day OTA event covers nights: arrive at the resort's check-in
  -- time on the first date, leave at its check-out time on the last --
  -- exactly how a native booking's period is built.
  if p_start_date is not null then
    return public.build_period(p_unit_id, p_start_date,
                               coalesce(p_end_date, p_start_date + 1));
  end if;
  if p_dtstart is null or p_dtend is null or p_dtend <= p_dtstart then
    raise exception using errcode = 'P0005', message = 'invalid event period';
  end if;
  return tstzrange(p_dtstart, p_dtend, '[)');
end;
$$;
```

Replace the stub definition of `public.ical_event_is_echo`, from `create function public.ical_event_is_echo(` through its `$$;`, with:

```sql
create function public.ical_event_is_echo(
  p_unit_id    uuid,
  p_start_date date,
  p_end_date   date
) returns boolean
language sql
stable
set search_path = public, pg_temp
as $$
  -- True when every night of the event is already taken here: a
  -- reservation on the unit contains the resort-local midnight that ends
  -- that night.
  select coalesce(p_end_date > p_start_date, false)
     and exists (select 1 from public.units where id = p_unit_id)
     and not exists (
       select 1
         from generate_series(p_start_date::timestamp,
                              (p_end_date - 1)::timestamp,
                              interval '1 day') as night(d)
         join public.units u on u.id = p_unit_id
         join public.properties p on p.id = u.property_id
        where not exists (
          select 1
            from public.reservations r
           where r.unit_id = p_unit_id
             and r.status <> 'cancelled'
             and r.period @> ((night.d::date + 1)::timestamp
                              at time zone p.timezone)));
$$;
```

- [ ] **Step 4: Redefine the poller**

Append to the end of `supabase/migrations/0058_ota_sync_status.sql` (after the revoke block):

```sql
-- ---------------------------------------------------------------------
-- 3b. The poller on top of the helpers. ical_parse_events keeps its
--     signature for existing callers; ical_poll_feed is copied from 0045
--     and ical_poll_all_feeds from 0018, then extended. Grants and revokes
--     survive `create or replace`.

create or replace function public.ical_parse_events(p_ics text)
returns table(uid text, dtstart timestamptz, dtend timestamptz)
language sql
stable
set search_path = public, pg_temp
as $$
  select f.uid, f.dtstart, f.dtend
    from public.ical_parse_feed(p_ics, 'UTC') as f
   where f.error is null;
$$;

-- Admin+ of the feed's resort for a PostgREST caller (Sync now); the cron
-- job (no JWT) is not checked. See 0018 for the state machine.
create or replace function public.ical_poll_feed(p_feed_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_property    uuid;
  v_feed        public.ical_feeds;
  v_tz          text;
  v_resp        record;
  v_event       record;
  v_period      tstzrange;
  v_fetched_at  timestamptz;
  v_events      int := 0;
  v_created     int := 0;
  v_updated     int := 0;
  v_unchanged   int := 0;
  v_conflicts   int := 0;
  v_echoes      int := 0;
  v_failed      int := 0;
  v_failed_note text;
  v_import      jsonb;
  v_error       text;
  v_req_id      bigint;
  v_result      jsonb;
begin
  if nullif(current_setting('request.jwt.claims', true), '') is not null then
    select property_id into v_property from public.ical_feeds where id = p_feed_id;
    if v_property is null then
      raise exception 'feed not found or inactive' using errcode = 'P0002';
    end if;
    perform public.assert_resort_role(v_property, true, 'owner','admin');
  end if;

  -- `for update`: a cron tick and a Sync press for the same feed must not
  -- both fire a request.
  select * into v_feed
  from public.ical_feeds
  where id = p_feed_id and is_active
  for update;

  if not found then
    raise exception 'feed not found or inactive' using errcode = 'P0002';
  end if;

  -- A request stuck far longer than pg_net's own timeout is abandoned.
  if v_feed.pending_request_id is not null
     and v_feed.pending_since < now() - interval '30 minutes' then
    v_feed.pending_request_id := null;
  end if;

  if v_feed.pending_request_id is not null then
    select status_code, content, error_msg, timed_out
      into v_resp
      from net._http_response
      where id = v_feed.pending_request_id;

    if not found then
      return jsonb_build_object('status', 'pending');
    end if;

    -- The data is as old as the request that fetched it.
    v_fetched_at := coalesce(v_feed.pending_since, now());
    select p.timezone into v_tz
      from public.units u join public.properties p on p.id = u.property_id
     where u.id = v_feed.unit_id;

    -- Every path must reach the `update ical_feeds` below, so an
    -- unexpected error cannot wedge the feed.
    begin
      if v_resp.timed_out or v_resp.error_msg is not null
         or v_resp.status_code is distinct from 200 then
        v_error := coalesce(
          v_resp.error_msg,
          case when v_resp.timed_out then 'request timed out'
               else 'HTTP ' || coalesce(v_resp.status_code::text, 'unknown') end);
        v_result := jsonb_build_object('status', 'error', 'error', v_error);
      elsif coalesce(v_resp.content, '') !~* 'BEGIN:VCALENDAR' then
        -- A login page or a listing page, not a calendar: zero events would
        -- otherwise read as a healthy, empty feed.
        v_error := 'not a calendar: the link did not return iCal data';
        v_result := jsonb_build_object('status', 'error', 'error', v_error);
      else
        for v_event in
          select * from public.ical_parse_feed(v_resp.content, coalesce(v_tz, 'UTC'))
        loop
          v_events := v_events + 1;
          -- One unreadable or refused event skips itself; the rest import.
          begin
            if v_event.error is not null then
              raise exception using errcode = 'P0005', message = v_event.error;
            end if;
            v_period := public.ical_event_period(v_feed.unit_id,
              v_event.dtstart, v_event.dtend, v_event.start_date, v_event.end_date);
            v_import := public.ical_import_event(
              v_feed.unit_id, v_event.uid, lower(v_period), upper(v_period));
            case v_import ->> 'status'
              when 'created'   then v_created   := v_created + 1;
              when 'updated'   then v_updated   := v_updated + 1;
              when 'unchanged' then v_unchanged := v_unchanged + 1;
              when 'conflict'  then
                -- The OTA listing our own booking back to us (it closed
                -- those dates because of our export) is not a conflict.
                if v_event.start_date is not null
                   and public.ical_event_is_echo(v_feed.unit_id,
                         v_event.start_date, v_event.end_date) then
                  v_echoes := v_echoes + 1;
                else
                  v_conflicts := v_conflicts + 1;
                end if;
              else null;
            end case;
          exception when others then
            v_failed := v_failed + 1;
            v_failed_note := coalesce(nullif(btrim(v_event.uid), ''), '(blank uid)')
              || ': ' || sqlerrm;
          end;
        end loop;

        v_error := nullif(trim(both ', ' from concat_ws(', ',
          case when v_conflicts > 0 then
            v_conflicts || ' event(s) conflicted with an existing booking '
            'and were skipped'
          end,
          case when v_failed > 0 then
            v_failed || ' event(s) failed to import and were skipped '
            '(last error: ' || v_failed_note || ')'
          end
        )), '');
        v_result := jsonb_build_object('status', 'ok', 'events', v_events,
          'created', v_created, 'updated', v_updated, 'unchanged', v_unchanged,
          'conflicts', v_conflicts, 'echoes', v_echoes, 'failed', v_failed);
      end if;
    exception when others then
      v_error := 'poll failed while processing response: ' || sqlerrm;
      v_result := jsonb_build_object('status', 'error', 'error', v_error);
    end;

    update public.ical_feeds
       set last_synced_at   = v_fetched_at,
           last_status      = v_result ->> 'status',
           last_error       = v_error,
           last_event_count = case when v_result ->> 'status' = 'ok'
                                   then v_events else last_event_count end,
           last_ok_at       = case when v_result ->> 'status' = 'ok'
                                   then v_fetched_at else last_ok_at end,
           pending_request_id = null,
           pending_since      = null
     where id = p_feed_id;
  end if;

  -- Fire the next request (the first, or the follow-up to the one just
  -- collected).
  begin
    v_req_id := net.http_get(url := v_feed.url, timeout_milliseconds := 15000);
  exception when others then
    if v_result is null then
      -- Nothing was collected in this call: the failed fetch is the news.
      update public.ical_feeds
         set last_synced_at = now(), last_status = 'error',
             last_error = 'fetch failed: ' || sqlerrm,
             pending_request_id = null, pending_since = null
       where id = p_feed_id;
      return jsonb_build_object('status', 'error', 'error', 'fetch failed: ' || sqlerrm);
    end if;
    update public.ical_feeds
       set pending_request_id = null, pending_since = null
     where id = p_feed_id;
    return v_result;
  end;

  update public.ical_feeds
    set pending_request_id = v_req_id, pending_since = now()
    where id = p_feed_id;

  return coalesce(v_result, jsonb_build_object('status', 'requested'));
end;
$$;

-- Cron only (revoked from every API role in 0018; the revoke survives).
create or replace function public.ical_poll_all_feeds()
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_feed record;
begin
  for v_feed in select id from public.ical_feeds where is_active loop
    -- One feed's failure must not roll back the other feeds' results.
    begin
      perform public.ical_poll_feed(v_feed.id);
    exception when others then
      update public.ical_feeds
         set last_synced_at = now(), last_status = 'error',
             last_error = 'poll failed: ' || sqlerrm,
             pending_request_id = null, pending_since = null
       where id = v_feed.id;
    end;
  end loop;
end;
$$;
```

- [ ] **Step 5: Run the tests**

Run: `supabase db reset && supabase test db supabase/tests/48_ota_sync_test.sql supabase/tests/14_ical_test.sql supabase/tests/37_tenancy_isolation_test.sql`
Expected: PASS. 48 passes 91/91.
- 14 is unchanged. Its bad feed now fails the blank-UID event with `missing UID` and the zero-length event with `DTEND is not after DTSTART`, so its note still starts with `2 event(s) failed to import and were skipped`.
- 37's allow-list is unchanged, because `ical_poll_feed` and `ical_poll_all_feeds` are already on it.

- [ ] **Step 6: Commit**

```bash
git add supabase/migrations/0058_ota_sync_status.sql supabase/tests/48_ota_sync_test.sql
git commit -m "$(cat <<'EOF'
feat(ota): record feed sync status; place all-day events at resort times; count echoes

ical_poll_feed writes last_status/last_event_count/last_ok_at, treats a
non-calendar 200 as an error, and no longer reports an OTA echoing our own
booking as a conflict.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

### Task 4: Feed URL rules (P0039)

**Track:** DB. Depends on Task 3.

**Files:**
- Modify: `supabase/migrations/0058_ota_sync_status.sql` (section 4)
- Test: `supabase/tests/48_ota_sync_test.sql`

**Interfaces:**
- Consumes: `ical_feeds`, and its `ical_feeds_read` and `ical_feeds_write` policies (0044).
- Produces:
  - The trigger `ical_feeds_normalize_url` (before insert, or update of `url` or `unit_id`). It trims and rewrites `webcal://` to `https://`.
  - P0039 `invalid_feed_url` or `duplicate_feed`. Task 7 maps both to `FeedUrlRejected`.

- [ ] **Step 1: Write the failing URL tests**

In `supabase/tests/48_ota_sync_test.sql`, change `select plan(91);` to `select plan(102);`, and insert this section just above `select * from finish();`:

```sql
-- === Task 4: feed URL rules (P0039) =========================================

reset role;
set local request.jwt.claims to '';

insert into public.ical_feeds (id, unit_id, url, label) values
  ('f9000000-0000-4000-8000-000000000060','f9000000-0000-4000-8000-000000000012',
   E'  WEBCAL://www.airbnb.com/calendar/ical/77.ics?s=abc \n','Pasted');
select is((select url from public.ical_feeds where id = 'f9000000-0000-4000-8000-000000000060'),
  'https://www.airbnb.com/calendar/ical/77.ics?s=abc',
  'a pasted link is trimmed and webcal:// becomes https://');
select throws_ok($$insert into public.ical_feeds (unit_id, url)
  values ('f9000000-0000-4000-8000-000000000012', 'ftp://example.com/a.ics')$$,
  'P0039', 'invalid_feed_url', 'only http(s) and webcal links are feeds');
select throws_ok($$insert into public.ical_feeds (unit_id, url)
  values ('f9000000-0000-4000-8000-000000000012', 'airbnb.com/calendar/ical/1.ics')$$,
  'P0039', 'invalid_feed_url', 'a link without a scheme is refused');
select throws_ok($$insert into public.ical_feeds (unit_id, url)
  values ('f9000000-0000-4000-8000-000000000012', 'https://')$$,
  'P0039', 'invalid_feed_url', 'a link without a host is refused');
select throws_ok($$insert into public.ical_feeds (unit_id, url)
  values ('f9000000-0000-4000-8000-000000000012', 'https://example.com/my cal.ics')$$,
  'P0039', 'invalid_feed_url', 'a link with a space inside is refused');
select throws_ok($$insert into public.ical_feeds (unit_id, url)
  values ('f9000000-0000-4000-8000-000000000012',
          'webcal://www.airbnb.com/calendar/ical/77.ics?s=abc')$$,
  'P0039', 'duplicate_feed',
  'the webcal:// form of a stored https:// link is the same calendar');
select lives_ok($$insert into public.ical_feeds (unit_id, url)
  values ('f9000000-0000-4000-8000-000000000011',
          'https://www.airbnb.com/calendar/ical/77.ics?s=abc')$$,
  'the same link on another unit is fine');
select throws_ok($$update public.ical_feeds set url = 'not a url'
  where id = 'f9000000-0000-4000-8000-000000000060'$$,
  'P0039', 'invalid_feed_url', 'editing a link checks it too');
select lives_ok($$update public.ical_feeds set label = 'Airbnb'
  where id = 'f9000000-0000-4000-8000-000000000060'$$,
  'editing only the label is not checked');

set local role authenticated;
set local request.jwt.claims to '{"sub":"f9000000-0000-4000-8000-000000000001","role":"authenticated"}';
select throws_ok($$insert into public.ical_feeds (unit_id, url)
  values ('f9000000-0000-4000-8000-000000000012',
          'https://www.airbnb.com/calendar/ical/77.ics?s=abc')$$,
  'P0039', 'duplicate_feed', 'an admin adding a calendar twice gets duplicate_feed');
insert into public.ical_feeds (id, unit_id, url) values
  ('f9000000-0000-4000-8000-000000000061','f9000000-0000-4000-8000-000000000012',
   'webcal://www.booking.com/ical/88.ics');
select is((select url from public.ical_feeds where id = 'f9000000-0000-4000-8000-000000000061'),
  'https://www.booking.com/ical/88.ics', 'an admin''s webcal:// link is stored as https://');
reset role;
set local request.jwt.claims to '';
```

- [ ] **Step 2: Run it to verify it fails**

Run: `supabase test db supabase/tests/48_ota_sync_test.sql`
Expected: FAIL. The first new assertion gets the untrimmed `WEBCAL://…` link back, and the `throws_ok`s report that no exception was raised.

- [ ] **Step 3: Implement the trigger**

Append to the end of `supabase/migrations/0058_ota_sync_status.sql`:

```sql
-- ---------------------------------------------------------------------
-- 4. Feed URL rules (P0039). A pasted link is trimmed and webcal:// (what
--    some calendar apps show) becomes https://; it must then be an http(s)
--    link with a host, at most 2048 characters, and new to its unit.
--    Invoker: the duplicate check reads ical_feeds through the caller's RLS,
--    and an owner or admin sees every feed of their resort. Existing rows
--    are normalised first, before the trigger exists.

update public.ical_feeds
   set url = regexp_replace(btrim(url, E' \t\r\n'), '^webcal://', 'https://', 'i')
 where url is distinct from
       regexp_replace(btrim(url, E' \t\r\n'), '^webcal://', 'https://', 'i');

create function public.ical_feeds_normalize_url()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  new.url := regexp_replace(btrim(coalesce(new.url, ''), E' \t\r\n'),
                            '^webcal://', 'https://', 'i');
  if length(new.url) > 2048
     or new.url !~* '^https?://[^[:space:]/?#]+[^[:space:]]*$' then
    raise exception using errcode = 'P0039', message = 'invalid_feed_url';
  end if;
  if exists (select 1 from public.ical_feeds f
              where f.unit_id = new.unit_id
                and f.url = new.url
                and f.id is distinct from new.id) then
    raise exception using errcode = 'P0039', message = 'duplicate_feed';
  end if;
  return new;
end;
$$;

create trigger ical_feeds_normalize_url
  before insert or update of url, unit_id on public.ical_feeds
  for each row execute function public.ical_feeds_normalize_url();
```

- [ ] **Step 4: Run the whole database suite**

Run: `supabase db reset && supabase test db`
Expected: 48 passes 102/102. 14 and 37 pass: their feeds use valid `https://` links on distinct units. Every other failure is one of the pre-existing ones recorded in Task 1 Step 1.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/0058_ota_sync_status.sql supabase/tests/48_ota_sync_test.sql
git commit -m "$(cat <<'EOF'
feat(ota): feed URL rules -- trim, webcal to https, refuse bad or duplicate links (P0039)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

## Phase 2: Tracks (after Task 1; 5, 6 and 8 in parallel; 7 after 6)

### Task 5: The `ical-export` Edge Function

**Track:** Deno. Depends on Task 1 (`types.ts`).

**Files:**
- Create: `supabase/functions/ical-export/handler.ts`
- Create: `supabase/functions/ical-export/index.ts`
- Create: `supabase/functions/ical-export/deno.json`
- Modify: `supabase/config.toml`
- Test: `supabase/functions/ical-export/handler_test.ts`

**Interfaces:**
- Consumes: `CalendarLookup`, `CalendarStore`, `ICS_CONTENT_TYPE` and `TOKEN_PATTERN` from `./types.ts`. It also calls PostgREST `POST /rest/v1/rpc/ical_export_public` with the body `{"p_token": "<token>"}`. The existing function returns a JSON string, `null` when the resort is not active, or a 400 carrying `code: "P0002"` for an unknown token.
- Produces:
  - `tokenFrom(url: URL): string | null`
  - `handle(req: Request, store: CalendarStore): Promise<Response>`
  - `restStore(supabaseUrl: string, anonKey: string, fetchFn?: typeof fetch): CalendarStore`
  - The public link `<SUPABASE_URL>/functions/v1/ical-export/<token>.ics`. Task 6 builds it in `icalExportUrl`.

- [ ] **Step 1: Write the failing tests**

Create `supabase/functions/ical-export/handler_test.ts`:

```ts
import { assertEquals, assertStrictEquals } from "jsr:@std/assert@1";
import { handle, restStore, tokenFrom } from "./handler.ts";
import type { CalendarLookup, CalendarStore } from "./types.ts";

const TOKEN = "0123456789abcdef0123456789abcdef0123456789abcdef";
const BASE = "http://localhost:54321/functions/v1/ical-export";
const ICS = "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nEND:VCALENDAR\r\n";

class FakeStore implements CalendarStore {
  calls: string[] = [];
  constructor(private result: CalendarLookup | Error) {}
  lookup(token: string): Promise<CalendarLookup> {
    this.calls.push(token);
    return this.result instanceof Error
      ? Promise.reject(this.result)
      : Promise.resolve(this.result);
  }
}

Deno.test("tokenFrom reads <token>.ics from the path", () => {
  assertEquals(tokenFrom(new URL(`${BASE}/${TOKEN}.ics`)), TOKEN);
  assertEquals(tokenFrom(new URL(`${BASE}/${TOKEN}.ICS`)), TOKEN);
  assertEquals(tokenFrom(new URL(`http://x/ical-export/${TOKEN}`)), TOKEN);
});

Deno.test("tokenFrom falls back to ?token= at the function root", () => {
  assertEquals(tokenFrom(new URL(`${BASE}?token=${TOKEN}`)), TOKEN);
  assertEquals(
    tokenFrom(new URL(`http://x/ical-export/?token=${TOKEN}`)),
    TOKEN,
  );
});

Deno.test("tokenFrom refuses anything that is not a 48-hex token", () => {
  assertStrictEquals(tokenFrom(new URL(`${BASE}/abc.ics`)), null);
  assertStrictEquals(
    tokenFrom(new URL(`${BASE}/${TOKEN.toUpperCase()}.ics`)),
    null,
  );
  assertStrictEquals(tokenFrom(new URL(`${BASE}/${TOKEN}x.ics`)), null);
  assertStrictEquals(tokenFrom(new URL(BASE)), null);
});

Deno.test("GET serves the calendar as text/calendar", async () => {
  const store = new FakeStore({ kind: "ok", ics: ICS });
  const res = await handle(new Request(`${BASE}/${TOKEN}.ics`), store);
  assertEquals(res.status, 200);
  assertEquals(res.headers.get("content-type"), "text/calendar; charset=utf-8");
  assertEquals(res.headers.get("cache-control"), "no-cache, max-age=0");
  assertEquals(await res.text(), ICS);
  assertEquals(store.calls, [TOKEN]);
});

Deno.test("HEAD gives the same headers and no body", async () => {
  const store = new FakeStore({ kind: "ok", ics: ICS });
  const res = await handle(
    new Request(`${BASE}/${TOKEN}.ics`, { method: "HEAD" }),
    store,
  );
  assertEquals(res.status, 200);
  assertEquals(res.headers.get("content-type"), "text/calendar; charset=utf-8");
  assertEquals(await res.text(), "");
});

Deno.test("a malformed token is 404 without asking the database", async () => {
  const store = new FakeStore({ kind: "ok", ics: ICS });
  const res = await handle(new Request(`${BASE}/not-a-token.ics`), store);
  assertEquals(res.status, 404);
  assertEquals(await res.text(), "Calendar not found");
  assertEquals(store.calls, []);
});

Deno.test("an unknown token or inactive resort is 404", async () => {
  const res = await handle(
    new Request(`${BASE}/${TOKEN}.ics`),
    new FakeStore({ kind: "not_found" }),
  );
  assertEquals(res.status, 404);
  assertEquals(res.headers.get("content-type"), "text/plain; charset=utf-8");
  assertEquals(await res.text(), "Calendar not found");
});

Deno.test("a database failure is 502, and a throwing store is too", async () => {
  const quiet = console.error;
  console.error = () => {};
  try {
    const down = await handle(
      new Request(`${BASE}/${TOKEN}.ics`),
      new FakeStore({ kind: "unavailable", detail: "HTTP 500" }),
    );
    assertEquals(down.status, 502);
    assertEquals(await down.text(), "Calendar temporarily unavailable");
    const threw = await handle(
      new Request(`${BASE}/${TOKEN}.ics`),
      new FakeStore(new Error("connection refused")),
    );
    assertEquals(threw.status, 502);
    await threw.body?.cancel();
  } finally {
    console.error = quiet;
  }
});

Deno.test("any other method is 405 with Allow", async () => {
  const res = await handle(
    new Request(`${BASE}/${TOKEN}.ics`, { method: "POST", body: "x" }),
    new FakeStore({ kind: "ok", ics: ICS }),
  );
  assertEquals(res.status, 405);
  assertEquals(res.headers.get("allow"), "GET, HEAD");
  await res.body?.cancel();
});

function fakeFetch(
  status: number,
  body: unknown,
  seen: Request[],
): typeof fetch {
  return (input: RequestInfo | URL, init?: RequestInit) => {
    seen.push(new Request(input, init));
    return Promise.resolve(
      new Response(JSON.stringify(body), {
        status,
        headers: { "Content-Type": "application/json" },
      }),
    );
  };
}

Deno.test("restStore posts p_token with the anon key and unwraps the JSON string", async () => {
  const seen: Request[] = [];
  const store = restStore(
    "http://db.test/",
    "anon-key",
    fakeFetch(200, ICS, seen),
  );
  assertEquals(await store.lookup(TOKEN), { kind: "ok", ics: ICS });
  assertEquals(seen.length, 1);
  assertEquals(seen[0].method, "POST");
  assertEquals(seen[0].url, "http://db.test/rest/v1/rpc/ical_export_public");
  assertEquals(seen[0].headers.get("apikey"), "anon-key");
  assertEquals(seen[0].headers.get("authorization"), "Bearer anon-key");
  assertEquals(await seen[0].json(), { p_token: TOKEN });
});

Deno.test("restStore maps null (resort not active) and P0002 to not_found", async () => {
  assertEquals(
    await restStore("http://db.test", "k", fakeFetch(200, null, [])).lookup(
      TOKEN,
    ),
    { kind: "not_found" },
  );
  assertEquals(
    await restStore(
      "http://db.test",
      "k",
      fakeFetch(400, {
        code: "P0002",
        message: "invalid or unknown iCal token",
      }, []),
    ).lookup(TOKEN),
    { kind: "not_found" },
  );
});

Deno.test("restStore reports any other failure as unavailable", async () => {
  const result = await restStore(
    "http://db.test",
    "k",
    fakeFetch(500, { code: "XX000", message: "boom" }, []),
  ).lookup(TOKEN);
  assertEquals(result, { kind: "unavailable", detail: "HTTP 500 XX000 boom" });
});
```

- [ ] **Step 2: Run them to verify they fail**

Run: `deno test supabase/functions/ical-export/`
Expected: FAIL with `Module not found "…/ical-export/handler.ts"`.

- [ ] **Step 3: Implement the handler and the wiring**

Create `supabase/functions/ical-export/handler.ts`:

```ts
import {
  type CalendarLookup,
  type CalendarStore,
  ICS_CONTENT_TYPE,
  TOKEN_PATTERN,
} from "./types.ts";

/**
 * The token from `/ical-export/<token>.ics`, or from `?token=` when the
 * path ends at the function name. Null unless it looks like a real token,
 * so junk never reaches the database.
 */
export function tokenFrom(url: URL): string | null {
  const last = url.pathname.split("/").filter((s) => s !== "").pop() ?? "";
  const fromPath = last.replace(/\.ics$/i, "");
  const candidate = fromPath === "" || fromPath === "ical-export"
    ? url.searchParams.get("token") ?? ""
    : fromPath;
  return TOKEN_PATTERN.test(candidate) ? candidate : null;
}

function plain(status: number, body: string, head: boolean): Response {
  return new Response(head ? null : body, {
    status,
    headers: {
      "Content-Type": "text/plain; charset=utf-8",
      "Cache-Control": "no-store",
    },
  });
}

/** Serves one unit's calendar to an OTA. Never throws. */
export async function handle(
  req: Request,
  store: CalendarStore,
): Promise<Response> {
  const head = req.method === "HEAD";
  if (req.method !== "GET" && !head) {
    return new Response("Method not allowed", {
      status: 405,
      headers: {
        Allow: "GET, HEAD",
        "Content-Type": "text/plain; charset=utf-8",
      },
    });
  }

  const token = tokenFrom(new URL(req.url));
  if (token === null) return plain(404, "Calendar not found", head);

  let found: CalendarLookup;
  try {
    found = await store.lookup(token);
  } catch (e) {
    found = { kind: "unavailable", detail: String(e) };
  }

  switch (found.kind) {
    case "ok":
      return new Response(head ? null : found.ics, {
        status: 200,
        headers: {
          "Content-Type": ICS_CONTENT_TYPE,
          "Cache-Control": "no-cache, max-age=0",
        },
      });
    case "not_found":
      return plain(404, "Calendar not found", head);
    case "unavailable":
      console.error(`ical-export: ${found.detail}`);
      return plain(502, "Calendar temporarily unavailable", head);
  }
}

/**
 * Reads the calendar through PostgREST's `ical_export_public` (granted to
 * `anon`) with the project's anon key. PostgREST returns the text as a JSON
 * string, or `null` when the unit's resort is not active.
 */
export function restStore(
  supabaseUrl: string,
  anonKey: string,
  fetchFn: typeof fetch = fetch,
): CalendarStore {
  const base = supabaseUrl.replace(/\/+$/, "");
  const endpoint = `${base}/rest/v1/rpc/ical_export_public`;
  return {
    async lookup(token: string): Promise<CalendarLookup> {
      const res = await fetchFn(endpoint, {
        method: "POST",
        headers: {
          apikey: anonKey,
          Authorization: `Bearer ${anonKey}`,
          "Content-Type": "application/json",
          Accept: "application/json",
        },
        body: JSON.stringify({ p_token: token }),
      });
      const body = await res.json().catch(() => null);
      if (res.ok) {
        return typeof body === "string" && body !== ""
          ? { kind: "ok", ics: body }
          : { kind: "not_found" };
      }
      if (body?.code === "P0002") return { kind: "not_found" };
      return {
        kind: "unavailable",
        detail: `HTTP ${res.status} ${body?.code ?? ""} ${body?.message ?? ""}`
          .trim(),
      };
    },
  };
}
```

Create `supabase/functions/ical-export/index.ts`:

```ts
// Wiring only: the logic, and everything the tests cover, is in handler.ts.
// SUPABASE_URL and SUPABASE_ANON_KEY are provided by the edge runtime.
import { handle, restStore } from "./handler.ts";

const store = restStore(
  Deno.env.get("SUPABASE_URL") ?? "",
  Deno.env.get("SUPABASE_ANON_KEY") ?? "",
);

Deno.serve((req) => handle(req, store));
```

Create `supabase/functions/ical-export/deno.json`:

```json
{ "imports": {} }
```

Append to `supabase/config.toml`:

```toml

# P9: the iCal export link that Airbnb/Booking.com fetch. OTAs cannot send
# a JWT; the per-unit token in the path is the only credential.
[functions.ical-export]
verify_jwt = false
```

- [ ] **Step 4: Run the tests and the type check**

Run: `deno fmt supabase/functions/ical-export/ && deno check supabase/functions/ical-export/index.ts && deno test supabase/functions/ical-export/`
Expected: `12 passed | 0 failed`. The check succeeds.

- [ ] **Step 5: Commit**

```bash
git add supabase/functions/ical-export supabase/config.toml
git commit -m "$(cat <<'EOF'
feat(ota): ical-export Edge Function serves the export link as text/calendar

The old PostgREST link could not work: it passed `token` to a function
whose parameter is `p_token`, and PostgREST returns text as a JSON string.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

### Task 6: Sync now runner and the export link

**Track:** Flutter. Depends on Task 1.

**Files:**
- Modify: `lib/data/repositories/ical_sync_runner.dart`
- Modify: `lib/data/repositories/ical_repository.dart` (`exportUrl` and a new `icalExportUrl`)
- Test: `test/data/ical_sync_runner_test.dart`, `test/data/ical_export_url_test.dart`

**Interfaces:**
- Consumes: `IcalSource.syncFeed`, `IcalSyncResult.isFinal` (Task 1), `FakeIcalSource` and `Env.supabaseUrl`.
- Produces:
  - `IcalSyncRunner.syncNow(String feedId)`, implemented. It makes at most `maxCalls` calls and waits `interval` between them.
  - `String icalExportUrl(String supabaseUrl, String token)`, which returns `<url>/functions/v1/ical-export/<token>.ics`.
  - `IcalRepository.exportUrl`, which uses `icalExportUrl`.

- [ ] **Step 1: Write the failing tests**

Create `test/data/ical_sync_runner_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/errors.dart';
import 'package:pasala/data/repositories/ical_repository.dart';
import 'package:pasala/data/repositories/ical_sync_runner.dart';

import '../support/fake_ical_source.dart';

void main() {
  const ok = IcalSyncResult(status: 'ok', events: 3);
  const stale = IcalSyncResult(status: 'ok', events: 1);
  const requested = IcalSyncResult(status: 'requested');
  const pending = IcalSyncResult(status: 'pending');

  late List<Duration> waits;
  IcalSyncRunner runner(FakeIcalSource source, {int maxCalls = 8}) =>
      IcalSyncRunner(
        source,
        maxCalls: maxCalls,
        wait: (delay) async => waits.add(delay),
      );

  setUp(() => waits = []);

  test('a result collected by the first call is stale: the second call\'s '
      'result is returned', () async {
    final source = FakeIcalSource()..syncScript = [stale, ok];

    final result = await runner(source).syncNow('f1');

    expect(result, same(ok));
    expect(source.syncCalls, ['f1', 'f1']);
    expect(waits, [const Duration(seconds: 2)]);
  });

  test('keeps calling through requested and pending until a result is '
      'collected', () async {
    final source = FakeIcalSource()..syncScript = [requested, pending, ok];

    final result = await runner(source).syncNow('f1');

    expect(result, same(ok));
    expect(source.syncCalls, hasLength(3));
    expect(waits, hasLength(2));
  });

  test('an error collected after the first call is returned as it is',
      () async {
    const failed = IcalSyncResult(status: 'error', error: 'HTTP 404');
    final source = FakeIcalSource()..syncScript = [requested, failed];

    expect(await runner(source).syncNow('f1'), same(failed));
  });

  test('a failed fetch on the first call is retried by the next ones',
      () async {
    final source = FakeIcalSource()
      ..syncScript = [
        const IcalSyncResult(status: 'error', error: 'fetch failed: dns'),
        requested,
        ok,
      ];

    expect(await runner(source).syncNow('f1'), same(ok));
    expect(source.syncCalls, hasLength(3));
  });

  test('gives up after maxCalls and reports the sync as still pending',
      () async {
    final source = FakeIcalSource()..syncScript = [requested, pending];

    final result = await runner(source, maxCalls: 5).syncNow('f1');

    expect(result.status, 'pending');
    expect(source.syncCalls, hasLength(5));
    expect(waits, hasLength(4));
  });

  test('a failure from the source (e.g. no permission) propagates', () async {
    final source = FakeIcalSource()..syncError = const NotPermitted();

    expect(runner(source).syncNow('f1'), throwsA(isA<NotPermitted>()));
  });
}
```

Create `test/data/ical_export_url_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/data/repositories/ical_repository.dart';

void main() {
  const token = '0123456789abcdef0123456789abcdef0123456789abcdef';

  test('points at the ical-export Edge Function with the token as a .ics '
      'file', () {
    expect(
      icalExportUrl('https://abc.supabase.co', token),
      'https://abc.supabase.co/functions/v1/ical-export/$token.ics',
    );
  });

  test('a trailing slash on the project URL does not double up', () {
    expect(
      icalExportUrl('http://127.0.0.1:54321/', token),
      'http://127.0.0.1:54321/functions/v1/ical-export/$token.ics',
    );
  });

  test('carries no API key -- the OTA fetches a plain link', () {
    final url = icalExportUrl('https://abc.supabase.co', token);
    expect(url, isNot(contains('apikey')));
    expect(url, isNot(contains('rest/v1')));
  });
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `flutter test test/data/ical_sync_runner_test.dart test/data/ical_export_url_test.dart`
Expected: FAIL. The URL test does not compile (`icalExportUrl` isn't defined). The runner tests throw `UnimplementedError`.

- [ ] **Step 3: Implement**

In `lib/data/repositories/ical_sync_runner.dart`, replace the `syncNow` stub with:

```dart
  Future<IcalSyncResult> syncNow(String feedId) async {
    // The first call only starts a fresh fetch (and may collect a stale one).
    await source.syncFeed(feedId);
    for (var call = 2; call <= maxCalls; call++) {
      await wait(interval);
      final result = await source.syncFeed(feedId);
      if (result.isFinal) return result;
    }
    return const IcalSyncResult(status: 'pending');
  }
```

In `lib/data/repositories/ical_repository.dart`, replace the `exportUrl` override and the comment above it. The old block starts at `// PostgREST's GET-for-RPC convention` and ends at `'?token=$token&apikey=${Env.supabaseAnonKey}';`. The new code is:

```dart
  @override
  String exportUrl(String token) => icalExportUrl(Env.supabaseUrl, token);
```

Then add this top-level function just above `final icalRepositoryProvider`:

```dart
/// The link an OTA fetches for [token]: the `ical-export` Edge Function,
/// which serves the unit's calendar as `text/calendar` (spec decision 15).
/// No key in it -- the function runs with `verify_jwt = false` and the
/// token is the only secret.
String icalExportUrl(String supabaseUrl, String token) {
  final base = supabaseUrl.replaceFirst(RegExp(r'/+$'), '');
  return '$base/functions/v1/ical-export/$token.ics';
}
```

- [ ] **Step 4: Run the tests and the analyzer**

Run: `flutter test test/data && flutter analyze lib/data test/data`
Expected: PASS, and `No issues found!`. The `Env` import stays in use through `Env.supabaseUrl`.

- [ ] **Step 5: Commit**

```bash
git add lib/data/repositories/ical_sync_runner.dart lib/data/repositories/ical_repository.dart \
  test/data/ical_sync_runner_test.dart test/data/ical_export_url_test.dart
git commit -m "$(cat <<'EOF'
feat(ota): Sync now waits for fresh data; export link points at ical-export

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

### Task 7: The OTA screen shows each feed's health

**Track:** Flutter. Depends on Task 6.

**Files:**
- Create: `lib/features/ota/feed_sync_status.dart`
- Modify: `lib/features/ota/ical_screen.dart`
- Modify: `lib/core/errors.dart`
- Test: `test/features/ota/feed_sync_status_test.dart`, `test/features/ota/ical_screen_test.dart`, `test/core/errors_test.dart`

**Interfaces:**
- Consumes:
  - `IcalFeed`, `FeedSyncStatus` and `IcalSyncResult` (Task 1)
  - `icalSyncRunnerProvider` and `IcalSyncRunner` (Task 6)
  - `FailureView.messageFor`
  - `FakeIcalSource` and `icalFeed`
- Produces:
  - `FeedLineTone`, `FeedLine`, `syncAgo`, `eventCount`, `feedErrorHint`, `feedStatusLines`, `syncOutcomeMessage`, `staleAfter`, `hintRelink`, `hintNotCalendar` and `staleWarning`.
  - `IcalScreen({required String unitId, DateTime Function() clock = DateTime.now})`.
  - `FeedUrlRejected`, with the constants `invalid` and `duplicate`.
  - Widget keys: `ical-sync-feed`, `ical-remove-feed`, `ical-syncing`, `ical-feed-url` and `ical-add-feed`.

- [ ] **Step 1: Write the failing unit tests**

Create `test/features/ota/feed_sync_status_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/data/models/ical_feed.dart';
import 'package:pasala/data/repositories/ical_repository.dart';
import 'package:pasala/features/ota/feed_sync_status.dart';

import '../../support/fake_ical_source.dart';

void main() {
  final now = DateTime.utc(2027, 1, 10, 12, 0);

  group('syncAgo', () {
    test('under a minute, or in the future, is just now', () {
      expect(syncAgo(now, now), 'just now');
      expect(syncAgo(now.subtract(const Duration(seconds: 59)), now), 'just now');
      expect(syncAgo(now.add(const Duration(minutes: 3)), now), 'just now');
    });

    test('minutes, hours, then days', () {
      expect(syncAgo(now.subtract(const Duration(minutes: 5)), now), '5 min ago');
      expect(syncAgo(now.subtract(const Duration(minutes: 59)), now), '59 min ago');
      expect(syncAgo(now.subtract(const Duration(minutes: 60)), now), '1 h ago');
      expect(syncAgo(now.subtract(const Duration(hours: 23)), now), '23 h ago');
      expect(syncAgo(now.subtract(const Duration(hours: 24)), now), '1 day ago');
      expect(syncAgo(now.subtract(const Duration(days: 2)), now), '2 days ago');
    });
  });

  test('eventCount is singular for one', () {
    expect(eventCount(0), '0 events');
    expect(eventCount(1), '1 event');
    expect(eventCount(3), '3 events');
  });

  test('feedErrorHint', () {
    expect(feedErrorHint('HTTP 404'), hintRelink);
    expect(feedErrorHint('HTTP 410'), hintRelink);
    expect(feedErrorHint('HTTP 403'), hintRelink);
    expect(feedErrorHint('HTTP 503'), isNull);
    expect(feedErrorHint('not a calendar: the link did not return iCal data'),
        hintNotCalendar);
    expect(feedErrorHint('request timed out'), isNull);
    expect(feedErrorHint(null), isNull);
  });

  group('feedStatusLines', () {
    test('never synced', () {
      expect(feedStatusLines(icalFeed(), now),
          [const FeedLine('Never synced', FeedLineTone.neutral)]);
    });

    test('ok: when and how many events', () {
      final feed = icalFeed(
        lastSyncedAt: now.subtract(const Duration(minutes: 5)),
        lastStatus: FeedSyncStatus.ok,
        lastEventCount: 3,
      );
      expect(feedStatusLines(feed, now),
          [const FeedLine('Last sync 5 min ago · 3 events', FeedLineTone.neutral)]);
    });

    test('ok with skipped events: the note is a warning', () {
      const note = '1 event(s) conflicted with an existing booking and were skipped';
      final feed = icalFeed(
        lastSyncedAt: now.subtract(const Duration(minutes: 5)),
        lastStatus: FeedSyncStatus.ok,
        lastEventCount: 1,
        lastError: note,
      );
      expect(feedStatusLines(feed, now), [
        const FeedLine('Last sync 5 min ago · 1 event', FeedLineTone.neutral),
        const FeedLine(note, FeedLineTone.warning),
      ]);
    });

    test('error: what failed, what to do, and the last good sync', () {
      final feed = icalFeed(
        lastSyncedAt: now.subtract(const Duration(minutes: 5)),
        lastStatus: FeedSyncStatus.error,
        lastError: 'HTTP 404',
        lastOkAt: now.subtract(const Duration(days: 2)),
        lastEventCount: 3,
      );
      expect(feedStatusLines(feed, now), [
        const FeedLine('Sync failed 5 min ago: HTTP 404', FeedLineTone.error),
        const FeedLine(hintRelink, FeedLineTone.error),
        const FeedLine('Last good sync 2 days ago', FeedLineTone.neutral),
      ]);
    });

    test('error on a feed that never worked', () {
      final feed = icalFeed(
        lastSyncedAt: now.subtract(const Duration(minutes: 1)),
        lastStatus: FeedSyncStatus.error,
        lastError: 'request timed out',
      );
      expect(feedStatusLines(feed, now), [
        const FeedLine('Sync failed 1 min ago: request timed out', FeedLineTone.error),
        const FeedLine('No successful sync yet', FeedLineTone.neutral),
      ]);
    });

    test('a status the app does not know reads as ok, without a count', () {
      final feed = icalFeed(lastSyncedAt: now.subtract(const Duration(minutes: 2)));
      expect(feedStatusLines(feed, now),
          [const FeedLine('Last sync 2 min ago', FeedLineTone.neutral)]);
    });

    test('an active feed not synced for over an hour is stale', () {
      final feed = icalFeed(
        lastSyncedAt: now.subtract(const Duration(minutes: 61)),
        lastStatus: FeedSyncStatus.ok,
        lastEventCount: 2,
      );
      expect(feedStatusLines(feed, now).last,
          const FeedLine(staleWarning, FeedLineTone.warning));
    });

    test('an hour exactly is not stale yet, and an inactive feed never is', () {
      final onTheHour = icalFeed(
        lastSyncedAt: now.subtract(const Duration(hours: 1)),
        lastStatus: FeedSyncStatus.ok,
        lastEventCount: 2,
      );
      final paused = icalFeed(
        isActive: false,
        lastSyncedAt: now.subtract(const Duration(days: 3)),
        lastStatus: FeedSyncStatus.ok,
        lastEventCount: 2,
      );
      expect(feedStatusLines(onTheHour, now), hasLength(1));
      expect(feedStatusLines(paused, now), hasLength(1));
    });
  });

  group('syncOutcomeMessage', () {
    test('ok', () {
      expect(syncOutcomeMessage(const IcalSyncResult(status: 'ok', events: 3)),
          'Synced -- 3 events');
    });

    test('ok with conflicts and unreadable events', () {
      expect(
        syncOutcomeMessage(const IcalSyncResult(
            status: 'ok', events: 4, conflicts: 1, failed: 2)),
        'Synced -- 4 events, 1 conflict skipped, 2 unreadable events skipped',
      );
    });

    test('echoes are not mentioned -- they are not a problem', () {
      expect(
        syncOutcomeMessage(
            const IcalSyncResult(status: 'ok', events: 2, echoes: 2)),
        'Synced -- 2 events',
      );
    });

    test('error', () {
      expect(
        syncOutcomeMessage(
            const IcalSyncResult(status: 'error', error: 'HTTP 503')),
        'Sync failed: HTTP 503',
      );
    });

    test('still running', () {
      expect(syncOutcomeMessage(const IcalSyncResult(status: 'pending')),
          'Still syncing -- the result will show here shortly.');
    });
  });
}
```

In `test/core/errors_test.dart`, insert above `test('NotPermitted never leaks the server message', () {`:

```dart
  test('P0039 invalid_feed_url maps to FeedUrlRejected with readable copy',
      () {
    final failure = map('P0039', 'invalid_feed_url');
    expect(failure, isA<FeedUrlRejected>());
    expect(failure.message, FeedUrlRejected.invalid);
  });

  test('P0039 duplicate_feed says the calendar is already added', () {
    final failure = map('P0039', 'duplicate_feed');
    expect(failure, isA<FeedUrlRejected>());
    expect(failure.message, 'This calendar is already added to this unit.');
  });

```

- [ ] **Step 2: Run them to verify they fail**

Run: `flutter test test/features/ota/feed_sync_status_test.dart test/core/errors_test.dart`
Expected: FAIL to compile. The output names `feed_sync_status.dart` and `FeedUrlRejected` as not found.

- [ ] **Step 3: Implement the status logic and P0039**

Create `lib/features/ota/feed_sync_status.dart`:

```dart
import '../../data/models/ical_feed.dart';
import '../../data/repositories/ical_repository.dart';

/// How a status line under an import feed reads: plain, a warning (amber,
/// with a warning icon) or an error (red, with an error icon).
enum FeedLineTone { neutral, warning, error }

class FeedLine {
  const FeedLine(this.text, this.tone);
  final String text;
  final FeedLineTone tone;

  @override
  bool operator ==(Object other) =>
      other is FeedLine && other.text == text && other.tone == tone;

  @override
  int get hashCode => Object.hash(text, tone);

  @override
  String toString() => 'FeedLine($text, $tone)';
}

/// An active feed whose last sync is older than this has missed several
/// 15-minute runs.
const staleAfter = Duration(hours: 1);

const hintRelink =
    'The OTA no longer serves this link. Copy the export link from the OTA '
    'again and replace this feed.';
const hintNotCalendar =
    'Check that you pasted the calendar export link, not the listing page.';
const staleWarning =
    'Automatic sync has not run for over an hour. Press Sync now.';

/// `just now`, `5 min ago`, `3 h ago`, `2 days ago`. A time slightly in the
/// future (the phone's clock behind the server's) reads as `just now`.
String syncAgo(DateTime from, DateTime now) {
  final diff = now.difference(from);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours} h ago';
  return '${diff.inDays} day${diff.inDays == 1 ? '' : 's'} ago';
}

/// `1 event`, `3 events`.
String eventCount(int n) => n == 1 ? '1 event' : '$n events';

/// What the admin can do about a feed-level [error], or null.
String? feedErrorHint(String? error) {
  if (error == null) return null;
  if (RegExp(r'^HTTP (401|403|404|410)\b').hasMatch(error)) return hintRelink;
  if (error.startsWith('not a calendar')) return hintNotCalendar;
  return null;
}

/// The status lines under one import feed, most important first.
List<FeedLine> feedStatusLines(IcalFeed feed, DateTime now) {
  final syncedAt = feed.lastSyncedAt;
  if (syncedAt == null) {
    return const [FeedLine('Never synced', FeedLineTone.neutral)];
  }

  final ago = syncAgo(syncedAt, now);
  final lines = <FeedLine>[];
  if (feed.lastStatus == FeedSyncStatus.error) {
    lines.add(FeedLine(
      'Sync failed $ago: ${feed.lastError ?? 'unknown error'}',
      FeedLineTone.error,
    ));
    final hint = feedErrorHint(feed.lastError);
    if (hint != null) lines.add(FeedLine(hint, FeedLineTone.error));
    final okAt = feed.lastOkAt;
    lines.add(FeedLine(
      okAt == null
          ? 'No successful sync yet'
          : 'Last good sync ${syncAgo(okAt, now)}',
      FeedLineTone.neutral,
    ));
  } else {
    final count = feed.lastEventCount;
    lines.add(FeedLine(
      count == null ? 'Last sync $ago' : 'Last sync $ago · ${eventCount(count)}',
      FeedLineTone.neutral,
    ));
    final note = feed.lastError;
    if (note != null) lines.add(FeedLine(note, FeedLineTone.warning));
  }

  if (feed.isActive && now.difference(syncedAt) > staleAfter) {
    lines.add(const FeedLine(staleWarning, FeedLineTone.warning));
  }
  return lines;
}

/// The snackbar after "Sync now".
String syncOutcomeMessage(IcalSyncResult result) => switch (result.status) {
      'ok' => _okMessage(result),
      'error' => 'Sync failed: ${result.error ?? 'unknown error'}',
      _ => 'Still syncing -- the result will show here shortly.',
    };

String _okMessage(IcalSyncResult result) {
  final parts = ['Synced -- ${eventCount(result.events ?? 0)}'];
  final conflicts = result.conflicts ?? 0;
  if (conflicts > 0) {
    parts.add('$conflicts conflict${conflicts == 1 ? '' : 's'} skipped');
  }
  final failed = result.failed ?? 0;
  if (failed > 0) {
    parts.add('$failed unreadable event${failed == 1 ? '' : 's'} skipped');
  }
  return parts.join(', ');
}
```

In `lib/core/errors.dart`, insert above `/// A 400/422 from Supabase auth`:

```dart
/// P0039 -- the `ical_feeds` URL rules (0058) refused an import feed: not
/// an http(s) or webcal link (`invalid_feed_url`), or already added to this
/// unit (`duplicate_feed`). The server sends bare code words, so the copy
/// lives here.
class FeedUrlRejected extends BookingFailure {
  const FeedUrlRejected(super.message);

  static const invalid =
      'That is not a calendar link. Paste the link that starts with '
      'https:// or webcal://.';
  static const duplicate = 'This calendar is already added to this unit.';
}

```

In `mapPostgrestError`, add below `'P0031' => const AlreadyDispatched(),`:

```dart
    // P0039: import feed URL rules (0058).
    'P0039' => FeedUrlRejected(message == 'duplicate_feed'
        ? FeedUrlRejected.duplicate
        : FeedUrlRejected.invalid),
```

- [ ] **Step 4: Run the unit tests**

Run: `flutter test test/features/ota/feed_sync_status_test.dart test/core/errors_test.dart`
Expected: PASS: 17 status tests and all the error tests.

- [ ] **Step 5: Write the failing widget tests**

In `test/features/ota/ical_screen_test.dart`:

1. Replace everything above the first `testWidgets(` (the imports and the `pump` helper) with:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/errors.dart';
import 'package:pasala/data/models/ical_feed.dart';
import 'package:pasala/data/repositories/ical_repository.dart';
import 'package:pasala/data/repositories/ical_sync_runner.dart';
import 'package:pasala/features/ota/feed_sync_status.dart';
import 'package:pasala/features/ota/ical_screen.dart';

import '../../support/fake_ical_source.dart';

final _now = DateTime.utc(2027, 1, 10, 12, 0);

void main() {
  /// [wait] is how the Sync now runner waits between calls; by default it
  /// returns at once.
  Future<void> pump(
    WidgetTester tester,
    FakeIcalSource source, {
    String unitId = 'u1',
    SyncWait? wait,
  }) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        icalSourceProvider.overrideWithValue(source),
        icalSyncRunnerProvider.overrideWithValue(
          IcalSyncRunner(source, wait: wait ?? (_) async {}),
        ),
      ],
      child: MaterialApp(home: IcalScreen(unitId: unitId, clock: () => _now)),
    ));
    await tester.pumpAndSettle();
  }

```

2. Delete the four tests from `testWidgets('a feed with a last_error shows it honestly'` through the end of `testWidgets('a sync error from the RPC is shown, not swallowed'`. Put this in their place:

```dart
  testWidgets('an ok feed shows when it last synced and how many events',
      (tester) async {
    await pump(
      tester,
      FakeIcalSource()
        ..rows = [
          icalFeed(
            lastSyncedAt: _now.subtract(const Duration(minutes: 5)),
            lastStatus: FeedSyncStatus.ok,
            lastEventCount: 3,
          ),
        ],
    );

    expect(find.text('Last sync 5 min ago · 3 events'), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsNothing);
    expect(find.byIcon(Icons.warning_amber_outlined), findsNothing);
  });

  testWidgets('skipped events show as a warning with an icon', (tester) async {
    const note =
        '1 event(s) conflicted with an existing booking and were skipped';
    await pump(
      tester,
      FakeIcalSource()
        ..rows = [
          icalFeed(
            lastSyncedAt: _now.subtract(const Duration(minutes: 5)),
            lastStatus: FeedSyncStatus.ok,
            lastEventCount: 1,
            lastError: note,
          ),
        ],
    );

    expect(find.text('Last sync 5 min ago · 1 event'), findsOneWidget);
    expect(find.text(note), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_outlined), findsOneWidget);
  });

  testWidgets('a failing feed shows the error in red with an icon, a hint and '
      'the last good sync', (tester) async {
    await pump(
      tester,
      FakeIcalSource()
        ..rows = [
          icalFeed(
            lastSyncedAt: _now.subtract(const Duration(minutes: 5)),
            lastStatus: FeedSyncStatus.error,
            lastError: 'HTTP 404',
            lastOkAt: _now.subtract(const Duration(days: 2)),
            lastEventCount: 3,
          ),
        ],
    );

    final error = find.text('Sync failed 5 min ago: HTTP 404');
    expect(error, findsOneWidget);
    final context = tester.element(error);
    expect(tester.widget<Text>(error).style?.color,
        Theme.of(context).colorScheme.error);
    expect(find.text(hintRelink), findsOneWidget);
    expect(find.text('Last good sync 2 days ago'), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsNWidgets(2));
  });

  testWidgets('a feed the 15-minute job has not reached for over an hour is '
      'flagged', (tester) async {
    await pump(
      tester,
      FakeIcalSource()
        ..rows = [
          icalFeed(
            lastSyncedAt: _now.subtract(const Duration(hours: 3)),
            lastStatus: FeedSyncStatus.ok,
            lastEventCount: 2,
          ),
        ],
    );

    expect(find.text('Last sync 3 h ago · 2 events'), findsOneWidget);
    expect(find.text(staleWarning), findsOneWidget);
  });

  testWidgets('Sync now waits for a fresh result, reports it and reloads the '
      'feeds', (tester) async {
    final source = FakeIcalSource()
      ..rows = [icalFeed()]
      ..syncScript = [
        const IcalSyncResult(status: 'ok', events: 1),
        const IcalSyncResult(status: 'ok', events: 3),
      ];
    await pump(tester, source);
    final loadsBefore = source.feedsCalls;

    await tester.tap(find.widgetWithText(TextButton, 'Sync now'));
    await tester.pumpAndSettle();

    expect(source.syncCalls, ['f1', 'f1']);
    expect(find.text('Synced -- 3 events'), findsOneWidget);
    expect(source.feedsCalls, greaterThan(loadsBefore));
  });

  testWidgets('while syncing, a spinner replaces Sync now', (tester) async {
    final gate = Completer<void>();
    final source = FakeIcalSource()..rows = [icalFeed()];
    await pump(tester, source, wait: (_) => gate.future);

    await tester.tap(find.byKey(const Key('ical-sync-feed')));
    await tester.pump();

    expect(find.byKey(const Key('ical-syncing')), findsOneWidget);
    expect(find.text('Syncing…'), findsOneWidget);
    expect(find.byKey(const Key('ical-sync-feed')), findsNothing);
    expect(
      tester
          .widget<TextButton>(find.byKey(const Key('ical-remove-feed')))
          .onPressed,
      isNull,
    );

    gate.complete();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ical-sync-feed')), findsOneWidget);
  });

  testWidgets('conflicts from Sync now are reported, not silently dropped', (
    tester,
  ) async {
    final source = FakeIcalSource()
      ..rows = [icalFeed()]
      ..syncResult =
          const IcalSyncResult(status: 'ok', events: 3, conflicts: 1);
    await pump(tester, source);

    await tester.tap(find.byKey(const Key('ical-sync-feed')));
    await tester.pumpAndSettle();

    expect(find.text('Synced -- 3 events, 1 conflict skipped'), findsOneWidget);
  });

  testWidgets('a sync error is shown, not swallowed', (tester) async {
    final source = FakeIcalSource()
      ..rows = [icalFeed()]
      ..syncResult = const IcalSyncResult(status: 'error', error: 'HTTP 503');
    await pump(tester, source);

    await tester.tap(find.byKey(const Key('ical-sync-feed')));
    await tester.pumpAndSettle();

    expect(find.text('Sync failed: HTTP 503'), findsOneWidget);
  });

  testWidgets('a sync that is still running when the runner gives up says so',
      (tester) async {
    final source = FakeIcalSource()
      ..rows = [icalFeed()]
      ..syncResult = const IcalSyncResult(status: 'pending');
    await pump(tester, source);

    await tester.tap(find.byKey(const Key('ical-sync-feed')));
    await tester.pumpAndSettle();

    expect(find.text('Still syncing -- the result will show here shortly.'),
        findsOneWidget);
    expect(source.syncCalls, hasLength(8));
  });

  testWidgets('a refused Sync (no access) goes through FailureView copy',
      (tester) async {
    final source = FakeIcalSource()
      ..rows = [icalFeed()]
      ..syncError = const NotPermitted();
    await pump(tester, source);

    await tester.tap(find.byKey(const Key('ical-sync-feed')));
    await tester.pumpAndSettle();

    expect(find.text('You do not have access to do that.'), findsOneWidget);
    expect(find.byKey(const Key('ical-sync-feed')), findsOneWidget);
  });

```

3. Insert these tests just above `testWidgets('an export-token repository error goes through FailureView, '`:

```dart
  testWidgets('a feed removed while Sync now runs says so and reloads the '
      'list', (tester) async {
    final source = FakeIcalSource()
      ..rows = [icalFeed()]
      ..syncError = const NotFound();
    await pump(tester, source);
    final loadsBefore = source.feedsCalls;

    await tester.tap(find.byKey(const Key('ical-sync-feed')));
    await tester.pumpAndSettle();

    expect(find.text('That item no longer exists.'), findsOneWidget);
    expect(source.feedsCalls, greaterThan(loadsBefore));
  });

  testWidgets('a link that is not http(s) or webcal is refused by the form',
      (tester) async {
    await pump(tester, FakeIcalSource());

    await tester.enterText(
      find.byKey(const Key('ical-feed-url')),
      'airbnb.com/calendar/ical/1.ics',
    );
    await tester.pump();

    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('ical-add-feed')))
          .onPressed,
      isNull,
    );
    expect(
      find.text('Paste the calendar link (starts with https:// or webcal://).'),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const Key('ical-feed-url')),
      'webcal://www.airbnb.com/calendar/ical/1.ics',
    );
    await tester.pump();

    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('ical-add-feed')))
          .onPressed,
      isNotNull,
    );
    expect(
      find.text('Paste the calendar link (starts with https:// or webcal://).'),
      findsNothing,
    );
  });

  testWidgets('a feed the server refuses (P0039) shows why', (tester) async {
    final source = FakeIcalSource()
      ..addError = const FeedUrlRejected(FeedUrlRejected.duplicate);
    await pump(tester, source);

    await tester.enterText(
      find.byKey(const Key('ical-feed-url')),
      'https://www.airbnb.com/calendar/ical/1.ics',
    );
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('ical-add-feed')));
    await tester.tap(find.byKey(const Key('ical-add-feed')));
    await tester.pumpAndSettle();

    expect(find.text('This calendar is already added to this unit.'),
        findsOneWidget);
    expect(source.added, isEmpty);
  });

  testWidgets('a failing feed fits a 360 px phone without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await pump(
      tester,
      FakeIcalSource()
        ..rows = [
          icalFeed(
            label: 'Airbnb -- Cottage by the long lake',
            url: 'https://www.airbnb.com/calendar/ical/12345678901234567890.ics'
                '?s=0123456789abcdef0123456789abcdef',
            lastSyncedAt: _now.subtract(const Duration(hours: 2)),
            lastStatus: FeedSyncStatus.error,
            lastError: 'not a calendar: the link did not return iCal data',
          ),
        ],
    );

    expect(tester.takeException(), isNull);
    expect(find.widgetWithText(TextButton, 'Sync now'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Remove'), findsOneWidget);
  });

```

- [ ] **Step 6: Run them to verify they fail**

Run: `flutter test test/features/ota/ical_screen_test.dart`
Expected: FAIL. `IcalScreen` has no `clock` parameter, so the file does not compile.

- [ ] **Step 7: Rewrite the screen**

Replace the whole of `lib/features/ota/ical_screen.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/failure_view.dart';
import '../../core/widgets/section_header.dart';
import '../../data/models/ical_feed.dart';
import '../../data/repositories/ical_repository.dart';
import '../../data/repositories/ical_sync_runner.dart';
import 'feed_sync_status.dart';

/// The amber used for warnings, the same as the room grid's Cleaning.
const _warningColor = Color(0xFFB26A00);

/// `http://`, `https://` or `webcal://` followed by something -- the form's
/// first check; the `ical_feeds` trigger (P0039) is the real rule.
final _feedUrlPattern =
    RegExp(r'^(https?|webcal)://\S+$', caseSensitive: false);

/// Every `ical_feeds` row for one unit -- RLS (`ical_feeds_read`) scopes
/// this to the resort's owners and admins; anyone else gets zero rows, not
/// an error, same convention as every other admin-only list in this app.
final icalFeedsProvider = FutureProvider.family<List<IcalFeed>, String>(
  (ref, unitId) => ref.watch(icalSourceProvider).feeds(unitId),
);

/// The unit's current export token, from `ical_export_tokens` (also
/// admin-only -- see `ical_repository.dart`'s header for why it is not a
/// column on `units`).
final icalExportTokenProvider = FutureProvider.family<String, String>(
  (ref, unitId) => ref.watch(icalSourceProvider).exportToken(unitId),
);

/// `/admin/ota/:unitId` -- Airbnb/Booking.com calendar sync for one unit,
/// with no paid channel manager: an export URL to paste INTO the OTA
/// (top), and the list of feeds this unit imports FROM the OTA, with add,
/// remove and a manual Sync (below). Reachable only by an admin --
/// `ical_feeds_admin`/`ical_export_tokens_admin` RLS is the real
/// enforcement underneath, same as everywhere else in `/admin/*`.
class IcalScreen extends StatelessWidget {
  const IcalScreen({
    super.key,
    required this.unitId,
    this.clock = DateTime.now,
  });

  final String unitId;

  /// What "5 min ago" is measured against; injectable so tests do not
  /// depend on the wall clock.
  final DateTime Function() clock;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('OTA calendar sync')),
        body: ListView(
          padding: const EdgeInsets.all(Spacing.md),
          children: [
            _ExportSection(unitId: unitId),
            const SectionHeader(title: 'Import feeds'),
            _ImportFeedsSection(unitId: unitId, clock: clock),
          ],
        ),
      );
}

class _ExportSection extends ConsumerWidget {
  const _ExportSection({required this.unitId});
  final String unitId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokenAsync = ref.watch(icalExportTokenProvider(unitId));
    final textTheme = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Export URL', style: textTheme.titleMedium),
            const SizedBox(height: Spacing.xs),
            Text(
              'Paste this link into the OTA\'s "import calendar" setting '
              '(Airbnb: Availability -> Connect calendars; Booking.com: '
              'Rates & Availability -> Sync calendars). It lists only busy '
              'dates -- no guest name, email or amount ever appears in it.',
              style: textTheme.bodySmall,
            ),
            const SizedBox(height: Spacing.sm),
            AsyncView(
              value: tokenAsync,
              onRetry: () => ref.invalidate(icalExportTokenProvider(unitId)),
              data: (token) => _ExportUrlRow(unitId: unitId, token: token),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExportUrlRow extends ConsumerStatefulWidget {
  const _ExportUrlRow({required this.unitId, required this.token});
  final String unitId;
  final String token;

  @override
  ConsumerState<_ExportUrlRow> createState() => _ExportUrlRowState();
}

class _ExportUrlRowState extends ConsumerState<_ExportUrlRow> {
  bool _rotating = false;

  Future<void> _copy() async {
    final url = ref.read(icalSourceProvider).exportUrl(widget.token);
    await Clipboard.setData(ClipboardData(text: url));
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Export URL copied')));
    }
  }

  Future<void> _rotate() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Rotate export token?'),
        content: const Text(
          'The current export URL stops working immediately. Update it '
          'wherever it is pasted (e.g. Airbnb) right after rotating.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Rotate'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _rotating = true);
    try {
      await ref.read(icalSourceProvider).rotateExportToken(widget.unitId);
      ref.invalidate(icalExportTokenProvider(widget.unitId));
    } on BookingFailure catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(FailureView.messageFor(e))));
      }
    } finally {
      if (mounted) setState(() => _rotating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final url = ref.watch(icalSourceProvider).exportUrl(widget.token);
    return Row(
      children: [
        Expanded(child: SelectableText(url, key: const Key('ical-export-url'))),
        IconButton(
          key: const Key('ical-copy-url'),
          icon: const Icon(Icons.copy_outlined),
          tooltip: 'Copy',
          onPressed: _copy,
        ),
        IconButton(
          key: const Key('ical-rotate-token'),
          icon: _rotating
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh),
          tooltip: 'Rotate token',
          onPressed: _rotating ? null : _rotate,
        ),
      ],
    );
  }
}

class _ImportFeedsSection extends ConsumerWidget {
  const _ImportFeedsSection({required this.unitId, required this.clock});
  final String unitId;
  final DateTime Function() clock;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feedsAsync = ref.watch(icalFeedsProvider(unitId));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AsyncView(
          value: feedsAsync,
          onRetry: () => ref.invalidate(icalFeedsProvider(unitId)),
          data: (feeds) => feeds.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: Spacing.md,
                    vertical: Spacing.sm,
                  ),
                  child: Text('No import feeds yet -- add one below.'),
                )
              : Column(
                  children: [
                    for (final feed in feeds)
                      Padding(
                        padding: const EdgeInsets.only(bottom: Spacing.sm),
                        child: _FeedTile(
                          feed: feed,
                          unitId: unitId,
                          clock: clock,
                        ),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: Spacing.sm),
        _AddFeedForm(unitId: unitId),
      ],
    );
  }
}

class _FeedTile extends ConsumerStatefulWidget {
  const _FeedTile({
    required this.feed,
    required this.unitId,
    required this.clock,
  });
  final IcalFeed feed;
  final String unitId;
  final DateTime Function() clock;

  @override
  ConsumerState<_FeedTile> createState() => _FeedTileState();
}

class _FeedTileState extends ConsumerState<_FeedTile> {
  bool _syncing = false;
  bool _removing = false;

  Future<void> _sync() async {
    setState(() => _syncing = true);
    try {
      final result =
          await ref.read(icalSyncRunnerProvider).syncNow(widget.feed.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(syncOutcomeMessage(result))));
      }
    } on BookingFailure catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(FailureView.messageFor(e))));
      }
    } finally {
      if (mounted) {
        setState(() => _syncing = false);
        ref.invalidate(icalFeedsProvider(widget.unitId));
      }
    }
  }

  Future<void> _remove() async {
    setState(() => _removing = true);
    try {
      await ref.read(icalSourceProvider).removeFeed(widget.feed.id);
      ref.invalidate(icalFeedsProvider(widget.unitId));
    } on BookingFailure catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(FailureView.messageFor(e))));
      }
      if (mounted) setState(() => _removing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final feed = widget.feed;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final hasLabel = feed.label != null && feed.label!.isNotEmpty;
    final busy = _syncing || _removing;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(hasLabel ? feed.label! : feed.url,
                key: const Key('ical-feed-title'), style: textTheme.bodyLarge),
            if (hasLabel)
              Text(feed.url,
                  style: textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant)),
            for (final line in feedStatusLines(feed, widget.clock()))
              _StatusLine(line: line),
            const SizedBox(height: Spacing.sm),
            Wrap(
              spacing: Spacing.sm,
              runSpacing: Spacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (_syncing)
                  const Row(
                    key: Key('ical-syncing'),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: Spacing.sm),
                      Text('Syncing…'),
                    ],
                  )
                else
                  TextButton.icon(
                    key: const Key('ical-sync-feed'),
                    onPressed: busy ? null : _sync,
                    icon: const Icon(Icons.sync),
                    label: const Text('Sync now'),
                  ),
                TextButton.icon(
                  key: const Key('ical-remove-feed'),
                  onPressed: busy ? null : _remove,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Remove'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// One status line: warnings and errors carry an icon, never colour alone.
class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.line});
  final FeedLine line;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (IconData? icon, Color color) = switch (line.tone) {
      FeedLineTone.neutral => (null, scheme.onSurfaceVariant),
      FeedLineTone.warning => (Icons.warning_amber_outlined, _warningColor),
      FeedLineTone.error => (Icons.error_outline, scheme.error),
    };
    return Padding(
      padding: const EdgeInsets.only(top: Spacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: color),
            const SizedBox(width: Spacing.xs),
          ],
          Expanded(
            child: Text(
              line.text,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddFeedForm extends ConsumerStatefulWidget {
  const _AddFeedForm({required this.unitId});
  final String unitId;

  @override
  ConsumerState<_AddFeedForm> createState() => _AddFeedFormState();
}

class _AddFeedFormState extends ConsumerState<_AddFeedForm> {
  final _url = TextEditingController();
  final _label = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // Same reason as `BlockDatesScreen`'s `_reason` listener: the Add
    // button's enabled state depends on this text, which
    // TextEditingController does not trigger a rebuild for on its own.
    _url.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _url.dispose();
    _label.dispose();
    super.dispose();
  }

  bool get _urlValid => _feedUrlPattern.hasMatch(_url.text.trim());
  bool get _canAdd => !_busy && _urlValid;

  Future<void> _add() async {
    if (!_canAdd) return;
    setState(() => _busy = true);
    try {
      await ref.read(icalSourceProvider).addFeed(
            unitId: widget.unitId,
            url: _url.text.trim(),
            label: _label.text.trim().isEmpty ? null : _label.text.trim(),
          );
      ref.invalidate(icalFeedsProvider(widget.unitId));
      _url.clear();
      _label.clear();
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
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(Spacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Add import feed', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: Spacing.sm),
              TextField(
                key: const Key('ical-feed-url'),
                controller: _url,
                decoration: InputDecoration(
                  labelText: 'Calendar URL',
                  hintText: 'https://www.airbnb.com/calendar/ical/....ics',
                  errorText: _url.text.trim().isEmpty || _urlValid
                      ? null
                      : 'Paste the calendar link (starts with https:// or '
                          'webcal://).',
                ),
              ),
              const SizedBox(height: Spacing.sm),
              TextField(
                key: const Key('ical-feed-label'),
                controller: _label,
                decoration: const InputDecoration(
                  labelText: 'Label (optional)',
                  hintText: 'Airbnb',
                ),
              ),
              const SizedBox(height: Spacing.sm),
              FilledButton(
                key: const Key('ical-add-feed'),
                onPressed: _canAdd ? _add : null,
                child: const Text('Add feed'),
              ),
            ],
          ),
        ),
      );
}
```

- [ ] **Step 8: Run the tests and the analyzer**

Run: `flutter test test/features/ota test/core/errors_test.dart test/core/router_test.dart && flutter analyze`
Expected:
- PASS: 24 screen tests and 17 status tests. The router test still builds `IcalScreen(unitId: …)` without a clock.
- `flutter analyze` reports only the 2 baseline infos.

- [ ] **Step 9: Commit**

```bash
git add lib/features/ota/feed_sync_status.dart lib/features/ota/ical_screen.dart \
  lib/core/errors.dart test/features/ota/feed_sync_status_test.dart \
  test/features/ota/ical_screen_test.dart test/core/errors_test.dart
git commit -m "$(cat <<'EOF'
feat(ota): each feed shows last sync, event count or error, with Sync now

Warnings and errors carry icons; the add form checks the link; P0039 has
readable copy.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

### Task 8: README section on linking a real listing

**Track:** docs. Depends on Task 1. It only names things Tasks 3, 5 and 7 build, so it can be written alongside them.

**Files:**
- Modify: `README.md`
- Modify: `docs/STATUS.md`

**Interfaces:**
- Consumes these names and texts:
  - The link shape `…/functions/v1/ical-export/<token>.ics` (Task 5).
  - The screen texts from the Global Constraints (Task 7).
  - The server error texts (Task 3).
  - `supabase functions deploy ical-export`.
- Produces: the section `## Linking a real Airbnb or Booking.com listing`, which `docs/STATUS.md` links to.

- [ ] **Step 1: Update the README's OTA paragraph**

In `README.md`, under `**OTA calendar sync — iCal (phase 2)**`, make three changes.

1. Replace the bullet that begins `- **An export URL** to paste into Airbnb` (all six of its lines) with:

~~~markdown
- **An export URL** to paste into Airbnb or Booking.com's "import calendar"
  setting: `<SUPABASE_URL>/functions/v1/ical-export/<token>.ics`, served as
  `text/calendar` by the `ical-export` Edge Function. It lists only busy
  date ranges as RFC 5545 `VEVENT`s — no guest name, email, or amount ever
  appears in it, by construction: the builder reads `unit_calendar_events`,
  the identity-free occupancy mirror, never `reservations` directly.
~~~

2. Replace the paragraph beginning `**Automatic polling is wired and real**` with:

~~~markdown
**Automatic polling is wired and real**: `pg_net` is available in this local
stack, so a `pg_cron` job (`ical-poll-feeds`, every 15 minutes) fetches every
active import feed and applies it automatically. The admin "Sync now" button
drives the same function and waits for fresh data. Each feed shows
"Last sync 5 min ago · 3 events", or its error in red with a hint. All-day
OTA events are placed at the resort's own check-in and check-out times, and
an OTA listing our own booking back to us is not reported as a conflict.
The import is tested against fixtures in the real Airbnb and Booking.com
export formats (`supabase/tests/48_ota_sync_test.sql`).
~~~

3. Replace the paragraph beginning `**The export URL shape has never been verified against a real Airbnb or` (three lines) with:

~~~markdown
**Linking a real listing is the one step left to verify by hand** — see
[Linking a real Airbnb or Booking.com listing](#linking-a-real-airbnb-or-bookingcom-listing).
~~~

- [ ] **Step 2: Add the new section**

In `README.md`, insert this section immediately above `## Known limitations`:

~~~markdown
## Linking a real Airbnb or Booking.com listing

This needs a live OTA listing, so it has to be done by someone who manages
one. Plan on about 30 minutes, plus however long the OTA takes to refresh
an imported calendar (often a few hours).

### Before you start

- The hosted project has every migration applied, and `pg_cron` and `pg_net`
  enabled (Database → Extensions).
- The export function is deployed: `supabase functions deploy ical-export`.
  `supabase/config.toml` sets `verify_jwt = false` for it, because an OTA
  cannot send a key. With an older CLI, add `--no-verify-jwt`.
- The app you use is built with the hosted `SUPABASE_URL`, because the
  export link is built from it.

### 1. Give the OTA our calendar

1. In the app, go to Admin → Properties → Units → the unit's menu → **OTA
   sync**, and copy the **Export URL**. It looks like
   `https://<project>.supabase.co/functions/v1/ical-export/<48 hex characters>.ics`.
2. Check the link before pasting it anywhere:

   ```bash
   curl -i 'https://<project>.supabase.co/functions/v1/ical-export/<token>.ics'
   ```

   Expect `200`, `content-type: text/calendar; charset=utf-8`, and a body
   starting with `BEGIN:VCALENDAR`. A `404 Calendar not found` means the
   token was rotated or mistyped, or the resort is not active.
3. Paste it into the OTA's import setting:
   - Airbnb: Listing → Availability → Connect calendars → Import.
   - Booking.com extranet: Rates & Availability → Sync calendars → Add
     calendar connection.
   - Menu names change; look for "import calendar". Name it "ResortHub".

### 2. Give our app the OTA's calendar

1. Copy the OTA's own export link. It is on the same page as the import,
   under "Export".
   - Airbnb: `https://www.airbnb.com/calendar/ical/<id>.ics?s=<secret>`.
   - Booking.com: a link to `admin.booking.com/…ical…`.
   - A `webcal://` link is fine: the app stores it as `https://`.
2. On the OTA sync screen, go to **Add import feed**. Paste the link, label
   it "Airbnb" or "Booking.com", and press **Add feed**.
3. Press **Sync now**. Within about 15 seconds the feed shows
   `Last sync just now · N events`. N should match the stays plus blocked
   periods on that OTA calendar, counting from today.

### 3. Prove both directions

1. **Ours to the OTA.** Block one night here (Admin → Block dates). After the
   OTA refreshes, that night shows as unavailable there. Check that it blocks
   **exactly** that night. Our export uses exact check-in/check-out times, so
   write down if an OTA also blocks the next night.
2. **The OTA to ours.** Block one night on the OTA, then press **Sync now**
   here. The count goes up by one, and the night is unavailable in this app's
   booking calendar.
3. Remove both test blocks. Removing the OTA block does **not** free the
   night here (see "Known gaps" below). Ask a developer to cancel the
   imported reservation.

### What the feed status means

| The feed shows | Meaning | What to do |
|---|---|---|
| `Last sync 5 min ago · 3 events` | Healthy. | Nothing. |
| Amber `N event(s) conflicted with an existing booking and were skipped` | The OTA has a stay on dates already booked here. | A double booking: contact the guest, then close the dates on the OTA. |
| Amber `N event(s) failed to import and were skipped (…)` | Some events could not be read. | Send the note and the OTA's link to a developer. |
| Red `Sync failed …: HTTP 404` (or 401, 403, 410) | The OTA no longer serves this link (it was reset, or the listing was unlisted). | Copy the export link from the OTA again, remove this feed and add the new link. |
| Red `Sync failed …: not a calendar: …` | The link opens a web page, not a calendar. | Use the calendar **export** link, not the listing page. |
| Red `request timed out` or `HTTP 5xx` | The OTA is down for a while. | Nothing; the next run is within 15 minutes. |
| Amber `Automatic sync has not run for over an hour` | The `pg_cron` job is not running. | In the SQL editor, run `select * from cron.job_run_details order by start_time desc limit 5;` and check that `ical-poll-feeds` is scheduled and succeeding. |

An OTA listing our own bookings back to us ("Airbnb (Not available)",
"CLOSED - Not available") is normal and is not counted as a conflict.

### Record the result

Update item 5 in `docs/STATUS.md` with the date, the OTA, and the listing.
Record whether each direction passed, and whether the OTA blocked any extra
night.

### Known gaps

- When an event disappears from an OTA feed (a cancellation there), the
  dates stay blocked here. Reservations do not yet record which feed they
  came from.
- Our export lists timed events (check-in to check-out). Step 3.1 is where
  you find out whether an OTA rounds them to one night too many.
~~~

- [ ] **Step 3: Update the out-of-scope bullet**

In `README.md`, replace the bullet under `## Known limitations` that begins `- **The iCal export URL shape has never been verified against a real` (five lines) with:

~~~markdown
- **The iCal link has not yet been tried with a real Airbnb or Booking.com
  listing** — see "Linking a real Airbnb or Booking.com listing" above. The
  import is tested against fixtures in both OTAs' real formats and the export
  is served as `text/calendar`; how a live OTA reads our export is what is
  left to check. Events removed from an OTA feed are not removed here.
~~~

- [ ] **Step 4: Update `docs/STATUS.md`**

1. In the phase 2 bullet that begins `- **iCal export and import.**`, replace the sentences from `Polling is real:` to the end of that bullet with:

~~~markdown
  Polling is real: a `pg_cron` job runs every 15 minutes, and each feed shows
  its last sync, its event count, or its error. The import is tested against
  fixtures in the real Airbnb and Booking.com formats (all-day events at the
  resort's check-in/check-out times, folded lines, CRLF/LF, time zones), and
  the export link is served as `text/calendar` by the `ical-export` Edge
  Function. What has NOT been verified: a real Airbnb or Booking.com listing
  on either end — see item 5 below.
~~~

2. Replace item `5.` (the numbered item that begins `5. **For iCal: pasting this app's export URL into Airbnb`) with:

~~~markdown
5. **For iCal: linking a real Airbnb and/or Booking.com listing.** The steps
   are in the README, "Linking a real Airbnb or Booking.com listing". This is
   a configuration step, not a paid account, but it needs a live listing,
   which the project does not have yet. Everything short of that is tested
   (see the iCal bullet above). Consequence while missing: **a double-booking
   between this app and a real OTA calendar is possible until someone with a
   listing performs the README steps and records the result here.**
~~~

3. Replace the known-limitations bullet that begins `- **The iCal export URL shape has never been verified against a real` (two lines) with:

~~~markdown
- **The iCal link has not yet been tried with a real Airbnb or Booking.com
  listing** (see item 5 above). Events removed from an OTA feed are not
  removed here.
~~~

- [ ] **Step 5: Check the links and the wording**

Run: `grep -n "ical-export\|Linking a real" README.md docs/STATUS.md && grep -n "has never been verified" README.md docs/STATUS.md`
Expected:
- The first grep lists the new section, the anchor link, and the STATUS references.
- The second grep prints nothing, because every "has never been verified" sentence about the iCal URL is replaced. If a line is still printed, it is an iCal sentence the steps above missed: fix it in the same way.

- [ ] **Step 6: Commit**

```bash
git add README.md docs/STATUS.md
git commit -m "$(cat <<'EOF'
docs(ota): how to link a real Airbnb or Booking.com listing, and what the feed status means

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

## Phase 3: Integration

### Task 9: Merge the tracks and verify end to end

**Track:** both. Depends on Tasks 2–8.

**Files:** none new. This task resolves merge conflicts only.

- [ ] **Step 1: Merge**

Merge the database branch (Tasks 2–4) and the track branches (Tasks 5–8) into the P9 branch. P9's own tasks touch disjoint files, so they do not conflict with each other. If other gap projects (P1–P11) merged first, conflicts are expected in these shared files. Keep every side:
- `lib/core/errors.dart`: each project adds its own failure class and its own `'P00xx' =>` case.
- `supabase/config.toml`: `[functions.*]` sections from P6, P7 and P8.
- `README.md` and `docs/STATUS.md`: new sections and bullets from P6 and P7.

- [ ] **Step 2: Run every suite**

Run: `supabase db reset && supabase test db 2>&1 | tail -20`
Expected: 48 passes 102/102, and 14 and 37 pass. The only failures are the baseline ones recorded in Task 1 Step 1.

Run: `deno test supabase/functions/ical-export/`
Expected: `12 passed | 0 failed`.

Run: `flutter analyze 2>&1 | tail -3 && flutter test 2>&1 | tail -1`
Expected: only the 2 baseline analyzer infos. `All tests passed!`, with the Flutter count from Task 1 Step 1 plus the tests added in Tasks 1, 6 and 7.

- [ ] **Step 3: Check the export link end to end, locally**

Run:

```bash
supabase start   # the local edge runtime serves supabase/functions
TOKEN=$(psql 'postgresql://postgres:postgres@127.0.0.1:54322/postgres' -tAc \
  "select token from public.ical_export_tokens limit 1")
curl -si "http://127.0.0.1:54321/functions/v1/ical-export/$TOKEN.ics" | head -12
curl -si "http://127.0.0.1:54321/functions/v1/ical-export/000000000000000000000000000000000000000000000000.ics" | head -1
```

Expected: the first response is `HTTP/1.1 200 OK` with `content-type: text/calendar; charset=utf-8` and a body starting `BEGIN:VCALENDAR`. The second is `404`. If the function is not served, run `supabase functions serve ical-export --no-verify-jwt` in another terminal and repeat.

- [ ] **Step 4: Check the import end to end, locally**

Save the Airbnb fixture from Task 2 as `airbnb.ics` in a scratch directory. Its content is the text between `$ics$` quotes, with CRLF line endings. Serve that directory with `python3 -m http.server 8765`. Then:
1. Run the app: `make run-web`. Sign in as the seeded admin. Go to Admin → Properties → Units → a unit's menu → OTA sync.
2. Add the feed `http://host.docker.internal:8765/airbnb.ics`, which pg_net reaches from inside the database container, and press **Sync now**.

   Expected: within about 15 seconds, a `Synced -- 2 events` snackbar, then `Last sync just now · 2 events`. Then check the periods:

   ```bash
   psql 'postgresql://postgres:postgres@127.0.0.1:54322/postgres' -c \
     "select external_uid, period from reservations where source = 'ical' order by lower(period)"
   ```

   Expected: `["2027-10-09 08:30:00+00","2027-10-12 05:30:00+00")`, which is 14:00 to 11:00 in Asia/Kolkata.
3. Add a second feed, `http://host.docker.internal:8765/`. The directory listing there is an HTML page. Press **Sync now**.

   Expected: in red, `Sync failed just now: not a calendar: the link did not return iCal data`, followed by the hint about the export link and `No successful sync yet`.
4. Paste `http://host.docker.internal:8765/airbnb.ics ` again, with a trailing space, and press **Add feed**.

   Expected: the snackbar `This calendar is already added to this unit.` The trigger trims the link before it checks for a duplicate.
5. Remove the test feeds and the imported reservations, then stop the HTTP server.

- [ ] **Step 5: Commit any merge resolutions**

```bash
git status --short
git commit -am "$(cat <<'EOF'
chore(ota): merge P9 tracks

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

(Skip the commit if there were no merge resolutions.)

---

## Self-Review

**Spec coverage:**

| Spec item | Where it is built |
|---|---|
| Decisions 1–4 (fixture tests, status columns, the screen, the README) | Tasks 2–3, 1 and 3, 7, 8 |
| Decision 5 (resort times) | Task 3 (`ical_event_period`, plus the Asia/Kolkata and Europe/London assertions) |
| Decisions 6–7 (zones and parser rules) | Task 2 |
| Decision 8 (echoes) | Task 3 |
| Decisions 9–12 (error against warning, `last_ok_at`, fetch time, the event count) | Task 3 |
| Decision 13 (Sync now) | Task 6, with the screen in Task 7 |
| Decision 14 (URL rules, P0039) | Task 4, with the form and copy in Task 7 |
| Decision 15 (export link) | Tasks 5 and 6 |
| Decision 16 (no definer) | Task 1 contract assertions |
| Decision 17 (backfill) | Task 1 migration |
| Out of scope (removal reconciliation, export format) | Stated in the README (Task 8) |

**Placeholder scan:** every code step has complete code. No "TBD", "similar to" or "add validation" remains.

**Type consistency:**
- `IcalSyncRunner(source, {wait, maxCalls, interval})` and `syncNow` match across Tasks 1, 6 and 7.
- The fields of `FakeIcalSource` match the `icalFeed` builder in Tasks 1, 6 and 7.
- The `ical_parse_feed` columns match the Task 1 contract assertion and the loop in Task 3.
- The poll result keys (`events`, `echoes`) match `IcalSyncResult.fromJson`.
- The SQL error texts match `feedErrorHint` and the README table.

**Plan counts:** `48_ota_sync_test.sql` grows 12 → 49 → 91 → 102. Each task updates `select plan(N)` before adding its section.

**Review Focus:** every one of the five lines has an owning test: Task 3 (empty calendar; London resort), Task 4 (newline plus `WEBCAL://`; webcal duplicate), Task 7 (future timestamp; feed removed mid-sync).
