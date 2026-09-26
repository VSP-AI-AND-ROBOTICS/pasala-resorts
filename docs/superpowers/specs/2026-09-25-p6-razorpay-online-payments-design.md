# Razorpay Online Payments (P6) — Design

## Why

Every booking advance and every guest self-checkout balance in ResortHub
goes through `MockGateway` (`lib/features/booking/payment_gateway.dart`),
which makes up a reference and charges nothing. No money has ever moved
through the app (`docs/STATUS.md`, "What is stubbed, and why").

The only real payment code is `RazorpayGateway`
(`lib/features/booking/razorpay_gateway.dart`). It is unsafe and incomplete:
- It expects `RAZORPAY_KEY_SECRET` as a `--dart-define`, so the merchant's
  secret key would be compiled into every web and mobile build.
- It creates an order and then throws `UnimplementedError`, because no
  checkout SDK is integrated.
- Nothing on the server checks that a payment happened. `confirm_booking`
  (latest in `0045_resort_functions.sql`) and the guest branch of
  `checkout_booking` (latest in `0048_finance_ledger.sql`) accept any
  `p_payment_ref` the app sends, and record it with `gateway = 'mock'`.

The product owner accepted the gap-closing decision for P6 (gaps-decisions,
section P6). Razorpay is called only from Supabase Edge Functions that hold
the secrets. The Flutter app only ever sees `key_id`. When no secrets are
set, the app behaves exactly as it does today.

Out of the existing code, these stay as they are: the hold/quote flow in
`BookingScreen`, `QuoteSheet`'s advance/full choice, the desk checkout
methods (0048), the finance reports, and the `PaymentGateway.charge` seam
that both screens call.

## Decisions (auto-approved 2026-09-25; judgment calls marked *)

1. **One Razorpay merchant account per deployment.** The platform collects
   the money; `RAZORPAY_KEY_ID`, `RAZORPAY_KEY_SECRET` and
   `RAZORPAY_WEBHOOK_SECRET` are Edge Function secrets. Paying resorts out
   (Razorpay Route) is out of scope.*
2. **Three Edge Functions** under `supabase/functions/`, in Deno:
   `payments-create-order`, `payments-verify` and `payments-webhook`. Each
   has its own `deno.json`. Shared code lives in
   `supabase/functions/_shared/`: the Razorpay client and HMAC helpers
   (`razorpay.ts`), which P8 subscription billing reuses; the contract types
   (`payments_types.ts`); the database adapter; and test fakes.
3. **Safe default.** If `RAZORPAY_KEY_ID` or `RAZORPAY_KEY_SECRET` is
   missing, `payments-create-order` and `payments-verify` answer
   `200 {"configured": false}`. The app then charges through `MockGateway`
   exactly as today. `payments-webhook` answers `503` until the webhook
   secret is set too.
4. **The app falls back to the mock only in two cases:** the function says
   `configured: false`, or the function cannot be reached at all. "Cannot
   be reached" means HTTP 404, a 5xx without the function's own
   `{"error": …}` body (not deployed, or still booting), or a transport
   error such as a failed CORS preflight when no functions are served.*
   Every other error is shown to the guest. Falling back is safe because
   of decision 5. A transport error during *verification* is different:
   money may already have moved, so the guest is told the payment was
   received but is not confirmed yet.
5. **A live switch in the database.** A server-only singleton,
   `payment_gateway_config.live`, is kept in sync with whether the secrets
   are set. Every call to `payments-create-order` syncs it, including a
   `{"probe": true}` call that creates no order. While it is on,
   `confirm_booking`, and `checkout_booking` with the `gateway` method,
   refuse a guest's own mock payment with **P0036
   `online_payment_required`**. The owner/admin confirmation path and the
   desk methods are unchanged.*
6. **The server does the settling.** A payment counts only after
   `payments-verify` checks
   `razorpay_signature = HMAC_SHA256(order_id|payment_id, key_secret)`, or
   after a signed `payment.captured` webhook arrives. Either one calls
   `payment_order_settle`. For an advance, settling confirms the hold. For a
   balance, it records the payment and checks the guest out. The app's own
   later `confirm_booking` / `checkout_booking` call then returns the row
   unchanged, because both functions are already idempotent for that status.
   So the screens change very little.
