# Razorpay Online Payments (P6) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let guests pay booking advances and stay balances with real Razorpay payments. Razorpay is called only from Supabase Edge Functions that hold the secrets. When no secrets are set, the app behaves exactly as today (`MockGateway`).

**Architecture:** Three Deno Edge Functions do the work. `payments-create-order` checks the amount with a database function that runs as the guest, creates the Razorpay order, and records it. `payments-verify` checks the checkout signature and settles the payment in the database. `payments-webhook` checks Razorpay's signature and settles, fails or refunds idempotently. Settling calls the existing `confirm_booking` / `checkout_booking` as the order's guest from a service-role-only function. A database live switch then stops guests confirming with mock payments. In Flutter, `RazorpayGateway` asks the server for an order and falls back to `MockGateway` when the server says "not configured". It opens Checkout.js on the web or `razorpay_flutter` on mobile, and verifies through the function.

**Tech Stack:** Supabase Postgres 15 (plpgsql, RLS, pgTAP via `supabase test db`), Supabase Edge Functions on Deno 2 (`deno test`, Web Crypto), Flutter 3.44 / Dart 3.10, Riverpod 3.3, `supabase_flutter` 2.16 (`functions.invoke`), `razorpay_flutter` 1.4.7, `package:web` + `dart:js_interop`.

**Spec:** `docs/superpowers/specs/2026-09-25-p6-razorpay-online-payments-design.md`

## Global Constraints

- One migration: `supabase/migrations/0055_online_payments.sql`. Tasks 1–4 each edit it. After every edit, rebuild with `supabase db reset` (it re-runs every migration and `supabase/seed.sql`), then run pgTAP. Before the first reset, dump local data: `mkdir -p ../pasala-db-backups && supabase db dump --local --data-only -f ../pasala-db-backups/local-before-p6.sql`.
- New pgTAP file: `supabase/tests/45_online_payments_test.sql`. Tasks 1–4 build it up section by section, and each section relies on the state the earlier ones leave. Run one file with `supabase test db supabase/tests/45_online_payments_test.sql`, and the suite with `supabase test db`. There are 3 known failures, which appear only between 00:00 and 05:30 IST (25/9, 26/3, 34/2). Everything else must pass.
- New error code: **P0036 `online_payment_required`**. Raise it with `raise exception using errcode = 'P0036', message = 'online_payment_required'`. The existing codes keep their meanings: P0002 not found, P0006 hold expired, P0008 not signed in or not yours, P0009 wrong state or amount, P0020 not_a_member, P0021 resort_mismatch, P0022 resort_suspended.
- Every new `security definer` function has `set search_path = public, pg_temp` and is revoked from `public` and `anon`. `payment_order_quote` is granted to `authenticated`. Every other new definer function is revoked from `authenticated` and granted only to `service_role`. All of them are added to the allow-list in `supabase/tests/37_tenancy_isolation_test.sql`. New tables are not exposed automatically (`auto_expose_new_tables` is unset), so every grant is explicit.
- When changing an existing function, copy its **latest** definition. `confirm_booking` is latest in `0045_resort_functions.sql` (line 362). `checkout_booking` is latest in `0048_finance_ledger.sql` (line 93).
- Secrets (`RAZORPAY_KEY_SECRET`, `RAZORPAY_WEBHOOK_SECRET`) live only in Edge Function secrets or a gitignored `supabase/functions/.env` (`.env` is already in `.gitignore`). They never go in Dart, SQL or git. Tests use the fixture values `rzp_secret_fixture` / `whsec_fixture`.
- Deno: each function lives in `supabase/functions/<name>/` with `index.ts` (wiring only), `handler.ts` (all logic, dependencies injected), `handler_test.ts` and `deno.json`. Test files import `jsr:@std/assert@1` by full specifier and never import `index.ts` or `_shared/payments_db_supabase.ts`, so `deno test supabase/functions/` needs no config and no network access to Razorpay or Supabase. Run: `deno test supabase/functions/`.
- pgTAP conventions (from `37_tenancy_isolation_test.sql`):
  - Switch users with `set local role authenticated; set local request.jwt.claims to '{"sub":"<uuid>","role":"authenticated"}';`.
  - Act as the Edge Functions with `set local role service_role; set local request.jwt.claims to '{"role":"service_role"}';`. `service_role` has no table grants on the new tables, so read them after `reset role`.
  - `reset role` does not clear the claims. Run `set local request.jwt.claims to '';` before any superuser change that a trigger checks against `auth.uid()`, such as the resort status.
  - `now()` is fixed for the whole test transaction.
- Dart: repositories map every error through `mapPostgrestError` (`lib/core/errors.dart`). Widget and unit tests use the fakes in `test/support/` and never a real `SupabaseClient`, Razorpay SDK or network.
- Commands: `flutter test <path>`, `flutter test`, and `flutter analyze`. The analyzer baseline is 2 infos in `service_request_screen.dart`; add no new issues. Never run `dart format` on whole directories or on existing files; format only the lines you write. Revert pubspec.lock changes that only bump the SDK. Task 11's `razorpay_flutter` and `eventify` additions are expected.
- Commits: every message ends with a blank line and `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Do not push.
- UI copy, exact:
  - P0036: `Online payment is not available right now. Please try again in a few minutes.`
  - Dismissed checkout: `Payment cancelled.`
  - Unapplied, refund started: `Your payment could not be added to this booking, so it is being refunded in full.`
  - Unapplied, refund not started: `Your payment could not be added to this booking. The resort will refund it.`
  - Verify not reachable: `Your payment was received but is not confirmed yet. Check your booking again in a minute before paying again.`
  - Unsupported platform: `Online payment is not available on this device.`
  - Order descriptions: `<resort name>: booking advance` and `<resort name>: stay balance`.

## Review Focus

1. **The guest's connection drops after Razorpay took the money but before `payments-verify` answered.** They must not be told "payment failed" and pay again. The app says "received but not confirmed yet", and the `payment.captured` webhook confirms the booking without any verify call. Owning tests: Task 9 (a network error during verify becomes the not-confirmed-yet message) and Task 8 (a captured webhook settles an order no verify has seen).
2. **Verify and the webhook settle the same payment at the same moment, or verify is retried.** There must be one `payments` row and one confirmation. Owning tests: Task 3 (settling twice gives one payment) and Task 7 (verify called twice answers `paid` both times, and the order is settled twice without error).
3. **The balance changes while the payment window is open** (a food order, or a desk payment of part of it). The captured payment must not check the guest out at the wrong figure: it is unapplied and refunded, and the checkout screen shows the new balance. Owning tests: Task 3 (R9: balance changed → `unapplied`, still `checked_in`) and Task 12 (a failed payment refetches the charges).
4. **The resort is suspended between order and payment.** The money must not vanish: the order is unapplied with the reason `resort_suspended`, and a refund is due. Owning test: Task 3 (R10).
5. **Online payments are live, but the payment functions cannot be reached from the app.** The app falls back to the mock, `confirm_booking` refuses it with P0036, and the guest sees a readable message while keeping their hold. Owning tests: Task 3 (P0036 while live) and Task 12 (the booking screen shows the P0036 copy and keeps the hold).

## Plan decisions (where the spec is silent)

- The status checks in `payment_order_quote` for an advance run in `confirm_booking`'s order: resort active (P0022), then status `hold` (P0009), then expiry (P0006). For a balance, the resort status is not checked, the same as `checkout_booking`.
- `payment_order_json(payment_orders)` is a small invoker helper that builds settle's return value in one place. `refund_needed` = `status = 'unapplied' and cardinality(refund_ids) = 0`. It stays true on every settle call until a refund is recorded, so a refund that failed is retried by the next caller (the webhook).
- `failure_reason` on an unapplied order is either `reservation is <status>` or the SQL error text of the inner `confirm_booking` / `checkout_booking` call (for example `resort_suspended`).
- `payment_order_open` never extends the hold (spec decision 9). `payment_order_settle` gives an expired but unswept hold one more minute before confirming, so that `confirm_booking`'s own expiry check passes.
- `payments-create-order` parses the body first (400 on bad input, without touching the database), then syncs the live switch, then answers a probe or `configured:false`, and only then requires `Authorization: Bearer …`. A probe therefore works with the anon key.
- A webhook event is marked processed only after it has been handled. If handling fails, the function answers 500 and leaves the event unfinished, so Razorpay's retry processes it again.
- `PaymentFunctionsSource` takes a `FunctionInvoker` (`(name, body) => supabase.functions.invoke(name, body: body)`) so that it can be unit-tested without a client. `PaymentGateway.charge`'s new `purpose` parameter defaults to `advance`, so existing callers and fakes keep working once their signature has the parameter.
- `PaymentPurpose` lives in `lib/data/models/payment_order.dart` and is re-exported from `payment_gateway.dart`.
- The Makefile gains `functions-test: deno test supabase/functions/`. P7 and P8 may add the same target when they merge; keep one copy.

## Execution tracks

After Task 1, the database track and the app/functions track share no files. They can run in parallel, in worktrees branched from Task 1's commit, and are merged back before Task 13. Deno and Flutter tasks never need a database, because they use fakes.

| Task | Track | Depends on | Files it owns |
|---|---|---|---|
| 1 Interface contract | both | none | `0055` (schema + stubs), `45` (fixtures + contract), `37` (allow-list), `_shared/payments_types.ts`, `payment_order.dart`, `payment_order_repository.dart` (seam), `razorpay_checkout.dart` (types), `razorpay_checkout_platform.dart`, `razorpay_checkout_stub.dart`, `payment_gateway.dart` (param), `razorpay_gateway.dart` (param), test fakes |
| 2 Quote and open | DB | 1 | `0055`, `45` |
| 3 Live switch and settling | DB | 2 | `0055`, `45` |
| 4 Failures, refunds, webhook ledger | DB | 3 | `0055`, `45` |
| 5 Shared Razorpay module | Track (Deno) | 1 | `_shared/razorpay.ts`, `_shared/http.ts`, `_shared/testing.ts`, `_shared/razorpay_test.ts`, `Makefile` |
| 6 `payments-create-order` | Track (Deno) | 5 | `payments-create-order/*`, `_shared/payments_db_supabase.ts` |
| 7 `payments-verify` | Track (Deno) | 6 | `payments-verify/*`, `_shared/settlement.ts`, `_shared/settlement_test.ts` |
| 8 `payments-webhook` | Track (Deno) | 7 | `payments-webhook/*`, `supabase/config.toml` |
| 9 Functions client | Track (Flutter) | 1 | `payment_order_repository.dart`, `errors.dart`, their tests |
| 10 `RazorpayGateway` | Track (Flutter) | 9 | `razorpay_gateway.dart`, `payment_gateway.dart`, `payment_settings_screen.dart` (comment), gateway tests |
| 11 Checkout windows | Track (Flutter) | 1 | `razorpay_checkout.dart`, `razorpay_checkout_platform.dart`, `razorpay_checkout_web.dart`, `razorpay_checkout_mobile.dart`, `pubspec.yaml`, `pubspec.lock` |
| 12 Screens | Track (Flutter) | 10 | `booking_screen.dart`, `checkout_screen.dart`, `hold_lifecycle_test.dart`, `checkout_screen_test.dart` |
| 13 Integration | both | 2–12 | `README.md`, `docs/STATUS.md` (verification + docs) |

- The database track is strictly sequential: Tasks 2, 3 and 4 share one migration, one test file and one local Postgres.
- Deno runs 5 → 6 → 7 → 8. Flutter runs 9 → 10 → 12. Task 11 can run alongside 9, 10 and 12, because it touches none of their files.

---

## File Structure

**Database**
- Create `supabase/migrations/0055_online_payments.sql`. It contains:
  - the `payment_order_status` enum
  - the tables `payment_orders`, `payment_webhook_events` and `payment_gateway_config`, with their RLS and grants
  - `online_payments_live()` and `payment_order_json()`
  - the eight definer functions
  - the P0036 check and the gateway label in `confirm_booking` and `checkout_booking`
- Create `supabase/tests/45_online_payments_test.sql`.
- Modify `supabase/tests/37_tenancy_isolation_test.sql`: the definer allow-list.

**Edge Functions**
- Create `supabase/functions/_shared/payments_types.ts`: the request and response contract, and the database and Razorpay interfaces.
- Create `supabase/functions/_shared/razorpay.ts`: config, HMAC and signatures, and `RazorpayClient` (orders and refunds). P8 reuses it.
- Create `supabase/functions/_shared/http.ts`: CORS, `json`, `fail` and `preflight`.
- Create `supabase/functions/_shared/settlement.ts`: `refundIfNeeded`.
- Create `supabase/functions/_shared/payments_db_supabase.ts`: the supabase-js adapters (`userDb`, `serviceDb`).
- Create `supabase/functions/_shared/testing.ts`: fakes and fixtures for the handler tests.
- Create `supabase/functions/payments-create-order/{index.ts,handler.ts,handler_test.ts,deno.json}`, and the same four files for `payments-verify` and `payments-webhook`.
- Modify `supabase/config.toml`: `[functions.payments-webhook] verify_jwt = false`.
- Modify `Makefile`: the `functions-test` target.

**App**
- Create `lib/data/models/payment_order.dart`: `PaymentPurpose`, `CreateOrderResult` / `PaymentsNotConfigured` / `RazorpayOrder`, `VerifyResult`.
- Create `lib/data/repositories/payment_order_repository.dart`: `FunctionInvoker`, `PaymentOrderSource`, `PaymentFunctionsSource`, `paymentOrderSourceProvider`.
- Create `lib/features/booking/razorpay_checkout.dart`: `CheckoutRequest`, `CheckoutOutcome`, `RazorpayCheckout`, `UnsupportedRazorpayCheckout`, `checkoutOptions`, and the message constants.
- Create `lib/features/booking/razorpay_checkout_platform.dart`: the conditional export.
- Create `lib/features/booking/razorpay_checkout_stub.dart`, `razorpay_checkout_web.dart` and `razorpay_checkout_mobile.dart`.
- Rewrite `lib/features/booking/razorpay_gateway.dart`.
- Modify `lib/features/booking/payment_gateway.dart`: the `purpose` parameter, `razorpayCheckoutProvider`, and the new `paymentGatewayProvider`.
- Modify `lib/core/errors.dart`: P0036.
- Modify `lib/features/booking/booking_screen.dart` and `lib/features/stay/checkout_screen.dart`.
- Modify `lib/features/owner/payment_settings_screen.dart`: the doc comment only.
- Modify `pubspec.yaml`: `razorpay_flutter`.
- Create `test/support/fake_payment_order_source.dart`, `test/support/fake_razorpay_checkout.dart`, `test/data/payment_order_test.dart`, `test/data/payment_order_repository_test.dart` and `test/features/booking/razorpay_checkout_test.dart`. Rewrite `test/features/booking/razorpay_gateway_test.dart`. Modify `test/features/booking/hold_lifecycle_test.dart`, `test/features/booking/range_validation_widget_test.dart`, `test/features/stay/checkout_screen_test.dart` and `test/core/errors_test.dart`.

**Docs**
- Modify `README.md` (Payments, `make` targets, Known limitations) and `docs/STATUS.md`.

---

## Phase 0: Interface

### Task 1: Interface contract (schema, function signatures, Edge Function types, Dart API)

**Track:** both. Every later task depends on it.

**Files:**
- Create: `supabase/migrations/0055_online_payments.sql`
- Create: `supabase/tests/45_online_payments_test.sql`
- Modify: `supabase/tests/37_tenancy_isolation_test.sql` (definer allow-list)
- Create: `supabase/functions/_shared/payments_types.ts`
- Create: `lib/data/models/payment_order.dart`
- Create: `lib/data/repositories/payment_order_repository.dart`
- Create: `lib/features/booking/razorpay_checkout.dart`, `lib/features/booking/razorpay_checkout_platform.dart`, `lib/features/booking/razorpay_checkout_stub.dart`
- Modify: `lib/features/booking/payment_gateway.dart`, `lib/features/booking/razorpay_gateway.dart` (the `charge` signature only)
- Create: `test/support/fake_payment_order_source.dart`, `test/support/fake_razorpay_checkout.dart`
- Modify: `test/features/booking/hold_lifecycle_test.dart`, `test/features/booking/range_validation_widget_test.dart`, `test/features/stay/checkout_screen_test.dart` (the fakes' `charge` signature only)
- Test: `test/data/payment_order_test.dart`

**Interfaces:**
- Consumes:
  - `public.fill_property_id(parent_table, parent_col)` and `public.has_resort_role(uuid, boolean, variadic …)` (0043).
  - `public.payment_kind` (`advance`, `balance`, from 0001).
  - `public.payments` (0006, plus `method`, `reference` and `recorded_by` from 0048).
  - `supabaseProvider` (`lib/core/supabase_client.dart`).
- Produces (SQL; later tasks replace only the stub bodies):
  - `public.payment_order_quote(p_reservation uuid, p_kind public.payment_kind, p_amount numeric) returns jsonb`. Keys: `reservation_id, property_id, property_name, customer_id, kind, amount, amount_paise, currency, receipt, description, prefill{name,email,contact}`.
  - `public.payment_order_open(p_reservation uuid, p_customer uuid, p_kind public.payment_kind, p_amount numeric, p_razorpay_order_id text) returns public.payment_orders`
  - `public.payment_order_settle(p_razorpay_order_id text, p_razorpay_payment_id text) returns jsonb`. Keys: `order_id, reservation_id, kind, amount, status, razorpay_payment_id, reason, refund_needed`.
  - `public.payment_order_failed(p_razorpay_order_id text, p_reason text) returns void`
  - `public.payment_order_refunded(p_razorpay_payment_id text, p_refund_id text, p_amount numeric) returns void`
  - `public.payment_webhook_begin(p_event_id text, p_event text, p_payload jsonb) returns boolean`
  - `public.payment_webhook_done(p_event_id text, p_outcome text) returns void`
  - `public.payments_set_live(p_live boolean, p_key_id text) returns void`
  - `public.online_payments_live() returns boolean`: real in this task; security invoker; no client grants.
  - Enum `public.payment_order_status ('created','paid','unapplied','failed','refunded')`. Tables `public.payment_orders`, `public.payment_webhook_events` and `public.payment_gateway_config` (one row, `live = false`).
- Produces (TypeScript, `supabase/functions/_shared/payments_types.ts`): `PaymentKind`, `Prefill`, `CreateOrderRequest`, `CreateOrderResponse`, `ProbeResponse`, `VerifyRequest`, `VerifyResponse`, `ErrorBody`, `OrderQuote`, `SettleResult`, `DbError`, `UserPaymentsDb`, `ServicePaymentsDb`, `RazorpayOrderCreated`, `RazorpayRefundCreated`, `RazorpayApi`, `RazorpayConfig`. Exact shapes are in Step 7.
- Produces (Dart):
  - `enum PaymentPurpose { advance, balance }` with `String wire`.
  - `sealed class CreateOrderResult` with `factory CreateOrderResult.fromJson(Map<String, dynamic>)`. `final class PaymentsNotConfigured`. `final class RazorpayOrder { keyId, orderId, int amountPaise, currency, name, description, reservationId, String? prefillName, prefillEmail, prefillContact }`.
  - `enum VerifyOutcome { paid, unapplied }`, `enum RefundState { initiated, failed }`, `class VerifyResult { VerifyOutcome outcome; String reservationId; RefundState? refund }`.
  - `typedef FunctionInvoker = Future<FunctionResponse> Function(String functionName, Map<String, dynamic> body)`.
  - `abstract interface class PaymentOrderSource`:
    - `Future<CreateOrderResult> createOrder({required String reservationId, required num amount, required PaymentPurpose purpose})`
    - `Future<VerifyResult> verify({required String orderId, required String paymentId, required String signature})`
  - `class PaymentFunctionsSource implements PaymentOrderSource { PaymentFunctionsSource(this.invoke); final FunctionInvoker invoke; static const createOrderFunction = 'payments-create-order'; static const verifyFunction = 'payments-verify'; }`. Its bodies are filled in Task 9.
  - `final paymentOrderSourceProvider = Provider<PaymentOrderSource>`.
  - `class CheckoutRequest { keyId, orderId, int amountPaise, currency, name, description, prefillName?, prefillEmail?, prefillContact?; factory CheckoutRequest.fromOrder(RazorpayOrder) }`.
  - `sealed class CheckoutOutcome`: `CheckoutSucceeded { paymentId, orderId, signature }`, `CheckoutDismissed`, `CheckoutFailed { message }`.
  - `abstract interface class RazorpayCheckout { Future<CheckoutOutcome> open(CheckoutRequest request); }` and `class UnsupportedRazorpayCheckout`.
  - `RazorpayCheckout createRazorpayCheckout()`, from `razorpay_checkout_platform.dart`.
  - `final razorpayCheckoutProvider = Provider<RazorpayCheckout>`, in `payment_gateway.dart`.
  - `PaymentGateway.charge({required String reservationId, required num amount, PaymentPurpose purpose = PaymentPurpose.advance})`.
  - Test support: `FakePaymentOrderSource` (`createResult`, `createError`, `verifyResult`, `verifyError`, `createCalls`, `verifyCalls`), `razorpayOrder({...})`, and `FakeRazorpayCheckout` (`outcome`, `requests`).

- [ ] **Step 1: Record the baselines**

Run: `supabase db reset && supabase test db 2>&1 | tail -20`, then `flutter analyze 2>&1 | tail -5`, then `flutter test 2>&1 | tail -3`, then `deno --version`.
Expected:
- pgTAP: only the time-window failures listed in Global Constraints.
- analyzer: 2 infos.
- Flutter: a pass count; write it down.
- Deno: 2.x.

- [ ] **Step 2: Write the failing pgTAP contract test**

Create `supabase/tests/45_online_payments_test.sql`:

```sql
-- Online payments through Razorpay (P6), added in 0055_online_payments.sql.
-- See docs/superpowers/specs/2026-09-25-p6-razorpay-online-payments-design.md.
--
-- One file, built up by the plan's database tasks in order: each section
-- relies on the state the sections before it leave behind.
--
-- Fixtures: resort A "Online A" (advance 50%) with an owner and a staff
-- member; resort B "Online B" (advance 100%) with an owner; guests Gita
-- (profile name and phone set) and Om. Reservations:
--   R1 ...31  A, hold, Gita, total 10000, expires in 10 minutes
--   R2 ...32  A, checked in, Gita, total 6000, 3000 paid -> 3000 due
--   R3 ...33  A, hold, Gita, total 4000, expired a minute ago (not swept)
--   R4 ...34  B, hold, Om, total 2000, expires in 10 minutes
--   R6 ...36  A, checked in, Om, total 1000, nothing paid
--   R7 ...37  A, hold, Gita, total 1000, expires in 10 minutes
-- and one Razorpay order, order_fixture_r1 (R1, advance 5000).
begin;
select plan(17);

insert into auth.users (id, email) values
  ('a6000000-0000-0000-0000-000000000001','p6-a-owner@example.com'),
  ('a6000000-0000-0000-0000-000000000002','p6-a-staff@example.com'),
  ('a6000000-0000-0000-0000-000000000003','p6-b-owner@example.com'),
  ('a6000000-0000-0000-0000-000000000004','p6-gita@example.com'),
  ('a6000000-0000-0000-0000-000000000005','p6-om@example.com');
update public.profiles set full_name = 'Gita Guest', phone = '+919800000001'
  where id = 'a6000000-0000-0000-0000-000000000004';

insert into public.properties (id, name, slug, advance_pct) values
  ('a6100000-0000-4000-8000-000000000001','Online A','online-a', 50),
  ('a6100000-0000-4000-8000-000000000002','Online B','online-b', 100);

insert into public.resort_members (property_id, user_id, role) values
  ('a6100000-0000-4000-8000-000000000001','a6000000-0000-0000-0000-000000000001','owner'),
  ('a6100000-0000-4000-8000-000000000001','a6000000-0000-0000-0000-000000000002','staff'),
  ('a6100000-0000-4000-8000-000000000002','a6000000-0000-0000-0000-000000000003','owner');

insert into public.units (id, property_id, name, capacity_base, capacity_max) values
  ('a6100000-0000-4000-8000-000000000011','a6100000-0000-4000-8000-000000000001','A Cottage 1',2,4),
  ('a6100000-0000-4000-8000-000000000012','a6100000-0000-4000-8000-000000000001','A Cottage 2',2,4),
  ('a6100000-0000-4000-8000-000000000013','a6100000-0000-4000-8000-000000000001','A Cottage 3',2,4),
  ('a6100000-0000-4000-8000-000000000021','a6100000-0000-4000-8000-000000000002','B Cottage 1',2,4);

insert into public.reservations
  (id, unit_id, period, kind, status, customer_id, guests, quote, hold_expires_at, checked_in_at) values
  ('a6100000-0000-4000-8000-000000000031','a6100000-0000-4000-8000-000000000011',
   public.build_period('a6100000-0000-4000-8000-000000000011', current_date + 10, current_date + 12),
   'booking','hold','a6000000-0000-0000-0000-000000000004',2,'{"total":10000}',
   now() + interval '10 minutes', null),
  ('a6100000-0000-4000-8000-000000000032','a6100000-0000-4000-8000-000000000012',
   tstzrange(now() - interval '1 day', now() + interval '1 day', '[)'),
   'booking','checked_in','a6000000-0000-0000-0000-000000000004',2,'{"total":6000}',
   null, now() - interval '1 day'),
  ('a6100000-0000-4000-8000-000000000033','a6100000-0000-4000-8000-000000000013',
   public.build_period('a6100000-0000-4000-8000-000000000013', current_date + 10, current_date + 11),
   'booking','hold','a6000000-0000-0000-0000-000000000004',2,'{"total":4000}',
   now() - interval '1 minute', null),
  ('a6100000-0000-4000-8000-000000000034','a6100000-0000-4000-8000-000000000021',
   public.build_period('a6100000-0000-4000-8000-000000000021', current_date + 10, current_date + 11),
   'booking','hold','a6000000-0000-0000-0000-000000000005',2,'{"total":2000}',
   now() + interval '10 minutes', null),
  ('a6100000-0000-4000-8000-000000000036','a6100000-0000-4000-8000-000000000013',
   tstzrange(now() - interval '1 day', now() + interval '1 day', '[)'),
   'booking','checked_in','a6000000-0000-0000-0000-000000000005',2,'{"total":1000}',
   null, now() - interval '1 day'),
  ('a6100000-0000-4000-8000-000000000037','a6100000-0000-4000-8000-000000000012',
   public.build_period('a6100000-0000-4000-8000-000000000012', current_date + 30, current_date + 31),
   'booking','hold','a6000000-0000-0000-0000-000000000004',2,'{"total":1000}',
   now() + interval '10 minutes', null);

insert into public.payments (reservation_id, amount, kind, status, gateway, gateway_ref)
values ('a6100000-0000-4000-8000-000000000032', 3000, 'advance', 'succeeded', 'mock', 'p6-r2-advance');

insert into public.payment_orders (reservation_id, customer_id, kind, amount, razorpay_order_id)
values ('a6100000-0000-4000-8000-000000000031','a6000000-0000-0000-0000-000000000004',
        'advance', 5000, 'order_fixture_r1');

-- === Task 1: the contract ===================================================

select has_table('public', 'payment_orders', 'payment_orders exists');
select has_table('public', 'payment_webhook_events', 'payment_webhook_events exists');
select has_table('public', 'payment_gateway_config', 'payment_gateway_config exists');
select enum_has_labels('public', 'payment_order_status',
  array['created','paid','unapplied','failed','refunded'],
  'payment_order_status is created, paid, unapplied, failed, refunded');
select is((select array_agg(column_name::text order by ordinal_position)
             from information_schema.columns
            where table_schema = 'public' and table_name = 'payment_orders'),
  array['id','property_id','reservation_id','customer_id','kind','amount','currency',
        'razorpay_order_id','razorpay_payment_id','status','payment_id','refunded_amount',
        'refund_ids','failure_reason','created_at','updated_at'],
  'payment_orders has the columns the functions and the app read');
select is((select count(*)::int from public.payment_gateway_config where not live), 1,
  'the gateway switch is one row, off');
select is(public.online_payments_live(), false, 'online payments start switched off');
select is((select array_agg(f::text order by f::text)
             from unnest(array[
               'public.payment_order_quote(uuid, public.payment_kind, numeric)',
               'public.payment_order_open(uuid, uuid, public.payment_kind, numeric, text)',
               'public.payment_order_settle(text, text)',
               'public.payment_order_failed(text, text)',
               'public.payment_order_refunded(text, text, numeric)',
               'public.payment_webhook_begin(text, text, jsonb)',
               'public.payment_webhook_done(text, text)',
               'public.payments_set_live(boolean, text)']::regprocedure[]) f
            where has_function_privilege('anon', f, 'execute')),
  null, 'anon can execute none of the payment functions');
select is((select count(*)::int
             from unnest(array[
               'public.payment_order_quote(uuid, public.payment_kind, numeric)',
               'public.payment_order_open(uuid, uuid, public.payment_kind, numeric, text)',
               'public.payment_order_settle(text, text)',
               'public.payment_order_failed(text, text)',
               'public.payment_order_refunded(text, text, numeric)',
               'public.payment_webhook_begin(text, text, jsonb)',
               'public.payment_webhook_done(text, text)',
               'public.payments_set_live(boolean, text)']::regprocedure[]) f
            where has_function_privilege('authenticated', f, 'execute')
              and f::oid <> 'public.payment_order_quote(uuid, public.payment_kind, numeric)'::regprocedure::oid),
  0, 'authenticated can execute only payment_order_quote');
select is((select count(*)::int
             from unnest(array[
               'public.payment_order_open(uuid, uuid, public.payment_kind, numeric, text)',
               'public.payment_order_settle(text, text)',
               'public.payment_order_failed(text, text)',
               'public.payment_order_refunded(text, text, numeric)',
               'public.payment_webhook_begin(text, text, jsonb)',
               'public.payment_webhook_done(text, text)',
               'public.payments_set_live(boolean, text)']::regprocedure[]) f
            where has_function_privilege('service_role', f, 'execute')),
  7, 'the service role executes the seven server-only functions');

-- Reads: the guest's own orders, and the resort's staff roles. No direct
-- writes for anyone; the two server tables are closed to clients.
set local role authenticated;
set local request.jwt.claims to '{"sub":"a6000000-0000-0000-0000-000000000004","role":"authenticated"}';
select is((select count(*)::int from public.payment_orders), 1,
  'the guest reads their own payment order');
select throws_ok($$insert into public.payment_orders (reservation_id, customer_id, kind, amount, razorpay_order_id)
  values ('a6100000-0000-4000-8000-000000000031','a6000000-0000-0000-0000-000000000004','advance',5000,'order_forged')$$,
  '42501', null, 'a guest cannot write payment orders');
select throws_ok($$select * from public.payment_webhook_events$$,
  '42501', null, 'webhook events are server-only');
select throws_ok($$select * from public.payment_gateway_config$$,
  '42501', null, 'the gateway switch is server-only');
set local request.jwt.claims to '{"sub":"a6000000-0000-0000-0000-000000000005","role":"authenticated"}';
select is((select count(*)::int from public.payment_orders), 0,
  'another guest reads none of them');
set local request.jwt.claims to '{"sub":"a6000000-0000-0000-0000-000000000002","role":"authenticated"}';
select is((select count(*)::int from public.payment_orders), 1,
  'staff read their resort''s payment orders');
set local request.jwt.claims to '{"sub":"a6000000-0000-0000-0000-000000000003","role":"authenticated"}';
select is((select count(*)::int from public.payment_orders), 0,
  'another resort''s owner reads none of them');
reset role;
set local request.jwt.claims to '';

select * from finish();
rollback;
```

- [ ] **Step 3: Run it to verify it fails**

Run: `supabase test db supabase/tests/45_online_payments_test.sql`
Expected: FAIL at `insert into public.payment_orders`, with `relation "public.payment_orders" does not exist`.

- [ ] **Step 4: Write the migration's schema and function stubs**

Create `supabase/migrations/0055_online_payments.sql`:

```sql
-- Online payments through Razorpay (P6). Three Edge Functions
-- (supabase/functions/payments-*) talk to Razorpay with the deployment's
-- secrets. This migration gives them a record of every Razorpay order, a
-- service-role-only way to settle one without trusting the app, a
-- webhook ledger, and a switch that stops a guest confirming with a mock
-- payment once real payments are on. See
-- docs/superpowers/specs/2026-09-25-p6-razorpay-online-payments-design.md.
--
-- Error codes: P0036 online_payment_required (the guest's own
-- confirm_booking / checkout_booking with a mock payment while online
-- payments are live). Also raised: P0002 not found, P0006 hold expired,
-- P0008 not signed in or not the booking's guest, P0009 wrong state or
-- amount, P0022 resort_suspended.

create type public.payment_order_status as enum
  ('created', 'paid', 'unapplied', 'failed', 'refunded');

-- ---------------------------------------------------------------------
-- payment_orders: one row per Razorpay order. `unapplied` = money
-- captured that could not be applied to the booking (and is refunded).
-- Refunds are recorded here only; payments rows and the finance ledger
-- are never changed by a refund (spec decision 11).
create table public.payment_orders (
  id                  uuid primary key default gen_random_uuid(),
  property_id         uuid not null references public.properties(id),
  reservation_id      uuid not null references public.reservations(id) on delete cascade,
  customer_id         uuid not null references public.profiles(id),
  kind                public.payment_kind not null,
  amount              numeric(12,2) not null
    constraint payment_orders_amount_positive check (amount > 0),
  currency            text not null default 'INR'
    constraint payment_orders_currency_inr check (currency = 'INR'),
  razorpay_order_id   text not null unique,
  razorpay_payment_id text unique,
  status              public.payment_order_status not null default 'created',
  payment_id          uuid references public.payments(id) on delete set null,
  refunded_amount     numeric(12,2) not null default 0,
  refund_ids          text[] not null default '{}',
  failure_reason      text
    constraint payment_orders_reason_length check (failure_reason is null or length(failure_reason) <= 500),
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);
create index payment_orders_reservation_idx on public.payment_orders (reservation_id);
create index payment_orders_property_created_idx on public.payment_orders (property_id, created_at);

create trigger payment_orders_fill_property
  before insert or update on public.payment_orders
  for each row execute function public.fill_property_id('reservations', 'reservation_id');

alter table public.payment_orders enable row level security;
revoke all on public.payment_orders from anon, authenticated;
grant select on public.payment_orders to authenticated;
create policy payment_orders_read on public.payment_orders
  for select to authenticated
  using (public.has_resort_role(property_id, false, 'owner','admin','staff','accountant')
         or customer_id = auth.uid());

-- ---------------------------------------------------------------------
-- payment_webhook_events: each Razorpay event is processed once
-- (X-Razorpay-Event-Id). Server-only: no policies, no client grants.
create table public.payment_webhook_events (
  event_id     text primary key
    constraint payment_webhook_events_id_length check (length(event_id) between 1 and 200),
  event        text not null,
  payload      jsonb not null,
  received_at  timestamptz not null default now(),
  processed_at timestamptz,
  outcome      text
);
alter table public.payment_webhook_events enable row level security;
revoke all on public.payment_webhook_events from anon, authenticated;

-- ---------------------------------------------------------------------
-- payment_gateway_config: one row. `live` mirrors whether the Edge
-- Functions have Razorpay keys; payments-create-order keeps it in sync
-- through payments_set_live. Server-only.
create table public.payment_gateway_config (
  id         boolean primary key default true
    constraint payment_gateway_config_singleton check (id),
  live       boolean not null default false,
  key_id     text,
  updated_at timestamptz not null default now()
);
insert into public.payment_gateway_config (id) values (true);
alter table public.payment_gateway_config enable row level security;
revoke all on public.payment_gateway_config from anon, authenticated;

-- Read by confirm_booking/checkout_booking, which run as the owner.
create function public.online_payments_live()
returns boolean
language sql
stable
set search_path = public, pg_temp
as $$
  select coalesce((select live from public.payment_gateway_config where id), false);
$$;
revoke execute on function public.online_payments_live() from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- The functions. The signatures are the contract the Edge Functions are
-- built against; Tasks 2-4 replace the stub bodies.

-- The signed-in guest's own booking only (payments-create-order calls it
-- with the guest's JWT). Checks the amount against the advance rule or the
-- balance due and returns what the Razorpay order needs.
create function public.payment_order_quote(
  p_reservation uuid,
  p_kind        public.payment_kind,
  p_amount      numeric
) returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  raise exception using errcode = '0A000', message = 'not implemented';
end;
$$;
revoke execute on function public.payment_order_quote(uuid, public.payment_kind, numeric) from public, anon;
grant execute on function public.payment_order_quote(uuid, public.payment_kind, numeric) to authenticated;

-- Service role only: records the Razorpay order payments-create-order made.
create function public.payment_order_open(
  p_reservation       uuid,
  p_customer          uuid,
  p_kind              public.payment_kind,
  p_amount            numeric,
  p_razorpay_order_id text
) returns public.payment_orders
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  raise exception using errcode = '0A000', message = 'not implemented';
end;
$$;
revoke execute on function public.payment_order_open(uuid, uuid, public.payment_kind, numeric, text) from public, anon, authenticated;
grant execute on function public.payment_order_open(uuid, uuid, public.payment_kind, numeric, text) to service_role;

-- Service role only: applies a verified payment (confirm or check out),
-- or marks it unapplied. Idempotent per order.
create function public.payment_order_settle(
  p_razorpay_order_id   text,
  p_razorpay_payment_id text
) returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  raise exception using errcode = '0A000', message = 'not implemented';
end;
$$;
revoke execute on function public.payment_order_settle(text, text) from public, anon, authenticated;
grant execute on function public.payment_order_settle(text, text) to service_role;

-- Service role only: a payment.failed webhook.
create function public.payment_order_failed(
  p_razorpay_order_id text,
  p_reason            text
) returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  raise exception using errcode = '0A000', message = 'not implemented';
end;
$$;
revoke execute on function public.payment_order_failed(text, text) from public, anon, authenticated;
grant execute on function public.payment_order_failed(text, text) to service_role;

-- Service role only: a refund Razorpay made (refund.processed, or the
-- automatic refund of an unapplied payment).
create function public.payment_order_refunded(
  p_razorpay_payment_id text,
  p_refund_id           text,
  p_amount              numeric
) returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  raise exception using errcode = '0A000', message = 'not implemented';
end;
$$;
revoke execute on function public.payment_order_refunded(text, text, numeric) from public, anon, authenticated;
grant execute on function public.payment_order_refunded(text, text, numeric) to service_role;

-- Service role only: the webhook ledger.
create function public.payment_webhook_begin(
  p_event_id text,
  p_event    text,
  p_payload  jsonb
) returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  raise exception using errcode = '0A000', message = 'not implemented';
end;
$$;
revoke execute on function public.payment_webhook_begin(text, text, jsonb) from public, anon, authenticated;
grant execute on function public.payment_webhook_begin(text, text, jsonb) to service_role;

create function public.payment_webhook_done(
  p_event_id text,
  p_outcome  text
) returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  raise exception using errcode = '0A000', message = 'not implemented';
end;
$$;
revoke execute on function public.payment_webhook_done(text, text) from public, anon, authenticated;
grant execute on function public.payment_webhook_done(text, text) to service_role;

-- Service role only: payments-create-order mirrors the secrets here.
create function public.payments_set_live(
  p_live   boolean,
  p_key_id text
) returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  raise exception using errcode = '0A000', message = 'not implemented';
end;
$$;
revoke execute on function public.payments_set_live(boolean, text) from public, anon, authenticated;
grant execute on function public.payments_set_live(boolean, text) to service_role;
```

- [ ] **Step 5: Add the new definer functions to the allow-list**

In `supabase/tests/37_tenancy_isolation_test.sql`, inside the `p.proname <> all (array[ … ])` list, insert these lines just before the `-- 0044: properties_guard_status …` comment:

```sql
        -- 0055: online payments. payment_order_quote checks that the
        -- caller is the booking's own guest; the other seven are
        -- executable by service_role only (the payments-* Edge Functions)
        -- and take the resort from the order or reservation row.
        'payment_order_quote','payment_order_open','payment_order_settle',
        'payment_order_failed','payment_order_refunded','payment_webhook_begin',
        'payment_webhook_done','payments_set_live',
```

- [ ] **Step 6: Run the database tests to verify they pass**

Run: `supabase db reset && supabase test db supabase/tests/45_online_payments_test.sql supabase/tests/37_tenancy_isolation_test.sql`
Expected: PASS, 17/17 in 45, and 37 fully green, including "every security definer function is on the reviewed allow-list" and "every table with property_id has row security enabled".

- [ ] **Step 7: Write the Edge Function contract types**

Create `supabase/functions/_shared/payments_types.ts`:

```ts
// The contract of the payments-* Edge Functions (spec: "Edge Functions").
// The Flutter client mirrors these shapes in
// lib/data/models/payment_order.dart; the SQL functions they wrap are in
// supabase/migrations/0055_online_payments.sql.

/** Mirrors public.payment_kind. */
export type PaymentKind = "advance" | "balance";

