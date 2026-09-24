# Subscriptions and Tiers (REQ-08) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the ResortHub platform admin a real SaaS console: every resort has a Starter / Pro / Enterprise plan with a trial or paid-until date, the console shows Subscribed, Active and MRR cards, a live search and a tier filter, and the admin sets plans, trials and prices by hand. Owners see their plan read-only in Settings, and the login and sign-up cards say ResortHub.

**Architecture:** Two platform-owned tables, `subscription_plans` (tier, name, monthly INR price) and `resort_subscriptions` (one row per resort), are written only through `security definer` functions that check `is_platform_admin()`. "Lapsed" is never stored: `subscription_lapsed()` works it out on every read, and `properties.status` stays the only thing that locks a resort. On the app side, `PlatformSource` gains totals, plans and the three writes, and a new `ResortPlanSource` seam backs `resortPlanProvider`, a family keyed by property id, for the owner's Settings tile.

**Tech Stack:** Supabase Postgres 15 (plpgsql, RLS, pgTAP via `supabase test db`), Flutter 3.44 / Dart 3.10, Riverpod 3.3, go_router 17.

**Spec:** `docs/superpowers/specs/2026-09-25-subscriptions-design.md`

## Global Constraints

- One migration: `supabase/migrations/0049_subscriptions.sql`. It comes after B's `0047_room_status.sql` and C's `0048_finance_ledger.sql` and touches none of their objects, so it also applies cleanly if they have not landed yet. Tasks 1–3 each edit it. After every edit, rebuild with `supabase db reset` (this re-runs every migration and `supabase/seed.sql`), then run pgTAP. Before the first reset in this plan, dump local data if you need it: `mkdir -p ../pasala-db-backups && supabase db dump --local --data-only -f ../pasala-db-backups/local-before-subscriptions.sql`.
- New pgTAP file: `supabase/tests/41_subscriptions_test.sql`. Tasks 1–3 build it up section by section, and each section relies on the state the earlier ones leave. Run one file with `supabase test db supabase/tests/41_subscriptions_test.sql` and the whole suite with `supabase test db`.
- No new error codes (P0032 and up stay free). Bad input is **P0005** with a message written for the admin (the app shows P0005 text verbatim as `InvalidState`), an unknown resort is **P0002**, a caller who is not the platform admin gets **P0008**, and a caller who is not an owner/admin of the resort gets **P0020** (from `assert_resort_role`).
- Every new `security definer` function has `set search_path = public, pg_temp`, is revoked from `public` and `anon`, is granted to `authenticated`, and is added to the definer allow-list in `supabase/tests/37_tenancy_isolation_test.sql`.
- Existing functions changed here (`platform_resorts`, `create_resort`) are copied from their **latest** definition, which is in `0045_resort_functions.sql` (lines 2608–2762). Neither is redefined in 0046–0048.
- Tiers: `starter`, `pro`, `enterprise`, labelled `Starter`, `Pro`, `Enterprise`. No free tier. Statuses: `trial`, `active`, `cancelled`, labelled `Trial`, `Active`, `Cancelled`.
- Placeholder monthly prices: Starter **2999**, Pro **7999**, Enterprise **19999** (INR).
- Existing resorts get `enterprise` / `active` / no end date.
- "Today" is the `Asia/Kolkata` calendar date: `(now() at time zone 'Asia/Kolkata')::date`. A plan is good **through** its end date and lapses the day after.
- Counts (spec decisions 6 and 7): Subscribed = has a row, not `cancelled`, resort not `archived`. Active = subscribed and not lapsed. Trials = live (not lapsed) trials. MRR = the sum of `monthly_price_inr` over `active`, not lapsed rows of non-archived resorts.
- The platform admin gets no direct row access to `resort_subscriptions`. Owners and admins read their own resort's row only.
- pgTAP conventions (from `37_tenancy_isolation_test.sql`): switch users with `set local role authenticated; set local request.jwt.claims to '{"sub":"<uuid>","role":"authenticated"}';`. `reset role` does **not** clear the claims, so run `set local request.jwt.claims to '';` after it.
- Dart: repositories wrap every call in `_guard`, which maps errors through `mapPostgrestError` (`lib/core/errors.dart`). Widget tests use fakes from `test/support/` and never a real `SupabaseClient`. A widget test that expects an error state passes `retry: (_, _) => null` to its `ProviderScope`, because Riverpod 3 otherwise retries a failed provider with backoff (see `test/features/calendar/availability_calendar_test.dart:193`).
- UI copy, exact:
  - Cards: `Subscribed resorts`, `Active subscriptions`, `incl. <n> trial` / `incl. <n> trials`, `MRR`.
  - Filter: search label `Search resorts or owner emails`; tier menu `All tiers`, `Starter`, `Pro`, `Enterprise`; no match `No resorts match your search.`
  - Plan lines: `Trial until <d MMM yyyy>`, `Lapsed: trial ended <date>`, `Paid until <date>`, `Lapsed: paid until <date>`, `Paid, no end date`, `Cancelled`. A resort without a row: chip `No plan`, button `Set plan`; otherwise `Change plan`.
  - Buttons: `Add resort`, `Plan prices`.
  - Owner tile: `Plan: <name>` over the plan line; `Plan: not set up` / `Contact ResortHub to choose a plan`; `Plan` / `Could not load your plan`.
  - Login and sign-up heading: `ResortHub`.
- Lapsed is never shown by colour alone: it carries a warning icon and the word "Lapsed".
- Commands: `flutter test <path>`, `flutter test`, and `flutter analyze` (no new issues beyond the baseline recorded in Task 1 Step 1). Never run `dart format` over whole directories, because the repo is not formatted with the current SDK. Format only the lines you write.

## Review Focus

1. **A plan that ends today must not show Lapsed**, and the day boundary is Asia/Kolkata, not UTC. An admin who records "paid until 31 Oct" expects the resort to count on 31 Oct. Owning tests: Task 2 (`subscription_lapsed` at today and yesterday; the resort paid until today is active and in MRR).
2. **A resort with no subscription row** (created in SQL, or local seed data) must still show on the console, count for nothing, and be fixable. People expect "No plan" and a way to set one, not a crash or a phantom Enterprise. Owning tests: Task 2 (no-plan columns, not counted), Task 3 (`set_resort_subscription` creates the row), Task 1 (`ResortPlan.fromRow` gives null), Task 5 (`No plan` chip and `Set plan`).
3. **Switching an active plan to Trial without picking an end date** must not save a trial that never ends. Owning tests: Task 5 (the dialog refuses and makes no call), Task 3 (the server refuses with P0005).
4. **Search typed with capitals or stray spaces, or on an owner's email, and the tier filter over resorts with no plan.** People expect "  RESORT a " to find Resort A, and "Pro" to hide plan-less resorts while "All tiers" shows them. Owning tests: Task 4 (`filterResorts` unit tests and the console tests).
5. **The owner's plan fails to load** (network, or a stale resort). The rest of Settings must still work and the tile must say so rather than spin. Owning test: Task 7 (error state keeps "Farmhouse information").

## Plan decisions (where the spec is silent or leaves a choice)

- Task 1 fixes the contract without breaking the running app or `38_resort_members_test.sql`: the new `platform_resorts()` keeps the old body and returns empty plan columns (`lapsed` false), and the new four-argument `create_resort` keeps the old body and ignores the tier and trial days. Tasks 2 and 3 replace those bodies. The four brand-new functions are stubs that raise `0A000`.
- `38_resort_members_test.sql` pinned `platform_resorts`' result as text and cast `'public.create_resort(text, text)'::regprocedure`. Task 1 changes the first to a check on the OUT parameter names (the same "summary columns only" intent, without depending on how Postgres prints enum types) and the second to the new signature. Its plan count stays 54.
- `41_subscriptions_test.sql` starts with `delete from public.resort_subscriptions;` inside its transaction. `platform_summary` counts every resort in the database, and the seeded resort would otherwise change the numbers.
- The backfill only has rows to work on in a database that already has resorts, never in a fresh `supabase db reset`. Task 2 checks it once by hand (reset to the migration before 0049 without the seed, add a resort, apply 0049). `supabase/seed.sql` gets the same Enterprise row, because the seed runs after the migrations.
- Prices are edited with a new `set_plan_price` function (spec decision 11). `subscription_plans` therefore carries a `uuid id` for the audit log's `entity_id`, which is `not null`.
- A tier gates nothing, so `SubscriptionTier.label` is the display name everywhere in the app. The server's `plan_name` is shown only where it comes back with the plan (the owner tile).
- The platform console keeps its filter state in the screen's `State` (no provider): it is per-visit UI state.
- `FakePlatformRepository` moves out of `platform_screen_test.dart` into `test/support/fake_platform_source.dart` as `FakePlatformSource`, because four test files now need it.

## Execution tracks

After Task 1, the database track and the app track share no files and can run in parallel, for example in two worktrees branched from Task 1's commit and merged back before Task 9. App tasks never need a database, because their tests use `FakePlatformSource` and `FakeResortPlanSource`.

| Task | Track | Depends on | Files it owns |
|---|---|---|---|
| 1 Interface contract | both | none | `0049` (schema, backfill, stubs), `41` (fixtures + contract), `37` (allow-list), `38` (signature checks), `subscription.dart`, `platform_repository.dart`, `subscription_repository.dart`, both fakes, `platform_screen_test.dart` (fake swap) |
| 2 Reading plans, counts and MRR | DB | 1 | `0049`, `41`, `seed.sql` |
| 3 Creating resorts, changing plans and prices | DB | 2 | `0049`, `41` |
| 4 Console cards, search and tier filter | App | 1 | `platform_screen.dart`, `platform_totals_row.dart`, `resort_filter.dart`, `resort_card.dart` (moved), `platform_screen_test.dart`, `resort_filter_test.dart` |
| 5 Plan line and Change plan dialog | App | 4 | `resort_card.dart`, `change_plan_dialog.dart`, `resort_card_test.dart`, `change_plan_dialog_test.dart` |
| 6 Add resort with a plan, and plan prices | App | 4 | `platform_screen.dart`, `new_resort_dialog.dart`, `plan_prices_dialog.dart`, `platform_screen_test.dart`, `new_resort_dialog_test.dart`, `plan_prices_dialog_test.dart` |
| 7 Owner's plan in Settings | App | 1 | `owner_settings_screen.dart`, `owner_settings_screen_test.dart` |
| 8 ResortHub on login and sign-up | App | none | `login_screen.dart`, `signup_screen.dart`, their tests |
| 9 Integration | both | 2–8 | none (verification) |

- The database track is strictly sequential: Tasks 2 and 3 share one migration file, one test file and one local Postgres.
- In the app track, Tasks 5 and 6 wait for Task 4 and can then run alongside each other. Tasks 7 and 8 can run alongside everything (Task 8 does not even need Task 1).

---

## File Structure

**Database**
- Create `supabase/migrations/0049_subscriptions.sql`: the enums, `subscription_plans` (seeded), `resort_subscriptions` with RLS, the backfill, `subscription_lapsed`, the new `platform_resorts`, `platform_summary`, `my_resort_subscription`, the new `create_resort`, `set_resort_subscription` and `set_plan_price`.
- Create `supabase/tests/41_subscriptions_test.sql`: fixtures, contract, RLS, lapsed, counts and MRR, the owner read, the writes, audit.
- Modify `supabase/tests/37_tenancy_isolation_test.sql`: the definer allow-list.
- Modify `supabase/tests/38_resort_members_test.sql`: the `platform_resorts` column check and the `create_resort` signature in the grant checks.
- Modify `supabase/seed.sql`: the seeded resort starts on Enterprise.

**App**
- Create `lib/data/models/subscription.dart`: `SubscriptionTier`, `SubscriptionStatus`, `SubscriptionPlan`, `PlatformTotals`, `ResortPlan`, `planStatusLine`, `dateToDb`.
- Modify `lib/data/repositories/platform_repository.dart`: `ResortSummary.plan`, the wider `PlatformSource`, `platformTotalsProvider`, `subscriptionPlansProvider`.
- Create `lib/data/repositories/subscription_repository.dart`: `ResortPlanSource`, `SubscriptionRepository`, `resortPlanProvider`.
- Modify `lib/features/platform/platform_screen.dart`: cards, filter, the `Add resort` button and the `Plan prices` action.
- Create `lib/features/platform/platform_totals_row.dart`: the three cards.
- Create `lib/features/platform/resort_filter.dart`: `filterResorts` and `ResortFilterBar`.
- Create `lib/features/platform/resort_card.dart`: `ResortCard` (moved out of the screen) and `PlanLine`.
- Create `lib/features/platform/change_plan_dialog.dart`, `lib/features/platform/new_resort_dialog.dart` (moved out of the screen) and `lib/features/platform/plan_prices_dialog.dart`.
- Modify `lib/features/owner/owner_settings_screen.dart`: the Plan tile.
- Modify `lib/features/auth/login_screen.dart` and `lib/features/auth/signup_screen.dart`: the ResortHub heading.
- Create `test/support/fake_platform_source.dart`, `test/support/fake_resort_plan_source.dart`, `test/data/subscription_test.dart`, `test/data/platform_providers_test.dart`, `test/features/platform/resort_filter_test.dart`, `test/features/platform/resort_card_test.dart`, `test/features/platform/change_plan_dialog_test.dart`, `test/features/platform/new_resort_dialog_test.dart`, `test/features/platform/plan_prices_dialog_test.dart` and `test/features/owner/owner_settings_screen_test.dart`. Modify `test/features/platform/platform_screen_test.dart`, `test/features/auth/login_screen_test.dart` and `test/features/auth/signup_screen_test.dart`.

---

## Phase 0: Interface

### Task 1: Interface contract (schema, function signatures, Dart API)

**Track:** both. Every later task except Task 8 depends on it.

**Files:**
- Create: `supabase/migrations/0049_subscriptions.sql`
- Create: `supabase/tests/41_subscriptions_test.sql`
- Modify: `supabase/tests/37_tenancy_isolation_test.sql` (definer allow-list)
- Modify: `supabase/tests/38_resort_members_test.sql:99-102` and the two `create_resort(text, text)` grant entries near line 339
- Create: `lib/data/models/subscription.dart`
- Modify: `lib/data/repositories/platform_repository.dart` (whole file)
- Create: `lib/data/repositories/subscription_repository.dart`
- Create: `test/support/fake_platform_source.dart`, `test/support/fake_resort_plan_source.dart`
- Modify: `test/features/platform/platform_screen_test.dart:1-60` (use the shared fake)
- Test: `test/data/subscription_test.dart`, `test/data/platform_providers_test.dart`

**Interfaces:**
- Consumes: `public.is_platform_admin()`, `public.has_resort_role(uuid, boolean, variadic resort_role[])`, `public.assert_resort_role(...)` (0043/0046); the 0045 bodies of `platform_resorts()` and `create_resort(text, text)`; `formatDate` (`lib/core/format.dart`), `mapPostgrestError`, `supabaseProvider`.
- Produces (SQL; later tasks replace only the bodies):
  - Enums `public.subscription_tier ('starter','pro','enterprise')` and `public.subscription_status ('trial','active','cancelled')`.
  - Tables `public.subscription_plans (tier pk, id uuid unique, name, monthly_price_inr numeric(12,2), sort_order, updated_at)` and `public.resort_subscriptions (property_id pk, tier, status, trial_ends_on date, paid_through date, notes, updated_at, updated_by)`.
  - `public.platform_resorts() returns table (property_id uuid, name text, status text, owner_emails text[], created_at timestamptz, bookings_30d int, revenue_30d numeric, bookings_365d int, revenue_365d numeric, plan_tier public.subscription_tier, plan_name text, plan_status public.subscription_status, trial_ends_on date, paid_through date, lapsed boolean, monthly_price_inr numeric, plan_notes text)`
  - `public.platform_summary() returns table (subscribed_count int, active_count int, trial_count int, mrr_inr numeric)`
  - `public.my_resort_subscription(p_property uuid) returns table (plan_tier public.subscription_tier, plan_name text, plan_status public.subscription_status, trial_ends_on date, paid_through date, lapsed boolean, monthly_price_inr numeric, plan_notes text)`
  - `public.create_resort(p_name text, p_owner_email text, p_tier public.subscription_tier default 'starter', p_trial_days int default 30) returns uuid` (the two-argument version is dropped)
  - `public.set_resort_subscription(p_property uuid, p_tier public.subscription_tier, p_status public.subscription_status, p_trial_ends_on date default null, p_paid_through date default null, p_notes text default null) returns void`
  - `public.set_plan_price(p_tier public.subscription_tier, p_monthly_price_inr numeric) returns void`
- Produces (Dart):
  - `enum SubscriptionTier { starter, pro, enterprise }` with `subscriptionTierFromDb(String)`, `subscriptionTierToDb(SubscriptionTier)` and the `label` getter (extension `SubscriptionTierLabel`).
  - `enum SubscriptionStatus { trial, active, cancelled }` with `subscriptionStatusFromDb`, `subscriptionStatusToDb` and `label` (extension `SubscriptionStatusLabel`).
  - `class SubscriptionPlan { tier, name, monthlyPriceInr (num), sortOrder }` with `fromJson`.
  - `class PlatformTotals { subscribed, active, trials (int), mrrInr (num) }` with `fromJson` and `PlatformTotals.zero`.
  - `class ResortPlan { tier, name, status, trialEndsOn, paidThrough (DateTime?, date only), lapsed, monthlyPriceInr, notes }` with `static ResortPlan? fromRow(Map<String, dynamic>)`.
  - `String planStatusLine(ResortPlan plan)` and `String dateToDb(DateTime d)`.
  - `ResortSummary` gains `final ResortPlan? plan` and `copyWith({String? status, ResortPlan? plan})`.
  - `abstract class PlatformSource`:
    - `Future<List<ResortSummary>> resorts()`
    - `Future<PlatformTotals> totals()`
    - `Future<List<SubscriptionPlan>> plans()`
    - `Future<void> setStatus(String propertyId, String status)`
    - `Future<String> createResort(String name, String ownerEmail, {SubscriptionTier tier = SubscriptionTier.starter, int trialDays = 30})`
    - `Future<void> setSubscription(String propertyId, {required SubscriptionTier tier, required SubscriptionStatus status, DateTime? trialEndsOn, DateTime? paidThrough, String? notes})`
    - `Future<void> setPlanPrice(SubscriptionTier tier, num monthlyPriceInr)`
  - Providers: `platformSourceProvider`, `platformResortsProvider` (unchanged), `platformTotalsProvider` (`FutureProvider<PlatformTotals>`), `subscriptionPlansProvider` (`FutureProvider<List<SubscriptionPlan>>`).
  - `abstract class ResortPlanSource { Future<ResortPlan?> resortPlan(String propertyId); }`, `resortPlanSourceProvider`, and `resortPlanProvider` (`FutureProvider.autoDispose.family<ResortPlan?, String>`, keyed by property id).
  - Test support: `FakePlatformSource` (fields `store`, `totalsValue`, `planList`, `resortsError`, `totalsError`, `plansError`, `setStatusError`, `createError`, `subscriptionError`, `priceError`; logs `statusCalls`, `createCalls` as `(String, String, SubscriptionTier, int)`, `subscriptionCalls` as `SubscriptionCall`, `priceCalls` as `(SubscriptionTier, num)`, and the counters `resortsCalls`, `totalsCalls`, `plansCalls`), the builders `resortSummary({...})` and `resortPlan({...})`, `defaultPlans`; and `FakeResortPlanSource` (`plan`, `error`, `calls`).

- [ ] **Step 1: Record the baselines**

Run: `supabase db reset && supabase test db 2>&1 | tail -20`, then `flutter analyze 2>&1 | tail -5`, then `flutter test 2>&1 | tail -3`
Expected: write down the pgTAP failure count and names. The tenancy ledger records 3 pre-existing time-of-day failures around the Asia/Kolkata midnight boundary. Also write down the analyzer issue count and the Flutter pass count. Later tasks compare against these numbers. Also run `ls supabase/migrations | tail -4` and write down the last migration before 0049 (`0048_finance_ledger.sql` if C has landed, otherwise an earlier one). Task 2 Step 7 needs it.

- [ ] **Step 2: Write the failing pgTAP contract test**

Create `supabase/tests/41_subscriptions_test.sql`:

