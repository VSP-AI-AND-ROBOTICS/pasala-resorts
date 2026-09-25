# Subscription Auto-Billing (P8) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a resort owner pay their ResortHub plan by Razorpay auto-pay. The owner starts, changes or cancels it from Settings. Razorpay's webhooks move `paid_through` forward on every charge and record an invoice. The platform console shows each resort's auto-pay state and last payment. Without Razorpay secrets, everything stays manual exactly as today.

**Architecture:**
- **Database.** A new migration adds `subscription_plans.razorpay_plan_id` and two owner-readable tables: `billing_subscriptions` (every Razorpay subscription created for a resort, one of them current) and `subscription_invoices` (one row per charge). They are written only by three `service_role` definer functions. Four client-callable definer functions cover the reads and the platform admin's plan ids.
- **Edge Functions.** Two Deno functions:
  - `billing-subscribe` reads the owner's state as the owner, talks to the Razorpay Subscriptions API, and records the result as the service role.
  - `billing-webhook` verifies Razorpay's signature and hands each `subscription.*` event to one SQL function, which holds all the plan rules.
- **App.** A `BillingSource` seam backs an owner card and sheet under the existing Plan tile. `PlatformSource` gains the console's billing read and the plan id write.

**Tech Stack:**
- Supabase Postgres 15 (plpgsql, RLS, pgTAP via `supabase test db`)
- Supabase Edge Functions on Deno 2.9 (`deno test`)
- Flutter 3.44 / Dart 3.10, Riverpod 3.3, `url_launcher` 6

**Spec:** `docs/superpowers/specs/2026-09-25-p8-subscription-auto-billing-design.md`

## Global Constraints

- **One migration**, `supabase/migrations/0057_subscription_billing.sql`. Tasks 1–4 each edit it.
  - After every edit, rebuild with `supabase db reset`, which re-runs every migration and `supabase/seed.sql`. Then run pgTAP.
  - Before the first reset, dump local data if you need it: `mkdir -p ../pasala-db-backups && supabase db dump --local --data-only -f ../pasala-db-backups/local-before-p8.sql`.
  - Other gap projects add 0051–0056 and 0058–0060. 0057 touches none of their objects, so it applies whether or not they have landed.
- **One pgTAP file**, `supabase/tests/47_subscription_billing_test.sql`. Tasks 1–4 build it up section by section, and each section relies on the state the earlier ones leave.
  - Run one file with `supabase test db supabase/tests/47_subscription_billing_test.sql`.
  - Run the whole suite with `supabase test db`.
  - 3 pgTAP failures are known and appear only 00:00–05:30 IST (files 25/9, 26/3, 34/2). Everything else must pass.
- **One new error code**, **P0038 `billing_unavailable`**, raised as `raise exception using errcode = 'P0038', message = 'billing_unavailable'`. The existing codes keep their meaning:
  - P0002 not found (`not_found`)
  - P0005 bad input, with a message written for the admin and shown verbatim
  - P0008 not the platform admin
  - P0020 not the resort's owner (from `assert_resort_role`)
  - P0021 resort mismatch
- **No existing SQL function is changed.** `platform_resorts`, `my_resort_subscription`, `set_resort_subscription` and the rest of 0049 stay as they are.
- **Every new function** is `security definer` with `set search_path = public, pg_temp`, and is revoked from `public` and `anon`.
  - The four client functions are granted to `authenticated`: `set_plan_razorpay_id`, `my_resort_billing`, `platform_billing` and `billing_subscribe_state`.
  - The three service functions are **also revoked from `authenticated`** and granted to `service_role`: `billing_subscription_opened`, `billing_subscription_cancel_requested` and `billing_webhook_apply`.
  - All seven go on the definer allow-list in `supabase/tests/37_tenancy_isolation_test.sql`.
- **Access.** Owner-only for billing reads and for starting auto-pay: `assert_resort_role(p_property, false, 'owner')` or `has_resort_role(property_id, false, 'owner')`. It runs in read mode, so a suspended resort's owner can still pay. The platform admin gets no row access to the new tables.
- **"Today"** is `(now() at time zone 'Asia/Kolkata')::date`. A plan is good **through** its `paid_through` date, and lapses the day after (0049).
- **pgTAP conventions:**
  - Switch users with `set local role authenticated; set local request.jwt.claims to '{"sub":"<uuid>","role":"authenticated"}';`.
  - Act as the Edge Functions with `set local role service_role;`.
  - `reset role` does **not** clear the claims, so follow it with `set local request.jwt.claims to '';`.
  - Read the new tables directly only after `reset role`. `supabase/config.toml` leaves `auto_expose_new_tables` unset, so `service_role` has no table grants on new tables. It reaches them only through the definer functions.
- **Secrets** live only in Edge Function secrets. They never go in the Flutter app, the database or git.
  - Names: `RAZORPAY_KEY_ID`, `RAZORPAY_KEY_SECRET`, and `RAZORPAY_BILLING_WEBHOOK_SECRET` (falling back to `RAZORPAY_WEBHOOK_SECRET`).
  - The runtime provides `SUPABASE_URL`, `SUPABASE_ANON_KEY` and `SUPABASE_SERVICE_ROLE_KEY`.
  - Integration fixtures use obviously fake values in a file outside the repo.
- **Razorpay:**
  - API base `https://api.razorpay.com/v1`, with HTTP Basic `key_id:key_secret`.
  - Create is `POST /subscriptions` with `plan_id`, `total_count: 60`, `quantity: 1`, `customer_notify: 1`, `notes {property_id, tier}`, `start_at` (unix seconds, only when set) and `notify_info {notify_email}` (only when known).
  - Cancel is `POST /subscriptions/:id/cancel` with `cancel_at_cycle_end: 1|0`.
  - Ids look like `plan_…`, `sub_…` and `pay_…`. Payment amounts are in paise.
  - The webhook signature is the hex HMAC-SHA256 of the raw body, in `X-Razorpay-Signature`.
- **Deno:**
  - Each function directory has a `deno.json` of `{"lock": false}`, and there are no import maps. Imports use full specifiers: `jsr:@std/assert@1` in tests, `npm:@supabase/supabase-js@2` in `db.ts`.
  - Tests import only `handler.ts` and `_shared/billing/*` modules, never `index.ts` or `db.ts`, so they need no environment and no network beyond the first `jsr:` download.
  - Run all of them with `deno test supabase/functions/_shared/billing supabase/functions/billing-subscribe supabase/functions/billing-webhook`.
- **Dart:**
  - Repositories wrap every call in `_guard`, which maps errors through `mapPostgrestError` (`lib/core/errors.dart`).
  - Widget tests use fakes from `test/support/` and never call a real `SupabaseClient`.
  - A widget test that expects an error state passes `retry: (_, _) => null` to its `ProviderScope`.
- **UI copy, exact:**
  - Owner card:
    - title `Auto-pay`
    - button `Pay / manage subscription`
    - refresh tooltip `Refresh`
    - load error `Could not load auto-pay`
    - `Last payment <₹amount> on <d MMM yyyy>`
  - Status lines:
    - `No auto-pay set up`
    - `Waiting for you to authorise auto-pay`
    - `Auto-pay authorised · first charge when your current period ends`
    - `Auto-pay on · next charge <date>` / `Auto-pay on`
    - `Auto-pay ends on <date>` / `Auto-pay ends with this period`
    - `A payment failed · Razorpay is retrying`
    - `Auto-pay stopped after failed payments`
    - `Auto-pay cancelled`
    - `Auto-pay finished`
    - `The auto-pay link expired`
    - `Auto-pay paused`
  - Sheet:
    - title `Pay / manage subscription`
    - note `Razorpay charges your plan every month. A change of plan starts when your current period ends.`
    - plan line `<₹price> / month`
    - buttons `Continue to payment` and `Cancel auto-pay`
    - confirm dialog `Cancel auto-pay?` / `Your plan stays paid until the end of the current period. Nothing more is charged.` / `Keep auto-pay` / `Cancel auto-pay`
    - payments section `Payments`, `No payments yet`, `Could not load payments`
  - Snackbars:
    - `Finish the payment on the Razorpay page, then tap Refresh.`
    - `Auto-pay is already on for <plan>.`
    - `Auto-pay will end with the current period.`
    - `Auto-pay cancelled.`
    - `There was no auto-pay to cancel.`
  - Errors:
    - `Razorpay did not send a payment link. Try again.`
    - `Could not open <url>`
    - `Razorpay did not respond. Try again in a minute.`
    - P0038: `Online payment isn't set up for this plan yet. Contact ResortHub.`
  - Console:
    - `Auto-pay: <label>`, joined to the last payment line with ` · `
    - labels: `Waiting for authorisation`, `Authorised`, `On`, `Retrying a failed payment`, `Stopped after failed payments`, `Cancelled`, `Finished`, `Expired`, `Paused`
    - Plan prices field `<Plan> Razorpay plan id`, with helper `Blank = billed by hand`
    - error `A Razorpay plan id looks like plan_ followed by letters and digits.`
- A state is never shown by colour alone: the plan picker uses radio icons, and every state has words.
- **Commands:** `flutter test <path>`, `flutter test`, `flutter analyze`.
  - The analyzer baseline is 2 infos in `service_request_screen.dart`, and no new issues are allowed.
  - Never run `dart format` over whole directories or over pre-existing files. Format only the lines you write.
  - Revert SDK-only `pubspec.lock` bumps.
- **Commits.** Every commit message ends with a blank line and `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Do not push.

## Review Focus

1. **An owner opens the Razorpay page and then abandons it.** Their trial must survive: Razorpay later sends `subscription.cancelled` for a subscription that was never charged, and that must not set the resort to Cancelled. Owning test: Task 4 (cancelling `sub_WebhookThree01`, never charged, gives `updated` and leaves R3 `active`).
2. **A double tap on "Continue to payment", or two open tabs.** This must never leave two live Razorpay subscriptions charging the same resort. Owning tests:
   - Task 3: a second opening supersedes the first and names it in `stale`.
   - Task 6: `billing-subscribe` cancels every `stale` id it is handed, and warns when it cannot.
   - Task 8: the button is disabled while a subscribe call is in flight, so a second tap makes no second call.
3. **Razorpay delivers the same webhook twice, or out of order** (a retry of `charged`, a late `charged`, a late `halted`). Expect one invoice per payment, `paid_through` never moving backwards, and an old `halted` not lapsing a freshly paid plan. Owning tests: Task 4 (duplicate, late charge, stale halted).
4. **A deployment with no Razorpay keys, or where the functions were never deployed.** Owner Settings must look exactly as before: no card and no error. The console must be unchanged. Owning tests:
   - Task 1: a probe that throws or answers 404 gives `BillingAvailability.off`.
   - Task 6: with the keys missing, every action answers `{configured:false}` and touches no database.
   - Task 8: the card is hidden when not configured.
5. **The owner of a suspended resort pays to get back on track**, while an admin of the same resort tries to start auto-pay. The owner must be allowed and the admin refused. Owning tests: Task 2 (suspended R3's owner gets a state; an admin, staff, a guest and the platform admin get P0020).

## Plan decisions (where the spec is silent or leaves a choice)

- `billing_webhook_apply` also returns the outcome `stale`, for a non-charge event older than the last one applied. The spec lists it; the Deno handler passes it through.
- A late `charged` event (not the newest) still records its invoice and can only move `paid_through` forward. It never changes the tier, the status or the trial date.
- `billing_subscription_opened` serialises openings per resort with `pg_advisory_xact_lock(hashtextextended('billing_subscriptions:' || p_property::text, 0))`, and does not lock the `properties` row.
- `set_plan_razorpay_id` trims its input, and treats blank as "clear". It refuses a plan id already used by another tier with P0005 before the unique index can raise 23505, so the admin gets a readable message.
- `billing_subscribe_state` returns `caller_id` (`auth.uid()`), so the Edge Function records who opened or cancelled a subscription without decoding the JWT itself.
- The probe answers with the billable plans (tier, name, monthly price), so the owner's sheet shows prices without reading `subscription_plans` through the platform repository.
- The Dart plan list in `BillingAvailability.plans` reuses `SubscriptionPlan`, with `sortOrder` taken from the order the function returned.
- `formatInr` shows whole rupees (`₹7,999`), the same as the rest of the console.
- Shared Deno code lives in `supabase/functions/_shared/billing/`, not in `_shared/` itself, so P6's `_shared/razorpay.ts` and P8 never touch the same file.
- The owner card watches `resortPlanProvider` only to preselect the current tier in the sheet. The existing Plan tile and its tests are unchanged.

## Execution tracks

After Task 1, three tracks share no files and can run in parallel: the database track (2 → 3 → 4), the Edge track (5 → 6, 5 → 7) and the app track (8, 9). For example, run them in three worktrees branched from Task 1's commit, and merge them back before Task 10. Edge and app tasks never need a database: Deno tests use `FakeBillingDb` / `FakeRazorpay`, and Flutter tests use `FakeBillingSource` / `FakePlatformSource`.

| Task | Track | Depends on | Files it owns |
|---|---|---|---|
| 1 Interface contract | all | none | `0057` (schema + stubs), `47` (fixtures + contract), `37` (allow-list), `billing.dart`, `subscription.dart`, `billing_repository.dart`, `platform_repository.dart`, `errors.dart`, `fake_billing_source.dart`, `fake_platform_source.dart`, `test/data/billing_test.dart`, `test/data/billing_repository_test.dart`, `test/core/errors_test.dart`, `_shared/billing/types.ts` |
| 2 Plan ids and the reads | DB | 1 | `0057`, `47` |
| 3 Opening and cancelling | DB | 2 | `0057`, `47` |
| 4 Webhook events | DB | 3 | `0057`, `47` |
| 5 Shared billing code | Edge | 1 | `_shared/billing/{http,signature,razorpay_subscriptions,decide,testing,db}.ts` and their tests |
| 6 `billing-subscribe` | Edge | 5 | `supabase/functions/billing-subscribe/*` |
| 7 `billing-webhook`, config and setup guide | Edge | 5 | `supabase/functions/billing-webhook/*`, `supabase/config.toml`, `docs/subscription-billing.md` |
| 8 Owner auto-pay card and sheet | App | 1 | `subscription_billing_card.dart`, `manage_subscription_sheet.dart`, `owner_settings_screen.dart`, their tests |
| 9 Console: plan ids and last payment | App | 1 | `plan_prices_dialog.dart`, `resort_card.dart`, `platform_screen.dart`, their tests |
| 10 Integration | all | 2–9 | none (verification) |

- The database track is strictly sequential, because Tasks 2–4 share one migration, one test file and one local Postgres.
- The Edge track: Task 5 first, then Tasks 6 and 7 side by side.
- The app track: Tasks 8 and 9 side by side.

---

## File Structure

**Database**
- Create `supabase/migrations/0057_subscription_billing.sql`: `razorpay_plan_id`, `billing_subscriptions`, `subscription_invoices` (RLS, `fill_property_id` trigger), and seven functions.
- Create `supabase/tests/47_subscription_billing_test.sql`: fixtures, contract, the reads, openings and cancellations, webhook events.
- Modify `supabase/tests/37_tenancy_isolation_test.sql`: the definer allow-list.

**Edge Functions**
- Create `supabase/functions/_shared/billing/`:
  - `types.ts`: the contract
  - `http.ts`: JSON, CORS and error responses
  - `signature.ts`: HMAC and a constant-time compare
  - `razorpay_subscriptions.ts`: the Razorpay client
  - `decide.ts`: the subscribe and cancel rules
  - `testing.ts`: fakes
  - `db.ts`: the supabase-js adapter
  - tests `signature_test.ts`, `razorpay_subscriptions_test.ts`, `decide_test.ts`
- Create `supabase/functions/billing-subscribe/{deno.json,handler.ts,handler_test.ts,index.ts}`.
- Create `supabase/functions/billing-webhook/{deno.json,handler.ts,handler_test.ts,index.ts}`.
- Modify `supabase/config.toml`: `[functions.billing-subscribe]` and `[functions.billing-webhook]`.
- Create `docs/subscription-billing.md`: the setup guide.

**App**
- Create `lib/data/models/billing.dart`:
  - `GatewayStatus`, `ResortBilling`, `PlatformBilling`, `SubscriptionInvoice`
  - `BillingAvailability`, `SubscribeResult`, `SubscribeAction`, `CancelAction`
  - `billingStatusLine`, `lastPaymentLine`
- Modify `lib/data/models/subscription.dart`: `SubscriptionPlan.razorpayPlanId`.
- Create `lib/data/repositories/billing_repository.dart`: `BillingSource`, `BillingRepository`, `billingFailureFor`, and the providers.
- Modify `lib/data/repositories/platform_repository.dart`: `billing()`, `setRazorpayPlanId()`, `platformBillingProvider`, and `plans()` selecting the plan id.
- Modify `lib/core/errors.dart`: `BillingUnavailable` and P0038.
- Create `lib/features/owner/subscription_billing_card.dart` and `lib/features/owner/manage_subscription_sheet.dart`. Modify `lib/features/owner/owner_settings_screen.dart` to add the card.
- Modify `lib/features/platform/plan_prices_dialog.dart` (plan ids), `lib/features/platform/resort_card.dart` (billing line) and `lib/features/platform/platform_screen.dart` (refresh).
- Tests:
  - Create `test/support/fake_billing_source.dart`, `test/data/billing_test.dart`, `test/data/billing_repository_test.dart` and `test/features/owner/subscription_billing_card_test.dart`.
  - Modify `test/support/fake_platform_source.dart`, `test/core/errors_test.dart`, `test/features/owner/owner_settings_screen_test.dart`, `test/features/platform/plan_prices_dialog_test.dart`, `test/features/platform/resort_card_test.dart` and `test/features/platform/platform_screen_test.dart`.

---

## Phase 0: Interface

### Task 1: Interface contract (schema, function signatures, Dart and Deno API)

**Track:** all. Every later task depends on it.

**Files:**
- Create: `supabase/migrations/0057_subscription_billing.sql`
- Create: `supabase/tests/47_subscription_billing_test.sql`
- Modify: `supabase/tests/37_tenancy_isolation_test.sql` (definer allow-list, after the `'report_collections','report_ledger','report_settlements','finance_summary',` line)
- Create: `lib/data/models/billing.dart`
- Modify: `lib/data/models/subscription.dart` (`SubscriptionPlan`)
- Create: `lib/data/repositories/billing_repository.dart`
- Modify: `lib/data/repositories/platform_repository.dart`
- Modify: `lib/core/errors.dart`
- Create: `test/support/fake_billing_source.dart`
- Modify: `test/support/fake_platform_source.dart`
- Create: `supabase/functions/_shared/billing/types.ts`
- Test: `test/data/billing_test.dart`, `test/data/billing_repository_test.dart`, `test/core/errors_test.dart`

**Interfaces:**
- Consumes:
  - `public.is_platform_admin()`, `public.has_resort_role(uuid, boolean, variadic resort_role[])`, `public.assert_resort_role(uuid, boolean, variadic resort_role[])` and `public.fill_property_id()` (0043/0046)
  - `public.subscription_tier`, `public.subscription_plans`, `public.resort_subscriptions` and `public.subscription_lapsed(...)` (0049)
  - `mapPostgrestError`, `supabaseProvider`, `formatInr`, `formatDate`, `SubscriptionTier` / `subscriptionTierFromDb` / `subscriptionTierToDb`, `SubscriptionPlan`, `defaultPlans` (`test/support/fake_platform_source.dart`)
- Produces (SQL; Tasks 2–4 replace only the bodies):
  - `subscription_plans.razorpay_plan_id text`, checked `^plan_[A-Za-z0-9]{6,40}$`, with a unique index.
  - `public.billing_subscriptions (id, property_id, tier, razorpay_plan_id, razorpay_subscription_id unique, status text, short_url, start_at, current_start, current_end, cancel_at_cycle_end, superseded_at, last_event_at, created_by, created_at, updated_at)`, with the partial unique index `billing_subscriptions_one_current`.
  - `public.subscription_invoices (id, property_id, billing_subscription_id, tier, razorpay_payment_id unique, razorpay_invoice_id, amount_inr, currency, period_start, period_end, paid_at, created_at)`.
  - `public.set_plan_razorpay_id(p_tier public.subscription_tier, p_plan_id text) returns void`
  - `public.my_resort_billing(p_property uuid) returns table(billing_status text, billing_tier public.subscription_tier, short_url text, cancel_at_cycle_end boolean, current_end timestamptz, last_payment_at timestamptz, last_payment_inr numeric)`
  - `public.platform_billing() returns table(property_id uuid, billing_status text, billing_tier public.subscription_tier, last_payment_at timestamptz, last_payment_inr numeric)`
  - `public.billing_subscribe_state(p_property uuid, p_tier public.subscription_tier default null) returns jsonb`
  - `public.billing_subscription_opened(p_property uuid, p_tier public.subscription_tier, p_razorpay_plan_id text, p_razorpay_subscription_id text, p_status text, p_short_url text, p_start_at timestamptz, p_created_by uuid) returns jsonb`
  - `public.billing_subscription_cancel_requested(p_razorpay_subscription_id text, p_at_cycle_end boolean, p_status text, p_actor uuid default null) returns void`
  - `public.billing_webhook_apply(p_event text, p_event_at timestamptz, p_subscription jsonb, p_payment jsonb) returns jsonb`
- Produces (Dart):
  - `enum GatewayStatus { created, authenticated, active, pending, halted, cancelled, completed, expired, paused }`, with `gatewayStatusFromDb(String)` and `label` (extension `GatewayStatusLabel`).
  - `class ResortBilling`:
    - fields `status (GatewayStatus?)`, `tier (SubscriptionTier?)`, `shortUrl`, `cancelAtCycleEnd`, `currentEnd`, `lastPaymentAt`, `lastPaymentInr`
    - `fromRow(Map)`, and `bool get canCancel`
  - `class PlatformBilling { propertyId, status, tier, lastPaymentAt, lastPaymentInr }` with `fromRow(Map)`.
  - `class SubscriptionInvoice { id, tier, amountInr, paidAt, periodStart, periodEnd }` with `fromJson(Map)`.
  - `class BillingAvailability { configured, plans (List<SubscriptionPlan>), canPay }`, with `fromJson` and `BillingAvailability.off`.
  - `enum SubscribeAction { created, reused, unchanged }`, and `class SubscribeResult { action, subscriptionId, shortUrl, status, warning }` with `fromJson`.
  - `enum CancelAction { cancelScheduled, cancelled, none }` with `cancelActionFromWire(Object?)`.
  - `String billingStatusLine(ResortBilling)` and `String? lastPaymentLine(num? amountInr, DateTime? paidAt)`.
  - `SubscriptionPlan` gains `final String? razorpayPlanId` (optional named constructor argument).
  - `abstract class BillingSource`:
    - `Future<BillingAvailability> availability(String propertyId)`
    - `Future<ResortBilling?> billing(String propertyId)`
    - `Future<List<SubscriptionInvoice>> invoices(String propertyId)`
    - `Future<SubscribeResult> subscribe(String propertyId, SubscriptionTier tier)`
    - `Future<CancelAction> cancel(String propertyId)`
  - `typedef BillingFunctionInvoker = Future<Object?> Function(String name, Map<String, dynamic> body)`, `const billingFunctionName = 'billing-subscribe'`, `class BillingRepository` and `BookingFailure billingFailureFor(Object error)`.
  - Providers:
    - `billingRepositoryProvider` and `billingSourceProvider`
    - `billingAvailabilityProvider`, `resortBillingProvider` and `subscriptionInvoicesProvider`: each `FutureProvider.autoDispose.family<…, String>`, keyed by property id
    - `platformBillingProvider` (`FutureProvider<Map<String, PlatformBilling>>`)
  - `PlatformSource` gains `Future<List<PlatformBilling>> billing()` and `Future<void> setRazorpayPlanId(SubscriptionTier tier, String? planId)`.
  - `class BillingUnavailable extends BookingFailure`, mapped from P0038.
  - Test support:
    - `FakeBillingSource`:
      - fields `availabilityValue`, `billingValue`, `invoiceList`, `subscribeResult`, `cancelResult`, `billingError`, `invoicesError`, `subscribeError`, `cancelError`, `hold` (`Completer<void>?`)
      - call logs `availabilityCalls`, `billingCalls`, `invoiceCalls`, `subscribeCalls` (`(String, SubscriptionTier)`) and `cancelCalls`
    - the builders `resortBilling({...})` and `subscriptionInvoice({...})`, and `billablePlans`
    - `FakePlatformSource` gains `billingList`, `billingError`, `planIdError`, `billingCalls` and `planIdCalls` (`(SubscriptionTier, String?)`)
- Produces (Deno): `supabase/functions/_shared/billing/types.ts`, which exports:
  - the types `Tier`, `RazorpaySubscriptionStatus`, `BillingAction`, `SubscribeRequest`, `BillablePlan`, `NotConfigured`, `ProbeResponse`, `SubscribeResponse`, `CancelResponse`, `ErrorKind`, `ErrorBody`, `WebhookResponse`, `CurrentSubscription`, `SubscribeState`, `OpenedArgs`, `OpenedResult`, `ApplyOutcome`, `ApplyResult` and `BillingDb`
  - the constants `TIERS` and `LIVE_STATUSES`
  - the class `DbError`

- [ ] **Step 1: Record the baselines**

Run: `supabase db reset && supabase test db 2>&1 | tail -20`, then `flutter analyze 2>&1 | tail -5`, then `flutter test 2>&1 | tail -3`
Expected: write down the pgTAP failure count and file names (the 3 known IST-midnight failures at most), the analyzer issue count (2 infos), and the Flutter pass count. Later tasks compare against these.

- [ ] **Step 2: Write the failing pgTAP contract test**

Create `supabase/tests/47_subscription_billing_test.sql`:

```sql
-- Subscription auto-billing (P8), added in 0057_subscription_billing.sql.
-- See docs/superpowers/specs/2026-09-25-p8-subscription-auto-billing-design.md.
--
-- One file, built up by the plan's database tasks in order: each section
-- relies on the state the sections before it leave behind.
--
-- Fixtures: a platform admin (U1); an owner (U2) of R1, R3, R4 and R5; an
-- admin (U3) and a staff member (U4) of R1; a second owner (U5) of R2;
-- and a guest (U6) with no membership.
--   R1 Bill Trial      starter trial ending in 10 days
--   R2 Bill Paid       pro, active, paid until 5 days from now
--   R3 Bill Suspended  suspended resort, starter, active, no end date
--   R4 Bill Lapsed     pro, active, paid until 3 days ago
--   R5 Bill None       no subscription row
begin;
select plan(20);

-- "Today" as the subscription functions see it.
create function pg_temp.today() returns date
language sql stable as $f$ select (now() at time zone 'Asia/Kolkata')::date $f$;

-- Unix seconds of midnight Asia/Kolkata at the start of p_day.
create function pg_temp.ist(p_day date) returns bigint
language sql stable as $f$
  select extract(epoch from (p_day::timestamp at time zone 'Asia/Kolkata'))::bigint
$f$;

insert into auth.users (id, email) values
  ('b8000000-0000-0000-0000-000000000001','bill-platform@example.com'),
  ('b8000000-0000-0000-0000-000000000002','bill-owner@example.com'),
  ('b8000000-0000-0000-0000-000000000003','bill-admin@example.com'),
  ('b8000000-0000-0000-0000-000000000004','bill-staff@example.com'),
  ('b8000000-0000-0000-0000-000000000005','bill-other@example.com'),
  ('b8000000-0000-0000-0000-000000000006','bill-guest@example.com');
update public.profiles set role = 'platform_admin'
  where id = 'b8000000-0000-0000-0000-000000000001';

insert into public.properties (id, name, slug, status) values
  ('b8100000-0000-4000-8000-000000000001','Bill Trial','bill-trial','active'),
  ('b8100000-0000-4000-8000-000000000002','Bill Paid','bill-paid','active'),
  ('b8100000-0000-4000-8000-000000000003','Bill Suspended','bill-suspended','suspended'),
  ('b8100000-0000-4000-8000-000000000004','Bill Lapsed','bill-lapsed','active'),
  ('b8100000-0000-4000-8000-000000000005','Bill None','bill-none','active');

insert into public.resort_members (property_id, user_id, role) values
  ('b8100000-0000-4000-8000-000000000001','b8000000-0000-0000-0000-000000000002','owner'),
  ('b8100000-0000-4000-8000-000000000001','b8000000-0000-0000-0000-000000000003','admin'),
  ('b8100000-0000-4000-8000-000000000001','b8000000-0000-0000-0000-000000000004','staff'),
  ('b8100000-0000-4000-8000-000000000002','b8000000-0000-0000-0000-000000000005','owner'),
  ('b8100000-0000-4000-8000-000000000003','b8000000-0000-0000-0000-000000000002','owner'),
  ('b8100000-0000-4000-8000-000000000004','b8000000-0000-0000-0000-000000000002','owner'),
  ('b8100000-0000-4000-8000-000000000005','b8000000-0000-0000-0000-000000000002','owner');

insert into public.resort_subscriptions (property_id, tier, status, trial_ends_on, paid_through) values
  ('b8100000-0000-4000-8000-000000000001','starter','trial',pg_temp.today() + 10,null),
  ('b8100000-0000-4000-8000-000000000002','pro','active',null,pg_temp.today() + 5),
  ('b8100000-0000-4000-8000-000000000003','starter','active',null,null),
  ('b8100000-0000-4000-8000-000000000004','pro','active',null,pg_temp.today() - 3);

-- === Task 1: the contract ===================================================

select has_column('public', 'subscription_plans', 'razorpay_plan_id',
  'each tier can carry a Razorpay plan id');
select has_table('public', 'billing_subscriptions', 'billing_subscriptions exists');
select has_table('public', 'subscription_invoices', 'subscription_invoices exists');
select throws_ok($$update public.subscription_plans set razorpay_plan_id = 'pro-monthly' where tier = 'pro'$$,
  '23514', null, 'a plan id must look like plan_...');
select throws_ok($$insert into public.billing_subscriptions
    (property_id, tier, razorpay_plan_id, razorpay_subscription_id)
  values ('b8100000-0000-4000-8000-000000000001', 'pro', 'plan_ContractPro01', 'subscription-1')$$,
  '23514', null, 'a subscription id must look like sub_...');
select is((select array_agg(p.parameter_name::text order by p.ordinal_position)
             from information_schema.parameters p
             join information_schema.routines r
               on r.specific_schema = p.specific_schema and r.specific_name = p.specific_name
            where r.routine_schema = 'public' and r.routine_name = 'my_resort_billing'
              and p.parameter_mode = 'OUT'),
  array['billing_status','billing_tier','short_url','cancel_at_cycle_end','current_end',
        'last_payment_at','last_payment_inr'],
  'my_resort_billing returns the columns ResortBilling.fromRow reads');
select is((select array_agg(p.parameter_name::text order by p.ordinal_position)
             from information_schema.parameters p
             join information_schema.routines r
               on r.specific_schema = p.specific_schema and r.specific_name = p.specific_name
            where r.routine_schema = 'public' and r.routine_name = 'platform_billing'
              and p.parameter_mode = 'OUT'),
  array['property_id','billing_status','billing_tier','last_payment_at','last_payment_inr'],
  'platform_billing returns the columns PlatformBilling.fromRow reads');
select is((select array_agg(f::text order by f::text)
             from unnest(array[
               'public.set_plan_razorpay_id(public.subscription_tier, text)',
               'public.my_resort_billing(uuid)',
               'public.platform_billing()',
               'public.billing_subscribe_state(uuid, public.subscription_tier)',
               'public.billing_subscription_opened(uuid, public.subscription_tier, text, text, text, text, timestamptz, uuid)',
               'public.billing_subscription_cancel_requested(text, boolean, text, uuid)',
               'public.billing_webhook_apply(text, timestamptz, jsonb, jsonb)']::regprocedure[]) f
            where has_function_privilege('anon', f, 'execute')),
  null, 'anon can execute none of the billing functions');
select is((select array_agg(p.proname::text order by p.proname::text)
             from unnest(array[
               'public.set_plan_razorpay_id(public.subscription_tier, text)',
               'public.my_resort_billing(uuid)',
               'public.platform_billing()',
               'public.billing_subscribe_state(uuid, public.subscription_tier)',
               'public.billing_subscription_opened(uuid, public.subscription_tier, text, text, text, text, timestamptz, uuid)',
               'public.billing_subscription_cancel_requested(text, boolean, text, uuid)',
               'public.billing_webhook_apply(text, timestamptz, jsonb, jsonb)']::regprocedure[]) f
             join pg_proc p on p.oid = f
            where has_function_privilege('authenticated', f, 'execute')),
  array['billing_subscribe_state','my_resort_billing','platform_billing','set_plan_razorpay_id'],
  'signed-in users execute only the reads and the plan id, never the billing writes');
select is((select count(*)::int
             from unnest(array[
               'public.billing_subscription_opened(uuid, public.subscription_tier, text, text, text, text, timestamptz, uuid)',
               'public.billing_subscription_cancel_requested(text, boolean, text, uuid)',
               'public.billing_webhook_apply(text, timestamptz, jsonb, jsonb)']::regprocedure[]) f
            where has_function_privilege('service_role', f, 'execute')),
  3, 'the Edge Functions (service role) execute the three billing writes');

-- A contract fixture: a current subscription with one invoice at R1.
insert into public.billing_subscriptions
  (id, property_id, tier, razorpay_plan_id, razorpay_subscription_id, status)
values ('b8200000-0000-4000-8000-000000000001', 'b8100000-0000-4000-8000-000000000001',
        'pro', 'plan_ContractPro01', 'sub_Contract000001', 'active');
insert into public.subscription_invoices
  (billing_subscription_id, tier, razorpay_payment_id, amount_inr, paid_at)
values ('b8200000-0000-4000-8000-000000000001', 'pro', 'pay_Contract000001', 7999, now());

select throws_ok($$insert into public.subscription_invoices
    (property_id, billing_subscription_id, tier, razorpay_payment_id, amount_inr, paid_at)
  values ('b8100000-0000-4000-8000-000000000002', 'b8200000-0000-4000-8000-000000000001',
          'pro', 'pay_Contract000002', 7999, now())$$,
  'P0021', null, 'an invoice always belongs to its subscription''s resort');
select throws_ok($$insert into public.billing_subscriptions
    (property_id, tier, razorpay_plan_id, razorpay_subscription_id)
  values ('b8100000-0000-4000-8000-000000000001', 'pro', 'plan_ContractPro01', 'sub_Contract000002')$$,
  '23505', null, 'a resort has one current subscription at a time');

set local role authenticated;
set local request.jwt.claims to '{"sub":"b8000000-0000-0000-0000-000000000002","role":"authenticated"}';
select is((select count(*)::int from public.billing_subscriptions), 1,
  'the owner reads their resort''s subscription');
select is((select count(*)::int from public.subscription_invoices), 1,
  'the owner reads their resort''s invoices');
select throws_ok($$insert into public.billing_subscriptions
    (property_id, tier, razorpay_plan_id, razorpay_subscription_id)
  values ('b8100000-0000-4000-8000-000000000005', 'pro', 'plan_ContractPro01', 'sub_Contract000003')$$,
  '42501', null, 'the owner cannot write a subscription directly');
select throws_ok($$update public.subscription_invoices set amount_inr = 0$$,
  '42501', null, 'the owner cannot change an invoice');
set local request.jwt.claims to '{"sub":"b8000000-0000-0000-0000-000000000003","role":"authenticated"}';
select is((select count(*)::int from public.billing_subscriptions), 0,
  'an admin reads no billing subscription (owner only)');
set local request.jwt.claims to '{"sub":"b8000000-0000-0000-0000-000000000004","role":"authenticated"}';
select is((select count(*)::int from public.subscription_invoices), 0, 'staff read no invoices');
set local request.jwt.claims to '{"sub":"b8000000-0000-0000-0000-000000000005","role":"authenticated"}';
select is((select count(*)::int from public.billing_subscriptions)
          + (select count(*)::int from public.subscription_invoices), 0,
  'another resort''s owner reads nothing');
set local request.jwt.claims to '{"sub":"b8000000-0000-0000-0000-000000000001","role":"authenticated"}';
select is((select count(*)::int from public.billing_subscriptions)
          + (select count(*)::int from public.subscription_invoices), 0,
  'the platform admin has no direct row access');
reset role;
set local request.jwt.claims to '';
delete from public.billing_subscriptions;

select * from finish();
rollback;
```

- [ ] **Step 3: Run it to verify it fails**

Run: `supabase test db supabase/tests/47_subscription_billing_test.sql`
Expected: FAIL at the first fixture insert into `billing_subscriptions`, with `relation "public.billing_subscriptions" does not exist`.

- [ ] **Step 4: Write the migration's schema and function contract**

Create `supabase/migrations/0057_subscription_billing.sql`:

```sql
-- Subscription auto-billing (P8): Razorpay Subscriptions on top of the
-- manual plans of 0049. The platform admin stores a Razorpay plan id per
-- tier; a resort owner starts, changes or cancels auto-pay through the
-- billing-subscribe Edge Function; the billing-webhook Edge Function hands
-- Razorpay's subscription events to billing_webhook_apply. Without
-- Razorpay secrets nothing here is ever called and plans stay manual.
-- See docs/superpowers/specs/2026-09-25-p8-subscription-auto-billing-design.md.
--
-- Errors: P0038 billing_unavailable (the tier has no Razorpay plan id),
-- P0005 bad input (messages written for the admin, shown verbatim), P0002
-- unknown row, P0008 not the platform admin, P0020 not the resort's owner,
-- P0021 a subscription id at another resort.

-- ---------------------------------------------------------------------
-- The Razorpay plan behind each tier (spec decision 3). Readable like the
-- rest of subscription_plans; written only by set_plan_razorpay_id.
alter table public.subscription_plans
  add column razorpay_plan_id text
    constraint subscription_plans_razorpay_plan_id_format
      check (razorpay_plan_id ~ '^plan_[A-Za-z0-9]{6,40}$');
create unique index subscription_plans_razorpay_plan_id_key
  on public.subscription_plans (razorpay_plan_id);

-- ---------------------------------------------------------------------
-- billing_subscriptions: every Razorpay subscription created for a
-- resort. The row with superseded_at null is the resort's current one
-- (spec decision 5). Read by the resort's owner; written only by the
-- service-role functions below.
create table public.billing_subscriptions (
  id                       uuid primary key default gen_random_uuid(),
  property_id              uuid not null references public.properties(id) on delete cascade,
  tier                     public.subscription_tier not null
                             references public.subscription_plans(tier),
  razorpay_plan_id         text not null,
  razorpay_subscription_id text not null unique
    constraint billing_subscriptions_id_format
      check (razorpay_subscription_id ~ '^sub_[A-Za-z0-9]{6,40}$'),
  -- Razorpay's own lifecycle, stored as sent.
  status                   text not null default 'created'
    constraint billing_subscriptions_status_known
      check (status in ('created','authenticated','active','pending','halted',
                        'cancelled','completed','expired','paused')),
  short_url                text,
  start_at                 timestamptz,
  current_start            timestamptz,
  current_end              timestamptz,
  cancel_at_cycle_end      boolean not null default false,
  superseded_at            timestamptz,
  -- created_at of the newest webhook event applied (spec decision 13).
  last_event_at            timestamptz,
  created_by               uuid,
  created_at               timestamptz not null default now(),
  updated_at               timestamptz not null default now()
);
create index billing_subscriptions_property_idx on public.billing_subscriptions (property_id);
create unique index billing_subscriptions_one_current
  on public.billing_subscriptions (property_id) where superseded_at is null;

alter table public.billing_subscriptions enable row level security;
revoke all on public.billing_subscriptions from anon, authenticated;
grant select on public.billing_subscriptions to authenticated;
create policy billing_subscriptions_read on public.billing_subscriptions
  for select to authenticated
  using (public.has_resort_role(property_id, false, 'owner'));

-- ---------------------------------------------------------------------
-- subscription_invoices: one row per successful Razorpay charge (spec
-- decisions 10 and 18). property_id is filled from, and checked against,
-- the subscription (P0021 on a mismatch).
create table public.subscription_invoices (
  id                      uuid primary key default gen_random_uuid(),
  property_id             uuid not null references public.properties(id) on delete cascade,
  billing_subscription_id uuid not null
                            references public.billing_subscriptions(id) on delete cascade,
  tier                    public.subscription_tier not null,
  razorpay_payment_id     text not null unique,
  razorpay_invoice_id     text,
  amount_inr              numeric(12,2) not null
    constraint subscription_invoices_amount_not_negative check (amount_inr >= 0),
  currency                text not null default 'INR',
  period_start            date,
  period_end              date,
  paid_at                 timestamptz not null,
  created_at              timestamptz not null default now()
);
create index subscription_invoices_property_idx
  on public.subscription_invoices (property_id, paid_at desc);
create index subscription_invoices_subscription_idx
  on public.subscription_invoices (billing_subscription_id);

create trigger subscription_invoices_fill_property
  before insert or update on public.subscription_invoices
  for each row execute function public.fill_property_id('billing_subscriptions', 'billing_subscription_id');

alter table public.subscription_invoices enable row level security;
revoke all on public.subscription_invoices from anon, authenticated;
grant select on public.subscription_invoices to authenticated;
create policy subscription_invoices_read on public.subscription_invoices
  for select to authenticated
  using (public.has_resort_role(property_id, false, 'owner'));

-- ---------------------------------------------------------------------
-- Functions. The signatures are the contract the app and the Edge
-- Functions are built against; Tasks 2-4 of the plan replace the bodies.

create function public.set_plan_razorpay_id(
  p_tier    public.subscription_tier,
  p_plan_id text
) returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  raise exception 'set_plan_razorpay_id is not implemented yet' using errcode = '0A000';
end;
$$;

create function public.my_resort_billing(p_property uuid)
returns table(
  billing_status      text,
  billing_tier        public.subscription_tier,
  short_url           text,
  cancel_at_cycle_end boolean,
  current_end         timestamptz,
  last_payment_at     timestamptz,
  last_payment_inr    numeric
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  raise exception 'my_resort_billing is not implemented yet' using errcode = '0A000';
end;
$$;

create function public.platform_billing()
returns table(
  property_id      uuid,
  billing_status   text,
  billing_tier     public.subscription_tier,
  last_payment_at  timestamptz,
  last_payment_inr numeric
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  raise exception 'platform_billing is not implemented yet' using errcode = '0A000';
end;
$$;

create function public.billing_subscribe_state(
  p_property uuid,
  p_tier     public.subscription_tier default null
) returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  raise exception 'billing_subscribe_state is not implemented yet' using errcode = '0A000';
end;
$$;

create function public.billing_subscription_opened(
  p_property                 uuid,
  p_tier                     public.subscription_tier,
  p_razorpay_plan_id         text,
  p_razorpay_subscription_id text,
  p_status                   text,
  p_short_url                text,
  p_start_at                 timestamptz,
  p_created_by               uuid
) returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  raise exception 'billing_subscription_opened is not implemented yet' using errcode = '0A000';
end;
$$;

create function public.billing_subscription_cancel_requested(
  p_razorpay_subscription_id text,
  p_at_cycle_end             boolean,
  p_status                   text,
  p_actor                    uuid default null
) returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  raise exception 'billing_subscription_cancel_requested is not implemented yet' using errcode = '0A000';
end;
$$;

create function public.billing_webhook_apply(
  p_event        text,
  p_event_at     timestamptz,
  p_subscription jsonb,
  p_payment      jsonb
) returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  raise exception 'billing_webhook_apply is not implemented yet' using errcode = '0A000';
end;
$$;

-- Client-callable: the reads and the platform admin's plan id.
revoke execute on function public.set_plan_razorpay_id(public.subscription_tier, text) from public, anon;
revoke execute on function public.my_resort_billing(uuid) from public, anon;
revoke execute on function public.platform_billing() from public, anon;
revoke execute on function public.billing_subscribe_state(uuid, public.subscription_tier) from public, anon;
grant execute on function public.set_plan_razorpay_id(public.subscription_tier, text) to authenticated;
grant execute on function public.my_resort_billing(uuid) to authenticated;
grant execute on function public.platform_billing() to authenticated;
grant execute on function public.billing_subscribe_state(uuid, public.subscription_tier) to authenticated;

-- Service role only: the Edge Functions record what Razorpay did.
revoke execute on function public.billing_subscription_opened(uuid, public.subscription_tier, text, text, text, text, timestamptz, uuid) from public, anon, authenticated;
revoke execute on function public.billing_subscription_cancel_requested(text, boolean, text, uuid) from public, anon, authenticated;
revoke execute on function public.billing_webhook_apply(text, timestamptz, jsonb, jsonb) from public, anon, authenticated;
grant execute on function public.billing_subscription_opened(uuid, public.subscription_tier, text, text, text, text, timestamptz, uuid) to service_role;
grant execute on function public.billing_subscription_cancel_requested(text, boolean, text, uuid) to service_role;
grant execute on function public.billing_webhook_apply(text, timestamptz, jsonb, jsonb) to service_role;
```

- [ ] **Step 5: Add the functions to the definer allow-list**

In `supabase/tests/37_tenancy_isolation_test.sql`, find the line
`        'report_collections','report_ledger','report_settlements','finance_summary',`
and insert directly after it:

```sql
        -- 0057: subscription billing. set_plan_razorpay_id and
        -- platform_billing check is_platform_admin(); my_resort_billing and
        -- billing_subscribe_state assert the owner at the resort they are
        -- given; the three billing writes are executable by service_role
        -- only and derive the resort from the Razorpay subscription row.
        'set_plan_razorpay_id','my_resort_billing','platform_billing',
        'billing_subscribe_state','billing_subscription_opened',
        'billing_subscription_cancel_requested','billing_webhook_apply',
```

- [ ] **Step 6: Run the database tests to verify they pass**

Run: `supabase db reset && supabase test db supabase/tests/47_subscription_billing_test.sql supabase/tests/37_tenancy_isolation_test.sql supabase/tests/41_subscriptions_test.sql`
Expected: 47 passes 20/20. 37 and 41 pass as in the baseline. 37's allow-list guard stays green, and 41 still passes, because `subscription_plans` only gained a nullable column.

- [ ] **Step 7: Write the Deno contract types**

Create `supabase/functions/_shared/billing/types.ts`:

```ts
// The contract of the billing Edge Functions (P8). Names match the SQL
// functions in supabase/migrations/0057_subscription_billing.sql and the
// Flutter side in lib/data/repositories/billing_repository.dart.

export type Tier = "starter" | "pro" | "enterprise";
export const TIERS: readonly Tier[] = ["starter", "pro", "enterprise"];

/** Razorpay's subscription states (billing_subscriptions.status). */
export type RazorpaySubscriptionStatus =
  | "created"
  | "authenticated"
  | "active"
  | "pending"
  | "halted"
  | "cancelled"
  | "completed"
  | "expired"
  | "paused";