export interface Prefill {
  name: string | null;
  email: string | null;
  contact: string | null;
}

/** POST payments-create-order. `amount` is in rupees, as the app shows it. */
export interface CreateOrderRequest {
  reservation_id: string;
  amount: number;
  purpose: PaymentKind;
}

export type CreateOrderResponse =
  | { configured: false }
  | {
    configured: true;
    key_id: string;
    order_id: string;
    /** Paise. */
    amount: number;
    currency: "INR";
    name: string;
    description: string;
    reservation_id: string;
    prefill: Prefill;
  };

/** POST payments-create-order with {"probe": true}. */
export type ProbeResponse = { configured: false } | { configured: true; key_id: string };

/** POST payments-verify: the three values Razorpay Checkout hands back. */
export interface VerifyRequest {
  razorpay_order_id: string;
  razorpay_payment_id: string;
  razorpay_signature: string;
}

export type VerifyResponse =
  | { configured: false }
  | {
    configured: true;
    outcome: "paid" | "unapplied";
    reservation_id: string;
    kind: PaymentKind;
    refund: "initiated" | "failed" | null;
  };

/** Every non-2xx body the three functions send. */
export interface ErrorBody {
  error:
    | "bad_request"
    | "unauthorized"
    | "db"
    | "gateway"
    | "invalid_signature"
    | "internal"
    | "not_configured";
  /** The Postgres error code, for error "db". */
  code?: string;
  message: string;
}

/** public.payment_order_quote's jsonb. */
export interface OrderQuote {
  reservation_id: string;
  property_id: string;
  property_name: string;
  customer_id: string;
  kind: PaymentKind;
  amount: number;
  amount_paise: number;
  currency: "INR";
  receipt: string;
  description: string;
  prefill: Prefill;
}

/** public.payment_order_settle's jsonb (built by payment_order_json). */
export interface SettleResult {
  order_id: string;
  reservation_id: string;
  kind: PaymentKind;
  amount: number;
  status: "paid" | "unapplied" | "refunded";
  razorpay_payment_id: string;
  reason: string | null;
  refund_needed: boolean;
}

/** A Postgres error from an RPC, with its SQLSTATE (e.g. "P0009"). */
export class DbError extends Error {
  constructor(readonly code: string, message: string) {
    super(message);
    this.name = "DbError";
  }
}

/** Calls made as the signed-in guest (their JWT). */
export interface UserPaymentsDb {
  quoteOrder(args: { reservationId: string; kind: PaymentKind; amount: number }): Promise<OrderQuote>;
}

/** Calls made with the service role. */
export interface ServicePaymentsDb {
  setLive(live: boolean, keyId: string | null): Promise<void>;
  openOrder(args: {
    reservationId: string;
    customerId: string;
    kind: PaymentKind;
    amount: number;
    razorpayOrderId: string;
  }): Promise<void>;
  /** null when the order id is not one of ours (P0002). */
  settleOrder(razorpayOrderId: string, razorpayPaymentId: string): Promise<SettleResult | null>;
  failOrder(razorpayOrderId: string, reason: string): Promise<void>;
  /** `amount` in rupees. */
  recordRefund(razorpayPaymentId: string, refundId: string, amount: number): Promise<void>;
  /** true while the event still needs processing. */
  beginWebhook(eventId: string, event: string, payload: unknown): Promise<boolean>;
  finishWebhook(eventId: string, outcome: string): Promise<void>;
}

export interface RazorpayOrderCreated {
  id: string;
  /** Paise. */
  amount: number;
  currency: string;
}

export interface RazorpayRefundCreated {
  id: string;
  /** Paise. */
  amount: number;
}

/** The two Razorpay REST calls the functions make. */
export interface RazorpayApi {
  createOrder(args: {
    amountPaise: number;
    currency: "INR";
    receipt: string;
    notes: Record<string, string>;
  }): Promise<RazorpayOrderCreated>;
  refundPayment(
    paymentId: string,
    args?: { amountPaise?: number; notes?: Record<string, string> },
  ): Promise<RazorpayRefundCreated>;
}

/** From the Edge Function secrets; null when the keys are not set. */
export interface RazorpayConfig {
  keyId: string;
  keySecret: string;
  webhookSecret: string | null;
}
```

Run: `deno check supabase/functions/_shared/payments_types.ts`
Expected: no output (it type-checks).

- [ ] **Step 8: Write the failing Dart model test**

Create `test/data/payment_order_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/data/models/payment_order.dart';
import 'package:pasala/features/booking/razorpay_checkout.dart';

void main() {
  test('PaymentPurpose uses the payment_kind wire values', () {
    expect(PaymentPurpose.advance.wire, 'advance');
    expect(PaymentPurpose.balance.wire, 'balance');
  });

  test('configured:false is PaymentsNotConfigured', () {
    expect(CreateOrderResult.fromJson({'configured': false}),
        isA<PaymentsNotConfigured>());
  });

  test('a created order reads every field payments-create-order sends', () {
    final result = CreateOrderResult.fromJson({
      'configured': true,
      'key_id': 'rzp_test_fixture',
      'order_id': 'order_P6test0001',
      'amount': 500000,
      'currency': 'INR',
      'name': 'Online A',
      'description': 'Online A: booking advance',
      'reservation_id': 'r1',
      'prefill': {'name': 'Gita Guest', 'email': 'gita@example.com', 'contact': null},
    });

    expect(result, isA<RazorpayOrder>());
    final order = result as RazorpayOrder;
    expect(order.keyId, 'rzp_test_fixture');
    expect(order.orderId, 'order_P6test0001');
    expect(order.amountPaise, 500000);
    expect(order.currency, 'INR');
    expect(order.name, 'Online A');
    expect(order.description, 'Online A: booking advance');
    expect(order.reservationId, 'r1');
    expect(order.prefillName, 'Gita Guest');
    expect(order.prefillEmail, 'gita@example.com');
    expect(order.prefillContact, isNull);
  });

  test('VerifyResult reads paid and unapplied with the refund state', () {
    final paid = VerifyResult.fromJson(
        {'configured': true, 'outcome': 'paid', 'reservation_id': 'r1', 'refund': null});
    expect(paid.outcome, VerifyOutcome.paid);
    expect(paid.reservationId, 'r1');
    expect(paid.refund, isNull);

    final unapplied = VerifyResult.fromJson({
      'configured': true,
      'outcome': 'unapplied',
      'reservation_id': 'r1',
      'refund': 'initiated',
    });
    expect(unapplied.outcome, VerifyOutcome.unapplied);
    expect(unapplied.refund, RefundState.initiated);
  });

  test('an outcome the app does not know is never read as paid', () {
    final result = VerifyResult.fromJson(
        {'configured': true, 'outcome': 'something-new', 'reservation_id': 'r1'});
    expect(result.outcome, VerifyOutcome.unapplied);
  });

  test('CheckoutRequest.fromOrder copies the order', () {
    const order = RazorpayOrder(
      keyId: 'rzp_test_fixture',
      orderId: 'order_1',
      amountPaise: 300000,
      currency: 'INR',
      name: 'Online A',
      description: 'Online A: stay balance',
      reservationId: 'r2',
      prefillContact: '+919800000001',
    );
    final request = CheckoutRequest.fromOrder(order);
    expect(request.keyId, 'rzp_test_fixture');
    expect(request.orderId, 'order_1');
    expect(request.amountPaise, 300000);
    expect(request.description, 'Online A: stay balance');
    expect(request.prefillContact, '+919800000001');
    expect(request.prefillName, isNull);
  });

  test('the unsupported checkout says so instead of pretending', () async {
    final outcome = await const UnsupportedRazorpayCheckout().open(
        CheckoutRequest.fromOrder(const RazorpayOrder(
      keyId: 'k',
      orderId: 'o',
      amountPaise: 100,
      currency: 'INR',
      name: 'n',
      description: 'd',
      reservationId: 'r',
    )));
    expect(outcome, isA<CheckoutFailed>());
    expect((outcome as CheckoutFailed).message,
        'Online payment is not available on this device.');
  });
}
```

- [ ] **Step 9: Run it to verify it fails**

Run: `flutter test test/data/payment_order_test.dart`
Expected: FAIL to compile: `payment_order.dart` / `razorpay_checkout.dart` not found.

- [ ] **Step 10: Write the Dart contract**

Create `lib/data/models/payment_order.dart`:

```dart
/// Online payments (P6): what the app sends to and reads back from the
/// payments-* Edge Functions. The shapes mirror
/// supabase/functions/_shared/payments_types.ts.
library;

/// What an online payment is for. Mirrors `public.payment_kind`: an
/// advance confirms a hold, a balance checks the guest out.
enum PaymentPurpose {
  advance('advance'),
  balance('balance');

  const PaymentPurpose(this.wire);

  /// The value `payments-create-order` and `public.payment_kind` use.
  final String wire;
}

/// What `payments-create-order` answered.
sealed class CreateOrderResult {
  const CreateOrderResult();

  factory CreateOrderResult.fromJson(Map<String, dynamic> json) =>
      json['configured'] == true
          ? RazorpayOrder.fromJson(json)
          : const PaymentsNotConfigured();
}

/// The deployment has no Razorpay keys: pay through the mock, exactly as
/// before P6 (spec decision 3).
final class PaymentsNotConfigured extends CreateOrderResult {
  const PaymentsNotConfigured();
}

/// A Razorpay order the server created for this exact amount.
final class RazorpayOrder extends CreateOrderResult {
  const RazorpayOrder({
    required this.keyId,
    required this.orderId,
    required this.amountPaise,
    required this.currency,
    required this.name,
    required this.description,
    required this.reservationId,
    this.prefillName,
    this.prefillEmail,
    this.prefillContact,
  });

