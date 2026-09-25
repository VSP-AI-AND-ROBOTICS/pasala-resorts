# Subscriptions and Tiers (REQ-08) — Design

## Why

The client's requirement REQ-08 (`docs/requirements/ResortHub_Requirements_For_Manager.pdf`,
priority CRITICAL) asks for a "Multi-Tenant Super Admin SaaS Management
Portal". Its pass criteria are two count cards ("Subscribed Resorts",
"Active Subscriptions"), a tier dropdown ("All Tiers / Starter / Pro /
Enterprise"), a live search bar and a "+ Add Resort" flow. The roles table
also says the Super Admin should "track platform MRR" (monthly recurring
revenue). The tenancy spec
(`docs/superpowers/specs/2026-09-24-resorthub-tenancy-design.md`) lists
"Subscriptions and platform billing" as sub-project #4 and left it out.

Today:
- `/platform` (`lib/features/platform/platform_screen.dart`) shows one card
  per resort (name, status chip, owner emails, 30/365-day bookings and
  revenue), a Suspend/Reactivate button (none for archived resorts) and a
  floating + that opens a "New resort" dialog. There are no count cards, no
  filter and no search.
- `platform_resorts()`, `set_resort_status(p_property, p_status)` and
  `create_resort(p_name, p_owner_email)` (all in `0045_resort_functions.sql`)
  are the platform admin's only view of resorts; anyone else gets P0008.
- `properties.status` (`active`/`suspended`/`archived`, 0043) is what locks
  a resort; only the platform admin can change it (`properties_guard_status`,
  0044).
- There is no payment collection anywhere: `razorpay_gateway.dart` is
  inactive, there is no Razorpay merchant account and no Edge Functions.
- The login and sign-up cards still say "Pasala Resorts" with the Pasala
  logo, while the welcome screen already says "ResortHub".

The closed PR #12 prototype (four tiers, a payments table and a manual UTR
flow) was a mock and is not reused.

## Decisions (agreed 2026-09-25)

1. **Tiers are Starter, Pro and Enterprise.** There is no free tier.
2. **A tier gates nothing yet.** It is a label with a monthly price, used for
   the filter, the counts and MRR. Limits come in a later project.
3. **No in-app payment.** The platform admin sets the tier, the status and
   the paid-until date by hand; payment happens off-platform.
4. **Lapsed is a flag only.** The console shows "Lapsed" and the Active count
   drops. Nothing is suspended automatically; suspending stays a separate,
   explicit admin action.
5. **Trials.** "+ Add resort" can start a trial (default 30 days) on a chosen
   tier.
6. **Counts.** Subscribed = the resort is not archived and its subscription
   is not cancelled. Active = subscribed, and paid up or in a trial, with no
   lapse.
7. **MRR** (third card) = the sum of the monthly price of every paid-up
   (`active`, not lapsed) subscription of a non-archived resort, trials
   excluded, in INR, at the plan's current price.
8. **Owners see their plan read-only** in Settings: "Plan: Pro" with
   "Paid until 31 Oct 2026" under it.
9. **Existing resorts start on Enterprise**, active, with no end date.
10. **Approach B:** two platform-owned tables, `subscription_plans` and
    `resort_subscriptions`, written only by the platform admin through
    security definer functions. The platform admin gets no resort row access
    beyond what exists today.
11. **Placeholder monthly prices**, editable by the platform admin on the
    console: Starter ₹2,999, Pro ₹7,999, Enterprise ₹19,999.
12. **Rebrand** the login and sign-up cards to ResortHub, matching the
    welcome screen: the heading reads "ResortHub" and the Pasala logo is
    removed from both cards.

Settled here where the draft was silent:
- Dates are calendar `date`s in `Asia/Kolkata` (the same "today" as
  `dashboard_summary`). A subscription is still good **on** its end date and
  lapses the day after.
- A resort with **no subscription row** (only possible for a resort inserted
  by hand in SQL, or local seed data before this project) has "No plan": it
  counts as neither subscribed nor active and adds nothing to MRR. The
  console offers "Set plan" for it, which creates the row.
- The count cards are platform-wide. The search and tier filter narrow the
  list below them, not the cards.
- A price change applies to every subscription on that tier at once, so MRR
  moves with it. No price history is kept (the audit log keeps the change).
- `notes` on a subscription are visible to that resort's owners and admins;
  they are not a private platform field.
- `set_resort_subscription` keeps only the date that matters: `trial_ends_on`
  for a trial, `paid_through` for active or cancelled.