/** States in which a subscription can still be authorised or charge. */
export const LIVE_STATUSES: readonly RazorpaySubscriptionStatus[] = [
  "created",
  "authenticated",
  "active",
  "pending",
  "paused",
];

// --- billing-subscribe ----------------------------------------------------

export type BillingAction = "probe" | "subscribe" | "cancel";

export interface SubscribeRequest {
  property_id: string;
  action: BillingAction;
  /** Required for "subscribe". */
  tier?: Tier;
}

export interface BillablePlan {
  tier: Tier;
  name: string;
  monthly_price_inr: number;
}

/** Every action's answer while RAZORPAY_KEY_ID / _SECRET are unset. */
export interface NotConfigured {
  configured: false;
}

export interface ProbeResponse {
  configured: true;
  /** Only the tiers with a Razorpay plan id, cheapest first. */
  plans: BillablePlan[];
}

export interface SubscribeResponse {
  configured: true;
  action: "created" | "reused" | "unchanged";
  subscription_id: string;
  short_url: string | null;
  status: RazorpaySubscriptionStatus;
  /** A replaced subscription could not be cancelled; it will be retried. */
  warning?: "previous_not_cancelled";
}

export interface CancelResponse {
  configured: true;
  action: "cancel_scheduled" | "cancelled" | "none";
  subscription_id: string | null;
  status: RazorpaySubscriptionStatus | null;
}

export type ErrorKind =
  | "bad_request"
  | "unauthorized"
  | "method_not_allowed"
  | "db"
  | "gateway"
  | "invalid_signature"
  | "not_configured"
  | "internal";

export interface ErrorBody {
  error: ErrorKind;
  /** The Postgres error code, for "db". */
  code?: string;
  message: string;
}

// --- billing-webhook -------------------------------------------------------

export type ApplyOutcome =
  | "ignored"
  | "updated"
  | "stale"
  | "charged"
  | "duplicate"
  | "lapsed"
  | "cancelled";

export interface WebhookResponse {
  status: "processed" | "ignored";
  outcome?: ApplyOutcome;
}

// --- the database (0057) ---------------------------------------------------

export interface CurrentSubscription {
  razorpay_subscription_id: string;
  tier: Tier;
  status: RazorpaySubscriptionStatus;
  short_url: string | null;
  cancel_at_cycle_end: boolean;
}

/** What billing_subscribe_state(p_property, p_tier) returns. */
export interface SubscribeState {
  property_id: string;
  property_name: string;
  caller_id: string;
  notify_email: string | null;
  tier: Tier | null;
  plan_id: string | null;
  /** Unix seconds; null = start now. */
  start_at: number | null;
  current: CurrentSubscription | null;
  /** Replaced subscriptions still live: cancel them. */
  stale: string[];
}

export interface OpenedArgs {
  property_id: string;
  tier: Tier;
  razorpay_plan_id: string;
  razorpay_subscription_id: string;
  status: RazorpaySubscriptionStatus;
  short_url: string | null;
  start_at: number | null;
  created_by: string;
}

export interface OpenedResult {
  id: string;
  stale: string[];
}

export interface ApplyResult {
  outcome: ApplyOutcome;
  property_id: string | null;
  cancel_subscription_id: string | null;
}

/** A Postgres error, with its SQLSTATE (e.g. P0020, P0038). */
export class DbError extends Error {
  constructor(readonly code: string, message: string) {
    super(message);
    this.name = "DbError";
  }
}

/**
 * Every database call the two functions make. billablePlans and
 * subscribeState run as the signed-in caller; the rest as the service role.
 */
export interface BillingDb {
  billablePlans(): Promise<BillablePlan[]>;
  subscribeState(propertyId: string, tier: Tier | null): Promise<SubscribeState>;
  opened(args: OpenedArgs): Promise<OpenedResult>;
  cancelRequested(
    subscriptionId: string,
    atCycleEnd: boolean,
    status: RazorpaySubscriptionStatus | null,
    actor: string | null,
  ): Promise<void>;
  applyWebhook(
    event: string,
    eventAt: string | null,
    subscription: Record<string, unknown>,
    payment: Record<string, unknown> | null,
  ): Promise<ApplyResult>;
}
```

Run: `deno check supabase/functions/_shared/billing/types.ts`
Expected: `Check …/types.ts` and no errors.

- [ ] **Step 8: Write the failing Dart model and repository tests**

Create `test/data/billing_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/data/models/billing.dart';
import 'package:pasala/data/models/subscription.dart';

void main() {
  group('GatewayStatus', () {
    test('every Razorpay state is read, and unknown text is rejected', () {
      for (final s in GatewayStatus.values) {
        expect(gatewayStatusFromDb(s.name), s);
      }
      expect(() => gatewayStatusFromDb('lapsed'), throwsArgumentError);
    });

    test('labels for the console', () {
      expect(GatewayStatus.active.label, 'On');
      expect(GatewayStatus.created.label, 'Waiting for authorisation');
      expect(GatewayStatus.halted.label, 'Stopped after failed payments');
    });
  });

  group('ResortBilling.fromRow', () {
    test('reads my_resort_billing', () {
      final b = ResortBilling.fromRow({
        'billing_status': 'active',
        'billing_tier': 'pro',
        'short_url': 'https://rzp.io/i/abc',
        'cancel_at_cycle_end': false,
        'current_end': '2026-11-01T00:00:00+05:30',
        'last_payment_at': '2026-10-01T09:30:00+00:00',
        'last_payment_inr': 7999,
      });
      expect(b.status, GatewayStatus.active);
      expect(b.tier, SubscriptionTier.pro);
      expect(b.shortUrl, 'https://rzp.io/i/abc');
      expect(b.currentEnd!.toUtc(), DateTime.utc(2026, 10, 31, 18, 30));
      expect(b.lastPaymentAt!.toUtc(), DateTime.utc(2026, 10, 1, 9, 30));
      expect(b.lastPaymentInr, 7999);
      expect(b.canCancel, isTrue);
    });

    test('a resort with only past payments has no status', () {
      final b = ResortBilling.fromRow({
        'billing_status': null,
        'billing_tier': null,
        'short_url': null,
        'cancel_at_cycle_end': null,
        'current_end': null,
        'last_payment_at': '2026-10-01T09:30:00+00:00',
        'last_payment_inr': '2999.00',
      });
      expect(b.status, isNull);
      expect(b.cancelAtCycleEnd, isFalse);
      expect(b.lastPaymentInr, 2999);
      expect(b.canCancel, isFalse);
    });

    test('a pending cancel cannot be cancelled again', () {
      const b = ResortBilling(
          status: GatewayStatus.active, cancelAtCycleEnd: true);
      expect(b.canCancel, isFalse);
    });
  });

  test('PlatformBilling.fromRow reads platform_billing', () {
    final b = PlatformBilling.fromRow({
      'property_id': 'p1',
      'billing_status': 'halted',
      'billing_tier': 'starter',
      'last_payment_at': null,
      'last_payment_inr': null,
    });
    expect(b.propertyId, 'p1');
    expect(b.status, GatewayStatus.halted);
    expect(b.tier, SubscriptionTier.starter);
    expect(b.lastPaymentInr, isNull);
  });

  test('SubscriptionInvoice.fromJson reads a subscription_invoices row', () {
    final i = SubscriptionInvoice.fromJson({
      'id': 'i1',
      'tier': 'pro',
      'amount_inr': 7999,
      'paid_at': '2026-10-01T09:30:00+00:00',
      'period_start': '2026-10-01',
      'period_end': '2026-10-31',
    });
    expect(i.tier, SubscriptionTier.pro);
    expect(i.amountInr, 7999);
    expect(i.periodStart, DateTime(2026, 10, 1));
    expect(i.periodEnd, DateTime(2026, 10, 31));
  });

  group('BillingAvailability.fromJson', () {
    test('not configured', () {
      final a = BillingAvailability.fromJson({'configured': false});
      expect(a.configured, isFalse);
      expect(a.canPay, isFalse);
    });

    test('configured, with the billable plans in order', () {
      final a = BillingAvailability.fromJson({
        'configured': true,
        'plans': [
          {'tier': 'starter', 'name': 'Starter', 'monthly_price_inr': 2999},
          {'tier': 'pro', 'name': 'Pro', 'monthly_price_inr': '7999.00'},
        ],
      });
      expect(a.canPay, isTrue);
      expect(a.plans.map((p) => p.tier),
          [SubscriptionTier.starter, SubscriptionTier.pro]);
      expect(a.plans[1].monthlyPriceInr, 7999);
      expect(a.plans[1].sortOrder, 2);
    });

    test('configured but no tier has a plan id: nothing to pay', () {
      final a = BillingAvailability.fromJson({'configured': true, 'plans': []});
      expect(a.configured, isTrue);
      expect(a.canPay, isFalse);
    });
  });

  test('SubscribeResult.fromJson and cancelActionFromWire', () {
    final r = SubscribeResult.fromJson({
      'configured': true,
      'action': 'reused',
      'subscription_id': 'sub_Abc123456789',
      'short_url': 'https://rzp.io/i/abc',
      'status': 'created',
    });
    expect(r.action, SubscribeAction.reused);
    expect(r.shortUrl, 'https://rzp.io/i/abc');
    expect(r.status, GatewayStatus.created);
    expect(r.warning, isNull);
    expect(cancelActionFromWire('cancel_scheduled'), CancelAction.cancelScheduled);
    expect(cancelActionFromWire('cancelled'), CancelAction.cancelled);
    expect(cancelActionFromWire('none'), CancelAction.none);
    expect(() => cancelActionFromWire('later'), throwsArgumentError);
  });

  group('billingStatusLine', () {
    test('every state reads as words', () {
      String line(GatewayStatus? s,
              {bool cancel = false, DateTime? end}) =>
          billingStatusLine(ResortBilling(
              status: s, cancelAtCycleEnd: cancel, currentEnd: end));
      final nov1 = DateTime(2026, 11, 1);
      expect(line(null), 'No auto-pay set up');
      expect(line(GatewayStatus.created),
          'Waiting for you to authorise auto-pay');
      expect(line(GatewayStatus.authenticated),
          'Auto-pay authorised · first charge when your current period ends');
      expect(line(GatewayStatus.active, end: nov1),
          'Auto-pay on · next charge 1 Nov 2026');
      expect(line(GatewayStatus.active), 'Auto-pay on');
      expect(line(GatewayStatus.active, cancel: true, end: nov1),
          'Auto-pay ends on 1 Nov 2026');
      expect(line(GatewayStatus.active, cancel: true),
          'Auto-pay ends with this period');
      expect(line(GatewayStatus.pending),
          'A payment failed · Razorpay is retrying');
      expect(line(GatewayStatus.halted),
          'Auto-pay stopped after failed payments');
      expect(line(GatewayStatus.cancelled), 'Auto-pay cancelled');
      expect(line(GatewayStatus.completed), 'Auto-pay finished');
      expect(line(GatewayStatus.expired), 'The auto-pay link expired');
      expect(line(GatewayStatus.paused), 'Auto-pay paused');
    });

    test('lastPaymentLine needs both an amount and a date', () {
      expect(lastPaymentLine(7999, DateTime(2026, 10, 1)),
          'Last payment ₹7,999 on 1 Oct 2026');
      expect(lastPaymentLine(null, DateTime(2026, 10, 1)), isNull);
      expect(lastPaymentLine(7999, null), isNull);
    });
  });

  test('SubscriptionPlan reads its Razorpay plan id', () {
    final plan = SubscriptionPlan.fromJson({
      'tier': 'pro',
      'name': 'Pro',
      'monthly_price_inr': 7999,
      'sort_order': 2,
      'razorpay_plan_id': 'plan_ProMonthly0001',
    });
    expect(plan.razorpayPlanId, 'plan_ProMonthly0001');
    expect(
        SubscriptionPlan.fromJson({
          'tier': 'pro',
          'name': 'Pro',
          'monthly_price_inr': 7999,
          'sort_order': 2,
        }).razorpayPlanId,
        isNull);
  });
}
```

Create `test/data/billing_repository_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:pasala/core/errors.dart';
import 'package:pasala/data/models/billing.dart';
import 'package:pasala/data/models/subscription.dart';
import 'package:pasala/data/repositories/billing_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A repository whose Edge Function calls go to [invoke]. The client is
/// never used by these tests: only the function path is exercised.
BillingRepository _repo(BillingFunctionInvoker invoke) => BillingRepository(
      SupabaseClient('http://localhost:54321', 'test-anon-key',
          authOptions: const AuthClientOptions(autoRefreshToken: false)),
      invoke: invoke,
    );

FunctionException _fx(int status, Object? details) =>
    FunctionException(status: status, details: details);

void main() {
  group('availability (the probe)', () {
    test('configured with plans', () async {
      final calls = <(String, Map<String, dynamic>)>[];
      final repo = _repo((name, body) async {
        calls.add((name, body));
        return {
          'configured': true,
          'plans': [
            {'tier': 'pro', 'name': 'Pro', 'monthly_price_inr': 7999},
          ],
        };
      });
      final a = await repo.availability('p1');
      expect(a.canPay, isTrue);
      expect(a.plans.single.tier, SubscriptionTier.pro);
      expect(calls.single.$1, 'billing-subscribe');
      expect(calls.single.$2, {'action': 'probe', 'property_id': 'p1'});
    });

    test('not configured stays manual', () async {
      final repo = _repo((_, _) async => {'configured': false});
      expect((await repo.availability('p1')).canPay, isFalse);
    });

    test('a function that is not deployed means not configured', () async {
      final repo = _repo((_, _) async => throw _fx(404, 'Not Found'));
      expect(await repo.availability('p1'), same(BillingAvailability.off));
    });

    test('a network failure means not configured, never an error', () async {
      final repo =
          _repo((_, _) async => throw http.ClientException('offline'));
      expect(await repo.availability('p1'), same(BillingAvailability.off));
    });
  });

  group('subscribe', () {
    test('sends the tier and reads the answer', () async {
      Map<String, dynamic>? sent;
      final repo = _repo((_, body) async {
        sent = body;
        return {
          'configured': true,
          'action': 'created',
          'subscription_id': 'sub_NewSub0000001',
          'short_url': 'https://rzp.io/i/new',
          'status': 'created',
        };
      });
      final r = await repo.subscribe('p1', SubscriptionTier.pro);
      expect(sent, {'action': 'subscribe', 'property_id': 'p1', 'tier': 'pro'});
      expect(r.action, SubscribeAction.created);
      expect(r.shortUrl, 'https://rzp.io/i/new');
    });

    test('P0038 from the database is BillingUnavailable', () async {
      final repo = _repo((_, _) async => throw _fx(409,
          {'error': 'db', 'code': 'P0038', 'message': 'billing_unavailable'}));
      await expectLater(repo.subscribe('p1', SubscriptionTier.enterprise),
          throwsA(isA<BillingUnavailable>()));
    });

    test('P0020 from the database is NotAMember', () async {
      final repo = _repo((_, _) async => throw _fx(409,
          {'error': 'db', 'code': 'P0020', 'message': 'not_a_member'}));
      await expectLater(repo.subscribe('p1', SubscriptionTier.pro),
          throwsA(isA<NotAMember>()));
    });

    test('Razorpay trouble is a readable InvalidState', () async {
      final repo = _repo((_, _) async => throw _fx(502,
          {'error': 'gateway', 'message': 'The plan id provided does not exist'}));
      await expectLater(
          repo.subscribe('p1', SubscriptionTier.pro),
          throwsA(isA<InvalidState>().having((e) => e.message, 'message',
              'Razorpay did not respond. Try again in a minute.')));
    });

    test('401 is NotPermitted', () async {
      final repo = _repo((_, _) async =>
          throw _fx(401, {'error': 'unauthorized', 'message': 'Sign in first.'}));
      await expectLater(repo.subscribe('p1', SubscriptionTier.pro),
          throwsA(isA<NotPermitted>()));
    });

    test('keys removed since the probe: BillingUnavailable', () async {
      final repo = _repo((_, _) async => {'configured': false});
      await expectLater(repo.subscribe('p1', SubscriptionTier.pro),
          throwsA(isA<BillingUnavailable>()));
    });

    test('offline is a NetworkFailure', () async {
      final repo =
          _repo((_, _) async => throw http.ClientException('offline'));
      await expectLater(repo.subscribe('p1', SubscriptionTier.pro),
          throwsA(isA<NetworkFailure>()));
    });
  });

  test('cancel reads the action', () async {
    Map<String, dynamic>? sent;
    final repo = _repo((_, body) async {
      sent = body;
      return {
        'configured': true,
        'action': 'cancel_scheduled',
        'subscription_id': 'sub_Current000001',
        'status': 'active',
      };
    });
    expect(await repo.cancel('p1'), CancelAction.cancelScheduled);
    expect(sent, {'action': 'cancel', 'property_id': 'p1'});
  });
}
```

Append to `test/core/errors_test.dart`, inside `main()` after the P0031 test:

```dart
  test('P0038 maps to BillingUnavailable with readable copy', () {
    final failure = map('P0038', 'billing_unavailable');
    expect(failure, isA<BillingUnavailable>());
    expect(failure.message,
        "Online payment isn't set up for this plan yet. Contact ResortHub.");
  });