```sql
-- Subscriptions and tiers (REQ-08), added in 0049_subscriptions.sql. See
-- docs/superpowers/specs/2026-09-25-subscriptions-design.md.
--
-- One file, built up by the plan's database tasks in order: each section
-- relies on the state the sections before it leave behind.
--
-- Fixtures: a platform admin; resort "Sub Paid" (P1) with an owner, an
-- admin, a staff member and an accountant; a second owner who owns "Sub
-- Open" (P2), "Sub Suspended" (P8) and "Sub None" (P9); and a guest with
-- no membership. P1-P9 cover every case the counts must handle:
--   P1 Pro, active, paid until today      -> active, in MRR
--   P2 Enterprise, active, no end date    -> active, in MRR
--   P3 Starter trial ending in 5 days     -> active, a live trial
--   P4 Starter trial that ended yesterday -> subscribed, lapsed
--   P5 Pro, active, paid until 3 days ago -> subscribed, lapsed
--   P6 Pro, cancelled                     -> not subscribed
--   P7 archived resort, Enterprise active -> counts for nothing
--   P8 suspended resort, Starter active   -> active, in MRR
--   P9 no subscription row                -> "No plan", counts for nothing
begin;
select plan(21);

-- "Today" as the subscription functions see it.
create function pg_temp.today() returns date
language sql stable as $f$ select (now() at time zone 'Asia/Kolkata')::date $f$;

-- platform_summary counts every resort in the database. Start from no
-- subscription rows so the seeded resort (and any other) counts for nothing.
delete from public.resort_subscriptions;

insert into auth.users (id, email) values
  ('f0000000-0000-0000-0000-000000000001','sub-platform@example.com'),
  ('f0000000-0000-0000-0000-000000000002','sub-owner@example.com'),
  ('f0000000-0000-0000-0000-000000000003','sub-admin@example.com'),
  ('f0000000-0000-0000-0000-000000000004','sub-staff@example.com'),
  ('f0000000-0000-0000-0000-000000000005','sub-accountant@example.com'),
  ('f0000000-0000-0000-0000-000000000006','sub-other-owner@example.com'),
  ('f0000000-0000-0000-0000-000000000007','sub-guest@example.com');
update public.profiles set role = 'platform_admin'
  where id = 'f0000000-0000-0000-0000-000000000001';

insert into public.properties (id, name, slug, status) values
  ('f1000000-0000-4000-8000-000000000001','Sub Paid','sub-paid','active'),
  ('f1000000-0000-4000-8000-000000000002','Sub Open','sub-open','active'),
  ('f1000000-0000-4000-8000-000000000003','Sub Trial','sub-trial','active'),
  ('f1000000-0000-4000-8000-000000000004','Sub Trial Lapsed','sub-trial-lapsed','active'),
  ('f1000000-0000-4000-8000-000000000005','Sub Paid Lapsed','sub-paid-lapsed','active'),
  ('f1000000-0000-4000-8000-000000000006','Sub Cancelled','sub-cancelled','active'),
  ('f1000000-0000-4000-8000-000000000007','Sub Archived','sub-archived','archived'),
  ('f1000000-0000-4000-8000-000000000008','Sub Suspended','sub-suspended','suspended'),
  ('f1000000-0000-4000-8000-000000000009','Sub None','sub-none','active');

insert into public.resort_members (property_id, user_id, role) values
  ('f1000000-0000-4000-8000-000000000001','f0000000-0000-0000-0000-000000000002','owner'),
  ('f1000000-0000-4000-8000-000000000001','f0000000-0000-0000-0000-000000000003','admin'),
  ('f1000000-0000-4000-8000-000000000001','f0000000-0000-0000-0000-000000000004','staff'),
  ('f1000000-0000-4000-8000-000000000001','f0000000-0000-0000-0000-000000000005','accountant'),
  ('f1000000-0000-4000-8000-000000000002','f0000000-0000-0000-0000-000000000006','owner'),
  ('f1000000-0000-4000-8000-000000000008','f0000000-0000-0000-0000-000000000006','owner'),
  ('f1000000-0000-4000-8000-000000000009','f0000000-0000-0000-0000-000000000006','owner');

insert into public.resort_subscriptions (property_id, tier, status, trial_ends_on, paid_through) values
  ('f1000000-0000-4000-8000-000000000001','pro','active',null,pg_temp.today()),
  ('f1000000-0000-4000-8000-000000000002','enterprise','active',null,null),
  ('f1000000-0000-4000-8000-000000000003','starter','trial',pg_temp.today() + 5,null),
  ('f1000000-0000-4000-8000-000000000004','starter','trial',pg_temp.today() - 1,null),
  ('f1000000-0000-4000-8000-000000000005','pro','active',null,pg_temp.today() - 3),
  ('f1000000-0000-4000-8000-000000000006','pro','cancelled',null,null),
  ('f1000000-0000-4000-8000-000000000007','enterprise','active',null,null),
  ('f1000000-0000-4000-8000-000000000008','starter','active',null,null);

-- === Task 1: the contract ===================================================

select has_table('public', 'subscription_plans', 'subscription_plans exists');
select has_table('public', 'resort_subscriptions', 'resort_subscriptions exists');
select enum_has_labels('public', 'subscription_tier', array['starter','pro','enterprise'],
  'the tiers are starter, pro and enterprise -- no free tier');
select enum_has_labels('public', 'subscription_status', array['trial','active','cancelled'],
  'lapsed is never stored');
select is((select array_agg(tier::text || ':' || name || ':' || monthly_price_inr::int order by sort_order)
             from public.subscription_plans),
  array['starter:Starter:2999','pro:Pro:7999','enterprise:Enterprise:19999'],
  'the three plans are seeded at the placeholder prices');
select is((select array_agg(p.parameter_name::text order by p.ordinal_position)
             from information_schema.parameters p
             join information_schema.routines r
               on r.specific_schema = p.specific_schema and r.specific_name = p.specific_name
            where r.routine_schema = 'public' and r.routine_name = 'platform_resorts'
              and p.parameter_mode = 'OUT'),
  array['property_id','name','status','owner_emails','created_at',
        'bookings_30d','revenue_30d','bookings_365d','revenue_365d',
        'plan_tier','plan_name','plan_status','trial_ends_on','paid_through',
        'lapsed','monthly_price_inr','plan_notes'],
  'platform_resorts returns the columns ResortSummary.fromJson reads');
select is((select array_agg(p.parameter_name::text order by p.ordinal_position)
             from information_schema.parameters p
             join information_schema.routines r
               on r.specific_schema = p.specific_schema and r.specific_name = p.specific_name
            where r.routine_schema = 'public' and r.routine_name = 'platform_summary'
              and p.parameter_mode = 'OUT'),
  array['subscribed_count','active_count','trial_count','mrr_inr'],
  'platform_summary returns the columns PlatformTotals.fromJson reads');
select is((select array_agg(p.parameter_name::text order by p.ordinal_position)
             from information_schema.parameters p
             join information_schema.routines r
               on r.specific_schema = p.specific_schema and r.specific_name = p.specific_name
            where r.routine_schema = 'public' and r.routine_name = 'my_resort_subscription'
              and p.parameter_mode = 'OUT'),
  array['plan_tier','plan_name','plan_status','trial_ends_on','paid_through',
        'lapsed','monthly_price_inr','plan_notes'],
  'my_resort_subscription returns the columns ResortPlan.fromRow reads');
select ok(to_regprocedure('public.create_resort(text, text, public.subscription_tier, integer)') is not null,
  'create_resort takes a tier and a number of trial days');
select ok(to_regprocedure('public.create_resort(text, text)') is null,
  'the two-argument create_resort is gone, so no call is ambiguous');
select is((select array_agg(f::text order by f::text)
             from unnest(array[
               'public.platform_resorts()',
               'public.platform_summary()',
               'public.my_resort_subscription(uuid)',
               'public.create_resort(text, text, public.subscription_tier, integer)',
               'public.set_resort_subscription(uuid, public.subscription_tier, public.subscription_status, date, date, text)',
               'public.set_plan_price(public.subscription_tier, numeric)']::regprocedure[]) f
            where has_function_privilege('anon', f, 'execute')),
  null, 'anon can execute none of the subscription functions');
select is((select count(*)::int
             from unnest(array[
               'public.platform_resorts()',
               'public.platform_summary()',
               'public.my_resort_subscription(uuid)',
               'public.create_resort(text, text, public.subscription_tier, integer)',
               'public.set_resort_subscription(uuid, public.subscription_tier, public.subscription_status, date, date, text)',
               'public.set_plan_price(public.subscription_tier, numeric)']::regprocedure[]) f
            where has_function_privilege('authenticated', f, 'execute')),
  6, 'authenticated can execute all six');
select throws_ok($$insert into public.resort_subscriptions (property_id, tier, status)
  values ('f1000000-0000-4000-8000-000000000009', 'starter', 'trial')$$,
  '23514', null, 'a trial without an end date is refused by the table itself');

-- Direct reads and writes. Owners and admins read their own resort's row;
-- nobody writes directly, not even the platform admin.
set local role authenticated;
set local request.jwt.claims to '{"sub":"f0000000-0000-0000-0000-000000000002","role":"authenticated"}';
select is((select array_agg(property_id::text) from public.resort_subscriptions),
  array['f1000000-0000-4000-8000-000000000001'],
  'an owner reads only their own resort''s subscription');
select is((select count(*)::int from public.subscription_plans), 3, 'an owner reads the plans');
select throws_ok($$insert into public.resort_subscriptions (property_id, tier, status)
  values ('f1000000-0000-4000-8000-000000000009', 'enterprise', 'active')$$,
  '42501', null, 'an owner cannot write a subscription directly');
select throws_ok($$update public.resort_subscriptions set tier = 'enterprise'$$,
  '42501', null, 'an owner cannot upgrade their own plan directly');
set local request.jwt.claims to '{"sub":"f0000000-0000-0000-0000-000000000003","role":"authenticated"}';
select is((select count(*)::int from public.resort_subscriptions), 1,
  'an admin reads their resort''s subscription');
set local request.jwt.claims to '{"sub":"f0000000-0000-0000-0000-000000000004","role":"authenticated"}';
select is((select count(*)::int from public.resort_subscriptions), 0, 'staff read no subscriptions');
set local request.jwt.claims to '{"sub":"f0000000-0000-0000-0000-000000000001","role":"authenticated"}';
select is((select count(*)::int from public.resort_subscriptions), 0,
  'the platform admin has no direct row access');
select throws_ok($$update public.subscription_plans set monthly_price_inr = 0$$,
  '42501', null, 'the platform admin changes prices only through set_plan_price');
reset role;
set local request.jwt.claims to '';

select * from finish();
rollback;
```

- [ ] **Step 3: Run it to verify it fails**

Run: `supabase test db supabase/tests/41_subscriptions_test.sql`
Expected: FAIL at `delete from public.resort_subscriptions` with `relation "public.resort_subscriptions" does not exist`.

- [ ] **Step 4: Write the migration's schema, backfill and function contract**

Create `supabase/migrations/0049_subscriptions.sql`:

```sql
-- Subscriptions and tiers (REQ-08): one plan per resort, set by hand by
-- the platform admin, with trials, a paid-until date and monthly prices
-- for MRR. Nothing here locks a resort: properties.status stays the only
-- lock. See docs/superpowers/specs/2026-09-25-subscriptions-design.md.
--
-- Errors: P0005 bad input (messages written for the admin, shown
-- verbatim), P0002 unknown resort, P0008 not the platform admin, P0020
-- not an owner/admin of the resort. No new codes.

create type public.subscription_tier as enum ('starter', 'pro', 'enterprise');
-- "Lapsed" is never stored: subscription_lapsed() works it out on read.
create type public.subscription_status as enum ('trial', 'active', 'cancelled');

-- ---------------------------------------------------------------------
-- subscription_plans: the tiers and their monthly prices. Readable by any
-- signed-in user; changed only by set_plan_price. `id` exists for the
-- audit log, whose entity_id is a non-null uuid.
create table public.subscription_plans (
  tier              public.subscription_tier primary key,
  id                uuid not null unique default gen_random_uuid(),
  name              text not null,
  monthly_price_inr numeric(12,2) not null
    constraint subscription_plans_price_not_negative check (monthly_price_inr >= 0),
  sort_order        int not null,
  updated_at        timestamptz not null default now()
);

-- Placeholder prices (spec decision 11); the platform admin edits them on
-- the console.
insert into public.subscription_plans (tier, name, monthly_price_inr, sort_order) values
  ('starter', 'Starter', 2999, 1),
  ('pro', 'Pro', 7999, 2),
  ('enterprise', 'Enterprise', 19999, 3);

alter table public.subscription_plans enable row level security;
revoke all on public.subscription_plans from anon, authenticated;
grant select on public.subscription_plans to authenticated;
create policy subscription_plans_read on public.subscription_plans
  for select to authenticated using (true);

-- ---------------------------------------------------------------------
-- resort_subscriptions: one row per resort. A resort with no row has "No
-- plan" and counts for nothing. Readable by the resort's owners and
-- admins; written only by the security definer functions below (no write
-- grant or policy, not even for the platform admin).
create table public.resort_subscriptions (
  property_id   uuid primary key references public.properties(id) on delete cascade,
  tier          public.subscription_tier not null references public.subscription_plans(tier),
  status        public.subscription_status not null,
  trial_ends_on date,
  -- null = no end date.
  paid_through  date,
  -- Visible to the resort's owners and admins: not a private field.
  notes         text,
  updated_at    timestamptz not null default now(),
  updated_by    uuid default auth.uid(),
  constraint resort_subscriptions_trial_has_end
    check (status <> 'trial' or trial_ends_on is not null)
);
create index resort_subscriptions_tier_idx on public.resort_subscriptions (tier);

alter table public.resort_subscriptions enable row level security;
revoke all on public.resort_subscriptions from anon, authenticated;
grant select on public.resort_subscriptions to authenticated;
create policy resort_subscriptions_read on public.resort_subscriptions
  for select to authenticated
  using (public.has_resort_role(property_id, false, 'owner','admin'));

-- Every resort that exists before this migration starts on Enterprise,
-- active, with no end date (spec decision 9). supabase/seed.sql does the
-- same for the seeded resort, because the seed runs after migrations.
insert into public.resort_subscriptions (property_id, tier, status)
select id, 'enterprise', 'active' from public.properties
on conflict (property_id) do nothing;

-- ---------------------------------------------------------------------
-- Functions. The signatures are the contract the app is built against;
-- Tasks 2 and 3 of the plan replace the bodies.

-- Adds the plan columns. Until Task 2 the body is 0045's with empty plan
-- columns, so the console keeps working.
drop function public.platform_resorts();

create function public.platform_resorts()
returns table(
  property_id       uuid,
  name              text,
  status            text,
  owner_emails      text[],
  created_at        timestamptz,
  bookings_30d      int,
  revenue_30d       numeric,
  bookings_365d     int,
  revenue_365d      numeric,
  plan_tier         public.subscription_tier,
  plan_name         text,
  plan_status       public.subscription_status,
  trial_ends_on     date,
  paid_through      date,
  lapsed            boolean,
  monthly_price_inr numeric,
  plan_notes        text
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  if not public.is_platform_admin() then
    raise exception 'not permitted' using errcode = 'P0008';
  end if;

  return query
    select
      p.id,
      p.name,
      p.status,
      coalesce((
        select array_agg(u.email::text order by u.email)
          from public.resort_members m
          join auth.users u on u.id = m.user_id
         where m.property_id = p.id and m.role = 'owner'), '{}'),
      p.created_at,
      coalesce(b.bookings_30d, 0),
      coalesce(b.revenue_30d, 0),
      coalesce(b.bookings_365d, 0),
      coalesce(b.revenue_365d, 0),
      null::public.subscription_tier,
      null::text,
      null::public.subscription_status,
      null::date,
      null::date,
      false,
      null::numeric,
      null::text
    from public.properties p
    left join lateral (
      select
        (count(*) filter (where r.created_at >= now() - interval '30 days'))::int
          as bookings_30d,
        sum((r.quote ->> 'total')::numeric)
          filter (where r.created_at >= now() - interval '30 days') as revenue_30d,
        count(*)::int as bookings_365d,
        sum((r.quote ->> 'total')::numeric) as revenue_365d
      from public.reservations r
      where r.property_id = p.id
        and r.kind = 'booking'
        and r.status in ('confirmed','checked_in','checked_out')
        and r.created_at >= now() - interval '365 days'
    ) b on true
    order by p.created_at, p.name;
end;
$$;

create function public.platform_summary()
returns table(
  subscribed_count int,
  active_count     int,
  trial_count      int,
  mrr_inr          numeric
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  raise exception 'platform_summary is not implemented yet' using errcode = '0A000';
end;
$$;

create function public.my_resort_subscription(p_property uuid)
returns table(
  plan_tier         public.subscription_tier,
  plan_name         text,
  plan_status       public.subscription_status,
  trial_ends_on     date,
  paid_through      date,
  lapsed            boolean,
  monthly_price_inr numeric,
  plan_notes        text
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  raise exception 'my_resort_subscription is not implemented yet' using errcode = '0A000';
end;
$$;

-- Adds a tier and trial days. Dropping the two-argument version keeps
-- PostgREST and SQL callers from ever hitting an ambiguous overload. Until
-- Task 3 the body is 0045's and ignores the new parameters.
drop function public.create_resort(text, text);

create function public.create_resort(
  p_name        text,
  p_owner_email text,
  p_tier        public.subscription_tier default 'starter',
  p_trial_days  int default 30
) returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_owner uuid;
  v_base  text;
  v_slug  text;
  v_n     int := 1;
  v_id    uuid;
begin
  if not public.is_platform_admin() then
    raise exception 'not permitted' using errcode = 'P0008';
  end if;

  if coalesce(trim(p_name), '') = '' then
    raise exception 'name is required' using errcode = 'P0005';
  end if;

  select id into v_owner from auth.users
   where lower(email) = lower(trim(p_owner_email));
  if v_owner is null then
    raise exception using errcode = 'P0002', message = 'not_found';
  end if;

  v_base := trim(both '-' from regexp_replace(lower(trim(p_name)), '[^a-z0-9]+', '-', 'g'));
  if v_base = '' then
    v_base := 'resort';
  end if;
  v_slug := v_base;
  while exists (select 1 from public.properties where slug = v_slug) loop
    v_n := v_n + 1;
    v_slug := v_base || '-' || v_n;
  end loop;

  insert into public.properties (name, slug)
  values (trim(p_name), v_slug)
  returning id into v_id;

  insert into public.resort_members (property_id, user_id, role)
  values (v_id, v_owner, 'owner');

  return v_id;
end;
$$;

create function public.set_resort_subscription(
  p_property      uuid,
  p_tier          public.subscription_tier,
  p_status        public.subscription_status,
  p_trial_ends_on date default null,
  p_paid_through  date default null,
  p_notes         text default null
) returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  raise exception 'set_resort_subscription is not implemented yet' using errcode = '0A000';
end;
$$;

create function public.set_plan_price(
  p_tier              public.subscription_tier,
  p_monthly_price_inr numeric
) returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  raise exception 'set_plan_price is not implemented yet' using errcode = '0A000';
end;
$$;

revoke execute on function public.platform_resorts() from public, anon;
revoke execute on function public.platform_summary() from public, anon;
revoke execute on function public.my_resort_subscription(uuid) from public, anon;
revoke execute on function public.create_resort(text, text, public.subscription_tier, int) from public, anon;
revoke execute on function public.set_resort_subscription(uuid, public.subscription_tier, public.subscription_status, date, date, text) from public, anon;
revoke execute on function public.set_plan_price(public.subscription_tier, numeric) from public, anon;
grant execute on function public.platform_resorts() to authenticated;
grant execute on function public.platform_summary() to authenticated;
grant execute on function public.my_resort_subscription(uuid) to authenticated;
grant execute on function public.create_resort(text, text, public.subscription_tier, int) to authenticated;
grant execute on function public.set_resort_subscription(uuid, public.subscription_tier, public.subscription_status, date, date, text) to authenticated;
grant execute on function public.set_plan_price(public.subscription_tier, numeric) to authenticated;
```

- [ ] **Step 5: Add the new functions to the definer allow-list**

In `supabase/tests/37_tenancy_isolation_test.sql`, find the line:

```sql
        'platform_resorts','set_resort_status','create_resort',
```

and insert these lines directly after it (keep any lines B's 0047 or C's 0048 already added there):

```sql
        -- 0049: subscriptions. The platform functions check
        -- is_platform_admin(); my_resort_subscription asserts owner/admin
        -- at the resort it is given.
        'platform_summary','my_resort_subscription','set_resort_subscription',
        'set_plan_price',
```

- [ ] **Step 6: Update 38's checks of the old signatures**

In `supabase/tests/38_resort_members_test.sql`, replace:

```sql
select is(pg_get_function_result('public.platform_resorts()'::regprocedure),
  'TABLE(property_id uuid, name text, status text, owner_emails text[], created_at timestamp with time zone, '
  'bookings_30d integer, revenue_30d numeric, bookings_365d integer, revenue_365d numeric)',
  'platform_resorts returns summary columns only -- no guest data');
```

with:

```sql
-- 0049 adds the plan columns; still summaries only, no guest data.
select is((select array_agg(p.parameter_name::text order by p.ordinal_position)
             from information_schema.parameters p
             join information_schema.routines r
               on r.specific_schema = p.specific_schema and r.specific_name = p.specific_name
            where r.routine_schema = 'public' and r.routine_name = 'platform_resorts'
              and p.parameter_mode = 'OUT'),
  array['property_id','name','status','owner_emails','created_at',
        'bookings_30d','revenue_30d','bookings_365d','revenue_365d',
        'plan_tier','plan_name','plan_status','trial_ends_on','paid_through',
        'lapsed','monthly_price_inr','plan_notes'],
  'platform_resorts returns summary and plan columns only -- no guest data');
```

Then replace both occurrences (in the anon and the authenticated grant checks) of:

```sql
               'public.create_resort(text, text)']::regprocedure[]) f
```

with:

```sql
               'public.create_resort(text, text, public.subscription_tier, integer)']::regprocedure[]) f
```

Leave `select plan(54);` as it is: no assertion is added or removed.

- [ ] **Step 7: Run the database tests to verify they pass**

Run: `supabase db reset && supabase test db supabase/tests/41_subscriptions_test.sql supabase/tests/37_tenancy_isolation_test.sql supabase/tests/38_resort_members_test.sql`
Expected: PASS. 41 reports 21/21, 38 reports 54/54, and 37 passes with the same count as in the Step 1 baseline.

- [ ] **Step 8: Write the failing Dart model tests**

Create `test/data/subscription_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/data/models/subscription.dart';

ResortPlan _plan({
  SubscriptionTier tier = SubscriptionTier.pro,
  SubscriptionStatus status = SubscriptionStatus.active,
  DateTime? trialEndsOn,
  DateTime? paidThrough,
  bool lapsed = false,
}) =>
    ResortPlan(
      tier: tier,
      name: tier.label,
      status: status,
      trialEndsOn: trialEndsOn,
      paidThrough: paidThrough,
      lapsed: lapsed,
      monthlyPriceInr: 7999,
    );

void main() {
  group('tiers and statuses', () {
    test('every tier round-trips through its database label', () {
      for (final tier in SubscriptionTier.values) {
        expect(subscriptionTierFromDb(subscriptionTierToDb(tier)), tier);
      }
    });

    test('every status round-trips through its database label', () {
      for (final status in SubscriptionStatus.values) {
        expect(subscriptionStatusFromDb(subscriptionStatusToDb(status)), status);
      }
    });

    test('unknown labels are rejected, not defaulted', () {
      expect(() => subscriptionTierFromDb('free'), throwsArgumentError);
      expect(() => subscriptionStatusFromDb('lapsed'), throwsArgumentError);
    });

    test('labels', () {
      expect(SubscriptionTier.values.map((t) => t.label).toList(),
          ['Starter', 'Pro', 'Enterprise']);
      expect(SubscriptionStatus.values.map((s) => s.label).toList(),
          ['Trial', 'Active', 'Cancelled']);
    });
  });

  group('ResortPlan.fromRow', () {
    test('parses the plan columns of a platform_resorts row', () {
      final plan = ResortPlan.fromRow(const {
        'plan_tier': 'pro',
        'plan_name': 'Pro',
        'plan_status': 'active',
        'trial_ends_on': null,
        'paid_through': '2026-10-31',
        'lapsed': false,
        'monthly_price_inr': 7999,
        'plan_notes': 'Invoice 12',
      })!;

      expect(plan.tier, SubscriptionTier.pro);
      expect(plan.name, 'Pro');
      expect(plan.status, SubscriptionStatus.active);
      expect(plan.trialEndsOn, isNull);
      expect(plan.paidThrough, DateTime(2026, 10, 31));
      expect(plan.lapsed, isFalse);
      expect(plan.monthlyPriceInr, 7999);
      expect(plan.notes, 'Invoice 12');
    });

    test('parses a lapsed trial', () {
      final plan = ResortPlan.fromRow(const {
        'plan_tier': 'starter',
        'plan_name': 'Starter',
        'plan_status': 'trial',
        'trial_ends_on': '2026-09-24',
        'paid_through': null,
        'lapsed': true,
        'monthly_price_inr': 2999,
        'plan_notes': null,
      })!;

      expect(plan.status, SubscriptionStatus.trial);
      expect(plan.trialEndsOn, DateTime(2026, 9, 24));
      expect(plan.lapsed, isTrue);
    });

    test('a row with no plan_tier has no plan', () {
      expect(
        ResortPlan.fromRow(const {
          'plan_tier': null,
          'plan_name': null,
          'plan_status': null,
          'lapsed': false,
        }),
        isNull,
      );
    });

    test('a price sent as text still parses', () {
      final plan = ResortPlan.fromRow(const {
        'plan_tier': 'starter',
        'plan_name': 'Starter',
        'plan_status': 'active',
        'lapsed': false,
        'monthly_price_inr': '2999.00',
      })!;
      expect(plan.monthlyPriceInr, 2999);
    });
  });

  test('SubscriptionPlan.fromJson reads a subscription_plans row', () {
    final plan = SubscriptionPlan.fromJson(const {
      'tier': 'enterprise',
      'name': 'Enterprise',
      'monthly_price_inr': 19999,
      'sort_order': 3,
    });
    expect(plan.tier, SubscriptionTier.enterprise);
    expect(plan.name, 'Enterprise');
    expect(plan.monthlyPriceInr, 19999);
    expect(plan.sortOrder, 3);
  });

  test('PlatformTotals.fromJson reads a platform_summary row', () {
    final totals = PlatformTotals.fromJson(const {
      'subscribed_count': 21,
      'active_count': 19,
      'trial_count': 2,
      'mrr_inr': 123456.5,
    });
    expect(totals.subscribed, 21);
    expect(totals.active, 19);
    expect(totals.trials, 2);
    expect(totals.mrrInr, 123456.5);
  });

  group('planStatusLine', () {
    test('a live trial', () {
      expect(
        planStatusLine(_plan(
            status: SubscriptionStatus.trial,
            trialEndsOn: DateTime(2026, 10, 24))),
        'Trial until 24 Oct 2026',
      );
    });

    test('a lapsed trial', () {
      expect(
        planStatusLine(_plan(
            status: SubscriptionStatus.trial,
            trialEndsOn: DateTime(2026, 10, 24),
            lapsed: true)),
        'Lapsed: trial ended 24 Oct 2026',
      );
    });

    test('paid until a date, including the date itself', () {
      expect(planStatusLine(_plan(paidThrough: DateTime(2026, 10, 31))),
          'Paid until 31 Oct 2026');
    });

    test('a lapsed paid plan', () {
      expect(
        planStatusLine(
            _plan(paidThrough: DateTime(2026, 9, 30), lapsed: true)),
        'Lapsed: paid until 30 Sep 2026',
      );
    });

    test('paid with no end date', () {
      expect(planStatusLine(_plan()), 'Paid, no end date');
    });

    test('cancelled, whatever the dates', () {
      expect(
        planStatusLine(_plan(
            status: SubscriptionStatus.cancelled,
            paidThrough: DateTime(2026, 9, 30))),
        'Cancelled',
      );
    });
  });

  test('dateToDb sends only the calendar day', () {
    expect(dateToDb(DateTime(2026, 10, 5, 23, 59)), '2026-10-05');
    expect(dateToDb(DateTime.utc(2026, 1, 9)), '2026-01-09');
  });
}
```