- No new error codes: bad input is P0005 with a message written for the
  admin, unknown resort P0002, not the platform admin P0008.

## Data model — `supabase/migrations/0049_subscriptions.sql`

Applied after B's `0047_room_status.sql` and C's `0048_finance_ledger.sql`;
it touches none of their objects.

- Enum `public.subscription_tier`: `starter`, `pro`, `enterprise`.
- Enum `public.subscription_status`: `trial`, `active`, `cancelled`.
  "Lapsed" is never stored.
- Table `public.subscription_plans`:
  - `tier public.subscription_tier primary key`
  - `id uuid not null unique default gen_random_uuid()` (the audit log's
    `entity_id`)
  - `name text not null`, `monthly_price_inr numeric(12,2) not null check (>= 0)`,
    `sort_order int not null`, `updated_at timestamptz not null default now()`
  - seeded with Starter 2999 (1), Pro 7999 (2), Enterprise 19999 (3)
  - RLS on; `select` granted to `authenticated` with a `using (true)` policy;
    no write grants.
- Table `public.resort_subscriptions` (one row per resort):
  - `property_id uuid primary key references properties(id) on delete cascade`
  - `tier public.subscription_tier not null references subscription_plans(tier)`
  - `status public.subscription_status not null`
  - `trial_ends_on date`, `paid_through date` (null = no end date)
  - `notes text`, `updated_at timestamptz not null default now()`,
    `updated_by uuid default auth.uid()`
  - `check (status <> 'trial' or trial_ends_on is not null)`
  - RLS on; `select` granted to `authenticated` with the policy
    `has_resort_role(property_id, false, 'owner','admin')`; no write grants
    or policies.
- Backfill: every existing resort gets `enterprise` / `active` /
  `paid_through` null. `supabase/seed.sql` does the same for the seeded
  resort, because the seed runs after the migrations.
- `public.subscription_lapsed(p_status, p_trial_ends_on, p_paid_through)
  returns boolean` (plain `stable` SQL, not a definer): a trial whose end
  date is before today, or an active subscription whose paid-until date is
  before today. Cancelled and "no row" are never lapsed.

## Functions (security definer, `search_path = public, pg_temp`, revoked from public and anon, granted to authenticated)

Platform admin only (P0008 for anyone else):
- `platform_resorts()` — dropped and re-created with the old nine columns
  plus `plan_tier, plan_name, plan_status, trial_ends_on, paid_through,
  lapsed, monthly_price_inr, plan_notes` (all null, and `lapsed` false, when
  the resort has no row). Still no guest data.
- `platform_summary()` — one row: `subscribed_count int, active_count int,
  trial_count int, mrr_inr numeric`, using decisions 6 and 7. `trial_count`
  is live (not lapsed) trials of non-archived resorts.
- `create_resort(p_name text, p_owner_email text, p_tier subscription_tier
  default 'starter', p_trial_days int default 30) returns uuid` — the old
  two-argument version is dropped. Keeps the existing behaviour and, in the
  same transaction, inserts the subscription: a trial ending today +
  `p_trial_days` when `p_trial_days > 0`, otherwise active with no end date.
  A null tier or `p_trial_days` outside 0..365 raises P0005. Writes an
  audit row (`entity 'subscription'`, action `subscription:create`).
- `set_resort_subscription(p_property uuid, p_tier subscription_tier,
  p_status subscription_status, p_trial_ends_on date default null,
  p_paid_through date default null, p_notes text default null) returns void`
  — upserts the row (so it also sets a plan for a "No plan" resort). A null
  tier or status, or a trial without an end date, raises P0005; an unknown
  resort P0002. Blank notes are stored as null. Locks the row, and writes an
  audit row with before/after JSON at that resort.
- `set_plan_price(p_tier subscription_tier, p_monthly_price_inr numeric)
  returns void` — a null, negative or above 1,00,00,000 price raises P0005.
  Writes an audit row (`entity 'subscription_plan'`, `property_id` null,
  i.e. a platform event).

Owners and admins of the resort:
- `my_resort_subscription(p_property uuid)` — `assert_resort_role(p_property,
  false, 'owner','admin')`, so it works at a suspended resort and gives P0020
  to everyone else, including the platform admin. Returns zero or one row
  with the same plan columns as `platform_resorts`.

The definer allow-list in `37_tenancy_isolation_test.sql` gains
`platform_summary`, `my_resort_subscription`, `set_resort_subscription` and
`set_plan_price`. `38_resort_members_test.sql` is updated for the new
`platform_resorts` columns and `create_resort` signature.

## App