  factory RazorpayOrder.fromJson(Map<String, dynamic> json) {
    final prefill = (json['prefill'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    return RazorpayOrder(
      keyId: json['key_id'] as String,
      orderId: json['order_id'] as String,
      amountPaise: (json['amount'] as num).toInt(),
      currency: json['currency'] as String? ?? 'INR',
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      reservationId: json['reservation_id'] as String,
      prefillName: prefill['name'] as String?,
      prefillEmail: prefill['email'] as String?,
      prefillContact: prefill['contact'] as String?,
    );
  }

  /// The public Razorpay key id (never the secret).
  final String keyId;
  final String orderId;
  final int amountPaise;
  final String currency;

  /// The resort's name, shown in the payment window.
  final String name;
  final String description;
  final String reservationId;
  final String? prefillName;
  final String? prefillEmail;
  final String? prefillContact;
}

enum VerifyOutcome { paid, unapplied }

enum RefundState { initiated, failed }

/// What `payments-verify` answered once the server settled the payment.
class VerifyResult {
  const VerifyResult({
    required this.outcome,
    required this.reservationId,
    this.refund,
  });

  /// Anything but `paid` is treated as unapplied: the app must never claim
  /// a booking is paid on an answer it does not understand.
  factory VerifyResult.fromJson(Map<String, dynamic> json) => VerifyResult(
        outcome: json['outcome'] == 'paid'
            ? VerifyOutcome.paid
            : VerifyOutcome.unapplied,
        reservationId: json['reservation_id'] as String,
        refund: switch (json['refund']) {
          'initiated' => RefundState.initiated,
          'failed' => RefundState.failed,
          _ => null,
        },
      );

  final VerifyOutcome outcome;
  final String reservationId;
  final RefundState? refund;
}
```

Create `lib/data/repositories/payment_order_repository.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase_client.dart';
import '../models/payment_order.dart';

/// Calls one Edge Function by name with a JSON body. In the app this is
/// `supabase.functions.invoke`; tests pass a fake.
typedef FunctionInvoker = Future<FunctionResponse> Function(
    String functionName, Map<String, dynamic> body);

/// The online-payment calls `RazorpayGateway` makes. Tests override
/// [paymentOrderSourceProvider] with `FakePaymentOrderSource`
/// (test/support/fake_payment_order_source.dart).
abstract interface class PaymentOrderSource {
  /// Asks the server to create a Razorpay order for [amount] rupees, or
  /// learns that online payments are not configured.
  Future<CreateOrderResult> createOrder({
    required String reservationId,
    required num amount,
    required PaymentPurpose purpose,
  });

  /// Hands Razorpay Checkout's answer to the server, which checks the
  /// signature and settles the payment.
  Future<VerifyResult> verify({
    required String orderId,
    required String paymentId,
    required String signature,
  });
}

/// Backs [PaymentOrderSource] with the `payments-create-order` and
/// `payments-verify` Edge Functions.
class PaymentFunctionsSource implements PaymentOrderSource {
  PaymentFunctionsSource(this.invoke);

  final FunctionInvoker invoke;

  static const createOrderFunction = 'payments-create-order';
  static const verifyFunction = 'payments-verify';

  @override
  Future<CreateOrderResult> createOrder({
    required String reservationId,
    required num amount,
    required PaymentPurpose purpose,
  }) =>
      throw UnimplementedError('PaymentFunctionsSource.createOrder: Task 9');

  @override
  Future<VerifyResult> verify({
    required String orderId,
    required String paymentId,
    required String signature,
  }) =>
      throw UnimplementedError('PaymentFunctionsSource.verify: Task 9');
}

final paymentOrderSourceProvider = Provider<PaymentOrderSource>((ref) {
  final db = ref.watch(supabaseProvider);
  return PaymentFunctionsSource(
      (name, body) => db.functions.invoke(name, body: body));
});
```

Create `lib/features/booking/razorpay_checkout.dart`:

```dart
import '../../data/models/payment_order.dart';

/// The Razorpay payment window: Checkout.js on the web, razorpay_flutter
/// on Android/iOS (razorpay_checkout_platform.dart picks one).

const unsupportedCheckoutMessage =
    'Online payment is not available on this device.';

/// What the payment window needs. Only the public key id -- never a secret.
class CheckoutRequest {
  const CheckoutRequest({
    required this.keyId,
    required this.orderId,
    required this.amountPaise,
    required this.currency,
    required this.name,
    required this.description,
    this.prefillName,
    this.prefillEmail,
    this.prefillContact,
  });

  factory CheckoutRequest.fromOrder(RazorpayOrder order) => CheckoutRequest(
        keyId: order.keyId,
        orderId: order.orderId,
        amountPaise: order.amountPaise,
        currency: order.currency,
        name: order.name,
        description: order.description,
        prefillName: order.prefillName,
        prefillEmail: order.prefillEmail,
        prefillContact: order.prefillContact,
      );

  final String keyId;
  final String orderId;
  final int amountPaise;
  final String currency;
  final String name;
  final String description;
  final String? prefillName;
  final String? prefillEmail;
  final String? prefillContact;
}

sealed class CheckoutOutcome {
  const CheckoutOutcome();
}

/// Razorpay says the guest paid. Not trusted until `payments-verify` has
/// checked [signature] on the server.
final class CheckoutSucceeded extends CheckoutOutcome {
  const CheckoutSucceeded({
    required this.paymentId,
    required this.orderId,
    required this.signature,
  });

  final String paymentId;
  final String orderId;
  final String signature;
}

/// The guest closed the window without paying.
final class CheckoutDismissed extends CheckoutOutcome {
  const CheckoutDismissed();
}

/// The window failed; [message] is written for the guest.
final class CheckoutFailed extends CheckoutOutcome {
  const CheckoutFailed(this.message);

  final String message;
}

abstract interface class RazorpayCheckout {
  Future<CheckoutOutcome> open(CheckoutRequest request);
}

/// Platforms without a Razorpay SDK (desktop): says so rather than hanging.
class UnsupportedRazorpayCheckout implements RazorpayCheckout {
  const UnsupportedRazorpayCheckout();

  @override
  Future<CheckoutOutcome> open(CheckoutRequest request) async =>
      const CheckoutFailed(unsupportedCheckoutMessage);
}
```

Create `lib/features/booking/razorpay_checkout_stub.dart`:

```dart
import 'razorpay_checkout.dart';

/// Any platform with no Razorpay SDK wired up.
RazorpayCheckout createRazorpayCheckout() => const UnsupportedRazorpayCheckout();
```

Create `lib/features/booking/razorpay_checkout_platform.dart` (Task 11 makes this conditional):

```dart
// Picks the Razorpay payment window for the platform being compiled.
export 'razorpay_checkout_stub.dart';
```

In `lib/features/booking/payment_gateway.dart`:
- Replace the import block with:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/payment_order.dart';
import 'razorpay_checkout.dart';
import 'razorpay_checkout_platform.dart';
import 'razorpay_gateway.dart';

export '../../data/models/payment_order.dart' show PaymentPurpose;
```

- Replace the `PaymentGateway` interface and `MockGateway.charge` signature so that both read:

```dart
abstract interface class PaymentGateway {
  /// Takes [amount] rupees for [reservationId]. [purpose] tells the server
  /// which rule the amount must meet: the advance range for a hold, the
  /// balance due for a checked-in stay.
  Future<PaymentResult> charge({
    required String reservationId,
    required num amount,
    PaymentPurpose purpose = PaymentPurpose.advance,
  });
}
```

```dart
  @override
  Future<PaymentResult> charge({
    required String reservationId,
    required num amount,
    PaymentPurpose purpose = PaymentPurpose.advance,
  }) async {
```

- Add after `paymentGatewayProvider`:

```dart
/// The Razorpay payment window for this platform. Tests override it with
/// `FakeRazorpayCheckout`.
final razorpayCheckoutProvider =
    Provider<RazorpayCheckout>((ref) => createRazorpayCheckout());
```

In `lib/features/booking/razorpay_gateway.dart`, change only the `charge` signature to the same three-parameter form (add `PaymentPurpose purpose = PaymentPurpose.advance,` after `required num amount,`). `PaymentPurpose` comes from the `payment_gateway.dart` import that is already there. Task 10 rewrites the rest.

In each of the three test fakes, add the parameter the same way: `_ScriptedGateway.charge` in `test/features/booking/hold_lifecycle_test.dart`, `_NoopGateway.charge` in `test/features/booking/range_validation_widget_test.dart`, and `_FakeGateway.charge` in `test/features/stay/checkout_screen_test.dart`. Add `PaymentPurpose purpose = PaymentPurpose.advance,` after `required num amount,`. In `checkout_screen_test.dart` the signature is on one line, so it becomes `charge({required String reservationId, required num amount, PaymentPurpose purpose = PaymentPurpose.advance}) async {`.

Create `test/support/fake_payment_order_source.dart`:

```dart
import 'package:pasala/data/models/payment_order.dart';
import 'package:pasala/data/repositories/payment_order_repository.dart';

/// A [PaymentOrderSource] with scripted answers and call logs.
class FakePaymentOrderSource implements PaymentOrderSource {
  CreateOrderResult createResult = const PaymentsNotConfigured();
  Object? createError;
  VerifyResult verifyResult =
      const VerifyResult(outcome: VerifyOutcome.paid, reservationId: 'r1');
  Object? verifyError;

  final createCalls =
      <({String reservationId, num amount, PaymentPurpose purpose})>[];
  final verifyCalls =
      <({String orderId, String paymentId, String signature})>[];

  @override
  Future<CreateOrderResult> createOrder({
    required String reservationId,
    required num amount,
    required PaymentPurpose purpose,
  }) async {
    createCalls.add(
        (reservationId: reservationId, amount: amount, purpose: purpose));
    if (createError != null) throw createError!;
    return createResult;
  }

  @override
  Future<VerifyResult> verify({
    required String orderId,
    required String paymentId,
    required String signature,
  }) async {
    verifyCalls.add(
        (orderId: orderId, paymentId: paymentId, signature: signature));
    if (verifyError != null) throw verifyError!;
    return verifyResult;
  }
}

RazorpayOrder razorpayOrder({
  String orderId = 'order_P6test0001',
  int amountPaise = 500000,
  String reservationId = 'r1',
}) =>
    RazorpayOrder(
      keyId: 'rzp_test_fixture',
      orderId: orderId,
      amountPaise: amountPaise,
      currency: 'INR',
      name: 'Online A',
      description: 'Online A: booking advance',
      reservationId: reservationId,
      prefillName: 'Gita Guest',
      prefillEmail: 'gita@example.com',
    );
```

Create `test/support/fake_razorpay_checkout.dart`:

```dart
import 'package:pasala/features/booking/razorpay_checkout.dart';

/// A payment window that answers [outcome] immediately and logs requests.
class FakeRazorpayCheckout implements RazorpayCheckout {
  FakeRazorpayCheckout([this.outcome = const CheckoutDismissed()]);

  CheckoutOutcome outcome;
  final requests = <CheckoutRequest>[];

  @override
  Future<CheckoutOutcome> open(CheckoutRequest request) async {
    requests.add(request);
    return outcome;
  }
}
```

- [ ] **Step 11: Run the tests to verify they pass**

Run: `flutter test test/data/payment_order_test.dart && flutter test && flutter analyze`
Expected: the new file passes (7 tests). The whole suite passes with the baseline count + 7. The analyzer shows only the 2 baseline infos.

- [ ] **Step 12: Commit**

```bash
git add supabase/migrations/0055_online_payments.sql supabase/tests/45_online_payments_test.sql \
  supabase/tests/37_tenancy_isolation_test.sql supabase/functions/_shared/payments_types.ts \
  lib/data/models/payment_order.dart lib/data/repositories/payment_order_repository.dart \
  lib/features/booking/razorpay_checkout.dart lib/features/booking/razorpay_checkout_platform.dart \
  lib/features/booking/razorpay_checkout_stub.dart lib/features/booking/payment_gateway.dart \
  lib/features/booking/razorpay_gateway.dart test/data/payment_order_test.dart \
  test/support/fake_payment_order_source.dart test/support/fake_razorpay_checkout.dart \
  test/features/booking/hold_lifecycle_test.dart test/features/booking/range_validation_widget_test.dart \
  test/features/stay/checkout_screen_test.dart
git commit -m "$(cat <<'EOF'
feat(payments): online payments contract (schema, function stubs, types)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

## Phase 1: Database track (Tasks 2 → 3 → 4, sequential)

### Task 2: `payment_order_quote` and `payment_order_open`

**Track:** DB. Depends on Task 1.

**Files:**
- Modify: `supabase/migrations/0055_online_payments.sql` (two stub bodies)
- Test: `supabase/tests/45_online_payments_test.sql` (new section; `plan(17)` becomes `plan(49)`)

**Interfaces:**
- Consumes: the Task 1 fixtures (R1–R7, `order_fixture_r1`), `public.current_charges(uuid)` (0045), `properties.advance_pct` (0014) and `properties.status` (0043).
- Produces: the real `payment_order_quote` and `payment_order_open` with the Task 1 signatures. It also leaves the orders `order_A1` (R1, advance 5000), `order_B1` (R2, balance 3000), `order_C1` (R3, advance 4000) and `order_D1` (R4, advance 2000), all `created`, for Task 3.

- [ ] **Step 1: Write the failing tests**

In `supabase/tests/45_online_payments_test.sql`, change `select plan(17);` to `select plan(49);`. Insert this section just before `select * from finish();`:

```sql
-- === Task 2: quoting and opening an order ====================================

set local role authenticated;
set local request.jwt.claims to '{"sub":"a6000000-0000-0000-0000-000000000004","role":"authenticated"}';

select is(public.payment_order_quote('a6100000-0000-4000-8000-000000000031', 'advance', 5000) ->> 'amount_paise',
  '500000', 'a 50% advance is quoted in paise');
select is(public.payment_order_quote('a6100000-0000-4000-8000-000000000031', 'advance', 5000) ->> 'customer_id',
  'a6000000-0000-0000-0000-000000000004', 'the quote names the paying guest');
select is(public.payment_order_quote('a6100000-0000-4000-8000-000000000031', 'advance', 5000) ->> 'receipt',
  'a6100000-0000-4000-8000-000000000031', 'the receipt is the reservation id');
select is(public.payment_order_quote('a6100000-0000-4000-8000-000000000031', 'advance', 5000) ->> 'description',
  'Online A: booking advance', 'an advance is described with the resort''s name');
select is(public.payment_order_quote('a6100000-0000-4000-8000-000000000031', 'advance', 5000) -> 'prefill',
  jsonb_build_object('name', 'Gita Guest', 'email', 'p6-gita@example.com', 'contact', '+919800000001'),
  'the payment window is prefilled from the guest''s profile');
select lives_ok($$select public.payment_order_quote('a6100000-0000-4000-8000-000000000031', 'advance', 10000)$$,
  'paying the full total is accepted');
select throws_ok($$select public.payment_order_quote('a6100000-0000-4000-8000-000000000031', 'advance', 4999.99)$$,
  'P0009', null, 'less than the advance is refused');
select throws_ok($$select public.payment_order_quote('a6100000-0000-4000-8000-000000000031', 'advance', 10000.01)$$,
  'P0009', null, 'more than the total is refused');
select throws_ok($$select public.payment_order_quote('a6100000-0000-4000-8000-000000000031', 'advance', null)$$,
  'P0009', null, 'a missing amount is refused');
select throws_ok($$select public.payment_order_quote('a6100000-0000-4000-8000-000000000031', 'advance', 5000.005)$$,
  'P0009', null, 'fractions of a paisa are refused');
select throws_ok($$select public.payment_order_quote('a6100000-0000-4000-8000-000000000033', 'advance', 4000)$$,
  'P0006', null, 'an expired hold cannot be paid for');
select throws_ok($$select public.payment_order_quote('a6100000-0000-4000-8000-000000000032', 'advance', 3000)$$,
  'P0009', null, 'a checked-in stay takes no advance');
select is(public.payment_order_quote('a6100000-0000-4000-8000-000000000032', 'balance', 3000) ->> 'kind',
  'balance', 'the balance of a checked-in stay is quoted');
select is(public.payment_order_quote('a6100000-0000-4000-8000-000000000032', 'balance', 3000) ->> 'description',
  'Online A: stay balance', 'a balance is described with the resort''s name');
select throws_ok($$select public.payment_order_quote('a6100000-0000-4000-8000-000000000032', 'balance', 2999)$$,
  'P0009', null, 'a balance must match what is due');
select throws_ok($$select public.payment_order_quote('a6100000-0000-4000-8000-000000000031', 'balance', 5000)$$,
  'P0009', null, 'a hold has no balance to pay');
select throws_ok($$select public.payment_order_quote('a6100000-0000-4000-8000-0000000000ff', 'advance', 1)$$,
  'P0002', null, 'an unknown booking is not found');
set local request.jwt.claims to '{"sub":"a6000000-0000-0000-0000-000000000005","role":"authenticated"}';
select throws_ok($$select public.payment_order_quote('a6100000-0000-4000-8000-000000000031', 'advance', 5000)$$,
  'P0008', null, 'another guest cannot pay for Gita''s hold');
set local request.jwt.claims to '';
select throws_ok($$select public.payment_order_quote('a6100000-0000-4000-8000-000000000031', 'advance', 5000)$$,
  'P0008', null, 'a caller with no identity is refused');

-- Resort B is suspended for one assertion.
reset role;
update public.properties set status = 'suspended' where id = 'a6100000-0000-4000-8000-000000000002';
set local role authenticated;
set local request.jwt.claims to '{"sub":"a6000000-0000-0000-0000-000000000005","role":"authenticated"}';
select throws_ok($$select public.payment_order_quote('a6100000-0000-4000-8000-000000000034', 'advance', 2000)$$,
  'P0022', null, 'a suspended resort takes no advance');
reset role;
set local request.jwt.claims to '';
update public.properties set status = 'active' where id = 'a6100000-0000-4000-8000-000000000002';

-- Opening orders, as the Edge Functions do.
set local role service_role;
set local request.jwt.claims to '{"role":"service_role"}';
select is((select o.status::text from public.payment_order_open('a6100000-0000-4000-8000-000000000031',
            'a6000000-0000-0000-0000-000000000004', 'advance', 5000, 'order_A1') o),
  'created', 'the service role opens an order');
select throws_ok($$select public.payment_order_open('a6100000-0000-4000-8000-000000000031',
  'a6000000-0000-0000-0000-000000000004', 'advance', 5000, 'order_A1')$$,
  '23505', null, 'a Razorpay order id is recorded once');
select throws_ok($$select public.payment_order_open('a6100000-0000-4000-8000-000000000031',
  'a6000000-0000-0000-0000-000000000005', 'advance', 5000, 'order_X1')$$,
  'P0008', null, 'an order is only for the booking''s own guest');
select throws_ok($$select public.payment_order_open('a6100000-0000-4000-8000-000000000031',
  'a6000000-0000-0000-0000-000000000004', 'balance', 5000, 'order_X2')$$,
  'P0009', null, 'a hold takes no balance order');
select throws_ok($$select public.payment_order_open('a6100000-0000-4000-8000-000000000031',
  'a6000000-0000-0000-0000-000000000004', 'advance', 0, 'order_X3')$$,
  'P0009', null, 'an order needs a positive amount');
select throws_ok($$select public.payment_order_open('a6100000-0000-4000-8000-000000000031',
  'a6000000-0000-0000-0000-000000000004', 'advance', 5000, '  ')$$,
  'P0009', null, 'an order needs a Razorpay order id');
select lives_ok($$select public.payment_order_open('a6100000-0000-4000-8000-000000000032',
  'a6000000-0000-0000-0000-000000000004', 'balance', 3000, 'order_B1')$$,
  'a balance order for the checked-in stay');
select lives_ok($$select public.payment_order_open('a6100000-0000-4000-8000-000000000033',
  'a6000000-0000-0000-0000-000000000004', 'advance', 4000, 'order_C1')$$,
  'an order for a hold that has just expired but is not swept yet');
select lives_ok($$select public.payment_order_open('a6100000-0000-4000-8000-000000000034',
  'a6000000-0000-0000-0000-000000000005', 'advance', 2000, 'order_D1')$$,
  'an order at resort B');
set local role authenticated;
set local request.jwt.claims to '{"sub":"a6000000-0000-0000-0000-000000000004","role":"authenticated"}';
select throws_ok($$select public.payment_order_open('a6100000-0000-4000-8000-000000000031',
  'a6000000-0000-0000-0000-000000000004', 'advance', 5000, 'order_X4')$$,
  '42501', null, 'a guest cannot open orders directly');
reset role;
set local request.jwt.claims to '';
select is((select property_id from public.payment_orders where razorpay_order_id = 'order_A1'),
  'a6100000-0000-4000-8000-000000000001'::uuid, 'the order takes the reservation''s resort');
select is((select hold_expires_at from public.reservations where id = 'a6100000-0000-4000-8000-000000000031'),
  now() + interval '10 minutes', 'opening an order does not extend the hold');
```

- [ ] **Step 2: Run them to verify they fail**

Run: `supabase test db supabase/tests/45_online_payments_test.sql`
Expected: FAIL from test 18 on: `not implemented` (SQLSTATE 0A000) from the stubs.

- [ ] **Step 3: Implement `payment_order_quote`**

In `0055_online_payments.sql`, replace the stub `create function public.payment_order_quote(…) … $$;` (keep the revoke/grant lines after it) with:

```sql
create function public.payment_order_quote(
  p_reservation uuid,
  p_kind        public.payment_kind,
  p_amount      numeric
) returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid      uuid := auth.uid();
  v_row      public.reservations;
  v_property public.properties;
  v_profile  public.profiles;
  v_email    text;
  v_total    numeric;
  v_min      numeric;
  v_balance  numeric;
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode = 'P0008';
  end if;

  select * into v_row from public.reservations where id = p_reservation;
  if not found then
    raise exception 'reservation not found' using errcode = 'P0002';
  end if;

  -- Only the guest pays online for their own booking (spec decision 14).
  if v_row.customer_id is distinct from v_uid then
    raise exception 'only the booking''s guest can pay online' using errcode = 'P0008';
  end if;

  if p_amount is null or p_amount <= 0 or p_amount <> round(p_amount, 2) then
    raise exception 'payment amount % is not valid', p_amount using errcode = 'P0009';
  end if;

  select * into v_property from public.properties where id = v_row.property_id;

  if p_kind = 'advance' then
    -- The same checks, in the same order, as confirm_booking (0045).
    if v_property.status is distinct from 'active' then
      raise exception using errcode = 'P0022', message = 'resort_suspended';
    end if;
    if v_row.status <> 'hold' then
      raise exception 'reservation is %', v_row.status using errcode = 'P0009';
    end if;
    if v_row.hold_expires_at < now() then
      raise exception 'hold expired' using errcode = 'P0006';
    end if;
    if v_row.quote is null then
      raise exception 'reservation has no quote' using errcode = 'P0009';
    end if;
    v_total := (v_row.quote ->> 'total')::numeric;
    v_min   := round(v_total * coalesce(v_property.advance_pct, 100) / 100, 2);
    if p_amount < v_min or p_amount > v_total then
      raise exception 'payment amount % is outside the accepted range % to %',
        p_amount, v_min, v_total
        using errcode = 'P0009';
    end if;
  elsif p_kind = 'balance' then
    -- The same rule as checkout_booking (0048): exactly what is due.
    if v_row.status <> 'checked_in' then
      raise exception 'reservation is %', v_row.status using errcode = 'P0009';
    end if;
    v_balance := (public.current_charges(p_reservation) ->> 'balance')::numeric;
    if p_amount is distinct from v_balance then
      raise exception 'payment amount % does not match balance due %', p_amount, v_balance
        using errcode = 'P0009';
    end if;
  else
    raise exception 'unknown payment kind' using errcode = 'P0009';
  end if;

  select * into v_profile from public.profiles where id = v_uid;
  select email into v_email from auth.users where id = v_uid;

  return jsonb_build_object(
    'reservation_id', v_row.id,
    'property_id',    v_row.property_id,
    'property_name',  v_property.name,
    'customer_id',    v_uid,
    'kind',           p_kind,
    'amount',         round(p_amount, 2),
    'amount_paise',   (round(p_amount, 2) * 100)::bigint,
    'currency',       'INR',
    'receipt',        v_row.id::text,
    'description',    v_property.name || case p_kind
                        when 'advance' then ': booking advance'
                        else ': stay balance' end,
    'prefill',        jsonb_build_object(
                        'name',    v_profile.full_name,
                        'email',   v_email,
                        'contact', v_profile.phone)
  );
end;
$$;
```

- [ ] **Step 4: Implement `payment_order_open`**

Replace the stub `create function public.payment_order_open(…) … $$;` (keep its revoke/grant lines) with:

```sql
create function public.payment_order_open(
  p_reservation       uuid,
  p_customer          uuid,
  p_kind              public.payment_kind,
  p_amount            numeric,
  p_razorpay_order_id text
) returns public.payment_orders
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_row   public.reservations;
  v_order public.payment_orders;
begin
  if p_razorpay_order_id is null or btrim(p_razorpay_order_id) = '' then
    raise exception 'a Razorpay order id is required' using errcode = 'P0009';
  end if;
  if p_amount is null or p_amount <= 0 then
    raise exception 'payment amount % is not valid', p_amount using errcode = 'P0009';
  end if;

  select * into v_row from public.reservations where id = p_reservation;
  if not found then
    raise exception 'reservation not found' using errcode = 'P0002';
  end if;

  -- payments-create-order quoted as this guest a moment ago; check again.
  if p_customer is null or v_row.customer_id is distinct from p_customer then
    raise exception 'only the booking''s guest can pay online' using errcode = 'P0008';
  end if;

  if p_kind is null
     or (p_kind = 'advance' and v_row.status <> 'hold')
     or (p_kind = 'balance' and v_row.status <> 'checked_in') then
    raise exception 'reservation is %', v_row.status using errcode = 'P0009';
  end if;

  -- The hold is not extended (spec decision 9). property_id comes from
  -- the reservation (payment_orders_fill_property).
  insert into public.payment_orders
    (reservation_id, customer_id, kind, amount, razorpay_order_id)
  values (p_reservation, p_customer, p_kind, p_amount, btrim(p_razorpay_order_id))
  returning * into v_order;

  return v_order;
end;
$$;
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `supabase db reset && supabase test db supabase/tests/45_online_payments_test.sql supabase/tests/37_tenancy_isolation_test.sql`
Expected: PASS, 49/49 in 45; 37 green.

- [ ] **Step 6: Commit**

```bash
git add supabase/migrations/0055_online_payments.sql supabase/tests/45_online_payments_test.sql
git commit -m "$(cat <<'EOF'
feat(payments): quote and open Razorpay orders server-side

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: The live switch, and settling a verified payment

**Track:** DB. Depends on Task 2.

**Files:**
- Modify: `supabase/migrations/0055_online_payments.sql` (the `payments_set_live` and `payment_order_settle` bodies, the new `payment_order_json`, and `confirm_booking` / `checkout_booking` copied in)
- Test: `supabase/tests/45_online_payments_test.sql` (new section; `plan(49)` becomes `plan(86)`)

**Interfaces:**
- Consumes: Task 2's orders; `confirm_booking(uuid, text, numeric)` (latest in 0045); `checkout_booking(uuid, text, numeric, payment_method)` (latest in 0048); `unit_room_status` (0047).
- Produces:
  - The real `payments_set_live` and `payment_order_settle`.
  - `public.payment_order_json(public.payment_orders) returns jsonb`, which is internal.
  - `confirm_booking` and `checkout_booking` raise P0036 for the guest's own mock payment while live, and label a payment `razorpay` when `payment_order_settle` calls them.
  - It leaves: `order_fixture_r1` paid (payment `pay_A1`); `order_A1` unapplied (`pay_A2`); `order_B1` and `order_C1` paid; `order_D1`, `order_G1` and `order_H1` unapplied. The live switch is off again.

- [ ] **Step 1: Write the failing tests**

Change `select plan(49);` to `select plan(86);`. Insert this section just before `select * from finish();`:

```sql
-- === Task 3: the live switch and settling ======================================

-- More fixtures: R9 is checked in at A with 2000 due, and its balance
-- changes before the payment lands; R10 is a hold at B, which is
-- suspended before the payment lands.
insert into public.reservations
  (id, unit_id, period, kind, status, customer_id, guests, quote, hold_expires_at, checked_in_at) values
  ('a6100000-0000-4000-8000-000000000039','a6100000-0000-4000-8000-000000000011',
   tstzrange(now() - interval '1 day', now() + interval '1 day', '[)'),
   'booking','checked_in','a6000000-0000-0000-0000-000000000004',2,'{"total":2000}',
   null, now() - interval '1 day'),
  ('a6100000-0000-4000-8000-000000000040','a6100000-0000-4000-8000-000000000021',
   public.build_period('a6100000-0000-4000-8000-000000000021', current_date + 50, current_date + 51),
   'booking','hold','a6000000-0000-0000-0000-000000000005',2,'{"total":2000}',
   now() + interval '10 minutes', null);

set local role service_role;
set local request.jwt.claims to '{"role":"service_role"}';
select lives_ok($$select public.payment_order_open('a6100000-0000-4000-8000-000000000039',
  'a6000000-0000-0000-0000-000000000004', 'balance', 2000, 'order_G1')$$, 'a balance order for R9');
select lives_ok($$select public.payment_order_open('a6100000-0000-4000-8000-000000000040',
  'a6000000-0000-0000-0000-000000000005', 'advance', 2000, 'order_H1')$$, 'an advance order for R10');
select lives_ok($$select public.payments_set_live(true, 'rzp_test_p6')$$,
  'the service role switches online payments on');
reset role;
select is(public.online_payments_live(), true, 'online payments are live');
select is((select key_id from public.payment_gateway_config), 'rzp_test_p6', 'the live key id is recorded');

-- While live, the guest's own mock payments are refused.
set local role authenticated;
set local request.jwt.claims to '{"sub":"a6000000-0000-0000-0000-000000000004","role":"authenticated"}';
select throws_ok($$select public.confirm_booking('a6100000-0000-4000-8000-000000000037', 'mock_r7', 1000)$$,
  'P0036', null, 'while live, a guest cannot confirm with a mock payment');
select throws_ok($$select public.checkout_booking('a6100000-0000-4000-8000-000000000032', 'mock_r2', 3000)$$,
  'P0036', null, 'while live, a guest cannot pay a balance with a mock payment');
set local app.payment_gateway = 'razorpay';
select throws_ok($$select public.confirm_booking('a6100000-0000-4000-8000-000000000037', 'mock_r7', 1000)$$,
  'P0036', null, 'a guest who sets app.payment_gateway still gets P0036');
set local app.payment_gateway = '';
set local request.jwt.claims to '{"sub":"a6000000-0000-0000-0000-000000000002","role":"authenticated"}';
select lives_ok($$select public.checkout_booking('a6100000-0000-4000-8000-000000000036', 'RCPT-1', 1000, 'cash')$$,
  'desk payments are unaffected while live');

-- Settling, as payments-verify and payments-webhook do.
set local role service_role;
set local request.jwt.claims to '{"role":"service_role"}';
select is(public.payment_order_settle('order_fixture_r1', 'pay_A1') ->> 'status', 'paid',
  'a verified advance is paid');
select is(auth.uid(), null, 'settling leaves no guest identity behind');
select is(coalesce(nullif(current_setting('app.payment_gateway', true), ''), 'unset'), 'unset',
  'settling leaves no gateway label behind');
select is(public.payment_order_settle('order_fixture_r1', 'pay_A1') ->> 'refund_needed', 'false',
  'settling again reports the same paid order');
reset role;
select is((select status::text from public.reservations where id = 'a6100000-0000-4000-8000-000000000031'),
  'confirmed', 'the hold is confirmed');
select is((select gateway || ':' || method || ':' || kind || ':' || amount || ':' || recorded_by
             from public.payments where gateway_ref = 'pay_A1'),
  'razorpay:gateway:advance:5000.00:a6000000-0000-0000-0000-000000000004',
  'the payment is recorded as Razorpay, by the guest');
select is((select count(*)::int from public.payments
            where reservation_id = 'a6100000-0000-4000-8000-000000000031'),
  1, 'one payment, however often it is settled');
select is((select payment_id is not null from public.payment_orders where razorpay_order_id = 'order_fixture_r1'),
  true, 'the order links its payment');

set local role service_role;
set local request.jwt.claims to '{"role":"service_role"}';
select is(public.payment_order_settle('order_A1', 'pay_A2') ->> 'status', 'unapplied',
  'a second payment for a confirmed booking is unapplied');
select is(public.payment_order_settle('order_A1', 'pay_A2') ->> 'refund_needed', 'true',
  'it stays refund-needed until a refund is recorded');
select is(public.payment_order_settle('order_B1', 'pay_B1') ->> 'status', 'paid',
  'a verified balance is paid');
select is(public.payment_order_settle('order_C1', 'pay_C1') ->> 'status', 'paid',
  'a payment for an expired but unswept hold still confirms');
reset role;
select is((select failure_reason from public.payment_orders where razorpay_order_id = 'order_A1'),
  'reservation is confirmed', 'the unapplied reason is kept');
select is((select status::text from public.reservations where id = 'a6100000-0000-4000-8000-000000000032'),
  'checked_out', 'the balance checks the guest out');
select is((select kind || ':' || gateway || ':' || amount from public.payments where gateway_ref = 'pay_B1'),
  'balance:razorpay:3000.00', 'the balance is recorded as Razorpay');
select is((select state::text from public.unit_room_status where unit_id = 'a6100000-0000-4000-8000-000000000012'),
  'dirty', 'the room needs cleaning after an online checkout');
select is((select status::text from public.reservations where id = 'a6100000-0000-4000-8000-000000000033'),
  'confirmed', 'the late hold is confirmed');

-- Before their payments land: R4's hold is swept, R9's balance changes
-- (a desk payment of 500), and resort B is suspended.
set local request.jwt.claims to '';
update public.reservations
   set status = 'cancelled', cancel_reason = 'hold expired', cancelled_at = now()
 where id = 'a6100000-0000-4000-8000-000000000034';
insert into public.payments (reservation_id, amount, kind, status, gateway, gateway_ref, method)
values ('a6100000-0000-4000-8000-000000000039', 500, 'balance', 'succeeded', 'desk', 'desk-p6-r9', 'cash');
update public.properties set status = 'suspended' where id = 'a6100000-0000-4000-8000-000000000002';
set local role service_role;
set local request.jwt.claims to '{"role":"service_role"}';
select is(public.payment_order_settle('order_D1', 'pay_D1') ->> 'status', 'unapplied',
  'a payment for a swept hold is unapplied');
select is(public.payment_order_settle('order_G1', 'pay_G1') ->> 'status', 'unapplied',
  'a balance that changed meanwhile is unapplied');
select is(public.payment_order_settle('order_H1', 'pay_H1') ->> 'reason', 'resort_suspended',
  'a resort suspended meanwhile leaves the payment unapplied');
select throws_ok($$select public.payment_order_settle('order_nope', 'pay_x')$$,
  'P0002', null, 'an unknown order is not found');
select throws_ok($$select public.payment_order_settle('order_fixture_r1', '')$$,
  'P0009', null, 'a payment id is required');
reset role;
set local request.jwt.claims to '';
update public.properties set status = 'active' where id = 'a6100000-0000-4000-8000-000000000002';
select is((select status::text from public.reservations where id = 'a6100000-0000-4000-8000-000000000039'),
  'checked_in', 'the stay whose balance changed is not checked out');

set local role authenticated;
set local request.jwt.claims to '{"sub":"a6000000-0000-0000-0000-000000000004","role":"authenticated"}';
select throws_ok($$select public.payment_order_settle('order_B1', 'pay_B1')$$,
  '42501', null, 'a guest cannot settle a payment');
select throws_ok($$select public.payments_set_live(false, null)$$,
  '42501', null, 'a guest cannot flip the switch');

-- Switched off again, the mock confirms exactly as before P6.
set local role service_role;
set local request.jwt.claims to '{"role":"service_role"}';
select lives_ok($$select public.payments_set_live(false, null)$$,
  'the switch goes off when the keys are removed');
set local role authenticated;
set local request.jwt.claims to '{"sub":"a6000000-0000-0000-0000-000000000004","role":"authenticated"}';
select lives_ok($$select public.confirm_booking('a6100000-0000-4000-8000-000000000037', 'mock_r7', 1000)$$,
  'with the switch off, the mock confirms as before');
reset role;
select is((select gateway from public.payments where reservation_id = 'a6100000-0000-4000-8000-000000000037'),
  'mock', 'and records a mock payment');
set local request.jwt.claims to '';
```

- [ ] **Step 2: Run them to verify they fail**

Run: `supabase test db supabase/tests/45_online_payments_test.sql`
Expected: FAIL at `the service role switches online payments on` (0A000). The later tests fail too.

- [ ] **Step 3: Implement `payments_set_live`**

Replace the stub `create function public.payments_set_live(…) … $$;` (keep its revoke/grant) with:

```sql
create function public.payments_set_live(
  p_live   boolean,
  p_key_id text
) returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_live   boolean := coalesce(p_live, false);
  v_key_id text    := case when coalesce(p_live, false) then nullif(btrim(p_key_id), '') end;
begin
  -- Called on every payments-create-order request: write only on change.
  update public.payment_gateway_config
     set live = v_live, key_id = v_key_id, updated_at = now()
   where id
     and (live is distinct from v_live or key_id is distinct from v_key_id);
end;
$$;
```

- [ ] **Step 4: Copy `confirm_booking` and `checkout_booking` in, with the gateway label and P0036**

Append to `0055_online_payments.sql`:

```sql
-- ---------------------------------------------------------------------
-- The gateway label and the live switch. A payment is labelled
-- `razorpay` only when payment_order_settle calls in (it sets
-- app.payment_gateway) AND the session role is service_role, so a client
-- that managed to set the setting still gets `mock`. While online
-- payments are live, the guest's own mock payment raises P0036
-- (spec decisions 5 and 7).
--
-- confirm_booking: copied from its latest definition,
-- 0045_resort_functions.sql; the changes are marked 0055.
create or replace function public.confirm_booking(
  p_reservation_id uuid,
  p_payment_ref    text,
  p_amount         numeric
) returns public.reservations
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid         uuid := auth.uid();
  v_row         public.reservations;
  v_total       numeric;
  v_advance_pct numeric;
  v_min         numeric;
  v_gateway     text := case                                        -- 0055
                          when current_setting('app.payment_gateway', true) = 'razorpay'
                           and current_setting('role', true) = 'service_role'
                          then 'razorpay' else 'mock' end;
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode = 'P0008';
  end if;

  select * into v_row from public.reservations
  where id = p_reservation_id for update;

  if not found then
    raise exception 'reservation not found' using errcode = 'P0002';
  end if;

  if v_row.customer_id is distinct from v_uid then
    perform public.assert_resort_role(v_row.property_id, true, 'owner','admin');
  end if;

  -- Before the resort-status check: a retried webhook for a booking that
  -- was already paid must get the row back even if the resort has since
  -- been suspended.
  if v_row.status = 'confirmed' then
    return v_row;   -- idempotent: a retried webhook must not double-charge
  end if;

  if not exists (select 1 from public.properties
                  where id = v_row.property_id and status = 'active') then
    raise exception using errcode = 'P0022', message = 'resort_suspended';
  end if;

  if v_row.status <> 'hold' then
    raise exception 'reservation is %', v_row.status using errcode = 'P0009';
  end if;

  if v_row.hold_expires_at < now() then
    raise exception 'hold expired' using errcode = 'P0006';
  end if;

  -- A NULL `p_amount` or NULL `quote` must hit this raise (see 0014).
  if p_amount is null or v_row.quote is null then
    raise exception 'payment amount % does not match quoted total %',
      p_amount, (v_row.quote ->> 'total')
      using errcode = 'P0009';
  end if;

  v_total := (v_row.quote ->> 'total')::numeric;

  select coalesce(p.advance_pct, 100) into v_advance_pct
  from public.properties p
  where p.id = v_row.property_id;

  v_min := round(v_total * coalesce(v_advance_pct, 100) / 100, 2);

  if p_amount < v_min or p_amount > v_total then
    raise exception
      'payment amount % is outside the accepted range % to %',
      p_amount, v_min, v_total
      using errcode = 'P0009';
  end if;

  -- 0055: once online payments are live, the guest's own confirmation
  -- comes only through payment_order_settle. An owner/admin confirming a
  -- hold (an offline payment) is unaffected.
  if v_gateway = 'mock' and v_row.customer_id = v_uid and public.online_payments_live() then
    raise exception using errcode = 'P0036', message = 'online_payment_required';
  end if;

  insert into public.payments
    (reservation_id, amount, kind, status, gateway, gateway_ref)
  values (p_reservation_id, p_amount, 'advance', 'succeeded', v_gateway,   -- 0055
          p_payment_ref);

  update public.reservations
     set status = 'confirmed', hold_expires_at = null
   where id = p_reservation_id
  returning * into v_row;

  return v_row;
end;
$$;

-- checkout_booking: copied from its latest definition,
-- 0048_finance_ledger.sql; the changes are marked 0055.
create or replace function public.checkout_booking(
  p_reservation_id uuid,
  p_payment_ref    text,
  p_amount         numeric,
  p_method         public.payment_method default 'gateway'
) returns public.reservations
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid     uuid := auth.uid();
  v_row     public.reservations;
  v_charges jsonb;
  v_balance numeric(12,2);
  v_method  public.payment_method := coalesce(p_method, 'gateway');   -- 0048
  v_gateway text := case                                                -- 0055
                      when current_setting('app.payment_gateway', true) = 'razorpay'
                       and current_setting('role', true) = 'service_role'
                      then 'razorpay' else 'mock' end;
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode = 'P0008';
  end if;

  select * into v_row from public.reservations
  where id = p_reservation_id for update;

  if not found then
    raise exception 'reservation not found' using errcode = 'P0002';
  end if;

  if v_row.customer_id is distinct from v_uid then
    perform public.assert_resort_role(v_row.property_id, true, 'owner','admin','staff','accountant');
  end if;

  -- 0048: only resort staff record a desk method, and only at the
  -- booking's own resort. A guest's own checkout (the branch above
  -- skipped) can only be gateway; a staff member checking out their own
  -- stay passes this check. Before the early return, so a guest never
  -- gets a desk method accepted, even as a no-op.
  if v_method <> 'gateway'
     and not public.has_resort_role(v_row.property_id, true,
                                    'owner','admin','staff','accountant') then
    raise exception 'desk payment methods are recorded by resort staff'
      using errcode = 'P0009';
  end if;

  if v_row.status = 'checked_out' then
    return v_row;   -- idempotent: a retried checkout must not double-charge
  end if;

  if v_row.status <> 'checked_in' then
    raise exception 'reservation is %', v_row.status using errcode = 'P0009';
  end if;

  v_charges := public.current_charges(p_reservation_id);
  v_balance := (v_charges ->> 'balance')::numeric;

  if v_balance > 0 and (p_amount is null or p_amount is distinct from v_balance) then
    raise exception 'payment amount % does not match balance due %',
      p_amount, v_balance
      using errcode = 'P0009';
  end if;

  if v_balance > 0 then
    if v_method = 'gateway' then
      -- 0055: see confirm_booking.
      if v_gateway = 'mock' and v_row.customer_id = v_uid and public.online_payments_live() then
        raise exception using errcode = 'P0036', message = 'online_payment_required';
      end if;
      insert into public.payments
        (reservation_id, amount, kind, status, gateway, gateway_ref, method, recorded_by)
      values (p_reservation_id, v_balance, 'balance', 'succeeded', v_gateway, p_payment_ref,   -- 0055
              'gateway', v_uid);
    else
      -- 0048: one balance payment per booking, so 'desk-<id>' stays unique
      -- under unique (gateway, gateway_ref) and doubles as a retry guard.
      -- The receipt/UTR number goes in `reference`, which is not unique.
      insert into public.payments
        (reservation_id, amount, kind, status, gateway, gateway_ref, method, reference, recorded_by)
      values (p_reservation_id, v_balance, 'balance', 'succeeded', 'desk',
              'desk-' || p_reservation_id, v_method,
              nullif(btrim(p_payment_ref), ''), v_uid);
    end if;
  end if;

  update public.reservations
     set status = 'checked_out', checked_out_at = clock_timestamp()
   where id = p_reservation_id
  returning * into v_row;

  -- 0047: the room needs cleaning now.
  insert into public.unit_room_status as s
    (unit_id, property_id, state, reason, updated_by, updated_at)
  values (v_row.unit_id, v_row.property_id, 'dirty', null, v_uid, now())
  on conflict (unit_id) do update
    set state      = 'dirty',
        reason     = null,
        updated_by = excluded.updated_by,
        updated_at = excluded.updated_at
    where s.state <> 'out_of_order';

  return v_row;
end;
$$;
```

Before pasting, diff both bodies against their sources: `sed -n '/create or replace function public.confirm_booking/,/^\$\$;/p' supabase/migrations/0045_resort_functions.sql` and `sed -n '/^create function public.checkout_booking/,/^\$\$;/p' supabase/migrations/0048_finance_ledger.sql`. The only differences may be the lines marked `0055`. `create or replace` keeps both functions' grants.

- [ ] **Step 5: Implement `payment_order_json` and `payment_order_settle`**

Replace the stub `create function public.payment_order_settle(…) … $$;` (keep its revoke/grant) with:

```sql
-- What settle returns; one place, so the idempotent and the first answer
-- have the same shape. Internal (no client grants).
create function public.payment_order_json(p_order public.payment_orders)
returns jsonb
language sql
immutable
set search_path = public, pg_temp
as $$
  select jsonb_build_object(
    'order_id',            p_order.id,
    'reservation_id',      p_order.reservation_id,
    'kind',                p_order.kind,
    'amount',              p_order.amount,
    'status',              p_order.status,
    'razorpay_payment_id', p_order.razorpay_payment_id,
    'reason',              p_order.failure_reason,
    'refund_needed',       p_order.status = 'unapplied' and cardinality(p_order.refund_ids) = 0
  );
$$;
revoke execute on function public.payment_order_json(public.payment_orders) from public, anon, authenticated;

create function public.payment_order_settle(
  p_razorpay_order_id   text,
  p_razorpay_payment_id text
) returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_order       public.payment_orders;
  v_res         public.reservations;
  v_payment     uuid;
  v_reason      text;
  v_prev_claims text := current_setting('request.jwt.claims', true);
  v_prev_sub    text := current_setting('request.jwt.claim.sub', true);
  v_prev_gw     text := current_setting('app.payment_gateway', true);
begin
  if p_razorpay_payment_id is null or btrim(p_razorpay_payment_id) = '' then
    raise exception 'a Razorpay payment id is required' using errcode = 'P0009';
  end if;

  select * into v_order from public.payment_orders
   where razorpay_order_id = p_razorpay_order_id
   for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'payment_order_not_found';
  end if;

  -- payments-verify and payments-webhook both land here for one payment:
  -- an order that is already settled is reported, never applied twice.
  if v_order.status in ('paid', 'unapplied', 'refunded') then
    return public.payment_order_json(v_order);
  end if;

  select * into v_res from public.reservations
   where id = v_order.reservation_id
   for update;

  -- Captured before release_expired_holds swept the hold: the dates are
  -- still held for this guest, so the payment wins (spec decision 9).
  if v_order.kind = 'advance' and v_res.status = 'hold' and v_res.hold_expires_at < now() then
    update public.reservations
       set hold_expires_at = now() + interval '1 minute'
     where id = v_res.id;
  end if;

  if (v_order.kind = 'advance' and v_res.status <> 'hold')
     or (v_order.kind = 'balance' and v_res.status <> 'checked_in') then
    v_reason := format('reservation is %s', v_res.status);
  else
    begin
      -- Act as the order's guest for the rest of this transaction, so the
      -- existing functions run their guest path unchanged (spec decision 7).
      perform set_config('request.jwt.claim.sub', v_order.customer_id::text, true);
      perform set_config('request.jwt.claims',
        json_build_object('sub', v_order.customer_id, 'role', 'authenticated')::text, true);
      perform set_config('app.payment_gateway', 'razorpay', true);

      if v_order.kind = 'advance' then
        perform public.confirm_booking(v_order.reservation_id, btrim(p_razorpay_payment_id), v_order.amount);
      else
        perform public.checkout_booking(v_order.reservation_id, btrim(p_razorpay_payment_id), v_order.amount, 'gateway');
      end if;

      select id into v_payment from public.payments
       where gateway = 'razorpay' and gateway_ref = btrim(p_razorpay_payment_id);
    exception when others then
      -- Money was taken but cannot be applied: unapplied, refunded by the
      -- caller (spec decision 10). The block's own settings roll back.
      v_reason  := sqlerrm;
      v_payment := null;
    end;
  end if;

  perform set_config('request.jwt.claim.sub', coalesce(v_prev_sub, ''), true);
  perform set_config('request.jwt.claims', coalesce(v_prev_claims, ''), true);
  perform set_config('app.payment_gateway', coalesce(v_prev_gw, ''), true);

  update public.payment_orders
     set status              = case when v_payment is null then 'unapplied' else 'paid' end
                                 ::public.payment_order_status,
         razorpay_payment_id = btrim(p_razorpay_payment_id),
         payment_id          = v_payment,
         failure_reason      = left(v_reason, 500),
         updated_at          = now()
   where id = v_order.id
  returning * into v_order;

  return public.payment_order_json(v_order);
end;
$$;
```

Keep the order in the file: `payment_order_json` must be created before `payment_order_settle`, and `confirm_booking` / `checkout_booking` (Step 4) may come anywhere after `online_payments_live`. Plpgsql resolves calls at run time.

- [ ] **Step 6: Run the tests to verify they pass**

Run: `supabase db reset && supabase test db supabase/tests/45_online_payments_test.sql supabase/tests/37_tenancy_isolation_test.sql supabase/tests/33_stay_checkout_test.sql supabase/tests/35_customer_checkout_test.sql supabase/tests/40_finance_ledger_test.sql`
Expected: PASS, 86/86 in 45. The existing checkout and finance files are unchanged and green, which proves the copied bodies behave as before while the switch is off.

If `a guest who sets app.payment_gateway still gets P0036` or `a verified advance is paid` fails, print `current_setting('role', true)` inside the settle path. The label check depends on `role` still reading `service_role` inside a security definer function (definer functions change `current_user`, not the `role` setting). Fix the check; do not delete the test.

- [ ] **Step 7: Commit**

```bash
git add supabase/migrations/0055_online_payments.sql supabase/tests/45_online_payments_test.sql
git commit -m "$(cat <<'EOF'
feat(payments): settle verified Razorpay payments; P0036 blocks mock while live

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: Failed payments, refunds, the webhook ledger, isolation

**Track:** DB. Depends on Task 3.

**Files:**
- Modify: `supabase/migrations/0055_online_payments.sql` (four stub bodies)
- Test: `supabase/tests/45_online_payments_test.sql` (new section; `plan(86)` becomes `plan(115)`)

**Interfaces:**
- Consumes: Task 3's orders and payments.
- Produces: the real `payment_order_failed`, `payment_order_refunded`, `payment_webhook_begin` and `payment_webhook_done`, with the Task 1 signatures.

- [ ] **Step 1: Write the failing tests**

Change `select plan(86);` to `select plan(115);`. Insert just before `select * from finish();`:

```sql
-- === Task 4: failures, refunds, the webhook ledger, isolation =================

-- R8: a hold at B whose first payment attempt fails.
insert into public.reservations
  (id, unit_id, period, kind, status, customer_id, guests, quote, hold_expires_at) values
  ('a6100000-0000-4000-8000-000000000038','a6100000-0000-4000-8000-000000000021',
   public.build_period('a6100000-0000-4000-8000-000000000021', current_date + 40, current_date + 41),
   'booking','hold','a6000000-0000-0000-0000-000000000005',2,'{"total":2000}',
   now() + interval '10 minutes');

set local role service_role;
set local request.jwt.claims to '{"role":"service_role"}';
select lives_ok($$select public.payment_order_open('a6100000-0000-4000-8000-000000000038',
  'a6000000-0000-0000-0000-000000000005', 'advance', 2000, 'order_F1')$$, 'an order for R8');
select lives_ok($$select public.payment_order_failed('order_F1', 'Card declined by bank')$$,
  'a failed attempt is recorded');
select lives_ok($$select public.payment_order_failed('order_fixture_r1', 'late failure')$$,
  'a failure event for a paid order is accepted');
select lives_ok($$select public.payment_order_failed('order_unknown', 'x')$$,
  'a failure for an unknown order is ignored');
reset role;
select is((select status || ':' || failure_reason from public.payment_orders where razorpay_order_id = 'order_F1'),
  'failed:Card declined by bank', 'the order is failed, with Razorpay''s reason');
select is((select status::text from public.payment_orders where razorpay_order_id = 'order_fixture_r1'),
  'paid', 'a failure never downgrades a paid order');
set local role service_role;
set local request.jwt.claims to '{"role":"service_role"}';
select is(public.payment_order_settle('order_F1', 'pay_F1') ->> 'status', 'paid',
  'a retry that succeeds on the same order settles');
reset role;
select is((select status::text from public.reservations where id = 'a6100000-0000-4000-8000-000000000038'),
  'confirmed', 'and confirms the hold');

set local role service_role;
set local request.jwt.claims to '{"role":"service_role"}';
select lives_ok($$select public.payment_order_refunded('pay_A2', 'rfnd_1', 5000)$$,
  'the service role records a refund');
select lives_ok($$select public.payment_order_refunded('pay_A2', 'rfnd_1', 5000)$$,
  'recording the same refund again is harmless');
select is(public.payment_order_settle('order_A1', 'pay_A2') ->> 'refund_needed', 'false',
  'a refunded order needs no refund');
select lives_ok($$select public.payment_order_refunded('pay_A1', 'rfnd_2', 1000)$$,
  'a partial refund of a paid order');
select lives_ok($$select public.payment_order_refunded('pay_unknown', 'rfnd_3', 100)$$,
  'a refund for an unknown payment is ignored');
select throws_ok($$select public.payment_order_refunded('pay_A1', '', 100)$$,
  'P0009', null, 'a refund needs its id');
reset role;
select is((select status || ':' || refunded_amount || ':' || cardinality(refund_ids)
             from public.payment_orders where razorpay_order_id = 'order_A1'),
  'refunded:5000.00:1', 'a full refund, counted once');
select is((select status || ':' || refunded_amount
             from public.payment_orders where razorpay_order_id = 'order_fixture_r1'),
  'paid:1000.00', 'a partial refund keeps the order paid');
select is((select status::text from public.payments where gateway_ref = 'pay_A1'),
  'succeeded', 'refunds never change the payments ledger');

set local role service_role;
set local request.jwt.claims to '{"role":"service_role"}';
select is(public.payment_webhook_begin('evt_p6_1', 'payment.captured', '{"n":1}'), true,
  'a new webhook event is to be processed');
select is(public.payment_webhook_begin('evt_p6_1', 'payment.captured', '{"n":1}'), true,
  'an event that was never finished is processed again');
select lives_ok($$select public.payment_webhook_done('evt_p6_1', 'settled:paid')$$,
  'the event is finished');
select is(public.payment_webhook_begin('evt_p6_1', 'payment.captured', '{"n":1}'), false,
  'a finished event is not processed twice');
select throws_ok($$select public.payment_webhook_begin('', 'x', '{}')$$,
  'P0009', null, 'an event needs its id');
reset role;
select is((select outcome from public.payment_webhook_events where event_id = 'evt_p6_1'),
  'settled:paid', 'the outcome is kept');

set local role authenticated;
set local request.jwt.claims to '{"sub":"a6000000-0000-0000-0000-000000000004","role":"authenticated"}';
select throws_ok($$select public.payment_webhook_begin('evt_x', 'x', '{}')$$,
  '42501', null, 'a guest cannot write the webhook ledger');
select throws_ok($$select public.payment_order_refunded('pay_A1', 'rfnd_x', 1)$$,
  '42501', null, 'a guest cannot record refunds');
set local request.jwt.claims to '{"sub":"a6000000-0000-0000-0000-000000000001","role":"authenticated"}';
select is((select count(*)::int from public.payment_orders
            where property_id = 'a6100000-0000-4000-8000-000000000002'),
  0, 'A''s owner reads none of B''s payment orders');
set local request.jwt.claims to '{"sub":"a6000000-0000-0000-0000-000000000003","role":"authenticated"}';
select is((select count(*)::int from public.payment_orders), 3,
  'B''s owner reads B''s three payment orders');
set local request.jwt.claims to '{"sub":"a6000000-0000-0000-0000-000000000005","role":"authenticated"}';
select is((select count(*)::int from public.payment_orders), 3,
  'Om reads his own three payment orders');
set local request.jwt.claims to '{"sub":"a6000000-0000-0000-0000-000000000002","role":"authenticated"}';
select throws_ok($$select public.payment_order_settle('order_F1', 'pay_F1')$$,
  '42501', null, 'resort staff cannot settle payments either');
reset role;
set local request.jwt.claims to '';
```

- [ ] **Step 2: Run them to verify they fail**

Run: `supabase test db supabase/tests/45_online_payments_test.sql`
Expected: FAIL at `a failed attempt is recorded` (0A000).

- [ ] **Step 3: Implement the four functions**

Replace each stub body (keep every revoke/grant) with:

```sql
create function public.payment_order_failed(
  p_razorpay_order_id text,
  p_reason            text
) returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  -- A failed attempt is not final: the guest can retry in the same
  -- payment window, and a later capture still settles the order.
  update public.payment_orders
     set status         = 'failed',
         failure_reason = left(coalesce(nullif(btrim(p_reason), ''), 'payment failed'), 500),
         updated_at     = now()
   where razorpay_order_id = p_razorpay_order_id
     and status in ('created', 'failed');
end;
$$;

create function public.payment_order_refunded(
  p_razorpay_payment_id text,
  p_refund_id           text,
  p_amount              numeric
) returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_order public.payment_orders;
  v_total numeric(12,2);
begin
  if p_refund_id is null or btrim(p_refund_id) = '' or p_amount is null or p_amount <= 0 then
    raise exception 'a refund id and a positive amount are required' using errcode = 'P0009';
  end if;

  select * into v_order from public.payment_orders
   where razorpay_payment_id = p_razorpay_payment_id
   for update;
  -- Unknown payments (another app on the same Razorpay account) and
  -- refunds already recorded are ignored.
  if not found or btrim(p_refund_id) = any (v_order.refund_ids) then
    return;
  end if;

  v_total := least(v_order.amount, v_order.refunded_amount + p_amount);

  -- Recorded here only: payments rows and the finance ledger stay as they
  -- are (spec decision 11).
  update public.payment_orders
     set refund_ids      = refund_ids || btrim(p_refund_id),
         refunded_amount = v_total,
         status          = case when v_total >= amount then 'refunded'::public.payment_order_status
                                else status end,
         updated_at      = now()
   where id = v_order.id;
end;
$$;

create function public.payment_webhook_begin(
  p_event_id text,
  p_event    text,
  p_payload  jsonb
) returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_processed timestamptz;
begin
  if p_event_id is null or btrim(p_event_id) = '' then
    raise exception 'a webhook event id is required' using errcode = 'P0009';
  end if;

  insert into public.payment_webhook_events (event_id, event, payload)
  values (btrim(p_event_id), coalesce(p_event, 'unknown'), coalesce(p_payload, '{}'::jsonb))
  on conflict (event_id) do nothing;

  select processed_at into v_processed
    from public.payment_webhook_events
   where event_id = btrim(p_event_id);

  -- Unfinished (a crash mid-way) is processed again; settling is idempotent.
  return v_processed is null;
end;
$$;

create function public.payment_webhook_done(
  p_event_id text,
  p_outcome  text
) returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  update public.payment_webhook_events
     set processed_at = now(),
         outcome      = left(p_outcome, 200)
   where event_id = btrim(p_event_id);
end;
$$;
```

- [ ] **Step 4: Run the whole suite**

Run: `supabase db reset && supabase test db`
Expected: 45 passes 115/115, 37 is green, and the only failures are the known time-window ones.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/0055_online_payments.sql supabase/tests/45_online_payments_test.sql
git commit -m "$(cat <<'EOF'
feat(payments): failed payments, refunds and the webhook ledger

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---
## Phase 2: Edge Functions track (Tasks 5 → 6 → 7 → 8)

### Task 5: The shared Razorpay module

**Track:** Track (Deno). Depends on Task 1 (`_shared/payments_types.ts`).

**Files:**
- Create: `supabase/functions/_shared/razorpay.ts`
- Create: `supabase/functions/_shared/http.ts`
- Create: `supabase/functions/_shared/testing.ts` (fakes and fixtures for every handler test)
- Test: `supabase/functions/_shared/razorpay_test.ts`
- Modify: `Makefile` (the `functions-test` target)

**Interfaces:**
- Consumes: `RazorpayApi`, `RazorpayConfig`, `RazorpayOrderCreated`, `RazorpayRefundCreated`, `ErrorBody` and the database interfaces (Task 1).
- Produces:
  - `razorpay.ts`:
    - `RAZORPAY_API`
    - `readConfig(get: (name: string) => string | undefined): RazorpayConfig | null`
    - `hmacSha256Hex(secret, message): Promise<string>`
    - `sha256Hex(message): Promise<string>`
    - `timingSafeEqual(a, b): boolean`
    - `verifyPaymentSignature(orderId, paymentId, signature, keySecret): Promise<boolean>`
    - `verifyWebhookSignature(rawBody, signature, webhookSecret): Promise<boolean>`
    - `class RazorpayHttpError { status; body }`
    - `type FetchFn`
    - `class RazorpayClient implements RazorpayApi`, constructed as `(config, fetchFn?, baseUrl?)`
  - `http.ts`: `corsHeaders`, `json(status, body)`, `fail(status, error, message, code?)`, `preflight()`.
  - `testing.ts`:
    - fixtures: `fixtureConfig`, `fixtureSignature`, `reservationId`
    - builders: `orderQuote()`, `settleResult()`
    - fakes: `FakeUserDb`, `FakeServiceDb`, `FakeRazorpay`
    - requests and events: `post()`, `signedWebhook()`, `capturedEvent()`, `failedEvent()`, `refundEvent()`

- [ ] **Step 1: Write the test fixtures and the failing tests**

Create `supabase/functions/_shared/testing.ts`:

```ts
// Fakes and fixtures for the payments-* handler tests. Never imported by
// a function's index.ts.
import { hmacSha256Hex } from "./razorpay.ts";
import type {
  OrderQuote,
  PaymentKind,
  RazorpayApi,
  RazorpayConfig,
  RazorpayOrderCreated,
  RazorpayRefundCreated,
  ServicePaymentsDb,
  SettleResult,
  UserPaymentsDb,
} from "./payments_types.ts";

export const fixtureConfig: RazorpayConfig = {
  keyId: "rzp_test_fixture",
  keySecret: "rzp_secret_fixture",
  webhookSecret: "whsec_fixture",
};

/** HMAC_SHA256("order_P6test0001|pay_P6test0001", "rzp_secret_fixture"). */
export const fixtureSignature = "2ae02360e84fd4e6929f7c8d0d9761625c989e7a088e20af8bc7ea63d2d9f08c";

export const reservationId = "a6100000-0000-4000-8000-000000000031";

export function orderQuote(overrides: Partial<OrderQuote> = {}): OrderQuote {
  return {
    reservation_id: reservationId,
    property_id: "a6100000-0000-4000-8000-000000000001",
    property_name: "Online A",
    customer_id: "a6000000-0000-0000-0000-000000000004",
    kind: "advance",
    amount: 5000,
    amount_paise: 500000,
    currency: "INR",
    receipt: reservationId,
    description: "Online A: booking advance",
    prefill: { name: "Gita Guest", email: "p6-gita@example.com", contact: "+919800000001" },
    ...overrides,
  };
}

export function settleResult(overrides: Partial<SettleResult> = {}): SettleResult {
  return {
    order_id: "po-1",
    reservation_id: reservationId,
    kind: "advance",
    amount: 5000,
    status: "paid",
    razorpay_payment_id: "pay_P6test0001",
    reason: null,
    refund_needed: false,
    ...overrides,
  };
}

export class FakeUserDb implements UserPaymentsDb {
  calls: Array<{ reservationId: string; kind: PaymentKind; amount: number }> = [];
  quote: OrderQuote = orderQuote();
  error: Error | null = null;

  quoteOrder(args: { reservationId: string; kind: PaymentKind; amount: number }): Promise<OrderQuote> {
    this.calls.push(args);
    return this.error ? Promise.reject(this.error) : Promise.resolve(this.quote);
  }
}

export class FakeServiceDb implements ServicePaymentsDb {
  live: boolean | null = null;
  liveKeyId: string | null = null;
  opened: Array<Parameters<ServicePaymentsDb["openOrder"]>[0]> = [];
  openError: Error | null = null;
  settles: Array<[string, string]> = [];
  settleResult: SettleResult | null = settleResult();
  settleError: Error | null = null;
  failed: Array<[string, string]> = [];
  refunds: Array<[string, string, number]> = [];
  events = new Map<string, { event: string; processed: boolean; outcome?: string }>();

  setLive(live: boolean, keyId: string | null): Promise<void> {
    this.live = live;
    this.liveKeyId = keyId;
    return Promise.resolve();
  }

  openOrder(args: Parameters<ServicePaymentsDb["openOrder"]>[0]): Promise<void> {
    if (this.openError) return Promise.reject(this.openError);
    this.opened.push(args);
    return Promise.resolve();
  }

  settleOrder(razorpayOrderId: string, razorpayPaymentId: string): Promise<SettleResult | null> {
    this.settles.push([razorpayOrderId, razorpayPaymentId]);
    return this.settleError ? Promise.reject(this.settleError) : Promise.resolve(this.settleResult);
  }

  failOrder(razorpayOrderId: string, reason: string): Promise<void> {
    this.failed.push([razorpayOrderId, reason]);
    return Promise.resolve();
  }

  recordRefund(razorpayPaymentId: string, refundId: string, amount: number): Promise<void> {
    this.refunds.push([razorpayPaymentId, refundId, amount]);
    return Promise.resolve();
  }

  beginWebhook(eventId: string, event: string, _payload: unknown): Promise<boolean> {
    const known = this.events.get(eventId);
    if (!known) {
      this.events.set(eventId, { event, processed: false });
      return Promise.resolve(true);
    }
    return Promise.resolve(!known.processed);
  }

  finishWebhook(eventId: string, outcome: string): Promise<void> {
    const known = this.events.get(eventId);
    if (known) {
      known.processed = true;
      known.outcome = outcome;
    }
    return Promise.resolve();
  }
}

export class FakeRazorpay implements RazorpayApi {
  orders: Array<Parameters<RazorpayApi["createOrder"]>[0]> = [];
  refunds: Array<[string, Parameters<RazorpayApi["refundPayment"]>[1]]> = [];
  orderError: Error | null = null;
  refundError: Error | null = null;

  createOrder(args: Parameters<RazorpayApi["createOrder"]>[0]): Promise<RazorpayOrderCreated> {
    this.orders.push(args);
    if (this.orderError) return Promise.reject(this.orderError);
    return Promise.resolve({ id: "order_P6test0001", amount: args.amountPaise, currency: args.currency });
  }

  refundPayment(
    paymentId: string,
    args?: Parameters<RazorpayApi["refundPayment"]>[1],
  ): Promise<RazorpayRefundCreated> {
    this.refunds.push([paymentId, args]);
    if (this.refundError) return Promise.reject(this.refundError);
    return Promise.resolve({ id: "rfnd_P6test0001", amount: 500000 });
  }
}

export function post(body: unknown, headers: Record<string, string> = { Authorization: "Bearer user-jwt" }): Request {
  return new Request("http://localhost/functions/v1/fn", {
    method: "POST",
    headers: { "Content-Type": "application/json", ...headers },
    body: typeof body === "string" ? body : JSON.stringify(body),
  });
}

/** A webhook request signed with fixtureConfig.webhookSecret. */
export async function signedWebhook(event: unknown, eventId?: string): Promise<Request> {
  const raw = JSON.stringify(event);
  const signature = await hmacSha256Hex(fixtureConfig.webhookSecret!, raw);
  return new Request("http://localhost/functions/v1/payments-webhook", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-Razorpay-Signature": signature,
      ...(eventId === undefined ? {} : { "X-Razorpay-Event-Id": eventId }),
    },
    body: raw,
  });
}

export function capturedEvent(orderId = "order_P6test0001", paymentId = "pay_P6test0001") {
  return {
    entity: "event",
    account_id: "acc_fixture",
    event: "payment.captured",
    contains: ["payment"],
    payload: {
      payment: {
        entity: {
          id: paymentId,
          entity: "payment",
          amount: 500000,
          currency: "INR",
          status: "captured",
          order_id: orderId,
        },
      },
    },
    created_at: 1790000000,
  };
}

export function failedEvent(orderId = "order_P6test0001", paymentId = "pay_P6test0001") {
  return {
    entity: "event",
    account_id: "acc_fixture",
    event: "payment.failed",
    contains: ["payment"],
    payload: {
      payment: {
        entity: {
          id: paymentId,
          entity: "payment",
          amount: 500000,
          currency: "INR",
          status: "failed",
          order_id: orderId,
          error_description: "Card declined by bank",
        },
      },
    },
    created_at: 1790000000,
  };
}

export function refundEvent(paymentId = "pay_P6test0001", refundId = "rfnd_P6test0002", amountPaise = 100000) {
  return {
    entity: "event",
    account_id: "acc_fixture",
    event: "refund.processed",
    contains: ["refund", "payment"],
    payload: {
      refund: {
        entity: {
          id: refundId,
          entity: "refund",
          amount: amountPaise,
          currency: "INR",
          payment_id: paymentId,
          status: "processed",
        },
      },
    },
    created_at: 1790000000,
  };
}
```

Create `supabase/functions/_shared/razorpay_test.ts`. The two signature fixtures were computed independently with `printf '%s' 'order_P6test0001|pay_P6test0001' | openssl dgst -sha256 -hmac 'rzp_secret_fixture'` and `printf '%s' '{"entity":"event","event":"payment.captured"}' | openssl dgst -sha256 -hmac 'whsec_fixture'`.

```ts
import { assert, assertEquals, assertFalse, assertRejects } from "jsr:@std/assert@1";
import {
  hmacSha256Hex,
  RazorpayClient,
  RazorpayHttpError,
  readConfig,
  sha256Hex,
  timingSafeEqual,
  verifyPaymentSignature,
  verifyWebhookSignature,
} from "./razorpay.ts";
import { fixtureConfig, fixtureSignature } from "./testing.ts";

Deno.test("hmacSha256Hex matches RFC 4231 test case 2", async () => {
  assertEquals(
    await hmacSha256Hex("Jefe", "what do ya want for nothing?"),
    "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843",
  );
});

Deno.test("sha256Hex of the empty string", async () => {
  assertEquals(await sha256Hex(""), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");
});

Deno.test("a checkout signature over order_id|payment_id verifies", async () => {
  assert(await verifyPaymentSignature("order_P6test0001", "pay_P6test0001", fixtureSignature, "rzp_secret_fixture"));
});

Deno.test("an upper-case signature verifies too", async () => {
  assert(await verifyPaymentSignature(
    "order_P6test0001",
    "pay_P6test0001",
    fixtureSignature.toUpperCase(),
    "rzp_secret_fixture",
  ));
});

Deno.test("a signature for another payment, another secret, or nothing fails", async () => {
  assertFalse(await verifyPaymentSignature("order_P6test0001", "pay_OTHER", fixtureSignature, "rzp_secret_fixture"));
  assertFalse(await verifyPaymentSignature("order_P6test0001", "pay_P6test0001", fixtureSignature, "another_secret"));
  assertFalse(await verifyPaymentSignature("order_P6test0001", "pay_P6test0001", "", "rzp_secret_fixture"));
  assertFalse(await verifyPaymentSignature("", "pay_P6test0001", fixtureSignature, "rzp_secret_fixture"));
});

Deno.test("a webhook signature over the raw body verifies", async () => {
  assert(await verifyWebhookSignature(
    '{"entity":"event","event":"payment.captured"}',
    "856760a7b485f76effd94942bd1d835432170da3171d7e11d72f08b0d4cc7669",
    "whsec_fixture",
  ));
});

Deno.test("a webhook signature fails when one byte of the body changes", async () => {
  assertFalse(await verifyWebhookSignature(
    '{"entity":"event", "event":"payment.captured"}',
    "856760a7b485f76effd94942bd1d835432170da3171d7e11d72f08b0d4cc7669",
    "whsec_fixture",
  ));
  assertFalse(await verifyWebhookSignature("{}", "", "whsec_fixture"));
});

Deno.test("timingSafeEqual compares whole strings", () => {
  assert(timingSafeEqual("abc", "abc"));
  assertFalse(timingSafeEqual("abc", "abd"));
  assertFalse(timingSafeEqual("abc", "abcd"));
});

Deno.test("readConfig needs both keys; the webhook secret is optional", () => {
  const env = (values: Record<string, string>) => (name: string) => values[name];
  assertEquals(readConfig(env({})), null);
  assertEquals(readConfig(env({ RAZORPAY_KEY_ID: "rzp_test_x" })), null);
  assertEquals(readConfig(env({ RAZORPAY_KEY_ID: "  ", RAZORPAY_KEY_SECRET: "s" })), null);
  assertEquals(
    readConfig(env({ RAZORPAY_KEY_ID: "rzp_test_x", RAZORPAY_KEY_SECRET: "s" })),
    { keyId: "rzp_test_x", keySecret: "s", webhookSecret: null },
  );
  assertEquals(
    readConfig(env({ RAZORPAY_KEY_ID: "rzp_test_x", RAZORPAY_KEY_SECRET: "s", RAZORPAY_WEBHOOK_SECRET: "w" })),
    { keyId: "rzp_test_x", keySecret: "s", webhookSecret: "w" },
  );
});

type Call = { url: string; init: RequestInit };

function fakeFetch(status: number, body: unknown, calls: Call[]) {
  return (url: string, init: RequestInit) => {
    calls.push({ url, init });
    return Promise.resolve(new Response(JSON.stringify(body), { status }));
  };
}

Deno.test("createOrder posts paise to /v1/orders with Basic auth", async () => {
  const calls: Call[] = [];
  const client = new RazorpayClient(
    fixtureConfig,
    fakeFetch(200, { id: "order_X", amount: 500000, currency: "INR", status: "created" }, calls),
  );

  const order = await client.createOrder({
    amountPaise: 500000,
    currency: "INR",
    receipt: "r1",
    notes: { reservation_id: "r1" },
  });

  assertEquals(order.id, "order_X");
  assertEquals(calls[0].url, "https://api.razorpay.com/v1/orders");
  assertEquals(calls[0].init.method, "POST");
  const headers = calls[0].init.headers as Record<string, string>;
  assertEquals(headers["Authorization"], `Basic ${btoa("rzp_test_fixture:rzp_secret_fixture")}`);
  assertEquals(JSON.parse(calls[0].init.body as string), {
    amount: 500000,
    currency: "INR",
    receipt: "r1",
    notes: { reservation_id: "r1" },
  });
});

Deno.test("a Razorpay error becomes RazorpayHttpError with the status", async () => {
  const client = new RazorpayClient(fixtureConfig, fakeFetch(400, { error: { code: "BAD_REQUEST_ERROR" } }, []));
  const error = await assertRejects(
    () => client.createOrder({ amountPaise: 1, currency: "INR", receipt: "r", notes: {} }),
    RazorpayHttpError,
  );
  assertEquals(error.status, 400);
});

Deno.test("refundPayment posts to /v1/payments/:id/refund, full amount by default", async () => {
  const calls: Call[] = [];
  const client = new RazorpayClient(fixtureConfig, fakeFetch(200, { id: "rfnd_X", amount: 500000 }, calls));

  const refund = await client.refundPayment("pay_P6test0001", { notes: { reason: "unapplied" } });

  assertEquals(refund.id, "rfnd_X");
  assertEquals(calls[0].url, "https://api.razorpay.com/v1/payments/pay_P6test0001/refund");
  assertEquals(JSON.parse(calls[0].init.body as string), { notes: { reason: "unapplied" } });
});
```

- [ ] **Step 2: Run them to verify they fail**

Run: `deno test supabase/functions/_shared/`
Expected: FAIL with `Module not found "…/_shared/razorpay.ts"`.

- [ ] **Step 3: Write the module and the HTTP helpers**

Create `supabase/functions/_shared/razorpay.ts`:

```ts
// Razorpay for the Edge Functions: reading the secrets, the two HMAC
// signatures, and the Orders and Refunds REST calls. No Razorpay SDK:
// fetch and Web Crypto only, so tests inject `fetch`. P8 (subscription
// billing) reuses this module.
import type {
  RazorpayApi,
  RazorpayConfig,
  RazorpayOrderCreated,
  RazorpayRefundCreated,
} from "./payments_types.ts";

export const RAZORPAY_API = "https://api.razorpay.com/v1";

/** null unless both RAZORPAY_KEY_ID and RAZORPAY_KEY_SECRET are set. */
export function readConfig(get: (name: string) => string | undefined): RazorpayConfig | null {
  const keyId = get("RAZORPAY_KEY_ID")?.trim() ?? "";
  const keySecret = get("RAZORPAY_KEY_SECRET")?.trim() ?? "";
  if (keyId === "" || keySecret === "") return null;
  const webhookSecret = get("RAZORPAY_WEBHOOK_SECRET")?.trim() ?? "";
  return { keyId, keySecret, webhookSecret: webhookSecret === "" ? null : webhookSecret };
}

const encoder = new TextEncoder();

function toHex(buffer: ArrayBuffer): string {
  return Array.from(new Uint8Array(buffer), (b) => b.toString(16).padStart(2, "0")).join("");
}

export async function hmacSha256Hex(secret: string, message: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  return toHex(await crypto.subtle.sign("HMAC", key, encoder.encode(message)));
}

export async function sha256Hex(message: string): Promise<string> {
  return toHex(await crypto.subtle.digest("SHA-256", encoder.encode(message)));
}

/** Compares in time that does not depend on where the strings differ. */
export function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

/** Checkout's razorpay_signature = HMAC_SHA256(order_id|payment_id, key_secret). */
export async function verifyPaymentSignature(
  orderId: string,
  paymentId: string,
  signature: string,
  keySecret: string,
): Promise<boolean> {
  if (!orderId || !paymentId || !signature) return false;
  const expected = await hmacSha256Hex(keySecret, `${orderId}|${paymentId}`);
  return timingSafeEqual(expected, signature.trim().toLowerCase());
}

/** X-Razorpay-Signature = HMAC_SHA256(raw request body, webhook secret). */
export async function verifyWebhookSignature(
  rawBody: string,
  signature: string,
  webhookSecret: string,
): Promise<boolean> {
  if (!signature) return false;
  const expected = await hmacSha256Hex(webhookSecret, rawBody);
  return timingSafeEqual(expected, signature.trim().toLowerCase());
}

/** A non-2xx answer from Razorpay. The body is logged, never shown. */
export class RazorpayHttpError extends Error {
  constructor(readonly status: number, readonly body: string) {
    super(`Razorpay answered HTTP ${status}`);
    this.name = "RazorpayHttpError";
  }
}

export type FetchFn = (input: string, init: RequestInit) => Promise<Response>;

export class RazorpayClient implements RazorpayApi {
  constructor(
    private readonly config: RazorpayConfig,
    private readonly fetchFn: FetchFn = (input, init) => fetch(input, init),
    private readonly baseUrl: string = RAZORPAY_API,
  ) {}

  private async post<T>(path: string, body: unknown): Promise<T> {
    const response = await this.fetchFn(`${this.baseUrl}${path}`, {
      method: "POST",
      headers: {
        "Authorization": `Basic ${btoa(`${this.config.keyId}:${this.config.keySecret}`)}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(body),
    });
    const text = await response.text();
    if (!response.ok) throw new RazorpayHttpError(response.status, text);
    return JSON.parse(text) as T;
  }

  /** POST /v1/orders. Amounts are paise. */
  createOrder(args: {
    amountPaise: number;
    currency: "INR";
    receipt: string;
    notes: Record<string, string>;
  }): Promise<RazorpayOrderCreated> {
    return this.post<RazorpayOrderCreated>("/orders", {
      amount: args.amountPaise,
      currency: args.currency,
      receipt: args.receipt,
      notes: args.notes,
    });
  }

  /** POST /v1/payments/:id/refund. No amount = the full payment. */
  refundPayment(
    paymentId: string,
    args: { amountPaise?: number; notes?: Record<string, string> } = {},
  ): Promise<RazorpayRefundCreated> {
    return this.post<RazorpayRefundCreated>(
      `/payments/${encodeURIComponent(paymentId)}/refund`,
      args.amountPaise === undefined
        ? { notes: args.notes ?? {} }
        : { amount: args.amountPaise, notes: args.notes ?? {} },
    );
  }
}
```

Create `supabase/functions/_shared/http.ts`:

```ts
// CORS and JSON helpers for the payments-* Edge Functions. The Flutter
// web build calls them from another origin, so every response, errors
// included, carries the CORS headers.
import type { ErrorBody } from "./payments_types.ts";