- [ ] **Step 9: Write the failing repository and provider tests**

Create `test/data/platform_providers_test.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/data/models/subscription.dart';
import 'package:pasala/data/repositories/platform_repository.dart';
import 'package:pasala/data/repositories/subscription_repository.dart';

import '../support/fake_platform_source.dart';
import '../support/fake_resort_plan_source.dart';

Map<String, dynamic> _row(Map<String, dynamic> plan) => {
      'property_id': 'p1',
      'name': 'Resort A',
      'status': 'active',
      'owner_emails': ['ownera@x.com'],
      'created_at': '2026-01-01T00:00:00+00:00',
      'bookings_30d': 1,
      'revenue_30d': 100,
      'bookings_365d': 2,
      'revenue_365d': 200,
      ...plan,
    };

void main() {
  group('ResortSummary.fromJson', () {
    test('reads the plan columns', () {
      final summary = ResortSummary.fromJson(_row({
        'plan_tier': 'enterprise',
        'plan_name': 'Enterprise',
        'plan_status': 'active',
        'trial_ends_on': null,
        'paid_through': null,
        'lapsed': false,
        'monthly_price_inr': 19999,
        'plan_notes': null,
      }));

      expect(summary.plan!.tier, SubscriptionTier.enterprise);
      expect(summary.plan!.paidThrough, isNull);
      expect(summary.bookings30d, 1);
    });

    test('a resort with no subscription row has no plan', () {
      final summary = ResortSummary.fromJson(_row({
        'plan_tier': null,
        'plan_name': null,
        'plan_status': null,
        'trial_ends_on': null,
        'paid_through': null,
        'lapsed': false,
        'monthly_price_inr': null,
        'plan_notes': null,
      }));

      expect(summary.plan, isNull);
    });
  });

  test('platformTotalsProvider reads the totals through the seam', () async {
    final source = FakePlatformSource()
      ..totalsValue = const PlatformTotals(
          subscribed: 3, active: 2, trials: 1, mrrInr: 7999);
    final container = ProviderContainer(
        overrides: [platformSourceProvider.overrideWithValue(source)]);
    addTearDown(container.dispose);

    final totals = await container.read(platformTotalsProvider.future);

    expect(totals.subscribed, 3);
    expect(totals.mrrInr, 7999);
    expect(source.totalsCalls, 1);
  });

  test('subscriptionPlansProvider lists the plans through the seam', () async {
    final source = FakePlatformSource();
    final container = ProviderContainer(
        overrides: [platformSourceProvider.overrideWithValue(source)]);
    addTearDown(container.dispose);

    final plans = await container.read(subscriptionPlansProvider.future);

    expect(plans.map((p) => p.tier).toList(), SubscriptionTier.values);
    expect(source.plansCalls, 1);
  });

  test('resortPlanProvider asks for the plan of the resort it is keyed by',
      () async {
    final source = FakeResortPlanSource()
      ..plan = resortPlan(tier: SubscriptionTier.pro);
    final container = ProviderContainer(
        overrides: [resortPlanSourceProvider.overrideWithValue(source)]);
    addTearDown(container.dispose);
    final sub = container.listen(resortPlanProvider('p1'), (_, _) {});
    addTearDown(sub.close);

    final plan = await container.read(resortPlanProvider('p1').future);

    expect(plan!.tier, SubscriptionTier.pro);
    expect(source.calls, ['p1']);
  });

  test('resortPlanProvider gives null for a resort with no plan', () async {
    final source = FakeResortPlanSource();
    final container = ProviderContainer(
        overrides: [resortPlanSourceProvider.overrideWithValue(source)]);
    addTearDown(container.dispose);
    final sub = container.listen(resortPlanProvider('p2'), (_, _) {});
    addTearDown(sub.close);

    expect(await container.read(resortPlanProvider('p2').future), isNull);
    expect(source.calls, ['p2']);
  });
}
```

- [ ] **Step 10: Run them to verify they fail**

Run: `flutter test test/data/subscription_test.dart test/data/platform_providers_test.dart`
Expected: FAIL to compile with "Target of URI doesn't exist: 'package:pasala/data/models/subscription.dart'".

- [ ] **Step 11: Write the model**

Create `lib/data/models/subscription.dart`:

```dart
import '../../core/format.dart';

/// A resort's plan tier (`public.subscription_tier`,
/// 0049_subscriptions.sql). A label with a monthly price only: it gates
/// no feature yet (spec decision 2).
enum SubscriptionTier { starter, pro, enterprise }

/// Unknown text is rejected rather than defaulted -- a silent fallback
/// would hide a server/app mismatch.
SubscriptionTier subscriptionTierFromDb(String raw) => switch (raw) {
      'starter' => SubscriptionTier.starter,
      'pro' => SubscriptionTier.pro,
      'enterprise' => SubscriptionTier.enterprise,
      _ => throw ArgumentError('Unknown subscription tier: $raw'),
    };

/// Inverse of [subscriptionTierFromDb] -- the Postgres enum label.
String subscriptionTierToDb(SubscriptionTier tier) => switch (tier) {
      SubscriptionTier.starter => 'starter',
      SubscriptionTier.pro => 'pro',
      SubscriptionTier.enterprise => 'enterprise',
    };

extension SubscriptionTierLabel on SubscriptionTier {
  String get label => switch (this) {
        SubscriptionTier.starter => 'Starter',
        SubscriptionTier.pro => 'Pro',
        SubscriptionTier.enterprise => 'Enterprise',
      };
}

/// What the platform admin set (`public.subscription_status`). "Lapsed" is
/// never stored: the server works it out on every read
/// ([ResortPlan.lapsed]).
enum SubscriptionStatus { trial, active, cancelled }

SubscriptionStatus subscriptionStatusFromDb(String raw) => switch (raw) {
      'trial' => SubscriptionStatus.trial,
      'active' => SubscriptionStatus.active,
      'cancelled' => SubscriptionStatus.cancelled,
      _ => throw ArgumentError('Unknown subscription status: $raw'),
    };

String subscriptionStatusToDb(SubscriptionStatus status) => switch (status) {
      SubscriptionStatus.trial => 'trial',
      SubscriptionStatus.active => 'active',
      SubscriptionStatus.cancelled => 'cancelled',
    };

extension SubscriptionStatusLabel on SubscriptionStatus {
  String get label => switch (this) {
        SubscriptionStatus.trial => 'Trial',
        SubscriptionStatus.active => 'Active',
        SubscriptionStatus.cancelled => 'Cancelled',
      };
}

/// `yyyy-MM-dd` for a Postgres `date` parameter: only the calendar day of
/// [d] is sent, whatever its time or zone.
String dateToDb(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// A Postgres `date` as a local, time-less [DateTime].
DateTime? _dateFromDb(Object? raw) {
  if (raw == null) return null;
  final parsed = DateTime.parse(raw as String);
  return DateTime(parsed.year, parsed.month, parsed.day);
}

/// PostgREST sends `numeric` as a JSON number; accept text too, so a
/// change of serialisation never turns a price into a crash.
num? _numFromDb(Object? raw) => switch (raw) {
      null => null,
      num n => n,
      String s => num.parse(s),
      _ => throw ArgumentError('Not a number: $raw'),
    };

/// One row of `subscription_plans`.
class SubscriptionPlan {
  const SubscriptionPlan({
    required this.tier,
    required this.name,
    required this.monthlyPriceInr,
    required this.sortOrder,
  });

  factory SubscriptionPlan.fromJson(Map<String, dynamic> json) =>
      SubscriptionPlan(
        tier: subscriptionTierFromDb(json['tier'] as String),
        name: json['name'] as String,
        monthlyPriceInr: _numFromDb(json['monthly_price_inr']) ?? 0,
        sortOrder: (json['sort_order'] as num).toInt(),
      );

  final SubscriptionTier tier;
  final String name;
  final num monthlyPriceInr;
  final int sortOrder;
}

/// The row `platform_summary()` returns: the console's three cards.
class PlatformTotals {
  const PlatformTotals({
    required this.subscribed,
    required this.active,
    required this.trials,
    required this.mrrInr,
  });

  factory PlatformTotals.fromJson(Map<String, dynamic> json) => PlatformTotals(
        subscribed: (json['subscribed_count'] as num).toInt(),
        active: (json['active_count'] as num).toInt(),
        trials: (json['trial_count'] as num).toInt(),
        mrrInr: _numFromDb(json['mrr_inr']) ?? 0,
      );

  static const zero =
      PlatformTotals(subscribed: 0, active: 0, trials: 0, mrrInr: 0);

  /// Not archived, and not cancelled.
  final int subscribed;

  /// Subscribed, and paid up or in a trial, with no lapse.
  final int active;

  /// Live (not lapsed) trials, included in [active].
  final int trials;

  /// The monthly price of every paid-up subscription, trials excluded.
  final num mrrInr;
}

/// A resort's subscription: the plan columns of `platform_resorts()` and
/// `my_resort_subscription()`, which share their names.
class ResortPlan {
  const ResortPlan({
    required this.tier,
    required this.name,
    required this.status,
    this.trialEndsOn,
    this.paidThrough,
    this.lapsed = false,
    required this.monthlyPriceInr,
    this.notes,
  });

  /// Null when the row carries no plan (`plan_tier` is null): the resort
  /// has no subscription row, shown as "No plan".
  static ResortPlan? fromRow(Map<String, dynamic> json) {
    final rawTier = json['plan_tier'] as String?;
    if (rawTier == null) return null;
    final tier = subscriptionTierFromDb(rawTier);
    return ResortPlan(
      tier: tier,
      name: json['plan_name'] as String? ?? tier.label,
      status: subscriptionStatusFromDb(json['plan_status'] as String),
      trialEndsOn: _dateFromDb(json['trial_ends_on']),
      paidThrough: _dateFromDb(json['paid_through']),
      lapsed: json['lapsed'] as bool? ?? false,
      monthlyPriceInr: _numFromDb(json['monthly_price_inr']) ?? 0,
      notes: json['plan_notes'] as String?,
    );
  }

  final SubscriptionTier tier;
  final String name;
  final SubscriptionStatus status;

  /// Set for a trial: the last day it runs.
  final DateTime? trialEndsOn;

  /// The last day paid for; null means no end date.
  final DateTime? paidThrough;

  /// Worked out by the server (Asia/Kolkata "today"): a trial or a paid
  /// plan whose last day has passed.
  final bool lapsed;
  final num monthlyPriceInr;
  final String? notes;
}

/// One line describing [plan]'s state, shared by the platform console and
/// the owner's Settings. "Lapsed" is always spelled out, so the state never
/// depends on colour alone.
String planStatusLine(ResortPlan plan) {
  switch (plan.status) {
    case SubscriptionStatus.cancelled:
      return 'Cancelled';
    case SubscriptionStatus.trial:
      final end = plan.trialEndsOn;
      if (end == null) return 'Trial';
      return plan.lapsed
          ? 'Lapsed: trial ended ${formatDate(end)}'
          : 'Trial until ${formatDate(end)}';
    case SubscriptionStatus.active:
      final paid = plan.paidThrough;
      if (paid == null) return 'Paid, no end date';
      return plan.lapsed
          ? 'Lapsed: paid until ${formatDate(paid)}'
          : 'Paid until ${formatDate(paid)}';
  }
}
```

- [ ] **Step 12: Widen the platform repository**

Replace the whole of `lib/data/repositories/platform_repository.dart` with:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors.dart';
import '../../core/supabase_client.dart';
import '../models/subscription.dart';

/// One row of `platform_resorts()` -- a resort summary for the platform
/// console. No guest data: owner emails, booking counts/revenue for the
/// last 30 and 365 days, and the resort's subscription (see the tenancy
/// and subscriptions design specs).
class ResortSummary {
  const ResortSummary({
    required this.propertyId,
    required this.name,
    required this.status,
    required this.ownerEmails,
    required this.createdAt,
    required this.bookings30d,
    required this.revenue30d,
    required this.bookings365d,
    required this.revenue365d,
    this.plan,
  });

  final String propertyId;
  final String name;

  /// `active`, `suspended` or `archived` -- `properties.status`, the only
  /// thing that locks a resort. The subscription never does.
  final String status;
  final List<String> ownerEmails;
  final DateTime createdAt;
  final int bookings30d;
  final num revenue30d;
  final int bookings365d;
  final num revenue365d;

  /// The resort's subscription, or null when it has none ("No plan").
  final ResortPlan? plan;

  factory ResortSummary.fromJson(Map<String, dynamic> json) => ResortSummary(
        propertyId: json['property_id'] as String,
        name: json['name'] as String,
        status: json['status'] as String,
        ownerEmails:
            (json['owner_emails'] as List<dynamic>? ?? []).cast<String>(),
        createdAt: DateTime.parse(json['created_at'] as String).toUtc(),
        bookings30d: (json['bookings_30d'] as num?)?.toInt() ?? 0,
        revenue30d: (json['revenue_30d'] as num?) ?? 0,
        bookings365d: (json['bookings_365d'] as num?)?.toInt() ?? 0,
        revenue365d: (json['revenue_365d'] as num?) ?? 0,
        plan: ResortPlan.fromRow(json),
      );

  ResortSummary copyWith({String? status, ResortPlan? plan}) => ResortSummary(
        propertyId: propertyId,
        name: name,
        status: status ?? this.status,
        ownerEmails: ownerEmails,
        createdAt: createdAt,
        bookings30d: bookings30d,
        revenue30d: revenue30d,
        bookings365d: bookings365d,
        revenue365d: revenue365d,
        plan: plan ?? this.plan,
      );
}

/// The slice of [PlatformRepository] the platform console needs. Extracted
/// as its own interface, mirroring [IcalSource]/`OutboxSource`, so tests
/// can override it with `FakePlatformSource`
/// (test/support/fake_platform_source.dart) instead of a real
/// [SupabaseClient].
abstract class PlatformSource {
  Future<List<ResortSummary>> resorts();

  /// The console's count cards: `platform_summary()`.
  Future<PlatformTotals> totals();

  /// The plans and their monthly prices, cheapest first.
  Future<List<SubscriptionPlan>> plans();

  Future<void> setStatus(String propertyId, String status);

  /// Creates the resort and its subscription: a trial of [trialDays] days
  /// on [tier], or active with no end date when [trialDays] is 0.
  Future<String> createResort(
    String name,
    String ownerEmail, {
    SubscriptionTier tier = SubscriptionTier.starter,
    int trialDays = 30,
  });

  /// Sets (or first creates) the resort's subscription. The server keeps
  /// only the date [status] needs: [trialEndsOn] for a trial,
  /// [paidThrough] otherwise.
  Future<void> setSubscription(
    String propertyId, {
    required SubscriptionTier tier,
    required SubscriptionStatus status,
    DateTime? trialEndsOn,
    DateTime? paidThrough,
    String? notes,
  });

  Future<void> setPlanPrice(SubscriptionTier tier, num monthlyPriceInr);
}

/// Drives the platform-admin-only functions of 0045_resort_functions.sql
/// and 0049_subscriptions.sql. The platform admin gets no row access to
/// any resort-owned table, so every call here goes through a `security
/// definer` function; the one direct read is `subscription_plans`, which
/// every signed-in user may read.
class PlatformRepository implements PlatformSource {
  PlatformRepository(this._db);
  final SupabaseClient _db;

  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } catch (e) {
      throw mapPostgrestError(e);
    }
  }

  @override
  Future<List<ResortSummary>> resorts() => _guard(() async {
        final rows = await _db.rpc('platform_resorts') as List<dynamic>;
        return rows
            .map((e) => ResortSummary.fromJson(e as Map<String, dynamic>))
            .toList();
      });

  @override
  Future<PlatformTotals> totals() => _guard(() async {
        final rows = await _db.rpc('platform_summary') as List<dynamic>;
        return rows.isEmpty
            ? PlatformTotals.zero
            : PlatformTotals.fromJson(rows.first as Map<String, dynamic>);
      });

  @override
  Future<List<SubscriptionPlan>> plans() => _guard(() async {
        final rows = await _db
            .from('subscription_plans')
            .select('tier, name, monthly_price_inr, sort_order')
            .order('sort_order');
        return rows.map(SubscriptionPlan.fromJson).toList();
      });

  @override
  Future<void> setStatus(String propertyId, String status) =>
      _guard(() async {
        await _db.rpc('set_resort_status', params: {
          'p_property': propertyId,
          'p_status': status,
        });
      });

  @override
  Future<String> createResort(
    String name,
    String ownerEmail, {
    SubscriptionTier tier = SubscriptionTier.starter,
    int trialDays = 30,
  }) =>
      _guard(() async {
        final id = await _db.rpc('create_resort', params: {
          'p_name': name,
          'p_owner_email': ownerEmail,
          'p_tier': subscriptionTierToDb(tier),
          'p_trial_days': trialDays,
        });
        return id as String;
      });

  @override
  Future<void> setSubscription(
    String propertyId, {
    required SubscriptionTier tier,
    required SubscriptionStatus status,
    DateTime? trialEndsOn,
    DateTime? paidThrough,
    String? notes,
  }) =>
      _guard(() async {
        await _db.rpc('set_resort_subscription', params: {
          'p_property': propertyId,
          'p_tier': subscriptionTierToDb(tier),
          'p_status': subscriptionStatusToDb(status),
          'p_trial_ends_on': trialEndsOn == null ? null : dateToDb(trialEndsOn),
          'p_paid_through': paidThrough == null ? null : dateToDb(paidThrough),
          'p_notes': notes,
        });
      });

  @override
  Future<void> setPlanPrice(SubscriptionTier tier, num monthlyPriceInr) =>
      _guard(() async {
        await _db.rpc('set_plan_price', params: {
          'p_tier': subscriptionTierToDb(tier),
          'p_monthly_price_inr': monthlyPriceInr,
        });
      });
}

final platformRepositoryProvider = Provider<PlatformRepository>(
  (ref) => PlatformRepository(ref.watch(supabaseProvider)),
);

/// [PlatformSource] seam around [platformRepositoryProvider], mirroring
/// `icalSourceProvider`: the console only ever calls this, so tests can
/// override just this provider with a fake.
final platformSourceProvider = Provider<PlatformSource>(
  (ref) => ref.watch(platformRepositoryProvider),
);

final platformResortsProvider = FutureProvider<List<ResortSummary>>(
  (ref) => ref.watch(platformSourceProvider).resorts(),
);

/// Platform-wide: the cards do not follow the console's search or filter.
final platformTotalsProvider = FutureProvider<PlatformTotals>(
  (ref) => ref.watch(platformSourceProvider).totals(),
);

final subscriptionPlansProvider = FutureProvider<List<SubscriptionPlan>>(
  (ref) => ref.watch(platformSourceProvider).plans(),
);
```

- [ ] **Step 13: Write the owner's plan seam**

Create `lib/data/repositories/subscription_repository.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors.dart';
import '../../core/supabase_client.dart';
import '../models/subscription.dart';

/// A resort's own plan, for its owners and admins. Tests override
/// [resortPlanSourceProvider] with `FakeResortPlanSource`
/// (test/support/fake_resort_plan_source.dart).
abstract class ResortPlanSource {
  /// Null when the resort has no subscription row. Anyone who is not an
  /// owner or admin of [propertyId] gets P0020 ([NotAMember]).
  Future<ResortPlan?> resortPlan(String propertyId);
}

/// Reads `my_resort_subscription(p_property)` (0049_subscriptions.sql).
class SubscriptionRepository implements ResortPlanSource {
  SubscriptionRepository(this._db);
  final SupabaseClient _db;

  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } catch (e) {
      throw mapPostgrestError(e);
    }
  }

  @override
  Future<ResortPlan?> resortPlan(String propertyId) => _guard(() async {
        final rows = await _db.rpc('my_resort_subscription', params: {
          'p_property': propertyId,
        }) as List<dynamic>;
        return rows.isEmpty
            ? null
            : ResortPlan.fromRow(rows.first as Map<String, dynamic>);
      });
}

final subscriptionRepositoryProvider = Provider<SubscriptionRepository>(
  (ref) => SubscriptionRepository(ref.watch(supabaseProvider)),
);

/// The [ResortPlanSource] seam every screen calls through.
final resortPlanSourceProvider = Provider<ResortPlanSource>(
  (ref) => ref.watch(subscriptionRepositoryProvider),
);

/// One resort's plan, keyed by property id so switching resort never shows
/// another resort's plan. `autoDispose`: Settings refetches it every time
/// it opens, so a change the platform admin made shows up.
final resortPlanProvider =
    FutureProvider.autoDispose.family<ResortPlan?, String>(
  (ref, propertyId) =>
      ref.watch(resortPlanSourceProvider).resortPlan(propertyId),
);
```

- [ ] **Step 14: Write the test fakes**

Create `test/support/fake_platform_source.dart`:

```dart
import 'package:pasala/data/models/subscription.dart';
import 'package:pasala/data/repositories/platform_repository.dart';

/// The arguments of one [PlatformSource.setSubscription] call.
typedef SubscriptionCall = ({
  String propertyId,
  SubscriptionTier tier,
  SubscriptionStatus status,
  DateTime? trialEndsOn,
  DateTime? paidThrough,
  String? notes,
});

/// The three plans at the spec's placeholder prices.
const defaultPlans = [
  SubscriptionPlan(
      tier: SubscriptionTier.starter,
      name: 'Starter',
      monthlyPriceInr: 2999,
      sortOrder: 1),
  SubscriptionPlan(
      tier: SubscriptionTier.pro,
      name: 'Pro',
      monthlyPriceInr: 7999,
      sortOrder: 2),
  SubscriptionPlan(
      tier: SubscriptionTier.enterprise,
      name: 'Enterprise',
      monthlyPriceInr: 19999,
      sortOrder: 3),
];