```

- [ ] **Step 9: Run them to verify they fail**

Run: `flutter test test/data/billing_test.dart test/data/billing_repository_test.dart test/core/errors_test.dart`
Expected: FAIL to compile, with `Target of URI doesn't exist: 'package:pasala/data/models/billing.dart'` and `Undefined name 'BillingUnavailable'`.

- [ ] **Step 10: Add P0038 to the error mapping**

In `lib/core/errors.dart`, add after the `AlreadyDispatched` class:

```dart
/// P0038 -- `billing_subscribe_state`: the chosen tier has no Razorpay
/// plan id yet, so it cannot be paid online (P8). The server sends the
/// bare code word `billing_unavailable`, so the copy lives here.
class BillingUnavailable extends BookingFailure {
  const BillingUnavailable()
      : super("Online payment isn't set up for this plan yet. "
            'Contact ResortHub.');
}
```

In `mapPostgrestError`'s final `switch (code)`, add after `'P0031' => const AlreadyDispatched(),`:

```dart
    // P0038: subscription billing (0057). Bare code word, copy lives here.
    'P0038' => const BillingUnavailable(),
```

- [ ] **Step 11: Write the models**

In `lib/data/models/subscription.dart`, replace the `SubscriptionPlan` class with:

```dart
/// One row of `subscription_plans`.
class SubscriptionPlan {
  const SubscriptionPlan({
    required this.tier,
    required this.name,
    required this.monthlyPriceInr,
    required this.sortOrder,
    this.razorpayPlanId,
  });

  factory SubscriptionPlan.fromJson(Map<String, dynamic> json) =>
      SubscriptionPlan(
        tier: subscriptionTierFromDb(json['tier'] as String),
        name: json['name'] as String,
        monthlyPriceInr: _numFromDb(json['monthly_price_inr']) ?? 0,
        sortOrder: (json['sort_order'] as num).toInt(),
        razorpayPlanId: json['razorpay_plan_id'] as String?,
      );

  final SubscriptionTier tier;
  final String name;
  final num monthlyPriceInr;
  final int sortOrder;

  /// The Razorpay plan behind this tier (P8), or null while the tier is
  /// billed by hand.
  final String? razorpayPlanId;
}
```

Create `lib/data/models/billing.dart`:

```dart
import '../../core/format.dart';
import 'subscription.dart';

/// Razorpay's subscription states, as stored in
/// `billing_subscriptions.status` (0057_subscription_billing.sql).
enum GatewayStatus {
  created,
  authenticated,
  active,
  pending,
  halted,
  cancelled,
  completed,
  expired,
  paused,
}

/// Unknown text is rejected rather than defaulted, as in subscription.dart.
GatewayStatus gatewayStatusFromDb(String raw) => switch (raw) {
  'created' => GatewayStatus.created,
  'authenticated' => GatewayStatus.authenticated,
  'active' => GatewayStatus.active,
  'pending' => GatewayStatus.pending,
  'halted' => GatewayStatus.halted,
  'cancelled' => GatewayStatus.cancelled,
  'completed' => GatewayStatus.completed,
  'expired' => GatewayStatus.expired,
  'paused' => GatewayStatus.paused,
  _ => throw ArgumentError('Unknown billing status: $raw'),
};

extension GatewayStatusLabel on GatewayStatus {
  /// The short state the platform console shows after "Auto-pay: ".
  String get label => switch (this) {
    GatewayStatus.created => 'Waiting for authorisation',
    GatewayStatus.authenticated => 'Authorised',
    GatewayStatus.active => 'On',
    GatewayStatus.pending => 'Retrying a failed payment',
    GatewayStatus.halted => 'Stopped after failed payments',
    GatewayStatus.cancelled => 'Cancelled',
    GatewayStatus.completed => 'Finished',
    GatewayStatus.expired => 'Expired',
    GatewayStatus.paused => 'Paused',
  };
}

const _liveStatuses = {
  GatewayStatus.created,
  GatewayStatus.authenticated,
  GatewayStatus.active,
  GatewayStatus.pending,
  GatewayStatus.paused,
};

DateTime? _timeFromDb(Object? raw) =>
    raw == null ? null : DateTime.parse(raw as String).toLocal();

DateTime? _dateFromDb(Object? raw) {
  if (raw == null) return null;
  final parsed = DateTime.parse(raw as String);
  return DateTime(parsed.year, parsed.month, parsed.day);
}

num? _numFromDb(Object? raw) => switch (raw) {
  null => null,
  num n => n,
  String s => num.parse(s),
  _ => throw ArgumentError('Not a number: $raw'),
};

SubscriptionTier? _tierOrNull(Object? raw) =>
    raw == null ? null : subscriptionTierFromDb(raw as String);

GatewayStatus? _statusOrNull(Object? raw) =>
    raw == null ? null : gatewayStatusFromDb(raw as String);

/// The row `my_resort_billing(p_property)` returns: the resort's current
/// Razorpay subscription and its latest payment.
class ResortBilling {
  const ResortBilling({
    this.status,
    this.tier,
    this.shortUrl,
    this.cancelAtCycleEnd = false,
    this.currentEnd,
    this.lastPaymentAt,
    this.lastPaymentInr,
  });

  factory ResortBilling.fromRow(Map<String, dynamic> json) => ResortBilling(
    status: _statusOrNull(json['billing_status']),
    tier: _tierOrNull(json['billing_tier']),
    shortUrl: json['short_url'] as String?,
    cancelAtCycleEnd: json['cancel_at_cycle_end'] as bool? ?? false,
    currentEnd: _timeFromDb(json['current_end']),
    lastPaymentAt: _timeFromDb(json['last_payment_at']),
    lastPaymentInr: _numFromDb(json['last_payment_inr']),
  );

  /// Null when there is no current subscription (only past payments).
  final GatewayStatus? status;
  final SubscriptionTier? tier;
  final String? shortUrl;
  final bool cancelAtCycleEnd;

  /// The end of the cycle Razorpay last reported: the next charge.
  final DateTime? currentEnd;
  final DateTime? lastPaymentAt;
  final num? lastPaymentInr;

  /// A live subscription that is not already ending.
  bool get canCancel =>
      status != null && _liveStatuses.contains(status) && !cancelAtCycleEnd;
}

/// One row of `platform_billing()`, for the console.
class PlatformBilling {
  const PlatformBilling({
    required this.propertyId,
    this.status,
    this.tier,
    this.lastPaymentAt,
    this.lastPaymentInr,
  });

  factory PlatformBilling.fromRow(Map<String, dynamic> json) =>
      PlatformBilling(
        propertyId: json['property_id'] as String,
        status: _statusOrNull(json['billing_status']),
        tier: _tierOrNull(json['billing_tier']),
        lastPaymentAt: _timeFromDb(json['last_payment_at']),
        lastPaymentInr: _numFromDb(json['last_payment_inr']),
      );

  final String propertyId;
  final GatewayStatus? status;
  final SubscriptionTier? tier;
  final DateTime? lastPaymentAt;
  final num? lastPaymentInr;
}

/// One row of `subscription_invoices`: a successful Razorpay charge.
class SubscriptionInvoice {
  const SubscriptionInvoice({
    required this.id,
    required this.tier,
    required this.amountInr,
    required this.paidAt,
    this.periodStart,
    this.periodEnd,
  });

  factory SubscriptionInvoice.fromJson(Map<String, dynamic> json) =>
      SubscriptionInvoice(
        id: json['id'] as String,
        tier: subscriptionTierFromDb(json['tier'] as String),
        amountInr: _numFromDb(json['amount_inr']) ?? 0,
        paidAt: _timeFromDb(json['paid_at'])!,
        periodStart: _dateFromDb(json['period_start']),
        periodEnd: _dateFromDb(json['period_end']),
      );

  final String id;
  final SubscriptionTier tier;
  final num amountInr;
  final DateTime paidAt;
  final DateTime? periodStart;
  final DateTime? periodEnd;
}

/// The probe's answer: whether auto-pay can be offered, and on which plans.
class BillingAvailability {
  const BillingAvailability({required this.configured, this.plans = const []});

  /// Not configured: the plan stays manual and no billing UI is shown.
  static const off = BillingAvailability(configured: false);

  factory BillingAvailability.fromJson(Map<String, dynamic> json) {
    if (json['configured'] != true) return off;
    final raw = (json['plans'] as List<dynamic>?) ?? const [];
    return BillingAvailability(
      configured: true,
      plans: [
        for (final (i, p) in raw.cast<Map<String, dynamic>>().indexed)
          SubscriptionPlan(
            tier: subscriptionTierFromDb(p['tier'] as String),
            name: p['name'] as String,
            monthlyPriceInr: _numFromDb(p['monthly_price_inr']) ?? 0,
            sortOrder: i + 1,
          ),
      ],
    );
  }

  final bool configured;

  /// Only the tiers that have a Razorpay plan id, cheapest first.
  final List<SubscriptionPlan> plans;

  bool get canPay => configured && plans.isNotEmpty;
}

enum SubscribeAction { created, reused, unchanged }

/// billing-subscribe's answer to "subscribe".
class SubscribeResult {
  const SubscribeResult({
    required this.action,
    required this.subscriptionId,
    this.shortUrl,
    required this.status,
    this.warning,
  });

  factory SubscribeResult.fromJson(Map<String, dynamic> json) =>
      SubscribeResult(
        action: switch (json['action']) {
          'created' => SubscribeAction.created,
          'reused' => SubscribeAction.reused,
          'unchanged' => SubscribeAction.unchanged,
          final other => throw ArgumentError('Unknown subscribe action: $other'),
        },
        subscriptionId: json['subscription_id'] as String,
        shortUrl: json['short_url'] as String?,
        status: gatewayStatusFromDb(json['status'] as String),
        warning: json['warning'] as String?,
      );

  final SubscribeAction action;
  final String subscriptionId;

  /// Razorpay's hosted page where the owner authorises auto-pay.
  final String? shortUrl;
  final GatewayStatus status;
  final String? warning;
}

enum CancelAction { cancelScheduled, cancelled, none }

CancelAction cancelActionFromWire(Object? raw) => switch (raw) {
  'cancel_scheduled' => CancelAction.cancelScheduled,
  'cancelled' => CancelAction.cancelled,
  'none' => CancelAction.none,
  _ => throw ArgumentError('Unknown cancel action: $raw'),
};

/// One line describing [billing]'s auto-pay state, always in words.
String billingStatusLine(ResortBilling billing) {
  final end = billing.currentEnd;
  return switch (billing.status) {
    null => 'No auto-pay set up',
    GatewayStatus.created => 'Waiting for you to authorise auto-pay',
    GatewayStatus.authenticated =>
      'Auto-pay authorised · first charge when your current period ends',
    GatewayStatus.active when billing.cancelAtCycleEnd => end == null
        ? 'Auto-pay ends with this period'
        : 'Auto-pay ends on ${formatDate(end)}',
    GatewayStatus.active =>
      end == null ? 'Auto-pay on' : 'Auto-pay on · next charge ${formatDate(end)}',
    GatewayStatus.pending => 'A payment failed · Razorpay is retrying',
    GatewayStatus.halted => 'Auto-pay stopped after failed payments',
    GatewayStatus.cancelled => 'Auto-pay cancelled',
    GatewayStatus.completed => 'Auto-pay finished',
    GatewayStatus.expired => 'The auto-pay link expired',
    GatewayStatus.paused => 'Auto-pay paused',
  };
}

/// "Last payment ₹7,999 on 1 Oct 2026", or null without both parts.
String? lastPaymentLine(num? amountInr, DateTime? paidAt) =>
    amountInr == null || paidAt == null
        ? null
        : 'Last payment ${formatInr(amountInr)} on ${formatDate(paidAt)}';
```

- [ ] **Step 12: Write the repositories**

Create `lib/data/repositories/billing_repository.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors.dart';
import '../../core/supabase_client.dart';
import '../models/billing.dart';
import '../models/subscription.dart';

/// Calls an Edge Function with a JSON body and returns its decoded JSON
/// body. Throws [FunctionException] on a non-2xx answer, as
/// `SupabaseClient.functions.invoke` does.
typedef BillingFunctionInvoker = Future<Object?> Function(
    String name, Map<String, dynamic> body);

/// The Edge Function behind every billing action
/// (supabase/functions/billing-subscribe).
const billingFunctionName = 'billing-subscribe';

/// Auto-pay for one resort's ResortHub plan (P8), for its owner. Tests
/// override [billingSourceProvider] with `FakeBillingSource`
/// (test/support/fake_billing_source.dart).
abstract class BillingSource {
  /// Whether auto-pay can be offered. Never throws: any failure means "not
  /// configured", and the plan stays manual exactly as before.
  Future<BillingAvailability> availability(String propertyId);

  /// Null when the resort never had auto-pay or a payment.
  Future<ResortBilling?> billing(String propertyId);

  /// Newest first, at most 12.
  Future<List<SubscriptionInvoice>> invoices(String propertyId);

  Future<SubscribeResult> subscribe(String propertyId, SubscriptionTier tier);

  Future<CancelAction> cancel(String propertyId);
}

/// Maps a billing-subscribe error body (`{error, code?, message}`) or any
/// other error to a [BookingFailure].
BookingFailure billingFailureFor(Object error) {
  if (error is FunctionException) {
    final details = error.details;
    final body = details is Map ? details : const <String, dynamic>{};
    final code = body['code'];
    return switch (body['error']) {
      'db' when code is String => mapPostgrestError(
          PostgrestException(message: '${body['message'] ?? ''}', code: code)),
      'gateway' =>
        const InvalidState('Razorpay did not respond. Try again in a minute.'),
      _ when error.status == 401 => const NotPermitted(),
      _ => UnknownFailure('billing-subscribe answered ${error.status}'),
    };
  }
  return mapPostgrestError(error);
}

/// Reads `my_resort_billing` and `subscription_invoices`, and drives the
/// billing-subscribe Edge Function (0057_subscription_billing.sql).
class BillingRepository implements BillingSource {
  BillingRepository(this._db, {BillingFunctionInvoker? invoke})
      : _invoke = invoke;

  final SupabaseClient _db;
  final BillingFunctionInvoker? _invoke;

  Future<Object?> _call(Map<String, dynamic> body) async {
    final invoke = _invoke;
    if (invoke != null) return invoke(billingFunctionName, body);
    final response = await _db.functions.invoke(billingFunctionName, body: body);
    return response.data;
  }

  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } catch (e) {
      throw billingFailureFor(e);
    }
  }

  @override
  Future<BillingAvailability> availability(String propertyId) async {
    try {
      final data = await _call({'action': 'probe', 'property_id': propertyId});
      return data is Map<String, dynamic>
          ? BillingAvailability.fromJson(data)
          : BillingAvailability.off;
    } catch (_) {
      return BillingAvailability.off;
    }
  }

  @override
  Future<ResortBilling?> billing(String propertyId) => _guard(() async {
    final rows = await _db.rpc(
      'my_resort_billing',
      params: {'p_property': propertyId},
    ) as List<dynamic>;
    return rows.isEmpty
        ? null
        : ResortBilling.fromRow(rows.first as Map<String, dynamic>);
  });

  @override
  Future<List<SubscriptionInvoice>> invoices(String propertyId) =>
      _guard(() async {
        final rows = await _db
            .from('subscription_invoices')
            .select('id, tier, amount_inr, paid_at, period_start, period_end')
            .eq('property_id', propertyId)
            .order('paid_at', ascending: false)
            .limit(12);
        return rows.map(SubscriptionInvoice.fromJson).toList();
      });

  @override
  Future<SubscribeResult> subscribe(
    String propertyId,
    SubscriptionTier tier,
  ) => _guard(() async {
    final json = await _call({
      'action': 'subscribe',
      'property_id': propertyId,
      'tier': subscriptionTierToDb(tier),
    }) as Map<String, dynamic>;
    if (json['configured'] != true) throw const BillingUnavailable();
    return SubscribeResult.fromJson(json);
  });

  @override
  Future<CancelAction> cancel(String propertyId) => _guard(() async {
    final json = await _call({'action': 'cancel', 'property_id': propertyId})
        as Map<String, dynamic>;
    if (json['configured'] != true) throw const BillingUnavailable();
    return cancelActionFromWire(json['action']);
  });
}

final billingRepositoryProvider = Provider<BillingRepository>(
  (ref) => BillingRepository(ref.watch(supabaseProvider)),
);

/// The [BillingSource] seam every screen calls through.
final billingSourceProvider = Provider<BillingSource>(
  (ref) => ref.watch(billingRepositoryProvider),
);

/// Keyed by property id; `autoDispose`, so Settings asks again every time
/// it opens (secrets may have been set since).
final billingAvailabilityProvider = FutureProvider.autoDispose
    .family<BillingAvailability, String>(
      (ref, propertyId) =>
          ref.watch(billingSourceProvider).availability(propertyId),
    );

final resortBillingProvider = FutureProvider.autoDispose
    .family<ResortBilling?, String>(
      (ref, propertyId) => ref.watch(billingSourceProvider).billing(propertyId),
    );

final subscriptionInvoicesProvider = FutureProvider.autoDispose
    .family<List<SubscriptionInvoice>, String>(
      (ref, propertyId) =>
          ref.watch(billingSourceProvider).invoices(propertyId),
    );
```

In `lib/data/repositories/platform_repository.dart`:

1. Add `import '../models/billing.dart';` after `import '../../core/supabase_client.dart';`.
2. In `abstract class PlatformSource`, add after `Future<void> setPlanPrice(SubscriptionTier tier, num monthlyPriceInr);`:

```dart

  /// Auto-pay state and last payment per resort (`platform_billing()`),
  /// only for resorts that ever had auto-pay or a payment (P8).
  Future<List<PlatformBilling>> billing();

  /// Sets or clears (null) the Razorpay plan behind [tier]
  /// (`set_plan_razorpay_id`).
  Future<void> setRazorpayPlanId(SubscriptionTier tier, String? planId);
```

3. In `PlatformRepository.plans()`, change the select string to `'tier, name, monthly_price_inr, sort_order, razorpay_plan_id'`.
4. In `class PlatformRepository`, add after `setPlanPrice`:

```dart

  @override
  Future<List<PlatformBilling>> billing() => _guard(() async {
    final rows = await _db.rpc('platform_billing') as List<dynamic>;
    return rows
        .map((e) => PlatformBilling.fromRow(e as Map<String, dynamic>))
        .toList();
  });

  @override
  Future<void> setRazorpayPlanId(SubscriptionTier tier, String? planId) =>
      _guard(() async {
        await _db.rpc(
          'set_plan_razorpay_id',
          params: {'p_tier': subscriptionTierToDb(tier), 'p_plan_id': planId ?? ''},
        );
      });
```

5. At the end of the file, add:

```dart

/// Billing per resort, keyed by property id. A resort without an entry
/// never had auto-pay.
final platformBillingProvider = FutureProvider<Map<String, PlatformBilling>>(
  (ref) async => {
    for (final b in await ref.watch(platformSourceProvider).billing())
      b.propertyId: b,
  },
);
```

- [ ] **Step 13: Write the fakes**

In `test/support/fake_platform_source.dart`:

1. Add `import 'package:pasala/data/models/billing.dart';` as the first import.
2. In `class FakePlatformSource`, add after `Object? priceError;`:

```dart
  List<PlatformBilling> billingList = [];
  Object? billingError;
  Object? planIdError;
  int billingCalls = 0;
  final List<(SubscriptionTier, String?)> planIdCalls = [];
```

3. In `setPlanPrice`, keep the plan id when a price changes. Replace the `SubscriptionPlan(...)` inside it with:

```dart
            ? SubscriptionPlan(
                tier: p.tier,
                name: p.name,
                monthlyPriceInr: monthlyPriceInr,
                sortOrder: p.sortOrder,
                razorpayPlanId: p.razorpayPlanId,
              )
```

4. Add at the end of the class:

```dart

  @override
  Future<List<PlatformBilling>> billing() async {
    billingCalls++;
    if (billingError != null) throw billingError!;
    return List.of(billingList);
  }

  @override
  Future<void> setRazorpayPlanId(SubscriptionTier tier, String? planId) async {
    planIdCalls.add((tier, planId));
    if (planIdError != null) throw planIdError!;
    planList = [
      for (final p in planList)
        p.tier == tier
            ? SubscriptionPlan(
                tier: p.tier,
                name: p.name,
                monthlyPriceInr: p.monthlyPriceInr,
                sortOrder: p.sortOrder,
                razorpayPlanId: planId,
              )
            : p,
    ];
  }
```

Create `test/support/fake_billing_source.dart`:

```dart
import 'dart:async';

import 'package:pasala/data/models/billing.dart';
import 'package:pasala/data/models/subscription.dart';
import 'package:pasala/data/repositories/billing_repository.dart';

import 'fake_platform_source.dart';

/// Auto-pay offered on Starter and Pro at the placeholder prices.
final billablePlans = BillingAvailability(
  configured: true,
  plans: [defaultPlans[0], defaultPlans[1]],
);

/// A billing row for tests: Pro auto-pay on, charged 1 Oct 2026, next
/// charge 1 Nov 2026.
ResortBilling resortBilling({
  GatewayStatus? status = GatewayStatus.active,
  SubscriptionTier? tier = SubscriptionTier.pro,
  bool cancelAtCycleEnd = false,
  DateTime? currentEnd,
  DateTime? lastPaymentAt,
  num? lastPaymentInr = 7999,
}) => ResortBilling(
  status: status,
  tier: tier,
  shortUrl: 'https://rzp.io/i/current',
  cancelAtCycleEnd: cancelAtCycleEnd,
  currentEnd: currentEnd ?? DateTime(2026, 11, 1),
  lastPaymentAt: lastPaymentAt ?? DateTime(2026, 10, 1),
  lastPaymentInr: lastPaymentInr,
);

SubscriptionInvoice subscriptionInvoice({
  String id = 'i1',
  SubscriptionTier tier = SubscriptionTier.pro,
  num amountInr = 7999,
  DateTime? paidAt,
}) => SubscriptionInvoice(
  id: id,
  tier: tier,
  amountInr: amountInr,
  paidAt: paidAt ?? DateTime(2026, 10, 1),
);

/// In-memory [BillingSource]. Set the `...Value`/`...Result` fields for what
/// the server would answer, an `...Error` to make that call throw, and
/// [hold] to keep `subscribe` in flight until it completes. The call logs
/// record every property id (and tier) asked for.
class FakeBillingSource implements BillingSource {
  BillingAvailability availabilityValue = BillingAvailability.off;
  ResortBilling? billingValue;
  List<SubscriptionInvoice> invoiceList = [];
  SubscribeResult subscribeResult = const SubscribeResult(
    action: SubscribeAction.created,
    subscriptionId: 'sub_TestSub000001',
    shortUrl: 'https://rzp.io/i/test',
    status: GatewayStatus.created,
  );
  CancelAction cancelResult = CancelAction.cancelScheduled;

  Object? billingError;
  Object? invoicesError;
  Object? subscribeError;
  Object? cancelError;
  Completer<void>? hold;

  final List<String> availabilityCalls = [];
  final List<String> billingCalls = [];
  final List<String> invoiceCalls = [];
  final List<(String, SubscriptionTier)> subscribeCalls = [];
  final List<String> cancelCalls = [];

  @override
  Future<BillingAvailability> availability(String propertyId) async {
    availabilityCalls.add(propertyId);
    return availabilityValue;
  }

  @override
  Future<ResortBilling?> billing(String propertyId) async {
    billingCalls.add(propertyId);
    if (billingError != null) throw billingError!;
    return billingValue;
  }

  @override
  Future<List<SubscriptionInvoice>> invoices(String propertyId) async {
    invoiceCalls.add(propertyId);
    if (invoicesError != null) throw invoicesError!;
    return List.of(invoiceList);
  }

  @override
  Future<SubscribeResult> subscribe(
    String propertyId,
    SubscriptionTier tier,
  ) async {
    subscribeCalls.add((propertyId, tier));
    await hold?.future;
    if (subscribeError != null) throw subscribeError!;
    return subscribeResult;
  }

  @override
  Future<CancelAction> cancel(String propertyId) async {
    cancelCalls.add(propertyId);
    if (cancelError != null) throw cancelError!;
    return cancelResult;
  }
}
```

- [ ] **Step 14: Run the Dart tests and the analyzer**

Run: `flutter test test/data/billing_test.dart test/data/billing_repository_test.dart test/core/errors_test.dart test/data/subscription_test.dart test/data/platform_providers_test.dart test/features/platform test/features/owner`
Expected: PASS. The existing platform and owner tests still pass, because the fake gained methods and `SubscriptionPlan` gained only an optional field.

Run: `flutter analyze`
Expected: no issues beyond the baseline.

- [ ] **Step 15: Commit**

```bash
git add supabase/migrations/0057_subscription_billing.sql supabase/tests/47_subscription_billing_test.sql \
  supabase/tests/37_tenancy_isolation_test.sql supabase/functions/_shared/billing/types.ts \
  lib/data/models/billing.dart lib/data/models/subscription.dart \
  lib/data/repositories/billing_repository.dart lib/data/repositories/platform_repository.dart \
  lib/core/errors.dart test/support/fake_billing_source.dart test/support/fake_platform_source.dart \
  test/data/billing_test.dart test/data/billing_repository_test.dart test/core/errors_test.dart
git commit -m "$(cat <<'EOF'
feat(billing): subscription auto-billing contract (schema, stubs, Dart and Deno types)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

## Phase 1: Database track (Tasks 2 → 3 → 4, sequential)

### Task 2: Plan ids and the reads

**Track:** DB. **Depends on:** Task 1.

**Files:**
- Modify: `supabase/migrations/0057_subscription_billing.sql` (replace the bodies of `set_plan_razorpay_id`, `my_resort_billing`, `platform_billing` and `billing_subscribe_state`)
- Test: `supabase/tests/47_subscription_billing_test.sql` (append the Task 2 section)

**Interfaces:**
- Consumes: Task 1's tables and signatures; `assert_resort_role`, `is_platform_admin`, `audit_log (actor_id, entity, entity_id, action, before, after, property_id)`.
- Produces:
  - `set_plan_razorpay_id`: P0008 / P0005 / P0002, trims, blank clears, no-op on the same value, one audit row per change (entity `subscription_plan`, action `razorpay_plan:<old|none>-><new|none>`).
  - `billing_subscribe_state` jsonb keys: `property_id, property_name, caller_id, notify_email, tier, plan_id, start_at, current, stale`.
    - `current` is `null` or `{razorpay_subscription_id, tier, status, short_url, cancel_at_cycle_end}`.
    - `stale` is a JSON array of subscription ids.
    - `start_at` is a JSON number (unix seconds) or `null`.
  - `my_resort_billing`: zero or one row. `platform_billing`: one row per resort with a current subscription or an invoice, ordered by resort creation and name.

- [ ] **Step 1: Write the failing tests**

In `supabase/tests/47_subscription_billing_test.sql`, change `select plan(20);` to `select plan(50);`, and insert before `select * from finish();`:

```sql
-- === Task 2: plan ids and the reads ========================================

set local role authenticated;
set local request.jwt.claims to '{"sub":"b8000000-0000-0000-0000-000000000002","role":"authenticated"}';
select throws_ok($$select public.set_plan_razorpay_id('pro', 'plan_ProMonthly0001')$$,
  'P0008', null, 'only the platform admin sets a plan id');
set local request.jwt.claims to '{"sub":"b8000000-0000-0000-0000-000000000001","role":"authenticated"}';
select throws_ok($$select public.set_plan_razorpay_id('pro', 'pro-monthly')$$,
  'P0005', null, 'a malformed plan id is refused with a message for the admin');
select lives_ok($$select public.set_plan_razorpay_id('pro', ' plan_ProMonthly0001 ')$$,
  'the platform admin sets Pro''s plan id (trimmed)');
select lives_ok($$select public.set_plan_razorpay_id('pro', 'plan_ProMonthly0001')$$,
  'setting the same id again is a no-op');
select throws_ok($$select public.set_plan_razorpay_id('starter', 'plan_ProMonthly0001')$$,
  'P0005', null, 'one Razorpay plan cannot back two tiers');
select lives_ok($$select public.set_plan_razorpay_id('starter', 'plan_StarterMon001')$$,
  'Starter gets its own plan id');
select lives_ok($$select public.set_plan_razorpay_id('enterprise', '')$$,
  'a blank id leaves Enterprise billed by hand');
reset role;
set local request.jwt.claims to '';
select is((select array_agg(tier::text || ':' || coalesce(razorpay_plan_id, '-') order by sort_order)
             from public.subscription_plans),
  array['starter:plan_StarterMon001','pro:plan_ProMonthly0001','enterprise:-'],
  'the plan ids are stored');
select is((select count(*)::int from public.audit_log
            where entity = 'subscription_plan' and action like 'razorpay_plan:%'),
  2, 'each real change is audited once; the no-ops are not');

