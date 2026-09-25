# QR Scanning at the Front Desk (P3) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the guest's decorative check-in QR into a signed, expiring pass. Reception scans the pass with the device camera, or types it, to open that booking's check-in.

**Architecture:** Two new `security definer` functions:
- `issue_stay_pass` signs a pass for the caller's own booking.
- `verify_stay_pass` checks the signature, the caller's Staff+ role at the pass's resort and the expiry, then returns the booking.

The pass is `rh1.` plus base64url of (reservation id ‖ property id ‖ expiry ‖ 16-byte HMAC-SHA256 tag). The HMAC key is a random per-database secret in a `private` schema that the API cannot reach.

On the app side, a `StayPassSource` seam sits behind Riverpod providers. It feeds:
- a shared `StayPassQr` widget on the three guest screens
- a `/admin/check-in/scan` camera screen built on `mobile_scanner`
- a search field, a "Scan pass" button and a check-in sheet on reception's check-in screen

**Tech Stack:** Supabase Postgres 17 (plpgsql, pgcrypto `extensions.hmac`, pgTAP via `supabase test db`), Flutter 3.44 / Dart 3.10, Riverpod 3.3, go_router 17, qr_flutter 4.1, mobile_scanner 7.4, Playwright.

**Spec:** `docs/superpowers/specs/2026-09-25-p3-qr-scanning-at-the-front-desk-design.md`

## Global Constraints

- One migration: `supabase/migrations/0052_stay_pass.sql`. Tasks 1–3 each edit it. After every edit, rebuild with `supabase db reset` (it re-runs every migration and `supabase/seed.sql`), then run pgTAP. Before the first reset, dump local data if you need it: `mkdir -p ../pasala-db-backups && supabase db dump --local --data-only -f ../pasala-db-backups/local-before-stay-pass.sql`.
- New pgTAP file: `supabase/tests/43_stay_pass_test.sql`. Tasks 1–3 build it up section by section, and each section relies on the fixtures and `test.*` settings the earlier ones leave. `plan()` goes 15 → 35 → 65. Run one file with `supabase test db supabase/tests/43_stay_pass_test.sql` and the whole suite with `supabase test db`.
- New error code **P0034**, raised as `raise exception using errcode = 'P0034', message = '<word>'` with exactly one of `pass_invalid`, `pass_expired`, `pass_other_resort`. The existing codes keep their meaning: P0002 not found, P0008 authentication required, P0009 wrong status, P0020 not a member, P0022 suspended.
- Every new `public` security definer function is `stable` and has `set search_path = public, pg_temp`. It is revoked from `public` and `anon`, granted to `authenticated`, and added to the definer allow-list in `supabase/tests/37_tenancy_isolation_test.sql`.
- Staff+ means `owner, admin, staff, accountant`, the same set as `check_in_booking` in `0045_resort_functions.sql`. Verifying is a read: `has_resort_role(<property>, false, ...)`.
- The HMAC secret never leaves Postgres. Never put it or any real key in Dart, in a test or in a commit.
- pgTAP conventions (from `37_tenancy_isolation_test.sql`): switch users with `set local role authenticated; set local request.jwt.claims to '{"sub":"<uuid>","role":"authenticated"}';`. `reset role` does **not** clear the claims, so run `set local request.jwt.claims to '';` before any superuser `update public.properties set status = ...` (the `properties_guard_status` trigger checks `auth.uid()`).
- Known pgTAP failures that appear only 00:00–05:30 IST: 25/9, 26/3, 34/2. Everything else must pass. `flutter analyze` baseline: 2 infos in `service_request_screen.dart`.
- Dart: repositories wrap every call in `_guard`, which maps errors through `mapPostgrestError` (`lib/core/errors.dart`). Widget tests use fakes from `test/support/` and never a real `SupabaseClient`. A test that makes a provider fail passes `retry: (_, _) => null` to its `ProviderScope`/`ProviderContainer`, because Riverpod 3 retries failed providers on its own.
- UI copy, exact:
  - Guest: `Check-in QR` (existing card title), `Show this at check-in` (existing), `Booking code PR3F2A`, `Couldn't load your pass. Show the booking code at the desk.`, the dialog title `Check-in pass`, `Close`, the retry tooltip `Try again`, the thumbnail tooltip `Show check-in pass`, the QR semantics label `Check-in pass QR code`.
  - Reception: the search label `Booking code, name or phone`, the button `Scan pass`, the field button tooltip `Open pass`, the empty filter `No booking matches "<query>"`, the list subtitle `Booking PR3F2A`, the sheet title `Pass verified`, the sheet button `Check in guest`, and the status lines `Already checked in`, `This stay has already checked out`, `This booking was cancelled`, `This booking is not confirmed yet`.
  - Scanner: the title `Scan pass`, the hint `Point the camera at the guest's check-in QR.`, the button `Enter code instead`.
  - P0034: invalid `This is not a valid check-in pass.`; expired `This pass has expired. Ask the guest to reopen their booking, or find them in the list.`; other resort `This pass is for a booking at a different resort.`
- Commands: `flutter test <path>`, `flutter test`, `flutter analyze`. Never run `dart format` on whole directories or on pre-existing files; format only the lines you write. Revert SDK-only `pubspec.lock` bumps (Task 5's real `mobile_scanner` lock entries are kept).
- Every commit message ends with a blank line and `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Do not push.

## Review Focus

1. **The camera reads the same QR on many frames**, and a person holding a phone steady produces a burst of identical reads. The scanner must leave its screen once and verify once, never pop the check-in list off the stack as well. Owning test: Task 5 ("the first code read leaves the screen with that code, once").
2. **A keyboard-wedge barcode scanner or a paste** delivers the pass with surrounding spaces or a trailing newline, and presses Enter. The pass must be trimmed and verified on Enter; the search must not just filter the list to nothing. Owning tests: Task 6 ("a pass typed by a keyboard scanner opens on Enter, trimmed") and Task 1 (`looksLikeStayPass` accepts padded text).
3. **A person who works at two resorts scans a guest of the other resort** while the app is on the current one. The server allows it (they are Staff+ there), but checking the guest in from the wrong resort's desk must be refused with the "different resort" message. Owning test: Task 6 ("a pass for another resort is refused even when the server verified it").
4. **The guest opens their booking with no signal**, or the booking is not confirmed yet, so `issue_stay_pass` fails. The screen must still render, with the booking code and a retry, and never a raw error or an endless spinner. Owning test: Task 4 ("a pass that fails to load shows the booking code and retries").
5. **An old screenshot of the previous bare-UUID QR**, or any other QR (a Wi-Fi code, a menu link), is scanned. It must read as "not a valid check-in pass", never crash or look up a booking. Owning tests: Task 3 (bare UUID and garbage → `pass_invalid`), Task 1 (an unknown P0034 word still reads as invalid, and the raw text is never shown).

## Plan decisions (where the spec is silent)

- The cross-resort checks for the pass functions live in `43_stay_pass_test.sql`, not in 37's role matrix. 37 gets only the two allow-list names, so its `plan(77)` is untouched and merges with other projects' edits to 37 stay simple.
- `issue_stay_pass` and `verify_stay_pass` are `stable`. Neither writes.
- `verify_stay_pass` checks the format with the regex `^rh1\.[A-Za-z0-9_-]{75}$` before decoding, so `decode()` never sees bad input and no exception block is needed.
- The private helpers are plain `language sql` functions in `private`. `private.stay_pass_token` exists so pgTAP can mint expired and forged passes.
- The guest-side `stayPassProvider` is **not** `autoDispose`. The pass for a booking never changes, so it is fetched once per app session and kept in memory.
- `StayPassRepository.verify` trims the token, and the reception screen trims too. The server never trims.
- `bookingCode` / `bookingMatchesSearch` stay in `admin_bookings_screen.dart`. The guest widget imports `bookingCode` from there with `show`, so the file is not moved and no other project conflicts.
- The Playwright spec reuses `support/frontdesk-data.ts` (setup and teardown per file; `workers: 1`), so it adds no new fixture ids.

## Execution tracks

After Task 1, the database track and the app track share no files and can run in parallel: two worktrees branched from Task 1's commit, merged back before Task 7. App tasks never need a database, because their tests use `FakeStayPassSource`.

| Task | Track | Depends on | Files it owns |
|---|---|---|---|
| 1 Interface contract | interface | none | `0052` (schema, secret, stubs), `43` (fixtures + contract), `37` (allow-list), `errors.dart`, `verified_pass.dart`, `stay_pass_repository.dart`, `fake_stay_pass_source.dart`, their tests |
| 2 `issue_stay_pass` and the pass format | DB | 1 | `0052`, `43` |
| 3 `verify_stay_pass` | DB | 2 | `0052`, `43` |
| 4 Guest pass QR | App | 1 | `stay_pass_qr.dart`, `confirmation_screen.dart`, `booking_detail_screen.dart`, `my_stay_screen.dart`, their tests |
| 5 Scanner screen and route | App | 1 | `pubspec.yaml`, `pubspec.lock`, `ios/Runner/Info.plist`, `scan_pass_screen.dart`, `router.dart`, `router_test.dart`, `scan_pass_screen_test.dart` |
| 6 Reception search, scan and sheet | App | 1 | `reception_checkin_screen.dart`, `pass_check_in_sheet.dart`, `reception_checkin_screen_test.dart` |
| 7 Integration | both | 2–6 | `e2e/tests/stay-pass.spec.ts`, `README.md` |

- The database track is strictly sequential (one migration, one test file, one local Postgres).
- Tasks 4, 5 and 6 are independent of each other. Task 6 pushes the route string `/admin/check-in/scan` and tests it with a stub route, so it never imports Task 5's screen.

---

## File Structure

**Database**
- Create `supabase/migrations/0052_stay_pass.sql`: the `private` schema, `private.stay_pass_secret` and its seed, the base64url / HMAC / token helpers, `issue_stay_pass` and `verify_stay_pass`.
- Create `supabase/tests/43_stay_pass_test.sql`: fixtures, contract, issue, verify.
- Modify `supabase/tests/37_tenancy_isolation_test.sql`: the definer allow-list.

**App**
- Modify `lib/core/errors.dart`: `PassRejection`, `StayPassRejected`, and P0034.
- Create `lib/data/models/verified_pass.dart`: `VerifiedPass` and `looksLikeStayPass`.
- Create `lib/data/repositories/stay_pass_repository.dart`: `StayPassSource`, `StayPassRepository` and the providers.
- Create `lib/features/stay/stay_pass_qr.dart`: `StayPassQr`, `StayPassThumbnail` and `showStayPassDialog`.
- Modify `lib/features/booking/confirmation_screen.dart`, `lib/features/account/booking_detail_screen.dart` and `lib/features/stay/my_stay_screen.dart`: render the pass.
- Create `lib/features/admin/scan_pass_screen.dart`: `ScanPassScreen`, `passScannerProvider`, `CameraPassScanner` and `cameraErrorMessage`.
- Create `lib/features/admin/pass_check_in_sheet.dart`: `PassCheckInSheet` and `passStatusLine`.
- Modify `lib/features/admin/reception_checkin_screen.dart`: search, Scan pass, and the verify flow.
- Modify `lib/core/router.dart`: the `scan` child route and the staff-or-above path.
- Modify `pubspec.yaml` / `pubspec.lock` (`mobile_scanner`) and `ios/Runner/Info.plist` (`NSCameraUsageDescription`).

**Tests and docs**
- Create `test/support/fake_stay_pass_source.dart`, `test/data/verified_pass_test.dart`, `test/data/stay_pass_provider_test.dart`, `test/features/stay/stay_pass_qr_test.dart` and `test/features/admin/scan_pass_screen_test.dart`.
- Modify `test/core/errors_test.dart`, `test/core/router_test.dart`, `test/features/booking/confirmation_screen_test.dart`, `test/features/account/booking_detail_screen_test.dart`, `test/features/stay/my_stay_screen_test.dart` and `test/features/admin/reception_checkin_screen_test.dart`.
- Create `e2e/tests/stay-pass.spec.ts`. Modify `README.md`.

---

## Phase 0: Interface

### Task 1: Interface contract (secret, function signatures, Dart API)

**Track:** interface. Every later task depends on it.

**Files:**
- Create: `supabase/migrations/0052_stay_pass.sql`
- Create: `supabase/tests/43_stay_pass_test.sql`
- Modify: `supabase/tests/37_tenancy_isolation_test.sql` (definer allow-list, around lines 436–451)
- Modify: `lib/core/errors.dart`
- Create: `lib/data/models/verified_pass.dart`
- Create: `lib/data/repositories/stay_pass_repository.dart`
- Create: `test/support/fake_stay_pass_source.dart`
- Test: `test/core/errors_test.dart`, `test/data/verified_pass_test.dart`, `test/data/stay_pass_provider_test.dart`

**Interfaces:**
- Consumes: `public.has_resort_role(uuid, boolean, variadic resort_role[])` (0043), `extensions.gen_random_bytes` (pgcrypto, used by 0018/0045). `Reservation.fromJson` (`lib/data/models/reservation.dart`), `mapPostgrestError`, `supabaseProvider`.
- Produces (SQL; Tasks 2 and 3 replace only the stub bodies and add private helpers):
  - `public.issue_stay_pass(p_reservation uuid) returns text`
  - `public.verify_stay_pass(p_token text) returns jsonb`: `to_jsonb(reservations row)` plus `profiles: {full_name, phone}` and `unit_name`
  - schema `private`, table `private.stay_pass_secret (id boolean pk, secret bytea, created_at)` with one 32-byte row
  - error P0034 with `pass_invalid | pass_expired | pass_other_resort`
- Produces (Dart):
  - `enum PassRejection { invalid, expired, otherResort }`
  - `class StayPassRejected extends BookingFailure`, with const constructors `.invalid()`, `.expired()`, `.otherResort()`, `factory StayPassRejected.fromServer(String code)`, and field `final PassRejection reason`
  - `class VerifiedPass { final Reservation reservation; final String propertyId; final String? unitName; factory VerifiedPass.fromJson(Map<String, dynamic>) }`
  - `bool looksLikeStayPass(String text)`: true when the trimmed text starts with `rh1.`
  - `abstract class StayPassSource { Future<String> issue(String reservationId); Future<VerifiedPass> verify(String token); }`
  - Providers:
    - `stayPassRepositoryProvider`: `Provider<StayPassRepository>`
    - `stayPassSourceProvider`: `Provider<StayPassSource>`
    - `stayPassProvider`: `FutureProvider.family<String, String>`, keyed by reservation id, not autoDispose
  - Test support:
    - `FakeStayPassSource`, with the fields `tokens`, `issueError`, `verified` and `verifyError`, and the call logs `issueCalls` and `verifyCalls`. By default a pass is `'rh1.fake-<reservationId>'`.
    - `verifiedPass({...})`

- [ ] **Step 1: Record the baselines**

Run: `supabase db reset && supabase test db 2>&1 | tail -20`, then `flutter analyze 2>&1 | tail -5`, then `flutter test 2>&1 | tail -3`
Expected: write down the pgTAP failure count and names (only the 3 known IST-midnight ones, if you run between 00:00 and 05:30 IST), the analyzer issue count (2 infos), and the Flutter pass count. Later tasks compare against these numbers.

- [ ] **Step 2: Write the failing pgTAP contract test**

Create `supabase/tests/43_stay_pass_test.sql`:

```sql
-- QR scanning at the front desk (P3), added in 0052_stay_pass.sql. See
-- docs/superpowers/specs/2026-09-25-p3-qr-scanning-at-the-front-desk-design.md.
--
-- One file, built up by the plan's tasks in order (contract, issue,
-- verify): each section relies on the fixtures and the `test.*` settings
-- the sections before it leave behind.
--
-- Fixtures: resort R (owner, admin, staff, accountant), resort S (one
-- staff member), guest Gita with five bookings at R, guest Hari with one
-- at S, and an outsider with no membership.
--   ...021 R Cottage 1  confirmed    tomorrow -> +3 days   (Gita)
--   ...022 R Cottage 2  checked_in   yesterday -> tomorrow (Gita)
--   ...023 R Cottage 1  cancelled    +10 -> +12 days       (Gita)
--   ...024 R Cottage 1  checked_out  -10 -> -8 days        (Gita)
--   ...025 R Cottage 2  confirmed    -5 -> -3 days, a no-show whose stay has ended (Gita)
--   ...026 S Villa      confirmed    tomorrow -> +3 days   (Hari)
begin;
select plan(15);

