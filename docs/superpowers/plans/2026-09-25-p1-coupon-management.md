# Coupon Management (P1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let resort owners and admins create, edit, deactivate and list their resort's coupons (with usage counts and an optional single-guest restriction) from a Coupons screen, without changing how guests redeem them.

**Architecture:** Five `security definer` functions in `0051_coupon_management.sql` back the screen. `list_coupons` and `find_resort_guest` read; `create_coupon`, `update_coupon` and `set_coupon_active` validate the input (P0033), write, and record an audit row. Each asserts owner/admin at the resort, and the two that take a coupon id derive that resort from the row. A table check keeps every code upper-case, and the guest's coupon field upper-cases what they type, so the unchanged `resolve_coupon` still matches it. On the app side, a `CouponSource` seam sits behind a `couponsProvider` family keyed by property id. It feeds `/admin/coupons` (`CouponsScreen` plus a full-screen `CouponForm` dialog), which is reached from the owner hub and admin More.

**Tech Stack:** Supabase Postgres 15 (plpgsql, RLS, pgTAP via `supabase test db`), Flutter 3.44 / Dart 3.10, Riverpod 3.3, go_router 17.

**Spec:** `docs/superpowers/specs/2026-09-25-p1-coupon-management-design.md`

## Global Constraints

- One migration: `supabase/migrations/0051_coupon_management.sql`. Tasks 1–3 each edit it. After every edit, rebuild with `supabase db reset` (this re-runs every migration and `supabase/seed.sql`), then run pgTAP.
- New pgTAP file: `supabase/tests/42_coupon_management_test.sql`. It is built up section by section by Tasks 1–3, and each section relies on the state the earlier ones leave. Run one file with `supabase test db supabase/tests/42_coupon_management_test.sql` and the whole suite with `supabase test db`.
- New error code: **P0033 `coupon_invalid`**. Raise it with `raise exception using errcode = 'P0033', message = '<reason>'`. The reason is exactly one of `code_invalid`, `code_taken`, `kind_required`, `value_invalid`, `min_amount_invalid`, `dates_invalid`, `usage_limit_invalid`, `usage_limit_below_used`, `guest_not_eligible`. Existing codes keep their meaning: P0002 not found, P0005 bad input, P0010 coupon not found or inactive (at booking), P0020 not_a_member, P0022 resort_suspended.
- Every new public function has `security definer` and `set search_path = public, pg_temp`. Each is revoked from `public` and `anon`, granted to `authenticated`, and added to the definer allow-list in `supabase/tests/37_tenancy_isolation_test.sql`. The internal helpers `coupon_check_input` and `is_resort_guest` use invoker rights and are revoked from `public`, `anon` and `authenticated`.
- Role set for every coupon function: `owner, admin`. Reads (`list_coupons`, `find_resort_guest`) use `assert_resort_role(<resort>, false, 'owner','admin')`. Writes use `assert_resort_role(<resort>, true, 'owner','admin')`.
- `update_coupon` and `set_coupon_active` read the coupon row first. An unknown id raises P0002 before the role check, the same as `block_dates`. They then assert the role at the row's `property_id`, never at a resort id the client supplied.
- Do not change `resolve_coupon`, `get_quote`, `create_hold`, `cancel_booking`, `release_reservation_coupon` or any policy on `coupons`, `coupon_redemptions`, `reservations` or `profiles`.
- An eligible guest has a reservation at the resort with `kind = 'booking'` and `status in ('confirmed','checked_in','checked_out')`.
- Dates are whole days in `properties.timezone`: `valid_from = D::timestamp at time zone tz`, and `valid_to = (D + 1)::timestamp at time zone tz - interval '1 microsecond'`.
- The code rule is: trim, upper-case, then match `^[A-Z0-9][A-Z0-9_-]{2,23}$`.
- pgTAP conventions (from `39_room_status_test.sql`):
  - Switch users with `set local role authenticated; set local request.jwt.claims to '{"sub":"<uuid>","role":"authenticated"}';`.
  - `reset role` does **not** clear the claims. Run `set local request.jwt.claims to '';` before any superuser change a trigger checks against `auth.uid()`, such as a resort status change.
  - The platform admin is `profiles.role = 'platform_admin'`.
- Dart:
  - Repositories wrap every call in `_guard`, which maps errors through `mapPostgrestError` (`lib/core/errors.dart`).
  - Providers are families keyed by `propertyId`, read from `currentResortProvider`.
  - Widget tests use fakes from `test/support/` and never a real `SupabaseClient`.
  - A dialog's buttons pop with the dialog builder's own context, never the screen's (see commit 66792f0).
- UI copy, exact:
  - Screen title `Coupons`. Tile title `Coupons` with subtitle `Discount codes guests enter when they book`.
  - Status labels: `Active`, `Scheduled`, `Expired`, `Used up`, `Inactive`.
  - Card lines:
    - `10% off` / `₹500 off`, followed by ` · Min ₹5,000` when a minimum is set;
    - `1 Oct 2026 – 31 Oct 2026` / `From 1 Oct 2026` / `Until 31 Oct 2026` / `No date limits`;
    - `Used 3 of 10` / `Used 3`, then ` · Everyone` / ` · Only <name>`.
  - Buttons: `New coupon`, `Deactivate`, `Activate`, `Create coupon`, `Save changes`, `Find`.
- A status is never shown by colour alone: every status chip carries its icon and its label.
- Commands: `flutter test <path>`, `flutter test`, and `flutter analyze`. The analyzer baseline is 2 infos in `service_request_screen.dart`. Never run `dart format` over whole directories or pre-existing files; format only the lines you write. Revert SDK-only `pubspec.lock` bumps.
- Known pgTAP failures appear only between 00:00 and 05:30 IST (25/9, 26/3, 34/2). Everything else must pass.
- Every commit message ends with a blank line and `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Never commit secrets. Do not push.

## Review Focus

1. **A guest types the code in lower case** (`save10`) on a desktop keyboard, where `textCapitalization` does nothing. The coupon must still apply. Codes are stored upper-case and `resolve_coupon` compares exactly, so the quote sheet must upper-case before sending. Owning test: Task 7.
2. **The admin finds a guest, then edits the email field, then saves.** The coupon must not silently go to the previously found guest. Owning test: Task 4 ("changing the email after a match clears the match").
3. **The usage limit is lowered while guests are booking.** The limit must never end up below uses already taken. The check sits in the `UPDATE`'s `WHERE`, under the same row lock `create_hold` takes. Owning tests: Task 2 (limit 2 refused with 3 used; limit 3 accepted).
4. **A coupon's guest has since cancelled their only booking, and the admin edits the value.** The edit must succeed. Only a newly chosen guest is checked. Owning test: Task 2 ("a coupon keeps the guest it already had").
5. **Deactivate from the Coupons screen, which lives inside the router's ShellRoute.** The confirm dialog must close itself, not pop the page. Owning test: Task 5 (the ShellRoute deactivate test).

## Plan decisions (where the spec is silent)

- The form is a full-screen dialog (`Dialog.fullscreen`) opened by `showCouponForm(...)`, which returns `true` when saved. It is not a separate route: the form has no URL worth restoring.
- `CouponForm` takes a `pickDate` callback (default `showDatePicker`) so widget tests can answer the date pickers.
- `set_coupon_active(p_coupon, null)` raises P0005 (`active must be true or false`).
- `update_coupon` passes the guest to `coupon_check_input` only when it differs from the stored `customer_id`.
- `list_coupons` orders by `is_active desc, created_at desc, code`.
- `CouponTile` and `CouponStatusChip` live in `coupons_screen.dart`; nothing else uses them.
- The helper `couponRow(...)` in `test/support/fake_coupon_source.dart` builds test coupons (not `coupon(...)`, which would clash with local variable names).

## Execution tracks

After Task 1, the database track and the app track share no files and can run in parallel, for example in two worktrees branched from Task 1's commit and merged back before Task 8. App tasks never need a database, because their tests use `FakeCouponSource`.

| Task | Track | Depends on | Files it owns |
|---|---|---|---|
| 1 Interface contract | both | none | `0051` (normalisation, check, stubs), `42` (fixtures + contract), `37` (allow-list), `coupon.dart`, `coupon_repository.dart`, `fake_coupon_source.dart`, `test/data/coupon_test.dart`, `test/data/coupon_provider_test.dart` |
| 2 Create, update, activate | DB | 1 | `0051`, `42` |
| 3 List, guest lookup, suspension | DB | 2 | `0051`, `42` |
| 4 Coupon form | App | 1 | `coupon_form.dart`, `errors.dart`, `coupon_form_test.dart`, `errors_test.dart` |
| 5 Coupons screen | App | 4 | `coupons_screen.dart`, `coupons_screen_test.dart` |
| 6 Navigation | App | 5 | `router.dart`, `owner_home_screen.dart`, `admin_more_screen.dart`, their tests |
| 7 Guest code upper-cased | App | none | `quote_sheet.dart`, `quote_sheet_test.dart` |
| 8 Integration | both | 2–7 | none (verification) |

- The database track is strictly sequential: Tasks 2 and 3 share one migration file, one test file and one local Postgres.
- In the app track, Task 5 waits for Task 4 and Task 6 waits for Task 5. Task 7 can run at any time.

---

## File Structure

**Database**
- Create `supabase/migrations/0051_coupon_management.sql`. It holds:
  - code normalisation and the `coupons_code_upper` check;
  - `is_resort_guest` and `coupon_check_input`;
  - `create_coupon`, `update_coupon` and `set_coupon_active`;
  - `list_coupons` and `find_resort_guest`;
  - the grants.
- Create `supabase/tests/42_coupon_management_test.sql`: fixtures, the contract, writes and validation, the role matrix, reads, guest lookup, suspension and archiving.
- Modify `supabase/tests/37_tenancy_isolation_test.sql`: the definer allow-list only.

**App**
- Create `lib/data/models/coupon.dart`:
  - `CouponKind` and `CouponStatus`, with their display strings;
  - `Coupon`, `CouponDraft` and `ResortGuest`;
  - `couponCodePattern` and `normalizeCouponCode`.
- Create `lib/data/repositories/coupon_repository.dart`: the `CouponSource` seam, `CouponRepository`, and the providers.
- Create `lib/features/admin/coupon_form.dart`: `showCouponForm`, `CouponForm` and `CouponDatePicker`.
- Create `lib/features/admin/coupons_screen.dart`: `CouponsScreen`, `CouponTile` and `CouponStatusChip`.
- Modify `lib/core/errors.dart`: `CouponInvalid` for P0033.
- Modify `lib/core/router.dart`: the `/admin/coupons` route.
- Modify `lib/features/owner/owner_home_screen.dart` and `lib/features/admin/admin_more_screen.dart`: a Coupons tile in each.
- Modify `lib/features/booking/quote_sheet.dart`: upper-case the code before applying it.
- Tests:
  - Create `test/support/fake_coupon_source.dart`, `test/data/coupon_test.dart`, `test/data/coupon_provider_test.dart`, `test/features/admin/coupon_form_test.dart` and `test/features/admin/coupons_screen_test.dart`.
  - Modify `test/core/errors_test.dart`, `test/core/router_test.dart`, `test/features/owner/owner_home_screen_test.dart`, `test/features/admin/admin_more_screen_test.dart` and `test/features/booking/quote_sheet_test.dart`.

---

## Phase 0: Interface

### Task 1: Interface contract (normalised codes, function signatures, Dart API)

**Track:** both. Every later task depends on it.

**Files:**
- Create: `supabase/migrations/0051_coupon_management.sql`
- Create: `supabase/tests/42_coupon_management_test.sql`
- Modify: `supabase/tests/37_tenancy_isolation_test.sql` (definer allow-list)
- Create: `lib/data/models/coupon.dart`
- Create: `lib/data/repositories/coupon_repository.dart`
- Create: `test/support/fake_coupon_source.dart`
- Test: `test/data/coupon_test.dart`, `test/data/coupon_provider_test.dart`

**Interfaces:**
- Consumes:
  - SQL: `public.coupons` (0012, with `property_id` since 0043/0045 and `unique (property_id, code)` = `coupons_property_code_key`); `public.coupon_kind ('percent','fixed')`; `public.assert_resort_role(uuid, boolean, variadic resort_role[])` (0043).
  - Dart: `formatInr`, `formatPct` and `formatDate` (`lib/core/format.dart`); `mapPostgrestError` (`lib/core/errors.dart`); `supabaseProvider` (`lib/core/supabase_client.dart`).
- Produces (SQL; later tasks replace only the stub bodies):
  - `public.list_coupons(p_property uuid) returns table (id uuid, code text, kind public.coupon_kind, value numeric, min_booking_value numeric, valid_from date, valid_until date, max_redemptions int, redeemed_count int, customer_id uuid, customer_email text, customer_name text, is_active boolean, status text, created_at timestamptz)`. `status` is one of `active|scheduled|expired|used_up|inactive`.
  - `public.find_resort_guest(p_property uuid, p_email text) returns table (user_id uuid, email text, full_name text)`
  - `public.create_coupon(p_property uuid, p_code text, p_kind public.coupon_kind, p_value numeric, p_min_amount numeric default null, p_valid_from date default null, p_valid_until date default null, p_usage_limit int default null, p_customer uuid default null) returns uuid`
  - `public.update_coupon(p_coupon uuid, p_code text, p_kind public.coupon_kind, p_value numeric, p_min_amount numeric default null, p_valid_from date default null, p_valid_until date default null, p_usage_limit int default null, p_customer uuid default null) returns void`
  - `public.set_coupon_active(p_coupon uuid, p_active boolean) returns void`
  - The check `coupons_code_upper` on `public.coupons`.
- Produces (Dart):
  - `enum CouponKind { percent, fixed }`, with `couponKindFromDb(String)` and `couponKindToDb(CouponKind)`.
  - `enum CouponStatus { active, scheduled, expired, usedUp, inactive }`, with `couponStatusFromDb(String)` and the extension `CouponStatusDisplay` (`label`, `icon`, `color`).
  - `final RegExp couponCodePattern` and `String normalizeCouponCode(String raw)`.
  - `class ResortGuest { userId, email, fullName; String get name; ResortGuest.fromJson }`.
  - `class Coupon`:
    - fields `id, code, kind, value (num), minAmount (num?), validFrom (DateTime?), validUntil (DateTime?), usageLimit (int?), usedCount (int), guest (ResortGuest?), isActive, status, createdAt`;
    - `Coupon.fromJson`;
    - getters `discountLabel`, `minAmountLabel` (String?), `validityLabel`, `usageLabel` and `audienceLabel`.
  - `class CouponDraft { code, kind, value, minAmount, validFrom, validUntil, usageLimit, guestId; Map<String, dynamic> toParams() }`. `toParams` returns the keys `p_code, p_kind, p_value, p_min_amount, p_valid_from, p_valid_until, p_usage_limit, p_customer`, always all eight.
  - `abstract class CouponSource`:
    - `Future<List<Coupon>> list(String propertyId)`
    - `Future<String> create(String propertyId, CouponDraft draft)`
    - `Future<void> update(String couponId, CouponDraft draft)`
    - `Future<void> setActive(String couponId, bool active)`
    - `Future<ResortGuest?> findGuest(String propertyId, String email)`
  - Providers: `couponRepositoryProvider`, `couponSourceProvider` (`Provider<CouponSource>`) and `couponsProvider` (`FutureProvider.autoDispose.family<List<Coupon>, String>`).
  - Test support: `FakeCouponSource`, with:
    - the fields `coupons`, `guests` (`Map<String, ResortGuest>` keyed by email), `listError`, `createError`, `updateError`, `setActiveError` and `findGuestError`;
    - the call logs `listCalls`, `createCalls` (`List<(String, CouponDraft)>`), `updateCalls` (`List<(String, CouponDraft)>`), `setActiveCalls` (`List<(String, bool)>`) and `findGuestCalls` (`List<(String, String)>`).
    - Also `couponRow({...})`.

- [ ] **Step 1: Record the baselines**

Run: `supabase db reset && supabase test db 2>&1 | tail -20`, then `flutter analyze 2>&1 | tail -5`, then `flutter test 2>&1 | tail -3`
Expected: write down the pgTAP failure count and names (at most the 3 known time-of-day failures), the analyzer issue count (2 infos in `service_request_screen.dart`) and the Flutter pass count. Later tasks compare against these numbers.

- [ ] **Step 2: Write the failing pgTAP contract test**

Create `supabase/tests/42_coupon_management_test.sql`:

```sql
-- Coupon management (P1), added in 0051_coupon_management.sql. See
-- docs/superpowers/specs/2026-09-25-p1-coupon-management-design.md.
--
-- One file, built up by the plan's database tasks in order: each section
-- relies on the state the sections before it leave behind.
--
-- Fixtures: resort R with an owner, an admin, a staff member and an
-- accountant; resort S with an owner. Guests: Gita (a confirmed booking at
-- R), Olu (a confirmed booking at S only), Hana (only a hold at R) and
-- Kiran (only a cancelled booking at R). A platform admin with no
-- membership. R has one rate rule (10,000 a night) and two coupons written
-- straight into the table: OLD5 (3 of 5 uses taken) and KIRANVIP
-- (restricted to Kiran).
begin;
select plan(17);

insert into auth.users (id, email) values
  ('c0000000-0000-0000-0000-000000000001','cp-r-owner@example.com'),
  ('c0000000-0000-0000-0000-000000000002','cp-r-admin@example.com'),
  ('c0000000-0000-0000-0000-000000000003','cp-r-staff@example.com'),
  ('c0000000-0000-0000-0000-000000000004','cp-r-accountant@example.com'),
  ('c0000000-0000-0000-0000-000000000005','cp-s-owner@example.com'),
  ('c0000000-0000-0000-0000-000000000006','Gita.Guest@Example.com'),
  ('c0000000-0000-0000-0000-000000000007','cp-olu@example.com'),
  ('c0000000-0000-0000-0000-000000000008','cp-hana@example.com'),
  ('c0000000-0000-0000-0000-000000000009','cp-kiran@example.com'),
  ('c0000000-0000-0000-0000-00000000000a','cp-platform@example.com');
update public.profiles set full_name = 'Gita Guest'
 where id = 'c0000000-0000-0000-0000-000000000006';
update public.profiles set role = 'platform_admin'
 where id = 'c0000000-0000-0000-0000-00000000000a';

insert into public.properties (id, name, slug) values
  ('c1000000-0000-4000-8000-000000000001','Coupon R','coupons-r'),
  ('c1000000-0000-4000-8000-000000000002','Coupon S','coupons-s');

