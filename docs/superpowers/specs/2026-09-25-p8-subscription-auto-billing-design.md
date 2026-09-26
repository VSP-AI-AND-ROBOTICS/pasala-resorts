# Subscription Auto-Billing (P8) — Design

## Why

Project D (`docs/superpowers/specs/2026-09-25-subscriptions-design.md`,
`supabase/migrations/0049_subscriptions.sql`) gave every resort a ResortHub
plan (Starter / Pro / Enterprise) with a trial end or a paid-until date. The
platform admin sets all of it by hand on the console
(`lib/features/platform/change_plan_dialog.dart`). No money moves. Every
month someone has to chase each owner, take the payment outside the app,
and type a new paid-until date.

The product owner accepted the gap-closing decision for P8 (gaps-decisions,
section P8). Each tier gets a Razorpay Subscriptions plan. A resort owner
starts auto-pay from Settings, and Razorpay's webhooks move the paid-until
date forward on every successful charge. Without Razorpay secrets, nothing
changes: plans stay manual, exactly as today.

What exists today and is kept as is:
- `subscription_plans` (tier, name, `monthly_price_inr`, readable by every
  signed-in user) and `resort_subscriptions` (one row per resort, status
  `trial | active | cancelled`, `trial_ends_on`, `paid_through`), written
  only by definer functions.
- Lapsed is never stored. `subscription_lapsed(status, trial_ends_on,
  paid_through)` works it out on read, in Asia/Kolkata days. Nothing locks a
  resort except `properties.status`.
- `set_resort_subscription` and `set_plan_price` (platform admin),
  `my_resort_subscription` (owner/admin), `platform_resorts` and
  `platform_summary` (platform admin).
- The owner's read-only Plan tile in `lib/features/owner/owner_settings_screen.dart`
  (`/owner/settings`, owner-only in `lib/core/router.dart`), and the
  console's `ResortCard` and `PlanPricesDialog`.
- The repo has no Edge Functions yet (`supabase/functions/` does not exist
  on `main`), and no function is granted to `service_role`.

## Decisions (auto-approved 2026-09-25; judgment calls marked *)

1. **One Razorpay merchant account per deployment**, the same one P6 uses.
   `RAZORPAY_KEY_ID` and `RAZORPAY_KEY_SECRET` are Edge Function secrets.
   The billing webhook's secret is `RAZORPAY_BILLING_WEBHOOK_SECRET`, and
   falls back to `RAZORPAY_WEBHOOK_SECRET` when unset. Razorpay lets each
   webhook URL have its own secret, so both work.*
2. **Configured** means both keys are set **and** at least one tier has a
   Razorpay plan id. `billing-subscribe` answers a probe with
   `{configured: false}` when the keys are missing. The app treats any probe
   failure (function not deployed, network, 5xx) the same as "not
   configured". Then the owner sees no billing card, and everything stays
   manual.*
3. **Plan ids come from the Razorpay dashboard.** The platform admin creates
   one monthly plan per tier in Razorpay, at the tier's price, and pastes
   its id (`plan_…`) into the console's Plan prices dialog. The app never
   creates or edits Razorpay plans. `monthly_price_inr` stays the source of
   MRR. Keeping the two prices equal is the admin's job, and the setup guide
   says so.*
4. **Only the resort's owner** starts, changes or cancels auto-pay, and only
   the owner reads billing state and invoices (the gaps decision says
   "owner reads own resort's rows"). Admins keep reading the plan through
   `my_resort_subscription` as today. A suspended resort's owner can still
   pay, because the checks use read mode. An archived resort gives P0020.*
5. **One current Razorpay subscription per resort.** They are kept in a new
   table, `billing_subscriptions`. When a subscription is replaced, it gets
   `superseded_at` and stays in the table as history. `resort_subscriptions`
   and its enum are unchanged: Lapsed is still worked out on read.*