export const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

export function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

/** An error body in the shape every payments function uses. */
export function fail(
  status: number,
  error: ErrorBody["error"],
  message: string,
  code?: string,
): Response {
  const body: ErrorBody = code === undefined ? { error, message } : { error, code, message };
  return json(status, body);
}

export function preflight(): Response {
  return new Response("ok", { headers: corsHeaders });
}
```

In `Makefile`, add `functions-test` to the `.PHONY` line, and add this target after `test:` (the recipe line starts with a tab):

```make
functions-test:
	deno test supabase/functions/
```

- [ ] **Step 4: Run them to verify they pass**

Run: `deno test supabase/functions/_shared/ && make functions-test`
Expected: PASS, 12 tests. No network access to Razorpay; the first run downloads `jsr:@std/assert` only.

- [ ] **Step 5: Commit**

```bash
git add supabase/functions/_shared/razorpay.ts supabase/functions/_shared/http.ts \
  supabase/functions/_shared/testing.ts supabase/functions/_shared/razorpay_test.ts Makefile
git commit -m "$(cat <<'EOF'
feat(payments): shared Razorpay module for Edge Functions (HMAC, orders, refunds)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: `payments-create-order`

**Track:** Track (Deno). Depends on Task 5.

**Files:**
- Create: `supabase/functions/payments-create-order/handler.ts`, `index.ts` and `deno.json`
- Create: `supabase/functions/_shared/payments_db_supabase.ts`
- Modify: `.gitignore` (`supabase/functions/**/deno.lock`)
- Test: `supabase/functions/payments-create-order/handler_test.ts`