/// A plan for tests; the price defaults to [defaultPlans]' price for [tier].
ResortPlan resortPlan({
  SubscriptionTier tier = SubscriptionTier.pro,
  SubscriptionStatus status = SubscriptionStatus.active,
  DateTime? trialEndsOn,
  DateTime? paidThrough,
  bool lapsed = false,
  num? monthlyPriceInr,
  String? notes,
}) =>
    ResortPlan(
      tier: tier,
      name: tier.label,
      status: status,
      trialEndsOn: trialEndsOn,
      paidThrough: paidThrough,
      lapsed: lapsed,
      monthlyPriceInr: monthlyPriceInr ??
          defaultPlans.firstWhere((p) => p.tier == tier).monthlyPriceInr,
      notes: notes,
    );

/// A resort summary for tests.
ResortSummary resortSummary({
  String propertyId = 'p1',
  String name = 'Resort A',
  String status = 'active',
  List<String> ownerEmails = const ['ownera@x.com'],
  ResortPlan? plan,
  int bookings30d = 0,
  num revenue30d = 0,
}) =>
    ResortSummary(
      propertyId: propertyId,
      name: name,
      status: status,
      ownerEmails: ownerEmails,
      createdAt: DateTime.utc(2024, 1, 1),
      bookings30d: bookings30d,
      revenue30d: revenue30d,
      bookings365d: bookings30d,
      revenue365d: revenue30d,
      plan: plan,
    );

/// In-memory [PlatformSource]. Set [store], [totalsValue] and [planList]
/// for what the server would return, an `...Error` to make that call
/// throw, and read the call logs to assert what a screen asked for. Writes
/// also update [store]/[planList], so a refetch shows them.
class FakePlatformSource implements PlatformSource {
  List<ResortSummary> store = [];
  PlatformTotals totalsValue = PlatformTotals.zero;
  List<SubscriptionPlan> planList = defaultPlans;

  Object? resortsError;
  Object? totalsError;
  Object? plansError;
  Object? setStatusError;
  Object? createError;
  Object? subscriptionError;
  Object? priceError;

  int resortsCalls = 0;
  int totalsCalls = 0;
  int plansCalls = 0;
  final List<(String, String)> statusCalls = [];
  final List<(String, String, SubscriptionTier, int)> createCalls = [];
  final List<SubscriptionCall> subscriptionCalls = [];
  final List<(SubscriptionTier, num)> priceCalls = [];
  int _idCounter = 0;

  @override
  Future<List<ResortSummary>> resorts() async {
    resortsCalls++;
    if (resortsError != null) throw resortsError!;
    return List.of(store);
  }

  @override
  Future<PlatformTotals> totals() async {
    totalsCalls++;
    if (totalsError != null) throw totalsError!;
    return totalsValue;
  }

  @override
  Future<List<SubscriptionPlan>> plans() async {
    plansCalls++;
    if (plansError != null) throw plansError!;
    return List.of(planList);
  }

  @override
  Future<void> setStatus(String propertyId, String status) async {
    statusCalls.add((propertyId, status));
    if (setStatusError != null) throw setStatusError!;
    store = [
      for (final r in store)
        r.propertyId == propertyId ? r.copyWith(status: status) : r,
    ];
  }

  @override
  Future<String> createResort(
    String name,
    String ownerEmail, {
    SubscriptionTier tier = SubscriptionTier.starter,
    int trialDays = 30,
  }) async {
    createCalls.add((name, ownerEmail, tier, trialDays));
    if (createError != null) throw createError!;
    final id = 'resort-${_idCounter++}';
    store = [
      ...store,
      resortSummary(
        propertyId: id,
        name: name,
        ownerEmails: [ownerEmail],
        plan: resortPlan(
          tier: tier,
          status: trialDays > 0
              ? SubscriptionStatus.trial
              : SubscriptionStatus.active,
          trialEndsOn:
              trialDays > 0 ? DateTime(2026, 9, 25 + trialDays) : null,
        ),
      ),
    ];
    return id;
  }

  @override
  Future<void> setSubscription(
    String propertyId, {
    required SubscriptionTier tier,
    required SubscriptionStatus status,
    DateTime? trialEndsOn,
    DateTime? paidThrough,
    String? notes,
  }) async {
    subscriptionCalls.add((
      propertyId: propertyId,
      tier: tier,
      status: status,
      trialEndsOn: trialEndsOn,
      paidThrough: paidThrough,
      notes: notes,
    ));
    if (subscriptionError != null) throw subscriptionError!;
    store = [
      for (final r in store)
        r.propertyId == propertyId
            ? r.copyWith(
                plan: resortPlan(
                  tier: tier,
                  status: status,
                  trialEndsOn: trialEndsOn,
                  paidThrough: paidThrough,
                  notes: notes,
                ),
              )
            : r,
    ];
  }

  @override
  Future<void> setPlanPrice(SubscriptionTier tier, num monthlyPriceInr) async {
    priceCalls.add((tier, monthlyPriceInr));
    if (priceError != null) throw priceError!;
    planList = [
      for (final p in planList)
        p.tier == tier
            ? SubscriptionPlan(
                tier: p.tier,
                name: p.name,
                monthlyPriceInr: monthlyPriceInr,
                sortOrder: p.sortOrder,
              )
            : p,
    ];
  }
}
```

Create `test/support/fake_resort_plan_source.dart`:

```dart
import 'package:pasala/data/models/subscription.dart';
import 'package:pasala/data/repositories/subscription_repository.dart';

/// In-memory [ResortPlanSource]: returns [plan] (null = "No plan"), or
/// throws [error]; [calls] logs the property ids asked for.
class FakeResortPlanSource implements ResortPlanSource {
  ResortPlan? plan;
  Object? error;
  final List<String> calls = [];

  @override
  Future<ResortPlan?> resortPlan(String propertyId) async {
    calls.add(propertyId);
    if (error != null) throw error!;
    return plan;
  }
}
```

- [ ] **Step 15: Point the existing console test at the shared fake**

`FakePlatformRepository` in `test/features/platform/platform_screen_test.dart` no longer implements the wider `PlatformSource`. In that file, replace everything from the first line through the closing `}` of `class FakePlatformRepository` (lines 1–60) with:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/format.dart';
import 'package:pasala/core/theme/app_theme.dart';
import 'package:pasala/core/theme/theme_toggle_button.dart';
import 'package:pasala/data/models/subscription.dart';
import 'package:pasala/data/repositories/platform_repository.dart';
import 'package:pasala/features/platform/platform_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_platform_source.dart';
```

Then replace every `FakePlatformRepository` in the file with `FakePlatformSource`. Finally, replace:

```dart
    expect(repo.createCalls, [('Resort E', 'owner@x.com')]);
```

with:

```dart
    expect(repo.createCalls,
        [('Resort E', 'owner@x.com', SubscriptionTier.starter, 30)]);
```

- [ ] **Step 16: Run the Dart tests to verify they pass**

Run: `flutter test test/data/subscription_test.dart test/data/platform_providers_test.dart test/features/platform/platform_screen_test.dart && flutter analyze`
Expected: all tests PASS. The analyzer shows no issues beyond the Step 1 baseline.

- [ ] **Step 17: Commit**

```bash
git add supabase/migrations/0049_subscriptions.sql supabase/tests/41_subscriptions_test.sql \
  supabase/tests/37_tenancy_isolation_test.sql supabase/tests/38_resort_members_test.sql \
  lib/data/models/subscription.dart lib/data/repositories/platform_repository.dart \
  lib/data/repositories/subscription_repository.dart test/support/fake_platform_source.dart \
  test/support/fake_resort_plan_source.dart test/data/subscription_test.dart \
  test/data/platform_providers_test.dart test/features/platform/platform_screen_test.dart
git commit -m "feat(subscriptions): fix the subscription contract (schema, function signatures, Dart API)"
```

---

## Phase 1: Database track (Tasks 2 → 3, sequential)

### Task 2: Reading plans, counts and MRR

**Track:** DB. **Depends on:** Task 1.

**Files:**
- Modify: `supabase/migrations/0049_subscriptions.sql` (add `subscription_lapsed`; replace the `platform_resorts` body and two stubs)
- Modify: `supabase/seed.sql` (append)
- Test: `supabase/tests/41_subscriptions_test.sql` (append a section)

**Interfaces:**
- Consumes: the Task 1 signatures and fixtures, `public.assert_resort_role(uuid, boolean, variadic resort_role[])`.
- Produces:
  - `public.subscription_lapsed(p_status public.subscription_status, p_trial_ends_on date, p_paid_through date) returns boolean` (plain `stable` SQL, not a definer). Task 3's checks rely on it through `platform_resorts` and `platform_summary`.
  - Working `platform_resorts()`, `platform_summary()` and `my_resort_subscription(uuid)`.
- State left for Task 3: the fixture rows are unchanged (this section only reads), and the file ends with `reset role` and empty claims.

- [ ] **Step 1: Write the failing tests**

In `supabase/tests/41_subscriptions_test.sql`, change `select plan(21);` to `select plan(38);`. Then insert this section immediately before the final `select * from finish();`:

```sql
-- === Task 2: reading plans, counts and MRR =================================

select is(array[
    public.subscription_lapsed('trial', pg_temp.today(), null),
    public.subscription_lapsed('trial', pg_temp.today() - 1, null),
    public.subscription_lapsed('active', null, pg_temp.today()),
    public.subscription_lapsed('active', null, pg_temp.today() - 1),
    public.subscription_lapsed('active', null, null),
    public.subscription_lapsed('cancelled', pg_temp.today() - 100, pg_temp.today() - 100)],
  array[false, true, false, true, false, false],
  'a plan is good through its end date, never lapses without one, and cancelled never lapses');

set local role authenticated;
set local request.jwt.claims to '{"sub":"f0000000-0000-0000-0000-000000000001","role":"authenticated"}';

select is((select plan_tier::text || '|' || plan_name || '|' || plan_status::text || '|'
                  || lapsed::text || '|' || monthly_price_inr::int
             from public.platform_resorts()
            where property_id = 'f1000000-0000-4000-8000-000000000001'),
  'pro|Pro|active|false|7999',
  'a resort paid until today shows its plan and price, and is not lapsed');
select is((select array_agg(name || ':' || lapsed::text order by name collate "C")
             from public.platform_resorts()
            where name like 'Sub %'),
  array['Sub Archived:false','Sub Cancelled:false','Sub None:false','Sub Open:false',
        'Sub Paid:false','Sub Paid Lapsed:true','Sub Suspended:false','Sub Trial:false',
        'Sub Trial Lapsed:true'],
  'platform_resorts flags exactly the lapsed trial and the lapsed paid plan');
select is((select plan_status::text || '|' || (trial_ends_on - pg_temp.today())::text
             from public.platform_resorts()
            where property_id = 'f1000000-0000-4000-8000-000000000003'),
  'trial|5', 'a trial shows its end date');
select ok((select plan_tier is null and plan_name is null and plan_status is null
                  and monthly_price_inr is null and not lapsed
             from public.platform_resorts()
            where property_id = 'f1000000-0000-4000-8000-000000000009'),
  'a resort with no subscription row shows no plan');
select is((select array[subscribed_count, active_count, trial_count]
             from public.platform_summary()),
  array[6, 4, 1],
  'subscribed leaves out cancelled, archived and plan-less resorts; active also leaves out the two lapsed; one live trial');
select is((select mrr_inr from public.platform_summary()), 30997::numeric,
  'MRR is Pro 7999 + Enterprise 19999 + the suspended resort''s Starter 2999: no trials, lapsed, cancelled or archived');

-- The owner of P1.
set local request.jwt.claims to '{"sub":"f0000000-0000-0000-0000-000000000002","role":"authenticated"}';
select throws_ok($$select * from public.platform_summary()$$,
  'P0008', null, 'an owner cannot read the platform totals');
select is((select plan_tier::text || '|' || plan_status::text || '|' || lapsed::text || '|' || paid_through::text
             from public.my_resort_subscription('f1000000-0000-4000-8000-000000000001')),
  'pro|active|false|' || pg_temp.today()::text, 'an owner reads their own plan');
select throws_ok($$select * from public.my_resort_subscription('f1000000-0000-4000-8000-000000000002')$$,
  'P0020', null, 'an owner cannot read another resort''s plan');

-- P1's admin, staff member and accountant.
set local request.jwt.claims to '{"sub":"f0000000-0000-0000-0000-000000000003","role":"authenticated"}';
select is((select count(*)::int
             from public.my_resort_subscription('f1000000-0000-4000-8000-000000000001')),
  1, 'an admin reads their resort''s plan');
set local request.jwt.claims to '{"sub":"f0000000-0000-0000-0000-000000000004","role":"authenticated"}';
select throws_ok($$select * from public.my_resort_subscription('f1000000-0000-4000-8000-000000000001')$$,
  'P0020', null, 'staff cannot read the plan');
select throws_ok($$select * from public.platform_summary()$$,
  'P0008', null, 'staff cannot read the platform totals');
set local request.jwt.claims to '{"sub":"f0000000-0000-0000-0000-000000000005","role":"authenticated"}';
select throws_ok($$select * from public.my_resort_subscription('f1000000-0000-4000-8000-000000000001')$$,
  'P0020', null, 'an accountant cannot read the plan');

-- The owner of P2, P8 (suspended) and P9 (no plan).
set local request.jwt.claims to '{"sub":"f0000000-0000-0000-0000-000000000006","role":"authenticated"}';
select is((select plan_status::text
             from public.my_resort_subscription('f1000000-0000-4000-8000-000000000008')),
  'active', 'the owner of a suspended resort still reads their plan');
select is((select count(*)::int
             from public.my_resort_subscription('f1000000-0000-4000-8000-000000000009')),
  0, 'a resort with no plan returns no row');

-- The platform admin is nobody's member.
set local request.jwt.claims to '{"sub":"f0000000-0000-0000-0000-000000000001","role":"authenticated"}';
select throws_ok($$select * from public.my_resort_subscription('f1000000-0000-4000-8000-000000000001')$$,
  'P0020', null, 'the platform admin reads plans through platform_resorts, not as a member');
reset role;
set local request.jwt.claims to '';
```

- [ ] **Step 2: Run it to verify it fails**

Run: `supabase test db supabase/tests/41_subscriptions_test.sql`
Expected: FAIL with `function public.subscription_lapsed(unknown, date, unknown) does not exist`.

- [ ] **Step 3: Add `subscription_lapsed`**

In `supabase/migrations/0049_subscriptions.sql`, insert this block directly after the backfill statement (the one ending `on conflict (property_id) do nothing;`):

```sql

-- Whether a subscription has run out, worked out on every read and never
-- stored. A plan is good through its end date (Asia/Kolkata, the same
-- "today" as dashboard_summary) and lapses the day after; no end date
-- never lapses; cancelled -- and a missing row, which arrives as all
-- nulls -- is never lapsed. Not a definer: it reads no table.
create function public.subscription_lapsed(
  p_status        public.subscription_status,
  p_trial_ends_on date,
  p_paid_through  date
) returns boolean
language sql
stable
set search_path = public, pg_temp
as $$
  select case p_status
    when 'trial'
      then coalesce(p_trial_ends_on < (now() at time zone 'Asia/Kolkata')::date, false)
    when 'active'
      then coalesce(p_paid_through < (now() at time zone 'Asia/Kolkata')::date, false)
    else false
  end;
$$;
```

- [ ] **Step 4: Join the subscription into `platform_resorts`**

In `supabase/migrations/0049_subscriptions.sql`, replace everything from the comment line `-- Adds the plan columns. Until Task 2 the body is 0045's with empty plan` through the `$$;` that ends `create function public.platform_resorts()` with:

```sql
-- 0045's summary plus the resort's subscription. A resort with no
-- subscription row gets null plan columns and lapsed = false ("No plan").
drop function public.platform_resorts();

create function public.platform_resorts()
returns table(
  property_id       uuid,
  name              text,
  status            text,
  owner_emails      text[],
  created_at        timestamptz,
  bookings_30d      int,
  revenue_30d       numeric,
  bookings_365d     int,
  revenue_365d      numeric,
  plan_tier         public.subscription_tier,
  plan_name         text,
  plan_status       public.subscription_status,
  trial_ends_on     date,
  paid_through      date,
  lapsed            boolean,
  monthly_price_inr numeric,
  plan_notes        text
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  if not public.is_platform_admin() then
    raise exception 'not permitted' using errcode = 'P0008';
  end if;

  return query
    select
      p.id,
      p.name,
      p.status,
      coalesce((
        select array_agg(u.email::text order by u.email)
          from public.resort_members m
          join auth.users u on u.id = m.user_id
         where m.property_id = p.id and m.role = 'owner'), '{}'),
      p.created_at,
      coalesce(b.bookings_30d, 0),
      coalesce(b.revenue_30d, 0),
      coalesce(b.bookings_365d, 0),
      coalesce(b.revenue_365d, 0),
      s.tier,
      pl.name,
      s.status,
      s.trial_ends_on,
      s.paid_through,
      public.subscription_lapsed(s.status, s.trial_ends_on, s.paid_through),
      pl.monthly_price_inr,
      s.notes
    from public.properties p
    left join public.resort_subscriptions s on s.property_id = p.id
    left join public.subscription_plans pl on pl.tier = s.tier
    left join lateral (
      select
        (count(*) filter (where r.created_at >= now() - interval '30 days'))::int
          as bookings_30d,
        sum((r.quote ->> 'total')::numeric)
          filter (where r.created_at >= now() - interval '30 days') as revenue_30d,
        count(*)::int as bookings_365d,
        sum((r.quote ->> 'total')::numeric) as revenue_365d
      from public.reservations r
      where r.property_id = p.id
        and r.kind = 'booking'
        and r.status in ('confirmed','checked_in','checked_out')
        and r.created_at >= now() - interval '365 days'
    ) b on true
    order by p.created_at, p.name;
end;
$$;
```

Every column reference in the body is qualified (`p.`, `s.`, `pl.`, `r.`, `m.`, `u.`): the OUT columns (`status`, `name`, `trial_ends_on`, ...) are plpgsql variables, and an unqualified reference would be ambiguous.

- [ ] **Step 5: Replace the `platform_summary` stub**

Replace the whole `create function public.platform_summary() ... $$;` block with:

```sql
-- The console's three cards (spec decisions 6 and 7). Archived resorts,
-- and resorts with no subscription row, count for nothing. MRR uses each
-- plan's current price.
create function public.platform_summary()
returns table(
  subscribed_count int,
  active_count     int,
  trial_count      int,
  mrr_inr          numeric
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  if not public.is_platform_admin() then
    raise exception 'not permitted' using errcode = 'P0008';
  end if;

  return query
    select
      (count(*) filter (where s.status <> 'cancelled'))::int,
      (count(*) filter (where s.status <> 'cancelled' and not x.lapsed))::int,
      (count(*) filter (where s.status = 'trial' and not x.lapsed))::int,
      coalesce(sum(pl.monthly_price_inr)
                 filter (where s.status = 'active' and not x.lapsed), 0)
    from public.resort_subscriptions s
    join public.properties p on p.id = s.property_id
    join public.subscription_plans pl on pl.tier = s.tier
    cross join lateral (
      select public.subscription_lapsed(s.status, s.trial_ends_on, s.paid_through) as lapsed
    ) x
    where p.status <> 'archived';
end;
$$;
```

- [ ] **Step 6: Replace the `my_resort_subscription` stub**

Replace the whole `create function public.my_resort_subscription(p_property uuid) ... $$;` block with:

```sql
-- The resort's own plan, for its owners and admins (spec decision 8).
-- A read, so it works at a suspended resort; anyone else, including the
-- platform admin, gets P0020. Zero rows when the resort has no plan.
create function public.my_resort_subscription(p_property uuid)
returns table(
  plan_tier         public.subscription_tier,
  plan_name         text,
  plan_status       public.subscription_status,
  trial_ends_on     date,
  paid_through      date,
  lapsed            boolean,
  monthly_price_inr numeric,
  plan_notes        text
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  perform public.assert_resort_role(p_property, false, 'owner','admin');

  return query
    select s.tier, pl.name, s.status, s.trial_ends_on, s.paid_through,
           public.subscription_lapsed(s.status, s.trial_ends_on, s.paid_through),
           pl.monthly_price_inr, s.notes
      from public.resort_subscriptions s
      join public.subscription_plans pl on pl.tier = s.tier
     where s.property_id = p_property;
end;
$$;
```

- [ ] **Step 7: Give the seeded resort its plan**

Append to the end of `supabase/seed.sql`:

```sql

-- 0049_subscriptions.sql starts every resort that already exists on
-- Enterprise, active, with no end date. The seed runs after the
-- migrations, so do the same for the seeded resort.
insert into public.resort_subscriptions (property_id, tier, status)
select id, 'enterprise', 'active' from public.properties
on conflict (property_id) do nothing;
```

- [ ] **Step 8: Run the tests to verify they pass**

Run: `supabase db reset && supabase test db supabase/tests/41_subscriptions_test.sql supabase/tests/37_tenancy_isolation_test.sql supabase/tests/38_resort_members_test.sql`
Expected: PASS, with 41 at 38/38, 38 at 54/54, and 37 at its baseline count.

- [ ] **Step 9: Check the backfill once, against a resort that existed before 0049**

A fresh reset has no resorts when 0049 runs, so no pgTAP test can reach the backfill. Check it by hand, using the migration version written down in Task 1 Step 1 (shown here as `0048`):

```bash
supabase db reset --version 0048 --no-seed
DB_URL="$(supabase status -o env | grep DB_URL | cut -d= -f2 | tr -d '"')"
psql "$DB_URL" -c "insert into public.properties (name, slug) values ('Old Resort', 'old-resort');"
supabase migration up --local
psql "$DB_URL" -At -c "select p.name, s.tier, s.status, coalesce(s.paid_through::text, 'none') from public.resort_subscriptions s join public.properties p on p.id = s.property_id;"
supabase db reset
```

Expected: the query prints exactly `Old Resort|enterprise|active|none`, and the final `supabase db reset` succeeds (it re-runs every migration and the seed).

- [ ] **Step 10: Commit**

```bash
git add supabase/migrations/0049_subscriptions.sql supabase/tests/41_subscriptions_test.sql supabase/seed.sql
git commit -m "feat(db): read resort plans, platform counts and MRR"
```

---

### Task 3: Creating resorts, changing plans and prices

**Track:** DB. **Depends on:** Task 2.

**Files:**
- Modify: `supabase/migrations/0049_subscriptions.sql` (replace the `create_resort` body and two stubs)
- Test: `supabase/tests/41_subscriptions_test.sql` (append a section)

**Interfaces:**
- Consumes: the Task 1 signatures, `subscription_lapsed`, `platform_resorts` and `platform_summary` from Task 2, and the fixtures in 41.
- Produces:
  - `create_resort` inserts the subscription in the same transaction (a trial ending today + `p_trial_days` when `p_trial_days > 0`, else active with no end date) and audits it (`entity 'subscription'`, action `subscription:create`). A null tier or `p_trial_days` outside 0..365 raises P0005.
  - `set_resort_subscription` upserts, keeps only the date the status needs, stores blank notes as null, and audits with before/after JSON (action `subscription:<old tier>/<old status>->...` or `subscription:none->...`).
  - `set_plan_price` changes one price (rounded to paise) and writes a platform audit row (`entity 'subscription_plan'`, `property_id` null, action `price:<old>-><new>`). A null, negative or above 1,00,00,000 price raises P0005.