insert into public.resort_members (property_id, user_id, role) values
  ('c1000000-0000-4000-8000-000000000001','c0000000-0000-0000-0000-000000000001','owner'),
  ('c1000000-0000-4000-8000-000000000001','c0000000-0000-0000-0000-000000000002','admin'),
  ('c1000000-0000-4000-8000-000000000001','c0000000-0000-0000-0000-000000000003','staff'),
  ('c1000000-0000-4000-8000-000000000001','c0000000-0000-0000-0000-000000000004','accountant'),
  ('c1000000-0000-4000-8000-000000000002','c0000000-0000-0000-0000-000000000005','owner');

insert into public.units (id, property_id, name, capacity_base, capacity_max) values
  ('c1000000-0000-4000-8000-000000000011','c1000000-0000-4000-8000-000000000001','R Cottage',2,4),
  ('c1000000-0000-4000-8000-000000000012','c1000000-0000-4000-8000-000000000002','S Cottage',2,4);

insert into public.rate_rules (unit_id, kind, price, extra_guest_price, cleaning_fee, priority)
values ('c1000000-0000-4000-8000-000000000011', 'base', 10000, 0, 0, 0);

insert into public.reservations
  (id, unit_id, period, kind, status, customer_id, guests, hold_expires_at) values
  ('c1000000-0000-4000-8000-000000000021','c1000000-0000-4000-8000-000000000011',
   tstzrange(now() + interval '10 days', now() + interval '11 days', '[)'),
   'booking','confirmed','c0000000-0000-0000-0000-000000000006',2,null),
  ('c1000000-0000-4000-8000-000000000022','c1000000-0000-4000-8000-000000000012',
   tstzrange(now() + interval '10 days', now() + interval '11 days', '[)'),
   'booking','confirmed','c0000000-0000-0000-0000-000000000007',2,null),
  ('c1000000-0000-4000-8000-000000000023','c1000000-0000-4000-8000-000000000011',
   tstzrange(now() + interval '20 days', now() + interval '21 days', '[)'),
   'booking','hold','c0000000-0000-0000-0000-000000000008',2, now() + interval '15 minutes'),
  ('c1000000-0000-4000-8000-000000000024','c1000000-0000-4000-8000-000000000011',
   tstzrange(now() + interval '30 days', now() + interval '31 days', '[)'),
   'booking','cancelled','c0000000-0000-0000-0000-000000000009',2,null);

insert into public.coupons (id, property_id, code, kind, value, max_redemptions, redeemed_count) values
  ('c1000000-0000-4000-8000-000000000031','c1000000-0000-4000-8000-000000000001','OLD5','fixed',500,5,3);
insert into public.coupons (id, property_id, code, kind, value, customer_id) values
  ('c1000000-0000-4000-8000-000000000032','c1000000-0000-4000-8000-000000000001','KIRANVIP','percent',20,
   'c0000000-0000-0000-0000-000000000009');

-- === Task 1: the contract ===================================================

select ok(to_regprocedure('public.create_coupon(uuid, text, public.coupon_kind, numeric, numeric, date, date, integer, uuid)') is not null,
  'create_coupon has the agreed signature');
select ok(to_regprocedure('public.update_coupon(uuid, text, public.coupon_kind, numeric, numeric, date, date, integer, uuid)') is not null,
  'update_coupon has the agreed signature');
select ok(to_regprocedure('public.set_coupon_active(uuid, boolean)') is not null,
  'set_coupon_active has the agreed signature');
select ok(to_regprocedure('public.list_coupons(uuid)') is not null,
  'list_coupons has the agreed signature');
select ok(to_regprocedure('public.find_resort_guest(uuid, text)') is not null,
  'find_resort_guest has the agreed signature');

-- The parameter names are the JSON keys CouponRepository sends.
select is((select array_to_string(p.proargnames, ',') from pg_proc p
            where p.oid = to_regprocedure('public.create_coupon(uuid, text, public.coupon_kind, numeric, numeric, date, date, integer, uuid)')),
  'p_property,p_code,p_kind,p_value,p_min_amount,p_valid_from,p_valid_until,p_usage_limit,p_customer',
  'create_coupon takes the parameter names CouponRepository sends');
select is((select array_to_string(p.proargnames, ',') from pg_proc p
            where p.oid = to_regprocedure('public.update_coupon(uuid, text, public.coupon_kind, numeric, numeric, date, date, integer, uuid)')),
  'p_coupon,p_code,p_kind,p_value,p_min_amount,p_valid_from,p_valid_until,p_usage_limit,p_customer',
  'update_coupon takes the parameter names CouponRepository sends');
select is((select array_to_string(p.proargnames, ',') from pg_proc p
            where p.oid = to_regprocedure('public.set_coupon_active(uuid, boolean)')),
  'p_coupon,p_active', 'set_coupon_active takes p_coupon and p_active');
select is((select array_to_string(p.proargnames[1:2], ',') from pg_proc p
            where p.oid = to_regprocedure('public.find_resort_guest(uuid, text)')),
  'p_property,p_email', 'find_resort_guest takes p_property and p_email');

select is((select array_agg(p.parameter_name::text order by p.ordinal_position)
             from information_schema.parameters p
             join information_schema.routines r
               on r.specific_schema = p.specific_schema and r.specific_name = p.specific_name
            where r.routine_schema = 'public' and r.routine_name = 'list_coupons'
              and p.parameter_mode = 'OUT'),
  array['id','code','kind','value','min_booking_value','valid_from','valid_until',
        'max_redemptions','redeemed_count','customer_id','customer_email',
        'customer_name','is_active','status','created_at'],
  'list_coupons returns the columns Coupon.fromJson reads');
select is((select array_agg(p.parameter_name::text order by p.ordinal_position)
             from information_schema.parameters p
             join information_schema.routines r
               on r.specific_schema = p.specific_schema and r.specific_name = p.specific_name
            where r.routine_schema = 'public' and r.routine_name = 'find_resort_guest'
              and p.parameter_mode = 'OUT'),
  array['user_id','email','full_name'], 'find_resort_guest returns user_id, email and full_name');

select is((select count(*)::int
             from unnest(array[
               'public.create_coupon(uuid, text, public.coupon_kind, numeric, numeric, date, date, integer, uuid)',
               'public.update_coupon(uuid, text, public.coupon_kind, numeric, numeric, date, date, integer, uuid)',
               'public.set_coupon_active(uuid, boolean)',
               'public.list_coupons(uuid)',
               'public.find_resort_guest(uuid, text)']::regprocedure[]) f
             join pg_proc p on p.oid = f
            where p.prosecdef and p.proconfig @> array['search_path=public, pg_temp']),
  5, 'all five coupon functions are security definer with a pinned search_path');
select is((select array_agg(f::text order by f::text)
             from unnest(array[
               'public.create_coupon(uuid, text, public.coupon_kind, numeric, numeric, date, date, integer, uuid)',
               'public.update_coupon(uuid, text, public.coupon_kind, numeric, numeric, date, date, integer, uuid)',
               'public.set_coupon_active(uuid, boolean)',
               'public.list_coupons(uuid)',
               'public.find_resort_guest(uuid, text)']::regprocedure[]) f
            where has_function_privilege('anon', f, 'execute')),
  null, 'anon can execute none of the coupon functions');
select is((select count(*)::int
             from unnest(array[
               'public.create_coupon(uuid, text, public.coupon_kind, numeric, numeric, date, date, integer, uuid)',
               'public.update_coupon(uuid, text, public.coupon_kind, numeric, numeric, date, date, integer, uuid)',
               'public.set_coupon_active(uuid, boolean)',
               'public.list_coupons(uuid)',
               'public.find_resort_guest(uuid, text)']::regprocedure[]) f
            where has_function_privilege('authenticated', f, 'execute')),
  5, 'authenticated can execute all five coupon functions');

select ok(exists (select 1 from pg_constraint
                   where conrelid = 'public.coupons'::regclass
                     and conname = 'coupons_code_upper'),
  'coupons carries the upper-case code check');
select throws_ok($$insert into public.coupons (property_id, code, kind, value)
  values ('c1000000-0000-4000-8000-000000000001','lower1','fixed',100)$$,
  '23514', null, 'a lower-case code is refused by the table itself');
select throws_ok($$insert into public.coupons (property_id, code, kind, value)
  values ('c1000000-0000-4000-8000-000000000001',' PAD1','fixed',100)$$,
  '23514', null, 'a code with surrounding spaces is refused by the table itself');

select * from finish();
rollback;
```

- [ ] **Step 3: Run it to verify it fails**

Run: `supabase test db supabase/tests/42_coupon_management_test.sql`
Expected: FAIL. `create_coupon` and the other functions do not exist yet, so `to_regprocedure(...) is not null` is false and the `regprocedure[]` casts error with `function public.create_coupon(...) does not exist`.

- [ ] **Step 4: Write the migration's normalisation, check and function stubs**

Create `supabase/migrations/0051_coupon_management.sql`:

```sql
-- Coupon management (P1): owners and admins create, edit, deactivate and
-- list their resort's coupons. See
-- docs/superpowers/specs/2026-09-25-p1-coupon-management-design.md.
--
-- Redemption is unchanged: resolve_coupon, get_quote and create_hold
-- (latest in 0045) still match a code exactly. So codes are stored
-- upper-case and trimmed from now on, and the guest's coupon field sends
-- them that way.
--
-- Error code: P0033 coupon_invalid. The message is one reason word:
-- code_invalid, code_taken, kind_required, value_invalid,
-- min_amount_invalid, dates_invalid, usage_limit_invalid,
-- usage_limit_below_used, guest_not_eligible. Also raised: P0002 (unknown
-- coupon), P0005 (missing active flag), P0020 not_a_member, P0022
-- resort_suspended.

-- ---------------------------------------------------------------------
-- Codes are upper-case and trimmed. Existing codes are normalised first.
-- A code whose normalised form would collide with another code at the
-- same resort keeps its spelling, and the check then stays NOT VALID (it
-- still applies to every new or changed row).
update public.coupons c
   set code = upper(btrim(c.code))
 where c.code <> upper(btrim(c.code))
   and not exists (select 1 from public.coupons d
                    where d.property_id = c.property_id
                      and d.id <> c.id
                      and upper(btrim(d.code)) = upper(btrim(c.code)));

alter table public.coupons
  add constraint coupons_code_upper check (code = upper(btrim(code))) not valid;

do $$
begin
  if not exists (select 1 from public.coupons where code <> upper(btrim(code))) then
    alter table public.coupons validate constraint coupons_code_upper;
  end if;
end;
$$;

-- ---------------------------------------------------------------------
-- Coupon functions. The signatures are the contract the app is built
-- against; Tasks 2 and 3 of the plan replace the stub bodies.