**Interfaces:**
- Consumes: Task 5's `http.ts`, `readConfig`, `RazorpayClient` and `testing.ts`; the `payment_order_quote`, `payment_order_open` and `payments_set_live` SQL signatures (Task 1).
- Produces:
  - `createOrderHandler(deps: CreateOrderDeps): (req: Request) => Promise<Response>`, with `interface CreateOrderDeps { config(): RazorpayConfig | null; service: ServicePaymentsDb; userDb(authorization: string): UserPaymentsDb; razorpay(config: RazorpayConfig): RazorpayApi }`.
  - `parseCreateOrder(body)`.
  - `userDb(authorization)` and `serviceDb()` (supabase-js adapters over the Task 1 SQL functions). `settleOrder` maps P0002 to `null`.

- [ ] **Step 1: Write the failing tests**

Create `supabase/functions/payments-create-order/handler_test.ts`:

```ts
import { assertEquals } from "jsr:@std/assert@1";
import { createOrderHandler, type CreateOrderDeps } from "./handler.ts";
import { DbError, type RazorpayConfig } from "../_shared/payments_types.ts";
import { FakeRazorpay, FakeServiceDb, FakeUserDb, fixtureConfig, post, reservationId } from "../_shared/testing.ts";

function setup(config: RazorpayConfig | null = fixtureConfig) {
  const service = new FakeServiceDb();
  const user = new FakeUserDb();
  const razorpay = new FakeRazorpay();
  const authorizations: string[] = [];
  const deps: CreateOrderDeps = {
    config: () => config,
    service,
    userDb: (authorization) => {
      authorizations.push(authorization);
      return user;
    },
    razorpay: () => razorpay,
  };
  return { handler: createOrderHandler(deps), service, user, razorpay, authorizations };
}

const request = { reservation_id: reservationId, amount: 5000, purpose: "advance" };

Deno.test("OPTIONS answers the CORS preflight", async () => {
  const { handler } = setup();
  const res = await handler(new Request("http://localhost/fn", { method: "OPTIONS" }));
  assertEquals(res.status, 200);
  assertEquals(res.headers.get("Access-Control-Allow-Origin"), "*");
});

Deno.test("GET is refused", async () => {
  const { handler } = setup();
  const res = await handler(new Request("http://localhost/fn"));
  assertEquals(res.status, 405);
});

Deno.test("without keys it answers configured:false, switches live off and calls nobody", async () => {
  const { handler, service, user, razorpay } = setup(null);
  const res = await handler(post(request));
  assertEquals(res.status, 200);
  assertEquals(await res.json(), { configured: false });
  assertEquals(service.live, false);
  assertEquals(user.calls.length, 0);
  assertEquals(razorpay.orders.length, 0);
});

Deno.test("a probe reports the key id and switches live on, creating nothing", async () => {
  const { handler, service, razorpay } = setup();
  const res = await handler(post({ probe: true }));
  assertEquals(await res.json(), { configured: true, key_id: "rzp_test_fixture" });
  assertEquals(service.live, true);
  assertEquals(service.liveKeyId, "rzp_test_fixture");
  assertEquals(razorpay.orders.length, 0);
});

Deno.test("a probe without keys reports configured:false", async () => {
  const { handler } = setup(null);
  assertEquals(await (await handler(post({ probe: true }))).json(), { configured: false });
});

Deno.test("a paying request needs a bearer token", async () => {
  const { handler, razorpay } = setup();
  const res = await handler(post(request, {}));
  assertEquals(res.status, 401);
  assertEquals((await res.json()).error, "unauthorized");
  assertEquals(razorpay.orders.length, 0);
});

Deno.test("bad bodies are 400 and touch nothing", async () => {
  const { handler, service } = setup();
  for (
    const body of [
      "not json",
      [],
      { ...request, purpose: "tip" },
      { ...request, amount: -1 },
      { ...request, amount: "5000" },
      { ...request, reservation_id: "r1" },
    ]
  ) {
    const res = await handler(post(body));
    assertEquals(res.status, 400, JSON.stringify(body));
    assertEquals((await res.json()).error, "bad_request");
  }
  assertEquals(service.live, null);
});

Deno.test("an order is quoted as the guest, created at the quoted paise and recorded", async () => {
  const { handler, service, user, razorpay, authorizations } = setup();

  const res = await handler(post(request));

  assertEquals(res.status, 200);
  assertEquals(authorizations, ["Bearer user-jwt"]);
  assertEquals(user.calls, [{ reservationId, kind: "advance", amount: 5000 }]);
  assertEquals(razorpay.orders, [{
    amountPaise: 500000,
    currency: "INR",
    receipt: reservationId,
    notes: { reservation_id: reservationId, property_id: "a6100000-0000-4000-8000-000000000001", kind: "advance" },
  }]);
  assertEquals(service.opened, [{
    reservationId,
    customerId: "a6000000-0000-0000-0000-000000000004",
    kind: "advance",
    amount: 5000,
    razorpayOrderId: "order_P6test0001",
  }]);
  assertEquals(await res.json(), {
    configured: true,
    key_id: "rzp_test_fixture",
    order_id: "order_P6test0001",
    amount: 500000,
    currency: "INR",
    name: "Online A",
    description: "Online A: booking advance",
    reservation_id: reservationId,
    prefill: { name: "Gita Guest", email: "p6-gita@example.com", contact: "+919800000001" },
  });
});

Deno.test("a refused quote is a 409 with the Postgres code, and no order is made", async () => {
  const { handler, user, razorpay } = setup();
  user.error = new DbError("P0009", "payment amount 1 is outside the accepted range 5000 to 10000");
  const res = await handler(post(request));
  assertEquals(res.status, 409);
  assertEquals(await res.json(), {
    error: "db",
    code: "P0009",
    message: "payment amount 1 is outside the accepted range 5000 to 10000",
  });
  assertEquals(razorpay.orders.length, 0);
});

Deno.test("a Razorpay failure is a 502 and nothing is recorded", async () => {
  const { handler, service, razorpay } = setup();
  razorpay.orderError = new Error("boom");
  const res = await handler(post(request));
  assertEquals(res.status, 502);
  assertEquals((await res.json()).error, "gateway");
  assertEquals(service.opened.length, 0);
});

Deno.test("a refused open is a 409", async () => {
  const { handler, service } = setup();
  service.openError = new DbError("P0008", "only the booking's guest can pay online");
  const res = await handler(post(request));
  assertEquals(res.status, 409);
  assertEquals((await res.json()).code, "P0008");
});

Deno.test("anything unexpected is a 500 with our own error body", async () => {
  const { handler, user } = setup();
  user.error = new TypeError("kaboom");
  const res = await handler(post(request));
  assertEquals(res.status, 500);
  assertEquals((await res.json()).error, "internal");
});
```

- [ ] **Step 2: Run them to verify they fail**

Run: `deno test supabase/functions/payments-create-order/`
Expected: FAIL with `Module not found "…/payments-create-order/handler.ts"`.

- [ ] **Step 3: Write the handler**

Create `supabase/functions/payments-create-order/handler.ts`:

```ts
// payments-create-order: checks the amount as the signed-in guest,
// creates the Razorpay order and records it. See the spec's "Edge
// Functions" section. index.ts wires the real dependencies.
import { fail, json, preflight } from "../_shared/http.ts";
import {
  type CreateOrderResponse,
  DbError,
  type PaymentKind,
  type ProbeResponse,
  type RazorpayApi,
  type RazorpayConfig,
  type RazorpayOrderCreated,
  type ServicePaymentsDb,
  type UserPaymentsDb,
} from "../_shared/payments_types.ts";

export interface CreateOrderDeps {
  /** Read on every request, so `supabase secrets set` takes effect without a redeploy. */
  config(): RazorpayConfig | null;
  service: ServicePaymentsDb;
  userDb(authorization: string): UserPaymentsDb;
  razorpay(config: RazorpayConfig): RazorpayApi;
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export type ParsedCreateOrder =
  | { probe: true }
  | { probe: false; reservationId: string; amount: number; kind: PaymentKind };

/** A message for the 400 answer, or the parsed request. */
export function parseCreateOrder(body: unknown): ParsedCreateOrder | string {
  if (typeof body !== "object" || body === null || Array.isArray(body)) {
    return "Body must be a JSON object.";
  }
  const b = body as Record<string, unknown>;
  if (b.probe === true) return { probe: true };
  if (typeof b.reservation_id !== "string" || !UUID.test(b.reservation_id)) {
    return "reservation_id must be a uuid.";
  }
  if (typeof b.amount !== "number" || !Number.isFinite(b.amount) || b.amount <= 0) {
    return "amount must be a positive number of rupees.";
  }
  if (b.purpose !== "advance" && b.purpose !== "balance") {
    return "purpose must be advance or balance.";
  }
  return { probe: false, reservationId: b.reservation_id, amount: b.amount, kind: b.purpose };
}

export function createOrderHandler(deps: CreateOrderDeps): (req: Request) => Promise<Response> {
  return async (req) => {
    if (req.method === "OPTIONS") return preflight();
    if (req.method !== "POST") return fail(405, "bad_request", "Use POST.");
    try {
      let body: unknown;
      try {
        body = await req.json();
      } catch {
        return fail(400, "bad_request", "Body must be JSON.");
      }
      const parsed = parseCreateOrder(body);
      if (typeof parsed === "string") return fail(400, "bad_request", parsed);

      // Keep the database's live switch in step with the secrets (spec
      // decision 5): on while the keys are set, off once they are removed.
      const config = deps.config();
      await deps.service.setLive(config !== null, config?.keyId ?? null);

      if (parsed.probe) {
        const probe: ProbeResponse = config ? { configured: true, key_id: config.keyId } : { configured: false };
        return json(200, probe);
      }
      if (!config) return json(200, { configured: false } satisfies CreateOrderResponse);

      const authorization = req.headers.get("Authorization") ?? "";
      if (!authorization.startsWith("Bearer ")) return fail(401, "unauthorized", "Sign in to pay.");

      // As the guest: their booking, the right status, an accepted amount.
      const quote = await deps.userDb(authorization).quoteOrder({
        reservationId: parsed.reservationId,
        kind: parsed.kind,
        amount: parsed.amount,
      });

      let order: RazorpayOrderCreated;
      try {
        order = await deps.razorpay(config).createOrder({
          amountPaise: quote.amount_paise,
          currency: "INR",
          receipt: quote.receipt,
          notes: { reservation_id: quote.reservation_id, property_id: quote.property_id, kind: quote.kind },
        });
      } catch (e) {
        console.error("payments-create-order: Razorpay order failed", e);
        return fail(502, "gateway", "The payment provider did not respond. Try again.");
      }

      await deps.service.openOrder({
        reservationId: quote.reservation_id,
        customerId: quote.customer_id,
        kind: quote.kind,
        amount: quote.amount,
        razorpayOrderId: order.id,
      });

      const response: CreateOrderResponse = {
        configured: true,
        key_id: config.keyId,
        order_id: order.id,
        amount: order.amount,
        currency: "INR",
        name: quote.property_name,
        description: quote.description,
        reservation_id: quote.reservation_id,
        prefill: quote.prefill,
      };
      return json(200, response);
    } catch (e) {
      if (e instanceof DbError) return fail(409, "db", e.message, e.code);
      console.error("payments-create-order", e);
      return fail(500, "internal", "Something went wrong. Try again.");
    }
  };
}
```

- [ ] **Step 4: Run them to verify they pass**

Run: `deno test supabase/functions/payments-create-order/`
Expected: PASS, 12 tests. The `console.error` lines printed by the 502 and 500 cases are expected.

- [ ] **Step 5: Wire the real dependencies**

Create `supabase/functions/_shared/payments_db_supabase.ts`:

```ts
// The real database adapters, over supabase-js. Imported only by the
// functions' index.ts, never by a test, so `deno test` needs neither
// supabase-js nor a database. Verified end to end in the integration task.
import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import {
  DbError,
  type OrderQuote,
  type ServicePaymentsDb,
  type SettleResult,
  type UserPaymentsDb,
} from "./payments_types.ts";

function env(name: string): string {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`${name} is not set`);
  return value;
}

async function rpc<T>(client: SupabaseClient, fn: string, args: Record<string, unknown>): Promise<T> {
  const { data, error } = await client.rpc(fn, args);
  if (error) throw new DbError(error.code ?? "unknown", error.message);
  return data as T;
}

/** Runs as the caller: their Authorization header is forwarded. */
export function userDb(authorization: string): UserPaymentsDb {
  const client = createClient(env("SUPABASE_URL"), env("SUPABASE_ANON_KEY"), {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  return {
    quoteOrder: ({ reservationId, kind, amount }) =>
      rpc<OrderQuote>(client, "payment_order_quote", {
        p_reservation: reservationId,
        p_kind: kind,
        p_amount: amount,
      }),
  };
}

/** Runs with the service role; created on first use. */
export function serviceDb(): ServicePaymentsDb {
  let client: SupabaseClient | null = null;
  const db = () =>
    client ??= createClient(env("SUPABASE_URL"), env("SUPABASE_SERVICE_ROLE_KEY"), {
      auth: { persistSession: false, autoRefreshToken: false },
    });
  return {
    async setLive(live, keyId) {
      await rpc(db(), "payments_set_live", { p_live: live, p_key_id: keyId });
    },
    async openOrder({ reservationId, customerId, kind, amount, razorpayOrderId }) {
      await rpc(db(), "payment_order_open", {
        p_reservation: reservationId,
        p_customer: customerId,
        p_kind: kind,
        p_amount: amount,
        p_razorpay_order_id: razorpayOrderId,
      });
    },
    async settleOrder(razorpayOrderId, razorpayPaymentId) {
      try {
        return await rpc<SettleResult>(db(), "payment_order_settle", {
          p_razorpay_order_id: razorpayOrderId,
          p_razorpay_payment_id: razorpayPaymentId,
        });
      } catch (e) {
        if (e instanceof DbError && e.code === "P0002") return null;
        throw e;
      }
    },
    async failOrder(razorpayOrderId, reason) {
      await rpc(db(), "payment_order_failed", { p_razorpay_order_id: razorpayOrderId, p_reason: reason });
    },
    async recordRefund(razorpayPaymentId, refundId, amount) {
      await rpc(db(), "payment_order_refunded", {
        p_razorpay_payment_id: razorpayPaymentId,
        p_refund_id: refundId,
        p_amount: amount,
      });
    },
    beginWebhook: (eventId, event, payload) =>
      rpc<boolean>(db(), "payment_webhook_begin", { p_event_id: eventId, p_event: event, p_payload: payload }),
    async finishWebhook(eventId, outcome) {
      await rpc(db(), "payment_webhook_done", { p_event_id: eventId, p_outcome: outcome });
    },
  };
}
```

Create `supabase/functions/payments-create-order/deno.json`:

```json
{
  "imports": {
    "@supabase/supabase-js": "jsr:@supabase/supabase-js@2"
  }
}
```

Create `supabase/functions/payments-create-order/index.ts`:

```ts
// payments-create-order. Logic and tests: handler.ts / handler_test.ts.
import { createOrderHandler } from "./handler.ts";
import { RazorpayClient, readConfig } from "../_shared/razorpay.ts";
import { serviceDb, userDb } from "../_shared/payments_db_supabase.ts";

Deno.serve(createOrderHandler({
  config: () => readConfig((name) => Deno.env.get(name)),
  service: serviceDb(),
  userDb,
  razorpay: (config) => new RazorpayClient(config),
}));
```

Append to `.gitignore`:

```
# Deno lockfiles the Supabase CLI or deno writes next to a function
supabase/functions/**/deno.lock
```

Run: `deno check --no-lock --config supabase/functions/payments-create-order/deno.json supabase/functions/payments-create-order/index.ts && make functions-test`
Expected: it type-checks (supabase-js is downloaded from jsr the first time), and every Deno test passes.

- [ ] **Step 6: Commit**

```bash
git add supabase/functions/payments-create-order supabase/functions/_shared/payments_db_supabase.ts .gitignore
git commit -m "$(cat <<'EOF'
feat(payments): payments-create-order Edge Function

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 7: `payments-verify`

**Track:** Track (Deno). Depends on Task 6.

**Files:**
- Create: `supabase/functions/_shared/settlement.ts`
- Create: `supabase/functions/payments-verify/handler.ts`, `index.ts` and `deno.json`
- Test: `supabase/functions/_shared/settlement_test.ts`, `supabase/functions/payments-verify/handler_test.ts`

**Interfaces:**
- Consumes: `verifyPaymentSignature`, `RazorpayClient`, `readConfig`, `serviceDb()`, `http.ts` and `testing.ts`.
- Produces:
  - `refundIfNeeded(settled: SettleResult, razorpay: RazorpayApi, service: ServicePaymentsDb): Promise<"initiated" | "failed" | null>`, which Task 8 uses too.
  - `verifyHandler(deps: VerifyDeps)`, with `interface VerifyDeps { config(): RazorpayConfig | null; service: ServicePaymentsDb; razorpay(config: RazorpayConfig): RazorpayApi }`.
  - `parseVerify(body)`.

- [ ] **Step 1: Write the failing tests**

Create `supabase/functions/_shared/settlement_test.ts`:

```ts
import { assertEquals } from "jsr:@std/assert@1";
import { refundIfNeeded } from "./settlement.ts";
import { FakeRazorpay, FakeServiceDb, settleResult } from "./testing.ts";

Deno.test("a paid order needs no refund", async () => {
  const razorpay = new FakeRazorpay();
  const service = new FakeServiceDb();
  assertEquals(await refundIfNeeded(settleResult(), razorpay, service), null);
  assertEquals(razorpay.refunds.length, 0);
});