insert into auth.users (id, email) values
  ('f3000000-0000-0000-0000-000000000001','pass-r-owner@example.com'),
  ('f3000000-0000-0000-0000-000000000002','pass-r-admin@example.com'),
  ('f3000000-0000-0000-0000-000000000003','pass-r-staff@example.com'),
  ('f3000000-0000-0000-0000-000000000004','pass-r-accountant@example.com'),
  ('f3000000-0000-0000-0000-000000000005','pass-s-staff@example.com'),
  ('f3000000-0000-0000-0000-000000000006','pass-gita@example.com'),
  ('f3000000-0000-0000-0000-000000000007','pass-hari@example.com'),
  ('f3000000-0000-0000-0000-000000000008','pass-outsider@example.com');
update public.profiles set full_name = 'Gita Guest', phone = '9000000001'
  where id = 'f3000000-0000-0000-0000-000000000006';
update public.profiles set full_name = 'Hari Guest'
  where id = 'f3000000-0000-0000-0000-000000000007';

insert into public.properties (id, name, slug) values
  ('f3f3f3f3-0000-4000-8000-000000000001','Pass Resort R','pass-r'),
  ('f3f3f3f3-0000-4000-8000-000000000002','Pass Resort S','pass-s');

insert into public.resort_members (property_id, user_id, role) values
  ('f3f3f3f3-0000-4000-8000-000000000001','f3000000-0000-0000-0000-000000000001','owner'),
  ('f3f3f3f3-0000-4000-8000-000000000001','f3000000-0000-0000-0000-000000000002','admin'),
  ('f3f3f3f3-0000-4000-8000-000000000001','f3000000-0000-0000-0000-000000000003','staff'),
  ('f3f3f3f3-0000-4000-8000-000000000001','f3000000-0000-0000-0000-000000000004','accountant'),
  ('f3f3f3f3-0000-4000-8000-000000000002','f3000000-0000-0000-0000-000000000005','staff');

insert into public.units (id, property_id, name, capacity_base, capacity_max) values
  ('f3f3f3f3-0000-4000-8000-000000000011','f3f3f3f3-0000-4000-8000-000000000001','Cottage 1',2,4),
  ('f3f3f3f3-0000-4000-8000-000000000012','f3f3f3f3-0000-4000-8000-000000000001','Cottage 2',2,4),
  ('f3f3f3f3-0000-4000-8000-000000000013','f3f3f3f3-0000-4000-8000-000000000002','S Villa',2,4);

insert into public.reservations
  (id, unit_id, period, kind, status, customer_id, guests, checked_in_at, checked_out_at)
values
  ('f3f3f3f3-0000-4000-8000-000000000021','f3f3f3f3-0000-4000-8000-000000000011',
   tstzrange(now() + interval '1 day', now() + interval '3 days', '[)'),
   'booking','confirmed','f3000000-0000-0000-0000-000000000006',2,null,null),
  ('f3f3f3f3-0000-4000-8000-000000000022','f3f3f3f3-0000-4000-8000-000000000012',
   tstzrange(now() - interval '1 day', now() + interval '1 day', '[)'),
   'booking','checked_in','f3000000-0000-0000-0000-000000000006',2,now() - interval '1 day',null),
  ('f3f3f3f3-0000-4000-8000-000000000023','f3f3f3f3-0000-4000-8000-000000000011',
   tstzrange(now() + interval '10 days', now() + interval '12 days', '[)'),
   'booking','cancelled','f3000000-0000-0000-0000-000000000006',2,null,null),
  ('f3f3f3f3-0000-4000-8000-000000000024','f3f3f3f3-0000-4000-8000-000000000011',
   tstzrange(now() - interval '10 days', now() - interval '8 days', '[)'),
   'booking','checked_out','f3000000-0000-0000-0000-000000000006',2,
   now() - interval '10 days', now() - interval '8 days'),
  ('f3f3f3f3-0000-4000-8000-000000000025','f3f3f3f3-0000-4000-8000-000000000012',
   tstzrange(now() - interval '5 days', now() - interval '3 days', '[)'),
   'booking','confirmed','f3000000-0000-0000-0000-000000000006',2,null,null),
  ('f3f3f3f3-0000-4000-8000-000000000026','f3f3f3f3-0000-4000-8000-000000000013',
   tstzrange(now() + interval '1 day', now() + interval '3 days', '[)'),
   'booking','confirmed','f3000000-0000-0000-0000-000000000007',2,null,null);

-- ---------------------------------------------------------------------
-- Section 1: contract (Task 1)

select has_function('public', 'issue_stay_pass', array['uuid'], 'issue_stay_pass(uuid) exists');
select has_function('public', 'verify_stay_pass', array['text'], 'verify_stay_pass(text) exists');
select is(pg_get_function_result('public.issue_stay_pass(uuid)'::regprocedure), 'text',
  'issue_stay_pass returns text');
select is(pg_get_function_result('public.verify_stay_pass(text)'::regprocedure), 'jsonb',
  'verify_stay_pass returns jsonb');
select is(
  (select array_agg(p.proname::text order by p.proname)
     from pg_proc p
    where p.pronamespace = 'public'::regnamespace
      and p.proname in ('issue_stay_pass', 'verify_stay_pass')
      and p.prosecdef
      and p.provolatile = 's'
      and exists (select 1 from unnest(p.proconfig) c
                   where c like 'search_path=%public%pg_temp%')),
  array['issue_stay_pass', 'verify_stay_pass'],
  'both pass functions are stable security definer with a pinned search_path');
select ok(not has_function_privilege('anon', 'public.issue_stay_pass(uuid)', 'execute'),
  'anon cannot execute issue_stay_pass');
select ok(not has_function_privilege('anon', 'public.verify_stay_pass(text)', 'execute'),
  'anon cannot execute verify_stay_pass');
select ok(has_function_privilege('authenticated', 'public.issue_stay_pass(uuid)', 'execute'),
  'authenticated can execute issue_stay_pass');
select ok(has_function_privilege('authenticated', 'public.verify_stay_pass(text)', 'execute'),
  'authenticated can execute verify_stay_pass');
select has_table('private', 'stay_pass_secret', 'private.stay_pass_secret exists');
select is((select count(*)::int from private.stay_pass_secret where length(secret) = 32), 1,
  'one 32-byte secret is seeded');
select ok(not has_schema_privilege('authenticated', 'private', 'usage'),
  'authenticated cannot use the private schema');
select ok(not has_schema_privilege('anon', 'private', 'usage'),
  'anon cannot use the private schema');
select ok(not has_table_privilege('authenticated', 'private.stay_pass_secret', 'select'),
  'authenticated has no select on the secret');

set local role authenticated;
set local request.jwt.claims to '{"sub":"f3000000-0000-0000-0000-000000000003","role":"authenticated"}';
select throws_ok($$select secret from private.stay_pass_secret$$, '42501', null,
  'resort staff cannot read the secret');
reset role;

select * from finish();
rollback;
```

- [ ] **Step 3: Run it to verify it fails**

Run: `supabase test db supabase/tests/43_stay_pass_test.sql`
Expected: FAIL. `has_function` is not ok, and the file aborts at `function public.issue_stay_pass(uuid) does not exist` (the `::regprocedure` cast).

- [ ] **Step 4: Write the migration with stubs**

Create `supabase/migrations/0052_stay_pass.sql`:

```sql
-- QR scanning at the front desk (P3): signed check-in passes.
-- See docs/superpowers/specs/2026-09-25-p3-qr-scanning-at-the-front-desk-design.md.
--
-- A pass is 'rh1.' || base64url(reservation id (16 bytes) || property id
-- (16) || expiry, epoch seconds (8, big-endian) || the first 16 bytes of
-- HMAC-SHA256(secret, 'rh1.' || those 40 bytes)): 79 characters. The key is
-- one random secret per database, in a schema the API does not expose;
-- only the security definer functions below read it.

create schema if not exists private;
revoke all on schema private from public;
revoke all on schema private from anon, authenticated;

create table private.stay_pass_secret (
  id         boolean primary key default true check (id),
  secret     bytea not null check (length(secret) >= 32),
  created_at timestamptz not null default now()
);
revoke all on private.stay_pass_secret from public, anon, authenticated;

-- One random secret per database; keeps whatever is already there.
-- Rotate with: update private.stay_pass_secret
--                 set secret = extensions.gen_random_bytes(32);
-- (every pass issued before then reads as pass_invalid).
insert into private.stay_pass_secret (secret)
values (extensions.gen_random_bytes(32))
on conflict (id) do nothing;

-- Stub: Task 2 replaces the body.
create function public.issue_stay_pass(p_reservation uuid)
returns text
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  raise exception using errcode = '0A000', message = 'issue_stay_pass not implemented';
end;
$$;

-- Stub: Task 3 replaces the body.
create function public.verify_stay_pass(p_token text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  raise exception using errcode = '0A000', message = 'verify_stay_pass not implemented';
end;
$$;

revoke execute on function public.issue_stay_pass(uuid) from public, anon;
revoke execute on function public.verify_stay_pass(text) from public, anon;
grant execute on function public.issue_stay_pass(uuid) to authenticated;
grant execute on function public.verify_stay_pass(text) to authenticated;
```

- [ ] **Step 5: Add the functions to the definer allow-list**

In `supabase/tests/37_tenancy_isolation_test.sql`, in the `p.proname <> all (array[...])` list, add this block right after the `'list_dispatchable_staff',` line (inside the array, before the `-- 0048: finance reports.` comment):

```sql
        -- 0052: stay passes. issue_stay_pass only signs the caller's own
        -- booking; verify_stay_pass asserts Staff+ at the resort the signed
        -- pass names and that the booking belongs to that resort.
        'issue_stay_pass','verify_stay_pass',
```

- [ ] **Step 6: Run the pgTAP tests**

Run: `supabase db reset && supabase test db supabase/tests/43_stay_pass_test.sql supabase/tests/37_tenancy_isolation_test.sql`
Expected: PASS, 43 at 15/15 and 37 at 77/77.

- [ ] **Step 7: Write the failing Dart tests**

Append to `test/core/errors_test.dart`, inside `main()` after the P0031 test:

```dart
  group('P0034 maps to StayPassRejected by code word', () {
    test('pass_invalid', () {
      final failure = map('P0034', 'pass_invalid');
      expect(failure, isA<StayPassRejected>());
      expect((failure as StayPassRejected).reason, PassRejection.invalid);
      expect(failure.message, 'This is not a valid check-in pass.');
    });

    test('pass_expired', () {
      final failure = map('P0034', 'pass_expired') as StayPassRejected;
      expect(failure.reason, PassRejection.expired);
      expect(failure.message,
          'This pass has expired. Ask the guest to reopen their booking, '
          'or find them in the list.');
    });

    test('pass_other_resort', () {
      final failure = map('P0034', 'pass_other_resort') as StayPassRejected;
      expect(failure.reason, PassRejection.otherResort);
      expect(failure.message,
          'This pass is for a booking at a different resort.');
    });

    // Review Focus 5: whatever the server sends, the desk never sees raw
    // text, and an unknown word reads as an invalid pass.
    test('an unknown code word reads as invalid and never leaks', () {
      final failure = map('P0034', 'something_new') as StayPassRejected;
      expect(failure.reason, PassRejection.invalid);
      expect(failure.message, isNot(contains('something_new')));
    });
  });
```

Create `test/data/verified_pass_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/data/models/reservation.dart';
import 'package:pasala/data/models/verified_pass.dart';

void main() {
  test('fromJson reads the booking, its resort and its unit name', () {
    final pass = VerifiedPass.fromJson({
      'id': 'res-1',
      'unit_id': 'u1',
      'property_id': 'p1',
      'period': '["2026-09-26 08:30:00+00","2026-09-28 05:30:00+00")',
      'kind': 'booking',
      'status': 'confirmed',
      'customer_id': 'c1',
      'guests': 2,
      'quote': null,
      'profiles': {'full_name': 'Ravi Kumar', 'phone': '9000000001'},
      'unit_name': 'Cottage 1',
    });

    expect(pass.reservation.id, 'res-1');
    expect(pass.reservation.unitId, 'u1');
    expect(pass.reservation.status, ReservationStatus.confirmed);
    expect(pass.reservation.start, DateTime.utc(2026, 9, 26, 8, 30));
    expect(pass.reservation.customerName, 'Ravi Kumar');
    expect(pass.reservation.customerPhone, '9000000001');
    expect(pass.reservation.guests, 2);
    expect(pass.propertyId, 'p1');
    expect(pass.unitName, 'Cottage 1');
  });

  test('a missing unit name is allowed', () {
    final pass = VerifiedPass.fromJson({
      'id': 'res-1',
      'unit_id': 'u1',
      'property_id': 'p1',
      'period': '["2026-09-26 08:30:00+00","2026-09-28 05:30:00+00")',
      'kind': 'booking',
      'status': 'cancelled',
    });
    expect(pass.unitName, isNull);
    expect(pass.reservation.status, ReservationStatus.cancelled);
  });

  group('looksLikeStayPass', () {
    test('accepts a pass, with or without surrounding whitespace', () {
      expect(looksLikeStayPass('rh1.abc'), isTrue);
      expect(looksLikeStayPass('  rh1.abc\n'), isTrue);
    });

    test('rejects booking codes, names, bare ids and empty text', () {
      expect(looksLikeStayPass('PR3F2A'), isFalse);
      expect(looksLikeStayPass('Ravi'), isFalse);
      expect(looksLikeStayPass('3f2a1b9c-0000-0000-0000-000000000000'), isFalse);
      expect(looksLikeStayPass(''), isFalse);
    });
  });
}
```

Create `test/data/stay_pass_provider_test.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/errors.dart';
import 'package:pasala/data/repositories/stay_pass_repository.dart';

import '../support/fake_stay_pass_source.dart';

void main() {
  test('stayPassProvider asks once per booking and keeps the pass', () async {
    final fake = FakeStayPassSource()..tokens['res-1'] = 'rh1.abc';
    final container = ProviderContainer(
      overrides: [stayPassSourceProvider.overrideWithValue(fake)],
    );
    addTearDown(container.dispose);

    expect(await container.read(stayPassProvider('res-1').future), 'rh1.abc');
    expect(await container.read(stayPassProvider('res-1').future), 'rh1.abc');
    expect(fake.issueCalls, ['res-1']);
  });

  test('each booking has its own pass', () async {
    final fake = FakeStayPassSource();
    final container = ProviderContainer(
      overrides: [stayPassSourceProvider.overrideWithValue(fake)],
    );
    addTearDown(container.dispose);

    expect(await container.read(stayPassProvider('a').future), 'rh1.fake-a');
    expect(await container.read(stayPassProvider('b').future), 'rh1.fake-b');
  });

  test('a failed issue surfaces the typed failure', () async {
    final fake = FakeStayPassSource()..issueError = const NetworkFailure();
    final container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [stayPassSourceProvider.overrideWithValue(fake)],
    );
    addTearDown(container.dispose);

    await expectLater(
      container.read(stayPassProvider('res-1').future),
      throwsA(isA<NetworkFailure>()),
    );
  });
}
```

Create `test/support/fake_stay_pass_source.dart`:

```dart
import 'package:pasala/data/models/reservation.dart';
import 'package:pasala/data/models/verified_pass.dart';
import 'package:pasala/data/repositories/stay_pass_repository.dart';