7. **Settling reuses the existing functions.*** `payment_order_settle`
   (service role only) sets the order's guest as the caller for the rest of
   the transaction (`request.jwt.claims`, local to the transaction), sets
   `app.payment_gateway = 'razorpay'`, and calls `confirm_booking` or
   `checkout_booking` unchanged except for two lines each. The payment is
   labelled `razorpay` only when the session role is `service_role`, so a
   guest who somehow set the setting would still get `mock` and P0036. The
   caller's settings are restored afterwards.
8. **Amounts are checked on the server.** `payment_order_quote` runs as the
   signed-in guest. It accepts an advance between `advance_pct` of the quote
   total and the full total (the same rule as `confirm_booking`), and a
   balance only when it equals `current_charges.balance`. The Razorpay order
   is created for that amount in paise. Currency is INR only.
9. **Holds are not extended.*** A payment captured after the hold's expiry
   but before `release_expired_holds` has swept it still confirms, because
   the dates are still held. Once the hold is swept, the payment is
   *unapplied*.
10. **Unapplied payments are refunded automatically.*** A payment is
    unapplied when money was captured but cannot be applied. That happens
    when the hold was released, the booking was already confirmed by another
    payment, the balance changed between order and payment, or the resort
    was suspended meanwhile. The order is marked `unapplied`, and the
    function that settled it issues a full refund through
    `POST /v1/payments/:id/refund`. If that refund call fails, the next
    settle call tries again (the webhook's, or a retry), until a refund is
    recorded.
11. **Refunds are recorded on `payment_orders` only.*** The `payments` rows
    and the finance ledger stay as they are. The ledger already reports
    refunds from cancelled bookings (`reservations.refund_amount`), so
    changing `payments.status` would count them twice. Refunding a
    cancelled booking is still done by hand in the Razorpay dashboard;
    automatic refunds on cancellation are out of scope.
12. **Webhook events:** `payment.captured` settles the payment,
    `payment.failed` marks the order failed (a later success on the same
    order still settles), and `refund.processed` records the refund. Other
    events, and payments for order ids this app does not know (P8's
    subscription payments, for example), are acknowledged with 200 and
    ignored. Each event is processed once, keyed by `X-Razorpay-Event-Id`
    (or the SHA-256 of the body when that header is missing), in
    `payment_webhook_events`.
13. **Capture:** a valid checkout signature proves only that the payment
    was authorized. `payments-verify` therefore asks Razorpay for the
    payment and its order before settling: a payment for another order,
    amount or currency is refused (`invalid_signature`); an authorized
    payment is captured for the order's amount; a captured one settles;
    anything else answers `{"outcome": "pending"}` and settles nothing (the
    app shows "not confirmed yet", and a later `payment.captured` webhook
    settles it). If Razorpay does not answer, verify returns 502 `gateway`,
    which the app also shows as "not confirmed yet". The account should
    keep its default automatic capture, so a payment whose guest closed the
    tab is still captured. (Changed after the final review; the first
    version settled on the signature alone.)*
14. **Only the guest pays online** for their own booking. Anyone else gets
    P0008. Staff keep the desk methods.
15. **Checkout UI:** on the web, Razorpay Checkout.js is injected on first
    use (not in `web/index.html`) and driven through `dart:js_interop`. On
    Android and iOS the app uses `razorpay_flutter`. Other platforms (desktop)
    get "Online payment is not available on this device."*
16. **No secret in the app.** The `RAZORPAY_KEY_ID` / `RAZORPAY_KEY_SECRET`
    dart-defines, `resolvePaymentGateway` and `RazorpayConfigurationError`
    are removed. `key_id` comes from `payments-create-order`.
17. **The hold countdown waits for an open checkout.*** While a payment is
    in flight, the booking screen's 1-second hold ticker does not expire the
    hold in the app. The server decides (decision 9).
18. **Verification needs a signed-in caller.** The Supabase gateway checks
    the JWT, but `payments-verify` settles on the signature alone and does
    not compare the caller with the order's guest. A valid signature is
    proof that the money was paid for that order.*

## Data model — `supabase/migrations/0055_online_payments.sql`

- Enum `public.payment_order_status`: `created`, `paid`, `unapplied`,
  `failed`, `refunded`.
- Table `public.payment_orders`, one row per Razorpay order:
  - `id uuid pk`
  - `property_id uuid not null`, filled and checked by
    `fill_property_id('reservations','reservation_id')`
  - `reservation_id uuid not null references reservations on delete cascade`
  - `customer_id uuid not null references profiles`
  - `kind public.payment_kind` (`advance` | `balance`)
  - `amount numeric(12,2) > 0`, `currency text = 'INR'`
  - `razorpay_order_id text not null unique`,
    `razorpay_payment_id text unique`
  - `status public.payment_order_status default 'created'`
  - `payment_id uuid references payments on delete set null`
  - `refunded_amount numeric(12,2) default 0`,
    `refund_ids text[] default '{}'`
  - `failure_reason text` (500 characters at most)
  - `created_at`, `updated_at`
  - RLS read: `has_resort_role(property_id, false, 'owner','admin','staff','accountant') or customer_id = auth.uid()`.
    `select` is granted to `authenticated`. There are no write grants;
    writes happen only through the functions below.
- Table `public.payment_webhook_events` (`event_id text pk`, `event`,
  `payload jsonb`, `received_at`, `processed_at`, `outcome`). It is
  server-only: RLS is on, there are no policies, and all privileges are
  revoked from `anon` and `authenticated`.
- Table `public.payment_gateway_config`, a singleton
  (`id boolean pk check (id)`, `live boolean default false`, `key_id text`,
  `updated_at`), seeded with one row. It is server-only.
- `public.payments` is unchanged. Razorpay payments are rows with
  `gateway = 'razorpay'`, `gateway_ref = <razorpay payment id>` and
  `method = 'gateway'`, recorded by the guest. `unique (gateway, gateway_ref)`
  stays the final guard against double recording.

## Functions (`set search_path = public, pg_temp`; each is revoked from public and anon)

- `payment_order_quote(p_reservation uuid, p_kind payment_kind, p_amount numeric) returns jsonb`.
  Security definer; granted to `authenticated`, and executed as the guest by
  `payments-create-order`. It raises P0008 when there is no caller or the
  caller is not the booking's guest, P0002 for an unknown reservation, and
  P0009 for a bad amount (null, ≤ 0, more than 2 decimals, outside the
  range) or the wrong status (advance needs `hold`, balance needs
  `checked_in`). For an advance it also raises P0022 when the resort is not
  active and P0006 when the hold has expired. It returns
  `reservation_id, property_id, property_name, customer_id, kind, amount,
  amount_paise, currency, receipt (= reservation id),
  description ("<resort>: booking advance" | "<resort>: stay balance"),
  prefill {name, email, contact}`.
- `payment_order_open(p_reservation uuid, p_customer uuid, p_kind payment_kind, p_amount numeric, p_razorpay_order_id text) returns payment_orders`.
  Service role only. It checks again that the reservation exists (P0002),
  that it is the customer's (P0008), and its status, amount and order id
  (P0009), then inserts a `created` order. The hold is not changed.
- `payment_order_settle(p_razorpay_order_id text, p_razorpay_payment_id text) returns jsonb`.
  Service role only. It raises P0002 for an unknown order and P0009 for an
  empty payment id. It is idempotent: an order that is already
  `paid`/`unapplied`/`refunded` is reported, not applied again. Otherwise it
  settles as in decisions 6, 7, 9 and 10 and returns
  `order_id, reservation_id, kind, amount, status, razorpay_payment_id,
  reason, refund_needed`. `refund_needed` means the order is `unapplied`
  and has no refund recorded.
- `payment_order_failed(p_razorpay_order_id text, p_reason text) returns void`.
  Service role only. It marks a `created` or `failed` order `failed`, and
  ignores unknown orders.
- `payment_order_refunded(p_razorpay_payment_id text, p_refund_id text, p_amount numeric) returns void`.
  Service role only. It is idempotent per refund id and adds up to at most
  the order amount. When the refunds reach the full amount, the order
  becomes `refunded`. It never touches `payments`.
- `payment_webhook_begin(p_event_id text, p_event text, p_payload jsonb) returns boolean`
  records the event and returns true while it is still unprocessed.
  `payment_webhook_done(p_event_id text, p_outcome text) returns void`
  marks it processed. Both are service role only.
- `payments_set_live(p_live boolean, p_key_id text) returns void`. Service
  role only; it writes only when the value changes.
- `online_payments_live() returns boolean` and
  `payment_order_json(payment_orders) returns jsonb` are internal
  (security invoker) and revoked from every client role.
- `confirm_booking` (copied from `0045`) and `checkout_booking` (copied from
  `0048`) each gain only the P0036 check and the `mock`/`razorpay` label
  (decisions 5 and 7). Their signatures and grants are unchanged.
- Every new definer function is added to the allow-list in
  `supabase/tests/37_tenancy_isolation_test.sql`.

## Edge Functions

All three answer CORS preflight and accept only `POST`. They return JSON
with CORS headers. An error body is always
`{"error": "bad_request"|"unauthorized"|"db"|"gateway"|"invalid_signature"|"internal"|"not_configured", "code"?: "<Postgres code>", "message": "…"}`.

- `payments-create-order` (JWT verified by the gateway). Request
  `{"reservation_id", "amount" (rupees), "purpose": "advance"|"balance"}`
  or `{"probe": true}`. It first syncs the live switch. Then:
  - `{configured:false}` when the keys are not set.
  - For a probe: `{configured, key_id?}`.
  - Otherwise it calls `payment_order_quote` as the caller, creates the
    order through `POST /v1/orders`, and calls `payment_order_open`. It
    answers
    `{configured:true, key_id, order_id, amount (paise), currency, name, description, reservation_id, prefill}`.
  - Errors: 400 bad body, 401 no bearer token, 409 `db` (with the Postgres
    code), 502 `gateway`, 500 `internal`.
- `payments-verify` (JWT verified). Request
  `{"razorpay_order_id", "razorpay_payment_id", "razorpay_signature"}`.
  - `{configured:false}` when the keys are not set.
  - 400 `invalid_signature` when the signature is wrong.
  - Otherwise it settles, refunds if needed, and answers
    `{configured:true, outcome: "paid"|"unapplied", reservation_id, kind, refund: "initiated"|"failed"|null}`.
  - An unknown order gives 409 `db` with `P0002`.
- `payments-webhook` (`verify_jwt = false` in `supabase/config.toml`).
  - 503 until all three secrets are set.
  - 401 on a bad `X-Razorpay-Signature` over the raw body.
  - Otherwise it records the event and handles it (decision 12). It answers
    200 `{status: "processed", outcome}` or `{status: "duplicate"}`, and 500
    on a database failure so that Razorpay retries.

## App

- `lib/data/models/payment_order.dart` holds:
  - `PaymentPurpose` (advance, balance; `wire`)
  - the sealed `CreateOrderResult`: `PaymentsNotConfigured`, or
    `RazorpayOrder` (`keyId, orderId, amountPaise, currency, name,
    description, reservationId, prefill*`)
  - `VerifyResult` (`outcome` paid|unapplied, `reservationId`, `refund`
    initiated|failed|null)
- `lib/data/repositories/payment_order_repository.dart` holds the
  `PaymentOrderSource` seam (`createOrder`, `verify`) and
  `PaymentFunctionsSource`, which calls
  `supabase.functions.invoke` through an injectable `FunctionInvoker`. It
  maps errors as in decision 4, maps `db` errors through
  `mapPostgrestError`, and turns a verify failure caused by the network into
  "received but not confirmed yet" rather than a plain failure.
  `paymentOrderSourceProvider` provides it.
- `lib/features/booking/razorpay_checkout.dart` holds:
  - the `RazorpayCheckout` interface, `CheckoutRequest`, and the sealed
    `CheckoutOutcome` (`CheckoutSucceeded`, `CheckoutDismissed`,
    `CheckoutFailed`)
  - `checkoutOptions()`
  - `UnsupportedRazorpayCheckout`

  The platform versions sit behind
  `razorpay_checkout_platform.dart`, which uses conditional exports: `_web`
  (Checkout.js), `_mobile` (`razorpay_flutter`) and `_stub`.
- `RazorpayGateway` is rewritten. It creates the order; on
  `PaymentsNotConfigured` it delegates to `MockGateway`. Otherwise it opens
  checkout, verifies, and returns the Razorpay payment id as the reference.
- `PaymentGateway.charge` gains `PaymentPurpose purpose = PaymentPurpose.advance`.
  `paymentGatewayProvider` always builds a `RazorpayGateway`. The selection
  between Razorpay and the mock now happens per charge, by asking the
  server.
- `BookingScreen._pay` passes `advance`, and the hold ticker waits while a
  payment is in flight. `CheckoutScreen` (guest) passes `balance`, and
  refetches the charges after a failed payment.
- `lib/core/errors.dart`: P0036 maps to `OnlinePaymentRequired` ("Online
  payment is not available right now. Please try again in a few
  minutes.").
- `pubspec.yaml` adds `razorpay_flutter: ^1.4.7`.

## Rules

- The Razorpay key secret and the webhook secret exist only as Edge
  Function secrets. They never appear in the Flutter app, in the database,
  or in git. `key_id` is public by Razorpay's design.
- Only `service_role` can move money state: open, settle, fail, refund, the
  webhook ledger and the live switch. The one function a client can call,
  `payment_order_quote`, only reads.
- Every new row is scoped to a resort through the reservation, following the
  tenancy rules. No existing policy is widened.
- Tests never reach Razorpay: Deno tests inject `fetch` and the database,
  and Flutter tests use fakes.

## Testing

- pgTAP `supabase/tests/45_online_payments_test.sql` covers:
  - the contract: tables, enum, privileges, and the read matrix
  - quote rules and every error code
  - open
  - live switch P0036, including the case where a guest sets
    `app.payment_gateway` themselves
  - desk payments unaffected while live
  - settle: advance, balance and room dirty, expired but not swept, swept
    → unapplied, duplicate → unapplied; it is idempotent, and it restores
    the claims
  - failed, refunded (idempotent, partial, never touching `payments`)
  - the webhook ledger and cross-resort isolation

  The allow-list in `37` gains the new definer functions.
- Deno (`deno test supabase/functions/`):
  - `_shared/razorpay_test.ts`: RFC 4231 HMAC vector, checkout and webhook
    signature fixtures, and the order and refund HTTP shapes against a fake
    `fetch`
  - one handler test per function, with fake database and Razorpay
- Flutter:
  - models `fromJson`
  - `PaymentFunctionsSource` status and body mapping
  - `RazorpayGateway` orchestration with fakes, including the mock fallback
  - checkout options and mobile outcome mapping
  - the booking screen ticker during a payment
  - the checkout screen purpose and refetch
  - errors P0036
- Integration: `supabase functions serve` with fixture secrets. A signed
  `payment.captured` webhook and a signed verify call settle real rows in
  the local database, and duplicates are no-ops. The probe without secrets
  switches live off again. `flutter build web` compiles the Checkout.js
  interop, and the Playwright guest spec still books through the mock.

## Out of scope

- Payouts per resort (Razorpay Route).
- Automatic refunds when a booking is cancelled.
- An in-app payments or reconciliation screen for owners.
- Saved cards and payment links.
- Subscription billing (P8, which reuses `_shared/razorpay.ts`).
- Checking the setup against a real, KYC-verified Razorpay account. That
  needs the owner's account; the README lists the steps.