Deno.test("an unapplied order is refunded in full and the refund recorded in rupees", async () => {
  const razorpay = new FakeRazorpay();
  const service = new FakeServiceDb();
  const state = await refundIfNeeded(
    settleResult({ status: "unapplied", refund_needed: true, reason: "reservation is cancelled" }),
    razorpay,
    service,
  );
  assertEquals(state, "initiated");
  assertEquals(razorpay.refunds, [[
    "pay_P6test0001",
    { notes: { reason: "unapplied", reservation_id: "a6100000-0000-4000-8000-000000000031" } },
  ]]);
  assertEquals(service.refunds, [["pay_P6test0001", "rfnd_P6test0001", 5000]]);
});

Deno.test("a refund Razorpay refuses is reported and not recorded", async () => {
  const razorpay = new FakeRazorpay();
  razorpay.refundError = new Error("payment not captured yet");
  const service = new FakeServiceDb();
  const state = await refundIfNeeded(settleResult({ status: "unapplied", refund_needed: true }), razorpay, service);
  assertEquals(state, "failed");
  assertEquals(service.refunds.length, 0);
});
```

Create `supabase/functions/payments-verify/handler_test.ts`:

```ts
import { assertEquals } from "jsr:@std/assert@1";
import { verifyHandler } from "./handler.ts";
import { DbError, type RazorpayConfig } from "../_shared/payments_types.ts";
import {
  FakeRazorpay,
  FakeServiceDb,
  fixtureConfig,
  fixtureSignature,
  post,
  reservationId,
  settleResult,
} from "../_shared/testing.ts";

function setup(config: RazorpayConfig | null = fixtureConfig) {
  const service = new FakeServiceDb();
  const razorpay = new FakeRazorpay();
  const handler = verifyHandler({ config: () => config, service, razorpay: () => razorpay });
  return { handler, service, razorpay };
}

const good = {
  razorpay_order_id: "order_P6test0001",
  razorpay_payment_id: "pay_P6test0001",
  razorpay_signature: fixtureSignature,
};

Deno.test("without keys it answers configured:false and settles nothing", async () => {
  const { handler, service } = setup(null);
  const res = await handler(post(good));
  assertEquals(await res.json(), { configured: false });
  assertEquals(service.settles.length, 0);
});

Deno.test("verifying needs a bearer token", async () => {
  const { handler } = setup();
  assertEquals((await handler(post(good, {}))).status, 401);
});

Deno.test("a missing field is 400", async () => {
  const { handler } = setup();
  const res = await handler(post({ ...good, razorpay_signature: "" }));
  assertEquals(res.status, 400);
  assertEquals((await res.json()).error, "bad_request");
});

Deno.test("a wrong signature is refused and nothing is settled", async () => {
  const { handler, service } = setup();
  const res = await handler(post({ ...good, razorpay_payment_id: "pay_forged" }));
  assertEquals(res.status, 400);
  assertEquals((await res.json()).error, "invalid_signature");
  assertEquals(service.settles.length, 0);
});

Deno.test("a good signature settles the order and answers paid", async () => {
  const { handler, service, razorpay } = setup();
  const res = await handler(post(good));
  assertEquals(res.status, 200);
  assertEquals(service.settles, [["order_P6test0001", "pay_P6test0001"]]);
  assertEquals(await res.json(), {
    configured: true,
    outcome: "paid",
    reservation_id: reservationId,
    kind: "advance",
    refund: null,
  });
  assertEquals(razorpay.refunds.length, 0);
});

Deno.test("verifying twice answers paid twice (the database settles once)", async () => {
  const { handler, service } = setup();
  assertEquals((await (await handler(post(good))).json()).outcome, "paid");
  assertEquals((await (await handler(post(good))).json()).outcome, "paid");
  assertEquals(service.settles.length, 2);
});

Deno.test("an unapplied payment is refunded and reported", async () => {
  const { handler, service, razorpay } = setup();
  service.settleResult = settleResult({ status: "unapplied", refund_needed: true, reason: "reservation is cancelled" });
  const body = await (await handler(post(good))).json();
  assertEquals(body.outcome, "unapplied");
  assertEquals(body.refund, "initiated");
  assertEquals(razorpay.refunds.length, 1);
  assertEquals(service.refunds, [["pay_P6test0001", "rfnd_P6test0001", 5000]]);
});

Deno.test("a refund that fails is reported as failed", async () => {
  const { handler, service, razorpay } = setup();
  service.settleResult = settleResult({ status: "unapplied", refund_needed: true });
  razorpay.refundError = new Error("not captured yet");
  assertEquals((await (await handler(post(good))).json()).refund, "failed");
});

Deno.test("an already refunded order is unapplied with nothing more to refund", async () => {
  const { handler, service, razorpay } = setup();
  service.settleResult = settleResult({ status: "refunded", refund_needed: false });
  const body = await (await handler(post(good))).json();
  assertEquals(body.outcome, "unapplied");
  assertEquals(body.refund, null);
  assertEquals(razorpay.refunds.length, 0);
});

Deno.test("an unknown order is a 409 P0002", async () => {
  const { handler, service } = setup();
  service.settleResult = null;
  const res = await handler(post(good));
  assertEquals(res.status, 409);
  assertEquals(await res.json(), { error: "db", code: "P0002", message: "payment_order_not_found" });
});

Deno.test("a database error is a 409 with its code", async () => {
  const { handler, service } = setup();
  service.settleError = new DbError("P0009", "a Razorpay payment id is required");
  const res = await handler(post(good));
  assertEquals(res.status, 409);
  assertEquals((await res.json()).code, "P0009");
});
```

- [ ] **Step 2: Run them to verify they fail**

Run: `deno test supabase/functions/_shared/settlement_test.ts supabase/functions/payments-verify/`
Expected: FAIL with `Module not found` for `settlement.ts` and `payments-verify/handler.ts`.

- [ ] **Step 3: Write the refund helper and the handler**

Create `supabase/functions/_shared/settlement.ts`:

```ts
// What payments-verify and payments-webhook both do after settling.
import type { RazorpayApi, ServicePaymentsDb, SettleResult } from "./payments_types.ts";

export type RefundState = "initiated" | "failed" | null;

/**
 * Refunds an unapplied payment in full (spec decision 10). Returns null
 * when no refund is due. A failed refund is logged and left for the next
 * settle call: payment_order_settle keeps `refund_needed` true until a
 * refund is recorded.
 */
export async function refundIfNeeded(
  settled: SettleResult,
  razorpay: RazorpayApi,
  service: ServicePaymentsDb,
): Promise<RefundState> {
  if (!settled.refund_needed) return null;
  try {
    const refund = await razorpay.refundPayment(settled.razorpay_payment_id, {
      notes: { reason: "unapplied", reservation_id: settled.reservation_id },
    });
    await service.recordRefund(settled.razorpay_payment_id, refund.id, refund.amount / 100);
    return "initiated";
  } catch (e) {
    console.error("refund failed", settled.razorpay_payment_id, e);
    return "failed";
  }
}
```

Create `supabase/functions/payments-verify/handler.ts`:

```ts
// payments-verify: checks Razorpay Checkout's signature and settles the
// payment in the database (spec decision 6).
import { fail, json, preflight } from "../_shared/http.ts";
import {
  DbError,
  type RazorpayApi,
  type RazorpayConfig,
  type ServicePaymentsDb,
  type VerifyResponse,
} from "../_shared/payments_types.ts";
import { verifyPaymentSignature } from "../_shared/razorpay.ts";
import { refundIfNeeded } from "../_shared/settlement.ts";

export interface VerifyDeps {
  config(): RazorpayConfig | null;
  service: ServicePaymentsDb;
  razorpay(config: RazorpayConfig): RazorpayApi;
}

export type ParsedVerify = { orderId: string; paymentId: string; signature: string };

export function parseVerify(body: unknown): ParsedVerify | string {
  if (typeof body !== "object" || body === null || Array.isArray(body)) {
    return "Body must be a JSON object.";
  }
  const b = body as Record<string, unknown>;
  const values: string[] = [];
  for (const field of ["razorpay_order_id", "razorpay_payment_id", "razorpay_signature"]) {
    const value = b[field];
    if (typeof value !== "string" || value.trim() === "" || value.length > 200) {
      return `${field} is required.`;
    }
    values.push(value.trim());
  }
  return { orderId: values[0], paymentId: values[1], signature: values[2] };
}

export function verifyHandler(deps: VerifyDeps): (req: Request) => Promise<Response> {
  return async (req) => {
    if (req.method === "OPTIONS") return preflight();
    if (req.method !== "POST") return fail(405, "bad_request", "Use POST.");
    try {
      const authorization = req.headers.get("Authorization") ?? "";
      if (!authorization.startsWith("Bearer ")) return fail(401, "unauthorized", "Sign in to pay.");

      let body: unknown;
      try {
        body = await req.json();
      } catch {
        return fail(400, "bad_request", "Body must be JSON.");
      }
      const parsed = parseVerify(body);
      if (typeof parsed === "string") return fail(400, "bad_request", parsed);

      const config = deps.config();
      if (!config) return json(200, { configured: false } satisfies VerifyResponse);

      const valid = await verifyPaymentSignature(
        parsed.orderId,
        parsed.paymentId,
        parsed.signature,
        config.keySecret,
      );
      if (!valid) return fail(400, "invalid_signature", "The payment could not be verified.");

      const settled = await deps.service.settleOrder(parsed.orderId, parsed.paymentId);
      if (!settled) return fail(409, "db", "payment_order_not_found", "P0002");

      const refund = await refundIfNeeded(settled, deps.razorpay(config), deps.service);
      const response: VerifyResponse = {
        configured: true,
        outcome: settled.status === "paid" ? "paid" : "unapplied",
        reservation_id: settled.reservation_id,
        kind: settled.kind,
        refund,
      };
      return json(200, response);
    } catch (e) {
      if (e instanceof DbError) return fail(409, "db", e.message, e.code);
      console.error("payments-verify", e);
      return fail(500, "internal", "Something went wrong. Try again.");
    }
  };
}
```

Create `supabase/functions/payments-verify/deno.json` (the same as create-order's):

```json
{
  "imports": {
    "@supabase/supabase-js": "jsr:@supabase/supabase-js@2"
  }
}
```

Create `supabase/functions/payments-verify/index.ts`:

```ts
// payments-verify. Logic and tests: handler.ts / handler_test.ts.
import { verifyHandler } from "./handler.ts";
import { RazorpayClient, readConfig } from "../_shared/razorpay.ts";
import { serviceDb } from "../_shared/payments_db_supabase.ts";

Deno.serve(verifyHandler({
  config: () => readConfig((name) => Deno.env.get(name)),
  service: serviceDb(),
  razorpay: (config) => new RazorpayClient(config),
}));
```

- [ ] **Step 4: Run them to verify they pass**

Run: `make functions-test && deno check --no-lock --config supabase/functions/payments-verify/deno.json supabase/functions/payments-verify/index.ts`
Expected: PASS, with 3 settlement tests and 11 verify tests added. It type-checks.

- [ ] **Step 5: Commit**

```bash
git add supabase/functions/_shared/settlement.ts supabase/functions/_shared/settlement_test.ts supabase/functions/payments-verify
git commit -m "$(cat <<'EOF'
feat(payments): payments-verify Edge Function with automatic refunds

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 8: `payments-webhook`

**Track:** Track (Deno). Depends on Task 7.

**Files:**
- Create: `supabase/functions/payments-webhook/handler.ts`, `index.ts` and `deno.json`
- Modify: `supabase/config.toml`
- Test: `supabase/functions/payments-webhook/handler_test.ts`

**Interfaces:**
- Consumes: `verifyWebhookSignature`, `sha256Hex`, `refundIfNeeded`, `serviceDb()`, `http.ts` and `testing.ts`.
- Produces:
  - `webhookHandler(deps: WebhookDeps)`, with `interface WebhookDeps { config(): RazorpayConfig | null; service: ServicePaymentsDb; razorpay(config: RazorpayConfig): RazorpayApi }`.
  - `handleEvent(event, config, deps): Promise<string>`, which returns the outcome stored in `payment_webhook_events.outcome`.
  - `verify_jwt = false` for this one function.

- [ ] **Step 1: Write the failing tests**

Create `supabase/functions/payments-webhook/handler_test.ts`:

```ts
import { assertEquals } from "jsr:@std/assert@1";
import { webhookHandler } from "./handler.ts";
import { DbError, type RazorpayConfig } from "../_shared/payments_types.ts";
import { sha256Hex } from "../_shared/razorpay.ts";
import {
  capturedEvent,
  failedEvent,
  FakeRazorpay,
  FakeServiceDb,
  fixtureConfig,
  refundEvent,
  settleResult,
  signedWebhook,
} from "../_shared/testing.ts";

function setup(config: RazorpayConfig | null = fixtureConfig) {
  const service = new FakeServiceDb();
  const razorpay = new FakeRazorpay();
  const handler = webhookHandler({ config: () => config, service, razorpay: () => razorpay });
  return { handler, service, razorpay };
}

Deno.test("without the keys or the webhook secret it is 503", async () => {
  assertEquals((await setup(null).handler(await signedWebhook(capturedEvent(), "evt_1"))).status, 503);
  const noSecret = setup({ ...fixtureConfig, webhookSecret: null });
  assertEquals((await noSecret.handler(await signedWebhook(capturedEvent(), "evt_1"))).status, 503);
});

Deno.test("a bad signature is 401 and nothing is recorded", async () => {
  const { handler, service } = setup();
  const req = new Request("http://localhost/fn", {
    method: "POST",
    headers: { "X-Razorpay-Signature": "00", "X-Razorpay-Event-Id": "evt_1" },
    body: JSON.stringify(capturedEvent()),
  });
  assertEquals((await handler(req)).status, 401);
  assertEquals(service.events.size, 0);
  assertEquals(service.settles.length, 0);
});

Deno.test("payment.captured settles an order no verify call has seen", async () => {
  const { handler, service } = setup();
  const res = await handler(await signedWebhook(capturedEvent(), "evt_1"));
  assertEquals(res.status, 200);
  assertEquals(await res.json(), { status: "processed", outcome: "settled:paid" });
  assertEquals(service.settles, [["order_P6test0001", "pay_P6test0001"]]);
  assertEquals(service.events.get("evt_1")?.outcome, "settled:paid");
});

Deno.test("the same event delivered again is a duplicate and settles nothing more", async () => {
  const { handler, service } = setup();
  await handler(await signedWebhook(capturedEvent(), "evt_1"));
  const res = await handler(await signedWebhook(capturedEvent(), "evt_1"));
  assertEquals(await res.json(), { status: "duplicate" });
  assertEquals(service.settles.length, 1);
});

Deno.test("a captured payment for an order that is not ours is ignored with 200", async () => {
  const { handler, service } = setup();
  service.settleResult = null;
  const res = await handler(await signedWebhook(capturedEvent("order_subscription"), "evt_2"));
  assertEquals(res.status, 200);
  assertEquals((await res.json()).outcome, "ignored:unknown_order");
});

Deno.test("an unapplied captured payment is refunded", async () => {
  const { handler, service, razorpay } = setup();
  service.settleResult = settleResult({ status: "unapplied", refund_needed: true });
  const body = await (await handler(await signedWebhook(capturedEvent(), "evt_3"))).json();
  assertEquals(body.outcome, "settled:unapplied:refund_initiated");
  assertEquals(razorpay.refunds.length, 1);
  assertEquals(service.refunds, [["pay_P6test0001", "rfnd_P6test0001", 5000]]);
});

Deno.test("payment.failed marks the order failed with Razorpay's reason", async () => {
  const { handler, service } = setup();
  const body = await (await handler(await signedWebhook(failedEvent(), "evt_4"))).json();
  assertEquals(body.outcome, "failed");
  assertEquals(service.failed, [["order_P6test0001", "Card declined by bank"]]);
});

Deno.test("refund.processed records the refund in rupees", async () => {
  const { handler, service } = setup();
  const body = await (await handler(await signedWebhook(refundEvent(), "evt_5"))).json();
  assertEquals(body.outcome, "refund_recorded");
  assertEquals(service.refunds, [["pay_P6test0001", "rfnd_P6test0002", 1000]]);
});

Deno.test("other events are acknowledged and ignored", async () => {
  const { handler, service } = setup();
  const body = await (await handler(await signedWebhook({ event: "order.paid", payload: {} }, "evt_6"))).json();
  assertEquals(body.outcome, "ignored:order.paid");
  assertEquals(service.settles.length, 0);
});

Deno.test("without X-Razorpay-Event-Id the event is keyed by the body's SHA-256", async () => {
  const { handler, service } = setup();
  const event = capturedEvent();
  await handler(await signedWebhook(event));
  assertEquals([...service.events.keys()], [`sha256:${await sha256Hex(JSON.stringify(event))}`]);
});

Deno.test("a database failure is 500 and leaves the event unfinished for the retry", async () => {
  const { handler, service } = setup();
  service.settleError = new DbError("08006", "connection failure");
  const res = await handler(await signedWebhook(capturedEvent(), "evt_7"));
  assertEquals(res.status, 500);
  assertEquals(service.events.get("evt_7")?.processed, false);
});
```

- [ ] **Step 2: Run them to verify they fail**

Run: `deno test supabase/functions/payments-webhook/`
Expected: FAIL with `Module not found "…/payments-webhook/handler.ts"`.

- [ ] **Step 3: Write the handler and wire it**

Create `supabase/functions/payments-webhook/handler.ts`:

```ts
// payments-webhook: Razorpay's server-to-server events. Settles captured
// payments the app never verified (the guest closed the tab), records
// failures and refunds. Each event is processed once (spec decision 12).
import { fail, json, preflight } from "../_shared/http.ts";
import type { RazorpayApi, RazorpayConfig, ServicePaymentsDb } from "../_shared/payments_types.ts";
import { sha256Hex, verifyWebhookSignature } from "../_shared/razorpay.ts";
import { refundIfNeeded } from "../_shared/settlement.ts";

export interface WebhookDeps {
  config(): RazorpayConfig | null;
  service: ServicePaymentsDb;
  razorpay(config: RazorpayConfig): RazorpayApi;
}

type Json = Record<string, unknown>;

function isObject(value: unknown): value is Json {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

/** payload.<kind>.entity, when present. */
function entity(event: Json, kind: "payment" | "refund"): Json | null {
  const payload = event.payload;
  if (!isObject(payload)) return null;
  const wrapper = payload[kind];
  if (!isObject(wrapper)) return null;
  return isObject(wrapper.entity) ? wrapper.entity : null;
}

/** Handles one verified event; returns the outcome stored in the ledger. */
export async function handleEvent(event: Json, config: RazorpayConfig, deps: WebhookDeps): Promise<string> {
  const name = typeof event.event === "string" ? event.event : "unknown";
  switch (name) {
    case "payment.captured": {
      const payment = entity(event, "payment");
      if (!payment || typeof payment.id !== "string" || typeof payment.order_id !== "string") {
        return "ignored:no_order";
      }
      const settled = await deps.service.settleOrder(payment.order_id, payment.id);
      // Not one of our orders (e.g. a P8 subscription charge).
      if (!settled) return "ignored:unknown_order";
      const refund = await refundIfNeeded(settled, deps.razorpay(config), deps.service);
      return `settled:${settled.status}${refund ? `:refund_${refund}` : ""}`;
    }
    case "payment.failed": {
      const payment = entity(event, "payment");
      if (!payment || typeof payment.order_id !== "string") return "ignored:no_order";
      const reason = typeof payment.error_description === "string" ? payment.error_description : "payment failed";
      await deps.service.failOrder(payment.order_id, reason);
      return "failed";
    }
    case "refund.processed": {
      const refund = entity(event, "refund");
      if (
        !refund || typeof refund.id !== "string" || typeof refund.payment_id !== "string" ||
        typeof refund.amount !== "number"
      ) {
        return "ignored:no_refund";
      }
      await deps.service.recordRefund(refund.payment_id, refund.id, refund.amount / 100);
      return "refund_recorded";
    }
    default:
      return `ignored:${name}`;
  }
}

export function webhookHandler(deps: WebhookDeps): (req: Request) => Promise<Response> {
  return async (req) => {
    if (req.method === "OPTIONS") return preflight();
    if (req.method !== "POST") return fail(405, "bad_request", "Use POST.");

    const config = deps.config();
    if (!config || !config.webhookSecret) {
      return fail(503, "not_configured", "Razorpay webhooks are not configured.");
    }

    try {
      const raw = await req.text();
      const signature = req.headers.get("X-Razorpay-Signature") ?? "";
      if (!(await verifyWebhookSignature(raw, signature, config.webhookSecret))) {
        return fail(401, "invalid_signature", "Bad signature.");
      }

      let event: Json;
      try {
        const parsed: unknown = JSON.parse(raw);
        if (!isObject(parsed)) return fail(400, "bad_request", "Body must be a JSON object.");
        event = parsed;
      } catch {
        return fail(400, "bad_request", "Body must be JSON.");
      }

      const eventId = req.headers.get("X-Razorpay-Event-Id")?.trim() || `sha256:${await sha256Hex(raw)}`;
      const name = typeof event.event === "string" ? event.event : "unknown";
      if (!(await deps.service.beginWebhook(eventId, name, event))) {
        return json(200, { status: "duplicate" });
      }

      const outcome = await handleEvent(event, config, deps);
      // Only after it was handled: a crash above leaves the event
      // unfinished, and Razorpay's retry processes it again.
      await deps.service.finishWebhook(eventId, outcome);
      return json(200, { status: "processed", outcome });
    } catch (e) {
      console.error("payments-webhook", e);
      return fail(500, "internal", "Processing failed; Razorpay will retry.");
    }
  };
}
```

Create `supabase/functions/payments-webhook/deno.json`:

```json
{
  "imports": {
    "@supabase/supabase-js": "jsr:@supabase/supabase-js@2"
  }
}
```

Create `supabase/functions/payments-webhook/index.ts`:

```ts
// payments-webhook (verify_jwt = false: Razorpay signs, it sends no JWT).
// Logic and tests: handler.ts / handler_test.ts.
import { webhookHandler } from "./handler.ts";
import { RazorpayClient, readConfig } from "../_shared/razorpay.ts";
import { serviceDb } from "../_shared/payments_db_supabase.ts";

Deno.serve(webhookHandler({
  config: () => readConfig((name) => Deno.env.get(name)),
  service: serviceDb(),
  razorpay: (config) => new RazorpayClient(config),
}));
```

Append to `supabase/config.toml`. Razorpay authenticates with its signature, not a Supabase JWT; the other two functions keep the default `verify_jwt = true`:

```toml
# P6: Razorpay signs its webhook calls (X-Razorpay-Signature); it cannot
# send a Supabase JWT. payments-create-order and payments-verify keep
# the default verify_jwt = true.
[functions.payments-webhook]
verify_jwt = false
```

- [ ] **Step 4: Run them to verify they pass**

Run: `make functions-test && deno check --no-lock --config supabase/functions/payments-webhook/deno.json supabase/functions/payments-webhook/index.ts`
Expected: PASS, 49 Deno tests in total (12 + 12 + 3 + 11 + 11). It type-checks.

- [ ] **Step 5: Commit**

```bash
git add supabase/functions/payments-webhook supabase/config.toml
git commit -m "$(cat <<'EOF'
feat(payments): payments-webhook Edge Function (captured, failed, refunds; idempotent)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

## Phase 3: Flutter track (Tasks 9 → 10 → 12; Task 11 alongside)

### Task 9: The payment functions client

**Track:** Track (Flutter). Depends on Task 1.

**Files:**
- Modify: `lib/data/repositories/payment_order_repository.dart` (fill in the Task 1 stubs)
- Modify: `lib/core/errors.dart` (P0036)
- Test: `test/data/payment_order_repository_test.dart`, `test/core/errors_test.dart`

**Interfaces:**
- Consumes: `FunctionResponse` and `FunctionException` (from `package:supabase_flutter`, via `functions_client`), `mapPostgrestError`, and the Task 1 models.
- Produces:
  - Working `PaymentFunctionsSource.createOrder` / `verify`.
  - `const paymentNotConfirmedYetMessage`.
  - `bool isFunctionUnavailable(FunctionException)`.
  - `BookingFailure failureFromFunction(FunctionException)`.
  - `class OnlinePaymentRequired extends BookingFailure`, which P0036 maps to.

- [ ] **Step 1: Write the failing tests**

Create `test/data/payment_order_repository_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:pasala/core/errors.dart';
import 'package:pasala/data/models/payment_order.dart';
import 'package:pasala/data/repositories/payment_order_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

typedef _Call = (String, Map<String, dynamic>);

PaymentFunctionsSource _answering(Object? data, [List<_Call>? calls]) =>
    PaymentFunctionsSource((name, body) async {
      calls?.add((name, body));
      return FunctionResponse(data: data, status: 200);
    });

PaymentFunctionsSource _throwing(Object error) =>
    PaymentFunctionsSource((name, body) async => throw error);

FunctionException _status(int status, [Object? details]) =>
    FunctionException(status: status, details: details);

Future<CreateOrderResult> _create(PaymentFunctionsSource source) =>
    source.createOrder(
        reservationId: 'r1', amount: 5000, purpose: PaymentPurpose.advance);

Future<VerifyResult> _verify(PaymentFunctionsSource source) => source.verify(
    orderId: 'order_1', paymentId: 'pay_1', signature: 'sig');

void main() {
  group('createOrder', () {
    test('posts the reservation, rupees and purpose to payments-create-order',
        () async {
      final calls = <_Call>[];
      await _answering({'configured': false}, calls).createOrder(
          reservationId: 'r2', amount: 3000, purpose: PaymentPurpose.balance);
      expect(calls.single.$1, 'payments-create-order');
      expect(calls.single.$2,
          {'reservation_id': 'r2', 'amount': 3000, 'purpose': 'balance'});
    });

    test('configured:false means pay through the mock', () async {
      expect(await _create(_answering({'configured': false})),
          isA<PaymentsNotConfigured>());
    });

    test('a created order is read', () async {
      final result = await _create(_answering({
        'configured': true,
        'key_id': 'rzp_test_fixture',
        'order_id': 'order_1',
        'amount': 500000,
        'currency': 'INR',
        'name': 'Online A',
        'description': 'Online A: booking advance',
        'reservation_id': 'r1',
        'prefill': {'name': null, 'email': null, 'contact': null},
      }));
      expect((result as RazorpayOrder).orderId, 'order_1');
    });

    test('a function that is not deployed (404) means the mock', () async {
      expect(await _create(_throwing(_status(404, 'Not Found'))),
          isA<PaymentsNotConfigured>());
    });

    test('a 5xx without our error body (booting) means the mock', () async {
      expect(await _create(_throwing(_status(503, {'code': 'BOOT_ERROR'}))),
          isA<PaymentsNotConfigured>());
    });

    test('an unreachable function (network / CORS) means the mock', () async {
      expect(await _create(_throwing(http.ClientException('XMLHttpRequest error.'))),
          isA<PaymentsNotConfigured>());
    });

    test('our own 5xx is an error, not the mock', () async {
      await expectLater(
          _create(_throwing(_status(500, {'error': 'internal', 'message': 'x'}))),
          throwsA(isA<UnknownFailure>()));
    });

    test('a database refusal maps through its Postgres code', () async {
      await expectLater(
          _create(_throwing(_status(409,
              {'error': 'db', 'code': 'P0006', 'message': 'hold expired'}))),
          throwsA(isA<HoldExpired>()));
      await expectLater(
          _create(_throwing(_status(409, {
            'error': 'db',
            'code': 'P0036',
            'message': 'online_payment_required'
          }))),
          throwsA(isA<OnlinePaymentRequired>()));
    });

    test('a Razorpay outage is a readable InvalidState', () async {
      await expectLater(
          _create(_throwing(_status(502, {'error': 'gateway', 'message': 'x'}))),
          throwsA(isA<InvalidState>().having((e) => e.message, 'message',
              'The payment service is not responding. Try again in a minute.')));
    });

    test('401 is NotPermitted', () async {
      await expectLater(
          _create(_throwing(
              _status(401, {'error': 'unauthorized', 'message': 'Sign in'}))),
          throwsA(isA<NotPermitted>()));
    });
  });

  group('verify', () {
    test('posts the three Checkout values to payments-verify', () async {
      final calls = <_Call>[];
      await _answering({
        'configured': true,
        'outcome': 'paid',
        'reservation_id': 'r1',
        'refund': null,
      }, calls)
          .verify(orderId: 'order_1', paymentId: 'pay_1', signature: 'sig');
      expect(calls.single.$1, 'payments-verify');
      expect(calls.single.$2, {
        'razorpay_order_id': 'order_1',
        'razorpay_payment_id': 'pay_1',
        'razorpay_signature': 'sig',
      });
    });

    test('reads paid and unapplied', () async {
      expect(
          (await _verify(_answering({
            'configured': true,
            'outcome': 'paid',
            'reservation_id': 'r1',
          })))
              .outcome,
          VerifyOutcome.paid);
      final unapplied = await _verify(_answering({
        'configured': true,
        'outcome': 'unapplied',
        'reservation_id': 'r1',
        'refund': 'initiated',
      }));
      expect(unapplied.outcome, VerifyOutcome.unapplied);
      expect(unapplied.refund, RefundState.initiated);
    });

    test('a bad signature is a readable InvalidState', () async {
      await expectLater(
          _verify(_throwing(_status(
              400, {'error': 'invalid_signature', 'message': 'x'}))),
          throwsA(isA<InvalidState>()));
    });

    test('a network error after paying says "not confirmed yet", not failed',
        () async {
      await expectLater(
          _verify(_throwing(http.ClientException('XMLHttpRequest error.'))),
          throwsA(isA<InvalidState>().having(
              (e) => e.message, 'message', paymentNotConfirmedYetMessage)));
    });

    test('an unreachable verify function says "not confirmed yet"', () async {
      await expectLater(_verify(_throwing(_status(404))),
          throwsA(isA<InvalidState>().having(
              (e) => e.message, 'message', paymentNotConfirmedYetMessage)));
    });

    test('payments switched off mid-payment says "not confirmed yet"',
        () async {
      await expectLater(_verify(_answering({'configured': false})),
          throwsA(isA<InvalidState>().having(
              (e) => e.message, 'message', paymentNotConfirmedYetMessage)));
    });
  });
}
```

In `test/core/errors_test.dart`, add before the test `'NotPermitted never leaks the server message'`:

```dart
  test('P0036 maps to OnlinePaymentRequired with readable copy', () {
    final failure = map('P0036', 'online_payment_required');
    expect(failure, isA<OnlinePaymentRequired>());
    expect(failure.message,
        'Online payment is not available right now. Please try again in a few minutes.');
  });