- [ ] **Step 1: Write the failing tests**

In `supabase/tests/41_subscriptions_test.sql`, change `select plan(38);` to `select plan(62);`. Then insert this section immediately before the final `select * from finish();`:

```sql
-- === Task 3: creating resorts, changing plans and prices ===================

set local role authenticated;
set local request.jwt.claims to '{"sub":"f0000000-0000-0000-0000-000000000001","role":"authenticated"}';

select lives_ok($$select public.create_resort('Sub New Trial', 'sub-other-owner@example.com')$$,
  'create_resort with only a name and an owner still works');
select is((select plan_tier::text || '|' || plan_status::text || '|' || (trial_ends_on - pg_temp.today())::text
             from public.platform_resorts() where name = 'Sub New Trial'),
  'starter|trial|30', 'by default a new resort starts a 30-day Starter trial');
select lives_ok($$select public.create_resort('Sub New Paid', 'sub-other-owner@example.com', 'pro', 0)$$,
  'create_resort with no trial');
select is((select plan_tier::text || '|' || plan_status::text || '|' || coalesce(paid_through::text, 'none')
             from public.platform_resorts() where name = 'Sub New Paid'),
  'pro|active|none', 'with no trial a new resort starts active with no end date');
select throws_ok($$select public.create_resort('Sub Bad', 'sub-other-owner@example.com', 'pro', -1)$$,
  'P0005', null, 'negative trial days are refused');
select throws_ok($$select public.create_resort('Sub Bad', 'sub-other-owner@example.com', 'pro', 366)$$,
  'P0005', null, 'a trial longer than a year is refused');
select throws_ok($$select public.create_resort('Sub Bad', 'sub-other-owner@example.com', null, 30)$$,
  'P0005', null, 'a new resort needs a tier');

-- P9 has no plan yet: set_resort_subscription creates the row.
select lives_ok($$select public.set_resort_subscription('f1000000-0000-4000-8000-000000000009',
  'enterprise', 'trial', pg_temp.today() + 14, pg_temp.today() + 99, '   ')$$,
  'set_resort_subscription gives a plan-less resort a plan');
select is((select plan_tier::text || '|' || plan_status::text || '|' || (trial_ends_on - pg_temp.today())::text
                  || '|' || coalesce(paid_through::text, 'none') || '|' || coalesce(plan_notes, 'none')
             from public.platform_resorts()
            where property_id = 'f1000000-0000-4000-8000-000000000009'),
  'enterprise|trial|14|none|none', 'a trial keeps only its end date, and blank notes are dropped');
-- P4's trial lapsed yesterday: the admin records a payment.
select lives_ok($$select public.set_resort_subscription('f1000000-0000-4000-8000-000000000004',
  'pro', 'active', pg_temp.today() + 3, pg_temp.today() + 30, 'Paid by UPI')$$,
  'the platform admin converts a lapsed trial into a paid plan');
select is((select plan_tier::text || '|' || plan_status::text || '|' || lapsed::text || '|'
                  || coalesce(trial_ends_on::text, 'none') || '|'
                  || (paid_through - pg_temp.today())::text || '|' || plan_notes
             from public.platform_resorts()
            where property_id = 'f1000000-0000-4000-8000-000000000004'),
  'pro|active|false|none|30|Paid by UPI', 'the paid plan runs 30 days, drops the trial date and is no longer lapsed');
select throws_ok($$select public.set_resort_subscription('f1000000-0000-4000-8000-000000000003', 'pro', 'trial')$$,
  'P0005', null, 'a trial needs an end date');
select throws_ok($$select public.set_resort_subscription('f1000000-0000-4000-8000-000000000003', null, 'active')$$,
  'P0005', null, 'a plan needs a tier');
select throws_ok($$select public.set_resort_subscription('00000000-0000-4000-8000-000000000000', 'pro', 'active')$$,
  'P0002', null, 'an unknown resort is not found');

select lives_ok($$select public.set_plan_price('pro', 8999)$$, 'the platform admin changes the Pro price');
select is((select array[subscribed_count, active_count, trial_count] from public.platform_summary()),
  array[9, 8, 3], 'the two new resorts and the plans set above are counted');
select is((select mrr_inr from public.platform_summary()), 49995::numeric,
  'MRR follows the new Pro price: three Pro at 8999 + Enterprise 19999 + Starter 2999');
select throws_ok($$select public.set_plan_price('pro', -1)$$,
  'P0005', null, 'a negative price is refused');
select throws_ok($$update public.resort_subscriptions set status = 'cancelled'$$,
  '42501', null, 'the platform admin writes subscriptions only through the functions');

-- The owner of P1 cannot touch plans or prices.
set local request.jwt.claims to '{"sub":"f0000000-0000-0000-0000-000000000002","role":"authenticated"}';
select throws_ok($$select public.set_resort_subscription('f1000000-0000-4000-8000-000000000001', 'enterprise', 'active')$$,
  'P0008', null, 'an owner cannot change their own plan');
select throws_ok($$select public.set_plan_price('starter', 1)$$,
  'P0008', null, 'an owner cannot change prices');
reset role;
set local request.jwt.claims to '';

select is((select count(*)::int from public.audit_log
            where entity = 'subscription'
              and entity_id = 'f1000000-0000-4000-8000-000000000004'
              and property_id = 'f1000000-0000-4000-8000-000000000004'
              and before ->> 'status' = 'trial' and after ->> 'status' = 'active'),
  1, 'set_resort_subscription writes an audit row with before and after');
select is((select count(*)::int from public.audit_log a
             join public.properties p on p.id = a.entity_id
            where a.entity = 'subscription' and a.action = 'subscription:create'
              and p.name in ('Sub New Trial', 'Sub New Paid')),
  2, 'create_resort audits the subscription it starts');
select is((select count(*)::int from public.audit_log
            where entity = 'subscription_plan' and property_id is null
              and action = 'price:7999.00->8999.00'),
  1, 'set_plan_price writes a platform audit row');
```

- [ ] **Step 2: Run it to verify it fails**