6. **Start date.** A new subscription starts on the day after the current
   trial or paid period ends (midnight Asia/Kolkata, sent as Razorpay's
   `start_at`). It starts immediately when there is no end date in the
   future (no plan, no end date, or already lapsed). No proration: a change
   of tier takes effect on the next billing date.*
7. **Changing tier creates a new Razorpay subscription.** The owner
   authorises it through its `short_url`, and the old one is cancelled
   immediately. The period the old one already paid for is kept in
   `paid_through`, and the new one starts after it (decision 6). Razorpay's
   update-plan API is not used, because it does not work for UPI mandates.*
8. **Reuse.** If the owner asks again for the same tier while the current
   subscription is still `created` (not yet authorised), they get its
   existing link back. If the current subscription is live on the same tier
   and not cancelling, nothing is created, and the answer is `unchanged`.
9. **Cancel auto-pay.** An authorised subscription is cancelled at the end of
   its cycle. One that was never authorised is cancelled immediately. The
   resort's status becomes `cancelled` only when Razorpay's
   `subscription.cancelled` arrives for the current subscription **and** it
   was charged at least once. Abandoning an unpaid checkout never cancels a
   trial.*
10. **`subscription.charged`** records a `subscription_invoices` row, keyed
    by the unique `razorpay_payment_id`, so a repeated event is a no-op.
    For the current subscription it also sets the resort's plan:
    - status `active`, with the subscription's tier
    - `trial_ends_on` cleared
    - `paid_through` = the later of the existing date and the Asia/Kolkata
      date of (`current_end` − 1 second)
    - if the event has no `current_end`: one month after the later of
      `paid_through` and yesterday

    `paid_through` never moves backwards. A resort with no plan row gets
    one.