-- Every coupon of the resort, for the Coupons screen. Owner/admin of the
-- resort (reads are allowed while it is suspended).
create function public.list_coupons(p_property uuid)
returns table (
  id                uuid,
  code              text,
  kind              public.coupon_kind,
  value             numeric,
  min_booking_value numeric,
  valid_from        date,
  valid_until       date,
  max_redemptions   int,
  redeemed_count    int,
  customer_id       uuid,
  customer_email    text,
  customer_name     text,
  is_active         boolean,
  status            text,
  created_at        timestamptz
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  raise exception 'list_coupons is not implemented yet' using errcode = '0A000';
end;
$$;

-- The guest with this email, if they have booked at the resort.
create function public.find_resort_guest(p_property uuid, p_email text)
returns table (user_id uuid, email text, full_name text)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  raise exception 'find_resort_guest is not implemented yet' using errcode = '0A000';
end;
$$;

create function public.create_coupon(
  p_property    uuid,
  p_code        text,
  p_kind        public.coupon_kind,
  p_value       numeric,
  p_min_amount  numeric default null,
  p_valid_from  date default null,
  p_valid_until date default null,
  p_usage_limit int default null,
  p_customer    uuid default null
) returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  raise exception 'create_coupon is not implemented yet' using errcode = '0A000';
end;
$$;

create function public.update_coupon(
  p_coupon      uuid,
  p_code        text,
  p_kind        public.coupon_kind,
  p_value       numeric,
  p_min_amount  numeric default null,
  p_valid_from  date default null,
  p_valid_until date default null,
  p_usage_limit int default null,
  p_customer    uuid default null
) returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  raise exception 'update_coupon is not implemented yet' using errcode = '0A000';
end;
$$;

create function public.set_coupon_active(p_coupon uuid, p_active boolean)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  raise exception 'set_coupon_active is not implemented yet' using errcode = '0A000';
end;
$$;

revoke execute on function public.list_coupons(uuid) from public, anon;
revoke execute on function public.find_resort_guest(uuid, text) from public, anon;
revoke execute on function public.create_coupon(uuid, text, public.coupon_kind, numeric, numeric, date, date, integer, uuid) from public, anon;
revoke execute on function public.update_coupon(uuid, text, public.coupon_kind, numeric, numeric, date, date, integer, uuid) from public, anon;
revoke execute on function public.set_coupon_active(uuid, boolean) from public, anon;
grant execute on function public.list_coupons(uuid) to authenticated;
grant execute on function public.find_resort_guest(uuid, text) to authenticated;
grant execute on function public.create_coupon(uuid, text, public.coupon_kind, numeric, numeric, date, date, integer, uuid) to authenticated;
grant execute on function public.update_coupon(uuid, text, public.coupon_kind, numeric, numeric, date, date, integer, uuid) to authenticated;
grant execute on function public.set_coupon_active(uuid, boolean) to authenticated;
```

- [ ] **Step 5: Add the five functions to the definer allow-list**

In `supabase/tests/37_tenancy_isolation_test.sql`, replace:

```sql
        'report_collections','report_ledger','report_settlements','finance_summary',
```

with:

```sql
        'report_collections','report_ledger','report_settlements','finance_summary',
        -- 0051: coupons. Each asserts owner/admin at the resort it is
        -- given, or at the coupon's own resort.
        'create_coupon','update_coupon','set_coupon_active','list_coupons',
        'find_resort_guest',
```

- [ ] **Step 6: Run the database tests to verify they pass**

Run: `supabase db reset && supabase test db supabase/tests/42_coupon_management_test.sql supabase/tests/37_tenancy_isolation_test.sql supabase/tests/11_coupons_test.sql`
Expected: PASS. 42 reports 17/17, 37 reports 77/77 and 11 reports 61/61. 11 still passes because every code it inserts is already upper-case.

- [ ] **Step 7: Write the failing Dart model and provider tests**

Create `test/data/coupon_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/data/models/coupon.dart';

import '../support/fake_coupon_source.dart';

void main() {
  group('Coupon.fromJson', () {
    test('reads every column list_coupons returns', () {
      final c = Coupon.fromJson(const {
        'id': 'c1',
        'code': 'SUMMER',
        'kind': 'fixed',
        'value': 500,
        'min_booking_value': 5000,
        'valid_from': '2026-10-01',
        'valid_until': '2026-10-31',
        'max_redemptions': 10,
        'redeemed_count': 3,
        'customer_id': 'g1',
        'customer_email': 'gita@example.com',
        'customer_name': 'Gita Guest',
        'is_active': true,
        'status': 'scheduled',
        'created_at': '2026-09-25T10:00:00+00:00',
      });

      expect(c.id, 'c1');
      expect(c.code, 'SUMMER');
      expect(c.kind, CouponKind.fixed);
      expect(c.value, 500);
      expect(c.minAmount, 5000);
      expect(c.validFrom, DateTime(2026, 10, 1));
      expect(c.validUntil, DateTime(2026, 10, 31));
      expect(c.usageLimit, 10);
      expect(c.usedCount, 3);
      expect(c.guest!.userId, 'g1');
      expect(c.guest!.email, 'gita@example.com');
      expect(c.guest!.fullName, 'Gita Guest');
      expect(c.isActive, isTrue);
      expect(c.status, CouponStatus.scheduled);
      expect(c.createdAt, DateTime.utc(2026, 9, 25, 10));
    });

    test('the optional columns may all be null', () {
      final c = Coupon.fromJson(const {
        'id': 'c2',
        'code': 'SAVE10',
        'kind': 'percent',
        'value': 10,
        'min_booking_value': null,
        'valid_from': null,
        'valid_until': null,
        'max_redemptions': null,
        'redeemed_count': 0,
        'customer_id': null,
        'customer_email': null,
        'customer_name': null,
        'is_active': false,
        'status': 'inactive',
        'created_at': '2026-09-25T10:00:00+00:00',
      });

      expect(c.minAmount, isNull);
      expect(c.validFrom, isNull);
      expect(c.validUntil, isNull);
      expect(c.usageLimit, isNull);
      expect(c.guest, isNull);
      expect(c.isActive, isFalse);
      expect(c.status, CouponStatus.inactive);
    });

    test('every status the server sends is understood, and nothing else', () {
      expect(couponStatusFromDb('active'), CouponStatus.active);
      expect(couponStatusFromDb('scheduled'), CouponStatus.scheduled);
      expect(couponStatusFromDb('expired'), CouponStatus.expired);
      expect(couponStatusFromDb('used_up'), CouponStatus.usedUp);
      expect(couponStatusFromDb('inactive'), CouponStatus.inactive);
      expect(() => couponStatusFromDb('bogus'), throwsArgumentError);
      expect(() => couponKindFromDb('bogus'), throwsArgumentError);
      expect(couponKindToDb(CouponKind.percent), 'percent');
      expect(couponKindToDb(CouponKind.fixed), 'fixed');
    });
  });

  group('display', () {
    test('each status has a label and an icon, never colour alone', () {
      expect(CouponStatus.values.map((s) => s.label),
          ['Active', 'Scheduled', 'Expired', 'Used up', 'Inactive']);
      for (final s in CouponStatus.values) {
        expect(s.icon, isA<IconData>());
      }
    });

    test('discount, minimum, usage and audience lines', () {
      expect(couponRow(value: 10).discountLabel, '10% off');
      expect(couponRow(value: 12.5).discountLabel, '12.5% off');
      expect(couponRow(kind: CouponKind.fixed, value: 500).discountLabel,
          '₹500 off');
      expect(couponRow().minAmountLabel, isNull);
      expect(couponRow(minAmount: 5000).minAmountLabel, 'Min ₹5,000');
      expect(couponRow(usedCount: 3).usageLabel, 'Used 3');
      expect(couponRow(usedCount: 3, usageLimit: 10).usageLabel,
          'Used 3 of 10');
      expect(couponRow().audienceLabel, 'Everyone');
      expect(
          couponRow(
                  guest: const ResortGuest(
                      userId: 'g1',
                      email: 'gita@example.com',
                      fullName: 'Gita Guest'))
              .audienceLabel,
          'Only Gita Guest');
      expect(
          couponRow(
                  guest: const ResortGuest(
                      userId: 'g1', email: 'gita@example.com'))
              .audienceLabel,
          'Only gita@example.com');
    });

    test('validity line for every combination of dates', () {
      expect(couponRow().validityLabel, 'No date limits');
      expect(couponRow(validFrom: DateTime(2026, 10, 1)).validityLabel,
          'From 1 Oct 2026');
      expect(couponRow(validUntil: DateTime(2026, 10, 31)).validityLabel,
          'Until 31 Oct 2026');
      expect(
          couponRow(
                  validFrom: DateTime(2026, 10, 1),
                  validUntil: DateTime(2026, 10, 31))
              .validityLabel,
          '1 Oct 2026 – 31 Oct 2026');
    });
  });

  group('CouponDraft.toParams', () {
    test('sends every field, dates as yyyy-MM-dd', () {
      final draft = CouponDraft(
        code: 'SUMMER',
        kind: CouponKind.fixed,
        value: 500,
        minAmount: 5000,
        validFrom: DateTime(2026, 10, 1),
        validUntil: DateTime(2026, 10, 31),
        usageLimit: 10,
        guestId: 'g1',
      );
      expect(draft.toParams(), {
        'p_code': 'SUMMER',
        'p_kind': 'fixed',
        'p_value': 500,
        'p_min_amount': 5000,
        'p_valid_from': '2026-10-01',
        'p_valid_until': '2026-10-31',
        'p_usage_limit': 10,
        'p_customer': 'g1',
      });
    });

    test('sends nulls too: an update replaces the whole coupon', () {
      const draft =
          CouponDraft(code: 'SAVE10', kind: CouponKind.percent, value: 10);
      expect(draft.toParams(), {
        'p_code': 'SAVE10',
        'p_kind': 'percent',
        'p_value': 10,
        'p_min_amount': null,
        'p_valid_from': null,
        'p_valid_until': null,
        'p_usage_limit': null,
        'p_customer': null,
      });
    });
  });

  test('the code rule matches the server', () {
    expect(normalizeCouponCode('  summer-10 '), 'SUMMER-10');
    expect(couponCodePattern.hasMatch('SUMMER-10'), isTrue);
    expect(couponCodePattern.hasMatch('A_1'), isTrue);
    expect(couponCodePattern.hasMatch('AB'), isFalse);
    expect(couponCodePattern.hasMatch('SAVE 10'), isFalse);
    expect(couponCodePattern.hasMatch('-SAVE'), isFalse);
    expect(couponCodePattern.hasMatch('save10'), isFalse);
    expect(couponCodePattern.hasMatch('A' * 24), isTrue);
    expect(couponCodePattern.hasMatch('A' * 25), isFalse);
  });
}
```

Create `test/data/coupon_provider_test.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/data/repositories/coupon_repository.dart';

import '../support/fake_coupon_source.dart';

void main() {
  test('couponsProvider lists the coupons of the resort it is keyed by',
      () async {
    final source = FakeCouponSource()..coupons = [couponRow(id: 'c1')];
    final container = ProviderContainer(
      overrides: [couponSourceProvider.overrideWithValue(source)],
    );
    addTearDown(container.dispose);
    final sub = container.listen(couponsProvider('p1'), (_, _) {});
    addTearDown(sub.close);

    final rows = await container.read(couponsProvider('p1').future);

    expect(rows.single.id, 'c1');
    expect(source.listCalls, ['p1']);
  });
}
```

- [ ] **Step 8: Run them to verify they fail**

Run: `flutter test test/data/coupon_test.dart test/data/coupon_provider_test.dart`
Expected: FAIL to compile with `Target of URI doesn't exist: 'package:pasala/data/models/coupon.dart'` (and the same for the repository and the fake).

- [ ] **Step 9: Write the model**

Create `lib/data/models/coupon.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/format.dart';

/// `public.coupon_kind`: a percentage off, or a fixed rupee amount off.
enum CouponKind { percent, fixed }

/// Unknown text is rejected rather than defaulted -- a silent fallback
/// would hide a server/app mismatch.
CouponKind couponKindFromDb(String raw) => switch (raw) {
  'percent' => CouponKind.percent,
  'fixed' => CouponKind.fixed,
  _ => throw ArgumentError('Unknown coupon kind: $raw'),
};

/// Inverse of [couponKindFromDb].
String couponKindToDb(CouponKind kind) => switch (kind) {
  CouponKind.percent => 'percent',
  CouponKind.fixed => 'fixed',
};

/// Where a coupon stands right now. Worked out by `list_coupons`
/// (0051_coupon_management.sql) in the order `resolve_coupon` checks at
/// booking time: inactive, expired, not yet valid, used up, else active.
enum CouponStatus { active, scheduled, expired, usedUp, inactive }

CouponStatus couponStatusFromDb(String raw) => switch (raw) {
  'active' => CouponStatus.active,
  'scheduled' => CouponStatus.scheduled,
  'expired' => CouponStatus.expired,
  'used_up' => CouponStatus.usedUp,
  'inactive' => CouponStatus.inactive,
  _ => throw ArgumentError('Unknown coupon status: $raw'),
};

/// Label, icon and colour for a [CouponStatus]. The icon and the label
/// always travel with the colour: a status is never told by colour alone.
extension CouponStatusDisplay on CouponStatus {
  String get label => switch (this) {
    CouponStatus.active => 'Active',
    CouponStatus.scheduled => 'Scheduled',
    CouponStatus.expired => 'Expired',
    CouponStatus.usedUp => 'Used up',
    CouponStatus.inactive => 'Inactive',
  };

  IconData get icon => switch (this) {
    CouponStatus.active => Icons.check_circle_outline,
    CouponStatus.scheduled => Icons.schedule,
    CouponStatus.expired => Icons.event_busy_outlined,
    CouponStatus.usedUp => Icons.do_not_disturb_on_outlined,
    CouponStatus.inactive => Icons.pause_circle_outline,
  };

  Color get color => switch (this) {
    CouponStatus.active => const Color(0xFF2E7D32),
    CouponStatus.scheduled => const Color(0xFF1565C0),
    CouponStatus.expired => const Color(0xFF616161),
    CouponStatus.usedUp => const Color(0xFFB26A00),
    CouponStatus.inactive => const Color(0xFF616161),
  };
}

/// The code rule `coupon_check_input` enforces, applied after
/// [normalizeCouponCode]: 3-24 characters from A-Z, 0-9, `-` and `_`,
/// starting with a letter or digit.
final couponCodePattern = RegExp(r'^[A-Z0-9][A-Z0-9_-]{2,23}$');

/// Codes are stored trimmed and upper-case (`coupons_code_upper`).
String normalizeCouponCode(String raw) => raw.trim().toUpperCase();

final _isoDay = DateFormat('yyyy-MM-dd');

String? _isoDayOrNull(DateTime? day) =>
    day == null ? null : _isoDay.format(day);

DateTime? _dayOrNull(Object? raw) =>
    raw == null ? null : DateTime.parse(raw as String);

/// A guest who has booked at the resort, as `find_resort_guest` returns
/// them -- or the guest a coupon is restricted to.
class ResortGuest {
  const ResortGuest({required this.userId, required this.email, this.fullName});

  factory ResortGuest.fromJson(Map<String, dynamic> json) => ResortGuest(
    userId: json['user_id'] as String,
    email: json['email'] as String,
    fullName: json['full_name'] as String?,
  );

  final String userId;
  final String email;
  final String? fullName;

  /// The full name, or the email for an account without one.
  String get name {
    final trimmed = fullName?.trim() ?? '';
    return trimmed.isEmpty ? email : trimmed;
  }
}

/// One row of `list_coupons(p_property)`. [validFrom] and [validUntil] are
/// calendar days in the resort's time zone; [usedCount] is the server's
/// `redeemed_count` (live holds included, released holds given back).
class Coupon {
  const Coupon({
    required this.id,
    required this.code,
    required this.kind,
    required this.value,
    this.minAmount,
    this.validFrom,
    this.validUntil,
    this.usageLimit,
    this.usedCount = 0,
    this.guest,
    this.isActive = true,
    this.status = CouponStatus.active,
    required this.createdAt,
  });

  factory Coupon.fromJson(Map<String, dynamic> json) {
    final guestId = json['customer_id'] as String?;
    return Coupon(
      id: json['id'] as String,
      code: json['code'] as String,
      kind: couponKindFromDb(json['kind'] as String),
      value: json['value'] as num,
      minAmount: json['min_booking_value'] as num?,
      validFrom: _dayOrNull(json['valid_from']),
      validUntil: _dayOrNull(json['valid_until']),
      usageLimit: json['max_redemptions'] as int?,
      usedCount: json['redeemed_count'] as int,
      guest: guestId == null
          ? null
          : ResortGuest(
              userId: guestId,
              email: json['customer_email'] as String? ?? '',
              fullName: json['customer_name'] as String?,
            ),
      isActive: json['is_active'] as bool,
      status: couponStatusFromDb(json['status'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  final String id;
  final String code;
  final CouponKind kind;
  final num value;
  final num? minAmount;
  final DateTime? validFrom;
  final DateTime? validUntil;
  final int? usageLimit;
  final int usedCount;
  final ResortGuest? guest;
  final bool isActive;
  final CouponStatus status;
  final DateTime createdAt;

  String get discountLabel => switch (kind) {
    CouponKind.percent => '${formatPct(value)}% off',
    CouponKind.fixed => '${formatInr(value)} off',
  };

  String? get minAmountLabel =>
      minAmount == null ? null : 'Min ${formatInr(minAmount!)}';

  String get validityLabel => switch ((validFrom, validUntil)) {
    (null, null) => 'No date limits',
    (final DateTime from, null) => 'From ${formatDate(from)}',
    (null, final DateTime until) => 'Until ${formatDate(until)}',
    (final DateTime from, final DateTime until) =>
      '${formatDate(from)} – ${formatDate(until)}',
  };

  String get usageLabel => usageLimit == null
      ? 'Used $usedCount'
      : 'Used $usedCount of $usageLimit';

  String get audienceLabel => guest == null ? 'Everyone' : 'Only ${guest!.name}';
}

/// What the form sends to `create_coupon` / `update_coupon`. [validFrom]
/// and [validUntil] are calendar days; the server turns them into whole
/// days in the resort's time zone.
class CouponDraft {
  const CouponDraft({
    required this.code,
    required this.kind,
    required this.value,
    this.minAmount,
    this.validFrom,
    this.validUntil,
    this.usageLimit,
    this.guestId,
  });

  final String code;
  final CouponKind kind;
  final num value;
  final num? minAmount;
  final DateTime? validFrom;
  final DateTime? validUntil;
  final int? usageLimit;
  final String? guestId;

  /// The parameters `create_coupon` and `update_coupon` share. Every key is
  /// always sent, nulls included: an update replaces the whole coupon.
  Map<String, dynamic> toParams() => {
    'p_code': code,
    'p_kind': couponKindToDb(kind),
    'p_value': value,
    'p_min_amount': minAmount,
    'p_valid_from': _isoDayOrNull(validFrom),
    'p_valid_until': _isoDayOrNull(validUntil),
    'p_usage_limit': usageLimit,
    'p_customer': guestId,
  };
}
```

- [ ] **Step 10: Write the repository, seam and providers**

Create `lib/data/repositories/coupon_repository.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors.dart';
import '../../core/supabase_client.dart';
import '../models/coupon.dart';

/// The slice of [CouponRepository] the Coupons screen and its form need.
/// Tests override [couponSourceProvider] with `FakeCouponSource`
/// (test/support/fake_coupon_source.dart) instead of a real client.
abstract class CouponSource {
  Future<List<Coupon>> list(String propertyId);

  /// Returns the new coupon's id.
  Future<String> create(String propertyId, CouponDraft draft);
  Future<void> update(String couponId, CouponDraft draft);
  Future<void> setActive(String couponId, bool active);

  /// The guest with this email who has booked at [propertyId], or null.
  Future<ResortGuest?> findGuest(String propertyId, String email);
}

/// Backs the Coupons screen through the five functions in
/// 0051_coupon_management.sql. Each checks the caller's role at the resort
/// server-side, so this repository checks nothing itself; refusals arrive
/// as P0002/P0020/P0022/P0033 through [mapPostgrestError].
class CouponRepository implements CouponSource {
  CouponRepository(this._db);
  final SupabaseClient _db;

  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } catch (e) {
      throw mapPostgrestError(e);
    }
  }

  @override
  Future<List<Coupon>> list(String propertyId) => _guard(() async {
    final rows =
        await _db.rpc('list_coupons', params: {'p_property': propertyId})
            as List<dynamic>;
    return rows
        .map((e) => Coupon.fromJson(e as Map<String, dynamic>))
        .toList();
  });

  @override
  Future<String> create(String propertyId, CouponDraft draft) =>
      _guard(() async {
        final id = await _db.rpc(
          'create_coupon',
          params: {'p_property': propertyId, ...draft.toParams()},
        );
        return id as String;
      });

  @override
  Future<void> update(String couponId, CouponDraft draft) => _guard(() async {
    await _db.rpc(
      'update_coupon',
      params: {'p_coupon': couponId, ...draft.toParams()},
    );
  });

  @override
  Future<void> setActive(String couponId, bool active) => _guard(() async {
    await _db.rpc(
      'set_coupon_active',
      params: {'p_coupon': couponId, 'p_active': active},
    );
  });

  @override
  Future<ResortGuest?> findGuest(String propertyId, String email) =>
      _guard(() async {
        final rows =
            await _db.rpc(
                  'find_resort_guest',
                  params: {'p_property': propertyId, 'p_email': email.trim()},
                )
                as List<dynamic>;
        if (rows.isEmpty) return null;
        return ResortGuest.fromJson(rows.first as Map<String, dynamic>);
      });
}

final couponRepositoryProvider = Provider<CouponRepository>(
  (ref) => CouponRepository(ref.watch(supabaseProvider)),
);

/// The [CouponSource] seam every screen calls through.
final couponSourceProvider = Provider<CouponSource>(
  (ref) => ref.watch(couponRepositoryProvider),
);

/// The coupons of one resort, keyed by property id so switching resort
/// never shows another resort's coupons. `autoDispose`: the list refetches
/// every time the screen is opened, and the screen invalidates it after
/// its own writes.
final couponsProvider = FutureProvider.autoDispose
    .family<List<Coupon>, String>(
      (ref, propertyId) => ref.watch(couponSourceProvider).list(propertyId),
    );
```

- [ ] **Step 11: Write the test fake**

Create `test/support/fake_coupon_source.dart`:

```dart
import 'package:pasala/data/models/coupon.dart';
import 'package:pasala/data/repositories/coupon_repository.dart';

/// In-memory [CouponSource]. Set [coupons]/[guests] for what the server
/// would return, an `...Error` to make that call throw, and read the call
/// logs to assert what a screen asked for.
class FakeCouponSource implements CouponSource {
  List<Coupon> coupons = [];

  /// Guests [findGuest] knows, keyed by the exact email it is asked for.
  Map<String, ResortGuest> guests = {};
  Object? listError;
  Object? createError;
  Object? updateError;
  Object? setActiveError;
  Object? findGuestError;

  final List<String> listCalls = [];
  final List<(String, CouponDraft)> createCalls = [];
  final List<(String, CouponDraft)> updateCalls = [];
  final List<(String, bool)> setActiveCalls = [];
  final List<(String, String)> findGuestCalls = [];

  @override
  Future<List<Coupon>> list(String propertyId) async {
    listCalls.add(propertyId);
    if (listError != null) throw listError!;
    return coupons;
  }

  @override
  Future<String> create(String propertyId, CouponDraft draft) async {
    createCalls.add((propertyId, draft));
    if (createError != null) throw createError!;
    return 'coupon-new';
  }

  @override
  Future<void> update(String couponId, CouponDraft draft) async {
    updateCalls.add((couponId, draft));
    if (updateError != null) throw updateError!;
  }

  @override
  Future<void> setActive(String couponId, bool active) async {
    setActiveCalls.add((couponId, active));
    if (setActiveError != null) throw setActiveError!;
  }

  @override
  Future<ResortGuest?> findGuest(String propertyId, String email) async {
    findGuestCalls.add((propertyId, email));
    if (findGuestError != null) throw findGuestError!;
    return guests[email];
  }
}

/// A coupon with defaults for a plain, active 10% code for everyone;
/// override only what a test is about.
Coupon couponRow({
  String id = 'c1',
  String code = 'SAVE10',
  CouponKind kind = CouponKind.percent,
  num value = 10,
  num? minAmount,
  DateTime? validFrom,
  DateTime? validUntil,
  int? usageLimit,
  int usedCount = 0,
  ResortGuest? guest,
  bool isActive = true,
  CouponStatus status = CouponStatus.active,
}) => Coupon(
  id: id,
  code: code,
  kind: kind,
  value: value,
  minAmount: minAmount,
  validFrom: validFrom,
  validUntil: validUntil,
  usageLimit: usageLimit,
  usedCount: usedCount,
  guest: guest,
  isActive: isActive,
  status: status,
  createdAt: DateTime.utc(2026, 9, 1),
);
```

- [ ] **Step 12: Run the Dart tests to verify they pass**

Run: `flutter test test/data/coupon_test.dart test/data/coupon_provider_test.dart && flutter analyze lib/data/models/coupon.dart lib/data/repositories/coupon_repository.dart test/support/fake_coupon_source.dart`
Expected: all tests pass; `No issues found!`.

- [ ] **Step 13: Commit**

```bash
git add supabase/migrations/0051_coupon_management.sql supabase/tests/42_coupon_management_test.sql \
  supabase/tests/37_tenancy_isolation_test.sql lib/data/models/coupon.dart \
  lib/data/repositories/coupon_repository.dart test/support/fake_coupon_source.dart \
  test/data/coupon_test.dart test/data/coupon_provider_test.dart
git commit -m "$(cat <<'EOF'
feat(coupons): contract for coupon management

Upper-case coupon codes (normalised, with a table check), stubs for
list_coupons, find_resort_guest, create_coupon, update_coupon and
set_coupon_active with their grants and allow-list entries, and the
Dart Coupon model, CouponSource seam, providers and test fake.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

## Phase 1: Database track (Tasks 2 → 3, sequential)

### Task 2: `create_coupon`, `update_coupon`, `set_coupon_active`

**Track:** DB. Depends on Task 1.

**Files:**
- Modify: `supabase/migrations/0051_coupon_management.sql` (the helpers are new; the three write stubs are replaced)
- Test: `supabase/tests/42_coupon_management_test.sql`

**Interfaces:**
- Consumes:
  - From Task 1: the stubs and fixtures.
  - `public.assert_resort_role` (0043).
  - `public.audit_log (actor_id, entity, entity_id, action, before, after, property_id)` (0006, `property_id` since 0043).
  - `public.get_quote(uuid, tstzrange, int, uuid, text)` (latest in 0045) as the unchanged redemption check.
- Produces:
  - `public.is_resort_guest(p_property uuid, p_user uuid) returns boolean`, with invoker rights and internal use only.
  - `public.coupon_check_input(p_property uuid, p_code text, p_kind public.coupon_kind, p_value numeric, p_min_amount numeric, p_valid_from date, p_valid_until date, p_usage_limit int, p_customer uuid) returns text`, with invoker rights and internal use only. It returns the normalised code. A null `p_customer` skips the guest check.
  - Working `create_coupon`, `update_coupon` and `set_coupon_active` with the Task 1 signatures. Audit actions: `create`, `update`, `activate`, `deactivate`, with entity `coupon`.

- [ ] **Step 1: Write the failing tests**

In `supabase/tests/42_coupon_management_test.sql`, change `select plan(17);` to `select plan(62);`. Then insert this block directly above `select * from finish();`:

```sql
-- === Task 2: create, update, activate ======================================

select is((select array_agg(p.proname::text order by p.proname)
             from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'public'
              and p.proname in ('coupon_check_input', 'is_resort_guest')
              and not p.prosecdef
              and not has_function_privilege('authenticated', p.oid, 'execute')
              and not has_function_privilege('anon', p.oid, 'execute')),
  array['coupon_check_input', 'is_resort_guest'],
  'the input check and the guest rule are internal helpers nobody calls directly');

set local role authenticated;
set local request.jwt.claims to '{"sub":"c0000000-0000-0000-0000-000000000002","role":"authenticated"}';

select ok(public.create_coupon('c1000000-0000-4000-8000-000000000001', '  save10 ', 'percent', 10) is not null,
  'an admin creates a coupon and gets its id back');
select is((select code from public.coupons
            where property_id = 'c1000000-0000-4000-8000-000000000001'
              and kind = 'percent' and value = 10),
  'SAVE10', 'the code is trimmed and upper-cased');
select lives_ok($$select public.create_coupon('c1000000-0000-4000-8000-000000000001', 'SUMMER', 'fixed', 500,
    5000, '2026-10-01', '2026-10-31', 10, 'c0000000-0000-0000-0000-000000000006')$$,
  'an admin creates a coupon with every field, for a guest who booked here');
select is((select min_booking_value || '|' || max_redemptions || '|' || customer_id || '|' ||
                  (valid_from at time zone 'Asia/Kolkata') || '|' ||
                  (valid_to at time zone 'Asia/Kolkata')
             from public.coupons
            where property_id = 'c1000000-0000-4000-8000-000000000001' and code = 'SUMMER'),
  '5000.00|10|c0000000-0000-0000-0000-000000000006|2026-10-01 00:00:00|2026-10-31 23:59:59.999999',
  'valid from/until cover whole days in the resort''s time zone');

select throws_ok($$select public.create_coupon('c1000000-0000-4000-8000-000000000001', 'AB', 'percent', 10)$$,
  'P0033', 'code_invalid', 'a two-character code is refused');
select throws_ok($$select public.create_coupon('c1000000-0000-4000-8000-000000000001', 'SAVE 20', 'percent', 10)$$,
  'P0033', 'code_invalid', 'a code with a space inside is refused');
select throws_ok($$select public.create_coupon('c1000000-0000-4000-8000-000000000001', 'ZERO', 'fixed', 0)$$,
  'P0033', 'value_invalid', 'a zero discount is refused');
select throws_ok($$select public.create_coupon('c1000000-0000-4000-8000-000000000001', 'MOST', 'percent', 101)$$,
  'P0033', 'value_invalid', 'a percentage above 100 is refused');
select throws_ok($$select public.create_coupon('c1000000-0000-4000-8000-000000000001', 'NOKIND', null, 10)$$,
  'P0033', 'kind_required', 'a coupon needs a kind');
select throws_ok($$select public.create_coupon('c1000000-0000-4000-8000-000000000001', 'NEGMIN', 'fixed', 100, -1)$$,
  'P0033', 'min_amount_invalid', 'a negative minimum is refused');
select throws_ok($$select public.create_coupon('c1000000-0000-4000-8000-000000000001', 'BACKWARD', 'fixed', 100,
    null, '2026-10-10', '2026-10-01')$$,
  'P0033', 'dates_invalid', 'an end date before the start date is refused');
select lives_ok($$select public.create_coupon('c1000000-0000-4000-8000-000000000001', 'ONEDAY', 'fixed', 100,
    null, '2026-10-10', '2026-10-10')$$,
  'a coupon valid for one day is fine');
select throws_ok($$select public.create_coupon('c1000000-0000-4000-8000-000000000001', 'NOUSE', 'fixed', 100,
    null, null, null, 0)$$,
  'P0033', 'usage_limit_invalid', 'a usage limit of 0 is refused');
select throws_ok($$select public.create_coupon('c1000000-0000-4000-8000-000000000001', 'FOROLU', 'fixed', 100,
    null, null, null, null, 'c0000000-0000-0000-0000-000000000007')$$,
  'P0033', 'guest_not_eligible', 'a guest who booked only at another resort cannot be chosen');
select throws_ok($$select public.create_coupon('c1000000-0000-4000-8000-000000000001', 'FORHANA', 'fixed', 100,
    null, null, null, null, 'c0000000-0000-0000-0000-000000000008')$$,
  'P0033', 'guest_not_eligible', 'a guest with only a hold cannot be chosen');
select throws_ok($$select public.create_coupon('c1000000-0000-4000-8000-000000000001', 'FORKIRAN', 'fixed', 100,
    null, null, null, null, 'c0000000-0000-0000-0000-000000000009')$$,
  'P0033', 'guest_not_eligible', 'a guest whose only booking was cancelled cannot be chosen');
select throws_ok($$select public.create_coupon('c1000000-0000-4000-8000-000000000001', 'save10', 'fixed', 100)$$,
  'P0033', 'code_taken', 'a code already used at this resort is refused, whatever its case');

set local request.jwt.claims to '{"sub":"c0000000-0000-0000-0000-000000000003","role":"authenticated"}';
select throws_ok($$select public.create_coupon('c1000000-0000-4000-8000-000000000001', 'STAFF1', 'fixed', 100)$$,
  'P0020', null, 'staff cannot create coupons');
set local request.jwt.claims to '{"sub":"c0000000-0000-0000-0000-000000000004","role":"authenticated"}';
select throws_ok($$select public.create_coupon('c1000000-0000-4000-8000-000000000001', 'ACCT1', 'fixed', 100)$$,
  'P0020', null, 'an accountant cannot create coupons');
set local request.jwt.claims to '{"sub":"c0000000-0000-0000-0000-000000000006","role":"authenticated"}';
select throws_ok($$select public.create_coupon('c1000000-0000-4000-8000-000000000001', 'GUEST1', 'fixed', 100)$$,
  'P0020', null, 'a guest cannot create coupons');
set local request.jwt.claims to '{"sub":"c0000000-0000-0000-0000-00000000000a","role":"authenticated"}';
select throws_ok($$select public.create_coupon('c1000000-0000-4000-8000-000000000001', 'PLAT1', 'fixed', 100)$$,
  'P0020', null, 'the platform admin cannot create coupons at a resort');
set local request.jwt.claims to '{"sub":"c0000000-0000-0000-0000-000000000001","role":"authenticated"}';
select lives_ok($$select public.create_coupon('c1000000-0000-4000-8000-000000000001', 'OWNER1', 'fixed', 250)$$,
  'the owner creates coupons');
set local request.jwt.claims to '{"sub":"c0000000-0000-0000-0000-000000000005","role":"authenticated"}';
select lives_ok($$select public.create_coupon('c1000000-0000-4000-8000-000000000002', 'SAVE10', 'percent', 5)$$,
  'another resort can use the same code');
select throws_ok($$select public.create_coupon('c1000000-0000-4000-8000-000000000001', 'SNEAKY', 'fixed', 100)$$,
  'P0020', null, 'another resort''s owner cannot create coupons here');

set local request.jwt.claims to '{"sub":"c0000000-0000-0000-0000-000000000002","role":"authenticated"}';
select lives_ok($$select public.update_coupon(
    (select id from public.coupons
      where property_id = 'c1000000-0000-4000-8000-000000000001' and code = 'SAVE10'),
    'save15', 'percent', 15)$$,
  'an admin edits a coupon');
select is((select code || '|' || value || '|' || coalesce(max_redemptions::text, 'none')
             from public.coupons
            where property_id = 'c1000000-0000-4000-8000-000000000001'
              and kind = 'percent' and value = 15),
  'SAVE15|15.00|none', 'the edit replaced the code and the value');
select throws_ok($$select public.update_coupon('c1000000-0000-4000-8000-000000000031', 'OLD5', 'fixed', 500,
    null, null, null, 2)$$,
  'P0033', 'usage_limit_below_used', 'the usage limit cannot drop below the 3 uses already taken');
select lives_ok($$select public.update_coupon('c1000000-0000-4000-8000-000000000031', 'OLD5', 'fixed', 500,
    null, null, null, 3)$$,
  'the usage limit can equal the uses already taken');
select lives_ok($$select public.update_coupon('c1000000-0000-4000-8000-000000000032', 'KIRANVIP', 'percent', 25,
    null, null, null, null, 'c0000000-0000-0000-0000-000000000009')$$,
  'a coupon keeps the guest it already had, even one who could not be chosen today');
select throws_ok($$select public.update_coupon('c1000000-0000-4000-8000-000000000032', 'KIRANVIP', 'percent', 25,
    null, null, null, null, 'c0000000-0000-0000-0000-000000000008')$$,
  'P0033', 'guest_not_eligible', 'switching to a guest who never booked here is refused');
select throws_ok($$select public.update_coupon('c1000000-0000-4000-8000-0000000000ff', 'NOPE', 'fixed', 1)$$,
  'P0002', null, 'editing an unknown coupon is P0002');
select throws_ok($$select public.update_coupon('c1000000-0000-4000-8000-000000000031', 'OWNER1', 'fixed', 500,
    null, null, null, 3)$$,
  'P0033', 'code_taken', 'renaming onto another coupon''s code is refused');
set local request.jwt.claims to '{"sub":"c0000000-0000-0000-0000-000000000003","role":"authenticated"}';
select throws_ok($$select public.update_coupon('c1000000-0000-4000-8000-000000000031', 'OLD5', 'fixed', 1)$$,
  'P0020', null, 'staff cannot edit coupons');
set local request.jwt.claims to '{"sub":"c0000000-0000-0000-0000-000000000005","role":"authenticated"}';
select throws_ok($$select public.update_coupon('c1000000-0000-4000-8000-000000000031', 'OLD5', 'fixed', 1)$$,
  'P0020', null, 'another resort''s owner cannot edit this resort''s coupons');

set local request.jwt.claims to '{"sub":"c0000000-0000-0000-0000-000000000002","role":"authenticated"}';
select lives_ok($$select public.set_coupon_active(
    (select id from public.coupons
      where property_id = 'c1000000-0000-4000-8000-000000000001' and code = 'SAVE15'), false)$$,
  'an admin deactivates a coupon');
select is((select is_active from public.coupons
            where property_id = 'c1000000-0000-4000-8000-000000000001' and code = 'SAVE15'),
  false, 'the coupon is now inactive');
set local request.jwt.claims to '{"sub":"c0000000-0000-0000-0000-000000000006","role":"authenticated"}';
select throws_ok($$select public.get_quote('c1000000-0000-4000-8000-000000000011',
    tstzrange(now() + interval '40 days', now() + interval '41 days', '[)'), 2, null, 'SAVE15')$$,
  'P0010', null, 'a guest cannot apply a deactivated coupon');
set local request.jwt.claims to '{"sub":"c0000000-0000-0000-0000-000000000002","role":"authenticated"}';
select lives_ok($$select public.set_coupon_active(
    (select id from public.coupons
      where property_id = 'c1000000-0000-4000-8000-000000000001' and code = 'SAVE15'), true)$$,
  'an admin reactivates it');
set local request.jwt.claims to '{"sub":"c0000000-0000-0000-0000-000000000006","role":"authenticated"}';
select is((public.get_quote('c1000000-0000-4000-8000-000000000011',
             tstzrange(now() + interval '40 days', now() + interval '41 days', '[)'), 2, null, 'SAVE15')
           -> 'coupon' ->> 'discount')::numeric,
  1500::numeric, 'a coupon made here applies through the unchanged get_quote: 15% of 10,000');
set local request.jwt.claims to '{"sub":"c0000000-0000-0000-0000-000000000003","role":"authenticated"}';
select throws_ok($$select public.set_coupon_active('c1000000-0000-4000-8000-000000000031', false)$$,
  'P0020', null, 'staff cannot deactivate coupons');
set local request.jwt.claims to '{"sub":"c0000000-0000-0000-0000-000000000002","role":"authenticated"}';
select throws_ok($$select public.set_coupon_active('c1000000-0000-4000-8000-0000000000ff', false)$$,
  'P0002', null, 'deactivating an unknown coupon is P0002');
select throws_ok($$select public.set_coupon_active('c1000000-0000-4000-8000-000000000031', null)$$,
  'P0005', null, 'set_coupon_active needs true or false');

reset role;
set local request.jwt.claims to '';
select is((select array_agg(a.action order by a.id)
             from public.audit_log a
             join public.coupons c on c.id = a.entity_id
            where a.entity = 'coupon'
              and c.property_id = 'c1000000-0000-4000-8000-000000000001'
              and c.code = 'SAVE15'),
  array['create','update','deactivate','activate'], 'every change to a coupon is audited');
select is((select count(*)::int from public.audit_log
            where entity = 'coupon'
              and property_id = 'c1000000-0000-4000-8000-000000000001'
              and actor_id is null),
  0, 'every coupon audit row names who made the change');
```

- [ ] **Step 2: Run it to verify it fails**

Run: `supabase test db supabase/tests/42_coupon_management_test.sql`
Expected: FAIL. The first new assertion returns `null` because the helpers do not exist, and `create_coupon` raises `0A000 create_coupon is not implemented yet`.

- [ ] **Step 3: Add the two internal helpers**

In `supabase/migrations/0051_coupon_management.sql`, insert this block directly above the `-- Coupon functions. The signatures are the contract ...` comment block:

```sql
-- ---------------------------------------------------------------------
-- Internal helpers, run with invoker rights. Only the security definer
-- functions below call them, so they run as those functions' owner.
-- Nobody else can execute them.

-- A guest the resort can restrict a coupon to: someone with a real
-- booking there (confirmed, in house or checked out). Holds, pending
-- payments and cancelled bookings do not count.
create function public.is_resort_guest(p_property uuid, p_user uuid)
returns boolean
language sql
stable
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.reservations r
     where r.property_id = p_property
       and r.customer_id = p_user
       and r.kind = 'booking'
       and r.status in ('confirmed', 'checked_in', 'checked_out'));