-- billing_subscribe_state, as the owner.
set local role authenticated;
set local request.jwt.claims to '{"sub":"b8000000-0000-0000-0000-000000000002","role":"authenticated"}';
select throws_ok($$select public.billing_subscribe_state('b8100000-0000-4000-8000-000000000001', 'enterprise')$$,
  'P0038', null, 'a tier without a Razorpay plan cannot be paid online');
select is(public.billing_subscribe_state('b8100000-0000-4000-8000-000000000001', 'pro') ->> 'plan_id',
  'plan_ProMonthly0001', 'the state carries the tier''s plan id');
select is((public.billing_subscribe_state('b8100000-0000-4000-8000-000000000001', 'pro') ->> 'start_at')::bigint,
  pg_temp.ist(pg_temp.today() + 11),
  'a trial resort''s auto-pay starts the day after the trial ends (midnight IST)');
select is(public.billing_subscribe_state('b8100000-0000-4000-8000-000000000001', 'pro')
            - array['property_id','property_name','caller_id','notify_email','tier','plan_id','start_at'],
  '{"current": null, "stale": []}'::jsonb, 'no current subscription and nothing stale yet');
select is((select jsonb_build_object('email', s -> 'notify_email', 'caller', s -> 'caller_id',
                                     'name', s -> 'property_name')
             from public.billing_subscribe_state('b8100000-0000-4000-8000-000000000001', 'pro') s),
  '{"email": "bill-owner@example.com", "caller": "b8000000-0000-0000-0000-000000000002", "name": "Bill Trial"}'::jsonb,
  'the state names the owner to notify and the resort');
select is(public.billing_subscribe_state('b8100000-0000-4000-8000-000000000003', 'starter') -> 'start_at',
  'null'::jsonb,
  'a suspended resort''s owner can still set up auto-pay; no end date means it starts now');
select is(public.billing_subscribe_state('b8100000-0000-4000-8000-000000000004', 'pro') -> 'start_at',
  'null'::jsonb, 'a lapsed plan starts auto-pay straight away');
select is(public.billing_subscribe_state('b8100000-0000-4000-8000-000000000001') -> 'plan_id',
  'null'::jsonb, 'without a tier (a cancel) no plan id is needed');
set local request.jwt.claims to '{"sub":"b8000000-0000-0000-0000-000000000003","role":"authenticated"}';
select throws_ok($$select public.billing_subscribe_state('b8100000-0000-4000-8000-000000000001', 'pro')$$,
  'P0020', null, 'an admin cannot start auto-pay (owner only)');
set local request.jwt.claims to '{"sub":"b8000000-0000-0000-0000-000000000004","role":"authenticated"}';
select throws_ok($$select public.billing_subscribe_state('b8100000-0000-4000-8000-000000000001', 'pro')$$,
  'P0020', null, 'staff cannot start auto-pay');
set local request.jwt.claims to '{"sub":"b8000000-0000-0000-0000-000000000006","role":"authenticated"}';
select throws_ok($$select public.billing_subscribe_state('b8100000-0000-4000-8000-000000000001', 'pro')$$,
  'P0020', null, 'a guest cannot start auto-pay');
set local request.jwt.claims to '{"sub":"b8000000-0000-0000-0000-000000000001","role":"authenticated"}';
select throws_ok($$select public.billing_subscribe_state('b8100000-0000-4000-8000-000000000001', 'pro')$$,
  'P0020', null, 'the platform admin cannot start a resort''s auto-pay');
set local request.jwt.claims to '{"sub":"b8000000-0000-0000-0000-000000000005","role":"authenticated"}';
select throws_ok($$select public.billing_subscribe_state('b8100000-0000-4000-8000-000000000001', 'pro')$$,
  'P0020', null, 'another resort''s owner cannot start it');
select is((public.billing_subscribe_state('b8100000-0000-4000-8000-000000000002', 'pro') ->> 'start_at')::bigint,
  pg_temp.ist(pg_temp.today() + 6),
  'a paid resort''s auto-pay starts the day after its paid period');

-- The reads, over a current subscription, a replaced one still live, and
-- two payments.
reset role;
set local request.jwt.claims to '';
insert into public.billing_subscriptions
  (id, property_id, tier, razorpay_plan_id, razorpay_subscription_id, status, superseded_at)
values ('b8200000-0000-4000-8000-000000000011', 'b8100000-0000-4000-8000-000000000001',
        'starter', 'plan_StarterMon001', 'sub_ReadOld000001', 'active', now());
insert into public.billing_subscriptions
  (id, property_id, tier, razorpay_plan_id, razorpay_subscription_id, status, short_url, current_end)
values ('b8200000-0000-4000-8000-000000000012', 'b8100000-0000-4000-8000-000000000001',
        'pro', 'plan_ProMonthly0001', 'sub_ReadCheck00001', 'active', 'https://rzp.io/i/read',
        now() + interval '20 days');
insert into public.subscription_invoices
  (billing_subscription_id, tier, razorpay_payment_id, amount_inr, paid_at)
values
  ('b8200000-0000-4000-8000-000000000011', 'starter', 'pay_ReadOld000001', 2999, now() - interval '40 days'),
  ('b8200000-0000-4000-8000-000000000012', 'pro', 'pay_ReadNew000001', 7999, now() - interval '10 days');

set local role authenticated;
set local request.jwt.claims to '{"sub":"b8000000-0000-0000-0000-000000000002","role":"authenticated"}';
select is((select jsonb_build_object('current', s -> 'current' -> 'razorpay_subscription_id',
                                     'stale', s -> 'stale')
             from public.billing_subscribe_state('b8100000-0000-4000-8000-000000000001', 'pro') s),
  '{"current": "sub_ReadCheck00001", "stale": ["sub_ReadOld000001"]}'::jsonb,
  'the state names the current subscription and the replaced one still live');
select is((select billing_status || '|' || billing_tier::text || '|' || cancel_at_cycle_end::text
                  || '|' || last_payment_inr::text
             from public.my_resort_billing('b8100000-0000-4000-8000-000000000001')),
  'active|pro|false|7999.00', 'the owner reads auto-pay state and the latest payment');
select is((select count(*)::int from public.my_resort_billing('b8100000-0000-4000-8000-000000000005')),
  0, 'a resort that never had auto-pay has no billing row');
set local request.jwt.claims to '{"sub":"b8000000-0000-0000-0000-000000000003","role":"authenticated"}';
select throws_ok($$select * from public.my_resort_billing('b8100000-0000-4000-8000-000000000001')$$,
  'P0020', null, 'an admin cannot read billing (owner only)');
set local request.jwt.claims to '{"sub":"b8000000-0000-0000-0000-000000000002","role":"authenticated"}';
select throws_ok($$select * from public.platform_billing()$$,
  'P0008', null, 'only the platform admin reads the console''s billing');
set local request.jwt.claims to '{"sub":"b8000000-0000-0000-0000-000000000001","role":"authenticated"}';
select is((select array_agg(property_id::text) from public.platform_billing()),
  array['b8100000-0000-4000-8000-000000000001'],
  'the console lists only resorts with auto-pay or payments');
select is((select billing_status || '|' || last_payment_inr::text from public.platform_billing()),
  'active|7999.00', 'the console sees the latest payment');
reset role;
set local request.jwt.claims to '';
delete from public.billing_subscriptions;
```

- [ ] **Step 2: Run them to verify they fail**

Run: `supabase test db supabase/tests/47_subscription_billing_test.sql`
Expected: FAIL. The first Task 2 `throws_ok` reports `caught: 0A000: set_plan_razorpay_id is not implemented yet` where P0008 was wanted, and later assertions error the same way.

- [ ] **Step 3: Write the four bodies**

In `supabase/migrations/0057_subscription_billing.sql`, replace each of the four stubs (header and body; keep the grants at the end of the file) with:

```sql
-- The platform admin sets or clears (blank) the Razorpay plan behind a
-- tier (spec decision 3). A platform event: the audit row has no
-- property_id.
create function public.set_plan_razorpay_id(
  p_tier    public.subscription_tier,
  p_plan_id text
) returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_old public.subscription_plans;
  v_id  text := nullif(btrim(p_plan_id), '');
begin
  if not public.is_platform_admin() then
    raise exception 'not permitted' using errcode = 'P0008';
  end if;

  if p_tier is null then
    raise exception 'Choose a plan.' using errcode = 'P0005';
  end if;

  if v_id is not null and v_id !~ '^plan_[A-Za-z0-9]{6,40}$' then
    raise exception 'A Razorpay plan id looks like plan_ followed by letters and digits.'
      using errcode = 'P0005';
  end if;

  select * into v_old from public.subscription_plans where tier = p_tier for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'not_found';
  end if;

  if v_old.razorpay_plan_id is not distinct from v_id then
    return;
  end if;

  if v_id is not null and exists (
       select 1 from public.subscription_plans
        where razorpay_plan_id = v_id and tier <> p_tier) then
    raise exception 'That Razorpay plan id is already used by another plan.'
      using errcode = 'P0005';
  end if;

  update public.subscription_plans
     set razorpay_plan_id = v_id,
         updated_at = now()
   where tier = p_tier;

  insert into public.audit_log (actor_id, entity, entity_id, action, before, after, property_id)
  values (auth.uid(), 'subscription_plan', v_old.id,
          'razorpay_plan:' || coalesce(v_old.razorpay_plan_id, 'none') || '->' || coalesce(v_id, 'none'),
          jsonb_build_object('razorpay_plan_id', v_old.razorpay_plan_id),
          jsonb_build_object('razorpay_plan_id', v_id),
          null);
end;
$$;