/// In-memory [StayPassSource]. [tokens] maps a reservation id to the pass
/// `issue` returns (default `'rh1.fake-<id>'`); [verified] is what
/// `verify` returns. Set an `...Error` to make that call throw, and read
/// the call logs to assert what a screen asked for.
class FakeStayPassSource implements StayPassSource {
  final Map<String, String> tokens = {};
  Object? issueError;
  VerifiedPass? verified;
  Object? verifyError;

  final List<String> issueCalls = [];
  final List<String> verifyCalls = [];

  @override
  Future<String> issue(String reservationId) async {
    issueCalls.add(reservationId);
    if (issueError != null) throw issueError!;
    return tokens[reservationId] ?? 'rh1.fake-$reservationId';
  }

  @override
  Future<VerifiedPass> verify(String token) async {
    verifyCalls.add(token);
    if (verifyError != null) throw verifyError!;
    final result = verified;
    if (result == null) {
      throw StateError('FakeStayPassSource.verified is not set');
    }
    return result;
  }
}

/// A verified pass with defaults for a confirmed two-guest booking at
/// resort `p1`; override only what a test is about.
VerifiedPass verifiedPass({
  String id = '3f2a1b9c-0000-0000-0000-000000000000',
  String propertyId = 'p1',
  String unitId = 'u1',
  String? unitName = 'Cottage 1',
  ReservationStatus status = ReservationStatus.confirmed,
  String? customerName = 'Ravi Kumar',
  String? customerPhone = '9000000001',
}) =>
    VerifiedPass(
      reservation: Reservation(
        id: id,
        unitId: unitId,
        start: DateTime.utc(2026, 9, 26, 8, 30),
        end: DateTime.utc(2026, 9, 28, 5, 30),
        kind: ReservationKind.booking,
        status: status,
        customerName: customerName,
        customerPhone: customerPhone,
        guests: 2,
      ),
      propertyId: propertyId,
      unitName: unitName,
    );
```

- [ ] **Step 8: Run them to verify they fail**

Run: `flutter test test/core/errors_test.dart test/data/verified_pass_test.dart test/data/stay_pass_provider_test.dart`
Expected: FAIL to compile. `StayPassRejected`, `PassRejection`, `verified_pass.dart` and `stay_pass_repository.dart` are not defined.

- [ ] **Step 9: Implement the Dart contract**

In `lib/core/errors.dart`, add after the `AlreadyDispatched` class:

```dart
/// Why `verify_stay_pass` refused a check-in pass (P0034).
enum PassRejection { invalid, expired, otherResort }

/// P0034 -- `verify_stay_pass` (0052_stay_pass.sql) refused a scanned or
/// typed check-in pass. The server sends one of three bare code words
/// (`pass_invalid`, `pass_expired`, `pass_other_resort`), so the copy lives
/// here; anything else reads as invalid.
class StayPassRejected extends BookingFailure {
  const StayPassRejected.invalid()
      : reason = PassRejection.invalid,
        super('This is not a valid check-in pass.');

  const StayPassRejected.expired()
      : reason = PassRejection.expired,
        super('This pass has expired. Ask the guest to reopen their booking, '
            'or find them in the list.');

  const StayPassRejected.otherResort()
      : reason = PassRejection.otherResort,
        super('This pass is for a booking at a different resort.');

  factory StayPassRejected.fromServer(String code) => switch (code) {
        'pass_expired' => const StayPassRejected.expired(),
        'pass_other_resort' => const StayPassRejected.otherResort(),
        _ => const StayPassRejected.invalid(),
      };

  final PassRejection reason;
}
```

In `mapPostgrestError`'s `switch (code)`, add after `'P0031' => const AlreadyDispatched(),`:

```dart
    // P0034: check-in passes (0052). Bare code words; see StayPassRejected.
    'P0034' => StayPassRejected.fromServer(message),
```

Create `lib/data/models/verified_pass.dart`:

```dart
import 'reservation.dart';

/// What `verify_stay_pass` returns for a genuine pass: the booking (with
/// the guest's name and phone), the resort the pass was signed for, and
/// the unit's name. The booking can be in any status -- reception sees a
/// cancelled or already checked-in booking for what it is.
class VerifiedPass {
  const VerifiedPass({
    required this.reservation,
    required this.propertyId,
    required this.unitName,
  });

  final Reservation reservation;
  final String propertyId;
  final String? unitName;

  /// The JSON is a `reservations` row plus `profiles {full_name, phone}`
  /// and `unit_name` -- the shape [Reservation.fromJson] already reads.
  factory VerifiedPass.fromJson(Map<String, dynamic> json) => VerifiedPass(
        reservation: Reservation.fromJson(json),
        propertyId: json['property_id'] as String,
        unitName: json['unit_name'] as String?,
      );
}

/// True when [text] is a check-in pass (format `rh1.`), not a booking code
/// or a name typed into reception's search. Surrounding whitespace -- a
/// paste, or a keyboard-wedge scanner's newline -- is ignored.
bool looksLikeStayPass(String text) => text.trim().startsWith('rh1.');
```

Create `lib/data/repositories/stay_pass_repository.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors.dart';
import '../../core/supabase_client.dart';
import '../models/verified_pass.dart';

/// The two calls behind signed check-in passes (0052_stay_pass.sql). The
/// guest screens and reception call through [stayPassSourceProvider];
/// tests override it with `FakeStayPassSource`
/// (test/support/fake_stay_pass_source.dart).
abstract class StayPassSource {
  /// The signed pass for the signed-in guest's own `confirmed` or
  /// `checked_in` booking (`issue_stay_pass`).
  Future<String> issue(String reservationId);

  /// Checks a scanned or typed pass (`verify_stay_pass`). Throws
  /// [StayPassRejected] for an invalid, expired or other-resort pass.
  Future<VerifiedPass> verify(String token);
}

/// Both functions check the caller server-side (the guest's own booking;
/// Staff+ at the pass's resort), so this repository checks nothing itself.
class StayPassRepository implements StayPassSource {
  StayPassRepository(this._db);
  final SupabaseClient _db;

  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } catch (e) {
      throw mapPostgrestError(e);
    }
  }

  @override
  Future<String> issue(String reservationId) => _guard(() async {
        final token = await _db.rpc(
          'issue_stay_pass',
          params: {'p_reservation': reservationId},
        );
        return token as String;
      });

  @override
  Future<VerifiedPass> verify(String token) => _guard(() async {
        final json = await _db.rpc(
          'verify_stay_pass',
          params: {'p_token': token.trim()},
        );
        return VerifiedPass.fromJson(json as Map<String, dynamic>);
      });
}

final stayPassRepositoryProvider = Provider<StayPassRepository>(
  (ref) => StayPassRepository(ref.watch(supabaseProvider)),
);

/// The [StayPassSource] seam every screen calls through.
final stayPassSourceProvider = Provider<StayPassSource>(
  (ref) => ref.watch(stayPassRepositoryProvider),
);

/// The guest's pass for one booking, keyed by reservation id. Not
/// `autoDispose`: a booking's pass never changes (it is signed over the
/// booking's ids and the end of the stay), so it is fetched once per app
/// session and survives the guest moving between screens.
final stayPassProvider = FutureProvider.family<String, String>(
  (ref, reservationId) =>
      ref.watch(stayPassSourceProvider).issue(reservationId),
);
```

- [ ] **Step 10: Run the Dart tests**

Run: `flutter test test/core/errors_test.dart test/data/verified_pass_test.dart test/data/stay_pass_provider_test.dart && flutter analyze`
Expected: PASS, with no new analyzer issues (still the 2 baseline infos).

- [ ] **Step 11: Commit**

```bash
git add supabase/migrations/0052_stay_pass.sql supabase/tests/43_stay_pass_test.sql \
  supabase/tests/37_tenancy_isolation_test.sql lib/core/errors.dart \
  lib/data/models/verified_pass.dart lib/data/repositories/stay_pass_repository.dart \
  test/support/fake_stay_pass_source.dart test/core/errors_test.dart \
  test/data/verified_pass_test.dart test/data/stay_pass_provider_test.dart
git commit -m "feat(stay-pass): contract for signed check-in passes

Private secret table and seed, issue/verify stubs with grants and the
definer allow-list, P0034 mapping, VerifiedPass and the StayPassSource
seam with its fake.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Phase 1: Database track (Tasks 2 → 3, sequential)

### Task 2: `issue_stay_pass` and the pass format

**Track:** DB. **Depends on:** Task 1.

**Files:**
- Modify: `supabase/migrations/0052_stay_pass.sql` (add the private helpers after the secret seed; replace the `issue_stay_pass` stub)
- Modify: `supabase/tests/43_stay_pass_test.sql` (Section 2; `plan(15)` → `plan(35)`)

**Interfaces:**
- Consumes: `private.stay_pass_secret` and the `issue_stay_pass` signature (Task 1).
- Produces:
  - `private.b64url_encode(bytea) returns text`
  - `private.b64url_decode(text) returns bytea`
  - `private.stay_pass_mac(p_body bytea) returns bytea` (16 bytes)
  - `private.stay_pass_token(p_reservation uuid, p_property uuid, p_expires bigint) returns text`
  - the real `issue_stay_pass`
  - the settings `test.tok_r1`, `test.tok_in`, `test.tok_past` and `test.tok_s1`, which Section 3 reads

- [ ] **Step 1: Write the failing tests**

In `supabase/tests/43_stay_pass_test.sql`, change `select plan(15);` to `select plan(35);`, and insert this section before `select * from finish();`:

```sql
-- ---------------------------------------------------------------------
-- Section 2: issue_stay_pass and the pass format (Task 2)

-- base64url helpers, as the superuser (private is unreachable otherwise).
-- \xfbff is '+/8=' in plain base64.
select is(private.b64url_encode('\xfbff'::bytea), '-_8',
  'b64url uses - and _ and drops the padding');
select is(private.b64url_decode(private.b64url_encode('\x00ff10abcdef'::bytea)),
  '\x00ff10abcdef'::bytea, 'b64url round-trips');

-- Gita, the guest.
set local role authenticated;
set local request.jwt.claims to '{"sub":"f3000000-0000-0000-0000-000000000006","role":"authenticated"}';
select ok(set_config('test.tok_r1',
  public.issue_stay_pass('f3f3f3f3-0000-4000-8000-000000000021'), true)
  ~ '^rh1\.[A-Za-z0-9_-]{75}$',
  'the guest gets a well-formed pass for a confirmed booking');
select is(public.issue_stay_pass('f3f3f3f3-0000-4000-8000-000000000021'),
  current_setting('test.tok_r1'), 'issuing again gives the same pass');
select ok(set_config('test.tok_in',
  public.issue_stay_pass('f3f3f3f3-0000-4000-8000-000000000022'), true) ~ '^rh1\.',
  'a checked-in booking has a pass too');
select ok(set_config('test.tok_past',
  public.issue_stay_pass('f3f3f3f3-0000-4000-8000-000000000025'), true) ~ '^rh1\.',
  'a confirmed booking whose stay has ended still gets its (expired) pass');
select throws_ok($$select public.issue_stay_pass('f3f3f3f3-0000-4000-8000-000000000023')$$,
  'P0009', 'reservation is cancelled', 'no pass for a cancelled booking');
select throws_ok($$select public.issue_stay_pass('f3f3f3f3-0000-4000-8000-000000000024')$$,
  'P0009', 'reservation is checked_out', 'no pass after checkout');
select throws_ok($$select public.issue_stay_pass('f3f3f3f3-0000-4000-8000-000000000026')$$,
  'P0002', 'reservation not found', 'no pass for another guest''s booking');
select throws_ok($$select public.issue_stay_pass('f3f3f3f3-0000-4000-8000-0000000000ff')$$,
  'P0002', 'reservation not found', 'no pass for an unknown booking');

-- Hari, the other guest: his pass is used by Section 3.
set local request.jwt.claims to '{"sub":"f3000000-0000-0000-0000-000000000007","role":"authenticated"}';
select ok(set_config('test.tok_s1',
  public.issue_stay_pass('f3f3f3f3-0000-4000-8000-000000000026'), true) ~ '^rh1\.',
  'the other guest gets a pass for their own booking');

-- Staff do not mint passes, and cannot reach the helpers.
set local request.jwt.claims to '{"sub":"f3000000-0000-0000-0000-000000000003","role":"authenticated"}';
select throws_ok($$select public.issue_stay_pass('f3f3f3f3-0000-4000-8000-000000000021')$$,
  'P0002', 'reservation not found', 'resort staff cannot mint a guest''s pass');
select throws_ok($$select private.stay_pass_token('f3f3f3f3-0000-4000-8000-000000000021',
  'f3f3f3f3-0000-4000-8000-000000000001', 4102444800)$$,
  '42501', null, 'authenticated cannot call the private helpers');

set local request.jwt.claims to '{"role":"authenticated"}';
select throws_ok($$select public.issue_stay_pass('f3f3f3f3-0000-4000-8000-000000000021')$$,
  'P0008', 'authentication required', 'a caller with no user id is refused');

reset role;
set local role anon;
set local request.jwt.claims to '{"role":"anon"}';
select throws_ok($$select public.issue_stay_pass('f3f3f3f3-0000-4000-8000-000000000021')$$,
  '42501', null, 'anon cannot call issue_stay_pass');

-- What the pass carries, decoded as the superuser.
reset role;
select is(encode(substring(private.b64url_decode(substr(current_setting('test.tok_r1'), 5))
                           from 1 for 16), 'hex')::uuid,
  'f3f3f3f3-0000-4000-8000-000000000021'::uuid, 'the pass carries the reservation id');
select is(encode(substring(private.b64url_decode(substr(current_setting('test.tok_r1'), 5))
                           from 17 for 16), 'hex')::uuid,
  'f3f3f3f3-0000-4000-8000-000000000001'::uuid, 'the pass carries the resort id');
select is(('x' || encode(substring(private.b64url_decode(substr(current_setting('test.tok_r1'), 5))
                                   from 33 for 8), 'hex'))::bit(64)::bigint,
  (select extract(epoch from upper(period))::bigint from public.reservations
    where id = 'f3f3f3f3-0000-4000-8000-000000000021'),
  'the pass expires when the stay ends');
select is(substring(private.b64url_decode(substr(current_setting('test.tok_r1'), 5)) from 41 for 16),
  private.stay_pass_mac(substring(private.b64url_decode(substr(current_setting('test.tok_r1'), 5))
                                  from 1 for 40)),
  'the tag is the HMAC of the body');
select is(current_setting('test.tok_r1'),
  private.stay_pass_token('f3f3f3f3-0000-4000-8000-000000000021',
    'f3f3f3f3-0000-4000-8000-000000000001',
    (select extract(epoch from upper(period))::bigint from public.reservations
      where id = 'f3f3f3f3-0000-4000-8000-000000000021')),
  'stay_pass_token builds the same pass');
```