$$;

-- Checks what create_coupon/update_coupon were given and returns the code
-- normalised (trimmed, upper-case). Raises P0033 with one reason word.
-- p_customer is checked only when given: update_coupon passes null when
-- the coupon keeps the guest it already had.
create function public.coupon_check_input(
  p_property    uuid,
  p_code        text,
  p_kind        public.coupon_kind,
  p_value       numeric,
  p_min_amount  numeric,
  p_valid_from  date,
  p_valid_until date,
  p_usage_limit int,
  p_customer    uuid
) returns text
language plpgsql
stable
set search_path = public, pg_temp
as $$
declare
  v_code text := upper(btrim(coalesce(p_code, '')));
begin
  if v_code !~ '^[A-Z0-9][A-Z0-9_-]{2,23}$' then
    raise exception using errcode = 'P0033', message = 'code_invalid';
  end if;
  if p_kind is null then
    raise exception using errcode = 'P0033', message = 'kind_required';
  end if;
  -- numeric(12,2) holds values below 10^10; anything larger would fail
  -- the insert with a raw overflow instead of a readable reason.
  if p_value is null or p_value <= 0 or p_value >= 10000000000
     or (p_kind = 'percent' and p_value > 100) then
    raise exception using errcode = 'P0033', message = 'value_invalid';
  end if;
  if p_min_amount is not null and (p_min_amount < 0 or p_min_amount >= 10000000000) then
    raise exception using errcode = 'P0033', message = 'min_amount_invalid';
  end if;
  if p_valid_from is not null and p_valid_until is not null
     and p_valid_until < p_valid_from then
    raise exception using errcode = 'P0033', message = 'dates_invalid';
  end if;
  if p_usage_limit is not null and p_usage_limit < 1 then
    raise exception using errcode = 'P0033', message = 'usage_limit_invalid';
  end if;
  if p_customer is not null
     and not public.is_resort_guest(p_property, p_customer) then
    raise exception using errcode = 'P0033', message = 'guest_not_eligible';
  end if;
  return v_code;
end;
$$;

revoke execute on function public.is_resort_guest(uuid, uuid) from public, anon, authenticated;
revoke execute on function public.coupon_check_input(uuid, text, public.coupon_kind, numeric, numeric, date, date, integer, uuid)
  from public, anon, authenticated;
```

- [ ] **Step 4: Replace the `create_coupon` stub**

In the same file, replace the whole `create function public.create_coupon(...) ... $$;` stub with:

```sql
-- A new coupon at p_property. Owner/admin there, and the resort must be
-- active (P0022 when suspended). Valid from/until are whole days in the
-- resort's time zone: 00:00 on the first day to the last microsecond of
-- the last.
create function public.create_coupon(
  p_property    uuid,
  p_code        text,
  p_kind        public.coupon_kind,
  p_value       numeric,
  p_min_amount  numeric default null,
  p_valid_from  date default null,
  p_valid_until date default null,
  p_usage_limit int default null,
  p_customer    uuid default null
) returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_code text;
  v_tz   text;
  v_row  public.coupons;
begin
  perform public.assert_resort_role(p_property, true, 'owner', 'admin');

  v_code := public.coupon_check_input(p_property, p_code, p_kind, p_value,
              p_min_amount, p_valid_from, p_valid_until, p_usage_limit, p_customer);

  select p.timezone into v_tz from public.properties p where p.id = p_property;

  begin
    insert into public.coupons
      (property_id, code, kind, value, min_booking_value, valid_from, valid_to,
       max_redemptions, customer_id)
    values
      (p_property, v_code, p_kind, p_value, p_min_amount,
       p_valid_from::timestamp at time zone v_tz,
       (p_valid_until + 1)::timestamp at time zone v_tz - interval '1 microsecond',
       p_usage_limit, p_customer)
    returning * into v_row;
  exception when unique_violation then
    raise exception using errcode = 'P0033', message = 'code_taken';
  end;

  insert into public.audit_log (actor_id, entity, entity_id, action, before, after, property_id)
  values (auth.uid(), 'coupon', v_row.id, 'create', null, to_jsonb(v_row), p_property);

  return v_row.id;