-- The resort's current auto-pay and its latest payment, for its owner
-- only (spec decision 4). A read, so it works at a suspended resort.
-- Zero rows when the resort never had auto-pay or a payment.
create function public.my_resort_billing(p_property uuid)
returns table(
  billing_status      text,
  billing_tier        public.subscription_tier,
  short_url           text,
  cancel_at_cycle_end boolean,
  current_end         timestamptz,
  last_payment_at     timestamptz,
  last_payment_inr    numeric
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  perform public.assert_resort_role(p_property, false, 'owner');

  return query
    select b.status, b.tier, b.short_url, coalesce(b.cancel_at_cycle_end, false),
           b.current_end, i.paid_at, i.amount_inr
      from (select 1) as one
      left join public.billing_subscriptions b
        on b.property_id = p_property and b.superseded_at is null
      left join lateral (
        select si.paid_at, si.amount_inr
          from public.subscription_invoices si
         where si.property_id = p_property
         order by si.paid_at desc
         limit 1
      ) i on true
     where b.id is not null or i.paid_at is not null;
end;
$$;

-- The console's billing column (spec decision 16): per resort, the
-- current auto-pay state and the latest payment. Only resorts that ever
-- had auto-pay or a payment.
create function public.platform_billing()
returns table(
  property_id      uuid,
  billing_status   text,
  billing_tier     public.subscription_tier,
  last_payment_at  timestamptz,
  last_payment_inr numeric
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
    select p.id, b.status, b.tier, i.paid_at, i.amount_inr
      from public.properties p
      left join public.billing_subscriptions b
        on b.property_id = p.id and b.superseded_at is null
      left join lateral (
        select si.paid_at, si.amount_inr
          from public.subscription_invoices si
         where si.property_id = p.id
         order by si.paid_at desc
         limit 1
      ) i on true
     where b.id is not null or i.paid_at is not null
     order by p.created_at, p.name;
end;
$$;

-- Everything billing-subscribe needs to decide, read as the owner (spec
-- decisions 4, 6, 8 and 14). Read mode, so a suspended resort's owner can
-- still pay. With a tier that has no Razorpay plan: P0038. start_at is
-- midnight Asia/Kolkata after the trial or paid period, when that period
-- has not ended yet; otherwise null (start now).
create function public.billing_subscribe_state(
  p_property uuid,
  p_tier     public.subscription_tier default null
) returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_name    text;
  v_plan_id text;
  v_sub     public.resort_subscriptions;
  v_cur     public.billing_subscriptions;
  v_today   date := (now() at time zone 'Asia/Kolkata')::date;
  v_end     date;
  v_start   timestamptz;
begin
  perform public.assert_resort_role(p_property, false, 'owner');

  select name into v_name from public.properties where id = p_property;

  if p_tier is not null then
    select razorpay_plan_id into v_plan_id
      from public.subscription_plans where tier = p_tier;
    if v_plan_id is null then
      raise exception using errcode = 'P0038', message = 'billing_unavailable';
    end if;
  end if;

  select * into v_sub from public.resort_subscriptions where property_id = p_property;
  v_end := case v_sub.status
             when 'trial' then v_sub.trial_ends_on
             when 'active' then v_sub.paid_through
           end;
  if v_end is not null and v_end >= v_today then
    v_start := (v_end + 1)::timestamp at time zone 'Asia/Kolkata';
  end if;

  select * into v_cur from public.billing_subscriptions
   where property_id = p_property and superseded_at is null;

  return jsonb_build_object(
    'property_id', p_property,
    'property_name', v_name,
    'caller_id', auth.uid(),
    'notify_email', (select u.email::text from auth.users u where u.id = auth.uid()),
    'tier', p_tier,
    'plan_id', v_plan_id,
    'start_at', case when v_start is null then null
                     else extract(epoch from v_start)::bigint end,
    'current', case when v_cur.id is null then null else jsonb_build_object(
        'razorpay_subscription_id', v_cur.razorpay_subscription_id,
        'tier', v_cur.tier,
        'status', v_cur.status,
        'short_url', v_cur.short_url,
        'cancel_at_cycle_end', v_cur.cancel_at_cycle_end) end,
    'stale', coalesce((
        select jsonb_agg(b.razorpay_subscription_id order by b.created_at)
          from public.billing_subscriptions b
         where b.property_id = p_property
           and b.superseded_at is not null
           and b.status in ('created','authenticated','active','pending','paused')),
      '[]'::jsonb));
end;
$$;
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `supabase db reset && supabase test db supabase/tests/47_subscription_billing_test.sql supabase/tests/37_tenancy_isolation_test.sql`
Expected: 47 passes 50/50, and 37 passes as in the baseline.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/0057_subscription_billing.sql supabase/tests/47_subscription_billing_test.sql
git commit -m "$(cat <<'EOF'
feat(billing): plan ids, the owner's billing state and the console's billing read

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: Opening and cancelling subscriptions

**Track:** DB. **Depends on:** Task 2.

**Files:**
- Modify: `supabase/migrations/0057_subscription_billing.sql` (replace the bodies of `billing_subscription_opened` and `billing_subscription_cancel_requested`)
- Test: `supabase/tests/47_subscription_billing_test.sql` (append the Task 3 section)

**Interfaces:**
- Consumes: Task 2's `billing_subscribe_state` (the test reads `current.cancel_at_cycle_end` and `stale` through it).
- Produces:
  - `billing_subscription_opened(...)` returns `{"id": "<uuid>", "stale": [<sub ids>]}`.
    - It supersedes the resort's current row and inserts the new one as current, under a per-resort advisory lock.
    - It is idempotent for a known id. The same id at another resort gives P0021. Missing arguments give P0005; an unknown resort gives P0002.
    - It writes audit `billing:opened <sub> <tier>`.
  - `billing_subscription_cancel_requested(...)`:
    - sets `cancel_at_cycle_end` and a known Razorpay `status` (unknown text keeps the stored one)
    - gives P0002 for an unknown id
    - writes audit `billing:cancel_requested <sub>`

- [ ] **Step 1: Write the failing tests**

In `supabase/tests/47_subscription_billing_test.sql`, change `select plan(50);` to `select plan(67);`, and insert before `select * from finish();`:

```sql
-- === Task 3: opening and cancelling subscriptions ==========================

set local role authenticated;
set local request.jwt.claims to '{"sub":"b8000000-0000-0000-0000-000000000002","role":"authenticated"}';
select throws_ok($$select public.billing_subscription_opened('b8100000-0000-4000-8000-000000000001',
    'starter', 'plan_StarterMon001', 'sub_FirstOpen00001', 'created', null, null,
    'b8000000-0000-0000-0000-000000000002')$$,
  '42501', null, 'a signed-in user cannot record a subscription');
select throws_ok($$select public.billing_subscription_cancel_requested('sub_FirstOpen00001', true, 'active')$$,
  '42501', null, 'a signed-in user cannot record a cancellation');
reset role;
set local request.jwt.claims to '';

set local role service_role;
select throws_ok($$select public.billing_subscription_opened('b8100000-0000-4000-8000-000000000001',
    null, 'plan_StarterMon001', 'sub_FirstOpen00001', 'created', null, null, null)$$,
  'P0005', null, 'a tier is required');
select throws_ok($$select public.billing_subscription_opened('b8100000-0000-4000-8000-0000000000ff',
    'starter', 'plan_StarterMon001', 'sub_FirstOpen00001', 'created', null, null, null)$$,
  'P0002', null, 'an unknown resort is refused');
select is(public.billing_subscription_opened('b8100000-0000-4000-8000-000000000001',
            'starter', 'plan_StarterMon001', 'sub_FirstOpen00001', 'created',
            'https://rzp.io/i/first', now() + interval '11 days',
            'b8000000-0000-0000-0000-000000000002') -> 'stale',
  '[]'::jsonb, 'the first subscription replaces nothing');
select is(public.billing_subscription_opened('b8100000-0000-4000-8000-000000000001',
            'starter', 'plan_StarterMon001', 'sub_FirstOpen00001', 'created',
            'https://rzp.io/i/first', null, null) ->> 'id',
          public.billing_subscription_opened('b8100000-0000-4000-8000-000000000001',
            'starter', 'plan_StarterMon001', 'sub_FirstOpen00001', 'created',
            'https://rzp.io/i/first', null, null) ->> 'id',
  'recording the same subscription again returns the same row');
select is(public.billing_subscription_opened('b8100000-0000-4000-8000-000000000001',
            'pro', 'plan_ProMonthly0001', 'sub_SecondOpen0001', 'created',
            'https://rzp.io/i/second', null, 'b8000000-0000-0000-0000-000000000002') -> 'stale',
  '["sub_FirstOpen00001"]'::jsonb,
  'a new subscription supersedes the current one and names it for cancelling');
select throws_ok($$select public.billing_subscription_opened('b8100000-0000-4000-8000-000000000001',
    'pro', 'plan_ProMonthly0001', 'sub_ThirdOpen00001', 'weird', null, null, null)$$,
  '23514', null, 'only Razorpay''s states are stored');
select throws_ok($$select public.billing_subscription_opened('b8100000-0000-4000-8000-000000000002',
    'pro', 'plan_ProMonthly0001', 'sub_SecondOpen0001', 'created', null, null, null)$$,
  'P0021', null, 'a subscription id is never moved to another resort');
select throws_ok($$select public.billing_subscription_cancel_requested('sub_Unknown000001', true, 'active')$$,
  'P0002', null, 'cancelling an unknown subscription is refused');
select lives_ok($$select public.billing_subscription_cancel_requested('sub_FirstOpen00001', false,
    'cancelled', 'b8000000-0000-0000-0000-000000000002')$$,
  'a replaced subscription is recorded as cancelled');
select lives_ok($$select public.billing_subscription_cancel_requested('sub_SecondOpen0001', true,
    'active', 'b8000000-0000-0000-0000-000000000002')$$,
  'the current one is set to cancel at the end of its cycle');
select lives_ok($$select public.billing_subscription_cancel_requested('sub_SecondOpen0001', true, 'bogus')$$,
  'an unknown status from Razorpay keeps the stored one');
reset role;

select is((select array_agg(razorpay_subscription_id || ':' || status || ':' || cancel_at_cycle_end::text
                            || ':' || (superseded_at is not null)::text
                            order by razorpay_subscription_id)
             from public.billing_subscriptions),
  array['sub_FirstOpen00001:cancelled:false:true','sub_SecondOpen0001:active:true:false'],
  'one current subscription; the replaced one is cancelled');
select is((select array[count(*) filter (where action like 'billing:opened %'),
                        count(*) filter (where action like 'billing:cancel_requested %')]::int[]
             from public.audit_log
            where entity = 'subscription' and property_id = 'b8100000-0000-4000-8000-000000000001'),
  array[2, 3], 'each opening and each cancellation is audited');
select is((select created_by::text || '|' || (start_at is not null)::text
             from public.billing_subscriptions where razorpay_subscription_id = 'sub_FirstOpen00001'),
  'b8000000-0000-0000-0000-000000000002|true',
  'the first recording is kept: who opened it and when it starts');

set local role authenticated;
set local request.jwt.claims to '{"sub":"b8000000-0000-0000-0000-000000000002","role":"authenticated"}';
select is((select jsonb_build_object('cancel', s -> 'current' -> 'cancel_at_cycle_end', 'stale', s -> 'stale')
             from public.billing_subscribe_state('b8100000-0000-4000-8000-000000000001', 'pro') s),
  '{"cancel": true, "stale": []}'::jsonb,
  'the owner sees the pending cancel, and nothing is left to clean up');
reset role;
set local request.jwt.claims to '';
delete from public.billing_subscriptions;
```

- [ ] **Step 2: Run them to verify they fail**

Run: `supabase test db supabase/tests/47_subscription_billing_test.sql`
Expected: FAIL from the first service-role assertion on: `caught: 0A000: billing_subscription_opened is not implemented yet`.

- [ ] **Step 3: Write the two bodies**

In `supabase/migrations/0057_subscription_billing.sql`, replace the two stubs with:

```sql
-- billing-subscribe records a subscription it just created in Razorpay
-- (spec decisions 5, 7 and 14). The resort's current row is superseded and
-- the new one becomes current, one opening at a time per resort. Returns
-- the row id and every replaced subscription still live, which the caller
-- cancels in Razorpay. Recording a known id again changes nothing.
create function public.billing_subscription_opened(
  p_property                 uuid,
  p_tier                     public.subscription_tier,
  p_razorpay_plan_id         text,
  p_razorpay_subscription_id text,
  p_status                   text,
  p_short_url                text,
  p_start_at                 timestamptz,
  p_created_by               uuid
) returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_row public.billing_subscriptions;
begin
  if p_property is null or p_tier is null
     or coalesce(btrim(p_razorpay_plan_id), '') = ''
     or coalesce(btrim(p_razorpay_subscription_id), '') = '' then
    raise exception 'A resort, a tier, a plan and a subscription are required.'
      using errcode = 'P0005';
  end if;

  perform 1 from public.properties where id = p_property;
  if not found then
    raise exception using errcode = 'P0002', message = 'not_found';
  end if;

  -- Two taps at once apply one after the other, so a resort never ends up
  -- with two current rows.
  perform pg_advisory_xact_lock(hashtextextended('billing_subscriptions:' || p_property::text, 0));

  select * into v_row from public.billing_subscriptions
   where razorpay_subscription_id = p_razorpay_subscription_id;

  if found then
    if v_row.property_id <> p_property then
      raise exception using errcode = 'P0021', message = 'resort_mismatch';
    end if;
  else
    update public.billing_subscriptions
       set superseded_at = now(),
           updated_at = now()
     where property_id = p_property and superseded_at is null;

    insert into public.billing_subscriptions
      (property_id, tier, razorpay_plan_id, razorpay_subscription_id, status,
       short_url, start_at, created_by)
    values
      (p_property, p_tier, btrim(p_razorpay_plan_id), btrim(p_razorpay_subscription_id),
       coalesce(p_status, 'created'), p_short_url, p_start_at, p_created_by)
    returning * into v_row;

    insert into public.audit_log (actor_id, entity, entity_id, action, before, after, property_id)
    values (p_created_by, 'subscription', p_property,
            'billing:opened ' || v_row.razorpay_subscription_id || ' ' || p_tier::text,
            null, to_jsonb(v_row), p_property);
  end if;

  return jsonb_build_object(
    'id', v_row.id,
    'stale', coalesce((
        select jsonb_agg(b.razorpay_subscription_id order by b.created_at)
          from public.billing_subscriptions b
         where b.property_id = p_property
           and b.superseded_at is not null
           and b.status in ('created','authenticated','active','pending','paused')),
      '[]'::jsonb));
end;
$$;

-- billing-subscribe (the owner's cancel, or cleaning up a replaced
-- subscription) or billing-webhook records a cancellation Razorpay
-- accepted (spec decisions 9 and 14). The plan itself changes only when
-- Razorpay's subscription.cancelled arrives (billing_webhook_apply).
create function public.billing_subscription_cancel_requested(
  p_razorpay_subscription_id text,
  p_at_cycle_end             boolean,
  p_status                   text,
  p_actor                    uuid default null
) returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_old public.billing_subscriptions;
  v_new public.billing_subscriptions;
begin
  select * into v_old from public.billing_subscriptions
   where razorpay_subscription_id = p_razorpay_subscription_id
   for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'not_found';
  end if;

  update public.billing_subscriptions b
     set cancel_at_cycle_end = coalesce(p_at_cycle_end, false),
         status = case
                    when p_status in ('created','authenticated','active','pending','halted',
                                      'cancelled','completed','expired','paused')
                      then p_status
                    else b.status
                  end,
         updated_at = now()
   where b.id = v_old.id
  returning * into v_new;

  insert into public.audit_log (actor_id, entity, entity_id, action, before, after, property_id)
  values (p_actor, 'subscription', v_new.property_id,
          'billing:cancel_requested ' || p_razorpay_subscription_id,
          to_jsonb(v_old), to_jsonb(v_new), v_new.property_id);
end;
$$;
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `supabase db reset && supabase test db supabase/tests/47_subscription_billing_test.sql supabase/tests/37_tenancy_isolation_test.sql`
Expected: 47 passes 67/67, and 37 passes as in the baseline.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/0057_subscription_billing.sql supabase/tests/47_subscription_billing_test.sql
git commit -m "$(cat <<'EOF'
feat(billing): record opened and cancelled Razorpay subscriptions

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: Webhook events

**Track:** DB. **Depends on:** Task 3.

**Files:**
- Modify: `supabase/migrations/0057_subscription_billing.sql` (replace the body of `billing_webhook_apply`)
- Test: `supabase/tests/47_subscription_billing_test.sql` (append the Task 4 section)

**Interfaces:**
- Consumes:
  - Razorpay's subscription entity fields: `id`, `status`, `current_start`, `current_end` (unix seconds or null) and `short_url`
  - Razorpay's payment entity fields: `id`, `amount` (paise), `currency`, `invoice_id` and `created_at` (unix seconds)
  - `public.subscription_lapsed(...)` (0049)
- Produces: `billing_webhook_apply(...)` returns `{"outcome": ignored|updated|stale|charged|duplicate|lapsed|cancelled, "property_id": uuid|null, "cancel_subscription_id": text|null}`. The rules are spec decisions 9–14. The audit actions are `billing:charged <pay>`, `billing:halted <sub>` and `billing:cancelled <sub>`.

- [ ] **Step 1: Write the failing tests**

In `supabase/tests/47_subscription_billing_test.sql`, change `select plan(67);` to `select plan(95);`, and insert before `select * from finish();`:

```sql
-- === Task 4: webhook events ================================================

-- Razorpay's subscription entity, and a captured payment of p_paise.
create function pg_temp.sub(p_id text, p_status text, p_start bigint default null,
                            p_end bigint default null)
returns jsonb language sql immutable as $f$
  select jsonb_build_object('id', p_id, 'entity', 'subscription', 'status', p_status,
                            'current_start', p_start, 'current_end', p_end,
                            'short_url', 'https://rzp.io/i/' || p_id)
$f$;
create function pg_temp.pay(p_id text, p_paise int)
returns jsonb language sql immutable as $f$
  select jsonb_build_object('id', p_id, 'entity', 'payment', 'amount', p_paise,
                            'currency', 'INR', 'status', 'captured',
                            'invoice_id', 'inv_' || substr(p_id, 5), 'created_at', 1790000000)
$f$;

insert into public.billing_subscriptions
  (property_id, tier, razorpay_plan_id, razorpay_subscription_id, status, superseded_at)
values
  ('b8100000-0000-4000-8000-000000000001', 'pro', 'plan_ProMonthly0001', 'sub_WebhookOne0001', 'created', null),
  ('b8100000-0000-4000-8000-000000000002', 'pro', 'plan_ProMonthly0001', 'sub_WebhookTwo0001', 'active', null),
  ('b8100000-0000-4000-8000-000000000002', 'starter', 'plan_StarterMon001', 'sub_WebhookOld0001', 'active', now()),
  ('b8100000-0000-4000-8000-000000000003', 'starter', 'plan_StarterMon001', 'sub_WebhookThree01', 'authenticated', null),
  ('b8100000-0000-4000-8000-000000000004', 'pro', 'plan_ProMonthly0001', 'sub_WebhookFour001', 'active', null);

-- A: authorise and charge R1's trial, twice, then a late charge.
set local role service_role;
select is(public.billing_webhook_apply('subscription.activated', now(),
            pg_temp.sub('sub_Unknown000001', 'active'), null) ->> 'outcome',
  'ignored', 'an event for a subscription this app did not create is ignored');
select is(public.billing_webhook_apply('subscription.authenticated', now() - interval '1 hour',
            pg_temp.sub('sub_WebhookOne0001', 'authenticated'), null) ->> 'outcome',
  'updated', 'authorising only updates the stored state');
select is(public.billing_webhook_apply('subscription.charged', now(),
            pg_temp.sub('sub_WebhookOne0001', 'active',
                        pg_temp.ist(pg_temp.today() + 11), pg_temp.ist(pg_temp.today() + 41)),
            pg_temp.pay('pay_WebhookOne0001', 799900)) ->> 'outcome',
  'charged', 'a successful charge is applied');
select is(public.billing_webhook_apply('subscription.charged', now(),
            pg_temp.sub('sub_WebhookOne0001', 'active',
                        pg_temp.ist(pg_temp.today() + 11), pg_temp.ist(pg_temp.today() + 41)),
            pg_temp.pay('pay_WebhookOne0001', 799900)) ->> 'outcome',
  'duplicate', 'the same charge delivered twice is recorded once');
select is(public.billing_webhook_apply('subscription.charged', now() - interval '1 day',
            pg_temp.sub('sub_WebhookOne0001', 'active',
                        pg_temp.ist(pg_temp.today() - 19), pg_temp.ist(pg_temp.today() + 10)),
            pg_temp.pay('pay_WebhookLate001', 799900)) ->> 'outcome',
  'charged', 'a late charge is still recorded');
reset role;

select is((select tier::text || '|' || amount_inr::text || '|' || period_start::text || '|'
                  || period_end::text || '|' || property_id::text
             from public.subscription_invoices where razorpay_payment_id = 'pay_WebhookOne0001'),
  'pro|7999.00|' || (pg_temp.today() + 11)::text || '|' || (pg_temp.today() + 40)::text
    || '|b8100000-0000-4000-8000-000000000001',
  'the invoice holds the rupee amount, the paid period in IST, and the resort');
select is((select count(*)::int from public.subscription_invoices
            where razorpay_payment_id = 'pay_WebhookOne0001'),
  1, 'a repeated charge adds no second invoice');
select is((select tier::text || '|' || status::text || '|' || coalesce(trial_ends_on::text, '-')
                  || '|' || paid_through::text
             from public.resort_subscriptions where property_id = 'b8100000-0000-4000-8000-000000000001'),
  'pro|active|-|' || (pg_temp.today() + 40)::text,
  'the charge turned the Starter trial into Pro paid through the period; the late charge did not move it back');
select is((select count(*)::int from public.audit_log
            where entity = 'subscription' and action = 'billing:charged pay_WebhookOne0001'),
  1, 'the charge is audited');
select is((select status || '|' || (current_end = to_timestamp(pg_temp.ist(pg_temp.today() + 41)))::text
             from public.billing_subscriptions where razorpay_subscription_id = 'sub_WebhookOne0001'),
  'active|true', 'the stored state follows the newest event, not the late one');

-- B: halted, stale, cancelled, and a replaced subscription that still charges.
set local role service_role;
select is(public.billing_webhook_apply('subscription.charged', now(),
            pg_temp.sub('sub_WebhookFour001', 'active'),
            pg_temp.pay('pay_WebhookFour001', 799900)) ->> 'outcome',
  'charged', 'a charge without a period is applied');
select is(public.billing_webhook_apply('subscription.halted', now() + interval '1 minute',
            pg_temp.sub('sub_WebhookFour001', 'halted'), null) ->> 'outcome',
  'lapsed', 'Razorpay giving up makes the plan lapse');
select is(public.billing_webhook_apply('subscription.halted', now() - interval '2 days',
            pg_temp.sub('sub_WebhookOne0001', 'halted'), null) ->> 'outcome',
  'stale', 'a halted event older than the last one applied changes nothing');
select is(public.billing_webhook_apply('subscription.cancelled', now(),
            pg_temp.sub('sub_WebhookThree01', 'cancelled'), null) ->> 'outcome',
  'updated', 'cancelling a subscription that never charged leaves the plan alone');
select is(public.billing_webhook_apply('subscription.cancelled', now() + interval '1 minute',
            pg_temp.sub('sub_WebhookOne0001', 'cancelled'), null) ->> 'outcome',
  'cancelled', 'cancelling a paid subscription cancels the plan');
select is(public.billing_webhook_apply('subscription.charged', now(),
            pg_temp.sub('sub_WebhookOld0001', 'active'),
            pg_temp.pay('pay_WebhookOld0001', 299900)) - 'property_id',
  '{"outcome": "charged", "cancel_subscription_id": "sub_WebhookOld0001"}'::jsonb,
  'a replaced subscription that still charges is recorded and handed back for cancelling');
select throws_ok($$select public.billing_webhook_apply('subscription.charged', now(),
    pg_temp.sub('sub_WebhookTwo0001', 'active'), null)$$,
  'P0005', null, 'a charged event without its payment is refused');
reset role;

select is((select period_end from public.subscription_invoices
            where razorpay_payment_id = 'pay_WebhookFour001'),
  ((pg_temp.today() - 1) + interval '1 month')::date,
  'without a period, a charge pays one month past yesterday for a lapsed plan');
select is((select paid_through::text || '|'
                  || public.subscription_lapsed(status, trial_ends_on, paid_through)::text
             from public.resort_subscriptions where property_id = 'b8100000-0000-4000-8000-000000000004'),
  (pg_temp.today() - 1)::text || '|true', 'halted forces the plan to lapse');
select is((select tier::text || '|' || status::text || '|' || coalesce(trial_ends_on::text, '-')
                  || '|' || paid_through::text
             from public.resort_subscriptions where property_id = 'b8100000-0000-4000-8000-000000000001'),
  'pro|cancelled|-|' || (pg_temp.today() + 40)::text,
  'the stale halted did nothing; the cancel kept the paid-through date');
select is((select status::text || '|' || coalesce(paid_through::text, '-')
             from public.resort_subscriptions where property_id = 'b8100000-0000-4000-8000-000000000003'),
  'active|-', 'an abandoned checkout never cancels the plan');
select is((select tier::text || '|' || status::text || '|' || paid_through::text
             from public.resort_subscriptions where property_id = 'b8100000-0000-4000-8000-000000000002'),
  'pro|active|' || (pg_temp.today() + 5)::text,
  'a charge on a replaced subscription does not change the plan');
select is((select count(*)::int from public.subscription_invoices
            where property_id = 'b8100000-0000-4000-8000-000000000002'),
  1, 'but its invoice is recorded at the right resort');
select is((select array[count(*) filter (where action = 'billing:halted sub_WebhookFour001'),
                        count(*) filter (where action = 'billing:cancelled sub_WebhookOne0001')]::int[]
             from public.audit_log where entity = 'subscription'),
  array[1, 1], 'the lapse and the cancel are audited');

-- Reads after the events.
set local role authenticated;
set local request.jwt.claims to '{"sub":"b8000000-0000-0000-0000-000000000002","role":"authenticated"}';
select is((select count(*)::int from public.subscription_invoices), 3,
  'the owner reads the invoices of their own resorts only');
set local request.jwt.claims to '{"sub":"b8000000-0000-0000-0000-000000000005","role":"authenticated"}';
select is((select count(*)::int from public.subscription_invoices), 1,
  'the other owner reads their one invoice');
set local request.jwt.claims to '{"sub":"b8000000-0000-0000-0000-000000000001","role":"authenticated"}';
select is((select billing_status || '|' || last_payment_inr::text from public.platform_billing()
            where property_id = 'b8100000-0000-4000-8000-000000000001'),
  'cancelled|7999.00', 'the console shows the cancelled auto-pay and its last payment');
select throws_ok($$select public.billing_webhook_apply('subscription.charged', now(),
    '{"id":"sub_WebhookTwo0001"}'::jsonb, '{"id":"pay_Forged000001","amount":1}'::jsonb)$$,
  '42501', null, 'a signed-in user cannot post webhook events');
reset role;
set local request.jwt.claims to '';
```

- [ ] **Step 2: Run them to verify they fail**

Run: `supabase test db supabase/tests/47_subscription_billing_test.sql`
Expected: FAIL from the first Task 4 assertion on: `0A000: billing_webhook_apply is not implemented yet`.

- [ ] **Step 3: Write the body**

In `supabase/migrations/0057_subscription_billing.sql`, replace the `billing_webhook_apply` stub with:

```sql
-- billing-webhook hands every signed subscription.* event here (spec
-- decisions 9-14). The stored Razorpay state follows the newest event;
-- invoices and paid_through only move forward; only the current
-- subscription changes the plan; a replaced one that is still live is
-- handed back (cancel_subscription_id) for the caller to cancel.
create function public.billing_webhook_apply(
  p_event        text,
  p_event_at     timestamptz,
  p_subscription jsonb,
  p_payment      jsonb
) returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_sub_id     text := p_subscription ->> 'id';
  v_status     text := p_subscription ->> 'status';
  v_cur_start  timestamptz := to_timestamp(nullif(p_subscription ->> 'current_start', '')::double precision);
  v_cur_end    timestamptz := to_timestamp(nullif(p_subscription ->> 'current_end', '')::double precision);
  v_today      date := (now() at time zone 'Asia/Kolkata')::date;
  v_row        public.billing_subscriptions;
  v_current    boolean;
  v_fresh      boolean;
  v_cancel     text;
  v_old        public.resort_subscriptions;
  v_new        public.resort_subscriptions;
  v_inv        public.subscription_invoices;
  v_period_end date;
  v_outcome    text := 'updated';
begin
  if coalesce(p_event, '') = '' or coalesce(v_sub_id, '') = '' then
    raise exception 'An event and a subscription id are required.' using errcode = 'P0005';
  end if;

  select * into v_row from public.billing_subscriptions
   where razorpay_subscription_id = v_sub_id
   for update;
  if not found then
    return jsonb_build_object('outcome', 'ignored', 'property_id', null,
                              'cancel_subscription_id', null);
  end if;

  v_current := v_row.superseded_at is null;
  v_fresh := p_event_at is null or v_row.last_event_at is null
             or p_event_at >= v_row.last_event_at;

  if v_fresh then
    update public.billing_subscriptions b
       set status = case
                      when v_status in ('created','authenticated','active','pending','halted',
                                        'cancelled','completed','expired','paused')
                        then v_status
                      else b.status
                    end,
           current_start = coalesce(v_cur_start, b.current_start),
           current_end   = coalesce(v_cur_end, b.current_end),
           short_url     = coalesce(p_subscription ->> 'short_url', b.short_url),
           last_event_at = coalesce(p_event_at, b.last_event_at),
           updated_at    = now()
     where b.id = v_row.id
    returning * into v_row;
  end if;

  if not v_current
     and v_row.status in ('created','authenticated','active','pending','paused') then
    v_cancel := v_row.razorpay_subscription_id;
  end if;

  if p_event = 'subscription.charged' then
    if coalesce(p_payment ->> 'id', '') = '' then
      raise exception 'A charged event carries its payment.' using errcode = 'P0005';
    end if;

    select * into v_old from public.resort_subscriptions
     where property_id = v_row.property_id
     for update;

    -- Good through the day the cycle ends (IST); without a cycle, one
    -- month past the later of the paid date and yesterday.
    v_period_end := case
      when v_cur_end is not null
        then ((v_cur_end - interval '1 second') at time zone 'Asia/Kolkata')::date
      else (greatest(coalesce(v_old.paid_through, v_today - 1), v_today - 1)
            + interval '1 month')::date
    end;

    insert into public.subscription_invoices
      (billing_subscription_id, tier, razorpay_payment_id, razorpay_invoice_id,
       amount_inr, currency, period_start, period_end, paid_at)
    values
      (v_row.id, v_row.tier, p_payment ->> 'id', p_payment ->> 'invoice_id',
       round(coalesce((p_payment ->> 'amount')::numeric, 0) / 100, 2),
       upper(coalesce(p_payment ->> 'currency', 'INR')),
       (v_cur_start at time zone 'Asia/Kolkata')::date,
       v_period_end,
       coalesce(to_timestamp(nullif(p_payment ->> 'created_at', '')::double precision),
                p_event_at, now()))
    on conflict (razorpay_payment_id) do nothing
    returning * into v_inv;

    if v_inv.id is null then
      return jsonb_build_object('outcome', 'duplicate', 'property_id', v_row.property_id,
                                'cancel_subscription_id', v_cancel);
    end if;

    if v_current then
      insert into public.resort_subscriptions as s
        (property_id, tier, status, trial_ends_on, paid_through, updated_at, updated_by)
      values (v_row.property_id, v_row.tier, 'active', null, v_period_end, now(), null)
      on conflict (property_id) do update
        set tier          = case when v_fresh then excluded.tier else s.tier end,
            status        = case when v_fresh then 'active'::public.subscription_status
                                 else s.status end,
            trial_ends_on = case when v_fresh then null else s.trial_ends_on end,
            paid_through  = greatest(coalesce(s.paid_through, excluded.paid_through),
                                     excluded.paid_through),
            updated_at    = now(),
            updated_by    = null
      returning * into v_new;

      insert into public.audit_log (actor_id, entity, entity_id, action, before, after, property_id)
      values (null, 'subscription', v_row.property_id,
              'billing:charged ' || v_inv.razorpay_payment_id,
              case when v_old.property_id is null then null else to_jsonb(v_old) end,
              to_jsonb(v_new), v_row.property_id);
    end if;
    v_outcome := 'charged';

  elsif not v_fresh then
    v_outcome := 'stale';

  elsif p_event = 'subscription.halted' and v_current then
    select * into v_old from public.resort_subscriptions
     where property_id = v_row.property_id
     for update;
    update public.resort_subscriptions s
       set paid_through = least(coalesce(s.paid_through, v_today - 1), v_today - 1),
           updated_at = now(),
           updated_by = null
     where s.property_id = v_row.property_id and s.status = 'active'
    returning * into v_new;
    if found then
      insert into public.audit_log (actor_id, entity, entity_id, action, before, after, property_id)
      values (null, 'subscription', v_row.property_id, 'billing:halted ' || v_sub_id,
              to_jsonb(v_old), to_jsonb(v_new), v_row.property_id);
      v_outcome := 'lapsed';
    end if;

  elsif p_event = 'subscription.cancelled' and v_current
        and exists (select 1 from public.subscription_invoices i
                     where i.billing_subscription_id = v_row.id) then
    select * into v_old from public.resort_subscriptions
     where property_id = v_row.property_id
     for update;
    update public.resort_subscriptions s
       set status = 'cancelled',
           updated_at = now(),
           updated_by = null
     where s.property_id = v_row.property_id and s.status <> 'cancelled'
    returning * into v_new;
    if found then
      insert into public.audit_log (actor_id, entity, entity_id, action, before, after, property_id)
      values (null, 'subscription', v_row.property_id, 'billing:cancelled ' || v_sub_id,
              to_jsonb(v_old), to_jsonb(v_new), v_row.property_id);
      v_outcome := 'cancelled';
    end if;
  end if;

  return jsonb_build_object('outcome', v_outcome, 'property_id', v_row.property_id,
                            'cancel_subscription_id', v_cancel);
end;
$$;
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `supabase db reset && supabase test db supabase/tests/47_subscription_billing_test.sql supabase/tests/37_tenancy_isolation_test.sql supabase/tests/41_subscriptions_test.sql`
Expected: 47 passes 95/95, and 37 and 41 pass as in the baseline.

Run: `supabase test db`
Expected: every file as in the Task 1 Step 1 baseline, plus 47 at 95/95.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/0057_subscription_billing.sql supabase/tests/47_subscription_billing_test.sql
git commit -m "$(cat <<'EOF'
feat(billing): apply Razorpay subscription webhooks to the resort's plan

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

## Phase 2: Edge track (after Task 1; 5 → 6, 5 → 7)

### Task 5: Shared billing code (signature, Razorpay client, rules, fakes, database adapter)

**Track:** Edge. **Depends on:** Task 1 (`types.ts`).

**Files:**
- Create: `supabase/functions/_shared/billing/http.ts`
- Create: `supabase/functions/_shared/billing/signature.ts`, test `signature_test.ts`
- Create: `supabase/functions/_shared/billing/razorpay_subscriptions.ts`, test `razorpay_subscriptions_test.ts`
- Create: `supabase/functions/_shared/billing/decide.ts`, test `decide_test.ts`
- Create: `supabase/functions/_shared/billing/testing.ts`
- Create: `supabase/functions/_shared/billing/db.ts`

**Interfaces:**
- Consumes: everything in `_shared/billing/types.ts` (Task 1).
- Produces:
  - `http.ts`:
    - `corsHeaders: Record<string, string>`
    - `json(status: number, body: unknown, cors = true): Response`
    - `fail(status: number, error: ErrorKind, message: string, code?: string, cors = true): Response`
    - `preflight(): Response`
  - `signature.ts`:
    - `hmacSha256Hex(secret: string, message: string): Promise<string>`
    - `timingSafeEqual(a: string, b: string): boolean`
    - `verifyWebhookSignature(rawBody: string, signature: string | null, secret: string): Promise<boolean>`
  - `razorpay_subscriptions.ts`:
    - `RAZORPAY_API`
    - the types `RazorpayKeys { keyId, keySecret }`, `RazorpaySubscription { id, plan_id, status, short_url, current_start, current_end }` and `CreateSubscriptionInput { planId, totalCount, startAt, notifyEmail, notes }`
    - the interface `RazorpaySubscriptions { create(input), cancel(subscriptionId, atCycleEnd) }`
    - the classes `RazorpayError(status, description)` and `RazorpaySubscriptionsClient(keys, fetchFn = fetch)`
  - `decide.ts`:
    - `SubscribeDecision` = `{kind:"create"}` | `{kind:"reuse"|"unchanged", subscriptionId, shortUrl, status}`
    - `CancelDecision` = `{kind:"none"}` | `{kind:"cancel", subscriptionId, atCycleEnd}`
    - `decideSubscribe(current, tier)` and `decideCancel(current)`
  - `testing.ts`:
    - `subscribeState(overrides)` and `rzpSubscription(overrides)`
    - `FakeBillingDb`, with fields `plans`, `state`, `openedResult`, `applyResult`, `error` and `calls`, and `callsTo(method)`
    - `FakeRazorpay`, with fields `created`, `cancelled`, `createResult`, `failCreate` and `failCancel`
  - `db.ts`: the `DbConfig { url, anonKey, serviceRoleKey }` type, and `makeBillingDb(config, callerJwt: string | null): BillingDb`.

- [ ] **Step 1: Write the failing tests**

Create `supabase/functions/_shared/billing/signature_test.ts`:

```ts
import { assert, assertEquals, assertFalse } from "jsr:@std/assert@1";
import { hmacSha256Hex, timingSafeEqual, verifyWebhookSignature } from "./signature.ts";

Deno.test("hmacSha256Hex matches RFC 4231 test case 2", async () => {
  assertEquals(
    await hmacSha256Hex("Jefe", "what do ya want for nothing?"),
    "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843",
  );
});

Deno.test("timingSafeEqual compares whole strings", () => {
  assert(timingSafeEqual("abc", "abc"));
  assertFalse(timingSafeEqual("abc", "abd"));
  assertFalse(timingSafeEqual("abc", "abcd"));
});

Deno.test("a signature over the raw body verifies, in either case", async () => {
  const body = '{"event":"subscription.charged"}';
  const sig = await hmacSha256Hex("whsec_test", body);
  assert(await verifyWebhookSignature(body, sig, "whsec_test"));
  assert(await verifyWebhookSignature(body, sig.toUpperCase(), "whsec_test"));
});

Deno.test("a wrong secret, a missing signature or a re-serialised body fails", async () => {
  const body = '{"event":"subscription.charged"}';
  const sig = await hmacSha256Hex("whsec_test", body);
  assertFalse(await verifyWebhookSignature(body, sig, "another_secret"));
  assertFalse(await verifyWebhookSignature(body, null, "whsec_test"));
  assertFalse(await verifyWebhookSignature('{"event": "subscription.charged"}', sig, "whsec_test"));
});
```

Create `supabase/functions/_shared/billing/razorpay_subscriptions_test.ts`:

```ts
import { assertEquals, assertRejects } from "jsr:@std/assert@1";
import { RAZORPAY_API, RazorpayError, RazorpaySubscriptionsClient } from "./razorpay_subscriptions.ts";

interface Seen {
  url: string;
  method: string;
  headers: Headers;
  body: unknown;
}

function fakeFetch(status: number, body: unknown, seen: Seen[]): typeof fetch {
  return (async (input: RequestInfo | URL, init?: RequestInit) => {
    seen.push({
      url: String(input),
      method: init?.method ?? "GET",
      headers: new Headers(init?.headers),
      body: init?.body ? JSON.parse(String(init.body)) : null,
    });
    return new Response(typeof body === "string" ? body : JSON.stringify(body), {
      status,
      headers: { "Content-Type": "application/json" },
    });
  }) as typeof fetch;
}

const keys = { keyId: "rzp_test_key", keySecret: "rzp_test_secret" };
const entity = {
  id: "sub_NewSub0000001",
  plan_id: "plan_ProMonthly0001",
  status: "created",
  short_url: "https://rzp.io/i/abc",
  current_start: null,
  current_end: null,
};
const input = {
  planId: "plan_ProMonthly0001",
  totalCount: 60,
  startAt: 1790000000,
  notifyEmail: "owner@example.com",
  notes: { property_id: "p1", tier: "pro" },
};

Deno.test("create posts the subscription with Basic auth", async () => {
  const seen: Seen[] = [];
  const client = new RazorpaySubscriptionsClient(keys, fakeFetch(200, entity, seen));
  const sub = await client.create(input);
  assertEquals(sub.id, "sub_NewSub0000001");
  assertEquals(sub.short_url, "https://rzp.io/i/abc");
  assertEquals(seen[0].url, `${RAZORPAY_API}/subscriptions`);
  assertEquals(seen[0].method, "POST");
  assertEquals(seen[0].headers.get("Authorization"), `Basic ${btoa("rzp_test_key:rzp_test_secret")}`);
  assertEquals(seen[0].body, {
    plan_id: "plan_ProMonthly0001",
    total_count: 60,
    quantity: 1,
    customer_notify: 1,
    notes: { property_id: "p1", tier: "pro" },
    start_at: 1790000000,
    notify_info: { notify_email: "owner@example.com" },
  });
});

Deno.test("create leaves out start_at and notify_info when there are none", async () => {
  const seen: Seen[] = [];
  const client = new RazorpaySubscriptionsClient(keys, fakeFetch(200, entity, seen));
  await client.create({ ...input, startAt: null, notifyEmail: null });
  assertEquals(seen[0].body, {
    plan_id: "plan_ProMonthly0001",
    total_count: 60,
    quantity: 1,
    customer_notify: 1,
    notes: { property_id: "p1", tier: "pro" },
  });
});

Deno.test("cancel posts cancel_at_cycle_end as 1 or 0", async () => {
  const seen: Seen[] = [];
  const client = new RazorpaySubscriptionsClient(
    keys,
    fakeFetch(200, { ...entity, id: "sub_Old0000000001", status: "cancelled" }, seen),
  );
  await client.cancel("sub_Old0000000001", true);
  const res = await client.cancel("sub_Old0000000001", false);
  assertEquals(res.status, "cancelled");
  assertEquals(seen[0].url, `${RAZORPAY_API}/subscriptions/sub_Old0000000001/cancel`);
  assertEquals(seen[0].body, { cancel_at_cycle_end: 1 });
  assertEquals(seen[1].body, { cancel_at_cycle_end: 0 });
});

Deno.test("a Razorpay error becomes RazorpayError with its description", async () => {
  const client = new RazorpaySubscriptionsClient(
    keys,
    fakeFetch(400, { error: { code: "BAD_REQUEST_ERROR", description: "The id provided does not exist" } }, []),
  );
  const err = await assertRejects(() => client.create(input), RazorpayError);
  assertEquals(err.status, 400);
  assertEquals(err.description, "The id provided does not exist");
});

Deno.test("a network failure becomes RazorpayError with status 0", async () => {
  const failing = (() => Promise.reject(new TypeError("connection refused"))) as typeof fetch;
  const client = new RazorpaySubscriptionsClient(keys, failing);
  const err = await assertRejects(() => client.cancel("sub_Old0000000001", true), RazorpayError);
  assertEquals(err.status, 0);
  assertEquals(err.description, "connection refused");
});
```

Create `supabase/functions/_shared/billing/decide_test.ts`:

```ts
import { assertEquals } from "jsr:@std/assert@1";
import { decideCancel, decideSubscribe } from "./decide.ts";
import type { CurrentSubscription } from "./types.ts";

function current(overrides: Partial<CurrentSubscription> = {}): CurrentSubscription {
  return {
    razorpay_subscription_id: "sub_Current000001",
    tier: "pro",
    status: "active",
    short_url: "https://rzp.io/i/cur",
    cancel_at_cycle_end: false,
    ...overrides,
  };
}

Deno.test("subscribe: nothing current, or a finished one, creates", () => {
  assertEquals(decideSubscribe(null, "pro"), { kind: "create" });
  for (const status of ["halted", "cancelled", "completed", "expired"] as const) {
    assertEquals(decideSubscribe(current({ status }), "pro"), { kind: "create" }, status);
  }
});

Deno.test("subscribe: another tier creates (the old one is cancelled after)", () => {
  assertEquals(decideSubscribe(current(), "enterprise"), { kind: "create" });
  assertEquals(decideSubscribe(current({ status: "created" }), "starter"), { kind: "create" });
});

Deno.test("subscribe: an unauthorised link for the same tier is reused", () => {
  assertEquals(decideSubscribe(current({ status: "created" }), "pro"), {
    kind: "reuse",
    subscriptionId: "sub_Current000001",
    shortUrl: "https://rzp.io/i/cur",
    status: "created",
  });
  assertEquals(decideSubscribe(current({ status: "created", short_url: null }), "pro"), { kind: "create" });
});

Deno.test("subscribe: live on the same tier is unchanged, unless it is ending", () => {
  for (const status of ["authenticated", "active", "pending", "paused"] as const) {
    assertEquals(decideSubscribe(current({ status }), "pro").kind, "unchanged", status);
  }
  assertEquals(decideSubscribe(current({ cancel_at_cycle_end: true }), "pro"), { kind: "create" });
});

Deno.test("cancel: authorised ends with its cycle, unauthorised ends now", () => {
  assertEquals(decideCancel(current()), {
    kind: "cancel",
    subscriptionId: "sub_Current000001",
    atCycleEnd: true,
  });
  assertEquals(decideCancel(current({ status: "created" })), {
    kind: "cancel",
    subscriptionId: "sub_Current000001",
    atCycleEnd: false,
  });
});

Deno.test("cancel: nothing live, or already ending, is none", () => {
  assertEquals(decideCancel(null), { kind: "none" });
  assertEquals(decideCancel(current({ status: "cancelled" })), { kind: "none" });
  assertEquals(decideCancel(current({ status: "halted" })), { kind: "none" });
  assertEquals(decideCancel(current({ cancel_at_cycle_end: true })), { kind: "none" });
});
```

- [ ] **Step 2: Run them to verify they fail**

Run: `deno test supabase/functions/_shared/billing`
Expected: FAIL with `Module not found "file:///…/_shared/billing/signature.ts"` (and the same for `razorpay_subscriptions.ts` and `decide.ts`).

- [ ] **Step 3: Write the shared modules**

Create `supabase/functions/_shared/billing/http.ts`:

```ts
import type { ErrorBody, ErrorKind } from "./types.ts";

export const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

/** A JSON response; browser-facing functions add the CORS headers. */
export function json(status: number, body: unknown, cors = true): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...(cors ? corsHeaders : {}), "Content-Type": "application/json" },
  });
}

/** The error body every billing function uses: {error, code?, message}. */
export function fail(
  status: number,
  error: ErrorKind,
  message: string,
  code?: string,
  cors = true,
): Response {
  const body: ErrorBody = code ? { error, code, message } : { error, message };
  return json(status, body, cors);
}

/** The answer to a browser's CORS preflight. */
export function preflight(): Response {
  return new Response("ok", { headers: corsHeaders });
}
```

Create `supabase/functions/_shared/billing/signature.ts`:

```ts
const encoder = new TextEncoder();

/** Lower-case hex HMAC-SHA256 of message under secret. */
export async function hmacSha256Hex(secret: string, message: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const mac = await crypto.subtle.sign("HMAC", key, encoder.encode(message));
  return Array.from(new Uint8Array(mac), (b) => b.toString(16).padStart(2, "0")).join("");
}

/** Compares every character, so the time taken does not leak a prefix. */
export function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

/**
 * Razorpay signs the exact bytes it sent: X-Razorpay-Signature is the hex
 * HMAC-SHA256 of the raw body under the webhook secret.
 */
export async function verifyWebhookSignature(
  rawBody: string,
  signature: string | null,
  secret: string,
): Promise<boolean> {
  if (!signature) return false;
  const expected = await hmacSha256Hex(secret, rawBody);
  return timingSafeEqual(expected, signature.trim().toLowerCase());
}
```

Create `supabase/functions/_shared/billing/razorpay_subscriptions.ts`:

```ts
import type { RazorpaySubscriptionStatus } from "./types.ts";

export const RAZORPAY_API = "https://api.razorpay.com/v1";

export interface RazorpayKeys {
  keyId: string;
  keySecret: string;
}

/** The fields of Razorpay's subscription entity this app reads. */
export interface RazorpaySubscription {
  id: string;
  plan_id: string;
  status: RazorpaySubscriptionStatus;
  short_url: string | null;
  current_start: number | null;
  current_end: number | null;
}

export interface CreateSubscriptionInput {
  planId: string;
  totalCount: number;
  /** Unix seconds; null = start now. */
  startAt: number | null;
  notifyEmail: string | null;
  notes: Record<string, string>;
}

export interface RazorpaySubscriptions {
  create(input: CreateSubscriptionInput): Promise<RazorpaySubscription>;
  cancel(subscriptionId: string, atCycleEnd: boolean): Promise<RazorpaySubscription>;
}

/** Razorpay refused (status >= 400) or could not be reached (status 0). */
export class RazorpayError extends Error {
  constructor(readonly status: number, readonly description: string) {
    super(`Razorpay answered ${status}: ${description}`);
    this.name = "RazorpayError";
  }
}

/** The Subscriptions API with the platform's keys; fetch is injectable. */
export class RazorpaySubscriptionsClient implements RazorpaySubscriptions {
  constructor(
    private readonly keys: RazorpayKeys,
    private readonly fetchFn: typeof fetch = fetch,
  ) {}

  create(input: CreateSubscriptionInput): Promise<RazorpaySubscription> {
    const body: Record<string, unknown> = {
      plan_id: input.planId,
      total_count: input.totalCount,
      quantity: 1,
      customer_notify: 1,
      notes: input.notes,
    };
    if (input.startAt !== null) body.start_at = input.startAt;
    if (input.notifyEmail) body.notify_info = { notify_email: input.notifyEmail };
    return this.post("/subscriptions", body);
  }

  cancel(subscriptionId: string, atCycleEnd: boolean): Promise<RazorpaySubscription> {
    return this.post(`/subscriptions/${encodeURIComponent(subscriptionId)}/cancel`, {
      cancel_at_cycle_end: atCycleEnd ? 1 : 0,
    });
  }

  private async post(path: string, body: unknown): Promise<RazorpaySubscription> {
    let res: Response;
    try {
      res = await this.fetchFn(`${RAZORPAY_API}${path}`, {
        method: "POST",
        headers: {
          Authorization: `Basic ${btoa(`${this.keys.keyId}:${this.keys.keySecret}`)}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify(body),
      });
    } catch (e) {
      throw new RazorpayError(0, e instanceof Error ? e.message : String(e));
    }
    const text = await res.text();
    let parsed: unknown = null;
    try {
      parsed = JSON.parse(text);
    } catch {
      // Not JSON: the description falls back to the raw text below.
    }
    if (!res.ok) {
      const description = (parsed as { error?: { description?: string } } | null)?.error
        ?.description ?? text.slice(0, 200);
      throw new RazorpayError(res.status, description);
    }
    return parsed as RazorpaySubscription;
  }
}
```

Create `supabase/functions/_shared/billing/decide.ts`:

```ts
import {
  type CurrentSubscription,
  LIVE_STATUSES,
  type RazorpaySubscriptionStatus,
  type Tier,
} from "./types.ts";

export type SubscribeDecision =
  | { kind: "create" }
  | {
    kind: "reuse" | "unchanged";
    subscriptionId: string;
    shortUrl: string | null;
    status: RazorpaySubscriptionStatus;
  };

export type CancelDecision =
  | { kind: "none" }
  | { kind: "cancel"; subscriptionId: string; atCycleEnd: boolean };

const isLive = (status: RazorpaySubscriptionStatus) => LIVE_STATUSES.includes(status);

/**
 * Spec decisions 7 and 8: reuse an unauthorised link for the same tier;
 * leave a live subscription on the same tier alone unless it is ending;
 * otherwise create a new one (billing_subscription_opened then names the
 * old one for cancelling).
 */