- [ ] **Step 2: Run it to verify it fails**

Run: `supabase test db supabase/tests/43_stay_pass_test.sql`
Expected: FAIL. The first Section 2 statement errors with `function private.b64url_encode(bytea) does not exist`.

- [ ] **Step 3: Add the helpers and the real `issue_stay_pass`**

In `supabase/migrations/0052_stay_pass.sql`, insert this block right after the `insert into private.stay_pass_secret ... on conflict (id) do nothing;` statement:

```sql
-- ---------------------------------------------------------------------
-- Private helpers. Not security definer: they run with the rights of the
-- definer functions that call them, and nobody else can reach `private`.

-- base64url without padding (RFC 4648 section 5). encode() wraps its
-- output every 76 characters, so the newlines are dropped too.
create function private.b64url_encode(p_bytes bytea)
returns text
language sql
immutable
strict
set search_path = pg_catalog, pg_temp
as $$
  select rtrim(translate(encode(p_bytes, 'base64'), E'+/\n', '-_'), '=');
$$;

create function private.b64url_decode(p_text text)
returns bytea
language sql
immutable
strict
set search_path = pg_catalog, pg_temp
as $$
  select decode(rpad(translate(p_text, '-_', '+/'),
                     ((length(p_text) + 3) / 4) * 4, '='),
                'base64');
$$;

-- The pass tag: HMAC-SHA256 under the deployment secret over the version
-- prefix and the 40-byte body, cut to 16 bytes.
create function private.stay_pass_mac(p_body bytea)
returns bytea
language sql
stable
strict
set search_path = pg_catalog, pg_temp
as $$
  select substring(extensions.hmac(convert_to('rh1.', 'UTF8') || p_body,
                                   s.secret, 'sha256')
                   from 1 for 16)
    from private.stay_pass_secret s
   where s.id;
$$;

create function private.stay_pass_token(
  p_reservation uuid,
  p_property    uuid,
  p_expires     bigint
) returns text
language sql
stable
strict
set search_path = pg_catalog, pg_temp
as $$
  with body as (
    select decode(replace(p_reservation::text, '-', ''), 'hex')
        || decode(replace(p_property::text, '-', ''), 'hex')
        || int8send(p_expires) as b
  )
  select 'rh1.' || private.b64url_encode(b || private.stay_pass_mac(b))
    from body;
$$;

revoke all on all functions in schema private from public, anon, authenticated;
```

Replace the whole `issue_stay_pass` stub (from `-- Stub: Task 2 replaces the body.` through its closing `$$;`) with:

```sql
-- The signed check-in pass for the caller's own booking. The same booking
-- always gets the same pass, valid until the stay ends (spec decision 9).
-- Anyone else's booking, an unknown id or a non-booking row is simply "not
-- found", so the function never reveals which ids exist.
create function public.issue_stay_pass(p_reservation uuid)
returns text
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_row public.reservations;
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode = 'P0008';
  end if;

  select * into v_row from public.reservations
   where id = p_reservation
     and customer_id = v_uid
     and kind = 'booking';
  if not found then
    raise exception 'reservation not found' using errcode = 'P0002';
  end if;

  if v_row.status not in ('confirmed', 'checked_in') then
    raise exception 'reservation is %', v_row.status using errcode = 'P0009';
  end if;

  return private.stay_pass_token(
    v_row.id, v_row.property_id,
    extract(epoch from upper(v_row.period))::bigint);
end;
$$;
```

- [ ] **Step 4: Run the tests**

Run: `supabase db reset && supabase test db supabase/tests/43_stay_pass_test.sql supabase/tests/37_tenancy_isolation_test.sql`
Expected: PASS, 43 at 35/35 and 37 at 77/77.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/0052_stay_pass.sql supabase/tests/43_stay_pass_test.sql
git commit -m "feat(stay-pass): issue signed check-in passes

issue_stay_pass signs reservation id, resort id and end-of-stay expiry
with HMAC-SHA256 under the private per-deployment secret, for the
caller's own confirmed or checked-in booking only.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 3: `verify_stay_pass`

**Track:** DB. **Depends on:** Task 2.

**Files:**
- Modify: `supabase/migrations/0052_stay_pass.sql` (replace the `verify_stay_pass` stub)
- Modify: `supabase/tests/43_stay_pass_test.sql` (Section 3; `plan(35)` → `plan(65)`)

**Interfaces:**
- Consumes: `private.b64url_decode`, `private.stay_pass_mac`, `private.stay_pass_token`, `public.has_resort_role` and the Section 2 settings.
- Produces: the real `verify_stay_pass(p_token text) returns jsonb`. It returns every `reservations` column, plus `profiles: {full_name, phone}` and `unit_name`, or raises P0034 with `pass_invalid | pass_other_resort | pass_expired`, checked in that order (signature, then resort, then expiry, then whether the booking exists).

- [ ] **Step 1: Write the failing tests**

Change `select plan(35);` to `select plan(65);`, and insert this section before `select * from finish();`:

```sql
-- ---------------------------------------------------------------------
-- Section 3: verify_stay_pass (Task 3)

-- Passes minted as the superuser: expired, swapped to resort S (correctly
-- signed, so only the resort check can catch it), and for the cancelled
-- booking.
reset role;
select set_config('test.tok_expired', private.stay_pass_token(
  'f3f3f3f3-0000-4000-8000-000000000021', 'f3f3f3f3-0000-4000-8000-000000000001',
  extract(epoch from now())::bigint - 1), true);
select set_config('test.tok_swap', private.stay_pass_token(
  'f3f3f3f3-0000-4000-8000-000000000021', 'f3f3f3f3-0000-4000-8000-000000000002',
  extract(epoch from now())::bigint + 86400), true);
select set_config('test.tok_cancel', private.stay_pass_token(
  'f3f3f3f3-0000-4000-8000-000000000023', 'f3f3f3f3-0000-4000-8000-000000000001',
  extract(epoch from now())::bigint + 86400), true);

-- R's staff member at the desk.
set local role authenticated;
set local request.jwt.claims to '{"sub":"f3000000-0000-0000-0000-000000000003","role":"authenticated"}';
select is(public.verify_stay_pass(current_setting('test.tok_r1')) ->> 'id',
  'f3f3f3f3-0000-4000-8000-000000000021', 'R staff: the pass opens its booking');
select is(public.verify_stay_pass(current_setting('test.tok_r1')) ->> 'property_id',
  'f3f3f3f3-0000-4000-8000-000000000001', 'the booking''s resort is returned');
select is(public.verify_stay_pass(current_setting('test.tok_r1')) ->> 'unit_name',
  'Cottage 1', 'the unit name is returned');
select is(public.verify_stay_pass(current_setting('test.tok_r1')) -> 'profiles' ->> 'full_name',
  'Gita Guest', 'the guest''s name is returned');
select is(public.verify_stay_pass(current_setting('test.tok_r1')) ->> 'status',
  'confirmed', 'the booking''s status is returned');
select is(public.verify_stay_pass(current_setting('test.tok_in')) ->> 'status',
  'checked_in', 'a checked-in booking verifies, with its status');
select throws_ok($$select public.verify_stay_pass(current_setting('test.tok_past'))$$,
  'P0034', 'pass_expired', 'a pass whose stay has ended is expired');
select throws_ok($$select public.verify_stay_pass(current_setting('test.tok_expired'))$$,
  'P0034', 'pass_expired', 'a pass one second past its expiry is expired');
select is(public.verify_stay_pass(current_setting('test.tok_cancel')) ->> 'status',
  'cancelled', 'a cancelled booking verifies and shows as cancelled');
select throws_ok($$select public.verify_stay_pass(current_setting('test.tok_s1'))$$,
  'P0034', 'pass_other_resort', 'a pass for resort S is another resort''s');
select throws_ok($$select public.verify_stay_pass(current_setting('test.tok_swap'))$$,
  'P0034', 'pass_other_resort', 'a pass re-signed for resort S is another resort''s');
select throws_ok($$select public.verify_stay_pass(
    'rh1.' || case when substr(current_setting('test.tok_r1'), 5, 1) = 'A' then 'B' else 'A' end
           || substr(current_setting('test.tok_r1'), 6))$$,
  'P0034', 'pass_invalid', 'a pass with one character changed is invalid');
select throws_ok($$select public.verify_stay_pass('hello')$$,
  'P0034', 'pass_invalid', 'any other QR text is invalid');
select throws_ok($$select public.verify_stay_pass('f3f3f3f3-0000-4000-8000-000000000021')$$,
  'P0034', 'pass_invalid', 'an old bare-UUID QR is invalid');
select throws_ok($$select public.verify_stay_pass(null)$$,
  'P0034', 'pass_invalid', 'no pass is invalid');
select throws_ok($$select public.verify_stay_pass('rh1.' || repeat('A', 75))$$,
  'P0034', 'pass_invalid', 'a well-formed but unsigned pass is invalid');
select throws_ok($$select public.verify_stay_pass('rh1.' || repeat('!', 75))$$,
  'P0034', 'pass_invalid', 'a pass with characters outside base64url is invalid');

-- Every Staff+ role at R.
set local request.jwt.claims to '{"sub":"f3000000-0000-0000-0000-000000000001","role":"authenticated"}';
select is(public.verify_stay_pass(current_setting('test.tok_r1')) ->> 'id',
  'f3f3f3f3-0000-4000-8000-000000000021', 'R owner verifies');
set local request.jwt.claims to '{"sub":"f3000000-0000-0000-0000-000000000002","role":"authenticated"}';
select is(public.verify_stay_pass(current_setting('test.tok_r1')) ->> 'id',
  'f3f3f3f3-0000-4000-8000-000000000021', 'R admin verifies');
set local request.jwt.claims to '{"sub":"f3000000-0000-0000-0000-000000000004","role":"authenticated"}';
select is(public.verify_stay_pass(current_setting('test.tok_r1')) ->> 'id',
  'f3f3f3f3-0000-4000-8000-000000000021', 'R accountant verifies');

-- S's staff member.
set local request.jwt.claims to '{"sub":"f3000000-0000-0000-0000-000000000005","role":"authenticated"}';
select throws_ok($$select public.verify_stay_pass(current_setting('test.tok_r1'))$$,
  'P0034', 'pass_other_resort', 'S staff: an R pass is another resort''s');
select throws_ok($$select public.verify_stay_pass(current_setting('test.tok_expired'))$$,
  'P0034', 'pass_other_resort', 'S staff learn nothing about an R pass''s expiry');
select throws_ok($$select public.verify_stay_pass(current_setting('test.tok_swap'))$$,
  'P0034', 'pass_invalid', 'S staff: a pass naming S for an R booking is invalid');
select is(public.verify_stay_pass(current_setting('test.tok_s1')) ->> 'id',
  'f3f3f3f3-0000-4000-8000-000000000026', 'S staff verify their own guest''s pass');

-- Not staff at all.
set local request.jwt.claims to '{"sub":"f3000000-0000-0000-0000-000000000006","role":"authenticated"}';
select throws_ok($$select public.verify_stay_pass(current_setting('test.tok_r1'))$$,
  'P0034', 'pass_other_resort', 'the guest cannot verify their own pass');
set local request.jwt.claims to '{"sub":"f3000000-0000-0000-0000-000000000008","role":"authenticated"}';
select throws_ok($$select public.verify_stay_pass(current_setting('test.tok_r1'))$$,
  'P0034', 'pass_other_resort', 'an outsider cannot verify a pass');
reset role;
set local role anon;
set local request.jwt.claims to '{"role":"anon"}';
select throws_ok($$select public.verify_stay_pass('rh1.x')$$,
  '42501', null, 'anon cannot call verify_stay_pass');

-- Suspended resort: verifying is a read and still works.
reset role;
set local request.jwt.claims to '';
update public.properties set status = 'suspended'
 where id = 'f3f3f3f3-0000-4000-8000-000000000001';
set local role authenticated;
set local request.jwt.claims to '{"sub":"f3000000-0000-0000-0000-000000000003","role":"authenticated"}';
select is(public.verify_stay_pass(current_setting('test.tok_r1')) ->> 'id',
  'f3f3f3f3-0000-4000-8000-000000000021', 'a suspended resort''s staff can still verify');

-- Archived resort: no access at all.
reset role;
set local request.jwt.claims to '';
update public.properties set status = 'archived'
 where id = 'f3f3f3f3-0000-4000-8000-000000000001';
set local role authenticated;
set local request.jwt.claims to '{"sub":"f3000000-0000-0000-0000-000000000003","role":"authenticated"}';
select throws_ok($$select public.verify_stay_pass(current_setting('test.tok_r1'))$$,
  'P0034', 'pass_other_resort', 'an archived resort''s staff cannot verify');
reset role;
set local request.jwt.claims to '';
update public.properties set status = 'active'
 where id = 'f3f3f3f3-0000-4000-8000-000000000001';

-- Rotating the secret invalidates every earlier pass.
update private.stay_pass_secret set secret = extensions.gen_random_bytes(32);
set local role authenticated;
set local request.jwt.claims to '{"sub":"f3000000-0000-0000-0000-000000000003","role":"authenticated"}';
select throws_ok($$select public.verify_stay_pass(current_setting('test.tok_r1'))$$,
  'P0034', 'pass_invalid', 'after a rotation the old pass is invalid');
reset role;
```

- [ ] **Step 2: Run it to verify it fails**

Run: `supabase test db supabase/tests/43_stay_pass_test.sql`
Expected: FAIL. The first `verify_stay_pass` call errors with `verify_stay_pass not implemented` (SQLSTATE 0A000).

- [ ] **Step 3: Implement `verify_stay_pass`**

In `supabase/migrations/0052_stay_pass.sql`, replace the whole `verify_stay_pass` stub (from `-- Stub: Task 3 replaces the body.` through its closing `$$;`) with:

```sql
-- Checks a scanned or typed pass at the front desk. The order is
-- deliberate (spec decision 11): format and signature, then the caller's
-- Staff+ role at the resort the pass names (so another resort's staff
-- learn nothing more), then expiry, then that the booking still exists at
-- that resort. The booking is returned in any status; check_in_booking
-- stays the only thing that changes it.
create function public.verify_stay_pass(p_token text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_raw     bytea;
  v_body    bytea;
  v_res_id  uuid;
  v_prop    uuid;
  v_expires bigint;
  v_row     public.reservations;
begin
  -- 'rh1.' and exactly 75 base64url characters (56 bytes). Anything else
  -- -- an old bare-UUID QR, a Wi-Fi code -- is not a pass, and decode()
  -- never sees it.
  if p_token is null or p_token !~ '^rh1\.[A-Za-z0-9_-]{75}$' then
    raise exception using errcode = 'P0034', message = 'pass_invalid';
  end if;

  v_raw  := private.b64url_decode(substr(p_token, 5));
  v_body := substring(v_raw from 1 for 40);
  if length(v_raw) <> 56
     or substring(v_raw from 41 for 16) <> private.stay_pass_mac(v_body) then
    raise exception using errcode = 'P0034', message = 'pass_invalid';
  end if;

  v_res_id  := encode(substring(v_body from 1 for 16), 'hex')::uuid;
  v_prop    := encode(substring(v_body from 17 for 16), 'hex')::uuid;
  v_expires := ('x' || encode(substring(v_body from 33 for 8), 'hex'))::bit(64)::bigint;

  if not public.has_resort_role(v_prop, false, 'owner','admin','staff','accountant') then
    raise exception using errcode = 'P0034', message = 'pass_other_resort';
  end if;

  if v_expires < extract(epoch from now()) then
    raise exception using errcode = 'P0034', message = 'pass_expired';
  end if;

  select * into v_row from public.reservations
   where id = v_res_id
     and property_id = v_prop
     and kind = 'booking';
  if not found then
    raise exception using errcode = 'P0034', message = 'pass_invalid';
  end if;

  return to_jsonb(v_row) || jsonb_build_object(
    'profiles', (select jsonb_build_object('full_name', p.full_name, 'phone', p.phone)
                   from public.profiles p
                  where p.id = v_row.customer_id),
    'unit_name', (select u.name from public.units u where u.id = v_row.unit_id));
end;
$$;
```

- [ ] **Step 4: Run the tests**

Run: `supabase db reset && supabase test db supabase/tests/43_stay_pass_test.sql supabase/tests/37_tenancy_isolation_test.sql`
Expected: PASS, 43 at 65/65 and 37 at 77/77.

- [ ] **Step 5: Run the whole pgTAP suite**

Run: `supabase test db 2>&1 | tail -20`
Expected: every file passes except the known IST-midnight failures recorded in Task 1 Step 1.

- [ ] **Step 6: Commit**

```bash
git add supabase/migrations/0052_stay_pass.sql supabase/tests/43_stay_pass_test.sql
git commit -m "feat(stay-pass): verify check-in passes at the desk

verify_stay_pass checks the HMAC, Staff+ at the resort the pass names,
the expiry and that the booking belongs to that resort; P0034
pass_invalid / pass_other_resort / pass_expired otherwise.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Phase 2: App track (after Task 1; Tasks 4, 5 and 6 independent)

### Task 4: The guest's pass QR

**Track:** App. **Depends on:** Task 1.

**Files:**
- Create: `lib/features/stay/stay_pass_qr.dart`
- Modify: `lib/features/booking/confirmation_screen.dart` (the QR `Container` around lines 122–137, and the `qr_flutter` import)
- Modify: `lib/features/account/booking_detail_screen.dart` (the QR `Container` around lines 231–243, and the `qr_flutter` import)
- Modify: `lib/features/stay/my_stay_screen.dart` (the 64-px QR `Container` around lines 172–179, and the `qr_flutter` import)
- Create: `test/features/stay/stay_pass_qr_test.dart`
- Modify: `test/features/booking/confirmation_screen_test.dart`, `test/features/account/booking_detail_screen_test.dart`, `test/features/stay/my_stay_screen_test.dart`

**Interfaces:**
- Consumes: `stayPassProvider`, `stayPassSourceProvider` (Task 1), `FakeStayPassSource` (Task 1), and `bookingCode(String)` from `lib/features/admin/admin_bookings_screen.dart`.
- Produces:
  - `StayPassQr({required String reservationId, double size = 140, bool compact = false})`
  - `StayPassThumbnail({required String reservationId})`, keyed `stay-pass-thumbnail`
  - `Future<void> showStayPassDialog(BuildContext, String reservationId)`
  - the keys `stay-pass-qr` and `stay-pass-retry`

- [ ] **Step 1: Write the failing widget tests**

Create `test/features/stay/stay_pass_qr_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/errors.dart';
import 'package:pasala/data/repositories/stay_pass_repository.dart';
import 'package:pasala/features/stay/stay_pass_qr.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../support/fake_stay_pass_source.dart';

const _id = '3f2a1b9c-0000-0000-0000-000000000000';

Widget _host(FakeStayPassSource passes, Widget child) => ProviderScope(
      retry: (_, _) => null,
      overrides: [stayPassSourceProvider.overrideWithValue(passes)],
      child: MaterialApp(home: Scaffold(body: Center(child: child))),
    );

void main() {
  testWidgets('shows the pass as a QR with the booking code under it',
      (tester) async {
    final passes = FakeStayPassSource();
    await tester.pumpWidget(_host(passes, const StayPassQr(reservationId: _id)));
    await tester.pumpAndSettle();

    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.byKey(const Key('stay-pass-qr')), findsOneWidget);
    expect(find.text('Booking code PR3F2A'), findsOneWidget);
    expect(passes.issueCalls, [_id]);
  });

  // Review Focus 4: offline, or a booking not confirmed yet.
  testWidgets('a pass that fails to load shows the booking code and retries',
      (tester) async {
    final passes = FakeStayPassSource()..issueError = const NetworkFailure();
    await tester.pumpWidget(_host(passes, const StayPassQr(reservationId: _id)));
    await tester.pumpAndSettle();

    expect(find.byType(QrImageView), findsNothing);
    expect(find.text("Couldn't load your pass. Show the booking code at the desk."),
        findsOneWidget);
    expect(find.text('Booking code PR3F2A'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    passes.issueError = null;
    await tester.tap(find.byKey(const Key('stay-pass-retry')));
    await tester.pumpAndSettle();

    expect(find.byType(QrImageView), findsOneWidget);
    expect(passes.issueCalls, [_id, _id]);
  });

  testWidgets('the compact form shows only the QR', (tester) async {
    await tester.pumpWidget(_host(FakeStayPassSource(),
        const StayPassQr(reservationId: _id, size: 64, compact: true)));
    await tester.pumpAndSettle();

    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.textContaining('Booking code'), findsNothing);
  });

  testWidgets('the thumbnail opens the pass full size, and Close closes it',
      (tester) async {
    await tester.pumpWidget(
        _host(FakeStayPassSource(), const StayPassThumbnail(reservationId: _id)));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('stay-pass-thumbnail')));
    await tester.pumpAndSettle();

    expect(find.text('Check-in pass'), findsOneWidget);
    expect(find.byType(QrImageView), findsNWidgets(2));
    expect(find.text('Booking code PR3F2A'), findsOneWidget);

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Check-in pass'), findsNothing);
  });
}
```

In `test/features/booking/confirmation_screen_test.dart`:
- Add the imports `package:pasala/data/repositories/stay_pass_repository.dart`, `package:pasala/features/admin/admin_bookings_screen.dart' show bookingCode`, `package:qr_flutter/qr_flutter.dart` and `'../../support/fake_stay_pass_source.dart'`.
- Change `Widget _appFor({Reservation? reservation})` to `Widget _appFor({Reservation? reservation, FakeStayPassSource? passes})`, and add `stayPassSourceProvider.overrideWithValue(passes ?? FakeStayPassSource()),` as the first entry of its `overrides:` list.
- Append this test inside `main()`:

```dart
  testWidgets('shows the signed check-in pass and the booking code',
      (tester) async {
    final passes = FakeStayPassSource();
    await tester.pumpWidget(_appFor(passes: passes));
    await tester.pumpAndSettle();

    expect(find.byType(QrImageView), findsOneWidget);
    expect(passes.issueCalls, everyElement('r1'));
    expect(find.text('Booking code ${bookingCode('r1')}'), findsOneWidget);
    expect(find.text('Show this at check-in'), findsOneWidget);
  });
```

In `test/features/account/booking_detail_screen_test.dart`:
- Add the imports `package:pasala/data/repositories/stay_pass_repository.dart`, `package:pasala/features/admin/admin_bookings_screen.dart' show bookingCode`, `package:qr_flutter/qr_flutter.dart` and `'../../support/fake_stay_pass_source.dart'`.
- Add the top-level `final _passes = FakeStayPassSource();` above `void main()`.
- Add `stayPassSourceProvider.overrideWithValue(_passes),` as the first entry of the `overrides:` list of **both** `ProviderScope(` sites. Find them with `grep -n "ProviderScope(" test/features/account/booking_detail_screen_test.dart`; they are the `app(...)` helper at about line 242 and `deepLinkedApp` at about line 636.
- Add this test right after the `'shows the stored quote breakdown, not a recomputed one'` test:

```dart
  testWidgets('the Check-in QR card shows the signed pass and booking code',
      (tester) async {
    final reservation = _reservation(status: ReservationStatus.confirmed);
    await openDetail(tester, reservation, _FakeCancelActions());

    expect(find.text('Check-in QR'), findsOneWidget);
    expect(find.byType(QrImageView), findsOneWidget);
    expect(_passes.issueCalls, contains('r1'));
    expect(find.text('Booking code ${bookingCode('r1')}'), findsOneWidget);
  });
```

In `test/features/stay/my_stay_screen_test.dart`:
- Add the imports `package:pasala/data/repositories/stay_pass_repository.dart`, `package:pasala/features/admin/admin_bookings_screen.dart' show bookingCode` and `'../../support/fake_stay_pass_source.dart'`.
- Add the `FakeStayPassSource? passes` parameter to `_app({...})`, and add `stayPassSourceProvider.overrideWithValue(passes ?? FakeStayPassSource()),` as the first entry of its `overrides:` list.
- Add the fixture below `_checkedOut`:

```dart
final _confirmed = Reservation(
  id: 'res-2',
  unitId: 'u1',
  start: DateTime(2026, 9, 26),
  end: DateTime(2026, 9, 28),
  kind: ReservationKind.booking,
  status: ReservationStatus.confirmed,
);
```

- Append inside `main()`:

```dart
  testWidgets('the hub shows the check-in pass, and a tap opens it full size',
      (tester) async {
    final passes = FakeStayPassSource();
    await tester.pumpWidget(_app(currentStay: _confirmed, passes: passes));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('stay-pass-thumbnail')), findsOneWidget);
    await tester.tap(find.byKey(const Key('stay-pass-thumbnail')));
    await tester.pumpAndSettle();

    expect(find.text('Check-in pass'), findsOneWidget);
    expect(find.text('Booking code ${bookingCode('res-2')}'), findsOneWidget);
    expect(passes.issueCalls, everyElement('res-2'));
  });
```

- [ ] **Step 2: Run them to verify they fail**

Run: `flutter test test/features/stay/stay_pass_qr_test.dart test/features/booking/confirmation_screen_test.dart test/features/account/booking_detail_screen_test.dart test/features/stay/my_stay_screen_test.dart`
Expected: FAIL. `stay_pass_qr.dart` does not exist, so the files do not compile.

- [ ] **Step 3: Write `StayPassQr`**

Create `lib/features/stay/stay_pass_qr.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/theme/tokens.dart';
import '../../data/repositories/stay_pass_repository.dart';
import '../admin/admin_bookings_screen.dart' show bookingCode;

/// The guest's signed check-in pass (P3) as a QR code that reception
/// scans, with the booking code underneath for reception to type when the
/// camera cannot read it. If the pass cannot be loaded (offline, or the
/// booking is not confirmed yet) the box shows a retry button and the
/// booking code still shows. [compact] draws only the QR box, for a small
/// thumbnail.
class StayPassQr extends ConsumerWidget {
  const StayPassQr({
    super.key,
    required this.reservationId,
    this.size = 140,
    this.compact = false,
  });

  final String reservationId;
  final double size;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pass = ref.watch(stayPassProvider(reservationId));
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    final box = Container(
      padding: EdgeInsets.all(compact ? Spacing.xs : Spacing.sm),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(PasalaTokens.radiusSm),
      ),
      child: SizedBox.square(
        dimension: size,
        child: pass.when(
          data: (token) => QrImageView(
            key: const Key('stay-pass-qr'),
            data: token,
            size: size,
            padding: EdgeInsets.zero,
            backgroundColor: Colors.white,
            semanticsLabel: 'Check-in pass QR code',
          ),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => Center(
            child: IconButton(
              key: const Key('stay-pass-retry'),
              tooltip: 'Try again',
              icon: const Icon(Icons.refresh, color: Colors.black54),
              onPressed: () => ref.invalidate(stayPassProvider(reservationId)),
            ),
          ),
        ),
      ),
    );
    if (compact) return box;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        box,
        if (pass.hasError && !pass.isLoading) ...[
          const SizedBox(height: Spacing.xs),
          Text(
            "Couldn't load your pass. Show the booking code at the desk.",
            textAlign: TextAlign.center,
            style: textTheme.bodySmall?.copyWith(color: scheme.error),
          ),
        ],
        const SizedBox(height: Spacing.xs),
        Text(
          'Booking code ${bookingCode(reservationId)}',
          style: textTheme.labelLarge,
        ),
      ],
    );
  }
}

/// My Stay's small pass. At 64 px the QR is too dense to scan, so a tap
/// opens it full size ([showStayPassDialog]).
class StayPassThumbnail extends StatelessWidget {
  const StayPassThumbnail({super.key, required this.reservationId});

  final String reservationId;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: 'Show check-in pass',
        child: InkWell(
          key: const Key('stay-pass-thumbnail'),
          borderRadius: BorderRadius.circular(PasalaTokens.radiusSm),
          onTap: () => showStayPassDialog(context, reservationId),
          child: StayPassQr(
            reservationId: reservationId,
            size: 64,
            compact: true,
          ),
        ),
      );
}

/// The pass full size in a dialog (200 px fits a 360-px-wide phone). The
/// dialog closes itself with its own context.
Future<void> showStayPassDialog(BuildContext context, String reservationId) =>
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Check-in pass'),
        content: StayPassQr(reservationId: reservationId, size: 200),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
```

- [ ] **Step 4: Use it on the three guest screens**

In `lib/features/booking/confirmation_screen.dart`:
- Delete the import `package:qr_flutter/qr_flutter.dart`.
- Add `import '../stay/stay_pass_qr.dart';`.
- Replace the block from the comment `// Decorative only -- reception looks up the booking and` through the `Container(...)` holding `QrImageView` (it ends just before `const SizedBox(height: Spacing.xs),` / `Text('Show this at check-in', ...)`) with:

```dart
                      // The signed check-in pass reception scans (P3).
                      StayPassQr(reservationId: reservation.id),
```

In `lib/features/account/booking_detail_screen.dart`:
- Delete the import `package:qr_flutter/qr_flutter.dart`.
- Add `import '../stay/stay_pass_qr.dart';`.
- Inside the `Check-in QR` card, replace the `Container(` whose child is `QrImageView(data: reservation.id, size: 140, backgroundColor: Colors.white)` (the whole `Container(...)` expression, up to and including its closing `),`) with:

```dart
                StayPassQr(reservationId: reservation.id),
```

In `lib/features/stay/my_stay_screen.dart`:
- Delete the import `package:qr_flutter/qr_flutter.dart`.
- Add `import 'stay_pass_qr.dart';`.
- Replace the trailing `Container(` in the stay card's `Row`, whose child is `QrImageView(data: reservation.id, size: 64)` (the whole `Container(...)` expression, up to and including its closing `),`), with:

```dart
                StayPassThumbnail(reservationId: reservation.id),
```

- [ ] **Step 5: Run the tests**

Run: `flutter test test/features/stay/stay_pass_qr_test.dart test/features/booking/confirmation_screen_test.dart test/features/account/booking_detail_screen_test.dart test/features/stay/my_stay_screen_test.dart && flutter analyze`
Expected: PASS. No `QrImageView(data: reservation.id` remains (`grep -rn "QrImageView(data: reservation.id\|data: reservation.id," lib/features` prints nothing), and there are no new analyzer issues.