end;
$$;
```

- [ ] **Step 5: Replace the `update_coupon` stub**

Replace the whole `create function public.update_coupon(...) ... $$;` stub with:

```sql
-- Replaces every field of one coupon (a null clears that optional field).
-- The resort comes from the coupon row. The usage-limit floor sits in the
-- UPDATE's WHERE: create_hold increments redeemed_count under the same
-- row lock, so a booking cannot slip between the check and the write.
create function public.update_coupon(
  p_coupon      uuid,
  p_code        text,
  p_kind        public.coupon_kind,
  p_value       numeric,
  p_min_amount  numeric default null,
  p_valid_from  date default null,
  p_valid_until date default null,
  p_usage_limit int default null,
  p_customer    uuid default null
) returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_old  public.coupons;
  v_new  public.coupons;
  v_code text;
  v_tz   text;
begin
  select * into v_old from public.coupons where id = p_coupon;
  if not found then
    raise exception using errcode = 'P0002', message = 'not_found';
  end if;
  perform public.assert_resort_role(v_old.property_id, true, 'owner', 'admin');

  -- A guest the coupon already has is not checked again: their booking
  -- may have been cancelled since, and that must not block other edits.
  v_code := public.coupon_check_input(v_old.property_id, p_code, p_kind, p_value,
              p_min_amount, p_valid_from, p_valid_until, p_usage_limit,
              case when p_customer is distinct from v_old.customer_id
                   then p_customer end);

  select p.timezone into v_tz from public.properties p where p.id = v_old.property_id;

  begin
    update public.coupons
       set code              = v_code,
           kind              = p_kind,
           value             = p_value,
           min_booking_value = p_min_amount,
           valid_from        = p_valid_from::timestamp at time zone v_tz,
           valid_to          = (p_valid_until + 1)::timestamp at time zone v_tz
                                 - interval '1 microsecond',
           max_redemptions   = p_usage_limit,
           customer_id       = p_customer
     where id = p_coupon
       and (p_usage_limit is null or redeemed_count <= p_usage_limit)
    returning * into v_new;
  exception when unique_violation then
    raise exception using errcode = 'P0033', message = 'code_taken';
  end;

  if v_new.id is null then
    raise exception using errcode = 'P0033', message = 'usage_limit_below_used';
  end if;

  insert into public.audit_log (actor_id, entity, entity_id, action, before, after, property_id)
  values (auth.uid(), 'coupon', p_coupon, 'update', to_jsonb(v_old), to_jsonb(v_new),
          v_old.property_id);
end;
$$;
```

- [ ] **Step 6: Replace the `set_coupon_active` stub**

Replace the whole `create function public.set_coupon_active(...) ... $$;` stub with:

```sql
-- Deactivates or reactivates one coupon. There is no delete: removing a
-- coupon would cascade to coupon_redemptions and erase history.
create function public.set_coupon_active(p_coupon uuid, p_active boolean)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_old public.coupons;
  v_new public.coupons;
begin
  select * into v_old from public.coupons where id = p_coupon;
  if not found then
    raise exception using errcode = 'P0002', message = 'not_found';
  end if;
  perform public.assert_resort_role(v_old.property_id, true, 'owner', 'admin');

  if p_active is null then
    raise exception 'active must be true or false' using errcode = 'P0005';
  end if;

  update public.coupons set is_active = p_active
   where id = p_coupon
  returning * into v_new;

  insert into public.audit_log (actor_id, entity, entity_id, action, before, after, property_id)
  values (auth.uid(), 'coupon', p_coupon,
          case when p_active then 'activate' else 'deactivate' end,
          to_jsonb(v_old), to_jsonb(v_new), v_old.property_id);
end;
$$;
```

- [ ] **Step 7: Run the tests to verify they pass**

Run: `supabase db reset && supabase test db supabase/tests/42_coupon_management_test.sql supabase/tests/37_tenancy_isolation_test.sql supabase/tests/11_coupons_test.sql`
Expected: PASS. 42 reports 62/62, 37 reports 77/77 and 11 reports 61/61. 37's allow-list guard still passes, because the two new helpers are not `security definer`.

- [ ] **Step 8: Commit**

```bash
git add supabase/migrations/0051_coupon_management.sql supabase/tests/42_coupon_management_test.sql
git commit -m "$(cat <<'EOF'
feat(coupons): create, edit and deactivate coupons

create_coupon, update_coupon and set_coupon_active validate the input
(P0033 with a reason word), derive the resort from the coupon row on
edits, keep the usage limit at or above uses taken inside the UPDATE,
store whole days in the resort's time zone, and write audit rows.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: `list_coupons`, `find_resort_guest`, suspended and archived resorts

**Track:** DB. Depends on Task 2.

**Files:**
- Modify: `supabase/migrations/0051_coupon_management.sql` (the two read stubs are replaced)
- Test: `supabase/tests/42_coupon_management_test.sql`

**Interfaces:**
- Consumes: `public.is_resort_guest(uuid, uuid)` from Task 2, plus the Task 1 and Task 2 fixtures and coupons. After Task 2, R has OLD5 (3 of 3 used), KIRANVIP, SAVE15, SUMMER, ONEDAY and OWNER1, and S has SAVE10.
- Produces: working `list_coupons` and `find_resort_guest` with the Task 1 signatures. `status` is `inactive`, `expired`, `scheduled`, `used_up` or `active`, in that precedence.

- [ ] **Step 1: Write the failing tests**

In `supabase/tests/42_coupon_management_test.sql`, change `select plan(62);` to `select plan(89);`. Then insert this block directly above `select * from finish();`:

```sql
-- === Task 3: listing, guest lookup, suspended and archived resorts ===========

-- One coupon in each remaining state, written straight into the table.
-- (Still superuser with empty claims from the end of Task 2's section.)
insert into public.coupons (property_id, code, kind, value, valid_to) values
  ('c1000000-0000-4000-8000-000000000001', 'EXPIRED1', 'fixed', 100, now() - interval '1 day');
insert into public.coupons (property_id, code, kind, value, valid_from) values
  ('c1000000-0000-4000-8000-000000000001', 'LATER1', 'fixed', 100, now() + interval '5 days');
insert into public.coupons (property_id, code, kind, value, max_redemptions, redeemed_count) values
  ('c1000000-0000-4000-8000-000000000001', 'USEDUP', 'fixed', 100, 1, 1);
insert into public.coupons (property_id, code, kind, value, is_active) values
  ('c1000000-0000-4000-8000-000000000001', 'OFF1', 'fixed', 100, false);

set local role authenticated;
set local request.jwt.claims to '{"sub":"c0000000-0000-0000-0000-000000000002","role":"authenticated"}';
select is((select count(*)::int from public.list_coupons('c1000000-0000-4000-8000-000000000001')),
  10, 'an admin lists every coupon of the resort, inactive ones too');
select is((select array_agg(code || ':' || status order by code)
             from public.list_coupons('c1000000-0000-4000-8000-000000000001')
            where code in ('EXPIRED1','LATER1','OFF1','SAVE15','USEDUP')),
  array['EXPIRED1:expired','LATER1:scheduled','OFF1:inactive','SAVE15:active','USEDUP:used_up'],
  'each coupon''s status follows the rules booking applies');
select is((select valid_from || '|' || valid_until || '|' || redeemed_count || '|' ||
                  customer_email || '|' || customer_name
             from public.list_coupons('c1000000-0000-4000-8000-000000000001')
            where code = 'SUMMER'),
  '2026-10-01|2026-10-31|0|Gita.Guest@Example.com|Gita Guest',
  'dates come back as the days picked, with the guest''s email and name');
select is((select redeemed_count || '/' || max_redemptions
             from public.list_coupons('c1000000-0000-4000-8000-000000000001')
            where code = 'OLD5'),
  '3/3', 'the usage count comes back with the limit');
select is((select code from public.list_coupons('c1000000-0000-4000-8000-000000000001') offset 9),
  'OFF1', 'inactive coupons are listed last');

set local request.jwt.claims to '{"sub":"c0000000-0000-0000-0000-000000000001","role":"authenticated"}';
select is((select count(*)::int from public.list_coupons('c1000000-0000-4000-8000-000000000001')),
  10, 'the owner lists them too');
set local request.jwt.claims to '{"sub":"c0000000-0000-0000-0000-000000000003","role":"authenticated"}';
select throws_ok($$select * from public.list_coupons('c1000000-0000-4000-8000-000000000001')$$,
  'P0020', null, 'staff cannot list coupons');
set local request.jwt.claims to '{"sub":"c0000000-0000-0000-0000-000000000004","role":"authenticated"}';
select throws_ok($$select * from public.list_coupons('c1000000-0000-4000-8000-000000000001')$$,
  'P0020', null, 'an accountant cannot list coupons');
set local request.jwt.claims to '{"sub":"c0000000-0000-0000-0000-00000000000a","role":"authenticated"}';
select throws_ok($$select * from public.list_coupons('c1000000-0000-4000-8000-000000000001')$$,
  'P0020', null, 'the platform admin cannot list a resort''s coupons');

set local request.jwt.claims to '{"sub":"c0000000-0000-0000-0000-000000000005","role":"authenticated"}';
select is((select array_agg(code) from public.list_coupons('c1000000-0000-4000-8000-000000000002')),
  array['SAVE10'], 'another resort lists only its own coupons');
select throws_ok($$select * from public.list_coupons('c1000000-0000-4000-8000-000000000001')$$,
  'P0020', null, 'another resort''s owner cannot list this resort''s coupons');
select is((select count(*)::int
             from public.find_resort_guest('c1000000-0000-4000-8000-000000000002', 'gita.guest@example.com')),
  0, 'a guest who never booked at S is not found there');
select is((select count(*)::int
             from public.find_resort_guest('c1000000-0000-4000-8000-000000000002', 'cp-olu@example.com')),
  1, 'S finds its own guest');

set local request.jwt.claims to '{"sub":"c0000000-0000-0000-0000-000000000002","role":"authenticated"}';
select is((select user_id || '|' || email || '|' || full_name
             from public.find_resort_guest('c1000000-0000-4000-8000-000000000001', '  GITA.guest@example.COM ')),
  'c0000000-0000-0000-0000-000000000006|Gita.Guest@Example.com|Gita Guest',
  'finds a guest who booked here, whatever the case and spacing');
select is((select count(*)::int
             from public.find_resort_guest('c1000000-0000-4000-8000-000000000001', 'cp-olu@example.com')),
  0, 'a guest of another resort is not found');
select is((select count(*)::int
             from public.find_resort_guest('c1000000-0000-4000-8000-000000000001', 'cp-hana@example.com')),
  0, 'a guest with only a hold is not found');
select is((select count(*)::int
             from public.find_resort_guest('c1000000-0000-4000-8000-000000000001', 'cp-kiran@example.com')),
  0, 'a guest whose only booking was cancelled is not found');
select is((select count(*)::int
             from public.find_resort_guest('c1000000-0000-4000-8000-000000000001', 'nobody@example.com')),
  0, 'an unknown email finds nobody');
select is((select count(*)::int
             from public.find_resort_guest('c1000000-0000-4000-8000-000000000001', 'cp-r-staff@example.com')),
  0, 'a team member who never booked is not found');
set local request.jwt.claims to '{"sub":"c0000000-0000-0000-0000-000000000003","role":"authenticated"}';
select throws_ok($$select * from public.find_resort_guest('c1000000-0000-4000-8000-000000000001', 'cp-olu@example.com')$$,
  'P0020', null, 'staff cannot look up guests');

-- Suspended: reads work, writes P0022. `reset role` keeps the claims;
-- clear them so the status change runs with no authenticated caller.
reset role;
set local request.jwt.claims to '';
update public.properties set status = 'suspended'
 where id = 'c1000000-0000-4000-8000-000000000001';
set local role authenticated;
set local request.jwt.claims to '{"sub":"c0000000-0000-0000-0000-000000000002","role":"authenticated"}';
select is((select count(*)::int from public.list_coupons('c1000000-0000-4000-8000-000000000001')),
  10, 'a suspended resort''s admin still lists coupons');
select is((select count(*)::int
             from public.find_resort_guest('c1000000-0000-4000-8000-000000000001', 'gita.guest@example.com')),
  1, 'and still looks up guests');
select throws_ok($$select public.create_coupon('c1000000-0000-4000-8000-000000000001', 'PAUSED', 'fixed', 100)$$,
  'P0022', null, 'no new coupons at a suspended resort');
select throws_ok($$select public.update_coupon('c1000000-0000-4000-8000-000000000031', 'OLD5', 'fixed', 500,
    null, null, null, 3)$$,
  'P0022', null, 'no edits at a suspended resort');
select throws_ok($$select public.set_coupon_active('c1000000-0000-4000-8000-000000000031', false)$$,
  'P0022', null, 'no deactivating at a suspended resort');

-- Archived: closed.
reset role;
set local request.jwt.claims to '';
update public.properties set status = 'archived'
 where id = 'c1000000-0000-4000-8000-000000000001';
set local role authenticated;
set local request.jwt.claims to '{"sub":"c0000000-0000-0000-0000-000000000002","role":"authenticated"}';
select throws_ok($$select * from public.list_coupons('c1000000-0000-4000-8000-000000000001')$$,
  'P0020', null, 'an archived resort''s coupons are closed to its admin');
select throws_ok($$select * from public.find_resort_guest('c1000000-0000-4000-8000-000000000001', 'gita.guest@example.com')$$,
  'P0020', null, 'and so is its guest lookup');
reset role;
set local request.jwt.claims to '';
```

- [ ] **Step 2: Run it to verify it fails**

Run: `supabase test db supabase/tests/42_coupon_management_test.sql`
Expected: FAIL at the first new assertion with `0A000 list_coupons is not implemented yet`.

- [ ] **Step 3: Replace the `list_coupons` stub**

In `supabase/migrations/0051_coupon_management.sql`, replace the whole `create function public.list_coupons(...) ... $$;` stub with:

```sql
-- Every coupon of the resort, for the Coupons screen. Owner/admin of the
-- resort (reads are allowed while it is suspended). Dates come back as
-- calendar days in the resort's time zone. status follows the order
-- resolve_coupon checks at booking time: inactive, expired, not yet valid
-- (scheduled), used up, else active. Active coupons first, newest first.
create function public.list_coupons(p_property uuid)
returns table (
  id                uuid,
  code              text,
  kind              public.coupon_kind,
  value             numeric,
  min_booking_value numeric,
  valid_from        date,
  valid_until       date,
  max_redemptions   int,
  redeemed_count    int,
  customer_id       uuid,
  customer_email    text,
  customer_name     text,
  is_active         boolean,
  status            text,
  created_at        timestamptz
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
#variable_conflict use_column
declare
  v_tz text;
begin
  perform public.assert_resort_role(p_property, false, 'owner', 'admin');

  select p.timezone into v_tz from public.properties p where p.id = p_property;

  return query
    select c.id,
           c.code,
           c.kind,
           c.value,
           c.min_booking_value,
           (c.valid_from at time zone v_tz)::date,
           (c.valid_to at time zone v_tz)::date,
           c.max_redemptions,
           c.redeemed_count,
           c.customer_id,
           u.email::text,
           pr.full_name,
           c.is_active,
           case
             when not c.is_active then 'inactive'
             when c.valid_to is not null and now() > c.valid_to then 'expired'
             when c.valid_from is not null and now() < c.valid_from then 'scheduled'
             when c.max_redemptions is not null
                  and c.redeemed_count >= c.max_redemptions then 'used_up'
             else 'active'
           end,
           c.created_at
      from public.coupons c
      left join auth.users u on u.id = c.customer_id
      left join public.profiles pr on pr.id = c.customer_id
     where c.property_id = p_property
     order by c.is_active desc, c.created_at desc, c.code;
end;
$$;
```

- [ ] **Step 4: Replace the `find_resort_guest` stub**

Replace the whole `create function public.find_resort_guest(...) ... $$;` stub with:

```sql
-- The account with this email (case-insensitive, trimmed), if it has a
-- real booking at the resort (is_resort_guest). Zero or one row. It never
-- reveals an account that has not booked at this resort.
create function public.find_resort_guest(p_property uuid, p_email text)
returns table (user_id uuid, email text, full_name text)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
#variable_conflict use_column
begin
  perform public.assert_resort_role(p_property, false, 'owner', 'admin');

  return query
    select u.id, u.email::text, pr.full_name
      from auth.users u
      left join public.profiles pr on pr.id = u.id
     where lower(u.email) = lower(btrim(p_email))
       and public.is_resort_guest(p_property, u.id);
end;
$$;
```

- [ ] **Step 5: Run the whole database suite to verify it passes**

Run: `supabase db reset && supabase test db`
Expected: 42 reports 89/89, 37 reports 77/77 and 11 reports 61/61. Every other file passes, apart from the 3 known time-of-day failures if you run between 00:00 and 05:30 IST.

- [ ] **Step 6: Commit**

```bash
git add supabase/migrations/0051_coupon_management.sql supabase/tests/42_coupon_management_test.sql
git commit -m "$(cat <<'EOF'
feat(coupons): list coupons and look up a resort's guests

list_coupons returns every coupon of the resort with its usage, guest
and a status worked out like resolve_coupon; find_resort_guest finds a
guest by email only if they have a real booking at that resort. Both
stay readable at a suspended resort and close with an archived one.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

## Phase 2: App track (after Task 1; 4 → 5 → 6; 7 independent)

### Task 4: The coupon form (create and edit) and P0033 copy

**Track:** App. Depends on Task 1.

**Files:**
- Create: `lib/features/admin/coupon_form.dart`
- Modify: `lib/core/errors.dart` (P0033)
- Test: `test/features/admin/coupon_form_test.dart`, `test/core/errors_test.dart`

**Interfaces:**
- Consumes (from Task 1):
  - `Coupon`, `CouponDraft`, `CouponKind`, `ResortGuest`, `couponCodePattern` and `normalizeCouponCode`;
  - `couponSourceProvider` and `CouponSource.create/update/findGuest`;
  - `FakeCouponSource` and `couponRow`.
- Produces:
  - `typedef CouponDatePicker = Future<DateTime?> Function(BuildContext context, DateTime initial);`
  - `Future<bool> showCouponForm(BuildContext context, {required String propertyId, Coupon? coupon, CouponDatePicker? pickDate})`. It resolves `true` when saved and `false` when closed.
  - `class CouponForm extends ConsumerStatefulWidget` (`propertyId`, `coupon`, `pickDate`).
  - `class CouponInvalid extends BookingFailure { final String reason; factory CouponInvalid(String reason) }`, mapped from P0033.
  - Widget keys:
    - fields and buttons: `coupon-code`, `coupon-kind`, `coupon-value`, `coupon-min-amount`, `coupon-valid-from`, `coupon-valid-until`, `coupon-valid-from-clear`, `coupon-valid-until-clear`, `coupon-usage-limit`, `coupon-audience`, `coupon-guest-email`, `coupon-guest-find`, `coupon-save` and `coupon-cancel`;
    - results and messages: `coupon-guest-found`, `coupon-guest-error`, `coupon-dates-error` and `coupon-form-error`.

- [ ] **Step 1: Write the failing tests**

Add to `test/core/errors_test.dart`, inside `main()` after the existing tests:

```dart
  group('P0033 coupon_invalid', () {
    test('each reason word gets its own copy', () {
      final failure = map('P0033', 'code_taken');
      expect(failure, isA<CouponInvalid>());
      expect((failure as CouponInvalid).reason, 'code_taken');
      expect(failure.message, 'That code is already in use at this resort.');
      expect(map('P0033', 'guest_not_eligible').message,
          'That guest has no booking at this resort.');
      expect(map('P0033', 'usage_limit_below_used').message,
          'The usage limit cannot be lower than the times already used.');
      expect(map('P0033', 'dates_invalid').message,
          'The end date must be on or after the start date.');
    });

    test('an unknown reason still reads as a coupon problem, never raw text',
        () {
      expect(map('P0033', 'something_new').message,
          'That coupon could not be saved. Check the details and try again.');
    });
  });