```

- [ ] **Step 2: Run them to verify they fail**

Run: `flutter test test/data/payment_order_repository_test.dart test/core/errors_test.dart`
Expected: FAIL to compile: `OnlinePaymentRequired`, `paymentNotConfirmedYetMessage` and `isFunctionUnavailable` are not defined.

- [ ] **Step 3: Map P0036**

In `lib/core/errors.dart`, add this class just before the `/// A 400/422 from Supabase auth` doc comment (the `InvalidCredentials` class):

```dart
/// P0036 -- `confirm_booking`/`checkout_booking` refused a mock payment
/// because online payments are live (0055). Reached only when the app
/// could not reach the payment functions and fell back to the mock.
class OnlinePaymentRequired extends BookingFailure {
  const OnlinePaymentRequired()
      : super('Online payment is not available right now. Please try again '
            'in a few minutes.');
}
```

Then, in `mapPostgrestError`'s `switch (code)`, add after `'P0031' => const AlreadyDispatched(),`:

```dart
    // P0036: online payments (0055). The server sends the bare code
    // `online_payment_required`, so the copy lives here.
    'P0036' => const OnlinePaymentRequired(),
```

- [ ] **Step 4: Implement the functions client**

Replace the whole of `lib/data/repositories/payment_order_repository.dart` with:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors.dart';
import '../../core/supabase_client.dart';
import '../models/payment_order.dart';

/// Calls one Edge Function by name with a JSON body. In the app this is
/// `supabase.functions.invoke`; tests pass a fake.
typedef FunctionInvoker = Future<FunctionResponse> Function(
    String functionName, Map<String, dynamic> body);

/// Shown when the payment may have gone through but the server could not
/// confirm it: the guest must not pay again blindly. The webhook settles
/// it (spec decision 12).
const paymentNotConfirmedYetMessage =
    'Your payment was received but is not confirmed yet. Check your booking '
    'again in a minute before paying again.';

/// The online-payment calls `RazorpayGateway` makes. Tests override
/// [paymentOrderSourceProvider] with `FakePaymentOrderSource`
/// (test/support/fake_payment_order_source.dart).
abstract interface class PaymentOrderSource {
  /// Asks the server to create a Razorpay order for [amount] rupees, or
  /// learns that online payments are not configured.
  Future<CreateOrderResult> createOrder({
    required String reservationId,
    required num amount,
    required PaymentPurpose purpose,
  });

  /// Hands Razorpay Checkout's answer to the server, which checks the
  /// signature and settles the payment.
  Future<VerifyResult> verify({
    required String orderId,
    required String paymentId,
    required String signature,
  });
}

/// Backs [PaymentOrderSource] with the `payments-create-order` and
/// `payments-verify` Edge Functions. Errors arrive as [BookingFailure]s.
class PaymentFunctionsSource implements PaymentOrderSource {
  PaymentFunctionsSource(this.invoke);

  final FunctionInvoker invoke;

  static const createOrderFunction = 'payments-create-order';
  static const verifyFunction = 'payments-verify';

  @override
  Future<CreateOrderResult> createOrder({
    required String reservationId,
    required num amount,
    required PaymentPurpose purpose,
  }) async {
    final FunctionResponse response;
    try {
      response = await invoke(createOrderFunction, {
        'reservation_id': reservationId,
        'amount': amount,
        'purpose': purpose.wire,
      });
    } on FunctionException catch (e) {
      // Not deployed, or not running: pay as before P6 (spec decision 4).
      if (isFunctionUnavailable(e)) return const PaymentsNotConfigured();
      throw failureFromFunction(e);
    } catch (e) {
      final failure = mapPostgrestError(e);
      // Unreachable (offline, or no functions served, so the browser's CORS
      // preflight failed): the mock again. Safe while online payments are
      // live too -- confirm_booking refuses the mock with P0036.
      if (failure is NetworkFailure) return const PaymentsNotConfigured();
      throw failure;
    }
    return CreateOrderResult.fromJson(_object(response.data));
  }

  @override
  Future<VerifyResult> verify({
    required String orderId,
    required String paymentId,
    required String signature,
  }) async {
    final FunctionResponse response;
    try {
      response = await invoke(verifyFunction, {
        'razorpay_order_id': orderId,
        'razorpay_payment_id': paymentId,
        'razorpay_signature': signature,
      });
    } on FunctionException catch (e) {
      if (isFunctionUnavailable(e)) {
        throw const InvalidState(paymentNotConfirmedYetMessage);
      }
      throw failureFromFunction(e);
    } catch (e) {
      // Razorpay may already have the money: never report this as a
      // failed payment (Review Focus 1).
      final failure = mapPostgrestError(e);
      if (failure is NetworkFailure) {
        throw const InvalidState(paymentNotConfirmedYetMessage);
      }
      throw failure;
    }
    final body = _object(response.data);
    if (body['configured'] != true) {
      throw const InvalidState(paymentNotConfirmedYetMessage);
    }
    return VerifyResult.fromJson(body);
  }
}

Map<String, dynamic> _object(Object? data) => switch (data) {
      final Map<dynamic, dynamic> map => map.cast<String, dynamic>(),
      _ => throw const UnknownFailure('Unexpected answer from payments.'),
    };

/// 404 (not deployed), or a 5xx without the function's own `{"error": …}`
/// body (booting, or the gateway in front of it failed).
bool isFunctionUnavailable(FunctionException e) {
  final details = e.details;
  final ours = details is Map && details['error'] is String;
  return e.status == 404 || (e.status >= 500 && !ours);
}

/// The function's own error bodies (supabase/functions/_shared/http.ts).
BookingFailure failureFromFunction(FunctionException e) {
  final details = e.details is Map
      ? (e.details as Map).cast<String, dynamic>()
      : const <String, dynamic>{};
  return switch (details['error']) {
    'db' => mapPostgrestError(PostgrestException(
        message: details['message'] as String? ?? '',
        code: details['code'] as String?,
      )),
    'unauthorized' => const NotPermitted(),
    'invalid_signature' => const InvalidState(
        'We could not verify this payment. If money was taken, contact the '
        'resort.'),
    'gateway' => const InvalidState(
        'The payment service is not responding. Try again in a minute.'),
    _ => const UnknownFailure('The payment service failed.'),
  };
}

final paymentOrderSourceProvider = Provider<PaymentOrderSource>((ref) {
  final db = ref.watch(supabaseProvider);
  return PaymentFunctionsSource(
      (name, body) => db.functions.invoke(name, body: body));
});
```

- [ ] **Step 5: Run them to verify they pass**

Run: `flutter test test/data/payment_order_repository_test.dart test/core/errors_test.dart && flutter analyze`
Expected: PASS (16 new repository tests, plus 1 in errors). The analyzer shows only the 2 baseline infos.

- [ ] **Step 6: Commit**

```bash
git add lib/data/repositories/payment_order_repository.dart lib/core/errors.dart \
  test/data/payment_order_repository_test.dart test/core/errors_test.dart
git commit -m "$(cat <<'EOF'
feat(payments): client for the payment Edge Functions; P0036 copy

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 10: `RazorpayGateway` through the server, with the mock as fallback

**Track:** Track (Flutter). Depends on Task 9.

**Files:**
- Rewrite: `lib/features/booking/razorpay_gateway.dart`
- Modify: `lib/features/booking/payment_gateway.dart` (the provider; `resolvePaymentGateway` and the dart-define constants are removed)
- Modify: `lib/features/owner/payment_settings_screen.dart` (the doc comment only)
- Rewrite: `test/features/booking/razorpay_gateway_test.dart`

**Interfaces:**
- Consumes: `PaymentOrderSource`, `paymentOrderSourceProvider`, `RazorpayCheckout`, `razorpayCheckoutProvider`, `CheckoutRequest.fromOrder`, `MockGateway`, `FakePaymentOrderSource`, `FakeRazorpayCheckout` and `razorpayOrder()`.
- Produces:
  - `class RazorpayGateway implements PaymentGateway { const RazorpayGateway({required PaymentOrderSource orders, required RazorpayCheckout checkout, PaymentGateway fallback = const MockGateway()}) }`.
  - The message constants `paymentCancelledMessage`, `paymentMismatchMessage`, `unappliedRefundingMessage` and `unappliedContactMessage`.
  - `paymentGatewayProvider` now always builds a `RazorpayGateway`.
  - Removed: `RazorpayConfigurationError`, `resolvePaymentGateway`, and the `RAZORPAY_KEY_ID` / `RAZORPAY_KEY_SECRET` dart-defines.

- [ ] **Step 1: Write the failing tests**

Replace the whole of `test/features/booking/razorpay_gateway_test.dart` with:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/errors.dart';
import 'package:pasala/data/models/payment_order.dart';
import 'package:pasala/data/repositories/payment_order_repository.dart';
import 'package:pasala/features/booking/payment_gateway.dart';
import 'package:pasala/features/booking/razorpay_checkout.dart';
import 'package:pasala/features/booking/razorpay_gateway.dart';

import '../../support/fake_payment_order_source.dart';
import '../../support/fake_razorpay_checkout.dart';

/// Records what the gateway delegated to it.
class _RecordingFallback implements PaymentGateway {
  final calls = <({String reservationId, num amount, PaymentPurpose purpose})>[];

  @override
  Future<PaymentResult> charge({
    required String reservationId,
    required num amount,
    PaymentPurpose purpose = PaymentPurpose.advance,
  }) async {
    calls.add((reservationId: reservationId, amount: amount, purpose: purpose));
    return const PaymentResult.success('mock_fallback');
  }
}

const _succeeded = CheckoutSucceeded(
  paymentId: 'pay_P6test0001',
  orderId: 'order_P6test0001',
  signature: 'sig',
);