export function decideSubscribe(current: CurrentSubscription | null, tier: Tier): SubscribeDecision {
  if (current === null || !isLive(current.status) || current.tier !== tier) {
    return { kind: "create" };
  }
  const same = {
    subscriptionId: current.razorpay_subscription_id,
    shortUrl: current.short_url,
    status: current.status,
  };
  if (current.status === "created") {
    return current.short_url ? { kind: "reuse", ...same } : { kind: "create" };
  }
  if (current.cancel_at_cycle_end) return { kind: "create" };
  return { kind: "unchanged", ...same };
}

/** Spec decision 9: authorised ends with its cycle; unauthorised ends now. */
export function decideCancel(current: CurrentSubscription | null): CancelDecision {
  if (current === null || !isLive(current.status)) return { kind: "none" };
  if (current.status === "created") {
    return { kind: "cancel", subscriptionId: current.razorpay_subscription_id, atCycleEnd: false };
  }
  if (current.cancel_at_cycle_end) return { kind: "none" };
  return { kind: "cancel", subscriptionId: current.razorpay_subscription_id, atCycleEnd: true };
}
```

Create `supabase/functions/_shared/billing/testing.ts`:

```ts
// Fakes for the billing handlers' tests. Nothing here touches the network
// or a database.
import type {
  ApplyResult,
  BillablePlan,
  BillingDb,
  OpenedArgs,
  OpenedResult,
  RazorpaySubscriptionStatus,
  SubscribeState,
  Tier,
} from "./types.ts";
import {
  type CreateSubscriptionInput,
  RazorpayError,
  type RazorpaySubscription,
  type RazorpaySubscriptions,
} from "./razorpay_subscriptions.ts";

export function subscribeState(overrides: Partial<SubscribeState> = {}): SubscribeState {
  return {
    property_id: "11111111-1111-4111-8111-111111111111",
    property_name: "Resort A",
    caller_id: "22222222-2222-4222-8222-222222222222",
    notify_email: "owner@example.com",
    tier: "pro",
    plan_id: "plan_ProMonthly0001",
    start_at: null,
    current: null,
    stale: [],
    ...overrides,
  };
}

export function rzpSubscription(overrides: Partial<RazorpaySubscription> = {}): RazorpaySubscription {
  return {
    id: "sub_NewSub0000001",
    plan_id: "plan_ProMonthly0001",
    status: "created",
    short_url: "https://rzp.io/i/new",
    current_start: null,
    current_end: null,
    ...overrides,
  };
}

/** Records every call in `calls`; `error`, when set, is thrown by every call. */
export class FakeBillingDb implements BillingDb {
  plans: BillablePlan[] = [];
  state: SubscribeState = subscribeState();
  openedResult: OpenedResult = { id: "row-1", stale: [] };
  applyResult: ApplyResult = { outcome: "updated", property_id: null, cancel_subscription_id: null };
  error: Error | null = null;
  calls: { method: string; args: unknown[] }[] = [];

  private record(method: string, args: unknown[]): void {
    this.calls.push({ method, args });
    if (this.error) throw this.error;
  }

  callsTo(method: string): unknown[][] {
    return this.calls.filter((c) => c.method === method).map((c) => c.args);
  }

  async billablePlans(): Promise<BillablePlan[]> {
    this.record("billablePlans", []);
    return this.plans;
  }

  async subscribeState(propertyId: string, tier: Tier | null): Promise<SubscribeState> {
    this.record("subscribeState", [propertyId, tier]);
    return this.state;
  }

  async opened(args: OpenedArgs): Promise<OpenedResult> {
    this.record("opened", [args]);
    return this.openedResult;
  }

  async cancelRequested(
    subscriptionId: string,
    atCycleEnd: boolean,
    status: RazorpaySubscriptionStatus | null,
    actor: string | null,
  ): Promise<void> {
    this.record("cancelRequested", [subscriptionId, atCycleEnd, status, actor]);
  }

  async applyWebhook(
    event: string,
    eventAt: string | null,
    subscription: Record<string, unknown>,
    payment: Record<string, unknown> | null,
  ): Promise<ApplyResult> {
    this.record("applyWebhook", [event, eventAt, subscription, payment]);
    return this.applyResult;
  }
}

/** Records creates and cancels; `failCreate` / `failCancel` make them throw. */
export class FakeRazorpay implements RazorpaySubscriptions {
  created: CreateSubscriptionInput[] = [];
  cancelled: { id: string; atCycleEnd: boolean }[] = [];
  createResult: RazorpaySubscription = rzpSubscription();
  failCreate: RazorpayError | null = null;
  failCancel: RazorpayError | null = null;

  async create(input: CreateSubscriptionInput): Promise<RazorpaySubscription> {
    this.created.push(input);
    if (this.failCreate) throw this.failCreate;
    return this.createResult;
  }

  async cancel(subscriptionId: string, atCycleEnd: boolean): Promise<RazorpaySubscription> {
    this.cancelled.push({ id: subscriptionId, atCycleEnd });
    if (this.failCancel) throw this.failCancel;
    return rzpSubscription({ id: subscriptionId, status: atCycleEnd ? "active" : "cancelled" });
  }
}
```

Create `supabase/functions/_shared/billing/db.ts`:

```ts
// The real BillingDb: supabase-js as the signed-in caller (the owner's
// reads, so assert_resort_role sees them) and as the service role (the
// billing writes, which no client role may execute). Not imported by any
// test; exercised by the plan's integration task.
import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";
import {
  type ApplyResult,
  type BillablePlan,
  type BillingDb,
  DbError,
  type OpenedResult,
  type SubscribeState,
} from "./types.ts";

export interface DbConfig {
  url: string;
  anonKey: string;
  serviceRoleKey: string;
}

export function makeBillingDb(config: DbConfig, callerJwt: string | null): BillingDb {
  const options = { auth: { persistSession: false, autoRefreshToken: false } };
  const service = createClient(config.url, config.serviceRoleKey, options);
  const caller = callerJwt === null ? null : createClient(config.url, config.anonKey, {
    ...options,
    global: { headers: { Authorization: `Bearer ${callerJwt}` } },
  });

  const asCaller = (): SupabaseClient => {
    if (caller === null) throw new DbError("P0008", "no signed-in caller");
    return caller;
  };

  async function rpc<T>(client: SupabaseClient, fn: string, args: Record<string, unknown>): Promise<T> {
    const { data, error } = await client.rpc(fn, args);
    if (error) throw new DbError(error.code ?? "", error.message);
    return data as T;
  }

  return {
    async billablePlans(): Promise<BillablePlan[]> {
      const { data, error } = await asCaller()
        .from("subscription_plans")
        .select("tier, name, monthly_price_inr")
        .not("razorpay_plan_id", "is", null)
        .order("sort_order");
      if (error) throw new DbError(error.code ?? "", error.message);
      return (data ?? []).map((r) => ({
        tier: r.tier,
        name: r.name,
        monthly_price_inr: Number(r.monthly_price_inr),
      }));
    },
    subscribeState: (propertyId, tier) =>
      rpc<SubscribeState>(asCaller(), "billing_subscribe_state", { p_property: propertyId, p_tier: tier }),
    opened: (a) =>
      rpc<OpenedResult>(service, "billing_subscription_opened", {
        p_property: a.property_id,
        p_tier: a.tier,
        p_razorpay_plan_id: a.razorpay_plan_id,
        p_razorpay_subscription_id: a.razorpay_subscription_id,
        p_status: a.status,
        p_short_url: a.short_url,
        p_start_at: a.start_at === null ? null : new Date(a.start_at * 1000).toISOString(),
        p_created_by: a.created_by,
      }),
    async cancelRequested(subscriptionId, atCycleEnd, status, actor) {
      await rpc<null>(service, "billing_subscription_cancel_requested", {
        p_razorpay_subscription_id: subscriptionId,
        p_at_cycle_end: atCycleEnd,
        p_status: status,
        p_actor: actor,
      });
    },
    applyWebhook: (event, eventAt, subscription, payment) =>
      rpc<ApplyResult>(service, "billing_webhook_apply", {
        p_event: event,
        p_event_at: eventAt,
        p_subscription: subscription,
        p_payment: payment,
      }),
  };
}
```

- [ ] **Step 4: Run the tests and type-check**

Run: `deno test supabase/functions/_shared/billing`
Expected: PASS (15 tests).

Run: `deno check supabase/functions/_shared/billing/testing.ts supabase/functions/_shared/billing/db.ts supabase/functions/_shared/billing/http.ts`
Expected: no errors. The first run downloads `npm:@supabase/supabase-js@2` for `db.ts`.

- [ ] **Step 5: Commit**

```bash
git add supabase/functions/_shared/billing
git commit -m "$(cat <<'EOF'
feat(billing): shared Deno code for Razorpay subscriptions (signature, client, rules, fakes)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: The `billing-subscribe` Edge Function

**Track:** Edge. **Depends on:** Task 5.

**Files:**
- Create: `supabase/functions/billing-subscribe/deno.json`
- Create: `supabase/functions/billing-subscribe/handler.ts`
- Create: `supabase/functions/billing-subscribe/index.ts`
- Test: `supabase/functions/billing-subscribe/handler_test.ts`

**Interfaces:**
- Consumes: from Task 5, `decideSubscribe`, `decideCancel`, `json`, `fail`, `preflight`, `RazorpayError`, `RazorpayKeys`, `RazorpaySubscriptions`, `RazorpaySubscriptionsClient`, `makeBillingDb`, `FakeBillingDb`, `FakeRazorpay`, `subscribeState` and `rzpSubscription`. From Task 1, `BillingDb`, `DbError`, `TIERS` and the response types.
- Produces:
  - `TOTAL_COUNT = 60`
  - `parseRequest(body: unknown): SubscribeRequest | string`
  - `interface SubscribeDeps { keys: RazorpayKeys | null; razorpay: (keys) => RazorpaySubscriptions; db: (callerJwt: string) => BillingDb }`
  - `makeSubscribeHandler(deps): (req: Request) => Promise<Response>`
  - The HTTP contract of spec § Edge Functions, used by Flutter's `BillingRepository`.

- [ ] **Step 1: Write the failing tests**

Create `supabase/functions/billing-subscribe/deno.json`:

```json
{
  "lock": false
}
```

Create `supabase/functions/billing-subscribe/handler_test.ts`:

```ts
import { assertEquals } from "jsr:@std/assert@1";
import { makeSubscribeHandler, TOTAL_COUNT } from "./handler.ts";
import { FakeBillingDb, FakeRazorpay, rzpSubscription, subscribeState } from "../_shared/billing/testing.ts";
import { RazorpayError } from "../_shared/billing/razorpay_subscriptions.ts";
import { type CurrentSubscription, DbError } from "../_shared/billing/types.ts";

const PROPERTY = "11111111-1111-4111-8111-111111111111";
const CALLER = "22222222-2222-4222-8222-222222222222";
const keys = { keyId: "rzp_test_key", keySecret: "rzp_test_secret" };

function setup(withKeys = true) {
  const db = new FakeBillingDb();
  const rp = new FakeRazorpay();
  const jwts: string[] = [];
  const handler = makeSubscribeHandler({
    keys: withKeys ? keys : null,
    razorpay: () => rp,
    db: (jwt) => {
      jwts.push(jwt);
      return db;
    },
  });
  return { db, rp, jwts, handler };
}

function post(body: unknown, auth: string | null = "Bearer user-jwt"): Request {
  const headers = new Headers({ "Content-Type": "application/json" });
  if (auth) headers.set("Authorization", auth);
  return new Request("http://localhost/billing-subscribe", {
    method: "POST",
    headers,
    body: typeof body === "string" ? body : JSON.stringify(body),
  });
}

function current(overrides: Partial<CurrentSubscription> = {}): CurrentSubscription {
  return {
    razorpay_subscription_id: "sub_Current000001",
    tier: "pro",
    status: "active",
    short_url: "https://rzp.io/i/cur",
    cancel_at_cycle_end: false,
    ...overrides,
  };
}

Deno.test("answers the CORS preflight", async () => {
  const res = await setup().handler(new Request("http://localhost/billing-subscribe", { method: "OPTIONS" }));
  assertEquals(res.status, 200);
  assertEquals(res.headers.get("Access-Control-Allow-Origin"), "*");
  await res.body?.cancel();
});

Deno.test("only POST", async () => {
  const res = await setup().handler(new Request("http://localhost/billing-subscribe"));
  assertEquals(res.status, 405);
  assertEquals((await res.json()).error, "method_not_allowed");
});

Deno.test("needs a bearer token", async () => {
  const res = await setup().handler(post({ property_id: PROPERTY, action: "probe" }, null));
  assertEquals(res.status, 401);
  assertEquals((await res.json()).error, "unauthorized");
});

Deno.test("rejects a bad body", async () => {
  const { handler } = setup();
  for (
    const body of [
      "not json",
      { property_id: "p1", action: "probe" },
      { property_id: PROPERTY, action: "refund" },
      { property_id: PROPERTY, action: "subscribe" },
      { property_id: PROPERTY, action: "subscribe", tier: "free" },
    ]
  ) {
    const res = await handler(post(body));
    assertEquals(res.status, 400, JSON.stringify(body));
    assertEquals((await res.json()).error, "bad_request");
  }
});

Deno.test("without keys every action says not configured and touches nothing", async () => {
  const { handler, db, jwts, rp } = setup(false);
  for (const action of ["probe", "subscribe", "cancel"]) {
    const res = await handler(post({ property_id: PROPERTY, action, tier: "pro" }));
    assertEquals(res.status, 200);
    assertEquals(await res.json(), { configured: false });
  }
  assertEquals(jwts, []);
  assertEquals(db.calls, []);
  assertEquals(rp.created, []);
});

Deno.test("probe lists the billable plans, reading as the caller", async () => {
  const { handler, db, jwts } = setup();
  db.plans = [{ tier: "pro", name: "Pro", monthly_price_inr: 7999 }];
  const res = await handler(post({ property_id: PROPERTY, action: "probe" }));
  assertEquals(await res.json(), { configured: true, plans: [{ tier: "pro", name: "Pro", monthly_price_inr: 7999 }] });
  assertEquals(jwts, ["user-jwt"]);
});

Deno.test("subscribe with nothing current creates, records and returns the link", async () => {
  const { handler, db, rp } = setup();
  db.state = subscribeState({ start_at: 1790000000 });
  const res = await handler(post({ property_id: PROPERTY, action: "subscribe", tier: "pro" }));
  assertEquals(res.status, 200);
  assertEquals(await res.json(), {
    configured: true,
    action: "created",
    subscription_id: "sub_NewSub0000001",
    short_url: "https://rzp.io/i/new",
    status: "created",
  });
  assertEquals(db.callsTo("subscribeState"), [[PROPERTY, "pro"]]);
  assertEquals(rp.created, [{
    planId: "plan_ProMonthly0001",
    totalCount: TOTAL_COUNT,
    startAt: 1790000000,
    notifyEmail: "owner@example.com",
    notes: { property_id: PROPERTY, tier: "pro" },
  }]);
  assertEquals(db.callsTo("opened"), [[{
    property_id: PROPERTY,
    tier: "pro",
    razorpay_plan_id: "plan_ProMonthly0001",
    razorpay_subscription_id: "sub_NewSub0000001",
    status: "created",
    short_url: "https://rzp.io/i/new",
    start_at: 1790000000,
    created_by: CALLER,
  }]]);
});

Deno.test("subscribe reuses an unauthorised link for the same tier", async () => {
  const { handler, db, rp } = setup();
  db.state = subscribeState({ current: current({ status: "created" }) });
  const body = await (await handler(post({ property_id: PROPERTY, action: "subscribe", tier: "pro" }))).json();
  assertEquals(body.action, "reused");
  assertEquals(body.short_url, "https://rzp.io/i/cur");
  assertEquals(rp.created, []);
  assertEquals(db.callsTo("opened"), []);
});

Deno.test("subscribe leaves live auto-pay on the same tier unchanged", async () => {
  const { handler, db, rp } = setup();
  db.state = subscribeState({ current: current() });
  const body = await (await handler(post({ property_id: PROPERTY, action: "subscribe", tier: "pro" }))).json();
  assertEquals(body.action, "unchanged");
  assertEquals(body.subscription_id, "sub_Current000001");
  assertEquals(rp.created, []);
});

Deno.test("changing tier creates the new one, then cancels the replaced one now", async () => {
  const { handler, db, rp } = setup();
  db.state = subscribeState({ tier: "enterprise", plan_id: "plan_EnterpriseM01", current: current() });
  db.openedResult = { id: "row-2", stale: ["sub_Current000001"] };
  rp.createResult = rzpSubscription({ id: "sub_Enterprise0001", plan_id: "plan_EnterpriseM01" });
  const body = await (await handler(post({ property_id: PROPERTY, action: "subscribe", tier: "enterprise" }))).json();
  assertEquals(body.action, "created");
  assertEquals(body.subscription_id, "sub_Enterprise0001");
  assertEquals(body.warning, undefined);
  assertEquals(rp.cancelled, [{ id: "sub_Current000001", atCycleEnd: false }]);
  assertEquals(db.callsTo("cancelRequested"), [["sub_Current000001", false, "cancelled", CALLER]]);
});

Deno.test("stale subscriptions are cleaned up first, and a failure is a warning", async () => {
  const { handler, db, rp } = setup();
  db.state = subscribeState({ current: current({ status: "created" }), stale: ["sub_Stale00000001"] });
  rp.failCancel = new RazorpayError(502, "Bad Gateway");
  const res = await handler(post({ property_id: PROPERTY, action: "subscribe", tier: "pro" }));
  assertEquals(res.status, 200);
  const body = await res.json();
  assertEquals(body.action, "reused");
  assertEquals(body.warning, "previous_not_cancelled");
  assertEquals(rp.cancelled, [{ id: "sub_Stale00000001", atCycleEnd: false }]);
  assertEquals(db.callsTo("cancelRequested"), []);
});

Deno.test("a database refusal is 409 db with the Postgres code", async () => {
  const { handler, db } = setup();
  db.error = new DbError("P0038", "billing_unavailable");
  const res = await handler(post({ property_id: PROPERTY, action: "subscribe", tier: "enterprise" }));
  assertEquals(res.status, 409);
  assertEquals(await res.json(), { error: "db", code: "P0038", message: "billing_unavailable" });
});

Deno.test("Razorpay refusing the create is 502 gateway, and nothing is recorded", async () => {
  const { handler, db, rp } = setup();
  rp.failCreate = new RazorpayError(400, "The id provided does not exist");
  const res = await handler(post({ property_id: PROPERTY, action: "subscribe", tier: "pro" }));
  assertEquals(res.status, 502);
  assertEquals(await res.json(), { error: "gateway", message: "The id provided does not exist" });
  assertEquals(db.callsTo("opened"), []);
});

Deno.test("cancel: authorised auto-pay ends with its cycle", async () => {
  const { handler, db, rp } = setup();
  db.state = subscribeState({ tier: null, plan_id: null, current: current() });
  const body = await (await handler(post({ property_id: PROPERTY, action: "cancel" }))).json();
  assertEquals(body, {
    configured: true,
    action: "cancel_scheduled",
    subscription_id: "sub_Current000001",
    status: "active",
  });
  assertEquals(db.callsTo("subscribeState"), [[PROPERTY, null]]);
  assertEquals(rp.cancelled, [{ id: "sub_Current000001", atCycleEnd: true }]);
  assertEquals(db.callsTo("cancelRequested"), [["sub_Current000001", true, "active", CALLER]]);
});

Deno.test("cancel: an unauthorised link is cancelled now", async () => {
  const { handler, db } = setup();
  db.state = subscribeState({ current: current({ status: "created" }) });
  const body = await (await handler(post({ property_id: PROPERTY, action: "cancel" }))).json();
  assertEquals(body.action, "cancelled");
  assertEquals(body.status, "cancelled");
});

Deno.test("cancel: nothing to cancel is none", async () => {
  const { handler, db, rp } = setup();
  db.state = subscribeState({ current: null });
  const body = await (await handler(post({ property_id: PROPERTY, action: "cancel" }))).json();
  assertEquals(body, { configured: true, action: "none", subscription_id: null, status: null });
  assertEquals(rp.cancelled, []);
});

Deno.test("anything unexpected is 500 internal", async () => {
  const { handler, db } = setup();
  db.error = new Error("boom");
  const res = await handler(post({ property_id: PROPERTY, action: "probe" }));
  assertEquals(res.status, 500);
  assertEquals((await res.json()).error, "internal");
});
```

- [ ] **Step 2: Run them to verify they fail**

Run: `deno test supabase/functions/billing-subscribe`
Expected: FAIL with `Module not found "file:///…/billing-subscribe/handler.ts"`.

- [ ] **Step 3: Write the handler and the entry point**

Create `supabase/functions/billing-subscribe/handler.ts`:

```ts
// billing-subscribe (P8): the resort owner's probe, subscribe and cancel.
// Reads run as the caller (billing_subscribe_state asserts the owner);
// the billing writes run as the service role. See the spec's
// "Edge Functions" section.
import { decideCancel, decideSubscribe } from "../_shared/billing/decide.ts";
import { fail, json, preflight } from "../_shared/billing/http.ts";
import {
  RazorpayError,
  type RazorpayKeys,
  type RazorpaySubscriptions,
} from "../_shared/billing/razorpay_subscriptions.ts";
import {
  type BillingDb,
  type CancelResponse,
  DbError,
  type NotConfigured,
  type ProbeResponse,
  type SubscribeRequest,
  type SubscribeResponse,
  type Tier,
  TIERS,
} from "../_shared/billing/types.ts";

/** Monthly cycles per subscription: 5 years (spec decision 15). */
export const TOTAL_COUNT = 60;

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export interface SubscribeDeps {
  /** Null while RAZORPAY_KEY_ID / RAZORPAY_KEY_SECRET are unset. */
  keys: RazorpayKeys | null;
  razorpay: (keys: RazorpayKeys) => RazorpaySubscriptions;
  db: (callerJwt: string) => BillingDb;
}

/** The request, or a message saying what is wrong with it. */
export function parseRequest(body: unknown): SubscribeRequest | string {
  if (typeof body !== "object" || body === null) return "The body must be a JSON object.";
  const b = body as Record<string, unknown>;
  if (typeof b.property_id !== "string" || !UUID.test(b.property_id)) {
    return "property_id must be a resort id.";
  }
  if (b.action !== "probe" && b.action !== "subscribe" && b.action !== "cancel") {
    return "action must be probe, subscribe or cancel.";
  }
  if (b.action === "subscribe" && !TIERS.includes(b.tier as Tier)) {
    return "tier must be starter, pro or enterprise.";
  }
  return {
    property_id: b.property_id,
    action: b.action,
    tier: b.action === "subscribe" ? b.tier as Tier : undefined,
  };
}

/** Cancels each id now; false when any of them could not be cancelled. */
async function cancelStale(
  db: BillingDb,
  razorpay: RazorpaySubscriptions,
  ids: string[],
  actor: string | null,
): Promise<boolean> {
  let all = true;
  for (const id of ids) {
    try {
      const res = await razorpay.cancel(id, false);
      await db.cancelRequested(id, false, res.status, actor);
    } catch (e) {
      console.error("billing-subscribe: could not cancel", id, e);
      all = false;
    }
  }
  return all;
}

async function subscribe(
  db: BillingDb,
  razorpay: RazorpaySubscriptions,
  propertyId: string,
  tier: Tier,
): Promise<SubscribeResponse> {
  const state = await db.subscribeState(propertyId, tier);
  if (!state.plan_id) throw new DbError("P0038", "billing_unavailable");
  let cleanedUp = await cancelStale(db, razorpay, state.stale, state.caller_id);
  const warning = () => cleanedUp ? {} : { warning: "previous_not_cancelled" as const };

  const decision = decideSubscribe(state.current, tier);
  if (decision.kind !== "create") {
    return {
      configured: true,
      action: decision.kind === "reuse" ? "reused" : "unchanged",
      subscription_id: decision.subscriptionId,
      short_url: decision.shortUrl,
      status: decision.status,
      ...warning(),
    };
  }

  const created = await razorpay.create({
    planId: state.plan_id,
    totalCount: TOTAL_COUNT,
    startAt: state.start_at,
    notifyEmail: state.notify_email,
    notes: { property_id: propertyId, tier },
  });
  const opened = await db.opened({
    property_id: propertyId,
    tier,
    razorpay_plan_id: state.plan_id,
    razorpay_subscription_id: created.id,
    status: created.status,
    short_url: created.short_url,
    start_at: state.start_at,
    created_by: state.caller_id,
  });
  cleanedUp = (await cancelStale(db, razorpay, opened.stale, state.caller_id)) && cleanedUp;
  return {
    configured: true,
    action: "created",
    subscription_id: created.id,
    short_url: created.short_url,
    status: created.status,
    ...warning(),
  };
}

async function cancel(
  db: BillingDb,
  razorpay: RazorpaySubscriptions,
  propertyId: string,
): Promise<CancelResponse> {
  const state = await db.subscribeState(propertyId, null);
  await cancelStale(db, razorpay, state.stale, state.caller_id);
  const decision = decideCancel(state.current);
  if (decision.kind === "none") {
    return {
      configured: true,
      action: "none",
      subscription_id: state.current?.razorpay_subscription_id ?? null,
      status: state.current?.status ?? null,
    };
  }
  const res = await razorpay.cancel(decision.subscriptionId, decision.atCycleEnd);
  await db.cancelRequested(decision.subscriptionId, decision.atCycleEnd, res.status, state.caller_id);
  return {
    configured: true,
    action: decision.atCycleEnd ? "cancel_scheduled" : "cancelled",
    subscription_id: decision.subscriptionId,
    status: res.status,
  };
}

export function makeSubscribeHandler(deps: SubscribeDeps): (req: Request) => Promise<Response> {
  return async (req) => {
    if (req.method === "OPTIONS") return preflight();
    if (req.method !== "POST") return fail(405, "method_not_allowed", "Use POST.");

    const auth = req.headers.get("Authorization") ?? "";
    const jwt = auth.startsWith("Bearer ") ? auth.slice(7).trim() : "";
    if (!jwt) return fail(401, "unauthorized", "Sign in first.");

    let raw: unknown;
    try {
      raw = await req.json();
    } catch {
      return fail(400, "bad_request", "The body must be JSON.");
    }
    const request = parseRequest(raw);
    if (typeof request === "string") return fail(400, "bad_request", request);

    if (deps.keys === null) return json(200, { configured: false } satisfies NotConfigured);

    try {
      const db = deps.db(jwt);
      switch (request.action) {
        case "probe":
          return json(200, { configured: true, plans: await db.billablePlans() } satisfies ProbeResponse);
        case "subscribe":
          return json(200, await subscribe(db, deps.razorpay(deps.keys), request.property_id, request.tier!));
        case "cancel":
          return json(200, await cancel(db, deps.razorpay(deps.keys), request.property_id));
      }
    } catch (e) {
      if (e instanceof DbError) return fail(409, "db", e.message, e.code);
      if (e instanceof RazorpayError) return fail(502, "gateway", e.description);
      console.error("billing-subscribe", e);
      return fail(500, "internal", "Something went wrong.");
    }
  };
}
```

Create `supabase/functions/billing-subscribe/index.ts`:

```ts
// Deployed entry point. Secrets come from `supabase secrets set`; without
// the Razorpay keys every action answers {configured:false}.
import { makeBillingDb } from "../_shared/billing/db.ts";
import { RazorpaySubscriptionsClient } from "../_shared/billing/razorpay_subscriptions.ts";
import { makeSubscribeHandler } from "./handler.ts";

const keyId = Deno.env.get("RAZORPAY_KEY_ID") ?? "";
const keySecret = Deno.env.get("RAZORPAY_KEY_SECRET") ?? "";
const config = {
  url: Deno.env.get("SUPABASE_URL") ?? "",
  anonKey: Deno.env.get("SUPABASE_ANON_KEY") ?? "",
  serviceRoleKey: Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
};

Deno.serve(makeSubscribeHandler({
  keys: keyId && keySecret ? { keyId, keySecret } : null,
  razorpay: (keys) => new RazorpaySubscriptionsClient(keys),
  db: (jwt) => makeBillingDb(config, jwt),
}));
```

- [ ] **Step 4: Run the tests and type-check**

Run: `deno test supabase/functions/billing-subscribe`
Expected: PASS (17 tests).

Run: `deno check supabase/functions/billing-subscribe/index.ts`
Expected: no errors.

- [ ] **Step 5: Commit**

```bash
git add supabase/functions/billing-subscribe
git commit -m "$(cat <<'EOF'
feat(billing): billing-subscribe Edge Function (probe, subscribe, cancel)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 7: The `billing-webhook` Edge Function, its config, and the setup guide

**Track:** Edge. **Depends on:** Task 5. It can run alongside Task 6.

**Files:**
- Create: `supabase/functions/billing-webhook/deno.json`
- Create: `supabase/functions/billing-webhook/handler.ts`
- Create: `supabase/functions/billing-webhook/index.ts`
- Test: `supabase/functions/billing-webhook/handler_test.ts`
- Modify: `supabase/config.toml` (append two `[functions.*]` blocks at the end)
- Create: `docs/subscription-billing.md`

**Interfaces:**
- Consumes: from Task 5, `verifyWebhookSignature`, `hmacSha256Hex` (tests), `json`, `fail`, `RazorpayKeys`, `RazorpaySubscriptions`, `RazorpaySubscriptionsClient`, `makeBillingDb`, `FakeBillingDb` and `FakeRazorpay`. From Task 1, `BillingDb`, `ApplyResult`, `DbError` and `WebhookResponse`.
- Produces:
  - `interface WebhookDeps { webhookSecret: string | null; keys: RazorpayKeys | null; razorpay: (keys) => RazorpaySubscriptions; db: () => BillingDb }`
  - `makeWebhookHandler(deps): (req: Request) => Promise<Response>`
  - The webhook URL `…/functions/v1/billing-webhook`, served with `verify_jwt = false`.

- [ ] **Step 1: Write the failing tests**

Create `supabase/functions/billing-webhook/deno.json`:

```json
{
  "lock": false
}
```

Create `supabase/functions/billing-webhook/handler_test.ts`:

```ts
import { assertEquals } from "jsr:@std/assert@1";
import { makeWebhookHandler } from "./handler.ts";
import { FakeBillingDb, FakeRazorpay } from "../_shared/billing/testing.ts";
import { hmacSha256Hex } from "../_shared/billing/signature.ts";
import { DbError } from "../_shared/billing/types.ts";

const SECRET = "whsec_fixture";
const keys = { keyId: "rzp_test_key", keySecret: "rzp_test_secret" };

const subscription = {
  id: "sub_WebhookOne0001",
  entity: "subscription",
  status: "active",
  current_start: 1790000000,
  current_end: 1792592000,
};
const payment = { id: "pay_WebhookOne0001", entity: "payment", amount: 799900, currency: "INR", created_at: 1790000100 };