- [ ] **Step 6: Commit**

```bash
git add lib/features/stay/stay_pass_qr.dart lib/features/booking/confirmation_screen.dart \
  lib/features/account/booking_detail_screen.dart lib/features/stay/my_stay_screen.dart \
  test/features/stay/stay_pass_qr_test.dart test/features/booking/confirmation_screen_test.dart \
  test/features/account/booking_detail_screen_test.dart test/features/stay/my_stay_screen_test.dart
git commit -m "feat(stay-pass): guests show the signed pass as their check-in QR

StayPassQr replaces the bare reservation-id QR on the confirmation,
booking detail and My Stay screens, with the booking code underneath,
a retry when the pass cannot load, and a full-size dialog from My Stay.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 5: The scanner screen and its route

**Track:** App. **Depends on:** Task 1 (only for the branch point; it uses no Task 1 API).

**Files:**
- Modify: `pubspec.yaml` (next to `qr_flutter`, around lines 54–56), `pubspec.lock` (via `flutter pub get`)
- Modify: `ios/Runner/Info.plist` (after `NSLocationWhenInUseUsageDescription`, around line 49)
- Create: `lib/features/admin/scan_pass_screen.dart`
- Modify: `lib/core/router.dart` (`redirectFor`'s `staffOrAboveOk`, around lines 147–153; the `/admin/check-in` GoRoute, around lines 624–627; the imports)
- Create: `test/features/admin/scan_pass_screen_test.dart`
- Modify: `test/core/router_test.dart`

**Interfaces:**
- Consumes: `mobile_scanner` 7.4 (`MobileScanner`, `MobileScannerController`, `BarcodeFormat.qrCode`, `DetectionSpeed.noDuplicates`, `BarcodeCapture.barcodes`, `Barcode.rawValue`, `MobileScannerException.errorCode`, `MobileScannerErrorCode`). The `errorBuilder` signature is `Widget Function(BuildContext, MobileScannerException)`, checked against 7.4.2's `lib/src/mobile_scanner.dart`.
- Produces:
  - `typedef PassScannerBuilder = Widget Function(BuildContext context, ValueChanged<String> onCode)`
  - `final passScannerProvider = Provider<PassScannerBuilder>(...)`
  - `class ScanPassScreen`: pops with `String?`
  - `class CameraPassScanner`
  - `String cameraErrorMessage(MobileScannerErrorCode code)`
  - the route `/admin/check-in/scan`, open to every member of the current resort

- [ ] **Step 1: Add the package and the iOS camera description**

In `pubspec.yaml`, replace:

```yaml
  # Decorative QR code on the confirmation/booking-detail screens --
  # nothing in this app ever scans one back.
  qr_flutter: ^4.1.0
```

with:

```yaml
  # Draws the guest's signed check-in pass as a QR
  # (lib/features/stay/stay_pass_qr.dart).
  qr_flutter: ^4.1.0
  # Reception's camera scanner for those passes
  # (lib/features/admin/scan_pass_screen.dart). Web: uses the browser's
  # BarcodeDetector, or loads zxing-wasm itself; needs HTTPS or localhost.
  mobile_scanner: ^7.4.2
```

Run: `flutter pub get`
Expected: `mobile_scanner 7.4.x` is added to `pubspec.lock`. If `git diff pubspec.lock` also shows SDK-only bumps (for example `flutter`/`sky_engine` package hashes) unrelated to mobile_scanner, revert those hunks and keep the mobile_scanner entries.

In `ios/Runner/Info.plist`, right after:

```xml
	<key>NSLocationWhenInUseUsageDescription</key>
	<string>Shows resorts and your city near you.</string>
```

add:

```xml
	<key>NSCameraUsageDescription</key>
	<string>Scans guests' check-in passes at the front desk.</string>
```

Android needs nothing: the plugin's own manifest declares `android.permission.CAMERA`, and `android.hardware.camera` is not required.

- [ ] **Step 2: Write the failing tests**

Create `test/features/admin/scan_pass_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:pasala/features/admin/scan_pass_screen.dart';