```

Create `test/features/admin/coupon_form_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/errors.dart';
import 'package:pasala/data/models/coupon.dart';
import 'package:pasala/data/repositories/coupon_repository.dart';
import 'package:pasala/features/admin/coupon_form.dart';

import '../../support/fake_coupon_source.dart';

const _gita = ResortGuest(
    userId: 'g1', email: 'gita@example.com', fullName: 'Gita Guest');

/// Opens the form from a button, the way the Coupons screen does, and
/// returns the list the form's result lands in. [picks] answers the date
/// pickers, in order.
Future<List<bool>> _open(
  WidgetTester tester,
  FakeCouponSource source, {
  Coupon? coupon,
  List<DateTime?> picks = const [],
}) async {
  tester.view.physicalSize = const Size(900, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final results = <bool>[];
  final queue = [...picks];
  await tester.pumpWidget(ProviderScope(
    overrides: [couponSourceProvider.overrideWithValue(source)],
    child: MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () async => results.add(await showCouponForm(
                context,
                propertyId: 'p1',
                coupon: coupon,
                pickDate: (_, _) async =>
                    queue.isEmpty ? null : queue.removeAt(0),
              )),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return results;
}

Future<void> _tapKey(WidgetTester tester, String key) async {
  final finder = find.byKey(Key(key));
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _type(WidgetTester tester, String key, String text) async {
  final finder = find.byKey(Key(key));
  await tester.ensureVisible(finder);
  await tester.enterText(finder, text);
  await tester.pump();
}

Finder _foundGuest(String text) => find.descendant(
    of: find.byKey(const Key('coupon-guest-found')), matching: find.text(text));

void main() {
  testWidgets('creates a percentage coupon for everyone, code upper-cased as '
      'typed', (tester) async {
    final source = FakeCouponSource();
    final results = await _open(tester, source);

    expect(find.text('New coupon'), findsOneWidget);
    await _type(tester, 'coupon-code', 'summer-10');
    expect(find.text('SUMMER-10'), findsOneWidget);
    await _type(tester, 'coupon-value', '15');
    await _tapKey(tester, 'coupon-save');

    final (propertyId, draft) = source.createCalls.single;
    expect(propertyId, 'p1');
    expect(draft.toParams(), {
      'p_code': 'SUMMER-10',
      'p_kind': 'percent',
      'p_value': 15,
      'p_min_amount': null,
      'p_valid_from': null,
      'p_valid_until': null,
      'p_usage_limit': null,
      'p_customer': null,
    });
    expect(results, [true]);
    expect(find.byType(CouponForm), findsNothing);
  });

  testWidgets('a fixed-amount coupon with every optional field',
      (tester) async {
    final source = FakeCouponSource();
    await _open(tester, source,
        picks: [DateTime(2026, 10, 1), DateTime(2026, 10, 31)]);

    await _type(tester, 'coupon-code', 'DIWALI');
    await tester.tap(find.text('Fixed amount'));
    await tester.pumpAndSettle();
    expect(find.text('Discount (₹)'), findsOneWidget);
    await _type(tester, 'coupon-value', '500');
    await _type(tester, 'coupon-min-amount', '5000');
    await _tapKey(tester, 'coupon-valid-from');
    await _tapKey(tester, 'coupon-valid-until');
    expect(find.text('1 Oct 2026'), findsOneWidget);
    expect(find.text('31 Oct 2026'), findsOneWidget);
    await _type(tester, 'coupon-usage-limit', '10');
    await _tapKey(tester, 'coupon-save');

    expect(source.createCalls.single.$2.toParams(), {
      'p_code': 'DIWALI',
      'p_kind': 'fixed',
      'p_value': 500,
      'p_min_amount': 5000,
      'p_valid_from': '2026-10-01',
      'p_valid_until': '2026-10-31',
      'p_usage_limit': 10,
      'p_customer': null,
    });
  });

  testWidgets('a bad code, a zero discount or a percentage above 100 never '
      'reaches the server', (tester) async {
    final source = FakeCouponSource();
    final results = await _open(tester, source);

    await _type(tester, 'coupon-code', 'ab');
    await _type(tester, 'coupon-value', '0');
    await _tapKey(tester, 'coupon-save');
    expect(find.text('Use 3–24 letters, numbers, - or _.'), findsOneWidget);
    expect(find.text('Enter a discount above 0.'), findsOneWidget);

    await _type(tester, 'coupon-code', 'SAVE10');
    await _type(tester, 'coupon-value', '150');
    await _tapKey(tester, 'coupon-save');
    expect(find.text('A percentage can be at most 100.'), findsOneWidget);

    expect(source.createCalls, isEmpty);
    expect(results, isEmpty);
  });

  testWidgets('an end date before the start date is refused on the form',
      (tester) async {
    final source = FakeCouponSource();
    await _open(tester, source,
        picks: [DateTime(2026, 10, 10), DateTime(2026, 10, 1)]);

    await _type(tester, 'coupon-code', 'SAVE10');
    await _type(tester, 'coupon-value', '10');
    await _tapKey(tester, 'coupon-valid-from');
    await _tapKey(tester, 'coupon-valid-until');
    await _tapKey(tester, 'coupon-save');

    expect(find.byKey(const Key('coupon-dates-error')), findsOneWidget);
    expect(find.text('The end date must be on or after the start date.'),
        findsOneWidget);
    expect(source.createCalls, isEmpty);
  });

  testWidgets('a picked date can be cleared again', (tester) async {
    final source = FakeCouponSource();
    await _open(tester, source, picks: [DateTime(2026, 10, 1)]);

    await _type(tester, 'coupon-code', 'SAVE10');
    await _type(tester, 'coupon-value', '10');
    await _tapKey(tester, 'coupon-valid-from');
    expect(find.text('1 Oct 2026'), findsOneWidget);
    await _tapKey(tester, 'coupon-valid-from-clear');
    expect(find.text('Any time'), findsOneWidget);
    await _tapKey(tester, 'coupon-save');

    expect(source.createCalls.single.$2.validFrom, isNull);
  });

  testWidgets('finds a guest who booked here and makes the coupon theirs only',
      (tester) async {
    final source = FakeCouponSource()..guests = {'gita@example.com': _gita};
    await _open(tester, source);

    await _type(tester, 'coupon-code', 'VIPGITA');
    await _type(tester, 'coupon-value', '20');
    await tester.tap(find.text('One guest'));
    await tester.pumpAndSettle();
    await _type(tester, 'coupon-guest-email', '  gita@example.com ');
    await _tapKey(tester, 'coupon-guest-find');

    expect(source.findGuestCalls, [('p1', 'gita@example.com')]);
    expect(_foundGuest('Gita Guest'), findsOneWidget);

    await _tapKey(tester, 'coupon-save');
    expect(source.createCalls.single.$2.guestId, 'g1');
  });

  testWidgets('an email with no booking here is reported and blocks saving',
      (tester) async {
    final source = FakeCouponSource();
    final results = await _open(tester, source);

    await _type(tester, 'coupon-code', 'VIPMEERA');
    await _type(tester, 'coupon-value', '20');
    await tester.tap(find.text('One guest'));
    await tester.pumpAndSettle();
    await _type(tester, 'coupon-guest-email', 'meera@example.com');
    await _tapKey(tester, 'coupon-guest-find');
    expect(find.text('No guest with that email has booked at this resort.'),
        findsOneWidget);

    await _tapKey(tester, 'coupon-save');
    expect(find.text('Find the guest first, or choose Everyone.'),
        findsOneWidget);
    expect(source.createCalls, isEmpty);
    expect(results, isEmpty);
  });

  testWidgets('changing the email after a match clears the match; Everyone '
      'saves without a guest', (tester) async {
    final source = FakeCouponSource()..guests = {'gita@example.com': _gita};
    await _open(tester, source);

    await _type(tester, 'coupon-code', 'VIPGITA');
    await _type(tester, 'coupon-value', '20');
    await tester.tap(find.text('One guest'));
    await tester.pumpAndSettle();
    await _type(tester, 'coupon-guest-email', 'gita@example.com');
    await _tapKey(tester, 'coupon-guest-find');
    expect(_foundGuest('Gita Guest'), findsOneWidget);

    await _type(tester, 'coupon-guest-email', 'other@example.com');
    expect(find.byKey(const Key('coupon-guest-found')), findsNothing);
    await _tapKey(tester, 'coupon-save');
    expect(find.text('Find the guest first, or choose Everyone.'),
        findsOneWidget);
    expect(source.createCalls, isEmpty);

    await tester.tap(find.text('Everyone'));
    await tester.pumpAndSettle();
    await _tapKey(tester, 'coupon-save');
    expect(source.createCalls.single.$2.guestId, isNull);
  });

  testWidgets('edit shows the coupon and saves every field back with its id',
      (tester) async {
    final source = FakeCouponSource();
    final existing = couponRow(
      id: 'c9',
      code: 'VIPGITA',
      kind: CouponKind.fixed,
      value: 500,
      minAmount: 5000,
      validFrom: DateTime(2026, 10, 1),
      validUntil: DateTime(2026, 10, 31),
      usageLimit: 10,
      usedCount: 3,
      guest: _gita,
    );
    final results = await _open(tester, source, coupon: existing);

    expect(find.text('Edit VIPGITA'), findsOneWidget);
    expect(find.text('Used 3 so far'), findsOneWidget);
    expect(find.text('Save changes'), findsOneWidget);
    expect(_foundGuest('Gita Guest'), findsOneWidget);
    await _type(tester, 'coupon-value', '750');
    await _tapKey(tester, 'coupon-save');

    final (id, draft) = source.updateCalls.single;
    expect(id, 'c9');
    expect(draft.toParams(), {
      'p_code': 'VIPGITA',
      'p_kind': 'fixed',
      'p_value': 750,
      'p_min_amount': 5000,
      'p_valid_from': '2026-10-01',
      'p_valid_until': '2026-10-31',
      'p_usage_limit': 10,
      'p_customer': 'g1',
    });
    expect(source.createCalls, isEmpty);
    expect(results, [true]);
  });

  testWidgets('the usage limit cannot go below the uses already taken',
      (tester) async {
    final source = FakeCouponSource();
    await _open(tester, source,
        coupon: couponRow(
            id: 'c5',
            code: 'OLD5',
            kind: CouponKind.fixed,
            value: 500,
            usageLimit: 5,
            usedCount: 3));

    await _type(tester, 'coupon-usage-limit', '2');
    await _tapKey(tester, 'coupon-save');

    expect(find.text('Already used 3 times — the limit cannot be lower.'),
        findsOneWidget);
    expect(source.updateCalls, isEmpty);
  });

  testWidgets('a server refusal stays on the form with its message',
      (tester) async {
    final source = FakeCouponSource()..createError = CouponInvalid('code_taken');
    final results = await _open(tester, source);

    await _type(tester, 'coupon-code', 'SAVE10');
    await _type(tester, 'coupon-value', '10');
    await _tapKey(tester, 'coupon-save');

    expect(find.byKey(const Key('coupon-form-error')), findsOneWidget);
    expect(find.text('That code is already in use at this resort.'),
        findsOneWidget);
    expect(find.byType(CouponForm), findsOneWidget);
    expect(results, isEmpty);
  });

  testWidgets('closing the form saves nothing', (tester) async {
    final source = FakeCouponSource();
    final results = await _open(tester, source);

    await _type(tester, 'coupon-code', 'SAVE10');
    await _tapKey(tester, 'coupon-cancel');

    expect(results, [false]);
    expect(source.createCalls, isEmpty);
    expect(find.byType(CouponForm), findsNothing);
  });
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `flutter test test/features/admin/coupon_form_test.dart test/core/errors_test.dart`
Expected: FAIL to compile. `coupon_form.dart` does not exist yet, and `CouponInvalid` is not defined.

- [ ] **Step 3: Map P0033**

In `lib/core/errors.dart`, add this class directly after `class AlreadyDispatched ... }`:

```dart
/// P0033 -- `create_coupon` / `update_coupon` (0051) refused the input.
/// The server sends one reason word ([reason]); the copy lives here. The
/// coupon form checks the same rules first, so most of these are
/// backstops -- `code_taken` and `guest_not_eligible` are the ones only
/// the server can know.
class CouponInvalid extends BookingFailure {
  const CouponInvalid._(this.reason, super.message);

  factory CouponInvalid(String reason) => CouponInvalid._(
    reason,
    switch (reason) {
      'code_invalid' => 'Use 3–24 letters, numbers, - or _ for the code.',
      'code_taken' => 'That code is already in use at this resort.',
      'kind_required' => 'Choose a percentage or a fixed amount.',
      'value_invalid' =>
        'Enter a discount above 0 (at most 100 for a percentage).',
      'min_amount_invalid' => 'The minimum booking amount cannot be negative.',
      'dates_invalid' => 'The end date must be on or after the start date.',
      'usage_limit_invalid' => 'The usage limit must be at least 1.',
      'usage_limit_below_used' =>
        'The usage limit cannot be lower than the times already used.',
      'guest_not_eligible' => 'That guest has no booking at this resort.',
      _ => 'That coupon could not be saved. Check the details and try again.',
    },
  );

  final String reason;
}
```

In `mapPostgrestError`, replace:

```dart
    'P0030' => const ReasonRequired(),
    'P0031' => const AlreadyDispatched(),
```

with:

```dart
    'P0030' => const ReasonRequired(),
    'P0031' => const AlreadyDispatched(),
    // P0033: coupon management (0051). The server sends a bare reason
    // word (`code_taken`, `guest_not_eligible`, ...); CouponInvalid holds
    // the copy.
    'P0033' => CouponInvalid(message),
```

- [ ] **Step 4: Write the form**

Create `lib/features/admin/coupon_form.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../core/format.dart';
import '../../core/theme/tokens.dart';
import '../../data/models/coupon.dart';
import '../../data/repositories/coupon_repository.dart';

/// Picks a day for "Valid from" / "Valid until". Tests pass their own.
typedef CouponDatePicker =
    Future<DateTime?> Function(BuildContext context, DateTime initial);

Future<DateTime?> _showDatePicker(BuildContext context, DateTime initial) =>
    showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );

/// Opens [CouponForm] full screen: a new coupon when [coupon] is null,
/// otherwise an edit of it. Completes with true once the coupon was saved,
/// false when the form was closed without saving.
Future<bool> showCouponForm(
  BuildContext context, {
  required String propertyId,
  Coupon? coupon,
  CouponDatePicker? pickDate,
}) async {
  final saved = await showDialog<bool>(
    context: context,
    builder: (_) => Dialog.fullscreen(
      child: CouponForm(
        propertyId: propertyId,
        coupon: coupon,
        pickDate: pickDate ?? _showDatePicker,
      ),
    ),
  );
  return saved ?? false;
}

enum _Audience { everyone, oneGuest }

/// Upper-cases the code as it is typed, so what the admin sees is what is
/// saved (`coupons_code_upper`) and what a guest must type.
class _UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) => newValue.copyWith(text: newValue.text.toUpperCase());
}

/// The create/edit form for one coupon. It checks locally everything
/// `coupon_check_input` checks except what only the server knows (a code
/// already taken, a guest's bookings), so most mistakes never leave the
/// device. A server refusal stays on the form with its message. It pops
/// itself with its own context: it lives on the dialog's route, never the
/// screen's.
class CouponForm extends ConsumerStatefulWidget {
  const CouponForm({
    super.key,
    required this.propertyId,
    this.coupon,
    this.pickDate = _showDatePicker,
  });

  final String propertyId;
  final Coupon? coupon;
  final CouponDatePicker pickDate;

  @override
  ConsumerState<CouponForm> createState() => _CouponFormState();
}

class _CouponFormState extends ConsumerState<CouponForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _code;
  late final TextEditingController _value;
  late final TextEditingController _minAmount;
  late final TextEditingController _usageLimit;
  late final TextEditingController _guestEmail;
  late CouponKind _kind;
  DateTime? _validFrom;
  DateTime? _validUntil;
  late _Audience _audience;
  ResortGuest? _guest;
  String? _guestError;
  String? _datesError;
  String? _formError;
  bool _finding = false;
  bool _saving = false;

  bool get _isEdit => widget.coupon != null;
  int get _used => widget.coupon?.usedCount ?? 0;

  static String _numText(num n) =>
      n % 1 == 0 ? n.toInt().toString() : n.toString();

  @override
  void initState() {
    super.initState();
    final c = widget.coupon;
    _code = TextEditingController(text: c?.code ?? '');
    _value = TextEditingController(text: c == null ? '' : _numText(c.value));
    _minAmount = TextEditingController(
      text: c?.minAmount == null ? '' : _numText(c!.minAmount!),
    );
    _usageLimit = TextEditingController(text: c?.usageLimit?.toString() ?? '');
    _guestEmail = TextEditingController(text: c?.guest?.email ?? '');
    _kind = c?.kind ?? CouponKind.percent;
    _validFrom = c?.validFrom;
    _validUntil = c?.validUntil;
    _guest = c?.guest;
    _audience = _guest == null ? _Audience.everyone : _Audience.oneGuest;
  }

  @override
  void dispose() {
    _code.dispose();
    _value.dispose();
    _minAmount.dispose();
    _usageLimit.dispose();
    _guestEmail.dispose();
    super.dispose();
  }

  Future<void> _pick({required bool from}) async {
    final initial =
        (from ? _validFrom : _validUntil) ?? _validFrom ?? DateTime.now();
    final picked = await widget.pickDate(context, initial);
    if (picked == null || !mounted) return;
    final day = DateTime(picked.year, picked.month, picked.day);
    setState(() {
      if (from) {
        _validFrom = day;
      } else {
        _validUntil = day;
      }
      _datesError = null;
    });
  }

  Future<void> _findGuest() async {
    final email = _guestEmail.text.trim();
    if (email.isEmpty) {
      setState(() => _guestError = "Enter the guest's email.");
      return;
    }
    setState(() {
      _finding = true;
      _guest = null;
      _guestError = null;
    });
    try {
      final guest = await ref
          .read(couponSourceProvider)
          .findGuest(widget.propertyId, email);
      if (!mounted) return;
      setState(() {
        _guest = guest;
        _guestError = guest == null
            ? 'No guest with that email has booked at this resort.'
            : null;
      });
    } on BookingFailure catch (e) {
      if (!mounted) return;
      setState(() => _guestError = e.message);
    } finally {
      if (mounted) setState(() => _finding = false);
    }
  }

  Future<void> _save() async {
    final fieldsOk = _formKey.currentState!.validate();
    final datesOk = _validFrom == null ||
        _validUntil == null ||
        !_validUntil!.isBefore(_validFrom!);
    final guestOk = _audience == _Audience.everyone || _guest != null;
    setState(() {
      _datesError =
          datesOk ? null : 'The end date must be on or after the start date.';
      if (!guestOk) _guestError = 'Find the guest first, or choose Everyone.';
      _formError = null;
    });
    if (!fieldsOk || !datesOk || !guestOk) return;

    final minText = _minAmount.text.trim();
    final limitText = _usageLimit.text.trim();
    final draft = CouponDraft(
      code: normalizeCouponCode(_code.text),
      kind: _kind,
      value: num.parse(_value.text.trim()),
      minAmount: minText.isEmpty ? null : num.parse(minText),
      validFrom: _validFrom,
      validUntil: _validUntil,
      usageLimit: limitText.isEmpty ? null : int.parse(limitText),
      guestId: _audience == _Audience.oneGuest ? _guest!.userId : null,
    );

    setState(() => _saving = true);
    final source = ref.read(couponSourceProvider);
    try {
      if (_isEdit) {
        await source.update(widget.coupon!.id, draft);
      } else {
        await source.create(widget.propertyId, draft);
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on BookingFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _formError = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final errorStyle = Theme.of(context)
        .textTheme
        .bodySmall
        ?.copyWith(color: Theme.of(context).colorScheme.error);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          key: const Key('coupon-cancel'),
          icon: const Icon(Icons.close),
          tooltip: 'Cancel',
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
        ),
        title: Text(_isEdit ? 'Edit ${widget.coupon!.code}' : 'New coupon'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(Spacing.md),
          children: [
            TextFormField(
              key: const Key('coupon-code'),
              controller: _code,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [_UpperCaseFormatter()],
              decoration: const InputDecoration(
                labelText: 'Code',
                helperText:
                    '3–24 letters, numbers, - or _. Guests type this when '
                    'they book.',
              ),
              validator: (v) =>
                  couponCodePattern.hasMatch(normalizeCouponCode(v ?? ''))
                      ? null
                      : 'Use 3–24 letters, numbers, - or _.',
            ),
            const SizedBox(height: Spacing.md),
            SegmentedButton<CouponKind>(
              key: const Key('coupon-kind'),
              segments: const [
                ButtonSegment(
                  value: CouponKind.percent,
                  label: Text('Percentage'),
                  icon: Icon(Icons.percent),
                ),
                ButtonSegment(
                  value: CouponKind.fixed,
                  label: Text('Fixed amount'),
                  icon: Icon(Icons.currency_rupee),
                ),
              ],
              selected: {_kind},
              onSelectionChanged: (s) => setState(() => _kind = s.first),
            ),
            const SizedBox(height: Spacing.md),
            TextFormField(
              key: const Key('coupon-value'),
              controller: _value,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: _kind == CouponKind.percent
                    ? 'Discount (%)'
                    : 'Discount (₹)',
              ),
              validator: (v) {
                final n = num.tryParse((v ?? '').trim());
                if (n == null || n <= 0) return 'Enter a discount above 0.';
                if (_kind == CouponKind.percent && n > 100) {
                  return 'A percentage can be at most 100.';
                }
                return null;
              },
            ),
            const SizedBox(height: Spacing.md),
            TextFormField(
              key: const Key('coupon-min-amount'),
              controller: _minAmount,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Minimum booking amount (₹, optional)',
              ),
              validator: (v) {
                final t = (v ?? '').trim();
                if (t.isEmpty) return null;
                final n = num.tryParse(t);
                return n == null || n < 0
                    ? 'Enter 0 or more, or leave it empty.'
                    : null;
              },
            ),
            const SizedBox(height: Spacing.sm),
            _DateRow(
              key: const Key('coupon-valid-from'),
              clearKey: const Key('coupon-valid-from-clear'),
              label: 'Valid from',
              value: _validFrom,
              emptyText: 'Any time',
              onPick: () => _pick(from: true),
              onClear: () => setState(() => _validFrom = null),
            ),
            _DateRow(
              key: const Key('coupon-valid-until'),
              clearKey: const Key('coupon-valid-until-clear'),
              label: 'Valid until',
              value: _validUntil,
              emptyText: 'No end date',
              onPick: () => _pick(from: false),
              onClear: () => setState(() => _validUntil = null),
            ),
            if (_datesError != null)
              Text(
                _datesError!,
                key: const Key('coupon-dates-error'),
                style: errorStyle,
              ),
            const SizedBox(height: Spacing.sm),
            TextFormField(
              key: const Key('coupon-usage-limit'),
              controller: _usageLimit,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: 'Usage limit (optional)',
                helperText: _isEdit
                    ? 'Used $_used so far'
                    : 'Leave empty for no limit',
              ),
              validator: (v) {
                final t = (v ?? '').trim();
                if (t.isEmpty) return null;
                final n = int.tryParse(t);
                if (n == null || n < 1) {
                  return 'Enter 1 or more, or leave it empty.';
                }
                if (n < _used) {
                  return 'Already used $_used times — the limit cannot be '
                      'lower.';
                }
                return null;
              },
            ),
            const SizedBox(height: Spacing.md),
            Text('Who can use it',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: Spacing.xs),
            SegmentedButton<_Audience>(
              key: const Key('coupon-audience'),
              segments: const [
                ButtonSegment(
                  value: _Audience.everyone,
                  label: Text('Everyone'),
                  icon: Icon(Icons.public),
                ),
                ButtonSegment(
                  value: _Audience.oneGuest,
                  label: Text('One guest'),
                  icon: Icon(Icons.person_outline),
                ),
              ],
              selected: {_audience},
              onSelectionChanged: (s) => setState(() {
                _audience = s.first;
                _guestError = null;
              }),
            ),
            if (_audience == _Audience.oneGuest) ...[
              const SizedBox(height: Spacing.sm),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('coupon-guest-email'),
                      controller: _guestEmail,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: "Guest's email",
                        helperText: 'Someone who has booked at this resort',
                      ),
                      // A found guest belongs to the email that found
                      // them: editing the email forgets the match.
                      onChanged: (text) {
                        if (_guest != null && text.trim() != _guest!.email) {
                          setState(() => _guest = null);
                        }
                      },
                      onSubmitted: (_) => _findGuest(),
                    ),
                  ),
                  const SizedBox(width: Spacing.sm),
                  OutlinedButton(
                    key: const Key('coupon-guest-find'),
                    onPressed: _finding ? null : _findGuest,
                    child: Text(_finding ? 'Finding…' : 'Find'),
                  ),
                ],
              ),
              if (_guest != null)
                ListTile(
                  key: const Key('coupon-guest-found'),
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.person),
                  title: Text(_guest!.name),
                  subtitle: Text(_guest!.email),
                ),
              if (_guestError != null)
                Padding(
                  padding: const EdgeInsets.only(top: Spacing.xs),
                  child: Text(
                    _guestError!,
                    key: const Key('coupon-guest-error'),
                    style: errorStyle,
                  ),
                ),
            ],
            if (_formError != null) ...[
              const SizedBox(height: Spacing.md),
              Text(
                _formError!,
                key: const Key('coupon-form-error'),
                style: errorStyle,
              ),
            ],
            const SizedBox(height: Spacing.lg),
            FilledButton(
              key: const Key('coupon-save'),
              onPressed: _saving ? null : _save,
              child: Text(
                _saving
                    ? 'Saving…'
                    : _isEdit
                        ? 'Save changes'
                        : 'Create coupon',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One optional date: tap to pick, the clear button to go back to
/// [emptyText].
class _DateRow extends StatelessWidget {
  const _DateRow({
    super.key,
    required this.clearKey,
    required this.label,
    required this.value,
    required this.emptyText,
    required this.onPick,
    required this.onClear,
  });

  final Key clearKey;
  final String label;
  final DateTime? value;
  final String emptyText;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: const Icon(Icons.event_outlined),
    title: Text(label),
    subtitle: Text(value == null ? emptyText : formatDate(value!)),
    onTap: onPick,
    trailing: value == null
        ? null
        : IconButton(
            key: clearKey,
            tooltip: 'Clear',
            icon: const Icon(Icons.clear),
            onPressed: onClear,
          ),
  );
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `flutter test test/features/admin/coupon_form_test.dart test/core/errors_test.dart && flutter analyze lib/features/admin/coupon_form.dart lib/core/errors.dart`
Expected: all tests pass; `No issues found!`.

- [ ] **Step 6: Commit**

```bash
git add lib/features/admin/coupon_form.dart lib/core/errors.dart \
  test/features/admin/coupon_form_test.dart test/core/errors_test.dart
git commit -m "$(cat <<'EOF'
feat(coupons): coupon form with guest lookup, and P0033 copy

A full-screen create/edit form: upper-case code, percentage or fixed
discount, optional minimum, whole-day validity, optional usage limit
(never below uses taken) and Everyone or one guest found by email.
P0033 reason words map to readable messages.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: The Coupons screen

**Track:** App. Depends on Task 4.

**Files:**
- Create: `lib/features/admin/coupons_screen.dart`
- Test: `test/features/admin/coupons_screen_test.dart`

**Interfaces:**
- Consumes:
  - `showCouponForm(context, propertyId:, coupon:)` and `CouponForm` from Task 4.
  - From Task 1: `couponsProvider`, `couponSourceProvider`, `Coupon` with its display getters, and `CouponStatusDisplay`.
  - `currentResortProvider` (`lib/core/current_resort.dart`).
  - `AsyncView` and `EmptyState` (`lib/core/widgets/`).
  - `BookingFailure` and `ResortSuspended` (`lib/core/errors.dart`).
- Produces:
  - `class CouponsScreen extends ConsumerWidget` (const, no arguments). Task 6 routes to it.
  - `class CouponTile` (`coupon`, `onEdit`, `onToggleActive`) and `class CouponStatusChip` (`status`).
  - Keys: `new-coupon`, `coupon-tile-<id>` and `coupon-toggle-<id>`.

- [ ] **Step 1: Write the failing tests**

Create `test/features/admin/coupons_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pasala/core/current_resort.dart';
import 'package:pasala/core/errors.dart';
import 'package:pasala/data/models/coupon.dart';
import 'package:pasala/data/models/resort_membership.dart';
import 'package:pasala/data/repositories/coupon_repository.dart';
import 'package:pasala/features/admin/coupon_form.dart';
import 'package:pasala/features/admin/coupons_screen.dart';

import '../../support/fake_coupon_source.dart';

class _FixedResort extends CurrentResort {
  _FixedResort(this._value);
  final ResortMembership _value;
  @override
  ResortMembership? build() => _value;
}

const _adminM = ResortMembership(
    propertyId: 'p1', resortName: 'Pasala', role: ResortRole.admin);

const _gita = ResortGuest(
    userId: 'g1', email: 'gita@example.com', fullName: 'Gita Guest');

final _coupons = [
  couponRow(
    id: 'c1',
    code: 'SAVE10',
    value: 10,
    usageLimit: 10,
    usedCount: 3,
    validUntil: DateTime(2026, 10, 31),
  ),
  couponRow(
    id: 'c2',
    code: 'VIPGITA',
    kind: CouponKind.fixed,
    value: 500,
    minAmount: 5000,
    validFrom: DateTime(2026, 10, 1),
    guest: _gita,
    status: CouponStatus.scheduled,
  ),
  couponRow(
    id: 'c3',
    code: 'OLD',
    isActive: false,
    status: CouponStatus.inactive,
  ),
];

/// Mounts the screen inside a ShellRoute, as the real router does, so a
/// dialog that popped the screen's navigator instead of itself would blank
/// the page (the bug fixed in 66792f0).
Future<void> _pump(WidgetTester tester, FakeCouponSource source) async {
  tester.view.physicalSize = const Size(900, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final router = GoRouter(
    initialLocation: '/admin/coupons',
    routes: [
      ShellRoute(
        builder: (_, _, child) => Scaffold(body: child),
        routes: [
          GoRoute(path: '/admin', builder: (_, _) => const Text('Admin home')),
          GoRoute(
              path: '/admin/coupons',
              builder: (_, _) => const CouponsScreen()),
        ],
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(ProviderScope(
    overrides: [
      couponSourceProvider.overrideWithValue(source),
      currentResortProvider.overrideWith(() => _FixedResort(_adminM)),
    ],
    child: MaterialApp.router(routerConfig: router),
  ));
  await tester.pumpAndSettle();
}

Finder _inTile(String id, Finder matching) => find.descendant(
    of: find.byKey(Key('coupon-tile-$id')), matching: matching);

void main() {
  testWidgets('shows each coupon with its status, discount, dates, usage and '
      'audience', (tester) async {
    final source = FakeCouponSource()..coupons = _coupons;
    await _pump(tester, source);

    expect(source.listCalls, ['p1']);
    expect(find.text('Coupons'), findsOneWidget);

    expect(_inTile('c1', find.text('SAVE10')), findsOneWidget);
    expect(_inTile('c1', find.text('Active')), findsOneWidget);
    expect(_inTile('c1', find.byIcon(Icons.check_circle_outline)),
        findsOneWidget);
    expect(_inTile('c1', find.text('10% off')), findsOneWidget);
    expect(_inTile('c1', find.text('Until 31 Oct 2026')), findsOneWidget);
    expect(_inTile('c1', find.text('Used 3 of 10 · Everyone')), findsOneWidget);
    expect(_inTile('c1', find.text('Deactivate')), findsOneWidget);

    expect(_inTile('c2', find.text('Scheduled')), findsOneWidget);
    expect(_inTile('c2', find.text('₹500 off · Min ₹5,000')), findsOneWidget);
    expect(_inTile('c2', find.text('From 1 Oct 2026')), findsOneWidget);
    expect(_inTile('c2', find.text('Used 0 · Only Gita Guest')),
        findsOneWidget);

    expect(_inTile('c3', find.text('Inactive')), findsOneWidget);
    expect(_inTile('c3', find.text('No date limits')), findsOneWidget);
    expect(_inTile('c3', find.text('Activate')), findsOneWidget);
  });

  testWidgets('no coupons yet shows the empty state', (tester) async {
    await _pump(tester, FakeCouponSource());

    expect(find.text('No coupons yet'), findsOneWidget);
    expect(find.byKey(const Key('new-coupon')), findsOneWidget);
  });

  testWidgets('a load error shows the reason and retries', (tester) async {
    final source = FakeCouponSource()..listError = const NetworkFailure();
    await _pump(tester, source);

    expect(find.text('Cannot reach the server. Check your connection.'),
        findsOneWidget);
    source.listError = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(source.listCalls, ['p1', 'p1']);
    expect(find.text('No coupons yet'), findsOneWidget);
  });

  testWidgets('New coupon opens the form, and a save refreshes the list',
      (tester) async {
    final source = FakeCouponSource()..coupons = _coupons;
    await _pump(tester, source);

    await tester.tap(find.byKey(const Key('new-coupon')));
    await tester.pumpAndSettle();
    expect(find.byType(CouponForm), findsOneWidget);

    await tester.enterText(find.byKey(const Key('coupon-code')), 'FESTIVE');
    await tester.enterText(find.byKey(const Key('coupon-value')), '12');
    await tester.ensureVisible(find.byKey(const Key('coupon-save')));
    await tester.tap(find.byKey(const Key('coupon-save')));
    await tester.pumpAndSettle();

    expect(source.createCalls.single.$1, 'p1');
    expect(source.createCalls.single.$2.code, 'FESTIVE');
    expect(find.byType(CouponForm), findsNothing);
    expect(source.listCalls, ['p1', 'p1']);
    expect(find.text('Coupon created'), findsOneWidget);
  });

  testWidgets('tapping a coupon opens it for editing; closing refetches '
      'nothing', (tester) async {
    final source = FakeCouponSource()..coupons = _coupons;
    await _pump(tester, source);

    await tester.tap(_inTile('c1', find.text('SAVE10')));
    await tester.pumpAndSettle();
    expect(find.text('Edit SAVE10'), findsOneWidget);

    await tester.tap(find.byKey(const Key('coupon-cancel')));
    await tester.pumpAndSettle();
    expect(find.byType(CouponForm), findsNothing);
    expect(find.byType(CouponsScreen), findsOneWidget);
    expect(source.listCalls, ['p1']);
  });

  testWidgets('Deactivate asks first; inside a ShellRoute the dialog closes, '
      'not the page', (tester) async {
    final source = FakeCouponSource()..coupons = _coupons;
    await _pump(tester, source);

    // Cancel first: the dialog closes, the page stays, nothing is sent.
    await tester.tap(find.byKey(const Key('coupon-toggle-c1')));
    await tester.pumpAndSettle();
    expect(find.text('Deactivate SAVE10?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(CouponsScreen), findsOneWidget);
    expect(source.setActiveCalls, isEmpty);

    // Confirm: deactivated, the dialog closes, the page stays and refetches.
    await tester.tap(find.byKey(const Key('coupon-toggle-c1')));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
        of: find.byType(AlertDialog), matching: find.text('Deactivate')));
    await tester.pumpAndSettle();

    expect(source.setActiveCalls, [('c1', false)]);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(CouponsScreen), findsOneWidget);
    expect(source.listCalls, ['p1', 'p1']);
    expect(find.text('SAVE10 deactivated'), findsOneWidget);
  });

  testWidgets('Activate needs no confirmation', (tester) async {
    final source = FakeCouponSource()..coupons = _coupons;
    await _pump(tester, source);

    await tester.tap(find.byKey(const Key('coupon-toggle-c3')));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(source.setActiveCalls, [('c3', true)]);
    expect(find.text('OLD is active again'), findsOneWidget);
  });

  testWidgets('a refused toggle shows the reason and changes nothing',
      (tester) async {
    final source = FakeCouponSource()
      ..coupons = _coupons
      ..setActiveError = const ResortSuspended();
    await _pump(tester, source);

    await tester.tap(find.byKey(const Key('coupon-toggle-c3')));
    await tester.pumpAndSettle();

    expect(find.text('This resort is suspended — changes are disabled.'),
        findsOneWidget);
    expect(source.listCalls, ['p1']);
  });
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `flutter test test/features/admin/coupons_screen_test.dart`
Expected: FAIL to compile with `Target of URI doesn't exist: 'package:pasala/features/admin/coupons_screen.dart'`.

- [ ] **Step 3: Write the screen**

Create `lib/features/admin/coupons_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/current_resort.dart';
import '../../core/errors.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/empty_state.dart';
import '../../data/models/coupon.dart';
import '../../data/repositories/coupon_repository.dart';
import 'coupon_form.dart';

/// `/admin/coupons` -- the current resort's coupons, for its owner and
/// admins (`redirectFor`'s `/admin/*` rule; `list_coupons` and the write
/// functions assert the same roles in Postgres). Lists every coupon with
/// its status, discount, dates, usage and audience. Tapping a card edits
/// it; the button on each card deactivates (after a confirmation) or
/// reactivates it. There is no delete: a coupon's history stays.
class CouponsScreen extends ConsumerWidget {
  const CouponsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final propertyId = ref.watch(currentResortProvider)?.propertyId;
    if (propertyId == null) {
      // The router only sends an owner or admin (who always has a current
      // resort) here; this covers the moment right after sign-out.
      return const Scaffold(body: SizedBox.shrink());
    }
    final couponsAsync = ref.watch(couponsProvider(propertyId));
    Future<void> refresh() => ref.refresh(couponsProvider(propertyId).future);

    return Scaffold(
      appBar: AppBar(title: const Text('Coupons')),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('new-coupon'),
        onPressed: () => _openForm(context, ref, propertyId),
        icon: const Icon(Icons.add),
        label: const Text('New coupon'),
      ),
      body: AsyncView(
        value: couponsAsync,
        onRetry: () => ref.invalidate(couponsProvider(propertyId)),
        empty: () => RefreshIndicator(
          onRefresh: refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: const [
              EmptyState(
                icon: Icons.local_offer_outlined,
                title: 'No coupons yet',
                message: 'Create a code guests can enter when they book.',
              ),
            ],
          ),
        ),
        data: (coupons) => RefreshIndicator(
          onRefresh: refresh,
          child: ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            // Bottom padding keeps the last card clear of the button.
            padding: const EdgeInsets.fromLTRB(
                Spacing.md, Spacing.md, Spacing.md, 96),
            itemCount: coupons.length,
            separatorBuilder: (_, _) => const SizedBox(height: Spacing.sm),
            itemBuilder: (context, i) => CouponTile(
              coupon: coupons[i],
              onEdit: () =>
                  _openForm(context, ref, propertyId, coupon: coupons[i]),
              onToggleActive: () =>
                  _toggle(context, ref, propertyId, coupons[i]),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openForm(
    BuildContext context,
    WidgetRef ref,
    String propertyId, {
    Coupon? coupon,
  }) async {
    final saved = await showCouponForm(
      context,
      propertyId: propertyId,
      coupon: coupon,
    );
    if (!saved || !context.mounted) return;
    ref.invalidate(couponsProvider(propertyId));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(coupon == null ? 'Coupon created' : 'Coupon saved'),
    ));
  }

  Future<void> _toggle(
    BuildContext context,
    WidgetRef ref,
    String propertyId,
    Coupon coupon,
  ) async {
    final activate = !coupon.isActive;
    if (!activate) {
      final confirmed = await showDialog<bool>(
        context: context,
        // The buttons pop with the dialog's own context: this screen lives
        // in the router's ShellRoute, so its context would pop the page.
        builder: (dialogContext) => AlertDialog(
          title: Text('Deactivate ${coupon.code}?'),
          content: const Text(
            'Guests can no longer apply it. Bookings that already used it '
            'keep their discount.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Deactivate'),
            ),
          ],
        ),
      );
      if (confirmed != true || !context.mounted) return;
    }

    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(couponSourceProvider).setActive(coupon.id, activate);
      ref.invalidate(couponsProvider(propertyId));
      messenger.showSnackBar(SnackBar(
        content: Text(activate
            ? '${coupon.code} is active again'
            : '${coupon.code} deactivated'),
      ));
    } on BookingFailure catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

/// One coupon: code and status on top, then discount and minimum, dates,
/// and usage with audience, and the Deactivate/Activate button.
class CouponTile extends StatelessWidget {
  const CouponTile({
    super.key,
    required this.coupon,
    required this.onEdit,
    required this.onToggleActive,
  });

  final Coupon coupon;
  final VoidCallback onEdit;
  final VoidCallback onToggleActive;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final muted = textTheme.bodySmall?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    final discount = [
      coupon.discountLabel,
      if (coupon.minAmountLabel != null) coupon.minAmountLabel!,
    ].join(' · ');

    return Card(
      key: Key('coupon-tile-${coupon.id}'),
      child: InkWell(
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              Spacing.md, Spacing.md, Spacing.md, Spacing.xs),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      coupon.code,
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                  CouponStatusChip(status: coupon.status),
                ],
              ),
              const SizedBox(height: Spacing.xs),
              Text(discount, style: textTheme.bodyLarge),
              Text(coupon.validityLabel, style: muted),
              Text('${coupon.usageLabel} · ${coupon.audienceLabel}',
                  style: muted),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  key: Key('coupon-toggle-${coupon.id}'),
                  onPressed: onToggleActive,
                  child: Text(coupon.isActive ? 'Deactivate' : 'Activate'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A coupon's status as icon plus label on a tinted pill -- never colour
/// alone.
class CouponStatusChip extends StatelessWidget {
  const CouponStatusChip({super.key, required this.status});

  final CouponStatus status;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: Spacing.sm, vertical: 2),
    decoration: BoxDecoration(
      color: status.color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(status.icon, size: 16, color: status.color),
        const SizedBox(width: Spacing.xs),
        Text(
          status.label,
          style: Theme.of(context)
              .textTheme
              .labelMedium
              ?.copyWith(color: status.color),
        ),
      ],
    ),
  );
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/features/admin/coupons_screen_test.dart test/features/admin/coupon_form_test.dart && flutter analyze lib/features/admin/coupons_screen.dart`
Expected: all tests pass; `No issues found!`.

- [ ] **Step 5: Commit**

```bash
git add lib/features/admin/coupons_screen.dart test/features/admin/coupons_screen_test.dart
git commit -m "$(cat <<'EOF'
feat(coupons): Coupons screen for owners and admins

Lists the resort's coupons with status (icon and label), discount,
dates, usage and audience; opens the form to create or edit; deactivates
after a confirmation whose dialog pops itself inside the ShellRoute, and
reactivates directly.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: Navigation to the Coupons screen

**Track:** App. Depends on Task 5.

**Files:**
- Modify: `lib/core/router.dart`
- Modify: `lib/features/owner/owner_home_screen.dart`
- Modify: `lib/features/admin/admin_more_screen.dart`
- Test: `test/core/router_test.dart`, `test/features/owner/owner_home_screen_test.dart`, `test/features/admin/admin_more_screen_test.dart`

**Interfaces:**
- Consumes: `CouponsScreen` (Task 5). It also uses `redirectFor`'s existing `/admin/*` rule, which already lets owner and admin through and sends everyone else to `/404`.
- Produces: the route `/admin/coupons`, plus a `Coupons` tile on `/owner` and on `/admin/more`.

- [ ] **Step 1: Write the failing tests**

In `test/core/router_test.dart`, add this group inside `main()`, directly after the `group('room status grid', ...)` block:

```dart
  group('coupons', () {
    test('the app router registers /admin/coupons', () {
      TestWidgetsFlutterBinding.ensureInitialized();
      final container = ProviderContainer(overrides: [
        currentUserProvider.overrideWith((ref) => Stream.value(null)),
        currentResortProvider.overrideWith(_NoResort.new),
      ]);
      addTearDown(container.dispose);

      final router = container.read(routerProvider);

      expect(_paths(router.configuration.routes), contains('/admin/coupons'));
    });

    test('/admin/coupons opens for owners and admins only', () {
      expect(_to(_superAdmin, _ownerM, '/admin/coupons'), null);
      expect(_to(_admin, _adminM, '/admin/coupons'), null);
      expect(_to(_staff, _staffM, '/admin/coupons'), '/404');
      expect(_to(_accountant, _accountantM, '/admin/coupons'), '/404');
      expect(_to(_customer, null, '/admin/coupons'), '/404');
    });
  });
```

In `test/features/owner/owner_home_screen_test.dart`:

1. In `_appFor`'s router, add a route next to the `/staff/rooms` one:

```dart
      GoRoute(path: '/admin/coupons', builder: (_, _) => const Text('Coupons screen')),
```

2. In `'shows a tile for every step of the Owner flow'`, add `'Coupons',` to the list, directly after `'Rooms',`.

3. Add this test at the end of `main()`:

```dart
  testWidgets('the Coupons tile opens the Coupons screen', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_appFor());
    await tester.pumpAndSettle();

    final couponsTile = find.text('Coupons');
    await tester.ensureVisible(couponsTile);
    await tester.pumpAndSettle();
    await tester.tap(couponsTile);
    await tester.pumpAndSettle();

    expect(find.text('Coupons screen'), findsOneWidget);
  });
```

In `test/features/admin/admin_more_screen_test.dart`:

1. In the first test's list, add `'Coupons',` directly after `'Finance',`.
2. Add this test at the end of `main()`:

```dart
  testWidgets('the Coupons entry opens /admin/coupons', (tester) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final router = GoRouter(
      initialLocation: '/admin/more',
      routes: [
        GoRoute(path: '/admin/more', builder: (_, _) => const AdminMoreScreen()),
        GoRoute(
            path: '/admin/coupons',
            builder: (_, _) => const Text('Coupons screen')),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Coupons'));
    await tester.pumpAndSettle();

    expect(find.text('Coupons screen'), findsOneWidget);
  });
```

- [ ] **Step 2: Run them to verify they fail**

Run: `flutter test test/core/router_test.dart test/features/owner/owner_home_screen_test.dart test/features/admin/admin_more_screen_test.dart`
Expected: FAIL. The route list does not contain `/admin/coupons`, and there is no `Coupons` tile on either hub.

- [ ] **Step 3: Register the route**

In `lib/core/router.dart`, add the import next to the other admin screen imports:

```dart
import '../features/admin/coupons_screen.dart';
```

Then replace:

```dart
          GoRoute(
            path: '/admin/tasks',
            builder: (_, _) => const TasksScreen(),
          ),
```

with:

```dart
          GoRoute(
            path: '/admin/tasks',
            builder: (_, _) => const TasksScreen(),
          ),
          // Coupons (P1). Owner and admin only, through the /admin/* rule
          // in redirectFor; list_coupons and the write functions assert the
          // same roles in Postgres.
          GoRoute(
            path: '/admin/coupons',
            builder: (_, _) => const CouponsScreen(),
          ),
```

- [ ] **Step 4: Add the owner hub tile**

In `lib/features/owner/owner_home_screen.dart`, replace:

```dart
    (
      icon: Icons.meeting_room_outlined,
      title: 'Rooms',
      subtitle: 'Room status, housekeeping and maintenance',
      path: '/staff/rooms',
    ),
```

with:

```dart
    (
      icon: Icons.meeting_room_outlined,
      title: 'Rooms',
      subtitle: 'Room status, housekeeping and maintenance',
      path: '/staff/rooms',
    ),
    (
      icon: Icons.local_offer_outlined,
      title: 'Coupons',
      subtitle: 'Discount codes guests enter when they book',
      path: '/admin/coupons',
    ),
```

- [ ] **Step 5: Add the admin More tile**

In `lib/features/admin/admin_more_screen.dart`, replace:

```dart
    (
      icon: Icons.account_balance_outlined,
      title: 'Finance',
      subtitle: 'Collections, ledger, tax and settlements',
      path: '/finance',
    ),
```

with:

```dart
    (
      icon: Icons.account_balance_outlined,
      title: 'Finance',
      subtitle: 'Collections, ledger, tax and settlements',
      path: '/finance',
    ),
    (
      icon: Icons.local_offer_outlined,
      title: 'Coupons',
      subtitle: 'Discount codes guests enter when they book',
      path: '/admin/coupons',
    ),
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `flutter test test/core/router_test.dart test/features/owner/owner_home_screen_test.dart test/features/admin/admin_more_screen_test.dart && flutter analyze lib/core/router.dart lib/features/owner/owner_home_screen.dart lib/features/admin/admin_more_screen.dart`
Expected: all tests pass; `No issues found!`.

- [ ] **Step 7: Commit**

```bash
git add lib/core/router.dart lib/features/owner/owner_home_screen.dart \
  lib/features/admin/admin_more_screen.dart test/core/router_test.dart \
  test/features/owner/owner_home_screen_test.dart test/features/admin/admin_more_screen_test.dart
git commit -m "$(cat <<'EOF'
feat(coupons): route /admin/coupons from the owner hub and admin More

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 7: The guest's coupon code is sent upper-case

**Track:** App. It has no dependencies and can run at any time.

**Files:**
- Modify: `lib/features/booking/quote_sheet.dart` (`_apply`)
- Test: `test/features/booking/quote_sheet_test.dart`

**Interfaces:**
- Consumes: `QuoteSheet.onApplyCoupon(String code)` (unchanged signature).
- Produces: `onApplyCoupon` always receives the trimmed, upper-cased code. Codes are stored that way (`coupons_code_upper`), and `resolve_coupon` compares exactly.

- [ ] **Step 1: Write the failing test**

In `test/features/booking/quote_sheet_test.dart`, add this test directly after `'tapping Apply calls onApplyCoupon with the trimmed field text'`:

```dart
  testWidgets(
      'a code typed in lower case is applied upper-case, the way codes are '
      'stored', (tester) async {
    final applied = <String>[];
    await tester.pumpWidget(sheet(
      quote: quote,
      onApplyCoupon: (code) async => applied.add(code),
    ));

    await tester.enterText(find.byKey(const Key('coupon-field')), ' save10 ');
    await tester.tap(find.byKey(const Key('apply-coupon-button')));
    await tester.pump();

    expect(applied, ['SAVE10']);
  });
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/features/booking/quote_sheet_test.dart`
Expected: FAIL: `Expected: ['SAVE10'] Actual: ['save10']`.

- [ ] **Step 3: Upper-case in `_apply`**

In `lib/features/booking/quote_sheet.dart`, replace:

```dart
  void _apply() {
    final code = _controller.text.trim();
```

with:

```dart
  void _apply() {
    // Codes are stored upper-case (0051's coupons_code_upper) and
    // resolve_coupon compares exactly; textCapitalization does nothing on
    // a desktop keyboard, so normalise here.
    final code = _controller.text.trim().toUpperCase();
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/features/booking/`
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/features/booking/quote_sheet.dart test/features/booking/quote_sheet_test.dart
git commit -m "$(cat <<'EOF'
fix(booking): apply coupon codes upper-case

Codes are stored upper-case and matched exactly, so a code typed in
lower case on a desktop keyboard is now upper-cased before it is sent.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

## Phase 3: Integration

### Task 8: Merge the tracks and verify end to end

**Track:** both. Depends on Tasks 2–7.

**Files:** none are expected to change. Fix only what verification finds, in the file that owns it.

- [ ] **Step 1: Merge**

If the tracks ran in separate worktrees, merge the database branch and the app branch into the Task 1 branch. They share no files after Task 1, so the merge must be conflict-free. Run: `git log --oneline -10` and check that the Task 1–7 commits are all present.

- [ ] **Step 2: Full database suite**

Run: `supabase db reset && supabase test db`
Expected: 42 reports 89/89, 37 reports 77/77 and 11 reports 61/61. Everything else passes, apart from the 3 known time-of-day failures between 00:00 and 05:30 IST (compare with the Task 1 baseline).

- [ ] **Step 3: Full Flutter suite and analyzer**

Run: `flutter analyze 2>&1 | tail -5 && flutter test 2>&1 | tail -3`
Expected: only the 2 baseline infos in `service_request_screen.dart`, and every test passes. The pass count equals the baseline plus the new tests.

- [ ] **Step 4: Contract cross-check (Dart keys against SQL names)**

Run:

```bash
supabase db reset >/dev/null && psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -At -c "
select p.proname || '(' || array_to_string(p.proargnames, ',') || ')'
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public'
   and p.proname in ('list_coupons','find_resort_guest','create_coupon','update_coupon','set_coupon_active')
 order by 1;"
grep -n "'p_\|json\['" lib/data/repositories/coupon_repository.dart lib/data/models/coupon.dart
```

Expected: every `p_…` key and every `json['…']` key in the Dart files appears among the argument or OUT names printed for the matching function. The pgTAP contract (Task 1) pins the same names. This check catches a rename made on one side only during the parallel tracks.

- [ ] **Step 5: Manual smoke test against the local stack**

Run: `supabase start`, then `flutter run -d chrome`.
1. Sign in as `super@pasala.test` / `password123` (the resort owner in `supabase/seed.sql`).
2. Owner hub → Coupons shows "No coupons yet". Tap New coupon and enter code `welcome10`. The field shows `WELCOME10`. Choose Percentage, enter 10, and save. The card shows `Active`, `10% off`, `No date limits` and `Used 0 · Everyone`.
3. Create `RAVIVIP`: Fixed amount, 500, One guest, `ravi@example.com` → Find shows Ravi Kumar (he has a confirmed seeded booking), then save. Then try One guest with `meera@example.com` → Find says "No guest with that email has booked at this resort."
4. Create another coupon with code `welcome10`. The form shows "That code is already in use at this resort."
5. Sign out. Sign in as `meera@example.com` / `password123`, start a booking, type `welcome10` in the coupon field and Apply. The discount line reads `Coupon (WELCOME10)`. Abandon the hold.
6. Sign in as the owner again. WELCOME10 shows `Used 1` while the hold lives, or `Used 0` once it has expired. Deactivate it (confirm). The card shows `Inactive` and `Activate`. As Meera, the code is now refused ("coupon not found or inactive").
7. Sign in as `admin@pasala.test`. More → Coupons opens the same list. Sign in as `staff@pasala.test` and open `/admin/coupons` directly: you land on the not-found page.

- [ ] **Step 6: Commit any fixes**

If Steps 2–5 needed fixes, commit them with a message naming what was fixed. The message ends with a blank line and `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. If nothing needed fixing, there is nothing to commit.