function event(name: string, withPayment: boolean): string {
  return JSON.stringify({
    entity: "event",
    account_id: "acc_Fixture000001",
    event: name,
    contains: withPayment ? ["subscription", "payment"] : ["subscription"],
    payload: {
      subscription: { entity: subscription },
      ...(withPayment ? { payment: { entity: payment } } : {}),
    },
    created_at: 1790000200,
  });
}

function setup(opts: { secret?: string | null; withKeys?: boolean } = {}) {
  const db = new FakeBillingDb();
  const rp = new FakeRazorpay();
  const handler = makeWebhookHandler({
    webhookSecret: opts.secret === undefined ? SECRET : opts.secret,
    keys: opts.withKeys === false ? null : keys,
    razorpay: () => rp,
    db: () => db,
  });
  return { db, rp, handler };
}

async function signed(raw: string, secret = SECRET): Promise<Request> {
  return new Request("http://localhost/billing-webhook", {
    method: "POST",
    headers: { "Content-Type": "application/json", "X-Razorpay-Signature": await hmacSha256Hex(secret, raw) },
    body: raw,
  });
}

Deno.test("only POST", async () => {
  const res = await setup().handler(new Request("http://localhost/billing-webhook"));
  assertEquals(res.status, 405);
  await res.body?.cancel();
});

Deno.test("503 until a webhook secret is set", async () => {
  const { handler, db } = setup({ secret: null });
  const res = await handler(await signed(event("subscription.charged", true)));
  assertEquals(res.status, 503);
  assertEquals((await res.json()).error, "not_configured");
  assertEquals(db.calls, []);
});

Deno.test("a wrong or missing signature is 401 and records nothing", async () => {
  const { handler, db } = setup();
  const raw = event("subscription.charged", true);
  const wrong = await handler(await signed(raw, "another_secret"));
  assertEquals(wrong.status, 401);
  assertEquals((await wrong.json()).error, "invalid_signature");
  const missing = await handler(new Request("http://localhost/billing-webhook", { method: "POST", body: raw }));
  assertEquals(missing.status, 401);
  await missing.body?.cancel();
  assertEquals(db.calls, []);
});

Deno.test("a signed body that is not JSON is 400", async () => {
  const res = await setup().handler(await signed("not json"));
  assertEquals(res.status, 400);
  await res.body?.cancel();
});

Deno.test("events that are not subscription.* are acknowledged and ignored", async () => {
  const { handler, db } = setup();
  const res = await handler(await signed(JSON.stringify({ event: "payment.captured", payload: {} })));
  assertEquals(res.status, 200);
  assertEquals(await res.json(), { status: "ignored" });
  assertEquals(db.calls, []);
});

Deno.test("a subscription event without its subscription is 400", async () => {
  const res = await setup().handler(await signed(JSON.stringify({ event: "subscription.charged", payload: {} })));
  assertEquals(res.status, 400);
  await res.body?.cancel();
});

Deno.test("subscription.charged is applied with its payment and time", async () => {
  const { handler, db } = setup();
  db.applyResult = { outcome: "charged", property_id: "p1", cancel_subscription_id: null };
  const res = await handler(await signed(event("subscription.charged", true)));
  assertEquals(res.status, 200);
  assertEquals(await res.json(), { status: "processed", outcome: "charged" });
  assertEquals(db.callsTo("applyWebhook"), [[
    "subscription.charged",
    new Date(1790000200 * 1000).toISOString(),
    subscription,
    payment,
  ]]);
});

Deno.test("subscription.halted has no payment", async () => {
  const { handler, db } = setup();
  db.applyResult = { outcome: "lapsed", property_id: "p1", cancel_subscription_id: null };
  const res = await handler(await signed(event("subscription.halted", false)));
  assertEquals(await res.json(), { status: "processed", outcome: "lapsed" });
  assertEquals(db.callsTo("applyWebhook")[0][3], null);
});

Deno.test("a database failure is 500, so Razorpay retries", async () => {
  const { handler, db } = setup();
  db.error = new DbError("40001", "could not serialize access");
  const res = await handler(await signed(event("subscription.charged", true)));
  assertEquals(res.status, 500);
  assertEquals((await res.json()).error, "db");
});

Deno.test("a replaced subscription that is still live is cancelled now", async () => {
  const { handler, db, rp } = setup();
  db.applyResult = { outcome: "charged", property_id: "p1", cancel_subscription_id: "sub_WebhookOld0001" };
  const res = await handler(await signed(event("subscription.charged", true)));
  assertEquals(res.status, 200);
  await res.body?.cancel();
  assertEquals(rp.cancelled, [{ id: "sub_WebhookOld0001", atCycleEnd: false }]);
  assertEquals(db.callsTo("cancelRequested"), [["sub_WebhookOld0001", false, "cancelled", null]]);
});

Deno.test("without the API keys the replaced subscription is left for later", async () => {
  const { handler, db, rp } = setup({ withKeys: false });
  db.applyResult = { outcome: "charged", property_id: "p1", cancel_subscription_id: "sub_WebhookOld0001" };
  const res = await handler(await signed(event("subscription.charged", true)));
  assertEquals(res.status, 200);
  await res.body?.cancel();
  assertEquals(rp.cancelled, []);
});
```

- [ ] **Step 2: Run them to verify they fail**

Run: `deno test supabase/functions/billing-webhook`
Expected: FAIL with `Module not found "file:///…/billing-webhook/handler.ts"`.

- [ ] **Step 3: Write the handler and the entry point**

Create `supabase/functions/billing-webhook/handler.ts`:

```ts
// billing-webhook (P8): Razorpay's subscription.* events. Called by
// Razorpay without a Supabase JWT (verify_jwt = false), so the signature
// over the raw body is the only authentication. The plan rules live in
// billing_webhook_apply (0057).
import { fail, json } from "../_shared/billing/http.ts";
import type { RazorpayKeys, RazorpaySubscriptions } from "../_shared/billing/razorpay_subscriptions.ts";
import { verifyWebhookSignature } from "../_shared/billing/signature.ts";
import { type ApplyResult, type BillingDb, DbError, type WebhookResponse } from "../_shared/billing/types.ts";

export interface WebhookDeps {
  /** RAZORPAY_BILLING_WEBHOOK_SECRET, else RAZORPAY_WEBHOOK_SECRET; null = 503. */
  webhookSecret: string | null;
  /** Needed only to cancel a replaced subscription that is still live. */
  keys: RazorpayKeys | null;
  razorpay: (keys: RazorpayKeys) => RazorpaySubscriptions;
  db: () => BillingDb;
}

interface RazorpayEvent {
  event?: unknown;
  created_at?: unknown;
  payload?: {
    subscription?: { entity?: Record<string, unknown> };
    payment?: { entity?: Record<string, unknown> };
  };
}

export function makeWebhookHandler(deps: WebhookDeps): (req: Request) => Promise<Response> {
  return async (req) => {
    if (req.method !== "POST") return fail(405, "method_not_allowed", "Use POST.", undefined, false);
    if (!deps.webhookSecret) {
      return fail(503, "not_configured", "The billing webhook secret is not set.", undefined, false);
    }

    const raw = await req.text();
    const valid = await verifyWebhookSignature(raw, req.headers.get("X-Razorpay-Signature"), deps.webhookSecret);
    if (!valid) return fail(401, "invalid_signature", "The signature does not match.", undefined, false);

    let body: RazorpayEvent;
    try {
      body = JSON.parse(raw);
    } catch {
      return fail(400, "bad_request", "The body must be JSON.", undefined, false);
    }

    const event = typeof body?.event === "string" ? body.event : "";
    if (!event.startsWith("subscription.")) {
      return json(200, { status: "ignored" } satisfies WebhookResponse, false);
    }
    const subscription = body.payload?.subscription?.entity;
    if (!subscription || typeof subscription.id !== "string") {
      return fail(400, "bad_request", "A subscription event needs its subscription.", undefined, false);
    }
    const payment = body.payload?.payment?.entity ?? null;
    const eventAt = typeof body.created_at === "number" ? new Date(body.created_at * 1000).toISOString() : null;

    const db = deps.db();
    let result: ApplyResult;
    try {
      result = await db.applyWebhook(event, eventAt, subscription, payment);
    } catch (e) {
      console.error("billing-webhook", event, e);
      return e instanceof DbError
        ? fail(500, "db", "Could not record the event.", e.code, false)
        : fail(500, "internal", "Could not record the event.", undefined, false);
    }

    if (result.cancel_subscription_id && deps.keys) {
      try {
        const res = await deps.razorpay(deps.keys).cancel(result.cancel_subscription_id, false);
        await db.cancelRequested(result.cancel_subscription_id, false, res.status, null);
      } catch (e) {
        // The next event for it, or the owner's next subscribe, retries.
        console.error("billing-webhook: could not cancel", result.cancel_subscription_id, e);
      }
    }

    return json(200, { status: "processed", outcome: result.outcome } satisfies WebhookResponse, false);
  };
}
```

Create `supabase/functions/billing-webhook/index.ts`:

```ts
// Deployed entry point (verify_jwt = false in supabase/config.toml).
import { makeBillingDb } from "../_shared/billing/db.ts";
import { RazorpaySubscriptionsClient } from "../_shared/billing/razorpay_subscriptions.ts";
import { makeWebhookHandler } from "./handler.ts";

const keyId = Deno.env.get("RAZORPAY_KEY_ID") ?? "";
const keySecret = Deno.env.get("RAZORPAY_KEY_SECRET") ?? "";
const webhookSecret = Deno.env.get("RAZORPAY_BILLING_WEBHOOK_SECRET") ||
  Deno.env.get("RAZORPAY_WEBHOOK_SECRET") || null;
const config = {
  url: Deno.env.get("SUPABASE_URL") ?? "",
  anonKey: Deno.env.get("SUPABASE_ANON_KEY") ?? "",
  serviceRoleKey: Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
};

Deno.serve(makeWebhookHandler({
  webhookSecret,
  keys: keyId && keySecret ? { keyId, keySecret } : null,
  razorpay: (keys) => new RazorpaySubscriptionsClient(keys),
  db: () => makeBillingDb(config, null),
}));
```

- [ ] **Step 4: Run the tests and type-check**

Run: `deno test supabase/functions/billing-webhook`
Expected: PASS (11 tests).

Run: `deno check supabase/functions/billing-webhook/index.ts`
Expected: no errors.

- [ ] **Step 5: Configure the functions and write the setup guide**

Append to the end of `supabase/config.toml`:

```toml

# Subscription auto-billing (P8). billing-subscribe needs the caller's
# Supabase JWT; Razorpay calls billing-webhook without one, so that
# function checks X-Razorpay-Signature instead.
[functions.billing-subscribe]
verify_jwt = true

[functions.billing-webhook]
verify_jwt = false
```

Create `docs/subscription-billing.md`:

````markdown
# Subscription auto-billing (Razorpay)

ResortHub can charge each resort's plan (Starter, Pro, Enterprise) monthly
through Razorpay Subscriptions. Until the steps below are done, nothing
changes: the platform admin keeps setting plans and paid-until dates by
hand on the platform console, and owners see no payment button.

Design: `docs/superpowers/specs/2026-09-25-p8-subscription-auto-billing-design.md`.

## 1. Create the plans in Razorpay

In the Razorpay Dashboard (Subscriptions → Plans), create one plan per
tier you want to bill online:

- Billing frequency: every 1 month.
- Amount: the same monthly price as the console's **Plan prices** dialog
  (MRR on the console uses the console's price, not Razorpay's).

Copy each plan's id (`plan_…`).

## 2. Paste the plan ids

On the platform console, open **Plan prices** and fill in
"<Plan> Razorpay plan id" for each tier. Leave a tier blank to keep it
billed by hand.

## 3. Set the secrets

```bash
supabase secrets set \
  RAZORPAY_KEY_ID=rzp_live_xxxxxxxx \
  RAZORPAY_KEY_SECRET=xxxxxxxxxxxxxxxx \
  RAZORPAY_BILLING_WEBHOOK_SECRET=choose-a-long-random-string
```

If you already set `RAZORPAY_WEBHOOK_SECRET` for online booking payments
(P6), you can reuse it: the billing webhook falls back to it when
`RAZORPAY_BILLING_WEBHOOK_SECRET` is unset. Never put these values in the
app, in the database or in git.

## 4. Deploy the functions

```bash
supabase functions deploy billing-subscribe
supabase functions deploy billing-webhook
```

## 5. Add the webhook in Razorpay

Razorpay Dashboard → Settings → Webhooks → Add:

- URL: `https://<project-ref>.supabase.co/functions/v1/billing-webhook`
- Secret: the value of `RAZORPAY_BILLING_WEBHOOK_SECRET`
- Events: `subscription.authenticated`, `subscription.activated`,
  `subscription.charged`, `subscription.pending`, `subscription.halted`,
  `subscription.cancelled`, `subscription.completed`,
  `subscription.paused`, `subscription.resumed`, `subscription.updated`.

## What happens then

- The owner sees **Auto-pay** under their plan in Settings, picks a plan,
  and authorises auto-pay on Razorpay's page. The first charge is on the
  day after their current trial or paid period ends (or at once if there
  is none).
- Every successful charge moves the plan's paid-until date to the end of
  the charged month and records a payment the owner sees in the sheet;
  the console shows "Auto-pay: On · Last payment …".
- If Razorpay gives up after failed retries, the plan shows Lapsed (it
  still locks nothing). Cancelling auto-pay keeps the plan paid until the
  end of the period.
- The platform admin can still change any plan by hand; the next Razorpay
  event applies on top.

## Checking it without a real account

The automated tests never call Razorpay. To try the webhook locally,
see Task 10 of `docs/superpowers/plans/2026-09-25-p8-subscription-auto-billing.md`
(a signed fixture event posted to `supabase functions serve`).
````

- [ ] **Step 6: Commit**

```bash
git add supabase/functions/billing-webhook supabase/config.toml docs/subscription-billing.md
git commit -m "$(cat <<'EOF'
feat(billing): billing-webhook Edge Function, function config and setup guide

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

## Phase 3: App track (after Task 1; Tasks 8 and 9 side by side)

### Task 8: The owner's auto-pay card and sheet

**Track:** App. **Depends on:** Task 1.

**Files:**
- Create: `lib/features/owner/subscription_billing_card.dart`
- Create: `lib/features/owner/manage_subscription_sheet.dart`
- Modify: `lib/features/owner/owner_settings_screen.dart` (the card under the Plan tile)
- Test: `test/features/owner/subscription_billing_card_test.dart`
- Modify: `test/features/owner/owner_settings_screen_test.dart` (override `billingSourceProvider`; one new test)

**Interfaces:**
- Consumes:
  - From Task 1: `BillingSource`, `billingSourceProvider`, `billingAvailabilityProvider`, `resortBillingProvider` and `subscriptionInvoicesProvider`; `BillingAvailability`, `ResortBilling.canCancel`, `SubscribeAction`, `CancelAction`, `billingStatusLine` and `lastPaymentLine`; and `FakeBillingSource`, `billablePlans`, `resortBilling()` and `subscriptionInvoice()`.
  - Existing: `resortPlanProvider` and `resortPlanSourceProvider` (`subscription_repository.dart`), `FakeResortPlanSource`, `resortPlan()` (`fake_platform_source.dart`), `FailureView.messageFor`, `formatInr`, `formatDate`, `Spacing` (`core/theme/tokens.dart`), and `url_launcher`'s `launchUrl`.
- Produces:
  - `SubscriptionBillingCard({required String propertyId})`
  - `ManageSubscriptionSheet({required String propertyId, required List<SubscriptionPlan> plans, ResortBilling? billing, SubscriptionTier? currentTier})`, which pops a `String?` snackbar message
  - `typedef BillingLinkOpener = Future<bool> Function(Uri uri)` and `billingLinkOpenerProvider`
  - Widget keys:
    - on the card: `owner-billing-card`, `billing-status-line`, `billing-last-payment`, `billing-manage-btn`, `billing-refresh`
    - in the sheet: `billing-tier-<tier>`, `billing-continue`, `billing-cancel`, `billing-cancel-confirm`, `billing-error`, `billing-invoice-<id>`

- [ ] **Step 1: Write the failing widget tests**

Create `test/features/owner/subscription_billing_card_test.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/errors.dart';
import 'package:pasala/data/models/billing.dart';
import 'package:pasala/data/models/subscription.dart';
import 'package:pasala/data/repositories/billing_repository.dart';
import 'package:pasala/data/repositories/subscription_repository.dart';
import 'package:pasala/features/owner/manage_subscription_sheet.dart';
import 'package:pasala/features/owner/subscription_billing_card.dart';

import '../../support/fake_billing_source.dart';
import '../../support/fake_platform_source.dart';
import '../../support/fake_resort_plan_source.dart';