11. **`subscription.halted`** (Razorpay gave up retrying) makes the resort
    Lapsed without a new enum value. For an `active` row, `paid_through`
    becomes at most yesterday, so `subscription_lapsed()` reports true.
    Nothing locks the resort (0049's rule).*
12. **Other subscription events** (`authenticated`, `activated`, `pending`,
    `paused`, `resumed`, `completed`, `updated`) only update the stored
    Razorpay state. After `completed`, the resort lapses on its own when
    `paid_through` passes.*
13. **Out-of-order delivery.** The stored state follows the newest event,
    by the event's `created_at`. `halted` and `cancelled` change the resort
    only when they are that newest event. Invoices and `paid_through` only
    ever move forward, so a late `charged` is still applied.*
14. **Replaced subscriptions that are still live get cancelled** by
    whichever function sees them next. `billing-subscribe` cancels the
    `stale` ones it is handed. The webhook cancels a replaced subscription
    when an event for it shows it is still live. A charge on a replaced
    subscription is recorded as an invoice, but it does not change the plan.*
15. **`total_count` is 60** monthly cycles (5 years). After that, Razorpay
    marks the subscription `completed` and the owner subscribes again.*
16. **The platform console shows auto-pay state and last payment** from a
    new function, `platform_billing()`, merged into `ResortCard` in the
    app. `platform_resorts()` is not changed, because P10 (0059) redefines
    it too. The Plan prices dialog gains a Razorpay plan id field per tier.*
17. **Manual control stays.** `set_resort_subscription` still overrides
    everything. The next webhook event applies on top of whatever the admin
    set.
18. **An invoice is Razorpay's payment record**: amount, date, period, tier
    and ids. A GST invoice PDF for subscription fees is out of scope; P2
    covers booking invoices only.*
19. **Error code P0038 `billing_unavailable`** is raised when the chosen
    tier has no Razorpay plan id. Everything else uses the existing codes:
    P0002 not found, P0005 bad input (messages written for the admin),
    P0008 not the platform admin, P0020 not the resort's owner, and P0021
    resort mismatch.
20. **Audit.** Every change to a resort's plan made by billing writes an
    `audit_log` row with entity `subscription`. Only owners and admins can
    read those, under 0049's policy. The actions are `billing:opened <sub>`,
    `billing:charged <payment>`, `billing:halted <sub>`,
    `billing:cancelled <sub>` and `billing:cancel_requested <sub>`. A plan
    id change writes `subscription_plan` / `razorpay_plan:<old>-><new>`.
21. **Independent of P6.** P8 keeps its own shared Deno code in
    `supabase/functions/_shared/billing/`. It shares no file with P6 except
    `supabase/config.toml`, where each adds its own `[functions.*]` block.*
22. **Refresh.** After paying in Razorpay's page, the owner taps Refresh on
    the billing card. There are no realtime updates.*

## Data model — `supabase/migrations/0057_subscription_billing.sql`

- `subscription_plans` gains `razorpay_plan_id text`:
  - `check (razorpay_plan_id ~ '^plan_[A-Za-z0-9]{6,40}$')`
  - unique index `subscription_plans_razorpay_plan_id_key` (multiple NULLs
    allowed)
  - readable like the rest of the row, and written only by
    `set_plan_razorpay_id`
- Table `public.billing_subscriptions`, one row per Razorpay subscription
  ever created for a resort:
  - `id uuid pk`
  - `property_id uuid not null references properties on delete cascade`
  - `tier subscription_tier not null references subscription_plans(tier)`
  - `razorpay_plan_id text not null`
  - `razorpay_subscription_id text not null unique`, with
    `check (~ '^sub_[A-Za-z0-9]{6,40}$')`
  - `status text not null default 'created'`, checked against Razorpay's
    states: `created, authenticated, active, pending, halted, cancelled,
    completed, expired, paused`
  - `short_url text`, `start_at`, `current_start`, `current_end timestamptz`
  - `cancel_at_cycle_end boolean not null default false`
  - `superseded_at timestamptz` (null = the resort's current subscription),
    with the partial unique index `billing_subscriptions_one_current
    (property_id) where superseded_at is null`
  - `last_event_at timestamptz`, `created_by uuid`, `created_at`,
    `updated_at`
  - RLS read: `has_resort_role(property_id, false, 'owner')`. `select` is
    granted to `authenticated`. There is no write grant or policy.
- Table `public.subscription_invoices`, one row per successful charge:
  - `id uuid pk`
  - `property_id uuid not null`, filled and checked by
    `fill_property_id('billing_subscriptions', 'billing_subscription_id')`
    (P0021 on a mismatch)
  - `billing_subscription_id uuid not null references billing_subscriptions on delete cascade`
  - `tier subscription_tier not null`
  - `razorpay_payment_id text not null unique`, `razorpay_invoice_id text`
  - `amount_inr numeric(12,2) not null check (>= 0)`,
    `currency text not null default 'INR'`
  - `period_start date`, `period_end date`
  - `paid_at timestamptz not null`, `created_at`
  - index `(property_id, paid_at desc)`
  - RLS read: `has_resort_role(property_id, false, 'owner')`. `select` is
    granted to `authenticated`. There is no write grant or policy.
- The platform admin gets no row access to either table (tenancy rule). The
  admin reads through `platform_billing()`.

## Functions (`security definer`, `set search_path = public, pg_temp`, revoked from `public` and `anon`)

Client-callable (granted to `authenticated`):
- `set_plan_razorpay_id(p_tier subscription_tier, p_plan_id text) returns void`.
  - Platform admin only (P0008).
  - A blank id clears the tier's plan id.
  - A bad format, or an id already used by another tier, raises P0005 with
    an admin-readable message.
  - Setting the same value again is a no-op. A change writes an audit row.
- `my_resort_billing(p_property uuid) returns table(billing_status text, billing_tier subscription_tier, short_url text, cancel_at_cycle_end boolean, current_end timestamptz, last_payment_at timestamptz, last_payment_inr numeric)`.
  - Owner only, read mode.
  - Returns the current subscription and the latest invoice.
  - Returns zero rows when the resort has neither.
- `platform_billing() returns table(property_id uuid, billing_status text, billing_tier subscription_tier, last_payment_at timestamptz, last_payment_inr numeric)`.
  - Platform admin only.
  - One row per resort that has a current subscription or an invoice.
- `billing_subscribe_state(p_property uuid, p_tier subscription_tier default null) returns jsonb`.
  - Executed **as the owner** by `billing-subscribe`. Owner only, read
    mode.
  - With a tier that has no plan id, it raises P0038.
  - Returns `{property_id, property_name, caller_id, notify_email, tier,
    plan_id, start_at (unix seconds | null), current: {razorpay_subscription_id,
    tier, status, short_url, cancel_at_cycle_end} | null, stale: [sub ids]}`.
  - `stale` lists replaced subscriptions still in a live state (`created`,
    `authenticated`, `active`, `pending`, `paused`).

Service role only (revoked from `authenticated`, granted to `service_role`):
- `billing_subscription_opened(p_property uuid, p_tier subscription_tier, p_razorpay_plan_id text, p_razorpay_subscription_id text, p_status text, p_short_url text, p_start_at timestamptz, p_created_by uuid) returns jsonb`.
  - Takes a per-resort transaction advisory lock, supersedes the current
    row, inserts the new one, and writes an audit row.
  - Returns `{id, stale}`.
  - Idempotent for an id it already knows. That id at another resort raises
    P0021.
- `billing_subscription_cancel_requested(p_razorpay_subscription_id text, p_at_cycle_end boolean, p_status text, p_actor uuid default null) returns void`.
  - Records `cancel_at_cycle_end` and Razorpay's returned status, and
    writes an audit row.
  - An unknown id raises P0002.
- `billing_webhook_apply(p_event text, p_event_at timestamptz, p_subscription jsonb, p_payment jsonb) returns jsonb`.
  - Applies decisions 9–14.
  - Returns `{outcome: ignored | updated | stale | charged | duplicate | lapsed | cancelled, property_id, cancel_subscription_id}`.
  - An unknown subscription is `ignored`. A non-charge event older than
    the last one applied is `stale`.
  - A `charged` event without a payment raises P0005.

Every new function is added to the definer allow-list in
`supabase/tests/37_tenancy_isolation_test.sql`.

## Edge Functions (Deno 2, `supabase/functions/`)

Shared code lives in `supabase/functions/_shared/billing/`:
- `types.ts`: the contract
- `http.ts`: JSON and CORS responses
- `signature.ts`: HMAC-SHA256 hex and a constant-time compare
- `razorpay_subscriptions.ts`: create and cancel, with `fetch` injected
- `decide.ts`: the pure subscribe and cancel rules
- `db.ts`: the supabase-js adapter; as the caller for the owner reads, and
  as the service role for the writes
- `testing.ts`: fakes

Each function has a `deno.json`, a `handler.ts` (dependencies injected) and
an `index.ts` (`Deno.serve`).

- **`billing-subscribe`** (JWT verified by the gateway). It accepts `POST`
  only and answers CORS preflight.
  - Request: `{property_id, action: "probe" | "subscribe" | "cancel", tier?}`.
  - Keys missing: `200 {configured: false}` for every action.
  - `probe`: `{configured: true, plans: [{tier, name, monthly_price_inr}]}`,
    listing only the tiers that have a plan id.
  - `subscribe`:
    1. Reads the state as the owner.
    2. Cancels any `stale` subscriptions (best effort).
    3. Applies `decideSubscribe`, which gives `reuse`, `unchanged` or
       `create`.
    4. For `create`: `POST /v1/subscriptions`, with `plan_id`,
       `total_count: 60`, `quantity: 1`, `customer_notify: 1`, `start_at`
       when set, `notify_info.notify_email`, and `notes {property_id,
       tier}`. Then records it through `billing_subscription_opened`, and
       immediately cancels the replaced ones it returns.
    5. Answers `{configured: true, action: created | reused | unchanged,
       subscription_id, short_url, status, warning?: "previous_not_cancelled"}`.
  - `cancel`: `decideCancel` gives `none` or `cancel(atCycleEnd)`. It calls
    `POST /v1/subscriptions/:id/cancel` with `cancel_at_cycle_end: 0|1`,
    then `billing_subscription_cancel_requested`. It answers
    `{configured: true, action: cancel_scheduled | cancelled | none,
    subscription_id, status}`.
  - Errors, as `{error, code?, message}`:

    | Status | `error` | When |
    |---|---|---|
    | 400 | `bad_request` | bad body |
    | 401 | `unauthorized` | no bearer token |
    | 405 | `method_not_allowed` | not `POST` |
    | 409 | `db` | a Postgres code, e.g. P0020 or P0038 |
    | 502 | `gateway` | Razorpay refused or is unreachable |
    | 500 | `internal` | anything else |
- **`billing-webhook`** (`verify_jwt = false` in `supabase/config.toml`).
  - `503 not_configured` until a webhook secret is set.
  - `401 invalid_signature` unless `X-Razorpay-Signature` equals the
    HMAC-SHA256 of the raw body.
  - `400 bad_request` on bad JSON, or a subscription event without a
    subscription entity.
  - An event that is not `subscription.*` gets `200 {status: "ignored"}`.
  - Otherwise it calls `billing_webhook_apply` and answers
    `200 {status: "processed", outcome}`.
    - If the result names a `cancel_subscription_id` and the keys are set,
      it cancels that subscription immediately (best effort).
    - A database error gives 500, so Razorpay retries.

## App

- `lib/data/models/billing.dart`:
  - `GatewayStatus` (Razorpay's nine states, with a short `label`)
  - `ResortBilling` and `PlatformBilling` (`fromRow`)
  - `SubscriptionInvoice` (`fromJson`)
  - `BillingAvailability` (`configured`, `plans`, `canPay`)
  - `SubscribeResult` / `SubscribeAction`, `CancelAction`
  - `billingStatusLine(ResortBilling)` and `lastPaymentLine(num?, DateTime?)`
- `lib/data/models/subscription.dart`: `SubscriptionPlan` gains
  `razorpayPlanId`.
- `lib/data/repositories/billing_repository.dart`:
  - the `BillingSource` seam: `availability`, `billing`, `invoices`,
    `subscribe`, `cancel`
  - `BillingRepository`, which calls `billing-subscribe` through an
    injectable `BillingFunctionInvoker`, and the RPC and table reads
    - A probe failure becomes `BillingAvailability.off`.
    - A `db` error body is mapped through `mapPostgrestError`.
    - A `gateway` error is shown as "Razorpay did not respond. Try again in
      a minute."
  - the providers `billingSourceProvider`,
    `billingAvailabilityProvider.family`, `resortBillingProvider.family`
    and `subscriptionInvoicesProvider.family`, keyed by property id and
    `autoDispose`
- `lib/data/repositories/platform_repository.dart`: `PlatformSource` gains
  `billing()`, backed by `platform_billing`, and
  `setRazorpayPlanId(tier, planId)`, backed by `set_plan_razorpay_id`.
  `plans()` selects `razorpay_plan_id`. The new
  `platformBillingProvider` gives a map keyed by property id.
- `lib/core/errors.dart`: P0038 maps to `BillingUnavailable` ("Online
  payment isn't set up for this plan yet. Contact ResortHub.").
- Owner Settings: `SubscriptionBillingCard` sits under the Plan tile.
  - It renders only when the probe says it can pay.
  - It shows the auto-pay status line, the last payment, **"Pay / manage
    subscription"** and a Refresh button.
  - The button opens `ManageSubscriptionSheet`:
    - the billable tiers, with their monthly prices
    - "Continue to payment", which subscribes and opens `short_url` in the
      browser through the injectable `billingLinkOpenerProvider`
      (`url_launcher`)
    - "Cancel auto-pay", with a confirmation
    - the last 12 payments
- Platform console:
  - `ResortCard` shows "Auto-pay: <state> · Last payment ₹<amount> on
    <date>" from `platformBillingProvider`. There is nothing when the
    resort has no entry, and nothing on a load error.
  - `PlanPricesDialog` gains a "<Plan> Razorpay plan id" field per tier.
    It is checked against the same pattern and saved through
    `setRazorpayPlanId` (blank = manual).
  - The console's refresh also invalidates `platformBillingProvider`.
- Docs: `docs/subscription-billing.md` covers:
  - creating the three Razorpay plans
  - pasting their ids
  - `supabase secrets set RAZORPAY_KEY_ID=… RAZORPAY_KEY_SECRET=… RAZORPAY_BILLING_WEBHOOK_SECRET=…`
  - the webhook URL `https://<project-ref>.supabase.co/functions/v1/billing-webhook`,
    with the `subscription.*` events
  - what "manual mode" means

## Rules

- Secrets exist only as Edge Function secrets. They are never in the
  Flutter app, the database or git. The app sees only Razorpay's hosted
  `short_url`.
- Only `service_role` writes billing state (opened, cancel requested,
  webhook). The client-callable functions are reads, plus the platform
  admin's plan id.
- Every resort-owned row carries `property_id`. RLS uses `has_resort_role`.
  The definer functions assert the owner at the resort they are given, or
  derive the resort from the Razorpay subscription row. No existing policy
  is widened.
- `resort_subscriptions` keeps its shape. Lapsed stays derived, and
  subscriptions still lock nothing.
- Tests never reach Razorpay. Deno tests inject `fetch` and the database,
  and Flutter tests use fakes.

## Testing

- pgTAP `supabase/tests/47_subscription_billing_test.sql` covers:
  - the contract: columns, tables, formats, privileges per role
    (`anon` / `authenticated` / `service_role`), RLS, and the P0021 trigger
  - `set_plan_razorpay_id`
  - `billing_subscribe_state`: roles, P0038, `start_at` for a trial, a paid
    period and a lapsed plan, `stale`, and a suspended resort
  - `my_resort_billing` and `platform_billing`
  - opened, including supersede, idempotency and audit
  - cancel requested
  - every webhook branch: charged, duplicate, a late charge, no
    `current_end`, halted, a stale halted, cancelled with and without
    charges, a replaced live subscription, and unknown ignored

  The allow-list in `37` gains the seven functions.
- Deno (`deno test supabase/functions/_shared/billing supabase/functions/billing-subscribe supabase/functions/billing-webhook`):
  - the RFC 4231 HMAC vector and signature fixtures
  - the Razorpay client's request shapes against a fake `fetch`
  - `decideSubscribe` and `decideCancel` tables
  - both handlers with fake database and Razorpay: every status code, and
    the not-configured path
- Flutter:
  - the models' `fromJson` and the status lines
  - `BillingRepository` function mapping (probe fallback, `db` → P0038,
    `gateway`, 401)
  - `SubscriptionBillingCard` and `ManageSubscriptionSheet` with
    `FakeBillingSource`: hidden when not configured, the subscribe path
    opens the link, `unchanged`, cancel with confirm, and error text
  - `PlanPricesDialog` plan ids
  - the `ResortCard` billing line
  - P0038 in `errors.dart`
- Integration: `supabase functions serve` with fixture (non-real) secrets.
  A signed `subscription.charged` posted to `billing-webhook` advances a
  local resort's `paid_through` and records one invoice, and a replay is
  a duplicate. Without the keys, the probe answers
  `{"configured":false}`.

## Out of scope

- Creating Razorpay plans from the app, and proration.
- A GST invoice PDF for subscription fees.
- Locking a resort on non-payment.
- Realtime updates of the billing card.
- Checking the setup against a real, KYC-verified Razorpay account. That
  needs the platform's account; the setup guide lists the steps.
- Admins paying on the owner's behalf.