Run: `supabase test db supabase/tests/41_subscriptions_test.sql`
Expected: FAIL. The first Task 3 assertion passes, `by default a new resort starts a 30-day Starter trial` fails (got NULL, because Task 1's `create_resort` inserts no subscription), and the `set_resort_subscription` / `set_plan_price` assertions fail with `0A000`.

- [ ] **Step 3: Replace the `create_resort` body**

In `supabase/migrations/0049_subscriptions.sql`, replace everything from the comment line `-- Adds a tier and trial days. Dropping the two-argument version keeps` through the `$$;` that ends `create function public.create_resort(` with:

```sql
-- 0045's create_resort, plus the resort's subscription in the same
-- transaction: a trial of p_trial_days on p_tier, or active with no end
-- date when p_trial_days is 0. Dropping the two-argument version keeps
-- PostgREST and SQL callers from ever hitting an ambiguous overload.
drop function public.create_resort(text, text);

create function public.create_resort(
  p_name        text,
  p_owner_email text,
  p_tier        public.subscription_tier default 'starter',
  p_trial_days  int default 30
) returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_owner uuid;
  v_base  text;
  v_slug  text;
  v_n     int := 1;
  v_id    uuid;
  v_sub   public.resort_subscriptions;
begin
  if not public.is_platform_admin() then
    raise exception 'not permitted' using errcode = 'P0008';
  end if;

  if coalesce(trim(p_name), '') = '' then
    raise exception 'name is required' using errcode = 'P0005';
  end if;

  if p_tier is null then
    raise exception 'Choose a plan.' using errcode = 'P0005';
  end if;

  if p_trial_days is null or p_trial_days < 0 or p_trial_days > 365 then
    raise exception 'A trial is 0 to 365 days.' using errcode = 'P0005';
  end if;

  select id into v_owner from auth.users
   where lower(email) = lower(trim(p_owner_email));
  if v_owner is null then
    raise exception using errcode = 'P0002', message = 'not_found';
  end if;

  v_base := trim(both '-' from regexp_replace(lower(trim(p_name)), '[^a-z0-9]+', '-', 'g'));
  if v_base = '' then
    v_base := 'resort';
  end if;
  v_slug := v_base;
  while exists (select 1 from public.properties where slug = v_slug) loop
    v_n := v_n + 1;
    v_slug := v_base || '-' || v_n;
  end loop;

  insert into public.properties (name, slug)
  values (trim(p_name), v_slug)
  returning id into v_id;

  insert into public.resort_members (property_id, user_id, role)
  values (v_id, v_owner, 'owner');

  insert into public.resort_subscriptions (property_id, tier, status, trial_ends_on)
  values (v_id,
          p_tier,
          (case when p_trial_days > 0 then 'trial' else 'active' end)::public.subscription_status,
          case when p_trial_days > 0
               then (now() at time zone 'Asia/Kolkata')::date + p_trial_days end)
  returning * into v_sub;

  insert into public.audit_log (actor_id, entity, entity_id, action, before, after, property_id)
  values (auth.uid(), 'subscription', v_id, 'subscription:create',
          null, to_jsonb(v_sub), v_id);

  return v_id;
end;
$$;
```

- [ ] **Step 4: Replace the `set_resort_subscription` stub**

Replace the whole `create function public.set_resort_subscription( ... $$;` block with:

```sql
-- The platform admin sets a resort's plan by hand (spec decision 3). An
-- upsert, so it also gives a "No plan" resort its first plan. Only the
-- date the status needs is kept: trial_ends_on for a trial, paid_through
-- (null = no end date) otherwise.
create function public.set_resort_subscription(
  p_property      uuid,
  p_tier          public.subscription_tier,
  p_status        public.subscription_status,
  p_trial_ends_on date default null,
  p_paid_through  date default null,
  p_notes         text default null
) returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_old public.resort_subscriptions;
  v_new public.resort_subscriptions;
begin
  if not public.is_platform_admin() then
    raise exception 'not permitted' using errcode = 'P0008';
  end if;

  if p_tier is null or p_status is null then
    raise exception 'Choose a plan and a status.' using errcode = 'P0005';
  end if;

  if p_status = 'trial' and p_trial_ends_on is null then
    raise exception 'A trial needs an end date.' using errcode = 'P0005';
  end if;

  perform 1 from public.properties where id = p_property;
  if not found then
    raise exception using errcode = 'P0002', message = 'not_found';
  end if;

  -- Lock the current row, if any, so two saves at once apply one after
  -- the other and each audits what it actually replaced.
  select * into v_old from public.resort_subscriptions
   where property_id = p_property
   for update;

  insert into public.resort_subscriptions as s
    (property_id, tier, status, trial_ends_on, paid_through, notes, updated_at, updated_by)
  values
    (p_property, p_tier, p_status,
     case when p_status = 'trial' then p_trial_ends_on end,
     case when p_status <> 'trial' then p_paid_through end,
     nullif(btrim(p_notes), ''),
     now(), auth.uid())
  on conflict (property_id) do update
    set tier          = excluded.tier,
        status        = excluded.status,
        trial_ends_on = excluded.trial_ends_on,
        paid_through  = excluded.paid_through,
        notes         = excluded.notes,
        updated_at    = excluded.updated_at,
        updated_by    = excluded.updated_by
  returning * into v_new;

  insert into public.audit_log (actor_id, entity, entity_id, action, before, after, property_id)
  values (auth.uid(), 'subscription', p_property,
          'subscription:'
            || coalesce(v_old.tier::text || '/' || v_old.status::text, 'none')
            || '->' || p_tier::text || '/' || p_status::text,
          case when v_old.property_id is null then null else to_jsonb(v_old) end,
          to_jsonb(v_new),
          p_property);
end;
$$;
```

- [ ] **Step 5: Replace the `set_plan_price` stub**

Replace the whole `create function public.set_plan_price( ... $$;` block with:

```sql
-- The platform admin edits a monthly price (spec decision 11). It applies
-- to every resort on the tier at once, so MRR moves with it. A platform
-- event: the audit row has no property_id.
create function public.set_plan_price(
  p_tier              public.subscription_tier,
  p_monthly_price_inr numeric
) returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_old public.subscription_plans;
  v_new public.subscription_plans;
begin
  if not public.is_platform_admin() then
    raise exception 'not permitted' using errcode = 'P0008';
  end if;

  if p_tier is null or p_monthly_price_inr is null
     or p_monthly_price_inr < 0 or p_monthly_price_inr > 10000000 then
    raise exception 'Enter a monthly price from 0 to 1,00,00,000.' using errcode = 'P0005';
  end if;

  select * into v_old from public.subscription_plans where tier = p_tier for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'not_found';
  end if;

  if round(p_monthly_price_inr, 2) = v_old.monthly_price_inr then
    return;
  end if;

  update public.subscription_plans
     set monthly_price_inr = round(p_monthly_price_inr, 2),
         updated_at = now()
   where tier = p_tier
  returning * into v_new;

  insert into public.audit_log (actor_id, entity, entity_id, action, before, after, property_id)
  values (auth.uid(), 'subscription_plan', v_new.id,
          'price:' || v_old.monthly_price_inr::text || '->' || v_new.monthly_price_inr::text,
          jsonb_build_object('monthly_price_inr', v_old.monthly_price_inr),
          jsonb_build_object('monthly_price_inr', v_new.monthly_price_inr),
          null);
end;
$$;
```

- [ ] **Step 6: Run the whole database suite to verify it passes**

Run: `supabase db reset && supabase test db`
Expected: 41 at 62/62, 38 at 54/54, 37 at its baseline count, and every other file as in the Task 1 Step 1 baseline.

- [ ] **Step 7: Commit**

```bash
git add supabase/migrations/0049_subscriptions.sql supabase/tests/41_subscriptions_test.sql
git commit -m "feat(db): create resorts on a plan, set plans and prices by hand, audited"
```

---

## Phase 2: App track (after Task 1; 4 → 5, 4 → 6; 7 and 8 independent)

### Task 4: Console cards, search and tier filter

**Track:** App. **Depends on:** Task 1.

**Files:**
- Create: `lib/features/platform/platform_totals_row.dart`
- Create: `lib/features/platform/resort_filter.dart`
- Create: `lib/features/platform/resort_card.dart` (the card, moved out of the screen unchanged)
- Modify: `lib/features/platform/platform_screen.dart` (whole file)
- Test: `test/features/platform/resort_filter_test.dart` (create), `test/features/platform/platform_screen_test.dart` (append)

**Interfaces:**
- Consumes: `platformResortsProvider`, `platformTotalsProvider`, `PlatformTotals`, `ResortSummary.plan`, `SubscriptionTier`/`label`, `FakePlatformSource`, `resortSummary`, `resortPlan` (Task 1).
- Produces:
  - `List<ResortSummary> filterResorts(List<ResortSummary> resorts, {String query = '', SubscriptionTier? tier})`
  - `class ResortFilterBar extends StatelessWidget` (`search`, `tier`, `onSearchChanged`, `onTierChanged`); keys `resort-search`, `tier-filter`.
  - `class PlatformTotalsRow extends ConsumerWidget`; keys `total-subscribed`, `total-active`, `total-mrr`, `totals-retry`.
  - `class ResortCard extends ConsumerWidget { ResortCard({required ResortSummary resort, required VoidCallback onChanged}) }` in `resort_card.dart`, with the keys `resort-row-<id>` and `resort-status-btn-<id>`. Task 5 rewrites this file.
  - `PlatformScreen` is a `ConsumerStatefulWidget`; its `_refresh()` invalidates `platformResortsProvider` **and** `platformTotalsProvider`, and is what it passes as every card's `onChanged`. The `_NewResortDialog` stays in the screen file until Task 6.

- [ ] **Step 1: Write the failing filter tests**

Create `test/features/platform/resort_filter_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/data/models/subscription.dart';
import 'package:pasala/features/platform/resort_filter.dart';

import '../../support/fake_platform_source.dart';

void main() {
  final a = resortSummary(
      propertyId: 'p1',
      name: 'Resort A',
      ownerEmails: const ['ownera@x.com'],
      plan: resortPlan(tier: SubscriptionTier.pro));
  final b = resortSummary(
      propertyId: 'p2',
      name: 'Resort B',
      ownerEmails: const ['ownerb@x.com', 'co@x.com'],
      plan: resortPlan(tier: SubscriptionTier.starter));
  final none = resortSummary(
      propertyId: 'p3', name: 'Hill Stay', ownerEmails: const []);
  final all = [a, b, none];

  test('an empty or blank query with All tiers keeps everything, in order',
      () {
    expect(filterResorts(all), all);
    expect(filterResorts(all, query: '   '), all);
  });

  test('the query ignores case and surrounding spaces', () {
    expect(filterResorts(all, query: '  RESORT a '), [a]);
  });

  test('the query matches any owner email', () {
    expect(filterResorts(all, query: 'CO@X'), [b]);
  });

  test('a tier hides other tiers and resorts with no plan', () {
    expect(filterResorts(all, tier: SubscriptionTier.pro), [a]);
    expect(filterResorts(all, tier: SubscriptionTier.enterprise), isEmpty);
  });

  test('the query and the tier combine', () {
    expect(
        filterResorts(all, query: 'resort', tier: SubscriptionTier.starter),
        [b]);
  });
}
```

- [ ] **Step 2: Write the failing console tests**

In `test/features/platform/platform_screen_test.dart`, add `import 'package:pasala/core/errors.dart';` to the imports. Add this helper after `_appFor`:

```dart
/// A surface tall enough that every card in these tests is built.
void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}
```

Then add this group at the end of `main()`:

```dart
  group('cards, search and tier filter', () {
    final paidPro = resortSummary(
        propertyId: 'p1',
        name: 'Resort A',
        ownerEmails: const ['ownera@x.com'],
        plan: resortPlan(tier: SubscriptionTier.pro));
    final trialStarter = resortSummary(
        propertyId: 'p2',
        name: 'Resort B',
        ownerEmails: const ['ownerb@x.com'],
        plan: resortPlan(
            tier: SubscriptionTier.starter,
            status: SubscriptionStatus.trial,
            trialEndsOn: DateTime(2026, 10, 24)));
    final noPlan = resortSummary(
        propertyId: 'p3', name: 'Hill Stay', ownerEmails: const ['hill@x.com']);

    Finder inCard(String key, String text) => find.descendant(
        of: find.byKey(Key(key)), matching: find.text(text));

    testWidgets('the cards show the platform totals', (tester) async {
      _tall(tester);
      final repo = FakePlatformSource()
        ..store = [paidPro]
        ..totalsValue = const PlatformTotals(
            subscribed: 21, active: 19, trials: 2, mrrInr: 123456);
      await tester.pumpWidget(_appFor(repo));
      await tester.pumpAndSettle();

      expect(inCard('total-subscribed', 'Subscribed resorts'), findsOneWidget);
      expect(inCard('total-subscribed', '21'), findsOneWidget);
      expect(inCard('total-active', 'Active subscriptions'), findsOneWidget);
      expect(inCard('total-active', '19'), findsOneWidget);
      expect(inCard('total-active', 'incl. 2 trials'), findsOneWidget);
      expect(inCard('total-mrr', 'MRR'), findsOneWidget);
      expect(inCard('total-mrr', formatInr(123456)), findsOneWidget);
    });

    testWidgets('one trial reads "incl. 1 trial"', (tester) async {
      final repo = FakePlatformSource()
        ..store = [paidPro]
        ..totalsValue = const PlatformTotals(
            subscribed: 1, active: 1, trials: 1, mrrInr: 0);
      await tester.pumpWidget(_appFor(repo));
      await tester.pumpAndSettle();

      expect(inCard('total-active', 'incl. 1 trial'), findsOneWidget);
    });

    testWidgets(
        'search matches names and owner emails, ignoring case and spaces',
        (tester) async {
      _tall(tester);
      final repo = FakePlatformSource()..store = [paidPro, trialStarter, noPlan];
      await tester.pumpWidget(_appFor(repo));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const Key('resort-search')), '  RESORT a ');
      await tester.pumpAndSettle();
      expect(find.text('Resort A'), findsOneWidget);
      expect(find.text('Resort B'), findsNothing);
      expect(find.text('Hill Stay'), findsNothing);

      await tester.enterText(find.byKey(const Key('resort-search')), 'hill@');
      await tester.pumpAndSettle();
      expect(find.text('Hill Stay'), findsOneWidget);
      expect(find.text('Resort A'), findsNothing);
    });

    testWidgets('the tier dropdown narrows the list and All tiers restores it',
        (tester) async {
      _tall(tester);
      final repo = FakePlatformSource()..store = [paidPro, trialStarter, noPlan];
      await tester.pumpWidget(_appFor(repo));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('tier-filter')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pro').last);
      await tester.pumpAndSettle();
      expect(find.text('Resort A'), findsOneWidget);
      expect(find.text('Resort B'), findsNothing);
      expect(find.text('Hill Stay'), findsNothing);

      await tester.tap(find.byKey(const Key('tier-filter')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('All tiers').last);
      await tester.pumpAndSettle();
      expect(find.text('Resort A'), findsOneWidget);
      expect(find.text('Resort B'), findsOneWidget);
      expect(find.text('Hill Stay'), findsOneWidget);
    });

    testWidgets('a search that matches nothing says so', (tester) async {
      final repo = FakePlatformSource()..store = [paidPro];
      await tester.pumpWidget(_appFor(repo));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('resort-search')), 'zzz');
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('no-matching-resorts')), findsOneWidget);
      expect(find.text('No resorts match your search.'), findsOneWidget);
    });

    testWidgets('a status change refreshes the cards as well as the list',
        (tester) async {
      final repo = FakePlatformSource()..store = [paidPro];
      await tester.pumpWidget(_appFor(repo));
      await tester.pumpAndSettle();
      expect(repo.totalsCalls, 1);

      await tester.tap(find.byKey(const Key('resort-status-btn-p1')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Suspend'));
      await tester.pumpAndSettle();

      expect(repo.totalsCalls, 2);
    });

    testWidgets('failed totals offer a retry and keep the list',
        (tester) async {
      final repo = FakePlatformSource()
        ..store = [paidPro]
        ..totalsError = const NetworkFailure();
      // retry: null -- without it Riverpod 3 keeps retrying the failed
      // provider and the error never settles.
      await tester.pumpWidget(ProviderScope(
        retry: (_, _) => null,
        overrides: [platformSourceProvider.overrideWithValue(repo)],
        child: const MaterialApp(home: PlatformScreen()),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Resort A'), findsOneWidget);
      expect(find.byKey(const Key('totals-retry')), findsOneWidget);

      repo.totalsError = null;
      await tester.tap(find.byKey(const Key('totals-retry')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('totals-retry')), findsNothing);
      expect(repo.totalsCalls, 2);
    });
  });
```

- [ ] **Step 3: Run them to verify they fail**

Run: `flutter test test/features/platform/resort_filter_test.dart test/features/platform/platform_screen_test.dart`
Expected: FAIL to compile with "Target of URI doesn't exist: 'package:pasala/features/platform/resort_filter.dart'".

- [ ] **Step 4: Write the filter**

Create `lib/features/platform/resort_filter.dart`:

```dart
import 'package:flutter/material.dart';

import '../../core/theme/spacing.dart';
import '../../data/models/subscription.dart';
import '../../data/repositories/platform_repository.dart';

/// The console's live search and tier filter (REQ-08), applied on the
/// device over `platform_resorts()`, which is fine at tens or hundreds of
/// resorts. [query] matches the resort name or any owner email, ignoring
/// case and surrounding spaces. A [tier] hides resorts on other tiers and
/// resorts with no plan; null ("All tiers") keeps them all. Order is kept.
List<ResortSummary> filterResorts(
  List<ResortSummary> resorts, {
  String query = '',
  SubscriptionTier? tier,
}) {
  final q = query.trim().toLowerCase();
  bool matches(ResortSummary r) =>
      q.isEmpty ||
      r.name.toLowerCase().contains(q) ||
      r.ownerEmails.any((e) => e.toLowerCase().contains(q));
  return [
    for (final r in resorts)
      if ((tier == null || r.plan?.tier == tier) && matches(r)) r,
  ];
}

/// The search field and the tier dropdown above the resort list.
class ResortFilterBar extends StatelessWidget {
  const ResortFilterBar({
    super.key,
    required this.search,
    required this.tier,
    required this.onSearchChanged,
    required this.onTierChanged,
  });

  final TextEditingController search;
  final SubscriptionTier? tier;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<SubscriptionTier?> onTierChanged;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(
            child: TextField(
              key: const Key('resort-search'),
              controller: search,
              onChanged: onSearchChanged,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                labelText: 'Search resorts or owner emails',
              ),
            ),
          ),
          const SizedBox(width: Spacing.sm),
          DropdownButton<SubscriptionTier?>(
            key: const Key('tier-filter'),
            value: tier,
            onChanged: onTierChanged,
            items: [
              const DropdownMenuItem<SubscriptionTier?>(
                  value: null, child: Text('All tiers')),
              for (final t in SubscriptionTier.values)
                DropdownMenuItem<SubscriptionTier?>(
                    value: t, child: Text(t.label)),
            ],
          ),
        ],
      );
}
```

- [ ] **Step 5: Write the cards**

Create `lib/features/platform/platform_totals_row.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme/spacing.dart';
import '../../data/models/subscription.dart';
import '../../data/repositories/platform_repository.dart';

/// The console's three count cards (REQ-08): Subscribed resorts, Active
/// subscriptions and MRR, from `platform_summary()`. Platform-wide: the
/// search and tier filter never change them. They wrap on a phone.
class PlatformTotalsRow extends ConsumerWidget {
  const PlatformTotalsRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final totalsAsync = ref.watch(platformTotalsProvider);
    final totals = totalsAsync.value;

    // Loading or failed: a dash, never a zero that looks like real data.
    String show(String Function(PlatformTotals t) pick) =>
        totals == null ? '—' : pick(totals);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: Spacing.sm,
          runSpacing: Spacing.sm,
          children: [
            _TotalCard(
              key: const Key('total-subscribed'),
              label: 'Subscribed resorts',
              value: show((t) => '${t.subscribed}'),
            ),
            _TotalCard(
              key: const Key('total-active'),
              label: 'Active subscriptions',
              value: show((t) => '${t.active}'),
              detail: totals == null
                  ? null
                  : 'incl. ${totals.trials} trial${totals.trials == 1 ? '' : 's'}',
            ),
            _TotalCard(
              key: const Key('total-mrr'),
              label: 'MRR',
              value: show((t) => formatInr(t.mrrInr)),
            ),
          ],
        ),
        if (totalsAsync.hasError && !totalsAsync.isLoading)
          TextButton.icon(
            key: const Key('totals-retry'),
            onPressed: () => ref.invalidate(platformTotalsProvider),
            icon: const Icon(Icons.refresh),
            label: const Text('Totals unavailable. Retry'),
          ),
      ],
    );
  }
}

class _TotalCard extends StatelessWidget {
  const _TotalCard({
    super.key,
    required this.label,
    required this.value,
    this.detail,
  });

  final String label;
  final String value;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 168,
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(Spacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: textTheme.labelMedium
                      ?.copyWith(color: scheme.onSurfaceVariant)),
              const SizedBox(height: Spacing.xs),
              Text(value, style: textTheme.headlineSmall),
              if (detail != null)
                Text(detail!,
                    style: textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 6: Move the resort card to its own file**

Create `lib/features/platform/resort_card.dart` with `_ResortCard` and `_statusLabel` moved out of `platform_screen.dart` unchanged, except that the class becomes public `ResortCard`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../core/format.dart';
import '../../core/theme/spacing.dart';
import '../../core/widgets/failure_view.dart';
import '../../data/repositories/platform_repository.dart';

String _statusLabel(String status) =>
    status.isEmpty ? status : status[0].toUpperCase() + status.substring(1);

/// One resort on the platform console: name, status, owners, booking
/// summary, and a Suspend (active) or Reactivate (suspended) action --
/// none for an archived resort. [onChanged] runs after a change, so the
/// console refetches the list and the cards.
class ResortCard extends ConsumerWidget {
  const ResortCard({super.key, required this.resort, required this.onChanged});

  final ResortSummary resort;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final suspended = resort.status == 'suspended';
    // Archived resorts are neither suspended nor active: they get no
    // status action here (Suspend would pretend they were active).
    final archived = resort.status == 'archived';

    return Card(
      key: Key('resort-row-${resort.propertyId}'),
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(resort.name,
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                Chip(
                  label: Text(_statusLabel(resort.status)),
                  backgroundColor: suspended
                      ? scheme.errorContainer
                      : archived
                          ? scheme.surfaceContainerHighest
                          : scheme.secondaryContainer,
                  side: BorderSide.none,
                ),
              ],
            ),
            const SizedBox(height: Spacing.xs),
            Text(
              resort.ownerEmails.isEmpty
                  ? 'No owner'
                  : resort.ownerEmails.join(', '),
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: Spacing.sm),
            Text(
              '${resort.bookings30d} bookings · ${formatInr(resort.revenue30d)} '
              '(last 30 days)',
            ),
            Text(
              '${resort.bookings365d} bookings · ${formatInr(resort.revenue365d)} '
              '(last 365 days)',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
            if (!archived) ...[
              const SizedBox(height: Spacing.sm),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton(
                  key: Key('resort-status-btn-${resort.propertyId}'),
                  onPressed: () => _confirmAndSetStatus(context, ref),
                  child: Text(suspended ? 'Reactivate' : 'Suspend'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _confirmAndSetStatus(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final suspending = resort.status != 'suspended';
    final newStatus = suspending ? 'suspended' : 'active';
    final actionLabel = suspending ? 'Suspend' : 'Reactivate';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('$actionLabel ${resort.name}?'),
        content: Text(
          suspending
              ? 'Staff at this resort will no longer be able to make changes. '
                'The guest can still read and cancel their bookings.'
              : 'This resort will be reactivated and staff can work again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(actionLabel),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      await ref
          .read(platformSourceProvider)
          .setStatus(resort.propertyId, newStatus);
      onChanged();
    } on BookingFailure catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(FailureView.messageFor(e))));
      }
    }
  }
}
```

- [ ] **Step 7: Rebuild the screen around the cards and the filter**

Replace the whole of `lib/features/platform/platform_screen.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors.dart';
import '../../core/theme/spacing.dart';
import '../../core/theme/theme_toggle_button.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/failure_view.dart';
import '../../data/models/subscription.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/platform_repository.dart';
import 'platform_totals_row.dart';
import 'resort_card.dart';
import 'resort_filter.dart';

/// `/platform` -- the platform admin's SaaS console (REQ-08): the
/// Subscribed / Active / MRR cards, a live search and a tier filter over
/// every resort, and per resort its status, owners, booking summary and
/// actions. The platform admin has no membership at any resort and no row
/// access to any resort-owned table (see the tenancy design spec), so this
/// screen reads and writes only through [PlatformSource].
///
/// Sits outside `AppShell`'s `ShellRoute` -- like `/choose-resort` -- since
/// its nav destinations are keyed off a current resort the platform admin
/// never has, so it carries its own sign-out action instead.
class PlatformScreen extends ConsumerStatefulWidget {
  const PlatformScreen({super.key});

  @override
  ConsumerState<PlatformScreen> createState() => _PlatformScreenState();
}

class _PlatformScreenState extends ConsumerState<PlatformScreen> {
  final _search = TextEditingController();
  SubscriptionTier? _tier;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// After any change the list and the cards both move.
  void _refresh() {
    ref.invalidate(platformResortsProvider);
    ref.invalidate(platformTotalsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final resortsAsync = ref.watch(platformResortsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Platform'),
        actions: [
          const ThemeToggleButton(),
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: _signOut,
          ),
        ],
      ),
      body: AsyncView(
        value: resortsAsync,
        onRetry: _refresh,
        empty: () => const EmptyState(
          icon: Icons.apartment_outlined,
          title: 'No resorts yet',
          message: 'Tap + to create the first one.',
        ),
        data: (resorts) {
          final shown =
              filterResorts(resorts, query: _search.text, tier: _tier);
          return ListView(
            padding: const EdgeInsets.all(Spacing.md),
            children: [
              const PlatformTotalsRow(),
              const SizedBox(height: Spacing.md),
              ResortFilterBar(
                search: _search,
                tier: _tier,
                onSearchChanged: (_) => setState(() {}),
                onTierChanged: (tier) => setState(() => _tier = tier),
              ),
              const SizedBox(height: Spacing.md),
              if (shown.isEmpty)
                const Padding(
                  key: Key('no-matching-resorts'),
                  padding: EdgeInsets.all(Spacing.lg),
                  child: Text(
                    'No resorts match your search.',
                    textAlign: TextAlign.center,
                  ),
                )
              else
                for (final resort in shown) ...[
                  ResortCard(resort: resort, onChanged: _refresh),
                  const SizedBox(height: Spacing.sm),
                ],
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => showDialog<void>(
          context: context,
          builder: (_) => const _NewResortDialog(),
        ),
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<void> _signOut() async {
    try {
      await ref.read(authRepositoryProvider).signOut();
      if (mounted) context.go('/login');
    } on BookingFailure catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(FailureView.messageFor(e))));
      }
    }
  }
}

/// "New resort" dialog: a name and an owner email, calling
/// `create_resort` -- the owner email must belong to an existing account
/// (no in-app account creation; see the tenancy design spec).
class _NewResortDialog extends ConsumerStatefulWidget {
  const _NewResortDialog();

  @override
  ConsumerState<_NewResortDialog> createState() => _NewResortDialogState();
}

class _NewResortDialogState extends ConsumerState<_NewResortDialog> {
  final _name = TextEditingController();
  final _ownerEmail = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _ownerEmail.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _name.text.trim();
    final ownerEmail = _ownerEmail.text.trim();
    if (name.isEmpty || ownerEmail.isEmpty) {
      setState(() => _error = 'Enter a name and an owner email.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(platformSourceProvider).createResort(name, ownerEmail);
      if (!mounted) return;
      ref.invalidate(platformResortsProvider);
      ref.invalidate(platformTotalsProvider);
      Navigator.of(context).pop();
    } on BookingFailure catch (e) {
      if (mounted) setState(() => _error = FailureView.messageFor(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('New resort'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const Key('new-resort-name'),
              controller: _name,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            const SizedBox(height: Spacing.sm),
            TextField(
              key: const Key('new-resort-owner-email'),
              controller: _ownerEmail,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Owner email',
                helperText: 'Must belong to an existing account',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: Spacing.sm),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: _busy ? null : _create,
            child: const Text('Create'),
          ),
        ],
      );
}
```

- [ ] **Step 8: Run the tests to verify they pass**

Run: `flutter test test/features/platform/ && flutter analyze`
Expected: all tests PASS, including the seven tests that were there before this task. The analyzer shows no issues beyond the Task 1 baseline.

- [ ] **Step 9: Commit**

```bash
git add lib/features/platform/platform_screen.dart lib/features/platform/platform_totals_row.dart \
  lib/features/platform/resort_filter.dart lib/features/platform/resort_card.dart \
  test/features/platform/resort_filter_test.dart test/features/platform/platform_screen_test.dart
git commit -m "feat(platform): subscribed, active and MRR cards, live search and tier filter"
```

---

### Task 5: Plan line and the Change plan dialog

**Track:** App. **Depends on:** Task 4. Can run alongside Task 6.

**Files:**
- Create: `lib/features/platform/change_plan_dialog.dart`
- Modify: `lib/features/platform/resort_card.dart` (whole file)
- Test: `test/features/platform/change_plan_dialog_test.dart`, `test/features/platform/resort_card_test.dart`

**Interfaces:**
- Consumes: `ResortCard` (Task 4), `PlatformSource.setSubscription`, `planStatusLine`, `ResortPlan`, `SubscriptionTier`/`SubscriptionStatus` and their labels, `formatDate`, `FakePlatformSource`, `SubscriptionCall`, `resortSummary`, `resortPlan` (Task 1).
- Produces:
  - `class ChangePlanDialog extends ConsumerStatefulWidget { ChangePlanDialog({required ResortSummary resort, DateTime? today}) }`. It pops `true` after a save and `false` on Cancel. Keys: `plan-tier`, `plan-status`, `plan-date`, `plan-date-clear`, `plan-notes`, `plan-save`.
  - `class PlanLine extends StatelessWidget { PlanLine({required ResortPlan plan}) }`.
  - `ResortCard` gains the tier chip (key `resort-tier-<id>`, `No plan` when there is none), the plan line, and a `Change plan` / `Set plan` button (key `resort-plan-btn-<id>`, hidden on archived resorts) that calls `onChanged` after a save.

- [ ] **Step 1: Write the failing dialog tests**

Create `test/features/platform/change_plan_dialog_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/errors.dart';
import 'package:pasala/data/models/subscription.dart';
import 'package:pasala/data/repositories/platform_repository.dart';
import 'package:pasala/features/platform/change_plan_dialog.dart';

import '../../support/fake_platform_source.dart';

final _paid = resortSummary(
  propertyId: 'p1',
  plan: resortPlan(
    tier: SubscriptionTier.pro,
    paidThrough: DateTime(2026, 10, 31),
    notes: 'Invoice 12',
  ),
);

Future<void> _open(
  WidgetTester tester,
  FakePlatformSource source,
  ResortSummary resort, {
  DateTime? today,
}) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [platformSourceProvider.overrideWithValue(source)],
    child: MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => showDialog<bool>(
                context: context,
                builder: (_) => ChangePlanDialog(resort: resort, today: today),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Future<void> _save(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('plan-save')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('opens on the current plan and saves it as it is',
      (tester) async {
    final source = FakePlatformSource();
    await _open(tester, source, _paid);

    expect(find.text('Paid until'), findsOneWidget);
    expect(find.text('31 Oct 2026'), findsOneWidget);
    await _save(tester);

    expect(source.subscriptionCalls, [
      (
        propertyId: 'p1',
        tier: SubscriptionTier.pro,
        status: SubscriptionStatus.active,
        trialEndsOn: null,
        paidThrough: DateTime(2026, 10, 31),
        notes: 'Invoice 12',
      ),
    ]);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('switching to Trial needs an end date before it saves',
      (tester) async {
    final source = FakePlatformSource();
    await _open(tester, source, _paid);

    await tester.tap(find.byKey(const Key('plan-tier')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enterprise').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Trial'));
    await tester.pumpAndSettle();

    expect(find.text('Trial ends'), findsOneWidget);
    expect(find.text('No end date'), findsOneWidget);
    await _save(tester);
    expect(find.text('Pick the date the trial ends.'), findsOneWidget);
    expect(source.subscriptionCalls, isEmpty);

    await tester.tap(find.byKey(const Key('plan-date')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Switch to input'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '11/15/2026');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('15 Nov 2026'), findsOneWidget);
    await _save(tester);

    expect(source.subscriptionCalls, [
      (
        propertyId: 'p1',
        tier: SubscriptionTier.enterprise,
        status: SubscriptionStatus.trial,
        trialEndsOn: DateTime(2026, 11, 15),
        paidThrough: null,
        notes: 'Invoice 12',
      ),
    ]);
  });

  testWidgets('a resort with no plan starts from a 30-day Starter trial',
      (tester) async {
    final source = FakePlatformSource();
    await _open(tester, source, resortSummary(propertyId: 'p9'),
        today: DateTime(2026, 9, 25));

    expect(find.text('25 Oct 2026'), findsOneWidget);
    await _save(tester);

    expect(source.subscriptionCalls, [
      (
        propertyId: 'p9',
        tier: SubscriptionTier.starter,
        status: SubscriptionStatus.trial,
        trialEndsOn: DateTime(2026, 10, 25),
        paidThrough: null,
        notes: null,
      ),
    ]);
  });

  testWidgets('clearing the paid-until date saves no end date',
      (tester) async {
    final source = FakePlatformSource();
    await _open(tester, source, _paid);

    await tester.tap(find.byKey(const Key('plan-date-clear')));
    await tester.pumpAndSettle();
    expect(find.text('No end date'), findsOneWidget);
    await _save(tester);

    expect(source.subscriptionCalls.single.paidThrough, isNull);
    expect(source.subscriptionCalls.single.status, SubscriptionStatus.active);
  });

  testWidgets('blank notes are sent as null', (tester) async {
    final source = FakePlatformSource();
    await _open(tester, source, _paid);

    await tester.enterText(find.byKey(const Key('plan-notes')), '   ');
    await _save(tester);

    expect(source.subscriptionCalls.single.notes, isNull);
  });

  testWidgets('a server refusal shows its message and keeps the dialog open',
      (tester) async {
    final source = FakePlatformSource()
      ..subscriptionError = const InvalidState('A trial needs an end date.');
    await _open(tester, source, _paid);

    await _save(tester);

    expect(find.text('A trial needs an end date.'), findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget);
  });
}
```

- [ ] **Step 2: Write the failing card tests**

Create `test/features/platform/resort_card_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/data/models/subscription.dart';
import 'package:pasala/data/repositories/platform_repository.dart';
import 'package:pasala/features/platform/resort_card.dart';

import '../../support/fake_platform_source.dart';

Future<void> _pump(
  WidgetTester tester,
  FakePlatformSource source,
  ResortSummary resort, {
  VoidCallback? onChanged,
}) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [platformSourceProvider.overrideWithValue(source)],
    child: MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ResortCard(resort: resort, onChanged: onChanged ?? () {}),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a paid plan shows its tier and its paid-until date',
      (tester) async {
    await _pump(
        tester,
        FakePlatformSource(),
        resortSummary(
            plan: resortPlan(
                tier: SubscriptionTier.pro,
                paidThrough: DateTime(2026, 10, 31))));

    expect(
        find.descendant(
            of: find.byKey(const Key('resort-tier-p1')),
            matching: find.text('Pro')),
        findsOneWidget);
    expect(find.text('Paid until 31 Oct 2026'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Change plan'), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
  });

  testWidgets('a lapsed plan says Lapsed, with an icon, in the error colour',
      (tester) async {
    await _pump(
        tester,
        FakePlatformSource(),
        resortSummary(
            plan: resortPlan(
                paidThrough: DateTime(2026, 9, 30), lapsed: true)));

    final line = find.text('Lapsed: paid until 30 Sep 2026');
    expect(line, findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    final error =
        Theme.of(tester.element(find.byType(ResortCard))).colorScheme.error;
    expect(tester.widget<Text>(line).style?.color, error);
  });

  testWidgets('a resort with no plan shows No plan and offers Set plan',
      (tester) async {
    await _pump(tester, FakePlatformSource(), resortSummary());

    expect(
        find.descendant(
            of: find.byKey(const Key('resort-tier-p1')),
            matching: find.text('No plan')),
        findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Set plan'), findsOneWidget);
  });

  testWidgets('an archived resort offers neither a plan nor a status action',
      (tester) async {
    await _pump(
        tester,
        FakePlatformSource(),
        resortSummary(
            propertyId: 'p3', status: 'archived', plan: resortPlan()));

    expect(find.byKey(const Key('resort-plan-btn-p3')), findsNothing);
    expect(find.byKey(const Key('resort-status-btn-p3')), findsNothing);
  });

  testWidgets('saving the Change plan dialog calls onChanged once',
      (tester) async {
    final source = FakePlatformSource();
    var changed = 0;
    await _pump(tester, source, resortSummary(plan: resortPlan()),
        onChanged: () => changed++);

    await tester.tap(find.byKey(const Key('resort-plan-btn-p1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('plan-save')));
    await tester.pumpAndSettle();

    expect(source.subscriptionCalls, hasLength(1));
    expect(changed, 1);
  });

  testWidgets('cancelling the dialog changes nothing', (tester) async {
    final source = FakePlatformSource();
    var changed = 0;
    await _pump(tester, source, resortSummary(plan: resortPlan()),
        onChanged: () => changed++);

    await tester.tap(find.byKey(const Key('resort-plan-btn-p1')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(source.subscriptionCalls, isEmpty);
    expect(changed, 0);
  });
}
```

- [ ] **Step 3: Run them to verify they fail**

Run: `flutter test test/features/platform/change_plan_dialog_test.dart test/features/platform/resort_card_test.dart`
Expected: FAIL to compile with "Target of URI doesn't exist: 'package:pasala/features/platform/change_plan_dialog.dart'".

- [ ] **Step 4: Write the dialog**

Create `lib/features/platform/change_plan_dialog.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../core/format.dart';
import '../../core/theme/spacing.dart';
import '../../core/widgets/failure_view.dart';
import '../../data/models/subscription.dart';
import '../../data/repositories/platform_repository.dart';

/// "Change plan" / "Set plan" on a resort card: the tier, the status, the
/// date that status needs (a trial's last day, required; or the paid-until
/// date, optional) and notes, saved with `set_resort_subscription`. Pops
/// `true` after a save so the caller refetches the list and the cards,
/// `false` on Cancel.
class ChangePlanDialog extends ConsumerStatefulWidget {
  const ChangePlanDialog({super.key, required this.resort, this.today});

  final ResortSummary resort;

  /// Today's date, for the default 30-day trial of a resort with no plan.
  /// Defaults to the device's date; tests pin it.
  final DateTime? today;

  @override
  ConsumerState<ChangePlanDialog> createState() => _ChangePlanDialogState();
}

class _ChangePlanDialogState extends ConsumerState<ChangePlanDialog> {
  late SubscriptionTier _tier;
  late SubscriptionStatus _status;
  DateTime? _trialEndsOn;
  DateTime? _paidThrough;
  final _notes = TextEditingController();
  String? _error;
  bool _busy = false;

  DateTime get _today {
    final now = widget.today ?? DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  bool get _isTrial => _status == SubscriptionStatus.trial;

  @override
  void initState() {
    super.initState();
    final plan = widget.resort.plan;
    if (plan == null) {
      // A resort with no plan starts where "Add resort" would: a 30-day
      // Starter trial.
      final today = _today;
      _tier = SubscriptionTier.starter;
      _status = SubscriptionStatus.trial;
      _trialEndsOn = DateTime(today.year, today.month, today.day + 30);
    } else {
      _tier = plan.tier;
      _status = plan.status;
      _trialEndsOn = plan.trialEndsOn;
      _paidThrough = plan.paidThrough;
      _notes.text = plan.notes ?? '';
    }
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final current = _isTrial ? _trialEndsOn : _paidThrough;
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? _today,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _error = null;
      if (_isTrial) {
        _trialEndsOn = picked;
      } else {
        _paidThrough = picked;
      }
    });
  }

  Future<void> _save() async {
    if (_isTrial && _trialEndsOn == null) {
      setState(() => _error = 'Pick the date the trial ends.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final notes = _notes.text.trim();
      await ref.read(platformSourceProvider).setSubscription(
            widget.resort.propertyId,
            tier: _tier,
            status: _status,
            trialEndsOn: _isTrial ? _trialEndsOn : null,
            paidThrough: _isTrial ? null : _paidThrough,
            notes: notes.isEmpty ? null : notes,
          );
      if (mounted) Navigator.of(context).pop(true);
    } on BookingFailure catch (e) {
      if (mounted) setState(() => _error = FailureView.messageFor(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final date = _isTrial ? _trialEndsOn : _paidThrough;

    return AlertDialog(
      title: Text('Plan for ${widget.resort.name}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<SubscriptionTier>(
              key: const Key('plan-tier'),
              initialValue: _tier,
              decoration: const InputDecoration(labelText: 'Tier'),
              items: [
                for (final t in SubscriptionTier.values)
                  DropdownMenuItem(value: t, child: Text(t.label)),
              ],
              onChanged: (t) {
                if (t != null) setState(() => _tier = t);
              },
            ),
            const SizedBox(height: Spacing.md),
            SegmentedButton<SubscriptionStatus>(
              key: const Key('plan-status'),
              segments: [
                for (final s in SubscriptionStatus.values)
                  ButtonSegment(value: s, label: Text(s.label)),
              ],
              selected: {_status},
              onSelectionChanged: (selected) => setState(() {
                _status = selected.first;
                _error = null;
              }),
            ),
            const SizedBox(height: Spacing.md),
            Row(
              children: [
                Expanded(child: Text(_isTrial ? 'Trial ends' : 'Paid until')),
                TextButton.icon(
                  key: const Key('plan-date'),
                  onPressed: _busy ? null : _pickDate,
                  icon: const Icon(Icons.event_outlined),
                  label: Text(date == null ? 'No end date' : formatDate(date)),
                ),
                if (!_isTrial && _paidThrough != null)
                  IconButton(
                    key: const Key('plan-date-clear'),
                    tooltip: 'No end date',
                    icon: const Icon(Icons.clear),
                    onPressed: () => setState(() => _paidThrough = null),
                  ),
              ],
            ),
            const SizedBox(height: Spacing.sm),
            TextField(
              key: const Key('plan-notes'),
              controller: _notes,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Notes',
                helperText: "Visible to the resort's owners and admins",
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: Spacing.sm),
              Text(_error!, style: TextStyle(color: scheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('plan-save'),
          onPressed: _busy ? null : _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
```

- [ ] **Step 5: Add the plan to the card**

Replace the whole of `lib/features/platform/resort_card.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../core/format.dart';
import '../../core/theme/spacing.dart';
import '../../core/widgets/failure_view.dart';
import '../../data/models/subscription.dart';
import '../../data/repositories/platform_repository.dart';
import 'change_plan_dialog.dart';

String _statusLabel(String status) =>
    status.isEmpty ? status : status[0].toUpperCase() + status.substring(1);

/// One resort on the platform console: name, status, owners, its plan
/// (tier chip and plan line), booking summary, and the actions -- Change
/// plan (Set plan when it has none) and Suspend (active) or Reactivate
/// (suspended). An archived resort gets no action at all. [onChanged]
/// runs after a change, so the console refetches the list and the cards.
class ResortCard extends ConsumerWidget {
  const ResortCard({super.key, required this.resort, required this.onChanged});

  final ResortSummary resort;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final suspended = resort.status == 'suspended';
    // Archived resorts are neither suspended nor active: they get no
    // status action here (Suspend would pretend they were active).
    final archived = resort.status == 'archived';
    final plan = resort.plan;

    return Card(
      key: Key('resort-row-${resort.propertyId}'),
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(resort.name,
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                Chip(
                  label: Text(_statusLabel(resort.status)),
                  backgroundColor: suspended
                      ? scheme.errorContainer
                      : archived
                          ? scheme.surfaceContainerHighest
                          : scheme.secondaryContainer,
                  side: BorderSide.none,
                ),
              ],
            ),
            const SizedBox(height: Spacing.xs),
            Text(
              resort.ownerEmails.isEmpty
                  ? 'No owner'
                  : resort.ownerEmails.join(', '),
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: Spacing.sm),
            Wrap(
              spacing: Spacing.sm,
              runSpacing: Spacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Chip(
                  key: Key('resort-tier-${resort.propertyId}'),
                  label: Text(plan?.tier.label ?? 'No plan'),
                  backgroundColor: plan == null
                      ? scheme.surfaceContainerHighest
                      : scheme.primaryContainer,
                  side: BorderSide.none,
                ),
                if (plan != null) PlanLine(plan: plan),
              ],
            ),
            const SizedBox(height: Spacing.sm),
            Text(
              '${resort.bookings30d} bookings · ${formatInr(resort.revenue30d)} '
              '(last 30 days)',
            ),
            Text(
              '${resort.bookings365d} bookings · ${formatInr(resort.revenue365d)} '
              '(last 365 days)',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
            if (!archived) ...[
              const SizedBox(height: Spacing.sm),
              Align(
                alignment: Alignment.centerRight,
                child: Wrap(
                  spacing: Spacing.sm,
                  runSpacing: Spacing.xs,
                  alignment: WrapAlignment.end,
                  children: [
                    TextButton(
                      key: Key('resort-plan-btn-${resort.propertyId}'),
                      onPressed: () => _changePlan(context),
                      child: Text(plan == null ? 'Set plan' : 'Change plan'),
                    ),
                    OutlinedButton(
                      key: Key('resort-status-btn-${resort.propertyId}'),
                      onPressed: () => _confirmAndSetStatus(context, ref),
                      child: Text(suspended ? 'Reactivate' : 'Suspend'),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _changePlan(BuildContext context) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => ChangePlanDialog(resort: resort),
    );
    if (saved == true) onChanged();
  }

  Future<void> _confirmAndSetStatus(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final suspending = resort.status != 'suspended';
    final newStatus = suspending ? 'suspended' : 'active';
    final actionLabel = suspending ? 'Suspend' : 'Reactivate';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('$actionLabel ${resort.name}?'),
        content: Text(
          suspending
              ? 'Staff at this resort will no longer be able to make changes. '
                'The guest can still read and cancel their bookings.'
              : 'This resort will be reactivated and staff can work again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(actionLabel),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      await ref
          .read(platformSourceProvider)
          .setStatus(resort.propertyId, newStatus);
      onChanged();
    } on BookingFailure catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(FailureView.messageFor(e))));
      }
    }
  }
}

/// The plan line next to the tier chip. A lapsed plan gets a warning icon
/// and the error colour on top of the word "Lapsed", so the state never
/// depends on colour alone.
class PlanLine extends StatelessWidget {
  const PlanLine({super.key, required this.plan});

  final ResortPlan plan;

  @override
  Widget build(BuildContext context) {
    final text = planStatusLine(plan);
    if (!plan.lapsed) return Text(text);
    final error = Theme.of(context).colorScheme.error;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.warning_amber_rounded, size: 18, color: error),
        const SizedBox(width: Spacing.xs),
        Flexible(child: Text(text, style: TextStyle(color: error))),
      ],
    );
  }
}
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `flutter test test/features/platform/ && flutter analyze`
Expected: all tests PASS (the Task 4 console tests too: the dropdown taps use `.last`, which is the open menu, not the new tier chips). The analyzer shows no issues beyond the Task 1 baseline.

- [ ] **Step 7: Commit**

```bash
git add lib/features/platform/change_plan_dialog.dart lib/features/platform/resort_card.dart \
  test/features/platform/change_plan_dialog_test.dart test/features/platform/resort_card_test.dart
git commit -m "feat(platform): plan line, lapsed warning and Change plan dialog on each resort"
```

---

### Task 6: Add resort with a plan, and plan prices

**Track:** App. **Depends on:** Task 4. Can run alongside Task 5.

**Files:**
- Create: `lib/features/platform/new_resort_dialog.dart` (the dialog moved out of the screen, plus the plan)
- Create: `lib/features/platform/plan_prices_dialog.dart`
- Modify: `lib/features/platform/platform_screen.dart` (whole file)
- Test: `test/features/platform/new_resort_dialog_test.dart`, `test/features/platform/plan_prices_dialog_test.dart`, `test/features/platform/platform_screen_test.dart` (append)

**Interfaces:**
- Consumes: `PlatformSource.createResort(name, ownerEmail, {tier, trialDays})`, `PlatformSource.setPlanPrice`, `subscriptionPlansProvider`, `platformTotalsProvider`, `platformResortsProvider`, `SubscriptionPlan`, `subscriptionTierToDb` (Task 1); `PlatformTotalsRow`, `ResortFilterBar`, `filterResorts`, `ResortCard` (Task 4).
- Produces:
  - `class NewResortDialog extends ConsumerStatefulWidget { const NewResortDialog() }`. Keys: `new-resort-name`, `new-resort-owner-email`, `new-resort-tier`, `new-resort-trial`, `new-resort-trial-days`. The button is `Create`.
  - `class PlanPricesDialog extends ConsumerStatefulWidget { PlanPricesDialog({required List<SubscriptionPlan> plans}) }`. Keys: `plan-price-starter`, `plan-price-pro`, `plan-price-enterprise`, `plan-prices-save`.
  - The screen's floating button becomes `FloatingActionButton.extended` labelled `Add resort` (key `add-resort-fab`), and the app bar gains `Plan prices` (key `plan-prices-btn`).

- [ ] **Step 1: Write the failing Add resort tests**

Create `test/features/platform/new_resort_dialog_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/errors.dart';
import 'package:pasala/data/models/subscription.dart';
import 'package:pasala/data/repositories/platform_repository.dart';
import 'package:pasala/features/platform/new_resort_dialog.dart';

import '../../support/fake_platform_source.dart';

Future<void> _open(WidgetTester tester, FakePlatformSource source) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [platformSourceProvider.overrideWithValue(source)],
    child: MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => const NewResortDialog(),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Future<void> _fillNameAndOwner(WidgetTester tester) async {
  await tester.enterText(find.byKey(const Key('new-resort-name')), 'Resort E');
  await tester.enterText(
      find.byKey(const Key('new-resort-owner-email')), 'owner@x.com');
}

Future<void> _create(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(FilledButton, 'Create'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('by default the resort starts a 30-day Starter trial',
      (tester) async {
    final source = FakePlatformSource();
    await _open(tester, source);

    await _fillNameAndOwner(tester);
    await _create(tester);

    expect(source.createCalls,
        [('Resort E', 'owner@x.com', SubscriptionTier.starter, 30)]);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('a chosen tier and trial length are sent', (tester) async {
    final source = FakePlatformSource();
    await _open(tester, source);

    await _fillNameAndOwner(tester);
    await tester.tap(find.byKey(const Key('new-resort-tier')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pro').last);
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('new-resort-trial-days')), '14');
    await _create(tester);

    expect(source.createCalls,
        [('Resort E', 'owner@x.com', SubscriptionTier.pro, 14)]);
  });

  testWidgets('with the trial switched off the resort starts active',
      (tester) async {
    final source = FakePlatformSource();
    await _open(tester, source);

    await _fillNameAndOwner(tester);
    await tester.tap(find.byKey(const Key('new-resort-trial')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('new-resort-trial-days')), findsNothing);
    await _create(tester);

    expect(source.createCalls,
        [('Resort E', 'owner@x.com', SubscriptionTier.starter, 0)]);
  });

  testWidgets('a trial length outside 1 to 365 days is refused',
      (tester) async {
    final source = FakePlatformSource();
    await _open(tester, source);
    await _fillNameAndOwner(tester);

    for (final days in ['0', '366', 'abc', '']) {
      await tester.enterText(
          find.byKey(const Key('new-resort-trial-days')), days);
      await _create(tester);
      expect(find.text('Enter a trial of 1 to 365 days.'), findsOneWidget,
          reason: 'days "$days"');
    }
    expect(source.createCalls, isEmpty);
  });

  testWidgets('a missing name is refused', (tester) async {
    final source = FakePlatformSource();
    await _open(tester, source);

    await tester.enterText(
        find.byKey(const Key('new-resort-owner-email')), 'owner@x.com');
    await _create(tester);

    expect(find.text('Enter a name and an owner email.'), findsOneWidget);
    expect(source.createCalls, isEmpty);
  });

  testWidgets('a server refusal keeps the dialog open with its message',
      (tester) async {
    final source = FakePlatformSource()
      ..createError = const InvalidState('A trial is 0 to 365 days.');
    await _open(tester, source);

    await _fillNameAndOwner(tester);
    await _create(tester);

    expect(find.text('A trial is 0 to 365 days.'), findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget);
  });
}
```

- [ ] **Step 2: Write the failing Plan prices tests**

Create `test/features/platform/plan_prices_dialog_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/errors.dart';
import 'package:pasala/data/models/subscription.dart';
import 'package:pasala/data/repositories/platform_repository.dart';
import 'package:pasala/features/platform/platform_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_platform_source.dart';

/// Opens Plan prices from the console, the way the admin does.
Future<void> _openFromConsole(
    WidgetTester tester, FakePlatformSource source) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [platformSourceProvider.overrideWithValue(source)],
    child: const MaterialApp(home: PlatformScreen()),
  ));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('plan-prices-btn')));
  await tester.pumpAndSettle();
}