/// Pumps the card for resort p1 (a Starter trial by default) and returns
/// the links the card asked to open.
Future<List<Uri>> _pump(
  WidgetTester tester,
  FakeBillingSource billing, {
  bool opens = true,
}) async {
  final opened = <Uri>[];
  final plans = FakeResortPlanSource()
    ..plan = resortPlan(
        tier: SubscriptionTier.starter,
        status: SubscriptionStatus.trial,
        trialEndsOn: DateTime(2026, 10, 5));
  await tester.pumpWidget(ProviderScope(
    retry: (_, _) => null,
    overrides: [
      billingSourceProvider.overrideWithValue(billing),
      resortPlanSourceProvider.overrideWithValue(plans),
      billingLinkOpenerProvider.overrideWithValue((uri) async {
        opened.add(uri);
        return opens;
      }),
    ],
    child: const MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: SubscriptionBillingCard(propertyId: 'p1'),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return opened;
}

FakeBillingSource _configured({ResortBilling? billing}) => FakeBillingSource()
  ..availabilityValue = billablePlans
  ..billingValue = billing;

Future<void> _openSheet(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('billing-manage-btn')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders nothing when auto-pay is not configured',
      (tester) async {
    final billing = FakeBillingSource();
    await _pump(tester, billing);

    expect(find.byKey(const Key('owner-billing-card')), findsNothing);
    expect(billing.availabilityCalls, ['p1']);
    expect(billing.billingCalls, isEmpty);
  });

  testWidgets('renders nothing when no plan has a Razorpay plan id',
      (tester) async {
    await _pump(tester,
        FakeBillingSource()..availabilityValue = const BillingAvailability(configured: true));

    expect(find.byKey(const Key('owner-billing-card')), findsNothing);
  });

  testWidgets('with no auto-pay yet: the state and the button', (tester) async {
    await _pump(tester, _configured());

    expect(find.text('Auto-pay'), findsOneWidget);
    expect(find.text('No auto-pay set up'), findsOneWidget);
    expect(find.byKey(const Key('billing-last-payment')), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Pay / manage subscription'),
        findsOneWidget);
  });

  testWidgets('shows the auto-pay state and the last payment', (tester) async {
    await _pump(tester, _configured(billing: resortBilling()));

    expect(find.text('Auto-pay on · next charge 1 Nov 2026'), findsOneWidget);
    expect(find.text('Last payment ₹7,999 on 1 Oct 2026'), findsOneWidget);
  });

  testWidgets('a billing load error keeps the button', (tester) async {
    await _pump(tester, _configured()..billingError = const NetworkFailure());

    expect(find.text('Could not load auto-pay'), findsOneWidget);
    expect(find.byKey(const Key('billing-manage-btn')), findsOneWidget);
  });

  testWidgets('Refresh asks the server again', (tester) async {
    final billing = _configured();
    await _pump(tester, billing);
    expect(billing.billingCalls, ['p1']);

    await tester.tap(find.byKey(const Key('billing-refresh')));
    await tester.pumpAndSettle();

    expect(billing.billingCalls, ['p1', 'p1']);
  });

  testWidgets(
      'the sheet lists the billable plans with prices, preselects the current '
      'plan, and has no cancel without auto-pay', (tester) async {
    await _pump(tester, _configured());
    await _openSheet(tester);

    expect(find.text('₹2,999 / month'), findsOneWidget);
    expect(find.text('₹7,999 / month'), findsOneWidget);
    expect(
        find.descendant(
            of: find.byKey(const Key('billing-tier-starter')),
            matching: find.byIcon(Icons.radio_button_checked)),
        findsOneWidget);
    expect(find.byKey(const Key('billing-cancel')), findsNothing);
    expect(find.text('No payments yet'), findsOneWidget);
  });

  testWidgets('Continue subscribes to the chosen plan and opens Razorpay',
      (tester) async {
    final billing = _configured();
    final opened = await _pump(tester, billing);
    await _openSheet(tester);

    await tester.tap(find.byKey(const Key('billing-tier-pro')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('billing-continue')));
    await tester.pumpAndSettle();

    expect(billing.subscribeCalls, [('p1', SubscriptionTier.pro)]);
    expect(opened, [Uri.parse('https://rzp.io/i/test')]);
    expect(find.text('Continue to payment'), findsNothing);
    expect(find.text('Finish the payment on the Razorpay page, then tap Refresh.'),
        findsOneWidget);
    expect(billing.billingCalls, ['p1', 'p1']);
  });

  testWidgets('auto-pay already on for that plan: a note, no link',
      (tester) async {
    final billing = _configured(billing: resortBilling())
      ..subscribeResult = const SubscribeResult(
        action: SubscribeAction.unchanged,
        subscriptionId: 'sub_Current000001',
        shortUrl: 'https://rzp.io/i/current',
        status: GatewayStatus.active,
      );
    final opened = await _pump(tester, billing);
    await _openSheet(tester);

    await tester.tap(find.byKey(const Key('billing-continue')));
    await tester.pumpAndSettle();

    expect(billing.subscribeCalls, [('p1', SubscriptionTier.pro)]);
    expect(opened, isEmpty);
    expect(find.text('Auto-pay is already on for Pro.'), findsOneWidget);
  });

  testWidgets('a refusal stays in the sheet with its message', (tester) async {
    await _pump(tester, _configured()..subscribeError = const BillingUnavailable());
    await _openSheet(tester);

    await tester.tap(find.byKey(const Key('billing-continue')));
    await tester.pumpAndSettle();

    expect(
        find.text(
            "Online payment isn't set up for this plan yet. Contact ResortHub."),
        findsOneWidget);
    expect(find.byKey(const Key('billing-continue')), findsOneWidget);
  });

  testWidgets('a link that cannot be opened is reported', (tester) async {
    await _pump(tester, _configured(), opens: false);
    await _openSheet(tester);

    await tester.tap(find.byKey(const Key('billing-continue')));
    await tester.pumpAndSettle();

    expect(find.text('Could not open https://rzp.io/i/test'), findsOneWidget);
  });

  testWidgets('a second tap while subscribing makes no second call',
      (tester) async {
    final billing = _configured()..hold = Completer<void>();
    await _pump(tester, billing);
    await _openSheet(tester);

    await tester.tap(find.byKey(const Key('billing-continue')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('billing-continue')),
        warnIfMissed: false);
    await tester.pump();
    expect(billing.subscribeCalls, hasLength(1));

    billing.hold!.complete();
    await tester.pumpAndSettle();
    expect(billing.subscribeCalls, hasLength(1));
  });

  testWidgets('Cancel auto-pay asks first, then ends auto-pay with the period',
      (tester) async {
    final billing = _configured(billing: resortBilling());
    await _pump(tester, billing);
    await _openSheet(tester);

    await tester.tap(find.byKey(const Key('billing-cancel')));
    await tester.pumpAndSettle();
    expect(find.text('Cancel auto-pay?'), findsOneWidget);
    await tester.tap(find.text('Keep auto-pay'));
    await tester.pumpAndSettle();
    expect(billing.cancelCalls, isEmpty);

    await tester.tap(find.byKey(const Key('billing-cancel')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('billing-cancel-confirm')));
    await tester.pumpAndSettle();

    expect(billing.cancelCalls, ['p1']);
    expect(find.text('Auto-pay will end with the current period.'),
        findsOneWidget);
  });

  testWidgets('no Cancel auto-pay when it is already ending', (tester) async {
    await _pump(tester,
        _configured(billing: resortBilling(cancelAtCycleEnd: true)));
    await _openSheet(tester);

    expect(find.byKey(const Key('billing-cancel')), findsNothing);
  });

  testWidgets('the sheet lists the payments', (tester) async {
    await _pump(tester, _configured()..invoiceList = [subscriptionInvoice()]);
    await _openSheet(tester);

    expect(find.text('1 Oct 2026 · Pro'), findsOneWidget);
    expect(find.text('₹7,999'), findsOneWidget);
  });
}
```

In `test/features/owner/owner_settings_screen_test.dart`:

1. Add the imports `import 'package:pasala/data/repositories/billing_repository.dart';` and `import '../../support/fake_billing_source.dart';`.
2. Replace the `_pump` function with:

```dart
Future<void> _pump(
  WidgetTester tester,
  FakeResortPlanSource source, {
  FakeBillingSource? billing,
}) async {
  await tester.pumpWidget(ProviderScope(
    // retry: null -- without it Riverpod 3 keeps retrying a failed
    // provider and the error state never settles.
    retry: (_, _) => null,
    overrides: [
      currentResortProvider.overrideWith(() => _FixedResort(_resort)),
      propertyProvider.overrideWith((ref, id) async => _property),
      resortPlanSourceProvider.overrideWithValue(source),
      billingSourceProvider.overrideWithValue(billing ?? FakeBillingSource()),
    ],
    child: const MaterialApp(home: OwnerSettingsScreen()),
  ));
  await tester.pumpAndSettle();
}
```

3. Add at the end of `main()`:

```dart
  testWidgets('the auto-pay card sits under the plan tile when configured',
      (tester) async {
    final source = FakeResortPlanSource()
      ..plan = resortPlan(
          tier: SubscriptionTier.pro, paidThrough: DateTime(2026, 10, 31));
    await _pump(tester, source,
        billing: FakeBillingSource()..availabilityValue = billablePlans);

    expect(find.byKey(const Key('owner-billing-card')), findsOneWidget);
    expect(
        tester.getTopLeft(find.byKey(const Key('owner-billing-card'))).dy,
        greaterThan(
            tester.getTopLeft(find.byKey(const Key('owner-plan-tile'))).dy));
  });

  testWidgets('without Razorpay the Settings screen is unchanged',
      (tester) async {
    await _pump(tester, FakeResortPlanSource()..plan = resortPlan());

    expect(find.byKey(const Key('owner-billing-card')), findsNothing);
    expect(find.text('Farmhouse information'), findsOneWidget);
  });
```

- [ ] **Step 2: Run them to verify they fail**

Run: `flutter test test/features/owner/subscription_billing_card_test.dart test/features/owner/owner_settings_screen_test.dart`
Expected: FAIL to compile, with `Target of URI doesn't exist: 'package:pasala/features/owner/manage_subscription_sheet.dart'`.

- [ ] **Step 3: Write the sheet**

Create `lib/features/owner/manage_subscription_sheet.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/errors.dart';
import '../../core/format.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/failure_view.dart';
import '../../data/models/billing.dart';
import '../../data/models/subscription.dart';
import '../../data/repositories/billing_repository.dart';

/// Opens Razorpay's hosted subscription page. A seam, so widget tests
/// never launch a browser.
typedef BillingLinkOpener = Future<bool> Function(Uri uri);

final billingLinkOpenerProvider = Provider<BillingLinkOpener>(
  (ref) => (uri) => launchUrl(uri, mode: LaunchMode.externalApplication),
);

/// "Pay / manage subscription" (P8): pick a plan and continue to Razorpay,
/// or cancel auto-pay; the last payments below. Pops with the message the
/// Settings screen shows as a snackbar, or null when dismissed.
class ManageSubscriptionSheet extends ConsumerStatefulWidget {
  const ManageSubscriptionSheet({
    super.key,
    required this.propertyId,
    required this.plans,
    this.billing,
    this.currentTier,
  });

  final String propertyId;

  /// The plans with a Razorpay plan id, from the probe. Never empty: the
  /// card only offers the sheet when there is one.
  final List<SubscriptionPlan> plans;
  final ResortBilling? billing;

  /// The resort's plan today, preselected when it can be paid online.
  final SubscriptionTier? currentTier;

  @override
  ConsumerState<ManageSubscriptionSheet> createState() =>
      _ManageSubscriptionSheetState();
}

class _ManageSubscriptionSheetState
    extends ConsumerState<ManageSubscriptionSheet> {
  late SubscriptionTier _tier = _initialTier();
  bool _busy = false;
  String? _error;

  SubscriptionTier _initialTier() {
    final billable = widget.plans.map((p) => p.tier).toSet();
    for (final tier in [widget.billing?.tier, widget.currentTier]) {
      if (tier != null && billable.contains(tier)) return tier;
    }
    return widget.plans.first.tier;
  }

  String get _planName =>
      widget.plans.firstWhere((p) => p.tier == _tier).name;

  Future<void> _continue() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await ref
          .read(billingSourceProvider)
          .subscribe(widget.propertyId, _tier);
      if (!mounted) return;
      if (result.action == SubscribeAction.unchanged) {
        Navigator.of(context).pop('Auto-pay is already on for $_planName.');
        return;
      }
      final url = result.shortUrl;
      final opened =
          url != null && await ref.read(billingLinkOpenerProvider)(Uri.parse(url));
      if (!mounted) return;
      if (!opened) {
        setState(() {
          _busy = false;
          _error = url == null
              ? 'Razorpay did not send a payment link. Try again.'
              : 'Could not open $url';
        });
        return;
      }
      Navigator.of(context)
          .pop('Finish the payment on the Razorpay page, then tap Refresh.');
    } on BookingFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = FailureView.messageFor(e);
      });
    }
  }

  Future<void> _cancel() async {
    // Pop with the dialog's own context (see resort_card.dart).
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cancel auto-pay?'),
        content: const Text('Your plan stays paid until the end of the '
            'current period. Nothing more is charged.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep auto-pay'),
          ),
          FilledButton(
            key: const Key('billing-cancel-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Cancel auto-pay'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final action =
          await ref.read(billingSourceProvider).cancel(widget.propertyId);
      if (!mounted) return;
      Navigator.of(context).pop(switch (action) {
        CancelAction.cancelScheduled =>
          'Auto-pay will end with the current period.',
        CancelAction.cancelled => 'Auto-pay cancelled.',
        CancelAction.none => 'There was no auto-pay to cancel.',
      });
    } on BookingFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = FailureView.messageFor(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final invoices = ref.watch(subscriptionInvoicesProvider(widget.propertyId));

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(Spacing.md, Spacing.md, Spacing.md,
            Spacing.md + MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Pay / manage subscription', style: textTheme.titleLarge),
              const SizedBox(height: Spacing.xs),
              Text(
                'Razorpay charges your plan every month. A change of plan '
                'starts when your current period ends.',
                style: textTheme.bodySmall,
              ),
              const SizedBox(height: Spacing.sm),
              for (final plan in widget.plans)
                ListTile(
                  key: Key('billing-tier-${subscriptionTierToDb(plan.tier)}'),
                  title: Text(plan.name),
                  subtitle: Text('${formatInr(plan.monthlyPriceInr)} / month'),
                  selected: plan.tier == _tier,
                  trailing: Icon(plan.tier == _tier
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked),
                  onTap: _busy ? null : () => setState(() => _tier = plan.tier),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: Spacing.sm),
                  child: Text(
                    _error!,
                    key: const Key('billing-error'),
                    style: TextStyle(color: scheme.error),
                  ),
                ),
              const SizedBox(height: Spacing.sm),
              FilledButton(
                key: const Key('billing-continue'),
                onPressed: _busy ? null : _continue,
                child: const Text('Continue to payment'),
              ),
              if (widget.billing?.canCancel ?? false)
                TextButton(
                  key: const Key('billing-cancel'),
                  onPressed: _busy ? null : _cancel,
                  child: const Text('Cancel auto-pay'),
                ),
              const Divider(height: Spacing.lg),
              Text('Payments', style: textTheme.titleSmall),
              switch (invoices) {
                AsyncData(:final value) when value.isEmpty =>
                  const Text('No payments yet'),
                AsyncData(:final value) => Column(
                    children: [
                      for (final invoice in value)
                        ListTile(
                          key: Key('billing-invoice-${invoice.id}'),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                              '${formatDate(invoice.paidAt)} · ${invoice.tier.label}'),
                          trailing: Text(formatInr(invoice.amountInr)),
                        ),
                    ],
                  ),
                AsyncError() => const Text('Could not load payments'),
                _ => const Text('Loading…'),
              },
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Write the card and add it to Settings**

Create `lib/features/owner/subscription_billing_card.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../../data/models/billing.dart';
import '../../data/models/subscription.dart';
import '../../data/repositories/billing_repository.dart';
import '../../data/repositories/subscription_repository.dart';
import 'manage_subscription_sheet.dart';

/// Auto-pay for the resort's ResortHub plan (P8), under the Plan tile in
/// Settings. Renders nothing unless billing-subscribe says auto-pay can be
/// offered (Razorpay keys set, and at least one plan has a Razorpay plan
/// id), so a deployment without Razorpay keeps its manual plans exactly as
/// before. Owner-only, like the rest of `/owner/settings`.
class SubscriptionBillingCard extends ConsumerWidget {
  const SubscriptionBillingCard({super.key, required this.propertyId});

  final String propertyId;

  void _refresh(WidgetRef ref) {
    ref.invalidate(resortBillingProvider(propertyId));
    ref.invalidate(subscriptionInvoicesProvider(propertyId));
    ref.invalidate(resortPlanProvider(propertyId));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final availability =
        switch (ref.watch(billingAvailabilityProvider(propertyId))) {
      AsyncData(:final value) when value.canPay => value,
      _ => null,
    };
    if (availability == null) return const SizedBox.shrink();

    final (statusLine, billing) =
        switch (ref.watch(resortBillingProvider(propertyId))) {
      AsyncData(:final value) =>
        (value == null ? 'No auto-pay set up' : billingStatusLine(value), value),
      AsyncError() => ('Could not load auto-pay', null),
      _ => ('Loading…', null),
    };
    final currentTier = switch (ref.watch(resortPlanProvider(propertyId))) {
      AsyncData(:final value) => value?.tier,
      _ => null,
    };
    final paid = billing == null
        ? null
        : lastPaymentLine(billing.lastPaymentInr, billing.lastPaymentAt);
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      key: const Key('owner-billing-card'),
      margin: const EdgeInsets.only(bottom: Spacing.sm),
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.autorenew, color: scheme.secondary),
                const SizedBox(width: Spacing.sm),
                Expanded(child: Text('Auto-pay', style: textTheme.titleMedium)),
                IconButton(
                  key: const Key('billing-refresh'),
                  tooltip: 'Refresh',
                  icon: const Icon(Icons.refresh),
                  onPressed: () => _refresh(ref),
                ),
              ],
            ),
            Text(statusLine, key: const Key('billing-status-line')),
            if (paid != null)
              Text(
                paid,
                key: const Key('billing-last-payment'),
                style: textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            const SizedBox(height: Spacing.sm),
            FilledButton.tonal(
              key: const Key('billing-manage-btn'),
              onPressed: () => _openSheet(
                  context, ref, availability, billing, currentTier),
              child: const Text('Pay / manage subscription'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openSheet(
    BuildContext context,
    WidgetRef ref,
    BillingAvailability availability,
    ResortBilling? billing,
    SubscriptionTier? currentTier,
  ) async {
    final message = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ManageSubscriptionSheet(
        propertyId: propertyId,
        plans: availability.plans,
        billing: billing,
        currentTier: currentTier,
      ),
    );
    if (!context.mounted) return;
    _refresh(ref);
    if (message != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }
}
```

In `lib/features/owner/owner_settings_screen.dart`:
1. Add `import 'subscription_billing_card.dart';` after `import 'payment_settings_screen.dart';`.
2. Replace `              _PlanTile(propertyId: propertyId),` with:

```dart
              _PlanTile(propertyId: propertyId),
              // P8: renders nothing unless Razorpay auto-pay is configured.
              SubscriptionBillingCard(propertyId: propertyId),
```

3. In the class doc comment, replace `The Plan tile at the top shows the
/// resort's ResortHub plan, read-only.` with `The Plan tile at the top shows the
/// resort's ResortHub plan, read-only, with the auto-pay card under it when
/// Razorpay billing is configured (P8).`

- [ ] **Step 5: Run the tests and the analyzer**

Run: `flutter test test/features/owner`
Expected: PASS: all the card tests, and the Settings tests old and new.

Run: `flutter analyze`
Expected: no issues beyond the baseline.

- [ ] **Step 6: Commit**

```bash
git add lib/features/owner/subscription_billing_card.dart lib/features/owner/manage_subscription_sheet.dart \
  lib/features/owner/owner_settings_screen.dart test/features/owner/subscription_billing_card_test.dart \
  test/features/owner/owner_settings_screen_test.dart
git commit -m "$(cat <<'EOF'
feat(owner): Auto-pay card and Pay / manage subscription sheet in Settings

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 9: Console: Razorpay plan ids and each resort's last payment

**Track:** App. **Depends on:** Task 1. It can run alongside Task 8.

**Files:**
- Modify: `lib/features/platform/plan_prices_dialog.dart` (whole file)
- Modify: `lib/features/platform/resort_card.dart` (billing line)
- Modify: `lib/features/platform/platform_screen.dart` (`_refresh`)
- Test: `test/features/platform/plan_prices_dialog_test.dart`, `test/features/platform/resort_card_test.dart`, `test/features/platform/platform_screen_test.dart` (new tests appended)

**Interfaces:**
- Consumes: from Task 1, `PlatformSource.billing()`, `PlatformSource.setRazorpayPlanId()`, `platformBillingProvider`, `PlatformBilling`, `GatewayStatusLabel.label`, `lastPaymentLine` and `SubscriptionPlan.razorpayPlanId`, plus `FakePlatformSource.billingList` / `billingError` / `planIdError` / `billingCalls` / `planIdCalls`. Also the existing `_openFromConsole`, `_field` and `_save` (plan prices test), `_pump` (resort card test) and `_appFor`, `_resortA` and `_resortB` (platform screen test).
- Produces: the widget keys `plan-razorpay-<tier>` (dialog) and `resort-billing-<propertyId>` (card).

- [ ] **Step 1: Write the failing tests**

Append inside `main()` of `test/features/platform/plan_prices_dialog_test.dart`:

```dart
  testWidgets("shows each plan's Razorpay plan id and saves only the changes",
      (tester) async {
    final source = FakePlatformSource()
      ..store = [resortSummary()]
      ..planList = [
        for (final p in defaultPlans)
          SubscriptionPlan(
            tier: p.tier,
            name: p.name,
            monthlyPriceInr: p.monthlyPriceInr,
            sortOrder: p.sortOrder,
            razorpayPlanId: p.tier == SubscriptionTier.starter
                ? 'plan_StarterMon001'
                : null,
          ),
      ];
    await _openFromConsole(tester, source);

    expect(_field(tester, 'plan-razorpay-starter'), 'plan_StarterMon001');
    expect(_field(tester, 'plan-razorpay-pro'), '');

    await tester.ensureVisible(find.byKey(const Key('plan-razorpay-starter')));
    await tester.enterText(find.byKey(const Key('plan-razorpay-starter')), '');
    await tester.ensureVisible(find.byKey(const Key('plan-razorpay-pro')));
    await tester.enterText(
        find.byKey(const Key('plan-razorpay-pro')), ' plan_ProMonthly0001 ');
    await _save(tester);

    expect(source.priceCalls, isEmpty);
    expect(source.planIdCalls, [
      (SubscriptionTier.starter, null),
      (SubscriptionTier.pro, 'plan_ProMonthly0001'),
    ]);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('a malformed Razorpay plan id is refused and nothing is saved',
      (tester) async {
    final source = FakePlatformSource()..store = [resortSummary()];
    await _openFromConsole(tester, source);

    await tester.ensureVisible(find.byKey(const Key('plan-razorpay-pro')));
    await tester.enterText(find.byKey(const Key('plan-razorpay-pro')), 'pro-monthly');
    await _save(tester);

    expect(
        find.text(
            'A Razorpay plan id looks like plan_ followed by letters and digits.'),
        findsOneWidget);
    expect(source.planIdCalls, isEmpty);
    expect(source.priceCalls, isEmpty);
    expect(find.byType(AlertDialog), findsOneWidget);
  });

  testWidgets('a refused plan id shows the server message', (tester) async {
    final source = FakePlatformSource()
      ..store = [resortSummary()]
      ..planIdError = const InvalidState(
          'That Razorpay plan id is already used by another plan.');
    await _openFromConsole(tester, source);

    await tester.ensureVisible(find.byKey(const Key('plan-razorpay-pro')));
    await tester.enterText(
        find.byKey(const Key('plan-razorpay-pro')), 'plan_ProMonthly0001');
    await _save(tester);

    expect(find.text('That Razorpay plan id is already used by another plan.'),
        findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget);
  });
```

In `test/features/platform/resort_card_test.dart`, add the imports `import 'package:pasala/core/errors.dart';` and `import 'package:pasala/data/models/billing.dart';`, then append inside `main()`:

```dart
  testWidgets('shows the auto-pay state and the last payment', (tester) async {
    final source = FakePlatformSource()
      ..billingList = [
        PlatformBilling(
          propertyId: 'p1',
          status: GatewayStatus.active,
          tier: SubscriptionTier.pro,
          lastPaymentAt: DateTime(2026, 10, 1),
          lastPaymentInr: 7999,
        ),
      ];
    await _pump(tester, source, resortSummary(plan: resortPlan()));

    expect(find.text('Auto-pay: On · Last payment ₹7,999 on 1 Oct 2026'),
        findsOneWidget);
  });

  testWidgets('a halted auto-pay with no payment yet says so', (tester) async {
    final source = FakePlatformSource()
      ..billingList = [
        const PlatformBilling(propertyId: 'p1', status: GatewayStatus.halted),
      ];
    await _pump(tester, source, resortSummary(plan: resortPlan()));

    expect(find.text('Auto-pay: Stopped after failed payments'), findsOneWidget);
  });

  testWidgets('no billing line for a resort that never had auto-pay',
      (tester) async {
    final source = FakePlatformSource()
      ..billingList = [
        const PlatformBilling(propertyId: 'p2', status: GatewayStatus.active),
      ];
    await _pump(tester, source, resortSummary(plan: resortPlan()));

    expect(find.byKey(const Key('resort-billing-p1')), findsNothing);
  });

  testWidgets('a billing load error leaves the card as it was',
      (tester) async {
    final source = FakePlatformSource()..billingError = const NetworkFailure();
    await tester.pumpWidget(ProviderScope(
      retry: (_, _) => null,
      overrides: [platformSourceProvider.overrideWithValue(source)],
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ResortCard(
                resort: resortSummary(plan: resortPlan()), onChanged: () {}),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('resort-billing-p1')), findsNothing);
    expect(find.widgetWithText(TextButton, 'Change plan'), findsOneWidget);
  });
```

Append inside `main()` of `test/features/platform/platform_screen_test.dart`:

```dart
  testWidgets('a change refetches the billing column too', (tester) async {
    final repo = FakePlatformSource()..store = [_resortA, _resortB];
    await tester.pumpWidget(_appFor(repo));
    await tester.pumpAndSettle();
    expect(repo.billingCalls, 1);

    await tester.tap(find.byKey(const Key('resort-status-btn-p1')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Suspend'));
    await tester.pumpAndSettle();

    expect(repo.billingCalls, 2);
  });
```

- [ ] **Step 2: Run them to verify they fail**

Run: `flutter test test/features/platform`
Expected: FAIL in the new tests:
- `Bad state: No element` for `plan-razorpay-starter`
- the `Auto-pay: …` texts are not found
- `billingCalls` is 0 where 1 is expected

- [ ] **Step 3: Write the plan id fields**

Replace `lib/features/platform/plan_prices_dialog.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../core/theme/spacing.dart';
import '../../core/widgets/failure_view.dart';
import '../../data/models/subscription.dart';
import '../../data/repositories/platform_repository.dart';

/// "Plan prices" (spec decision 11): the monthly INR price of each plan,
/// and (P8) the Razorpay plan behind it -- blank keeps that plan billed by
/// hand. Save sends only what changed, through `set_plan_price` and
/// `set_plan_razorpay_id`. A change applies to every resort on that plan
/// at once, so the list, the cards (MRR) and the plans are refetched --
/// even after a partial failure, because the changes saved before it are
/// real.
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
  late final Map<SubscriptionTier, TextEditingController> _planIds = {
    for (final plan in widget.plans)
      plan.tier: TextEditingController(text: plan.razorpayPlanId ?? ''),
  };
  String? _error;
  bool _busy = false;

  /// The same rule as the database's check (0057_subscription_billing.sql).
  static final _planIdPattern = RegExp(r'^plan_[A-Za-z0-9]{6,40}$');

  static String _show(num price) =>
      price % 1 == 0 ? price.toStringAsFixed(0) : price.toStringAsFixed(2);

  @override
  void dispose() {
    for (final c in [..._prices.values, ..._planIds.values]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final changes = <SubscriptionTier, num>{};
    final planIdChanges = <SubscriptionTier, String?>{};
    for (final plan in widget.plans) {
      final text = _prices[plan.tier]!.text.trim().replaceAll(',', '');
      final value = num.tryParse(text);
      if (value == null || value < 0) {
        setState(() =>
            _error = 'Enter a monthly price of 0 or more for every plan.');
        return;
      }
      if (value != plan.monthlyPriceInr) changes[plan.tier] = value;

      final id = _planIds[plan.tier]!.text.trim();
      if (id.isNotEmpty && !_planIdPattern.hasMatch(id)) {
        setState(() => _error = 'A Razorpay plan id looks like plan_ '
            'followed by letters and digits.');
        return;
      }
      final newId = id.isEmpty ? null : id;
      if (newId != plan.razorpayPlanId) planIdChanges[plan.tier] = newId;
    }
    if (changes.isEmpty && planIdChanges.isEmpty) {
      Navigator.of(context).pop();
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    BookingFailure? failure;
    try {
      final source = ref.read(platformSourceProvider);
      for (final change in changes.entries) {
        await source.setPlanPrice(change.key, change.value);
      }
      for (final change in planIdChanges.entries) {
        await source.setRazorpayPlanId(change.key, change.value);
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
              const SizedBox(height: Spacing.md),
              Text('Razorpay auto-pay',
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: Spacing.sm),
              for (final plan in widget.plans)
                Padding(
                  padding: const EdgeInsets.only(bottom: Spacing.sm),
                  child: TextField(
                    key: Key('plan-razorpay-${subscriptionTierToDb(plan.tier)}'),
                    controller: _planIds[plan.tier],
                    decoration: InputDecoration(
                      labelText: '${plan.name} Razorpay plan id',
                      helperText: 'Blank = billed by hand',
                    ),
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

- [ ] **Step 4: Write the billing line and the refresh**

In `lib/features/platform/resort_card.dart`:

1. Add `import '../../data/models/billing.dart';` after `import '../../core/widgets/failure_view.dart';`.
2. In `ResortCard.build`, directly after the `Wrap` that holds the tier chip and `PlanLine` (the one ending `if (plan != null) PlanLine(plan: plan),` / `],` / `),`), insert:

```dart
            _BillingLine(propertyId: resort.propertyId),
```

3. Add at the end of the file:

```dart
/// The `Auto-pay: …` line (P8): the auto-pay state and the last payment.
/// Nothing for a resort that never had auto-pay, while loading, or when
/// the billing read fails: it is extra detail and never hides the card.
class _BillingLine extends ConsumerWidget {
  const _BillingLine({required this.propertyId});

  final String propertyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entry = switch (ref.watch(platformBillingProvider)) {
      AsyncData(:final value) => value[propertyId],
      _ => null,
    };
    if (entry == null) return const SizedBox.shrink();
    final status = entry.status;
    final paid = lastPaymentLine(entry.lastPaymentInr, entry.lastPaymentAt);
    final parts = [
      if (status != null) 'Auto-pay: ${status.label}',
      ?paid,
    ];
    if (parts.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: Spacing.xs),
      child: Text(
        parts.join(' · '),
        key: Key('resort-billing-$propertyId'),
        style: Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    );
  }
}
```

In `lib/features/platform/platform_screen.dart`, replace `_refresh` with:

```dart
  /// After any change the list, the cards and the billing column all move.
  void _refresh() {
    ref.invalidate(platformResortsProvider);
    ref.invalidate(platformTotalsProvider);
    ref.invalidate(platformBillingProvider);
  }
```

- [ ] **Step 5: Run the tests and the analyzer**

Run: `flutter test test/features/platform`
Expected: PASS: every existing console test, and the new ones.

Run: `flutter analyze`
Expected: no issues beyond the baseline.

- [ ] **Step 6: Commit**

```bash
git add lib/features/platform/plan_prices_dialog.dart lib/features/platform/resort_card.dart \
  lib/features/platform/platform_screen.dart test/features/platform/plan_prices_dialog_test.dart \
  test/features/platform/resort_card_test.dart test/features/platform/platform_screen_test.dart
git commit -m "$(cat <<'EOF'
feat(platform): Razorpay plan ids in Plan prices; auto-pay and last payment per resort

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

## Phase 4: Integration

### Task 10: Merge the tracks and verify end to end

**Track:** all. **Depends on:** Tasks 2–9.

**Files:**
- None created. This task only verifies. A fix belongs to the task that owns the file, and gets its own commit.
- The fixture secrets file lives in the session scratch directory, never in the repo.

**Interfaces:**
- Consumes: everything above.
- Produces: one branch where the database, the Edge Functions and the app agree on names and shapes, with every suite green.

- [ ] **Step 1: Merge**

If the tracks ran in separate worktrees, merge the database, Edge and app branches into the P8 branch. They own disjoint files, so no conflicts are expected. If another gap project has landed first, `supabase/config.toml`, `lib/core/errors.dart` and `test/core/errors_test.dart` may conflict at their ends. Keep both sides' additions.

- [ ] **Step 2: Check the contract by name**

Run: `grep -n "rpc('\|'p_[a-z_]*'\|billing-subscribe\|from('subscription_invoices')" lib/data/repositories/billing_repository.dart lib/data/repositories/platform_repository.dart`
Expected: `my_resort_billing` (`p_property`), `platform_billing`, `set_plan_razorpay_id` (`p_tier`, `p_plan_id`), `billing-subscribe`, and `subscription_invoices` with `property_id`.

Run: `grep -n "rpc<[A-Za-z]*>(\|p_[a-z_]*:" supabase/functions/_shared/billing/db.ts`
Expected: `billing_subscribe_state` (`p_property`, `p_tier`), `billing_subscription_opened` (`p_property`, `p_tier`, `p_razorpay_plan_id`, `p_razorpay_subscription_id`, `p_status`, `p_short_url`, `p_start_at`, `p_created_by`), `billing_subscription_cancel_requested` (`p_razorpay_subscription_id`, `p_at_cycle_end`, `p_status`, `p_actor`) and `billing_webhook_apply` (`p_event`, `p_event_at`, `p_subscription`, `p_payment`).

Compare them with `grep -n "create function public\.\(set_plan_razorpay_id\|my_resort_billing\|platform_billing\|billing_[a-z_]*\)" -A9 supabase/migrations/0057_subscription_billing.sql`.

- [ ] **Step 3: Run the full suites**

Run: `supabase db reset && supabase test db`
Expected: 47 at 95/95, 37 and 41 green, and every other file as in the Task 1 Step 1 baseline (at most the 3 known IST-midnight failures).

Run: `deno test supabase/functions/_shared/billing supabase/functions/billing-subscribe supabase/functions/billing-webhook`
Expected: 43 passed (15 + 17 + 11).

Run: `deno check supabase/functions/billing-subscribe/index.ts supabase/functions/billing-webhook/index.ts`
Expected: no errors.

Run: `flutter test`, then `flutter analyze`
Expected: every test passes, and the count is the baseline plus the tests this plan added. There are no analyzer issues beyond the 2 baseline infos.

- [ ] **Step 4: Smoke-test the functions against the local stack, without keys**

Run:
```bash
eval "$(supabase status -o env)"
supabase functions serve
```
(`functions serve` blocks. Run it in the background or in a second terminal, and stop it before Step 5.)

Then:
```bash
TOKEN=$(curl -s -X POST "$API_URL/auth/v1/token?grant_type=password" -H "apikey: $ANON_KEY" \
  -H 'Content-Type: application/json' -d '{"email":"super@pasala.test","password":"password123"}' | jq -r .access_token)
curl -s -X POST "$API_URL/functions/v1/billing-subscribe" -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"property_id":"a0000000-0000-0000-0000-000000000001","action":"probe"}'
```
Expected: `{"configured":false}`. `super@pasala.test` is the seeded Pasala owner.

Run: `curl -s -o /dev/null -w '%{http_code}\n' -X POST "$API_URL/functions/v1/billing-webhook" -d '{}'`
Expected: `503`.

- [ ] **Step 5: Smoke-test the functions with fixture secrets (fake values, never committed)**

Write the fixture file in the session scratch directory (`$SCRATCH`, outside the repo):

```bash
cat > "$SCRATCH/billing-fixture.env" <<'EOF'
RAZORPAY_KEY_ID=rzp_test_fixture
RAZORPAY_KEY_SECRET=fixture_secret_not_real
RAZORPAY_BILLING_WEBHOOK_SECRET=whsec_fixture_not_real
EOF
supabase functions serve --env-file "$SCRATCH/billing-fixture.env"
```

Then, in another shell with `eval "$(supabase status -o env)"` and `TOKEN` set as in Step 4:

```bash
curl -s -X POST "$API_URL/functions/v1/billing-subscribe" -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' -d '{"property_id":"a0000000-0000-0000-0000-000000000001","action":"probe"}'
# expected: {"configured":true,"plans":[]}

psql "$DB_URL" -c "update public.subscription_plans set razorpay_plan_id = 'plan_FixturePro001' where tier = 'pro'"
curl -s -X POST "$API_URL/functions/v1/billing-subscribe" -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' -d '{"property_id":"a0000000-0000-0000-0000-000000000001","action":"probe"}'
# expected: {"configured":true,"plans":[{"tier":"pro","name":"Pro","monthly_price_inr":7999}]}

psql "$DB_URL" -c "insert into public.billing_subscriptions (property_id, tier, razorpay_plan_id, razorpay_subscription_id, status) values ('a0000000-0000-0000-0000-000000000001', 'pro', 'plan_FixturePro001', 'sub_FixtureLocal01', 'authenticated')"

BODY='{"entity":"event","event":"subscription.charged","payload":{"subscription":{"entity":{"id":"sub_FixtureLocal01","status":"active","current_start":1790000000,"current_end":1792592000}},"payment":{"entity":{"id":"pay_FixtureLocal01","amount":799900,"currency":"INR","created_at":1790000100}}},"created_at":1790000200}'
SIG=$(printf '%s' "$BODY" | openssl dgst -sha256 -hmac 'whsec_fixture_not_real' | sed 's/^.* //')
curl -s -X POST "$API_URL/functions/v1/billing-webhook" -H "X-Razorpay-Signature: $SIG" \
  -H 'Content-Type: application/json' --data-binary "$BODY"
# expected: {"status":"processed","outcome":"charged"}
curl -s -X POST "$API_URL/functions/v1/billing-webhook" -H "X-Razorpay-Signature: $SIG" \
  -H 'Content-Type: application/json' --data-binary "$BODY"
# expected: {"status":"processed","outcome":"duplicate"}
curl -s -o /dev/null -w '%{http_code}\n' -X POST "$API_URL/functions/v1/billing-webhook" \
  -H 'X-Razorpay-Signature: 00' --data-binary "$BODY"
# expected: 401

psql "$DB_URL" -c "select tier, status, paid_through, ((to_timestamp(1792592000) - interval '1 second') at time zone 'Asia/Kolkata')::date as expected from public.resort_subscriptions where property_id = 'a0000000-0000-0000-0000-000000000001'"
# expected: pro | active | paid_through equal to expected
psql "$DB_URL" -c "select count(*), sum(amount_inr) from public.subscription_invoices"
# expected: 1 | 7999.00
```

Do **not** call `"action":"subscribe"` or `"cancel"` here. With fake keys they would reach the real Razorpay API. Those paths are covered by the Deno tests.

- [ ] **Step 6: Check the screens against the local stack**

With `supabase functions serve --env-file "$SCRATCH/billing-fixture.env"` still running, run `make run-web` and sign in as `super@pasala.test` / `password123`. Open Settings (`/owner/settings`) and confirm:
1. Under the Plan tile ("Plan: Pro", "Paid until <date>"), the **Auto-pay** card shows `Auto-pay on · next charge <date>` and `Last payment ₹7,999 on <date>`.
2. **Pay / manage subscription** opens the sheet with `Pro` / `₹7,999 / month` selected, `Cancel auto-pay`, and one payment listed. Close it without continuing.

Make a temporary platform admin: `psql "$DB_URL" -c "update public.profiles set role = 'platform_admin' where id = '10000000-0000-0000-0000-000000000006'"`. Sign in as `meera@example.com` / `password123`. On `/platform`, confirm:
3. Pasala's card shows `Auto-pay: On · Last payment ₹7,999 on <date>`.
4. **Plan prices** shows `plan_FixturePro001` in "Pro Razorpay plan id". Clearing it and saving turns Pro back to billed by hand.

Stop `functions serve`, start it again without `--env-file`, and reload Settings as the owner:
5. The Auto-pay card is gone, and the rest of Settings is unchanged.

- [ ] **Step 7: Clean up**

Run: `supabase db reset && rm -f "$SCRATCH/billing-fixture.env"`
Expected: the local database is back to migrations plus seed, and the fixture file is gone. Run `git status --short` and confirm no `.env` file and no `pubspec.lock` change is staged. Revert an SDK-only `pubspec.lock` bump with `git checkout pubspec.lock`.

- [ ] **Step 8: Commit any fixes**

For each fix, `git add <the fixed files>` and `git commit` with a message ending in a blank line and `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. If nothing needed fixing, there is nothing to commit.

---

## Self-Review

**1. Spec coverage**

| Spec requirement | Task |
|---|---|
| `subscription_plans.razorpay_plan_id` (format check, unique), set by the platform admin | 1 (column), 2 (`set_plan_razorpay_id`), 9 (dialog) |
| `billing_subscriptions` (one current per resort, Razorpay states, owner read, no writes) | 1 |
| `subscription_invoices` (unique payment, `fill_property_id` / P0021, owner read) | 1 |
| Platform admin has no row access; reads through `platform_billing` | 1 (RLS test), 2 |
| `my_resort_billing`, `platform_billing` | 2 |
| `billing_subscribe_state`: owner only, read mode (suspended OK), P0038, `start_at`, `current`, `stale`, `caller_id` | 2 |
| `billing_subscription_opened`: supersede, lock, idempotent, P0021, audit | 3 |
| `billing_subscription_cancel_requested` | 3 |
| Decisions 9–14 in `billing_webhook_apply`: charged, duplicate, late, no `current_end`, halted → Lapsed, cancelled only if charged, stale ordering, replaced live subscription handed back | 4 |
| Service-role-only writes, grants, allow-list | 1 (privileges), 3 and 4 (42501 checks) |
| Decision 2: configured = keys + plan ids; probe failure = manual | 1 (`availability`), 6 (keys missing), 8 (card hidden) |
| Decision 6: `start_at` | 2 (SQL), 6 (passed to Razorpay) |
| Decisions 7 and 8: create / reuse / unchanged, cancel replaced | 5 (`decideSubscribe`), 6 |
| Decision 9: cancel at cycle end / now | 5 (`decideCancel`), 6, 8 |
| Decision 15: `total_count` 60 | 6 (`TOTAL_COUNT`) |
| Decision 1: secret names and webhook fallback | 7 (`index.ts`), 7 (setup guide) |
| `billing-subscribe` HTTP contract (400/401/405/409/502/500, CORS) | 6 |
| `billing-webhook` contract (503/401/400/ignored/processed/500, best-effort cancel) | 7 |
| `verify_jwt` config | 7 |
| Owner card and sheet, Refresh, `url_launcher` seam | 8 |
| Console last payment and plan ids, refresh | 9 |
| P0038 copy | 1 |
| Setup guide `docs/subscription-billing.md` | 7 |
| Integration (local serve with fixture secrets, signed webhook, duplicate, probe without keys) | 10 |

**2. Placeholder scan.**
- Every code step carries its code. "Fill in" appears only in the setup guide's user instructions.
- The fixture secrets are deliberately fake literals.
- `<project-ref>`, `<date>` and `<plan>` are UI-copy and URL templates, not plan gaps.

**3. Type consistency.**
- SQL, Deno and Dart use the same names:
  - `billing_subscribe_state` keys, `ApplyResult`, `OpenedResult`
  - the probe's `plans` / `BillablePlan` / `BillingAvailability.plans`
  - `SubscribeResponse` / `SubscribeResult.fromJson`
  - `CancelResponse.action` / `cancelActionFromWire`
- `FakeBillingSource`'s fields (`availabilityValue`, `billingValue`, `invoiceList`, `subscribeResult`, `cancelResult`, `hold`, `…Calls`) are used with these names in Task 8.
- `FakePlatformSource.billingList` / `billingError` / `planIdError` / `billingCalls` / `planIdCalls` are used in Task 9.
- `billingLinkOpenerProvider` is defined in `manage_subscription_sheet.dart` (Task 8) and overridden in its test.

**4. Review Focus.** All five lines have owning tests:
1. Task 4 (R3 abandoned checkout).
2. Task 3 (supersede and `stale`), Task 6 (stale cleanup and warning), Task 8 (single call while in flight).
3. Task 4 (duplicate, late charge, stale halted).
4. Task 1 (probe 404 and network → off), Task 6 (no keys), Task 8 (hidden card, unchanged Settings).
5. Task 2 (suspended owner allowed; admin, staff, guest and platform admin refused).