void main() {
  late String? result;
  late int returns;

  Widget app() {
    result = 'unset';
    returns = 0;
    final router = GoRouter(
      initialLocation: '/start',
      routes: [
        GoRoute(
          path: '/start',
          builder: (context, _) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  final code = await context.push<String>('/scan');
                  returns++;
                  result = code;
                },
                child: const Text('OPEN SCANNER'),
              ),
            ),
          ),
        ),
        GoRoute(path: '/scan', builder: (_, _) => const ScanPassScreen()),
      ],
    );
    return ProviderScope(
      overrides: [
        // No camera under flutter test: a button stands in for it. A real
        // camera reports the same code on many frames, so it fires twice.
        passScannerProvider.overrideWithValue(
          (context, onCode) => Center(
            child: TextButton(
              key: const Key('fake-camera'),
              onPressed: () {
                onCode('rh1.first');
                onCode('rh1.second');
              },
              child: const Text('READ'),
            ),
          ),
        ),
      ],
      child: MaterialApp.router(routerConfig: router),
    );
  }

  Future<void> openScanner(WidgetTester tester) async {
    await tester.pumpWidget(app());
    await tester.tap(find.text('OPEN SCANNER'));
    await tester.pumpAndSettle();
  }

  testWidgets('shows the camera, a hint and a way to type the code instead',
      (tester) async {
    await openScanner(tester);

    expect(find.text('Scan pass'), findsOneWidget);
    expect(find.byKey(const Key('fake-camera')), findsOneWidget);
    expect(find.text("Point the camera at the guest's check-in QR."), findsOneWidget);
    expect(find.text('Enter code instead'), findsOneWidget);
  });

  // Review Focus 1.
  testWidgets('the first code read leaves the screen with that code, once',
      (tester) async {
    await openScanner(tester);

    await tester.tap(find.byKey(const Key('fake-camera')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(result, 'rh1.first');
    expect(returns, 1);
    expect(find.text('OPEN SCANNER'), findsOneWidget);
  });

  testWidgets('Enter code instead returns with no code', (tester) async {
    await openScanner(tester);

    await tester.tap(find.byKey(const Key('scan-enter-code')));
    await tester.pumpAndSettle();

    expect(result, isNull);
    expect(returns, 1);
    expect(find.text('OPEN SCANNER'), findsOneWidget);
  });

  group('cameraErrorMessage', () {
    test('a denied permission says how to turn it on', () {
      expect(cameraErrorMessage(MobileScannerErrorCode.permissionDenied),
          'Camera access is off. Allow the camera in your browser or phone '
          'settings, or enter the code instead.');
    });

    test('a device without a camera says so', () {
      expect(cameraErrorMessage(MobileScannerErrorCode.unsupported),
          'This device has no camera the app can use. Enter the code instead.');
    });

    test('anything else offers typing the code', () {
      expect(cameraErrorMessage(MobileScannerErrorCode.genericError),
          'The camera could not start. Enter the code instead.');
    });
  });
}
```

In `test/core/router_test.dart`, add this group inside `main()`, right after the `group('desk checkout', ...)` group closes:

```dart
  group('pass scanner', () {
    test('/admin/check-in/scan opens for every role at the current resort', () {
      expect(_to(_superAdmin, _ownerM, '/admin/check-in/scan'), null);
      expect(_to(_admin, _adminM, '/admin/check-in/scan'), null);
      expect(_to(_staff, _staffM, '/admin/check-in/scan'), null);
      expect(_to(_accountant, _accountantM, '/admin/check-in/scan'), null);
    });

    test('customers are refused /admin/check-in/scan', () {
      expect(_to(_customer, null, '/admin/check-in/scan'), '/404');
    });

    test('the app router registers scan under /admin/check-in', () {
      TestWidgetsFlutterBinding.ensureInitialized();
      final container = ProviderContainer(overrides: [
        currentUserProvider.overrideWith((ref) => Stream.value(null)),
        currentResortProvider.overrideWith(_NoResort.new),
      ]);
      addTearDown(container.dispose);
      final router = container.read(routerProvider);

      GoRoute? findCheckIn(List<RouteBase> routes) {
        for (final route in routes) {
          if (route is GoRoute && route.path == '/admin/check-in') return route;
          final hit = findCheckIn(route.routes);
          if (hit != null) return hit;
        }
        return null;
      }

      final checkIn = findCheckIn(router.configuration.routes);
      expect(checkIn, isNotNull);
      expect(checkIn!.routes.whereType<GoRoute>().map((r) => r.path),
          contains('scan'));
    });
  });
```

- [ ] **Step 3: Run them to verify they fail**

Run: `flutter test test/features/admin/scan_pass_screen_test.dart test/core/router_test.dart`
Expected: FAIL. `scan_pass_screen.dart` does not exist, so the file does not compile. In `router_test.dart`, `/admin/check-in/scan` redirects to `/404` for staff and accountants, and the `scan` child is missing.

- [ ] **Step 4: Write the scanner screen**

Create `lib/features/admin/scan_pass_screen.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/theme/tokens.dart';

/// Builds the live camera view. [onCode] gets the raw text of every QR
/// code the camera reads. Tests override [passScannerProvider] with a
/// stand-in, because there is no camera under `flutter test`.
typedef PassScannerBuilder = Widget Function(
  BuildContext context,
  ValueChanged<String> onCode,
);

final passScannerProvider = Provider<PassScannerBuilder>(
  (ref) => (context, onCode) => CameraPassScanner(onCode: onCode),
);

/// What reception reads when the camera cannot start. Every message ends
/// with the way out: typing the code on the check-in screen.
String cameraErrorMessage(MobileScannerErrorCode code) => switch (code) {
      MobileScannerErrorCode.permissionDenied =>
        'Camera access is off. Allow the camera in your browser or phone '
            'settings, or enter the code instead.',
      MobileScannerErrorCode.unsupported =>
        'This device has no camera the app can use. Enter the code instead.',
      _ => 'The camera could not start. Enter the code instead.',
    };

/// `/admin/check-in/scan` -- the camera. Pops with the raw text of the
/// first QR code it reads (the check-in screen verifies it), or with null
/// when reception taps "Enter code instead".
class ScanPassScreen extends ConsumerStatefulWidget {
  const ScanPassScreen({super.key});

  @override
  ConsumerState<ScanPassScreen> createState() => _ScanPassScreenState();
}

class _ScanPassScreenState extends ConsumerState<ScanPassScreen> {
  bool _done = false;

  void _onCode(String code) {
    // The camera keeps reporting the same code frame after frame; only the
    // first one leaves the screen.
    if (_done || !mounted) return;
    _done = true;
    context.pop(code);
  }

  @override
  Widget build(BuildContext context) {
    final scanner = ref.watch(passScannerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Scan pass')),
      body: Stack(
        fit: StackFit.expand,
        children: [
          scanner(context, _onCode),
          IgnorePointer(
            child: Center(
              child: Container(
                width: 240,
                height: 240,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white, width: 3),
                  borderRadius: BorderRadius.circular(PasalaTokens.radiusSm),
                ),
              ),
            ),
          ),
          Positioned(
            left: Spacing.md,
            right: Spacing.md,
            bottom: Spacing.xl,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(Spacing.sm),
                    child: Text(
                      "Point the camera at the guest's check-in QR.",
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
                const SizedBox(height: Spacing.sm),
                FilledButton.tonal(
                  key: const Key('scan-enter-code'),
                  onPressed: () {
                    if (_done) return;
                    _done = true;
                    context.pop();
                  },
                  child: const Text('Enter code instead'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The mobile_scanner camera, reading QR codes only.
class CameraPassScanner extends StatefulWidget {
  const CameraPassScanner({super.key, required this.onCode});

  final ValueChanged<String> onCode;

  @override
  State<CameraPassScanner> createState() => _CameraPassScannerState();
}

class _CameraPassScannerState extends State<CameraPassScanner> {
  final _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );

  @override
  void dispose() {
    unawaited(_controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MobileScanner(
        controller: _controller,
        onDetect: (capture) {
          for (final barcode in capture.barcodes) {
            final value = barcode.rawValue;
            if (value != null && value.isNotEmpty) {
              widget.onCode(value);
              return;
            }
          }
        },
        errorBuilder: (context, error) => ColoredBox(
          color: Colors.black,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(Spacing.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.no_photography_outlined,
                      color: Colors.white, size: 48),
                  const SizedBox(height: Spacing.sm),
                  Text(
                    cameraErrorMessage(error.errorCode),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}
```

- [ ] **Step 5: Add the route and open it to staff**

In `lib/core/router.dart`:
- Add `import '../features/admin/scan_pass_screen.dart';` after the `reception_checkout_screen.dart` import.
- In `redirectFor`'s `staffOrAboveOk`, replace `path == '/admin/check-in' ||` with:

```dart
            path == '/admin/check-in' ||
            path.startsWith('/admin/check-in/') ||
```

- In the comment block above it, after the sentence that ends "…with the desk checkout of one booking at `/admin/check-out/:reservationId`.", add: `The pass scanner at /admin/check-in/scan (P3) belongs to the check-in desk the same way.`
- Replace:

```dart
          GoRoute(
            path: '/admin/check-in',
            builder: (_, _) => const ReceptionCheckinScreen(),
          ),
```

with:

```dart
          GoRoute(
            path: '/admin/check-in',
            builder: (_, _) => const ReceptionCheckinScreen(),
            routes: [
              // The pass scanner (P3). A child of the list, so the list
              // stays underneath and gets the scanned text back from pop.
              GoRoute(
                path: 'scan',
                builder: (_, _) => const ScanPassScreen(),
              ),
            ],
          ),
```

- [ ] **Step 6: Run the tests**

Run: `flutter test test/features/admin/scan_pass_screen_test.dart test/core/router_test.dart && flutter analyze`
Expected: PASS, with no new analyzer issues.

- [ ] **Step 7: Commit**

```bash
git add pubspec.yaml pubspec.lock ios/Runner/Info.plist lib/features/admin/scan_pass_screen.dart \
  lib/core/router.dart test/features/admin/scan_pass_screen_test.dart test/core/router_test.dart
git commit -m "feat(stay-pass): camera scanner at /admin/check-in/scan

mobile_scanner reads QR codes only and the screen pops with the first
read; 'Enter code instead' pops with nothing. Open to every member of
the current resort, like the check-in desk.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 6: Reception search, Scan pass and the check-in sheet

**Track:** App. **Depends on:** Task 1.

**Files:**
- Create: `lib/features/admin/pass_check_in_sheet.dart`
- Modify: `lib/features/admin/reception_checkin_screen.dart` (full rewrite of the widget; `roomWarningFor` kept as is)
- Modify: `test/features/admin/reception_checkin_screen_test.dart`

**Interfaces:**
- Consumes (Task 1):
  - `stayPassSourceProvider`
  - `VerifiedPass`
  - `looksLikeStayPass`
  - `StayPassRejected.otherResort()`
  - `FakeStayPassSource`
  - `verifiedPass({...})`
- Consumes (existing):
  - `bookingCode` and `bookingMatchesSearch` (`admin_bookings_screen.dart`)
  - `roomBoardProvider`
  - `todaysArrivalsProvider`
  - `checkedInProvider`
  - `allBookingsProvider`
  - `stayRepositoryProvider`
  - the route string `/admin/check-in/scan` (Task 5 registers it; this task's tests use a stub route)
- Produces:
  - `PassCheckInSheet({required VerifiedPass pass, String? roomWarning})`, which pops `true` on "Check in guest"
  - `String passStatusLine(ReservationStatus)`
  - the keys `checkin-search`, `open-pass`, `scan-pass-button`, `pass-check-in`, `pass-status` and `pass-room-warning`

- [ ] **Step 1: Write the failing tests**

Replace the top half of `test/features/admin/reception_checkin_screen_test.dart`, from the imports through the end of the `appFor` helper, so it reads:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pasala/core/current_resort.dart';
import 'package:pasala/core/errors.dart';
import 'package:pasala/data/models/reservation.dart';
import 'package:pasala/data/models/resort_membership.dart';
import 'package:pasala/data/models/room_status.dart';
import 'package:pasala/data/repositories/room_status_repository.dart';
import 'package:pasala/data/repositories/stay_pass_repository.dart';
import 'package:pasala/data/repositories/stay_repository.dart';
import 'package:pasala/features/admin/pass_check_in_sheet.dart';
import 'package:pasala/features/admin/reception_checkin_screen.dart';

import '../../support/fake_room_board_source.dart';
import '../../support/fake_stay_pass_source.dart';

const _resort =
    ResortMembership(propertyId: 'p1', resortName: 'Pasala', role: ResortRole.admin);

const _bookingId = '3f2a1b9c-0000-0000-0000-000000000000';
const _otherId = 'aa11bb22-0000-0000-0000-000000000000';

class _FixedResort extends CurrentResort {
  @override
  ResortMembership? build() => _resort;
}

Reservation _booking({String? customerName, String id = _bookingId}) => Reservation(
      id: id,
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
    FakeStayPassSource? passes,
  }) {
    // /admin/check-in/scan is Task 5's screen; a stub stands in for it
    // here, returning a code or nothing the way the real one pops.
    final router = GoRouter(
      initialLocation: '/admin/check-in',
      routes: [
        GoRoute(
          path: '/admin/check-in',
          builder: (_, _) => const ReceptionCheckinScreen(),
          routes: [
            GoRoute(
              path: 'scan',
              builder: (context, _) => Scaffold(
                body: Column(
                  children: [
                    TextButton(
                      onPressed: () => context.pop('rh1.scanned'),
                      child: const Text('FAKE READ'),
                    ),
                    TextButton(
                      onPressed: () => context.pop(),
                      child: const Text('FAKE CANCEL'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
    return ProviderScope(
      overrides: [
        todaysArrivalsProvider.overrideWith((ref, propertyId) async {
          listedPropertyIds.add(propertyId);
          return arrivals;
        }),
        currentResortProvider.overrideWith(_FixedResort.new),
        roomBoardSourceProvider
            .overrideWithValue(board ?? FakeRoomBoardSource()),
        stayPassSourceProvider
            .overrideWithValue(passes ?? FakeStayPassSource()),
        if (stay != null) stayRepositoryProvider.overrideWithValue(stay),
      ],
      child: MaterialApp.router(routerConfig: router),
    );
  }
```

Keep every existing test below `appFor` unchanged. Then append these tests at the end of `main()`:

```dart
  testWidgets('each row shows the booking code the guest sees', (tester) async {
    await tester.pumpWidget(appFor([_booking(customerName: 'Ravi Kumar')]));
    await tester.pumpAndSettle();

    expect(find.textContaining('Booking PR3F2A'), findsOneWidget);
  });

  testWidgets('typing a booking code, name or phone filters the list',
      (tester) async {
    await tester.pumpWidget(appFor([
      _booking(customerName: 'Ravi Kumar'),
      _booking(customerName: 'Meera Nair', id: _otherId),
    ]));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('checkin-search')), 'pr3f');
    await tester.pumpAndSettle();
    expect(find.text('Ravi Kumar'), findsOneWidget);
    expect(find.text('Meera Nair'), findsNothing);

    await tester.enterText(find.byKey(const Key('checkin-search')), 'meera');
    await tester.pumpAndSettle();
    expect(find.text('Ravi Kumar'), findsNothing);
    expect(find.text('Meera Nair'), findsOneWidget);
  });

  testWidgets('a search that matches nothing says so', (tester) async {
    await tester.pumpWidget(appFor([_booking(customerName: 'Ravi Kumar')]));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('checkin-search')), 'zzz');
    await tester.pumpAndSettle();

    expect(find.text('No booking matches "zzz"'), findsOneWidget);
  });

  testWidgets(
      'Scan pass reads a pass, opens its check-in, and Check in guest checks in',
      (tester) async {
    final passes = FakeStayPassSource()..verified = verifiedPass();
    final stay = _FakeStayRepository();
    await tester.pumpWidget(appFor([_booking(customerName: 'Ravi Kumar')],
        passes: passes, stay: stay));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('scan-pass-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('FAKE READ'));
    await tester.pumpAndSettle();

    expect(passes.verifyCalls, ['rh1.scanned']);
    expect(find.text('Pass verified'), findsOneWidget);
    expect(find.textContaining('Cottage 1'), findsWidgets);
    expect(find.text('9000000001'), findsOneWidget);

    await tester.tap(find.byKey(const Key('pass-check-in')));
    await tester.pumpAndSettle();

    expect(stay.checkIns, [_bookingId]);
    expect(find.text('Checked in'), findsOneWidget);
    expect(find.text('Pass verified'), findsNothing);
  });

  testWidgets('closing the scanner without a code does nothing', (tester) async {
    final passes = FakeStayPassSource();
    await tester.pumpWidget(
        appFor([_booking(customerName: 'Ravi Kumar')], passes: passes));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('scan-pass-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('FAKE CANCEL'));
    await tester.pumpAndSettle();

    expect(passes.verifyCalls, isEmpty);
    expect(find.text('Ravi Kumar'), findsOneWidget);
  });

  testWidgets('a rejected pass shows why, and no sheet', (tester) async {
    final passes = FakeStayPassSource()
      ..verifyError = const StayPassRejected.expired();
    await tester.pumpWidget(
        appFor([_booking(customerName: 'Ravi Kumar')], passes: passes));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('scan-pass-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('FAKE READ'));
    await tester.pumpAndSettle();

    expect(find.text(const StayPassRejected.expired().message), findsOneWidget);
    expect(find.text('Pass verified'), findsNothing);
  });

  // Review Focus 3.
  testWidgets('a pass for another resort is refused even when the server '
      'verified it', (tester) async {
    final passes = FakeStayPassSource()
      ..verified = verifiedPass(propertyId: 'p2');
    final stay = _FakeStayRepository();
    await tester.pumpWidget(appFor([_booking(customerName: 'Ravi Kumar')],
        passes: passes, stay: stay));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('scan-pass-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('FAKE READ'));
    await tester.pumpAndSettle();

    expect(find.text(const StayPassRejected.otherResort().message), findsOneWidget);
    expect(find.text('Pass verified'), findsNothing);
    expect(stay.checkIns, isEmpty);
  });

  // Review Focus 2.
  testWidgets('a pass typed by a keyboard scanner opens on Enter, trimmed',
      (tester) async {
    final passes = FakeStayPassSource()..verified = verifiedPass();
    await tester.pumpWidget(
        appFor([_booking(customerName: 'Ravi Kumar')], passes: passes));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('checkin-search')), '  rh1.typed \n');
    await tester.testTextInput.receiveAction(TextInputAction.go);
    await tester.pumpAndSettle();

    expect(passes.verifyCalls, ['rh1.typed']);
    expect(find.text('Pass verified'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byKey(const Key('checkin-search'))).controller!.text,
      isEmpty,
    );
  });

  testWidgets('the Open pass button shows only for a pass', (tester) async {
    final passes = FakeStayPassSource()..verified = verifiedPass();
    await tester.pumpWidget(
        appFor([_booking(customerName: 'Ravi Kumar')], passes: passes));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('checkin-search')), 'PR3F');
    await tester.pump();
    expect(find.byKey(const Key('open-pass')), findsNothing);

    await tester.enterText(find.byKey(const Key('checkin-search')), 'rh1.pasted');
    await tester.pump();
    // While a pass is being typed the list is not filtered by it.
    expect(find.text('Ravi Kumar'), findsOneWidget);
    await tester.tap(find.byKey(const Key('open-pass')));
    await tester.pumpAndSettle();

    expect(passes.verifyCalls, ['rh1.pasted']);
  });

  testWidgets('an already checked-in booking shows its status and no button',
      (tester) async {
    final passes = FakeStayPassSource()
      ..verified = verifiedPass(status: ReservationStatus.checkedIn);
    await tester.pumpWidget(
        appFor([_booking(customerName: 'Ravi Kumar')], passes: passes));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('scan-pass-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('FAKE READ'));
    await tester.pumpAndSettle();

    expect(find.text('Already checked in'), findsOneWidget);
    expect(find.byKey(const Key('pass-check-in')), findsNothing);
  });

  testWidgets('the sheet warns when the room still needs cleaning',
      (tester) async {
    final passes = FakeStayPassSource()..verified = verifiedPass();
    await tester.pumpWidget(appFor(
      [_booking(customerName: 'Ravi Kumar')],
      passes: passes,
      board: FakeRoomBoardSource()
        ..entries = [
          boardEntry(unitId: 'u1', state: RoomState.dirty, status: RoomStatus.cleaning),
        ],
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('scan-pass-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('FAKE READ'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('pass-room-warning')), findsOneWidget);
    expect(find.byKey(const Key('pass-check-in')), findsOneWidget);
  });

  group('passStatusLine', () {
    test('says what happened to a booking that cannot be checked in', () {
      expect(passStatusLine(ReservationStatus.checkedIn), 'Already checked in');
      expect(passStatusLine(ReservationStatus.checkedOut),
          'This stay has already checked out');
      expect(passStatusLine(ReservationStatus.cancelled), 'This booking was cancelled');
      expect(passStatusLine(ReservationStatus.hold), 'This booking is not confirmed yet');
      expect(passStatusLine(ReservationStatus.pendingPayment),
          'This booking is not confirmed yet');
    });
  });
```

- [ ] **Step 2: Run them to verify they fail**

Run: `flutter test test/features/admin/reception_checkin_screen_test.dart`
Expected: FAIL. `pass_check_in_sheet.dart` does not exist, so the file does not compile.

- [ ] **Step 3: Write the sheet**

Create `lib/features/admin/pass_check_in_sheet.dart`:

```dart
import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/theme/tokens.dart';
import '../../data/models/reservation.dart';
import '../../data/models/room_status.dart';
import '../../data/models/verified_pass.dart';
import 'admin_bookings_screen.dart' show bookingCode;

/// Why a verified booking has no "Check in guest" button.
String passStatusLine(ReservationStatus status) => switch (status) {
      ReservationStatus.checkedIn => 'Already checked in',
      ReservationStatus.checkedOut => 'This stay has already checked out',
      ReservationStatus.cancelled => 'This booking was cancelled',
      _ => 'This booking is not confirmed yet',
    };

/// What reception sees after a guest's pass is verified (P3): whose
/// booking it is, the room warning if any, and "Check in guest" for a
/// confirmed booking. Pops `true` when reception taps it; the check-in
/// screen then runs its usual check-in.
class PassCheckInSheet extends StatelessWidget {
  const PassCheckInSheet({super.key, required this.pass, this.roomWarning});

  final VerifiedPass pass;
  final String? roomWarning;

  @override
  Widget build(BuildContext context) {
    final r = pass.reservation;
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final details = [
      if (pass.unitName != null) pass.unitName!,
      '${formatDay(r.start.toLocal())} → ${formatDay(r.end.toLocal())}',
      '${r.guests ?? '—'} guests',
      'Booking ${bookingCode(r.id)}',
    ].join(' · ');

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.verified_outlined, color: scheme.primary),
                const SizedBox(width: Spacing.sm),
                Text('Pass verified', style: textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: Spacing.md),
            Text(r.customerName ?? 'Guest', style: textTheme.headlineSmall),
            if (r.customerPhone case final phone?) Text(phone),
            const SizedBox(height: Spacing.xs),
            Text(details, style: textTheme.bodyMedium),
            if (roomWarning case final warning?)
              Padding(
                padding: const EdgeInsets.only(top: Spacing.sm),
                child: Chip(
                  key: const Key('pass-room-warning'),
                  visualDensity: VisualDensity.compact,
                  avatar: Icon(Icons.warning_amber_outlined,
                      size: 18, color: RoomStatus.cleaning.color),
                  label: Text(warning),
                ),
              ),
            const SizedBox(height: Spacing.lg),
            if (r.status == ReservationStatus.confirmed)
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const Key('pass-check-in'),
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Check in guest'),
                ),
              )
            else
              Text(
                passStatusLine(r.status),
                key: const Key('pass-status'),
                style: textTheme.titleSmall,
              ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Rewrite the check-in screen**

Replace everything in `lib/features/admin/reception_checkin_screen.dart` below the `roomWarningFor` function, and the import block above it, so the file reads:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/current_resort.dart';
import '../../core/errors.dart';
import '../../core/format.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/failure_view.dart';
import '../../data/models/room_status.dart';
import '../../data/models/verified_pass.dart';
import '../../data/repositories/room_status_repository.dart';
import '../../data/repositories/stay_pass_repository.dart';
import '../../data/repositories/stay_repository.dart';
import '../staff/providers.dart' show allBookingsProvider;
import 'admin_bookings_screen.dart' show bookingCode, bookingMatchesSearch;
import 'pass_check_in_sheet.dart';

/// The warning reception sees on a booking whose room is not ready. A
/// warning only: check-in is never blocked on room state (room status
/// spec, decision 10). Null when the room is ready or its state is
/// unknown.
String? roomWarningFor(RoomBoardEntry? room) => switch (room?.state) {
      RoomState.dirty => 'Room not cleaned yet',
      RoomState.outOfOrder => 'Maintenance: ${room?.reason ?? 'out of order'}',
      _ => null,
    };

/// `/admin/check-in` -- every `confirmed` booking, one-tap Check In.
/// Reception finds a guest by scrolling, by typing a booking code, name
/// or phone into the search (which filters the list), or by the guest's
/// signed check-in pass (P3): "Scan pass" opens the camera at
/// `/admin/check-in/scan`, and a pass typed or pasted into the search --
/// which is also what a keyboard-wedge barcode scanner does -- opens on
/// Enter. A verified pass opens [PassCheckInSheet] for that booking.
/// A booking whose room still needs cleaning or is in maintenance carries
/// a warning chip (see [roomWarningFor]).
class ReceptionCheckinScreen extends ConsumerStatefulWidget {
  const ReceptionCheckinScreen({super.key});

  @override
  ConsumerState<ReceptionCheckinScreen> createState() =>
      _ReceptionCheckinScreenState();
}

class _ReceptionCheckinScreenState
    extends ConsumerState<ReceptionCheckinScreen> {
  final _search = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _checkIn(String id, String propertyId) async {
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
      _toast('Checked in');
    } on BookingFailure catch (e) {
      _toast(FailureView.messageFor(e));
    }
  }

  Future<void> _scan() async {
    final code = await context.push<String>('/admin/check-in/scan');
    if (!mounted || code == null) return;
    await _openPass(code);
  }

  /// Verifies [raw] and, for a genuine pass at this resort, opens its
  /// check-in sheet.
  Future<void> _openPass(String raw) async {
    if (_busy) return;
    final propertyId = ref.read(currentResortProvider)!.propertyId;
    setState(() => _busy = true);
    try {
      final VerifiedPass pass;
      try {
        pass = await ref.read(stayPassSourceProvider).verify(raw.trim());
      } on BookingFailure catch (e) {
        _toast(FailureView.messageFor(e));
        return;
      } finally {
        // A pass in the search box has done its job either way.
        if (mounted && looksLikeStayPass(_search.text)) _search.clear();
      }
      // Someone who works at two resorts passes the server's check for
      // either; this desk checks guests in at the current resort only.
      if (pass.propertyId != propertyId) {
        _toast(const StayPassRejected.otherResort().message);
        return;
      }
      if (!mounted) return;
      final rooms = ref.read(roomBoardProvider(propertyId)).value ??
          const <RoomBoardEntry>[];
      final room = {for (final r in rooms) r.unitId: r}[pass.reservation.unitId];
      final checkIn = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) =>
            PassCheckInSheet(pass: pass, roomWarning: roomWarningFor(room)),
      );
      if (checkIn == true) await _checkIn(pass.reservation.id, propertyId);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final propertyId = ref.watch(currentResortProvider)!.propertyId;
    final arrivalsAsync = ref.watch(todaysArrivalsProvider(propertyId));
    // The board only adds warnings: while it loads, or if it fails, the
    // list shows without them and check-in works as before.
    final rooms = ref.watch(roomBoardProvider(propertyId)).value ??
        const <RoomBoardEntry>[];
    final roomByUnit = {for (final r in rooms) r.unitId: r};
    final query = _search.text;
    final typingPass = looksLikeStayPass(query);

    return Scaffold(
      appBar: AppBar(title: const Text('Check-In')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                Spacing.md, Spacing.md, Spacing.md, 0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('checkin-search'),
                    controller: _search,
                    textInputAction: TextInputAction.go,
                    decoration: InputDecoration(
                      labelText: 'Booking code, name or phone',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: typingPass
                          ? IconButton(
                              key: const Key('open-pass'),
                              tooltip: 'Open pass',
                              icon: const Icon(Icons.arrow_forward),
                              onPressed:
                                  _busy ? null : () => _openPass(_search.text),
                            )
                          : null,
                    ),
                    onSubmitted: (value) {
                      if (looksLikeStayPass(value)) _openPass(value);
                    },
                  ),
                ),
                const SizedBox(width: Spacing.sm),
                FilledButton.icon(
                  key: const Key('scan-pass-button'),
                  onPressed: _busy ? null : _scan,
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('Scan pass'),
                ),
              ],
            ),
          ),
          Expanded(
            child: AsyncView(
              value: arrivalsAsync,
              onRetry: () => ref.invalidate(todaysArrivalsProvider(propertyId)),
              empty: () => const EmptyState(
                icon: Icons.how_to_reg_outlined,
                title: 'No bookings waiting to check in',
              ),
              data: (bookings) {
                // A pass being typed is not a search term.
                final shown = typingPass
                    ? bookings
                    : bookings
                        .where((b) => bookingMatchesSearch(b, query))
                        .toList();
                if (shown.isEmpty) {
                  return EmptyState(
                    icon: Icons.search_off,
                    title: 'No booking matches "${query.trim()}"',
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.all(Spacing.md),
                  itemCount: shown.length,
                  itemBuilder: (context, i) {
                    final b = shown[i];
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
                              '${b.guests ?? '—'} guests · Booking ${bookingCode(b.id)}',
                            ),
                            if (warning != null)
                              Padding(
                                padding:
                                    const EdgeInsets.only(top: Spacing.xs),
                                child: Chip(
                                  key: Key('room-warning-${b.id}'),
                                  visualDensity: VisualDensity.compact,
                                  avatar: Icon(Icons.warning_amber_outlined,
                                      size: 18,
                                      color: RoomStatus.cleaning.color),
                                  label: Text(warning),
                                ),
                              ),
                          ],
                        ),
                        trailing: FilledButton(
                          onPressed: () => _checkIn(b.id, propertyId),
                          child: const Text('Check In'),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 5: Run the tests**

Run: `flutter test test/features/admin/reception_checkin_screen_test.dart && flutter analyze`
Expected: PASS, both the earlier tests (names, warnings, board refetch on check-in) and the new ones, with no new analyzer issues.

- [ ] **Step 6: Commit**

```bash
git add lib/features/admin/pass_check_in_sheet.dart lib/features/admin/reception_checkin_screen.dart \
  test/features/admin/reception_checkin_screen_test.dart
git commit -m "feat(stay-pass): reception scans or types a pass to check a guest in

Search by booking code, name or phone; Scan pass opens the camera, and
a pass typed or pasted (or sent by a keyboard-wedge scanner) opens on
Enter. A verified pass at this resort opens a sheet with the room
warning and Check in guest.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Phase 3: Integration

### Task 7: Merge the tracks and verify end to end

**Track:** both. **Depends on:** Tasks 2–6.

**Files:**
- Create: `e2e/tests/stay-pass.spec.ts`
- Modify: `README.md` (a new section before `## Per-platform host`)
- Anything else: a fix belongs to the task that owns the file, and gets its own commit.

**Interfaces:**
- Consumes: everything above. From the e2e helpers:
  - `runSql` (`e2e/fixtures/db.ts`)
  - `setupFrontdeskFixture`, `teardownFrontdeskFixture`, `frontdeskGuest` and `frontdeskBookingId` (`e2e/support/frontdesk-data.ts`)
  - `login`, `goTo` and `fillField` (`e2e/support/index.ts`)
  - `resortA.team.admin` (`e2e/fixtures/world.ts`)
- Produces: a branch where the database and the app agree on names and shapes, with every suite green.

- [ ] **Step 1: Merge**

If the tracks ran in separate worktrees, merge the database branch and the app branch. The tracks own disjoint files, so no conflicts are expected. If one appears, keep both sides' additions.

- [ ] **Step 2: Check the contract by name**

Run: `grep -n "rpc(\|'p_" lib/data/repositories/stay_pass_repository.dart && grep -n "create function public\.\(issue_stay_pass\|verify_stay_pass\)" -A1 supabase/migrations/0052_stay_pass.sql`
Expected: exactly the RPC names `issue_stay_pass` and `verify_stay_pass`, with the parameter names `p_reservation` and `p_token`, matching the SQL signatures. Also run `grep -rn "'/admin/check-in/scan'" lib` and expect the push in `reception_checkin_screen.dart`, matching the `scan` child route in `router.dart`.

- [ ] **Step 3: Run the full suites**

Run: `supabase db reset && supabase test db`, then `flutter test`, then `flutter analyze`
Expected:
- pgTAP: 43 at 65/65, 37 at 77/77, and every other file as in the Task 1 Step 1 baseline.
- Flutter: all tests pass; the count is the baseline plus the tests this plan added.
- Analyzer: the 2 baseline infos only.

- [ ] **Step 4: Write the Playwright spec**

Create `e2e/tests/stay-pass.spec.ts`:

```ts
// Front-desk check-in passes (P3): a guest's signed pass, typed into
// reception's check-in search the way a keyboard-wedge barcode scanner
// types it, opens that booking's check-in sheet. The camera path is
// checked by hand (Step 6): a headless browser has no camera to point at
// a QR.
//
// Fixture: the front-desk guest and booking from support/frontdesk-data.ts
// (confirmed, arriving tomorrow). frontdesk.spec.ts uses the same rows;
// each file creates and removes them itself, and files run one at a time
// (playwright.config.ts: workers 1), so the two never overlap. The tests
// here run in order: the second checks the guest in.

import { expect, test } from '@playwright/test';
import { runSql } from '../fixtures/db.ts';
import { resortA } from '../fixtures/world.ts';
import { fillField, goTo, login } from '../support/index.ts';
import {
  frontdeskBookingId,
  frontdeskGuest,
  setupFrontdeskFixture,
  teardownFrontdeskFixture,
} from '../support/frontdesk-data.ts';

test.beforeAll(() => setupFrontdeskFixture());
test.afterAll(() => teardownFrontdeskFixture());

const admin = resortA.team.admin;

/** The pass issue_stay_pass gives the fixture guest, as their app gets it. */
function issuePass(): string {
  const out = runSql(`
begin;
set local role authenticated;
set local request.jwt.claims to '{"sub":"${frontdeskGuest.id}","role":"authenticated"}';
select 'PASS=' || public.issue_stay_pass('${frontdeskBookingId}');
commit;
`);
  const match = out.match(/PASS=(rh1\.[A-Za-z0-9_-]{75})/);
  if (!match) throw new Error(`issue_stay_pass returned no pass:\n${out}`);
  return match[1];
}

test('a tampered pass is refused with a readable message', async ({ page }) => {
  const pass = issuePass();
  const tampered = `rh1.${pass[4] === 'A' ? 'B' : 'A'}${pass.slice(5)}`;

  await login(page, admin);
  await goTo(page, '/admin/check-in');
  await fillField(page.getByLabel('Booking code, name or phone'), tampered);
  await page.getByRole('button', { name: 'Open pass' }).click();

  await expect(page.getByText('This is not a valid check-in pass.').first()).toBeVisible();
  await expect(page.getByText('Pass verified')).toBeHidden();
});

test("a guest's pass opens their check-in and checks them in", async ({ page }) => {
  const pass = issuePass();

  await login(page, admin);
  await goTo(page, '/admin/check-in');
  await fillField(page.getByLabel('Booking code, name or phone'), pass);
  await page.getByRole('button', { name: 'Open pass' }).click();

  await expect(page.getByText('Pass verified')).toBeVisible();
  await page.getByRole('button', { name: 'Check in guest', exact: true }).click();

  // The visible snackbar and a screen-reader live region: .first() takes either.
  await expect(page.getByText('Checked in', { exact: true }).first()).toBeVisible();
  await expect(
    page.getByRole('group', { name: new RegExp(`^${frontdeskGuest.fullName}`) }),
  ).toBeHidden();
});
```

Run: `cd e2e && npx playwright test tests/stay-pass.spec.ts tests/frontdesk.spec.ts`
Expected: PASS. `frontdesk.spec.ts` must still pass after this file (it recreates its fixture in `beforeAll`). If `fillField` cannot keep a 79-character value, check `e2e/REPORT.md` for the field-typing notes before changing the helper.

- [ ] **Step 5: Document passes in the README**

In `README.md`, insert before `## Per-platform host`:

```markdown
## Front-desk check-in passes

The QR a guest sees on their booking (confirmation, booking detail, My
Stay) is a signed check-in pass: `rh1.` plus the booking id, the resort id
and the end of the stay, signed with HMAC-SHA256 under a random
per-database secret (`supabase/migrations/0052_stay_pass.sql`). Reception
opens it from `/admin/check-in` with **Scan pass** (the device camera), or
by typing or pasting it into the search field. A USB or Bluetooth barcode
scanner that types and presses Enter works too. Guests can always read out
the booking code under the QR instead.

- The secret lives in `private.stay_pass_secret`, which the API cannot
  reach. `supabase db reset` (or the first migration run) creates it.
- To rotate it, which invalidates every pass issued so far (guests get a
  fresh one the next time they open their booking):
  `update private.stay_pass_secret set secret = extensions.gen_random_bytes(32);`
- The web camera needs HTTPS or `localhost`. On iOS the app asks with
  `NSCameraUsageDescription`; Android gets the camera permission from the
  `mobile_scanner` plugin.
```

- [ ] **Step 6: Manual smoke test against the local stack**

Run `make run-web`, then:
1. As a seeded guest with a confirmed booking, open the booking: the Check-in QR card shows a QR and `Booking code PR…`. My Stay's small QR opens a `Check-in pass` dialog.
2. As that resort's admin or staff member, open `/admin/check-in` in a browser on a laptop or phone with a camera (localhost or HTTPS). Tap **Scan pass**, allow the camera, and point it at the guest's QR on another screen. The `Pass verified` sheet shows the guest; **Check in guest** checks them in.
3. Deny the camera permission: the scanner shows "Camera access is off…". **Enter code instead** returns to the list.
4. Type the booking code: the list filters to that guest.
5. Scan an unrelated QR, for example any URL QR: "This is not a valid check-in pass."

- [ ] **Step 7: Commit**

```bash
git add e2e/tests/stay-pass.spec.ts README.md
git commit -m "test(e2e): check a guest in from their signed pass; document passes

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

For each fix found in Steps 2–6, run `git add <the fixed files>` and `git commit -m "fix(stay-pass): <what was wrong>"`, with the same trailer.

---

## Self-Review

**1. Spec coverage**

| Spec requirement | Task |
|---|---|
| Signed compact token (ids, expiry, HMAC-SHA256) | 2 |
| `rh1.` format, 79 characters | 2 (format tests), 3 (regex) |
| Per-deployment secret in a server-only table, seeded if absent | 1 |
| `issue_stay_pass`, the guest's own booking only, with P0008/P0002/P0009 | 1 (signature), 2 |
| Expiry = end of stay, deterministic | 2 |
| `verify_stay_pass`, Staff+ at the token's resort, P0034 invalid/expired/other | 1 (signature), 3 |
| Check order: signature → resort → expiry → booking | 3 |
| Returned shape (row, profiles, unit_name) and any status | 3 (SQL), 1 (`VerifiedPass.fromJson`) |
| Suspended allowed, archived refused | 3 |
| Rotation invalidates | 3 |
| Grants, `search_path`, allow-list | 1 |
| P0034 copy in `errors.dart` | 1 |
| `StayPassSource` seam, providers and fake | 1 |
| Guest QR renders the signed token on 3 screens, with the booking code and the retry state | 4 |
| My Stay thumbnail → dialog | 4 |
| `mobile_scanner`, web camera, iOS description | 5 |
| Scan pass route, and the router matrix | 5 |
| Scan → verify → that booking's check-in | 6 |
| Manual entry kept (search field, typed/pasted pass, keyboard wedge) | 6 |
| Current-resort check for multi-resort staff | 6 |
| Old bare-UUID QR refused | 3, and 1 (copy) |
| Playwright and README | 7 |

**2. Placeholder scan:** no "TBD", "TODO" or "similar to Task N". Every code step shows its code. Every SQL test uses literal ids, and every Dart test uses concrete fixtures.

**3. Type consistency:**
- `StayPassSource.issue(String) → Future<String>` and `verify(String) → Future<VerifiedPass>` match between the repository, the fake and the screens.
- `stayPassProvider` is `FutureProvider.family<String, String>` in the widget and the tests.
- `StayPassRejected.invalid/expired/otherResort` and `PassRejection` use the same names in `errors.dart`, the tests and the screen.
- `PassScannerBuilder` is `(BuildContext, ValueChanged<String>)` in the provider, the screen and the test override.
- The RPC parameter names are `p_reservation` and `p_token` in both SQL and Dart.
- The pgTAP settings `test.tok_r1/tok_in/tok_past/tok_s1` (Task 2) are the ones Task 3 reads.
- The `plan()` counts are 15, 35 and 65.

**4. Review Focus:** each of the five lines has a test in its owning task: 1 in Task 5, 2 in Tasks 6 and 1, 3 in Task 6, 4 in Task 4, 5 in Tasks 3 and 1. Other inputs the spec implies, already covered:
- a pass re-signed for another resort (Task 3)
- another resort's staff probing an expired pass (Task 3)
- a cancelled booking's pass (Task 3, and the sheet status line in Task 6)
- an already checked-in booking (Task 6)
- a camera error (Task 5)