String _field(WidgetTester tester, String key) =>
    tester.widget<TextField>(find.byKey(Key(key))).controller!.text;

Future<void> _save(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('plan-prices-save')));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('shows the current monthly price of each plan', (tester) async {
    final source = FakePlatformSource()..store = [resortSummary()];
    await _openFromConsole(tester, source);

    expect(_field(tester, 'plan-price-starter'), '2999');
    expect(_field(tester, 'plan-price-pro'), '7999');
    expect(_field(tester, 'plan-price-enterprise'), '19999');
  });

  testWidgets('Save sends only the prices that changed and refreshes MRR',
      (tester) async {
    final source = FakePlatformSource()..store = [resortSummary()];
    await _openFromConsole(tester, source);
    expect(source.totalsCalls, 1);

    await tester.enterText(find.byKey(const Key('plan-price-pro')), '8999');
    await _save(tester);

    expect(source.priceCalls, [(SubscriptionTier.pro, 8999)]);
    expect(find.byType(AlertDialog), findsNothing);
    expect(source.totalsCalls, 2);
  });

  testWidgets('a negative or non-numeric price is refused and nothing is saved',
      (tester) async {
    final source = FakePlatformSource()..store = [resortSummary()];
    await _openFromConsole(tester, source);

    for (final price in ['-5', 'abc', '']) {
      await tester.enterText(find.byKey(const Key('plan-price-pro')), price);
      await _save(tester);
      expect(find.text('Enter a monthly price of 0 or more for every plan.'),
          findsOneWidget,
          reason: 'price "$price"');
    }
    expect(source.priceCalls, isEmpty);
  });

  testWidgets('a server refusal shows its message and keeps the dialog',
      (tester) async {
    final source = FakePlatformSource()
      ..store = [resortSummary()]
      ..priceError =
          const InvalidState('Enter a monthly price from 0 to 1,00,00,000.');
    await _openFromConsole(tester, source);

    await tester.enterText(
        find.byKey(const Key('plan-price-starter')), '99999999');
    await _save(tester);

    expect(find.text('Enter a monthly price from 0 to 1,00,00,000.'),
        findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget);
  });
}
```

- [ ] **Step 3: Write the failing console tests for the new button**

Append to the end of `main()` in `test/features/platform/platform_screen_test.dart`:

```dart
  group('adding a resort', () {
    testWidgets('the add button is labelled Add resort', (tester) async {
      final repo = FakePlatformSource()..store = [_resortA];
      await tester.pumpWidget(_appFor(repo));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('add-resort-fab')), findsOneWidget);
      expect(find.widgetWithText(FloatingActionButton, 'Add resort'),
          findsOneWidget);
    });

    testWidgets('a new resort refreshes the list and the cards',
        (tester) async {
      final repo = FakePlatformSource()..store = [_resortA];
      await tester.pumpWidget(_appFor(repo));
      await tester.pumpAndSettle();
      expect(repo.totalsCalls, 1);

      await tester.tap(find.byKey(const Key('add-resort-fab')));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const Key('new-resort-name')), 'Resort E');
      await tester.enterText(
          find.byKey(const Key('new-resort-owner-email')), 'owner@x.com');
      await tester.tap(find.widgetWithText(FilledButton, 'Create'));
      await tester.pumpAndSettle();

      expect(find.text('Resort E'), findsOneWidget);
      expect(repo.totalsCalls, 2);
    });
  });
```

- [ ] **Step 4: Run them to verify they fail**

Run: `flutter test test/features/platform/new_resort_dialog_test.dart test/features/platform/plan_prices_dialog_test.dart test/features/platform/platform_screen_test.dart`
Expected: FAIL to compile with "Target of URI doesn't exist: 'package:pasala/features/platform/new_resort_dialog.dart'".

- [ ] **Step 5: Write the Add resort dialog**

Create `lib/features/platform/new_resort_dialog.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../core/theme/spacing.dart';
import '../../core/widgets/failure_view.dart';
import '../../data/models/subscription.dart';
import '../../data/repositories/platform_repository.dart';

/// "+ Add resort" (REQ-08): a name, an owner email -- which must belong to
/// an existing account (no in-app account creation; see the tenancy design
/// spec) -- and the plan it starts on: a tier (default Starter) and a
/// trial (default on, 30 days, 1 to 365). With the trial off the resort
/// starts active with no end date.
class NewResortDialog extends ConsumerStatefulWidget {
  const NewResortDialog({super.key});

  @override
  ConsumerState<NewResortDialog> createState() => _NewResortDialogState();
}

class _NewResortDialogState extends ConsumerState<NewResortDialog> {
  final _name = TextEditingController();
  final _ownerEmail = TextEditingController();
  final _trialDays = TextEditingController(text: '30');
  SubscriptionTier _tier = SubscriptionTier.starter;
  bool _trial = true;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _ownerEmail.dispose();
    _trialDays.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _name.text.trim();
    final ownerEmail = _ownerEmail.text.trim();
    if (name.isEmpty || ownerEmail.isEmpty) {
      setState(() => _error = 'Enter a name and an owner email.');
      return;
    }
    var trialDays = 0;
    if (_trial) {
      final days = int.tryParse(_trialDays.text.trim());
      if (days == null || days < 1 || days > 365) {
        setState(() => _error = 'Enter a trial of 1 to 365 days.');
        return;
      }
      trialDays = days;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(platformSourceProvider)
          .createResort(name, ownerEmail, tier: _tier, trialDays: trialDays);
      if (!mounted) return;
      ref.invalidate(platformResortsProvider);
      ref.invalidate(platformTotalsProvider);
      Navigator.of(context).pop();
    } on BookingFailure catch (e) {
      if (mounted) setState(() => _error = FailureView.messageFor(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Add resort'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const Key('new-resort-name'),
                controller: _name,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              const SizedBox(height: Spacing.sm),
              TextField(
                key: const Key('new-resort-owner-email'),
                controller: _ownerEmail,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Owner email',
                  helperText: 'Must belong to an existing account',
                ),
              ),
              const SizedBox(height: Spacing.sm),
              DropdownButtonFormField<SubscriptionTier>(
                key: const Key('new-resort-tier'),
                initialValue: _tier,
                decoration: const InputDecoration(labelText: 'Plan'),
                items: [
                  for (final t in SubscriptionTier.values)
                    DropdownMenuItem(value: t, child: Text(t.label)),
                ],
                onChanged: (t) {
                  if (t != null) setState(() => _tier = t);
                },
              ),
              SwitchListTile(
                key: const Key('new-resort-trial'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Start with a trial'),
                value: _trial,
                onChanged: (on) => setState(() => _trial = on),
              ),
              if (_trial)
                TextField(
                  key: const Key('new-resort-trial-days'),
                  controller: _trialDays,
                  keyboardType: TextInputType.number,
                  decoration:
                      const InputDecoration(labelText: 'Trial length (days)'),
                ),
              if (_error != null) ...[
                const SizedBox(height: Spacing.sm),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: _busy ? null : _create,
            child: const Text('Create'),
          ),
        ],
      );
}
```

- [ ] **Step 6: Write the Plan prices dialog**

Create `lib/features/platform/plan_prices_dialog.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../core/theme/spacing.dart';
import '../../core/widgets/failure_view.dart';
import '../../data/models/subscription.dart';
import '../../data/repositories/platform_repository.dart';

/// "Plan prices" (spec decision 11): the monthly INR price of each plan.
/// Save sends only the prices that changed, through `set_plan_price`. A
/// change applies to every resort on that plan at once, so the list, the
/// cards (MRR) and the plans are refetched -- even after a partial failure,
/// because the prices saved before it are real.
class PlanPricesDialog extends ConsumerStatefulWidget {
  const PlanPricesDialog({super.key, required this.plans});

  final List<SubscriptionPlan> plans;

  @override
  ConsumerState<PlanPricesDialog> createState() => _PlanPricesDialogState();
}

class _PlanPricesDialogState extends ConsumerState<PlanPricesDialog> {
  late final Map<SubscriptionTier, TextEditingController> _prices = {
    for (final plan in widget.plans)
      plan.tier: TextEditingController(text: _show(plan.monthlyPriceInr)),
  };
  String? _error;
  bool _busy = false;

  static String _show(num price) =>
      price % 1 == 0 ? price.toStringAsFixed(0) : price.toStringAsFixed(2);