- `lib/data/models/subscription.dart`: `SubscriptionTier` and
  `SubscriptionStatus` (from/to db, labels), `SubscriptionPlan`,
  `PlatformTotals`, `ResortPlan` (the plan columns; null when `plan_tier` is
  null), `planStatusLine(ResortPlan)`, and `dateToDb(DateTime)`.
- `lib/data/repositories/platform_repository.dart`: `ResortSummary` gains
  `plan`. `PlatformSource` gains `totals()`, `plans()`,
  `setSubscription(...)`, `setPlanPrice(...)`, and `createResort` gains
  `tier` and `trialDays`. New `platformTotalsProvider` and
  `subscriptionPlansProvider`.
- `lib/data/repositories/subscription_repository.dart`: the
  `ResortPlanSource` seam (`resortPlan(propertyId)` over
  `my_resort_subscription`) and `resortPlanProvider`, an `autoDispose`
  family keyed by property id.
- `/platform`:
  - three cards at the top: **Subscribed resorts**, **Active subscriptions**
    (with "incl. N trials"), **MRR** (`formatInr`); they wrap on a phone.
  - a search field (resort name or owner email, case-insensitive, filters
    as you type) and a tier dropdown (**All tiers / Starter / Pro /
    Enterprise**). Both filter on the device.
  - each card gains a tier chip ("No plan" when there is none) and a plan
    line: "Trial until 24 Oct 2026", "Paid until 31 Oct 2026", "Paid, no end
    date", "Cancelled", or, with a warning icon and the error colour,
    "Lapsed: trial ended 24 Oct 2026" / "Lapsed: paid until 30 Sep 2026".
  - a "Change plan" button ("Set plan" when there is none; not on archived
    resorts) opens a dialog: tier, status (Trial / Active / Cancelled), the
    date that status needs (trial end, required; or paid until, optional),
    and notes.
  - the + button becomes a labelled "Add resort" button; its dialog adds a
    tier dropdown (default Starter) and a "Start with a trial" switch (on)
    with a days field (30, 1–365).
  - a "Plan prices" action in the app bar edits the three monthly prices.
  - after any change the list, the cards and the prices are refetched.
- Owner Settings: a read-only **Plan** tile at the top: "Plan: Pro" over the
  plan line, "Plan: not set up" when there is no row, and "Plan" / "Could not
  load your plan" on an error (the rest of Settings still works).
- Login and sign-up: the card heading reads "ResortHub" and the Pasala logo
  is gone.

## Rules

- Only the platform admin changes tiers, statuses, dates or prices, and only
  through the definer functions. Owners and admins only read their own
  resort's plan. Staff, accountants and guests see nothing.
- Subscription state never locks a resort. `properties.status` remains the
  only lock, changed only by Suspend / Reactivate.
- Archived resorts are left out of both counts and MRR.
- Every subscription or price change writes an audit_log row.
- No guest data is added to anything the platform admin can see.

## Testing

- pgTAP `supabase/tests/41_subscriptions_test.sql` (~60 assertions): schema
  and seeded prices; function signatures and grants; the table's read policy
  (owner/admin their own row only; staff, other owners and the platform admin
  none; no direct writes by anyone); `lapsed` at the day boundary; counts and
  MRR over paid, open-ended, trial, lapsed trial, lapsed paid, cancelled,
  archived, suspended and no-plan resorts; `my_resort_subscription` role
  matrix incl. suspended resort and platform admin; `create_resort` defaults,
  no-trial and bad input; `set_resort_subscription` insert, update, date
  clearing, bad input, unknown resort; `set_plan_price` and its effect on MRR;
  P0008 for owners; audit rows.
- `37` allow-list passes; `38` updated and passing.
- The backfill is checked once by hand against a resort that existed before
  0049 (`supabase db reset --version`, then `supabase migration up`).
- Flutter: model parsing, `planStatusLine`, providers keyed by property id;
  console cards, search on name and email, tier filter, empty filter result,
  lapsed line, Change plan dialog (arguments, trial date required, errors),
  Add resort dialog (tier, trial days, trial off, bad days), Plan prices
  dialog, archived card has no actions; owner Plan tile (plan, none, error);
  login and sign-up show ResortHub and no BrandMark.

## Out of scope

Collecting payments (Razorpay Subscriptions, Edge Functions, webhooks,
invoices); automatic suspension after a lapse; tier limits or feature gates;
a payment log or UTR entry; owners requesting an upgrade; price history or
grandfathered prices; ranking guest browse by tier; renaming the app shell's
BrandMark.