void main() {
  late FakePaymentOrderSource orders;
  late FakeRazorpayCheckout checkout;
  late _RecordingFallback fallback;
  late RazorpayGateway gateway;

  setUp(() {
    orders = FakePaymentOrderSource();
    checkout = FakeRazorpayCheckout();
    fallback = _RecordingFallback();
    gateway = RazorpayGateway(orders: orders, checkout: checkout, fallback: fallback);
  });

  test('without Razorpay keys the mock takes the payment, exactly as before',
      () async {
    orders.createResult = const PaymentsNotConfigured();

    final result = await gateway.charge(reservationId: 'r1', amount: 5000);

    expect(result.reference, 'mock_fallback');
    expect(fallback.calls,
        [(reservationId: 'r1', amount: 5000, purpose: PaymentPurpose.advance)]);
    expect(checkout.requests, isEmpty);
  });

  test('the order is created for the amount and purpose asked', () async {
    await gateway.charge(
        reservationId: 'r2', amount: 3000, purpose: PaymentPurpose.balance);
    expect(orders.createCalls,
        [(reservationId: 'r2', amount: 3000, purpose: PaymentPurpose.balance)]);
  });

  test('a created order opens the payment window with its details', () async {
    orders.createResult = razorpayOrder();
    await gateway.charge(reservationId: 'r1', amount: 5000);

    final request = checkout.requests.single;
    expect(request.keyId, 'rzp_test_fixture');
    expect(request.orderId, 'order_P6test0001');
    expect(request.amountPaise, 500000);
    expect(request.name, 'Online A');
    expect(request.prefillEmail, 'gita@example.com');
    expect(fallback.calls, isEmpty);
  });

  test('a paid window is verified and its payment id is the reference',
      () async {
    orders.createResult = razorpayOrder();
    checkout.outcome = _succeeded;

    final result = await gateway.charge(reservationId: 'r1', amount: 5000);

    expect(orders.verifyCalls, [
      (orderId: 'order_P6test0001', paymentId: 'pay_P6test0001', signature: 'sig')
    ]);
    expect(result.succeeded, isTrue);
    expect(result.reference, 'pay_P6test0001');
  });

  test('closing the window is a cancelled payment and nothing is verified',
      () async {
    orders.createResult = razorpayOrder();
    checkout.outcome = const CheckoutDismissed();

    final result = await gateway.charge(reservationId: 'r1', amount: 5000);

    expect(result.succeeded, isFalse);
    expect(result.failureMessage, 'Payment cancelled.');
    expect(orders.verifyCalls, isEmpty);
  });

  test("a failed window passes on the window's message", () async {
    orders.createResult = razorpayOrder();
    checkout.outcome = const CheckoutFailed('Network error during payment. Try again.');

    final result = await gateway.charge(reservationId: 'r1', amount: 5000);

    expect(result.failureMessage, 'Network error during payment. Try again.');
  });

  test('an answer for another order is never verified', () async {
    orders.createResult = razorpayOrder();
    checkout.outcome = const CheckoutSucceeded(
        paymentId: 'pay_x', orderId: 'order_other', signature: 'sig');

    final result = await gateway.charge(reservationId: 'r1', amount: 5000);

    expect(result.succeeded, isFalse);
    expect(orders.verifyCalls, isEmpty);
  });

  test('an unapplied payment fails with the refund message', () async {
    orders
      ..createResult = razorpayOrder()
      ..verifyResult = const VerifyResult(
          outcome: VerifyOutcome.unapplied,
          reservationId: 'r1',
          refund: RefundState.initiated);
    checkout.outcome = _succeeded;

    final refunding = await gateway.charge(reservationId: 'r1', amount: 5000);
    expect(refunding.succeeded, isFalse);
    expect(refunding.failureMessage,
        'Your payment could not be added to this booking, so it is being refunded in full.');

    orders.verifyResult = const VerifyResult(
        outcome: VerifyOutcome.unapplied,
        reservationId: 'r1',
        refund: RefundState.failed);
    final contact = await gateway.charge(reservationId: 'r1', amount: 5000);
    expect(contact.failureMessage,
        'Your payment could not be added to this booking. The resort will refund it.');
  });

  test("the server's refusals reach the caller as BookingFailures", () async {
    orders.createError = const HoldExpired();
    await expectLater(gateway.charge(reservationId: 'r1', amount: 5000),
        throwsA(isA<HoldExpired>()));

    orders
      ..createError = null
      ..createResult = razorpayOrder()
      ..verifyError = const InvalidState(paymentNotConfirmedYetMessage);
    checkout.outcome = _succeeded;
    await expectLater(gateway.charge(reservationId: 'r1', amount: 5000),
        throwsA(isA<InvalidState>()));
  });

  group('paymentGatewayProvider', () {
    test('always builds a RazorpayGateway, which falls back to the real mock',
        () async {
      final container = ProviderContainer(overrides: [
        paymentOrderSourceProvider.overrideWithValue(FakePaymentOrderSource()),
        razorpayCheckoutProvider.overrideWithValue(FakeRazorpayCheckout()),
      ]);
      addTearDown(container.dispose);

      final gateway = container.read(paymentGatewayProvider);
      expect(gateway, isA<RazorpayGateway>());

      final result = await gateway.charge(reservationId: 'c1', amount: 11500);
      expect(result.reference, 'mock_c1_11500');
    });
  });
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `flutter test test/features/booking/razorpay_gateway_test.dart`
Expected: FAIL to compile: `RazorpayGateway` has no `orders` / `checkout` / `fallback` parameters.

- [ ] **Step 3: Rewrite the gateway**

Replace the whole of `lib/features/booking/razorpay_gateway.dart` with:

```dart
import '../../data/models/payment_order.dart';
import '../../data/repositories/payment_order_repository.dart';
import 'payment_gateway.dart';
import 'razorpay_checkout.dart';

const paymentCancelledMessage = 'Payment cancelled.';
const paymentMismatchMessage =
    'The payment window answered for a different order. If money was taken, '
    'contact the resort.';
const unappliedRefundingMessage =
    'Your payment could not be added to this booking, so it is being '
    'refunded in full.';
const unappliedContactMessage =
    'Your payment could not be added to this booking. The resort will '
    'refund it.';

/// Online payments through Razorpay, with no secret in the app (spec
/// decisions 6 and 16):
///  1. `payments-create-order` checks the amount and creates the order --
///     or says online payments are not configured, and [fallback] (the
///     mock) takes the payment exactly as before P6;
///  2. the platform's Razorpay window collects the payment;
///  3. `payments-verify` checks Razorpay's signature and settles the
///     payment server-side (confirms the hold, or checks the guest out).
///
/// The caller's own `confirm_booking` / `checkout_booking` that follows a
/// success then finds the booking already settled and returns it.
class RazorpayGateway implements PaymentGateway {
  const RazorpayGateway({
    required PaymentOrderSource orders,
    required RazorpayCheckout checkout,
    PaymentGateway fallback = const MockGateway(),
  })  : _orders = orders,
        _checkout = checkout,
        _fallback = fallback;

  final PaymentOrderSource _orders;
  final RazorpayCheckout _checkout;
  final PaymentGateway _fallback;

  @override
  Future<PaymentResult> charge({
    required String reservationId,
    required num amount,
    PaymentPurpose purpose = PaymentPurpose.advance,
  }) async {
    final order = await _orders.createOrder(
      reservationId: reservationId,
      amount: amount,
      purpose: purpose,
    );
    switch (order) {
      case PaymentsNotConfigured():
        return _fallback.charge(
          reservationId: reservationId,
          amount: amount,
          purpose: purpose,
        );
      case RazorpayOrder():
        return _pay(order);
    }
  }

  Future<PaymentResult> _pay(RazorpayOrder order) async {
    final outcome = await _checkout.open(CheckoutRequest.fromOrder(order));
    switch (outcome) {
      case CheckoutDismissed():
        return const PaymentResult.failure(paymentCancelledMessage);
      case CheckoutFailed(:final message):
        return PaymentResult.failure(message);
      case CheckoutSucceeded():
        if (outcome.orderId != order.orderId) {
          return const PaymentResult.failure(paymentMismatchMessage);
        }
        final verified = await _orders.verify(
          orderId: order.orderId,
          paymentId: outcome.paymentId,
          signature: outcome.signature,
        );
        return switch (verified.outcome) {
          VerifyOutcome.paid => PaymentResult.success(outcome.paymentId),
          VerifyOutcome.unapplied => PaymentResult.failure(
              verified.refund == RefundState.initiated
                  ? unappliedRefundingMessage
                  : unappliedContactMessage),
        };
    }
  }
}
```

In `lib/features/booking/payment_gateway.dart`:
- Add `import '../../data/repositories/payment_order_repository.dart';` after the `payment_order.dart` import.
- Replace the doc comment above `abstract interface class PaymentGateway` ("The seam phase 2 replaces with Razorpay. …") with:

```dart
/// How the app takes a payment. [RazorpayGateway] is the only
/// implementation the app uses; [MockGateway] is its fallback when the
/// deployment has no Razorpay keys, and tests use their own fakes.
```

- Delete everything from the comment `// There is no live Razorpay merchant account` down to, and including, the old `paymentGatewayProvider`. That covers `_razorpayKeyId`, `_razorpayKeySecret`, `resolvePaymentGateway` and its doc comment. In its place put:

```dart
/// Every payment asks the server first: with Razorpay keys set it takes a
/// real payment, without them [RazorpayGateway] hands it to [MockGateway]
/// exactly as before P6. The app never holds a Razorpay secret.
final paymentGatewayProvider = Provider<PaymentGateway>((ref) => RazorpayGateway(
      orders: ref.watch(paymentOrderSourceProvider),
      checkout: ref.watch(razorpayCheckoutProvider),
    ));
```

The file's end now reads: `MockGateway`, then `paymentGatewayProvider`, then `razorpayCheckoutProvider` (from Task 1).

In `lib/features/owner/payment_settings_screen.dart`, replace the first four lines of the class doc comment, from `/// Payment configuration -- business-facing settings only. Real gateway` through `/// here -- this screen controls \`properties.advance_pct\` (already existed,`, with:

```dart
/// Payment configuration -- business-facing settings only. Razorpay keys
/// are Edge Function secrets set at deploy time (README, "Online payments
/// (Razorpay)") and are never in the app, the database, or editable
/// here -- this screen controls `properties.advance_pct` (already existed,
```

- [ ] **Step 4: Run them to verify they pass**

Run: `grep -rn "resolvePaymentGateway\|RazorpayConfigurationError\|RAZORPAY_KEY" lib test; flutter test test/features/booking && flutter analyze`
Expected: the grep finds nothing. The booking tests pass, including the 10 new gateway tests (the provider test waits for the real `MockGateway`'s 400 ms). The analyzer shows only the 2 baseline infos.

- [ ] **Step 5: Commit**

```bash
git add lib/features/booking/razorpay_gateway.dart lib/features/booking/payment_gateway.dart \
  lib/features/owner/payment_settings_screen.dart test/features/booking/razorpay_gateway_test.dart
git commit -m "$(cat <<'EOF'
feat(payments): RazorpayGateway pays through the server; mock only without keys

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 11: The Razorpay payment windows (web and mobile)

**Track:** Track (Flutter). Depends on Task 1 only, so it can run alongside Tasks 9, 10 and 12.

**Files:**
- Modify: `lib/features/booking/razorpay_checkout.dart` (messages and `checkoutOptions`)
- Modify: `lib/features/booking/razorpay_checkout_platform.dart` (conditional export)
- Create: `lib/features/booking/razorpay_checkout_web.dart`, `lib/features/booking/razorpay_checkout_mobile.dart`
- Modify: `pubspec.yaml`, `pubspec.lock`
- Test: `test/features/booking/razorpay_checkout_test.dart`

**Interfaces:**
- Consumes: `CheckoutRequest`, `CheckoutOutcome` and `UnsupportedRazorpayCheckout` (Task 1).
- Produces:
  - `Map<String, Object?> checkoutOptions(CheckoutRequest)`.
  - The message constants `paymentFailedMessage`, `networkFailedMessage`, `checkoutLoadFailedMessage`, `incompleteResponseMessage` and `externalWalletMessage`.
  - `createRazorpayCheckout()` per platform.
  - `class MobileRazorpayCheckout`, `outcomeFromSuccess(PaymentSuccessResponse)` and `outcomeFromFailure(PaymentFailureResponse)`.
  - `class WebRazorpayCheckout` and `checkoutScriptUrl`.

- [ ] **Step 1: Add the dependency**

Run: `flutter pub add razorpay_flutter:^1.4.7`. Then, in `pubspec.yaml`, put this comment above the new line so that it reads:

```yaml
  geolocator: ^14.0.3
  # Razorpay's payment window on Android and iOS (P6). The web build uses
  # Checkout.js instead (lib/features/booking/razorpay_checkout_web.dart).
  razorpay_flutter: ^1.4.7
```

Run: `git diff pubspec.lock`. Expected: two new packages, `eventify` 1.0.1 and `razorpay_flutter` 1.4.7. If the `sdks:` → `dart:` line changed (for example `">=3.10.8 <4.0.0"` became `">=3.11.0 <4.0.0"`), change that one line back. It is an SDK-only bump (Global Constraints).

- [ ] **Step 2: Write the failing tests**

Create `test/features/booking/razorpay_checkout_test.dart`:

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/features/booking/razorpay_checkout.dart';
import 'package:pasala/features/booking/razorpay_checkout_mobile.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

const _request = CheckoutRequest(
  keyId: 'rzp_test_fixture',
  orderId: 'order_P6test0001',
  amountPaise: 500000,
  currency: 'INR',
  name: 'Online A',
  description: 'Online A: booking advance',
  prefillName: 'Gita Guest',
  prefillContact: '+919800000001',
);

void main() {
  test('checkoutOptions carries the order and leaves out empty prefill', () {
    expect(checkoutOptions(_request), {
      'key': 'rzp_test_fixture',
      'order_id': 'order_P6test0001',
      'amount': 500000,
      'currency': 'INR',
      'name': 'Online A',
      'description': 'Online A: booking advance',
      'prefill': {'name': 'Gita Guest', 'contact': '+919800000001'},
    });
  });

  test('checkoutOptions never carries a secret', () {
    final text = checkoutOptions(_request).toString();
    expect(text, isNot(contains('secret')));
  });

  group('mobile', () {
    test('a complete success is CheckoutSucceeded', () {
      final outcome = outcomeFromSuccess(PaymentSuccessResponse(
          'pay_1', 'order_1', 'sig', const {}));
      expect(outcome, isA<CheckoutSucceeded>());
      final ok = outcome as CheckoutSucceeded;
      expect((ok.paymentId, ok.orderId, ok.signature), ('pay_1', 'order_1', 'sig'));
    });

    test('a success without a signature cannot be verified', () {
      final outcome =
          outcomeFromSuccess(PaymentSuccessResponse('pay_1', 'order_1', null, const {}));
      expect(outcome, isA<CheckoutFailed>());
    });

    test('cancelling is dismissed, a network error and others are failures', () {
      expect(
          outcomeFromFailure(
              PaymentFailureResponse(Razorpay.PAYMENT_CANCELLED, 'cancelled', null)),
          isA<CheckoutDismissed>());
      expect(
          (outcomeFromFailure(PaymentFailureResponse(Razorpay.NETWORK_ERROR, '{"raw":1}', null))
                  as CheckoutFailed)
              .message,
          'Network error during payment. Try again.');
      expect(
          (outcomeFromFailure(PaymentFailureResponse(Razorpay.UNKNOWN_ERROR, '{"raw":1}', null))
                  as CheckoutFailed)
              .message,
          'Payment failed. Try again or choose another method.');
    });

    test('Android and iOS get the native window, desktop the unsupported one',
        () {
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(createRazorpayCheckout(), isA<MobileRazorpayCheckout>());
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(createRazorpayCheckout(), isA<MobileRazorpayCheckout>());
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      expect(createRazorpayCheckout(), isA<UnsupportedRazorpayCheckout>());
    });
  });
}
```

- [ ] **Step 3: Run them to verify they fail**

Run: `flutter test test/features/booking/razorpay_checkout_test.dart`
Expected: FAIL to compile: `checkoutOptions` and `razorpay_checkout_mobile.dart` do not exist.

- [ ] **Step 4: Write the options and both windows**

In `lib/features/booking/razorpay_checkout.dart`, add after `unsupportedCheckoutMessage`:

```dart
const paymentFailedMessage = 'Payment failed. Try again or choose another method.';
const networkFailedMessage = 'Network error during payment. Try again.';
const checkoutLoadFailedMessage =
    'Could not load the payment window. Check your connection and try again.';
const incompleteResponseMessage =
    'The payment window gave an incomplete answer. If money was taken, '
    'contact the resort.';
const externalWalletMessage =
    'That wallet is not supported here. Choose another payment method.';
```

and at the end of the file:

```dart
/// The options both payment windows take (Razorpay's documented Checkout
/// options). Empty prefill fields are left out.
Map<String, Object?> checkoutOptions(CheckoutRequest request) => {
      'key': request.keyId,
      'order_id': request.orderId,
      'amount': request.amountPaise,
      'currency': request.currency,
      'name': request.name,
      'description': request.description,
      'prefill': <String, Object?>{
        if (request.prefillName != null) 'name': request.prefillName,
        if (request.prefillEmail != null) 'email': request.prefillEmail,
        if (request.prefillContact != null) 'contact': request.prefillContact,
      },
    };
```

Create `lib/features/booking/razorpay_checkout_mobile.dart`:

```dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

import 'razorpay_checkout.dart';

/// razorpay_flutter has Android and iOS plugins only; on desktop its
/// platform channel never answers, so those get the unsupported window.
RazorpayCheckout createRazorpayCheckout() => switch (defaultTargetPlatform) {
      TargetPlatform.android || TargetPlatform.iOS => MobileRazorpayCheckout(),
      _ => const UnsupportedRazorpayCheckout(),
    };

CheckoutOutcome outcomeFromSuccess(PaymentSuccessResponse response) {
  final paymentId = response.paymentId;
  final orderId = response.orderId;
  final signature = response.signature;
  if (paymentId == null || orderId == null || signature == null) {
    return const CheckoutFailed(incompleteResponseMessage);
  }
  return CheckoutSucceeded(
      paymentId: paymentId, orderId: orderId, signature: signature);
}

/// The SDK's own messages can be raw JSON, so the guest gets ours.
CheckoutOutcome outcomeFromFailure(PaymentFailureResponse response) =>
    switch (response.code) {
      Razorpay.PAYMENT_CANCELLED => const CheckoutDismissed(),
      Razorpay.NETWORK_ERROR => const CheckoutFailed(networkFailedMessage),
      _ => const CheckoutFailed(paymentFailedMessage),
    };

/// Razorpay's native checkout (Android/iOS) through razorpay_flutter. One
/// SDK instance per payment, cleared afterwards.
class MobileRazorpayCheckout implements RazorpayCheckout {
  @override
  Future<CheckoutOutcome> open(CheckoutRequest request) async {
    final razorpay = Razorpay();
    final result = Completer<CheckoutOutcome>();
    void finish(CheckoutOutcome outcome) {
      if (!result.isCompleted) result.complete(outcome);
    }

    razorpay
      ..on(Razorpay.EVENT_PAYMENT_SUCCESS,
          (PaymentSuccessResponse r) => finish(outcomeFromSuccess(r)))
      ..on(Razorpay.EVENT_PAYMENT_ERROR,
          (PaymentFailureResponse r) => finish(outcomeFromFailure(r)))
      ..on(Razorpay.EVENT_EXTERNAL_WALLET,
          (ExternalWalletResponse _) => finish(const CheckoutFailed(externalWalletMessage)));
    try {
      razorpay.open(checkoutOptions(request));
      return await result.future;
    } finally {
      razorpay.clear();
    }
  }
}
```

Create `lib/features/booking/razorpay_checkout_web.dart`:

```dart
import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import 'razorpay_checkout.dart';

/// Razorpay's hosted Checkout script. Injected on first use only, so a
/// deployment without Razorpay keys never loads anything from Razorpay.
const checkoutScriptUrl = 'https://checkout.razorpay.com/v1/checkout.js';

RazorpayCheckout createRazorpayCheckout() => WebRazorpayCheckout();

@JS('Razorpay')
extension type _Razorpay._(JSObject _) implements JSObject {
  external factory _Razorpay(JSObject options);
  external void open();
  external void on(String event, JSFunction handler);
}

/// Razorpay Checkout.js through `dart:js_interop`.
class WebRazorpayCheckout implements RazorpayCheckout {
  static Future<void>? _loading;

  static Future<void> _ensureLoaded() {
    if (globalContext.has('Razorpay')) return Future.value();
    return _loading ??= _inject();
  }

  static Future<void> _inject() async {
    final loaded = Completer<void>();
    final script = web.HTMLScriptElement()
      ..src = checkoutScriptUrl
      ..async = true;
    script.onload = ((web.Event _) {
      if (!loaded.isCompleted) loaded.complete();
    }).toJS;
    script.onerror = ((web.Event _) {
      if (!loaded.isCompleted) {
        loaded.completeError(StateError('checkout.js failed to load'));
      }
    }).toJS;
    web.document.head!.append(script);
    try {
      await loaded.future.timeout(const Duration(seconds: 20));
    } catch (_) {
      _loading = null; // the next payment tries again
      script.remove();
      rethrow;
    }
  }

  @override
  Future<CheckoutOutcome> open(CheckoutRequest request) async {
    try {
      await _ensureLoaded();
    } catch (_) {
      return const CheckoutFailed(checkoutLoadFailedMessage);
    }

    final result = Completer<CheckoutOutcome>();
    String? lastError;

    final options = checkoutOptions(request).jsify()! as JSObject;
    options['handler'] = ((JSObject response) {
      final data = (response.dartify() as Map?) ?? const {};
      final paymentId = data['razorpay_payment_id'] as String?;
      final orderId = data['razorpay_order_id'] as String?;
      final signature = data['razorpay_signature'] as String?;
      if (result.isCompleted) return;
      result.complete(paymentId == null || orderId == null || signature == null
          ? const CheckoutFailed(incompleteResponseMessage)
          : CheckoutSucceeded(
              paymentId: paymentId, orderId: orderId, signature: signature));
    }).toJS;
    final modal = JSObject();
    modal['ondismiss'] = (() {
      if (result.isCompleted) return;
      final error = lastError;
      result.complete(
          error == null ? const CheckoutDismissed() : CheckoutFailed(error));
    }).toJS;
    options['modal'] = modal;

    final razorpay = _Razorpay(options);
    // Checkout.js keeps its window open after a failed attempt so the
    // guest can retry; remember why, in case they then close it.
    razorpay.on(
        'payment.failed',
        ((JSObject response) {
          final data = (response.dartify() as Map?) ?? const {};
          final error = data['error'];
          final description = error is Map ? error['description'] : null;
          lastError = description is String && description.trim().isNotEmpty
              ? description
              : paymentFailedMessage;
        }).toJS);
    razorpay.open();
    return result.future;
  }
}
```

Replace the whole of `lib/features/booking/razorpay_checkout_platform.dart` with:

```dart
// Picks the Razorpay payment window for the platform being compiled:
// Checkout.js on the web, razorpay_flutter on Android/iOS (other native
// platforms get UnsupportedRazorpayCheckout from the mobile file), and a
// stub anywhere else. dart.library.js_interop is the web test, as in
// lib/features/reports/csv_download.dart.
export 'razorpay_checkout_stub.dart'
    if (dart.library.js_interop) 'razorpay_checkout_web.dart'
    if (dart.library.io) 'razorpay_checkout_mobile.dart';
```

- [ ] **Step 5: Run the tests, the analyzer and a web build**

Run: `flutter test test/features/booking/razorpay_checkout_test.dart && flutter analyze && flutter build web`
Expected:
- the tests pass (6 tests);
- the analyzer shows only the 2 baseline infos;
- `✓ Built build/web`, which proves the Checkout.js interop compiles. The VM tests only ever compile the mobile file.

Never construct `Razorpay()` in a test: its constructor path calls a platform channel.

- [ ] **Step 6: Commit**

```bash
git add lib/features/booking/razorpay_checkout.dart lib/features/booking/razorpay_checkout_platform.dart \
  lib/features/booking/razorpay_checkout_web.dart lib/features/booking/razorpay_checkout_mobile.dart \
  pubspec.yaml pubspec.lock test/features/booking/razorpay_checkout_test.dart
git commit -m "$(cat <<'EOF'
feat(payments): Razorpay payment windows (Checkout.js on web, razorpay_flutter on mobile)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 12: The booking and checkout screens

**Track:** Track (Flutter). Depends on Task 10.

**Files:**
- Modify: `lib/features/booking/booking_screen.dart` (`_startHoldTicker` and `_pay`)
- Modify: `lib/features/stay/checkout_screen.dart` (`_checkout`, and the class doc comment)
- Test: `test/features/booking/hold_lifecycle_test.dart`, `test/features/stay/checkout_screen_test.dart`

**Interfaces:**
- Consumes: `PaymentGateway.charge(…, purpose:)`, `PaymentPurpose`, `OnlinePaymentRequired` and `currentChargesProvider`.
- Produces: no new API. Behaviour:
  - the hold ticker does not expire the hold while `_busy`;
  - the guest's advance is charged with `PaymentPurpose.advance` and the balance with `PaymentPurpose.balance`;
  - a failed guest checkout payment invalidates `currentChargesProvider(reservationId)`.

- [ ] **Step 1: Write the failing tests**

In `test/features/booking/hold_lifecycle_test.dart`:
- Add `import 'dart:async';` as the first import.
- In `_FakeBookingActions`, add under `Quote? quoteToReturn;`:

```dart
  /// How long a new hold lives. `Duration.zero` makes it already expired
  /// by the hold ticker's first tick.
  Duration holdTtl = const Duration(minutes: 15);

  /// Thrown by [confirm] when set (e.g. P0036 while payments are live).
  Object? confirmError;
```

- In `createHold`, change `holdExpiresAt: DateTime.now().toUtc().add(const Duration(minutes: 15)),` to `holdExpiresAt: DateTime.now().toUtc().add(holdTtl),`.
- In `confirm`, add `if (confirmError != null) throw confirmError!;` right after `calls.add('confirm');`.
- Add this class just before `Quote _quote({num total = 5500})`:

```dart
/// A [PaymentGateway] whose charge stays open until the test completes
/// [completer] -- a payment window the guest has not finished with yet.
class _PendingGateway implements PaymentGateway {
  final completer = Completer<PaymentResult>();
  final purposes = <PaymentPurpose>[];

  @override
  Future<PaymentResult> charge({
    required String reservationId,
    required num amount,
    PaymentPurpose purpose = PaymentPurpose.advance,
  }) {
    purposes.add(purpose);
    return completer.future;
  }
}
```

- Inside `group('BookingScreen widget', …)`, just before the test `'Cancel hold calls cancel_booking immediately and removes the resume '…`, add:

```dart
    testWidgets(
        'the hold countdown does not expire the hold while the payment '
        'window is open, and the booking completes when it closes',
        (tester) async {
      final actions = _FakeBookingActions()
        ..quoteToReturn = _quote()
        ..holdTtl = Duration.zero;
      final gateway = _PendingGateway();

      await tester.pumpWidget(bookingApp(actions: actions, gateway: gateway));
      await tester.pumpAndSettle();

      final now = DateTime.now();
      final from = DateTime(now.year, now.month, now.day).add(const Duration(days: 5));
      final to = from.add(const Duration(days: 2));
      final cursor = _MonthCursor(DateTime(now.year, now.month));
      await pickRange(tester, cursor, from, to);
      await tapVisible(tester, const Key('pay-button'));

      // Three ticks of the 1-second hold ticker, all with the hold at zero.
      await tester.pump(const Duration(seconds: 3));

      expect(gateway.purposes, [PaymentPurpose.advance]);
      expect(find.textContaining('hold expired'), findsNothing,
          reason: 'a payment in flight owns the hold until it finishes');
      expect(actions.calls, ['quote', 'createHold']);

      gateway.completer.complete(const PaymentResult.success('pay_P6test0001'));
      await tester.pumpAndSettle();

      expect(actions.calls, ['quote', 'createHold', 'confirm']);
      expect(find.text('confirmed:hold-0'), findsOneWidget);
    });

    testWidgets(
        'P0036 after a mock fallback shows the readable message and keeps '
        'the hold to resume', (tester) async {
      final actions = _FakeBookingActions()
        ..quoteToReturn = _quote()
        ..confirmError = const OnlinePaymentRequired();
      final gateway = _ScriptedGateway([const PaymentResult.success('mock_ref')]);

      await tester.pumpWidget(bookingApp(actions: actions, gateway: gateway));
      await tester.pumpAndSettle();

      final now = DateTime.now();
      final from = DateTime(now.year, now.month, now.day).add(const Duration(days: 5));
      final to = from.add(const Duration(days: 2));
      final cursor = _MonthCursor(DateTime(now.year, now.month));
      await pickRange(tester, cursor, from, to);
      await tapVisible(tester, const Key('pay-button'));

      expect(
          find.text('Online payment is not available right now. Please try '
              'again in a few minutes.'),
          findsOneWidget);
      expect(find.byKey(const Key('resume-hold-button')), findsOneWidget);
      expect(actions.cancelledIds, isEmpty);
    });
```

In `test/features/stay/checkout_screen_test.dart`:
- Replace `_FakeGateway` with:

```dart
class _FakeGateway implements PaymentGateway {
  final charges = <num>[];
  final purposes = <PaymentPurpose>[];

  /// What [charge] answers; a success with `mock_<id>` when null.
  PaymentResult? result;

  @override
  Future<PaymentResult> charge({required String reservationId, required num amount, PaymentPurpose purpose = PaymentPurpose.advance}) async {
    charges.add(amount);
    purposes.add(purpose);
    return result ?? PaymentResult.success('mock_$reservationId');
  }
}
```

- In `_pump`, add the parameter `void Function()? onChargesRead,` after `FakeFinanceSource? finance,`, and replace the override `currentChargesProvider.overrideWith((ref, id) async => _charges(balance)),` with:

```dart
      currentChargesProvider.overrideWith((ref, id) async {
        onChargesRead?.call();
        return _charges(balance);
      }),
```

- In `group('guest checkout', …)`, just before `'with nothing to pay it sends no-balance-due'`, add:

```dart
    testWidgets('pays the balance as a balance payment', (tester) async {
      final gateway = _FakeGateway();
      await _pump(tester, extra: 'r1', stay: _FakeStayRepository(), gateway: gateway);

      await tester.tap(find.widgetWithText(FilledButton, 'Pay ₹2,000 and check out'));
      await tester.pumpAndSettle();

      expect(gateway.purposes, [PaymentPurpose.balance]);
    });

    testWidgets('a failed payment shows why and re-reads the charges', (tester) async {
      final stay = _FakeStayRepository();
      final gateway = _FakeGateway()
        ..result = const PaymentResult.failure(
            'Your payment could not be added to this booking, so it is being refunded in full.');
      var chargesReads = 0;
      await _pump(tester,
          extra: 'r1', stay: stay, gateway: gateway, onChargesRead: () => chargesReads++);
      final readsBefore = chargesReads;

      await tester.tap(find.widgetWithText(FilledButton, 'Pay ₹2,000 and check out'));
      await tester.pumpAndSettle();

      expect(
          find.text('Your payment could not be added to this booking, so it is being refunded in full.'),
          findsOneWidget);
      expect(chargesReads, greaterThan(readsBefore));
      expect(stay.checkouts, isEmpty);
      expect(find.text('INVOICE r1'), findsNothing);
    });
```

- [ ] **Step 2: Run them to verify they fail**

Run: `flutter test test/features/booking/hold_lifecycle_test.dart test/features/stay/checkout_screen_test.dart`
Expected: 2 failures:
- `the hold countdown does not expire the hold while the payment window is open…`: "Your 15-minute hold expired" is shown, and `confirm` is never called.
- `a failed payment shows why and re-reads the charges`: the charges are not re-read.

The P0036 test already passes: the existing failure path shows the message and keeps the hold. It pins that behaviour.

- [ ] **Step 3: Change the two screens**

In `lib/features/booking/booking_screen.dart`, `_startHoldTicker`, inside `if (remaining == null || remaining == Duration.zero) {` and before `_ticker?.cancel();`, add:

```dart
        // A payment in flight owns the hold until it finishes: the server
        // still confirms a payment captured moments after the expiry
        // (payment_order_settle), so the payment window must not have the
        // booking torn down underneath it. The next tick after it
        // finishes handles a hold that really did lapse.
        if (_busy) return;
```

In `_pay`, replace

```dart
      final payment = await ref
          .read(paymentGatewayProvider)
          .charge(reservationId: hold.id, amount: payAmount);
```

with

```dart
      final payment = await ref.read(paymentGatewayProvider).charge(
            reservationId: hold.id,
            amount: payAmount,
            purpose: PaymentPurpose.advance,
          );
```

In `lib/features/stay/checkout_screen.dart`, replace the guest branch's charge

```dart
          final payment = await ref
              .read(paymentGatewayProvider)
              .charge(reservationId: widget.reservationId, amount: balance);
```

with

```dart
          final payment = await ref.read(paymentGatewayProvider).charge(
                reservationId: widget.reservationId,
                amount: balance,
                purpose: PaymentPurpose.balance,
              );
```

and in `_checkout`'s `on BookingFailure catch (e)` block, add after `if (!mounted) return;`:

```dart
      // The balance may have changed under an online payment (a food order
      // placed meanwhile leaves the payment unapplied and refunded), so
      // show the current figure before the guest tries again.
      if (!widget.desk) {
        ref.invalidate(currentChargesProvider(widget.reservationId));
      }
```

Replace the class doc comment's first two lines, `/// The final bill. A guest settles it through the same mock` and `/// [PaymentGateway] seam \`booking_screen.dart\`'s own \`_pay\` uses.`, with:

```dart
/// The final bill. A guest settles it through the same [PaymentGateway]
/// `booking_screen.dart`'s own `_pay` uses (Razorpay, or the mock without
/// keys).
```

- [ ] **Step 4: Run them to verify they pass**

Run: `flutter test && flutter analyze`
Expected: the whole suite passes. The count is the Task 1 baseline + 36: 7 (Task 1) + 17 (Task 9) + 10 − 8 (Task 10's gateway tests replace the old file's 8) + 6 (Task 11) + 4 (this task). The analyzer shows only the 2 baseline infos.

- [ ] **Step 5: Commit**

```bash
git add lib/features/booking/booking_screen.dart lib/features/stay/checkout_screen.dart \
  test/features/booking/hold_lifecycle_test.dart test/features/stay/checkout_screen_test.dart
git commit -m "$(cat <<'EOF'
feat(payments): screens pass the payment purpose; hold waits for an open payment window

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

## Phase 4: Integration

### Task 13: Merge the tracks, verify end to end, and document

**Track:** both. Depends on Tasks 2–12.

**Files:**
- Modify: `README.md` (replace the "Payments (phase 2 seam, still stubbed)" block, add a `make` target row, and update the "Payment is still a mock gateway" limitation)
- Modify: `docs/STATUS.md` (the three payment statements)
- Verification only for everything else.

**Interfaces:**
- Consumes: everything above.
- Produces: a branch where the database, the Deno functions and the app pass together, and the docs describe how to switch Razorpay on.

- [ ] **Step 1: Merge the tracks**

If the tracks ran in separate worktrees, merge them onto the Task 1 branch: the DB branch (Tasks 2–4), then the Deno branch (5–8), then the Flutter branch (9–12). They share no files, so there should be no conflicts. If `supabase/tests/37_tenancy_isolation_test.sql` or `lib/core/errors.dart` conflict with another project already merged into `feat/gaps`, keep both sides' entries.

- [ ] **Step 2: Run every suite**

Run: `supabase db reset && supabase test db 2>&1 | tail -15`
Expected: 45 passes 115/115, and 37 is green. The only failures allowed are the known time-window ones (25/9, 26/3 and 34/2, between 00:00 and 05:30 IST).

Run: `make functions-test`
Expected: 49 passed.

Run: `flutter analyze && flutter test && flutter build web`
Expected: the 2 baseline infos only; all tests pass; `✓ Built build/web`.

- [ ] **Step 3: Smoke-test the functions against the local database with fixture secrets**

These are made-up secrets for this machine only. Nothing here reaches Razorpay, because only `payments-create-order` calls Razorpay and it is exercised with a probe only.

```bash
SMOKE_ENV="$(mktemp -d)/p6-smoke.env"
printf 'RAZORPAY_KEY_ID=rzp_test_local\nRAZORPAY_KEY_SECRET=local_secret\nRAZORPAY_WEBHOOK_SECRET=whsec_local\n' > "$SMOKE_ENV"
supabase functions serve --env-file "$SMOKE_ENV"     # run in the background
```

In another shell:

```bash
eval "$(supabase status -o env | grep -E '^(ANON_KEY|API_URL)=')"
FN="$API_URL/functions/v1"
docker exec -i supabase_db_pasala_farm psql -U postgres -v ON_ERROR_STOP=1 <<'SQL'
insert into auth.users (id, email) values ('a6ffffff-0000-0000-0000-000000000001','p6-smoke@example.com');
insert into public.properties (id, name, slug) values ('a6ffffff-0000-4000-8000-000000000001','P6 Smoke','p6-smoke');
insert into public.units (id, property_id, name, capacity_base, capacity_max)
  values ('a6ffffff-0000-4000-8000-000000000011','a6ffffff-0000-4000-8000-000000000001','Smoke Cottage',2,2);
insert into public.reservations (id, unit_id, period, kind, status, customer_id, guests, quote, hold_expires_at) values
  ('a6ffffff-0000-4000-8000-000000000031','a6ffffff-0000-4000-8000-000000000011',
   public.build_period('a6ffffff-0000-4000-8000-000000000011', current_date + 100, current_date + 101),
   'booking','hold','a6ffffff-0000-0000-0000-000000000001',2,'{"total":1000}', now() + interval '15 minutes'),
  ('a6ffffff-0000-4000-8000-000000000032','a6ffffff-0000-4000-8000-000000000011',
   public.build_period('a6ffffff-0000-4000-8000-000000000011', current_date + 110, current_date + 111),
   'booking','hold','a6ffffff-0000-0000-0000-000000000001',2,'{"total":1000}', now() + interval '15 minutes');
set role service_role;
select public.payment_order_open('a6ffffff-0000-4000-8000-000000000031','a6ffffff-0000-0000-0000-000000000001','advance',1000,'order_smoke_1');
select public.payment_order_open('a6ffffff-0000-4000-8000-000000000032','a6ffffff-0000-0000-0000-000000000001','advance',1000,'order_smoke_2');
SQL

# 1. The probe switches the database live.
curl -s -X POST "$FN/payments-create-order" -H "Authorization: Bearer $ANON_KEY" \
  -H 'Content-Type: application/json' -d '{"probe":true}'
# expect {"configured":true,"key_id":"rzp_test_local"}

# 2. A signed payment.captured webhook settles order_smoke_1; a second delivery is a duplicate.
BODY='{"event":"payment.captured","payload":{"payment":{"entity":{"id":"pay_smoke_1","order_id":"order_smoke_1","amount":100000}}}}'
SIG=$(printf '%s' "$BODY" | openssl dgst -sha256 -hmac whsec_local | awk '{print $NF}')
for i in 1 2; do
  curl -s -X POST "$FN/payments-webhook" -H 'Content-Type: application/json' \
    -H "X-Razorpay-Signature: $SIG" -H 'X-Razorpay-Event-Id: evt_smoke_1' -d "$BODY"; echo
done
# expect {"status":"processed","outcome":"settled:paid"} then {"status":"duplicate"}
curl -s -o /dev/null -w '%{http_code}\n' -X POST "$FN/payments-webhook" \
  -H 'X-Razorpay-Signature: 00' -d "$BODY"          # expect 401

# 3. A signed verify settles order_smoke_2.
VSIG=$(printf '%s' 'order_smoke_2|pay_smoke_2' | openssl dgst -sha256 -hmac local_secret | awk '{print $NF}')
curl -s -X POST "$FN/payments-verify" -H "Authorization: Bearer $ANON_KEY" -H 'Content-Type: application/json' \
  -d "{\"razorpay_order_id\":\"order_smoke_2\",\"razorpay_payment_id\":\"pay_smoke_2\",\"razorpay_signature\":\"$VSIG\"}"
# expect {"configured":true,"outcome":"paid","reservation_id":"a6ffffff-…-000000000032","kind":"advance","refund":null}

docker exec -i supabase_db_pasala_farm psql -U postgres -c "
  select (select live from public.payment_gateway_config) as live,
         (select string_agg(status::text, ',' order by id) from public.reservations
           where id::text like 'a6ffffff-%') as reservations,
         (select string_agg(gateway || ':' || gateway_ref, ',' order by gateway_ref) from public.payments
           where reservation_id::text like 'a6ffffff-%') as payments;"
# expect: live t | confirmed,confirmed | razorpay:pay_smoke_1,razorpay:pay_smoke_2
```

Stop `supabase functions serve`, start it again without `--env-file`, and switch live off, then clean up:

```bash
curl -s -X POST "$FN/payments-create-order" -H "Authorization: Bearer $ANON_KEY" \
  -H 'Content-Type: application/json' -d '{"probe":true}'      # expect {"configured":false}
docker exec -i supabase_db_pasala_farm psql -U postgres -v ON_ERROR_STOP=1 <<'SQL'
select live from public.payment_gateway_config;                  -- expect f
delete from public.payment_webhook_events where event_id = 'evt_smoke_1';
delete from public.reservations where id::text like 'a6ffffff-%'; -- payments and payment_orders cascade
delete from public.units where id = 'a6ffffff-0000-4000-8000-000000000011';
delete from public.properties where id = 'a6ffffff-0000-4000-8000-000000000001';
delete from auth.users where id = 'a6ffffff-0000-0000-0000-000000000001';
SQL
rm -f "$SMOKE_ENV"
```

If a step answers differently, fix the cause in the owning task's files and rerun that task's tests before continuing.

- [ ] **Step 4: The guest still books through the mock (no secrets)**

Run from `e2e/`: `./build-app.sh && npx playwright test tests/guest.spec.ts tests/smoke.spec.ts`
Expected: PASS. With no secrets set, the app gets `{"configured":false}`, or cannot reach the functions at all, and pays through `MockGateway` as before. `select live from public.payment_gateway_config` is still `f`.

- [ ] **Step 5: Document how to switch Razorpay on**

In `README.md`, replace the whole block from `**Payments (phase 2 seam, still stubbed)**` down to and including its second bullet (ending `them.`) with:

````markdown
**Online payments (Razorpay)**

- Guests pay the booking advance and their checkout balance through
  Razorpay: Checkout.js on the web, `razorpay_flutter` on Android and iOS.
  The app holds only the public key id. Three Edge Functions hold the
  secrets and do the work:
  - `payments-create-order` checks the amount (the advance rule or the
    balance due) as the signed-in guest and creates the Razorpay order;
  - `payments-verify` checks Checkout's signature and confirms the booking
    (or checks the guest out) on the server;
  - `payments-webhook` handles `payment.captured`, `payment.failed` and
    `refund.processed`, once each.

  A payment that cannot be applied (the hold was released, the booking
  was already paid, the balance changed) is refunded automatically.
- **Without secrets nothing changes.** The functions answer
  `{"configured": false}`, and the app pays through `MockGateway` as before.
  With secrets set, the database refuses a guest's mock confirmation
  (P0036), so a live deployment cannot be booked for free.

To switch it on (test keys first):

```bash
supabase secrets set RAZORPAY_KEY_ID=rzp_test_xxx RAZORPAY_KEY_SECRET=xxx RAZORPAY_WEBHOOK_SECRET=xxx
supabase functions deploy payments-create-order payments-verify payments-webhook
# Switch the database to live now rather than at the first payment:
curl -X POST "https://<project-ref>.supabase.co/functions/v1/payments-create-order" \
  -H "Authorization: Bearer <anon key>" -H "Content-Type: application/json" \
  -d '{"probe": true}'     # → {"configured":true,"key_id":"rzp_test_xxx"}
```

In the Razorpay Dashboard (Account & Settings → Webhooks), add the URL
`https://<project-ref>.supabase.co/functions/v1/payments-webhook`. Give it
the same secret as `RAZORPAY_WEBHOOK_SECRET`, and the events
`payment.captured`, `payment.failed` and `refund.processed`. Leave
automatic capture on (the default).

To switch it off, run
`supabase secrets unset RAZORPAY_KEY_ID RAZORPAY_KEY_SECRET RAZORPAY_WEBHOOK_SECRET`
and then the probe again. Refunds for cancelled bookings are still made by
hand in the Razorpay Dashboard.

To run it locally, put the three variables in `supabase/functions/.env`
(gitignored) and run
`supabase functions serve --env-file supabase/functions/.env`. Razorpay can
reach a local webhook only through a tunnel. Never put the key secret in
`--dart-define`, the database or git.

**Not yet verified against a real Razorpay account.** The functions are
tested with signature fixtures and a mocked Razorpay API only. See
`docs/STATUS.md`.
````

In the `make` targets table, add after the `make test` row:

```markdown
| `make functions-test` | `deno test supabase/functions/` — run the Edge Function tests |
```

Under "Known limitations" → "From phase 2", replace the bullet `**Payment is still a mock gateway.** …` (all four lines) with:

```markdown
- **Online payments are off until Razorpay secrets are set, and have not been
  run against a real Razorpay account.** See "Online payments (Razorpay)"
  above. Refunds for cancelled bookings are made by hand in the Razorpay
  Dashboard.
```

In `docs/STATUS.md`:
- In "What works today", change `only a mocked payment and unsent notifications (see below).` to `only unsent notifications and, until Razorpay secrets are set, a mocked payment (see below).`
- Replace the whole "What is stubbed" bullet that starts `- **Payment is a mock.**` with:

```markdown
- **Payment is a mock until Razorpay secrets are set.** Without the
  `RAZORPAY_KEY_ID`/`RAZORPAY_KEY_SECRET` Edge Function secrets, `MockGateway`
  makes up a reference and charges nothing, exactly as before. Every
  environment this repo has run in is in that state. The real path (P6)
  exists and is tested against fixtures:
  - `payments-create-order`, `payments-verify` and `payments-webhook` create,
    verify and settle Razorpay orders on the server;
  - the app opens Checkout.js or the native SDK with only the public key id;
  - the database refuses a guest's mock confirmation while the secrets are
    set (P0036).

  It has never been run against a real Razorpay account.
```

- In item 1 of "What is needed from the owner to go live", replace `Every booking made against a deployed build still runs through` / `` `MockGateway`, which fabricates a success reference and charges nothing. `` with `` Until the account's keys are set as Edge Function secrets (README, "Online payments (Razorpay)"), every booking runs through `MockGateway`, which makes up a success reference and charges nothing. ``

- [ ] **Step 6: Commit**

```bash
git add README.md docs/STATUS.md
git commit -m "$(cat <<'EOF'
docs(payments): how to switch Razorpay online payments on

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

## Self-Review

**1. Spec coverage.**

| Spec item | Task(s) |
|---|---|
| Decision 1: one account, secrets only in Edge Functions | 5 (`readConfig`), 6–8 (`index.ts`), 13 (docs) |
| Decision 2: three functions, `deno.json` each, `_shared` reusable by P8 | 5–8 |
| Decision 3: safe default, `{configured:false}`; webhook 503 | 6, 7, 8 (tests); 13 Step 4 |
| Decision 4: fallback to the mock on not configured, 404, foreign 5xx, network; verify is "not confirmed yet" | 9 (tests), 10 |
| Decision 5: live switch, sync on every create-order call, probe, P0036 | 1 (table), 3 (switch + P0036), 6 (sync), 13 Step 3 |
| Decision 6: settle on signature or webhook; the app's confirm is idempotent | 3, 7, 8, 12 |
| Decision 7: settle as the guest, `razorpay` label only under `service_role`, settings restored | 3 (tests 8, 10–12) |
| Decision 8: amount rules, paise, INR | 2 |
| Decision 9: no hold extension; unswept expired hold confirms | 2 (test 32), 3 (test 21) |
| Decision 10: unapplied → automatic refund, retried until recorded | 3, 7 (`refundIfNeeded`), 8 |
| Decision 11: refunds only on `payment_orders` | 4 (tests 15–17) |
| Decision 12: webhook events, idempotency, unknown orders ignored | 4 (ledger), 8 |
| Decision 13: automatic capture; the signature is enough | 7 |
| Decision 14: only the guest pays online | 2 (tests 18, 23), 3 (test 33) |
| Decision 15: Checkout.js on web, `razorpay_flutter` on mobile, unsupported elsewhere | 11 |
| Decision 16: no secret in the app, dart-defines removed | 10 |
| Decision 17: the hold ticker waits for an open payment | 12 |
| Decision 18: verify needs a JWT, settles on the signature | 7, 8 (`verify_jwt` only off for the webhook) |
| Data model, RLS, grants, allow-list | 1, 4 (isolation) |
| App: models, seam, gateway, errors, screens, pubspec | 1, 9–12 |
| Testing: pgTAP 45, Deno, Flutter, integration | 1–13 |

**2. Placeholder scan.** No "TBD" or "similar to Task N". Every code step shows its code. The one prose-only edit is the removal in Task 10 Step 3, which names its exact start and end.

**3. Type consistency.**
- SQL: `payment_order_open(uuid, uuid, payment_kind, numeric, text)` is the same in Tasks 1, 2 and 6 (`p_reservation`, `p_customer`, `p_kind`, `p_amount`, `p_razorpay_order_id`). `payment_order_settle(text, text)` returns the keys `SettleResult` declares (built by `payment_order_json`), as do `payment_order_refunded(text, text, numeric)` (amount in rupees; the functions divide paise by 100) and `payment_webhook_begin(text, text, jsonb) returns boolean`.
- TS ↔ Dart: `CreateOrderResponse` fields `key_id, order_id, amount (paise), currency, name, description, reservation_id, prefill` match `RazorpayOrder.fromJson`. `VerifyResponse` `outcome` / `reservation_id` / `refund` match `VerifyResult.fromJson`. The error body `{error, code, message}` matches `failureFromFunction`.
- Dart: `PaymentGateway.charge({reservationId, amount, purpose})` is the same everywhere. `PaymentOrderSource.createOrder({reservationId, amount, purpose})` / `verify({orderId, paymentId, signature})` match the fakes. `CheckoutSucceeded({paymentId, orderId, signature})` matches both windows.

**4. Review Focus.** All five lines have their owning tests: Tasks 3, 7, 8, 9 and 12, as listed in the section.