  @override
  void dispose() {
    for (final c in _prices.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final changes = <SubscriptionTier, num>{};
    for (final plan in widget.plans) {
      final text = _prices[plan.tier]!.text.trim().replaceAll(',', '');
      final value = num.tryParse(text);
      if (value == null || value < 0) {
        setState(() =>
            _error = 'Enter a monthly price of 0 or more for every plan.');
        return;
      }
      if (value != plan.monthlyPriceInr) changes[plan.tier] = value;
    }
    if (changes.isEmpty) {
      Navigator.of(context).pop();
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    BookingFailure? failure;
    try {
      for (final change in changes.entries) {
        await ref
            .read(platformSourceProvider)
            .setPlanPrice(change.key, change.value);
      }
    } on BookingFailure catch (e) {
      failure = e;
    }
    if (!mounted) return;
    ref.invalidate(subscriptionPlansProvider);
    ref.invalidate(platformTotalsProvider);
    ref.invalidate(platformResortsProvider);
    if (failure == null) {
      Navigator.of(context).pop();
    } else {
      setState(() {
        _busy = false;
        _error = FailureView.messageFor(failure!);
      });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Plan prices (per month)'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final plan in widget.plans)
                Padding(
                  padding: const EdgeInsets.only(bottom: Spacing.sm),
                  child: TextField(
                    key: Key('plan-price-${subscriptionTierToDb(plan.tier)}'),
                    controller: _prices[plan.tier],
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: plan.name,
                      prefixText: '₹ ',
                    ),
                  ),
                ),
              Text(
                'A change applies to every resort on that plan, and to MRR, '
                'straight away.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (_error != null) ...[
                const SizedBox(height: Spacing.sm),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('plan-prices-save'),
            onPressed: _busy ? null : _save,
            child: const Text('Save'),
          ),
        ],
      );
}
```

- [ ] **Step 7: Wire both into the console**

Replace the whole of `lib/features/platform/platform_screen.dart` with (the `_NewResortDialog` class is gone; it now lives in `new_resort_dialog.dart`):

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors.dart';
import '../../core/theme/spacing.dart';
import '../../core/theme/theme_toggle_button.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/failure_view.dart';
import '../../data/models/subscription.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/platform_repository.dart';
import 'new_resort_dialog.dart';
import 'plan_prices_dialog.dart';
import 'platform_totals_row.dart';
import 'resort_card.dart';
import 'resort_filter.dart';

/// `/platform` -- the platform admin's SaaS console (REQ-08): the
/// Subscribed / Active / MRR cards, a live search and a tier filter over
/// every resort, per resort its status, owners, plan, booking summary and
/// actions, "Add resort", and the plan prices. The platform admin has no
/// membership at any resort and no row access to any resort-owned table
/// (see the tenancy design spec), so this screen reads and writes only
/// through [PlatformSource].
///
/// Sits outside `AppShell`'s `ShellRoute` -- like `/choose-resort` -- since
/// its nav destinations are keyed off a current resort the platform admin
/// never has, so it carries its own sign-out action instead.
class PlatformScreen extends ConsumerStatefulWidget {
  const PlatformScreen({super.key});

  @override
  ConsumerState<PlatformScreen> createState() => _PlatformScreenState();
}

class _PlatformScreenState extends ConsumerState<PlatformScreen> {
  final _search = TextEditingController();
  SubscriptionTier? _tier;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// After any change the list and the cards both move.
  void _refresh() {
    ref.invalidate(platformResortsProvider);
    ref.invalidate(platformTotalsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final resortsAsync = ref.watch(platformResortsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Platform'),
        actions: [
          IconButton(
            key: const Key('plan-prices-btn'),
            tooltip: 'Plan prices',
            icon: const Icon(Icons.sell_outlined),
            onPressed: _openPlanPrices,
          ),
          const ThemeToggleButton(),
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: _signOut,
          ),
        ],
      ),
      body: AsyncView(
        value: resortsAsync,
        onRetry: _refresh,
        empty: () => const EmptyState(
          icon: Icons.apartment_outlined,
          title: 'No resorts yet',
          message: 'Tap Add resort to create the first one.',
        ),
        data: (resorts) {
          final shown =
              filterResorts(resorts, query: _search.text, tier: _tier);
          return ListView(
            // Room at the bottom so the extended button never covers the
            // last card's actions.
            padding: const EdgeInsets.fromLTRB(
                Spacing.md, Spacing.md, Spacing.md, Spacing.xxl + Spacing.xl),
            children: [
              const PlatformTotalsRow(),
              const SizedBox(height: Spacing.md),
              ResortFilterBar(
                search: _search,
                tier: _tier,
                onSearchChanged: (_) => setState(() {}),
                onTierChanged: (tier) => setState(() => _tier = tier),
              ),
              const SizedBox(height: Spacing.md),
              if (shown.isEmpty)
                const Padding(
                  key: Key('no-matching-resorts'),
                  padding: EdgeInsets.all(Spacing.lg),
                  child: Text(
                    'No resorts match your search.',
                    textAlign: TextAlign.center,
                  ),
                )
              else
                for (final resort in shown) ...[
                  ResortCard(resort: resort, onChanged: _refresh),
                  const SizedBox(height: Spacing.sm),
                ],
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('add-resort-fab'),
        onPressed: () => showDialog<void>(
          context: context,
          builder: (_) => const NewResortDialog(),
        ),
        icon: const Icon(Icons.add),
        label: const Text('Add resort'),
      ),
    );
  }

  Future<void> _openPlanPrices() async {
    try {
      final plans = await ref.read(subscriptionPlansProvider.future);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => PlanPricesDialog(plans: plans),
      );
    } on BookingFailure catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(FailureView.messageFor(e))));
      }
    }
  }

  Future<void> _signOut() async {
    try {
      await ref.read(authRepositoryProvider).signOut();
      if (mounted) context.go('/login');
    } on BookingFailure catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(FailureView.messageFor(e))));
      }
    }
  }
}
```

- [ ] **Step 8: Run the tests to verify they pass**

Run: `flutter test test/features/platform/ && flutter analyze`
Expected: all tests PASS, including the older `creating a resort calls createResort and refreshes the list` (it finds the extended button by type and still sees `('Resort E', 'owner@x.com', SubscriptionTier.starter, 30)`). The analyzer shows no issues beyond the Task 1 baseline.

- [ ] **Step 9: Commit**

```bash
git add lib/features/platform/new_resort_dialog.dart lib/features/platform/plan_prices_dialog.dart \
  lib/features/platform/platform_screen.dart test/features/platform/new_resort_dialog_test.dart \
  test/features/platform/plan_prices_dialog_test.dart test/features/platform/platform_screen_test.dart
git commit -m "feat(platform): Add resort on a tier with an optional trial, and editable plan prices"
```

---

### Task 7: The owner's plan in Settings

**Track:** App. **Depends on:** Task 1. Can run alongside Tasks 4–6 and 8.

**Files:**
- Modify: `lib/features/owner/owner_settings_screen.dart` (imports; the top of the `ListView`; a new `_PlanTile` class)
- Test: `test/features/owner/owner_settings_screen_test.dart` (create)

**Interfaces:**
- Consumes: `resortPlanProvider` and `resortPlanSourceProvider` (keyed by property id), `planStatusLine`, `ResortPlan`, `FakeResortPlanSource`, `resortPlan` (Task 1); `currentResortProvider`, `propertyProvider`.
- Produces: a read-only Plan card at the top of `/owner/settings` (key `owner-plan-tile`), with no tap action.

- [ ] **Step 1: Write the failing tests**

Create `test/features/owner/owner_settings_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/current_resort.dart';
import 'package:pasala/core/errors.dart';
import 'package:pasala/data/models/property.dart';
import 'package:pasala/data/models/resort_membership.dart';
import 'package:pasala/data/models/subscription.dart';
import 'package:pasala/data/repositories/subscription_repository.dart';
import 'package:pasala/features/browse/providers.dart';
import 'package:pasala/features/owner/owner_settings_screen.dart';

import '../../support/fake_platform_source.dart';
import '../../support/fake_resort_plan_source.dart';

const _resort = ResortMembership(
    propertyId: 'p1', resortName: 'Pasala Farm House', role: ResortRole.owner);

const _property = Property(
  id: 'p1',
  name: 'Pasala Farm House',
  slug: 'pasala-farm-house',
  description: null,
  address: null,
  images: [],
  amenities: [],
  checkInTime: '14:00',
  checkOutTime: '11:00',
  isActive: true,
);

/// Pins the current resort, mirroring `_FixedResort` in
/// `team_screen_test.dart`.
class _FixedResort extends CurrentResort {
  _FixedResort(this._value);
  final ResortMembership? _value;
  @override
  ResortMembership? build() => _value;
}

Future<void> _pump(WidgetTester tester, FakeResortPlanSource source) async {
  await tester.pumpWidget(ProviderScope(
    // retry: null -- without it Riverpod 3 keeps retrying a failed
    // provider and the error state never settles.
    retry: (_, _) => null,
    overrides: [
      currentResortProvider.overrideWith(() => _FixedResort(_resort)),
      propertyProvider.overrideWith((ref, id) async => _property),
      resortPlanSourceProvider.overrideWithValue(source),
    ],
    child: const MaterialApp(home: OwnerSettingsScreen()),
  ));
  await tester.pumpAndSettle();
}

Finder _inPlanTile(String text) => find.descendant(
    of: find.byKey(const Key('owner-plan-tile')), matching: find.text(text));

void main() {
  testWidgets("shows the current resort's plan, read-only", (tester) async {
    final source = FakeResortPlanSource()
      ..plan = resortPlan(
          tier: SubscriptionTier.pro, paidThrough: DateTime(2026, 10, 31));
    await _pump(tester, source);

    expect(_inPlanTile('Plan: Pro'), findsOneWidget);
    expect(_inPlanTile('Paid until 31 Oct 2026'), findsOneWidget);
    expect(source.calls, ['p1']);
    final tile = tester.widget<ListTile>(find.descendant(
        of: find.byKey(const Key('owner-plan-tile')),
        matching: find.byType(ListTile)));
    expect(tile.onTap, isNull);
  });

  testWidgets('a lapsed trial says so', (tester) async {
    final source = FakeResortPlanSource()
      ..plan = resortPlan(
          tier: SubscriptionTier.starter,
          status: SubscriptionStatus.trial,
          trialEndsOn: DateTime(2026, 9, 24),
          lapsed: true);
    await _pump(tester, source);

    expect(_inPlanTile('Plan: Starter'), findsOneWidget);
    expect(_inPlanTile('Lapsed: trial ended 24 Sep 2026'), findsOneWidget);
  });

  testWidgets('a resort with no plan says it is not set up', (tester) async {
    await _pump(tester, FakeResortPlanSource());

    expect(_inPlanTile('Plan: not set up'), findsOneWidget);
    expect(_inPlanTile('Contact ResortHub to choose a plan'), findsOneWidget);
  });

  testWidgets('a plan that fails to load does not break Settings',
      (tester) async {
    final source = FakeResortPlanSource()..error = const NetworkFailure();
    await _pump(tester, source);

    expect(_inPlanTile('Could not load your plan'), findsOneWidget);
    expect(find.text('Farmhouse information'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `flutter test test/features/owner/owner_settings_screen_test.dart`
Expected: FAIL: `find.byKey(const Key('owner-plan-tile'))` finds nothing, so the `Plan: ...` expectations fail.

- [ ] **Step 3: Add the Plan tile**

In `lib/features/owner/owner_settings_screen.dart`, add these imports after `import '../../core/widgets/async_view.dart';`:

```dart
import '../../data/models/subscription.dart';
import '../../data/repositories/subscription_repository.dart';
```

Replace:

```dart
            children: [
              eyebrow('PROPERTY'),
```

with:

```dart
            children: [
              eyebrow('PLAN'),
              _PlanTile(propertyId: propertyId),
              const SizedBox(height: Spacing.md),
              eyebrow('PROPERTY'),
```

Then add this class at the end of the file:

```dart
/// The resort's ResortHub plan, read-only (spec decision 8): only the
/// platform admin changes it. Watches its own provider, so a failure here
/// never hides the rest of Settings.
class _PlanTile extends ConsumerWidget {
  const _PlanTile({required this.propertyId});

  final String propertyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final (title, subtitle, lapsed) =
        switch (ref.watch(resortPlanProvider(propertyId))) {
      AsyncData(value: final plan?) =>
        ('Plan: ${plan.name}', planStatusLine(plan), plan.lapsed),
      AsyncData() =>
        ('Plan: not set up', 'Contact ResortHub to choose a plan', false),
      AsyncError() => ('Plan', 'Could not load your plan', false),
      _ => ('Plan', 'Loading…', false),
    };

    return Card(
      key: const Key('owner-plan-tile'),
      margin: const EdgeInsets.only(bottom: Spacing.sm),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: scheme.secondary.withValues(alpha: 0.12),
          child: Icon(Icons.workspace_premium_outlined, color: scheme.secondary),
        ),
        title: Text(title),
        subtitle: Text(
          subtitle,
          style: lapsed ? TextStyle(color: scheme.error) : null,
        ),
      ),
    );
  }
}
```

Also add one line to the class comment of `OwnerSettingsScreen`, after its first sentence: `The Plan tile at the top shows the resort's ResortHub plan, read-only.`

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/features/owner/ && flutter analyze`
Expected: all tests PASS. The analyzer shows no issues beyond the Task 1 baseline.

- [ ] **Step 5: Commit**

```bash
git add lib/features/owner/owner_settings_screen.dart test/features/owner/owner_settings_screen_test.dart
git commit -m "feat(owner): show the resort's plan, read-only, in Settings"
```

---

### Task 8: ResortHub on the login and sign-up cards

**Track:** App. **Depends on:** nothing (it touches no subscription code). Can run alongside every other task.

**Files:**
- Modify: `lib/features/auth/login_screen.dart:10` (import) and `:87-93` (heading)
- Modify: `lib/features/auth/signup_screen.dart:10` (import) and `:91-97` (heading)
- Test: `test/features/auth/login_screen_test.dart`, `test/features/auth/signup_screen_test.dart`

**Interfaces:**
- Consumes: nothing new.
- Produces: both cards show the heading `ResortHub` (the same `headlineMedium` style the welcome screen uses) and no `BrandMark`. The subtitles `Welcome back` and `Create your account` stay.

- [ ] **Step 1: Write the failing tests**

In `test/features/auth/login_screen_test.dart`, replace:

```dart
  testWidgets('shows the brand mark above the heading', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));

    expect(find.byType(BrandMark), findsOneWidget);
  });
```

with:

```dart
  testWidgets('shows the ResortHub name, not the Pasala logo or name',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));

    expect(find.text('ResortHub'), findsOneWidget);
    expect(find.text('Pasala Resorts'), findsNothing);
    expect(find.byType(BrandMark), findsNothing);
  });
```

In `test/features/auth/signup_screen_test.dart`, replace:

```dart
  testWidgets('shows the brand mark above the heading', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SignupScreen()));

    expect(find.byType(BrandMark), findsOneWidget);
  });
```

with:

```dart
  testWidgets('shows the ResortHub name, not the Pasala logo or name',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SignupScreen()));

    expect(find.text('ResortHub'), findsOneWidget);
    expect(find.text('Pasala Resorts'), findsNothing);
    expect(find.byType(BrandMark), findsNothing);
  });
```

- [ ] **Step 2: Run them to verify they fail**

Run: `flutter test test/features/auth/login_screen_test.dart test/features/auth/signup_screen_test.dart`
Expected: FAIL in both new tests: `Expected: exactly one matching candidate` for `find.text('ResortHub')` (found zero).

- [ ] **Step 3: Rebrand the login card**

In `lib/features/auth/login_screen.dart`, delete the line:

```dart
import '../../core/widgets/brand_mark.dart';
```

and replace:

```dart
                          const BrandMark(
                            size: BrandMarkSize.splash,
                            showWordmark: false,
                          ),
                          const SizedBox(height: Spacing.md),
                          Text(
                            'Pasala Resorts',
```

with:

```dart
                          Text(
                            'ResortHub',
```

- [ ] **Step 4: Rebrand the sign-up card**

Make the same two changes in `lib/features/auth/signup_screen.dart`: delete `import '../../core/widgets/brand_mark.dart';`, and replace the `BrandMark(...)`, its `SizedBox(height: Spacing.md)` and `'Pasala Resorts',` with `Text(` / `'ResortHub',` exactly as in Step 3.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `flutter test test/features/auth/ && flutter analyze`
Expected: all tests PASS (the welcome screen's tests are unchanged). The analyzer shows no issues beyond the Task 1 baseline; in particular no "unused import" for `brand_mark.dart`, which the app shell and splash still use.

- [ ] **Step 6: Commit**

```bash
git add lib/features/auth/login_screen.dart lib/features/auth/signup_screen.dart \
  test/features/auth/login_screen_test.dart test/features/auth/signup_screen_test.dart
git commit -m "feat(auth): ResortHub heading on the login and sign-up cards"
```

---

## Phase 3: Integration

### Task 9: Merge the tracks and verify end to end

**Track:** both. **Depends on:** Tasks 2–8.

**Files:**
- None created. This task only verifies; a fix belongs to the task that owns the file, and gets its own commit.

**Interfaces:**
- Consumes: everything above.
- Produces: a branch where the database and the app agree on names and shapes, with both suites green.

- [ ] **Step 1: Merge**

If the tracks ran in separate worktrees, merge the database branch and the app branch into the feature branch. The tracks own disjoint files, so no conflicts are expected. If one appears in `37_tenancy_isolation_test.sql` (B or C also added allow-list lines there), keep every side's lines.

- [ ] **Step 2: Check the contract by name**

Run: `grep -n "rpc('\|'p_[a-z_]*'\|from('subscription_plans')" lib/data/repositories/platform_repository.dart lib/data/repositories/subscription_repository.dart`
Expected: the RPC names `platform_resorts`, `platform_summary`, `set_resort_status`, `create_resort`, `set_resort_subscription`, `set_plan_price` and `my_resort_subscription`, the parameter names `p_property`, `p_status`, `p_name`, `p_owner_email`, `p_tier`, `p_trial_days`, `p_trial_ends_on`, `p_paid_through`, `p_notes` and `p_monthly_price_inr`, and the direct read of `subscription_plans`. Each must match a signature in `0049_subscriptions.sql` (or `0045` for `set_resort_status`); list them with `grep -n "create function public\.\(platform_resorts\|platform_summary\|my_resort_subscription\|create_resort\|set_resort_subscription\|set_plan_price\)" -A7 supabase/migrations/0049_subscriptions.sql`. The JSON keys read by `ResortPlan.fromRow`, `PlatformTotals.fromJson` and `SubscriptionPlan.fromJson` must equal the OUT columns pinned in 41's contract section.

- [ ] **Step 3: Run the full suites**

Run: `supabase db reset && supabase test db`, then `flutter test`, then `flutter analyze`
Expected:
- pgTAP: 41 at 62/62, 38 at 54/54, 37 passing, and every other file as in the Task 1 Step 1 baseline.
- Flutter: all tests pass, with the count equal to the baseline plus the tests this plan added (the two replaced auth tests count as zero added).
- Analyzer: no issues beyond the baseline.

- [ ] **Step 4: Manual smoke test against the local stack**

The seed has no platform admin. Make one for the smoke test: `psql "$(supabase status -o env | grep DB_URL | cut -d= -f2 | tr -d '"')" -c "update public.profiles set role = 'platform_admin' where id = '10000000-0000-0000-0000-000000000006';"` (Meera, a customer with no membership). Then run `make run-web` and confirm:
1. The login and sign-up cards say ResortHub, with no Pasala logo.
2. Sign in as `meera@example.com` / `password123`: `/platform` shows Subscribed resorts 1, Active subscriptions 1 (incl. 0 trials) and MRR ₹19,999, and Pasala Farm House has an Enterprise chip and "Paid, no end date".
3. Add resort "Test Stay" for `ravi@example.com` with the default trial: the list shows it with a Starter chip and "Trial until <today + 30>", Subscribed is 2, Active is 2 (incl. 1 trial) and MRR is unchanged.
4. Type "test" in the search: only Test Stay shows. Choose Enterprise in the tier filter with the search cleared: only Pasala Farm House shows.
5. Change plan on Test Stay to Pro, Active, paid until yesterday: the card shows the warning icon and "Lapsed: paid until <yesterday>", and Active drops to 1.
6. Plan prices: set Enterprise to 20999; MRR becomes ₹20,999.
7. Sign in as `super@pasala.test` (the seeded owner): Settings shows "Plan: Enterprise" and "Paid, no end date", and the tile does nothing when tapped.
Afterwards, `supabase db reset` restores the seed (Meera is a customer again).

- [ ] **Step 5: Commit any fixes**

For each fix, run `git add <the fixed files>` and then `git commit -m "fix(subscriptions): <what was wrong>"`. If nothing needed fixing, there is nothing to commit.

---

## Self-Review

**1. Spec coverage**

| Spec requirement | Task |
|---|---|
| Enums `subscription_tier` / `subscription_status`, no free tier, lapsed never stored | 1 |
| `subscription_plans` seeded at 2999 / 7999 / 19999, read by any signed-in user, no write grant | 1 |
| `resort_subscriptions` (cascade, trial-needs-end check, owner/admin read policy, no write grants) | 1 |
| Backfill of existing resorts to Enterprise / active / no end date | 1 (statement), 2 (seed row, manual check) |
| `subscription_lapsed`: good through the end date, Asia/Kolkata | 2 |
| `platform_resorts` plan columns, "No plan" as nulls | 1 (signature), 2 |
| `platform_summary`: subscribed / active / trials / MRR, archived and plan-less excluded | 1 (signature), 2 |
| `my_resort_subscription`: owner/admin, suspended resort readable, P0020 otherwise | 1 (signature), 2 |
| `create_resort` with tier and trial days, two-argument version dropped, P0005, audit | 1 (signature), 3 |
| `set_resort_subscription`: upsert, date kept per status, blank notes null, P0005/P0002, lock, audit | 1 (signature), 3 |
| `set_plan_price`: P0005 bounds, platform audit row, MRR follows | 1 (signature), 3 |
| P0008 for everyone but the platform admin | 2, 3 |
| Definer allow-list; 38 updated | 1 |
| Dart models, `planStatusLine`, `dateToDb` | 1 |
| `PlatformSource` additions and providers; `ResortPlanSource` and `resortPlanProvider` keyed by property id | 1 |
| Console: three cards, wrap on a phone, platform-wide | 4 |
| Console: search on name and owner email; tier dropdown All tiers / Starter / Pro / Enterprise | 4 |
| Console: tier chip, plan line, Lapsed with icon and error colour | 5 |
| Console: Change plan / Set plan dialog; none on archived resorts | 5 |
| Console: labelled Add resort with tier and trial (30, 1–365) | 6 |
| Console: Plan prices | 6 |
| Console: refetch list, cards and prices after every change | 4, 5, 6 |
| Owner Settings Plan tile (plan, not set up, error) | 7 |
| Login and sign-up rebrand | 8 |
| pgTAP list in the spec's Testing section | 1–3 |
| Flutter list in the spec's Testing section | 1, 4–8 |

**2. Placeholder scan:** no "TBD", "TODO" or "similar to Task N". Every code step shows its code, and every SQL test uses literal ids. Task 8 Step 4 repeats Step 3's edit on the second file with the exact text to remove and add.

**3. Type consistency:**
- `createResort(String, String, {SubscriptionTier tier = SubscriptionTier.starter, int trialDays = 30})` is the same in `PlatformSource`, `PlatformRepository`, `FakePlatformSource` and `NewResortDialog`; the fake logs `(String, String, SubscriptionTier, int)`, which the Task 1, 4 and 6 tests compare against.
- `setSubscription(String, {required tier, required status, DateTime? trialEndsOn, DateTime? paidThrough, String? notes})` matches the `SubscriptionCall` record the Task 5 tests build.
- `setPlanPrice(SubscriptionTier, num)` matches `priceCalls` as `(SubscriptionTier, num)`.
- The OUT columns pinned in 41 (`plan_tier ... plan_notes`, `subscribed_count ... mrr_inr`) are the keys `ResortPlan.fromRow` and `PlatformTotals.fromJson` read, and 38 pins the same `platform_resorts` list.
- `resortPlanProvider` is `FutureProvider.autoDispose.family<ResortPlan?, String>` in the repository, its test and the owner tile.
- Widget keys used by tests (`total-*`, `resort-search`, `tier-filter`, `resort-tier-<id>`, `resort-plan-btn-<id>`, `plan-*`, `new-resort-*`, `add-resort-fab`, `plan-prices-btn`, `plan-price-<tier>`, `plan-prices-save`, `owner-plan-tile`) are each set in exactly one widget.

**4. Review Focus:** each of the five lines has a test in its owning task: 1 in Task 2, 2 in Tasks 1, 2, 3 and 5, 3 in Tasks 3 and 5, 4 in Task 4, 5 in Task 7. Inputs the spec implies that are already covered elsewhere:
- Trial days of 0, 366, text or blank: Task 6 (dialog) and Task 3 (server).
- A negative, non-numeric or oversized price: Task 6 (dialog) and Task 3 (server).
- Blank notes: Task 5 (dialog sends null) and Task 3 (server stores null).
- An archived resort: Task 2 (not counted) and Task 5 (no actions).
