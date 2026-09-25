# Email and SMS Delivery (P7) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver the booking emails and SMS that `public.outbox` already queues. A Supabase Edge Function `outbox-dispatch`, which pg_cron calls every minute, sends email through Resend and SMS through MSG91, retries with backoff up to 5 attempts, and does a dry run (sends nothing, marks rows `dry_run`) when the provider keys are not set. The Outbox screen shows the real delivery state for each channel.

**Architecture:** The SQL side owns all state changes. Four `security definer` functions work on the queue: `claim_outbox_batch` (skip-locked claim, 5-minute lease, notification settings re-checked), `complete_outbox_message` (the outcome, backoff and attempt limit), `record_outbox_dispatch_run` (a heartbeat per channel), plus the app-facing `outbox_delivery_status` and `retry_outbox_message`. A tick function reads the function URL and the service key from Vault and POSTs through `pg_net`. The Deno function is small and fully dependency-injected: config → store (PostgREST RPCs) → senders (Resend, MSG91) → `dispatchOnce`. Every piece is tested with stub `fetch` functions, so no test touches the network. The Flutter Outbox screen swaps its permanent "no provider" banner for a delivery status panel, adds retry and sent details, and gives owners and admins a Send again button.

**Tech Stack:** Supabase Postgres 17 (plpgsql, RLS, pg_cron, pg_net, Vault, pgTAP via `supabase test db`), Deno 2.9 (Supabase Edge Functions, `jsr:@std/assert`), Flutter 3.38 / Dart 3.10, Riverpod 3.3, go_router 17.

**Spec:** `docs/superpowers/specs/2026-09-25-p7-email-and-sms-delivery-design.md`

## Global Constraints

- One migration, `supabase/migrations/0056_email_sms_delivery.sql`, created by Task 1. Tasks 2–4 edit it in place: each replaces a stub body or appends at the end. After every edit, rebuild with `supabase db reset` (re-runs every migration and `supabase/seed.sql`), then run pgTAP.
- One new pgTAP file, `supabase/tests/46_email_sms_delivery_test.sql`, built up section by section by Tasks 1–4. Each section relies on the state the earlier sections leave. Run it with `supabase test db supabase/tests/46_email_sms_delivery_test.sql`. The `select plan(N)` line is updated in every task.
- One new error code: **P0037**, raised as `outbox_not_in_flight` by `complete_outbox_message` and as `not_retryable` by `retry_outbox_message`. Other refusals reuse existing codes: P0002 (unknown row), P0020 (not a member, or wrong role), P0022 (suspended resort), 22023 (unknown outcome), 42501 (no execute grant), 23514 (bad mode).
- Every new `security definer` function has `set search_path = public, pg_temp`, is revoked from `public` and `anon`, and is added to the definer allow-list in `supabase/tests/37_tenancy_isolation_test.sql`. The allow-list gets exactly these seven names: `claim_outbox_batch`, `complete_outbox_message`, `record_outbox_dispatch_run`, `outbox_delivery_status`, `retry_outbox_message`, `outbox_template_context`, `outbox_dispatch_tick`. `outbox_dispatch_post` and `outbox_retry_delay` are not definer functions.
- Grants: `claim_outbox_batch`, `complete_outbox_message` and `record_outbox_dispatch_run` are executable by `service_role` only. `outbox_delivery_status` and `retry_outbox_message` are executable by `authenticated` only. `outbox_template_context`, `outbox_dispatch_post` and `outbox_dispatch_tick` are executable by no client role at all (`anon`, `authenticated` and `service_role` are all revoked).
- `render_template` is copied from its latest definition, `supabase/migrations/0045_resort_functions.sql` lines 1863–1935. `enqueue_outbox_message` and `enqueue_reservation_outbox` are not changed.
- The attempt limit is **5**. Backoff is `2^(attempts-1)` minutes (1, 2, 4, 8). The lease is **5 minutes**. The batch limit is clamped to 1..200: the SQL default is 25, and the function's `OUTBOX_BATCH_SIZE` defaults to 50. The stale-sender warning shows after **10 minutes**.
- Vault secret names: `outbox_dispatch_url`, `outbox_dispatch_key`. The pg_cron job is named `outbox-dispatch` and runs every minute (`* * * * *`).
- Edge Function secrets: `RESEND_API_KEY`, `RESEND_FROM` (a bare address), `MSG91_AUTH_KEY`, `MSG91_SENDER_ID` (optional), `MSG91_TEMPLATES` (a JSON object mapping template name to MSG91 template id) and `OUTBOX_BATCH_SIZE` (optional). `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are provided by Supabase. **Never commit a secret.** `supabase/functions/.env` is already ignored by the root `.gitignore` rule `.env`; check with `git check-ignore supabase/functions/.env`.
- The Edge Function lives only under `supabase/functions/outbox-dispatch/`, with its own `deno.json`. There is no shared `_shared` folder (other projects add functions in parallel). Run its tests with `(cd supabase/functions/outbox-dispatch && deno test)`, which grants no permissions. Tests must never reach Resend, MSG91 or any network: use `stubFetch` from `testing.ts`.
- pgTAP conventions: switch users with `set local role authenticated; set local request.jwt.claims to '{"sub":"<uuid>","role":"authenticated"}';`. `reset role` does **not** clear the claims, so follow it with `set local request.jwt.claims to '';`. Act as the dispatcher with `set local role service_role;` … `reset role;`.
- Dart: repositories wrap every call in `_guard`, which maps errors through `mapPostgrestError` (`lib/core/errors.dart`). Widget tests use fakes from `test/support/` and never a real `SupabaseClient`. Every `ProviderScope` in the new widget tests passes `retry: (_, _) => null`, because Riverpod 3 otherwise retries a failed provider with backoff.
- UI copy, exact:
  - Status panel lines: `Email: sending via Resend`, `SMS: sending via MSG91`, `<Channel>: dry run, nothing is sent`, `<Channel>: not connected, messages stay queued`, `<Channel>: waiting for the sender to run`. Channel labels are `Email`, `SMS` and `WhatsApp`.
  - Run line: `Last checked <since>.`, `The sender last ran <since>. Pending messages are waiting.`, `The sender has not run yet. Pending messages wait until it does.`. `<since>` is `just now`, `<n> min ago`, `<n> h ago` or `<n> day(s) ago`.
  - Status error: `Delivery status is unavailable right now.`
  - Sections: `Pending (n)`, `Failed (n)`, `Dry run (n)`, `Skipped (n)`, `Sent (n)`, in that order.
  - Row lines: `Attempt <n> of 5 failed · next try <HH:mm>`, `Failed after <n> attempt(s)`, `Sent <d MMM yyyy, HH:mm>`.
  - Button `Send again`. Snackbar `Queued to send again.` P0037 copy: `Only failed or dry-run messages can be sent again.`
  - Notification settings card: `Turn a channel off to stop sending it for this resort. Messages already queued for that channel are skipped too. The Outbox shows what was sent.`
  - Admin More Outbox subtitle: `Booking emails and SMS, and whether each was sent`.
- Commands:
  - `flutter test <path>`, `flutter test`, and `flutter analyze`. The analyze baseline is 2 infos in `service_request_screen.dart`, and there must be no new issues.
  - Never run `dart format` on whole directories or on files that already existed. Format only the lines you write.
  - Revert SDK-only `pubspec.lock` bumps (`git checkout pubspec.lock`).
- Three pgTAP failures are known and appear only between 00:00 and 05:30 IST (25/9, 26/3, 34/2). Everything else must pass.
- Every commit message ends with a blank line and `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Use `git commit -m "<subject>" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"`. Do not push.

## Review Focus

1. **A run dies after Resend accepted an email but before `complete_outbox_message` recorded it.** The lease expires and the row is claimed again. The guest expects one email, not two. Owning tests: Task 5 (the `Idempotency-Key` header is the outbox row id), Task 2 (the lease runs out, and the row comes back on its next attempt), Task 7 (a failed complete is counted and the run carries on).
2. **Guest phone numbers typed any way people type them** (`+91 98765 43210`, `098765 43210`, `0091…`), and foreign or garbage numbers. An Indian mobile must still get its SMS. Anything else must fail at once with a readable reason, not burn five retries. Owning tests: Task 5 (`normalizeIndianMobile` table), Task 7 (an invalid number fails without calling MSG91).
3. **MSG91 answers HTTP 200 with `"type":"error"`** (bad template, DLT mismatch, no balance). The row must show as failed with MSG91's message, never as sent. Owning test: Task 5.
4. **An owner turns SMS off while messages are already queued.** A reasonable owner expects those messages not to go out. Owning test: Task 2 (the claim marks the queued SMS `skipped` with the disabled reason).
5. **The sender silently stops.** Examples: the Vault secrets were never set, a `supabase db reset` removed them, or the function is not deployed. Staff must be told on the Outbox screen, not shown a calm "pending" list forever. Owning tests: Task 4 (`not_running` before any run, and the run time is recorded), Task 8 (a never-run or 10-minute-stale sender shows the warning line and icon).

## Plan decisions (where the spec is silent or leaves a choice)

- Task 1 fixes the whole contract. Every new function exists, with its final signature, grants and search_path, as a stub that raises `0A000 not_implemented`. `render_template` keeps working unchanged until Task 2. `outbox_retry_delay` starts as a plpgsql stub and becomes a SQL function in Task 3 (it is edited in place, so the language change is fine).
- The tick is split in two. `outbox_dispatch_tick()` reads Vault, and `outbox_dispatch_post(url, key)` does the null checks and the `net.http_post`. The tests can then check the POST without writing Vault secrets, which may belong to a developer's local setup.
- `46_email_sms_delivery_test.sql` starts with `delete from public.outbox; delete from public.outbox_channel_status;` inside its transaction. The seed's confirmed booking queues outbox rows, and those would otherwise be claimed too.
- Cross-resort refusals for the new functions (`retry_outbox_message`, `outbox_delivery_status`) are tested in file 46. `37_tenancy_isolation_test.sql` only gains the allow-list names, so its `plan(77)` stays as it is. Other gap projects edit the same file.
- The Deno test doubles live in `supabase/functions/outbox-dispatch/testing.ts` (stub fetch, created in Task 1, used by Tasks 5–7) and `fakes.ts` (store and senders, created in Task 7). Neither matches Deno's test-file pattern, and neither is imported by `index.ts`, so neither is deployed.
- `deno.lock` is committed next to `deno.json` so that `@std/assert` resolves the same way everywhere.
- The Outbox screen takes an optional `clock` parameter (`DateTime Function()?`; null means `DateTime.now`) so tests can pin "now". The route keeps building `const OutboxScreen()`.

## Execution tracks

After Task 1, three tracks share no files and can run in parallel, for example in three worktrees branched from Task 1's commit and merged back before Task 10. The Deno and app tracks never need a database: they use `testing.ts`/`fakes.ts` and `FakeOutboxSource`.

| Task | Track | Depends on | Files it owns |
|---|---|---|---|
| 1 Interface contract | all | none | `0056` (schema, stubs, grants), `46` (fixtures + contract), `37` (allow-list), `outbox_message.dart`, `channel_delivery.dart`, `outbox_repository.dart`, `providers.dart`, `outbox_screen.dart` (status switch only), `errors.dart`, `fake_outbox_source.dart`, `outbox_screen_test.dart` (fake swap), `outbox_message_test.dart`, `channel_delivery_test.dart`, `errors_test.dart`, `outbox-dispatch/{deno.json,deno.lock,types.ts,util.ts,testing.ts,util_test.ts}` |
| 2 Template context and claiming | DB | 1 | `0056`, `46` |
| 3 Completing, backoff and Send again | DB | 2 | `0056`, `46` |
| 4 Delivery status, heartbeat and cron tick | DB | 3 | `0056`, `46` |
| 5 Resend and MSG91 senders | Deno | 1 | `resend.ts`, `msg91.ts`, `resend_test.ts`, `msg91_test.ts` |
| 6 Config and PostgREST store | Deno | 1 | `config.ts`, `store.ts`, `config_test.ts`, `store_test.ts` |
| 7 Dispatch, handler, wiring and docs | Deno | 5, 6 | `dispatch.ts`, `handler.ts`, `deps.ts`, `index.ts`, `fakes.ts`, `dispatch_test.ts`, `handler_test.ts`, `deps_test.ts`, `docs/email-and-sms-delivery.md`, `README.md`, `docs/STATUS.md` |
| 8 Delivery status panel | App | 1 | `delivery_status_panel.dart`, `delivery_status_panel_test.dart` |
| 9 Outbox screen, Send again and copy | App | 8 | `outbox_screen.dart`, `outbox_screen_test.dart`, `notification_settings_screen.dart`, `notification_settings_screen_test.dart`, `notification_settings.dart` (doc comment), `admin_more_screen.dart` |
| 10 Integration | all | 2–9 | none (verification only) |

- The database track is strictly sequential: Tasks 2–4 share one migration file, one test file and one local Postgres.
- Deno track: Tasks 5 and 6 run in parallel. Task 7 waits for both.
- App track: Task 9 waits for Task 8.

---

## File Structure

**Database**
- Create `supabase/migrations/0056_email_sms_delivery.sql`. It adds the `dry_run` status and the new `outbox` columns (with their index), creates `outbox_channel_status`, and defines `outbox_retry_delay`, `outbox_template_context`, `render_template` (the copy), `claim_outbox_batch`, `complete_outbox_message`, `record_outbox_dispatch_run`, `outbox_delivery_status`, `retry_outbox_message`, `outbox_dispatch_post` and `outbox_dispatch_tick`. It also sets the grants and schedules the cron job.
- Create `supabase/tests/46_email_sms_delivery_test.sql`.
- Modify `supabase/tests/37_tenancy_isolation_test.sql` (definer allow-list only).

**Edge Function** (`supabase/functions/outbox-dispatch/`)
- `deno.json`, `deno.lock`: import map (`@std/assert`) and tasks.
- `types.ts`: every shared type (the contract with the SQL and between modules).
- `util.ts`: `safeJson`, `clip`, `errorText`, `isRetryableStatus`.
- `testing.ts`: `stubFetch`, `jsonResponse` (test-only).
- `resend.ts`: `ResendEmailSender`, `displayName`, `RESEND_URL`.
- `msg91.ts`: `Msg91SmsSender`, `normalizeIndianMobile`, `smsVars`, `MSG91_FLOW_URL`, `DLT_VAR_MAX`.
- `config.ts`: `loadConfig`, `parseBatchSize`, `ConfigError`.
- `store.ts`: `RestOutboxStore`, `outcomeArgs`, `StoreError`.
- `dispatch.ts`: `DispatchDeps`, `channelModes`, `deliver`, `dispatchOnce`.
- `handler.ts`: `handleRequest`, `bearerMatches`, `timingSafeEqual`.
- `deps.ts`: `buildDeps`.
- `index.ts`: `Deno.serve` only.
- `fakes.ts`: `FakeStore`, `FakeEmailSender`, `FakeSmsSender`, `liveConfig`, `dryConfig`, `emailRow`, `smsRow` (test-only).
- Tests: `util_test.ts`, `resend_test.ts`, `msg91_test.ts`, `config_test.ts`, `store_test.ts`, `dispatch_test.ts`, `handler_test.ts`, `deps_test.ts`.

**App**
- Modify `lib/data/models/outbox_message.dart`: `OutboxStatus.dryRun`, `outboxStatusFromDb`, `outboxMaxAttempts`, `nextAttemptAt`, `lastAttemptAt`.
- Create `lib/data/models/channel_delivery.dart`: `DeliveryMode`, `deliveryModeFromDb`, `ChannelDelivery`.
- Modify `lib/data/repositories/outbox_repository.dart`: `OutboxSource.deliveryStatus`, `OutboxSource.retry`.
- Modify `lib/features/outbox/providers.dart`: `outboxDeliveryStatusProvider`.
- Modify `lib/core/errors.dart`: `NotRetryable`, P0037.
- Create `lib/features/outbox/delivery_status_panel.dart`: `DeliveryStatusPanel` and the pure line helpers.
- Modify `lib/features/outbox/outbox_screen.dart`: panel, sections, row lines, Send again, refresh.
- Modify `lib/features/owner/notification_settings_screen.dart`, `lib/data/models/notification_settings.dart` (doc comment) and `lib/features/admin/admin_more_screen.dart`: copy.
- Create `test/support/fake_outbox_source.dart`, `test/data/channel_delivery_test.dart` and `test/features/outbox/delivery_status_panel_test.dart`. Modify `test/data/outbox_message_test.dart`, `test/core/errors_test.dart`, `test/features/outbox/outbox_screen_test.dart` and `test/features/owner/notification_settings_screen_test.dart`.

**Docs**
- Create `docs/email-and-sms-delivery.md`. Modify `README.md` (outbox section, out-of-scope bullet, known-limitations bullet) and `docs/STATUS.md` (the outbox bullet and item 3).

---

## Phase 0: Interface

### Task 1: Interface contract (schema, function stubs, Dart API, Deno types)

**Track:** all. Every later task depends on it.

**Files:**
- Create: `supabase/migrations/0056_email_sms_delivery.sql`
- Create: `supabase/tests/46_email_sms_delivery_test.sql`
- Modify: `supabase/tests/37_tenancy_isolation_test.sql` (definer allow-list, around line 431)
- Modify: `lib/data/models/outbox_message.dart` (whole file)
- Create: `lib/data/models/channel_delivery.dart`
- Modify: `lib/data/repositories/outbox_repository.dart` (whole file)
- Modify: `lib/features/outbox/providers.dart` (whole file)
- Modify: `lib/features/outbox/outbox_screen.dart:27-44` (`_statusLabel`, `_statusOrder` only)
- Modify: `lib/core/errors.dart` (new class after `AlreadyDispatched`; one new arm after `'P0031'`)
- Create: `test/support/fake_outbox_source.dart`
- Modify: `test/features/outbox/outbox_screen_test.dart:1-31` (use the shared fake)
- Test: `test/data/outbox_message_test.dart`, `test/data/channel_delivery_test.dart`, `test/core/errors_test.dart`
- Create: `supabase/functions/outbox-dispatch/deno.json`, `types.ts`, `util.ts`, `testing.ts`, `util_test.ts` (and the generated `deno.lock`)

**Interfaces:**
- Consumes: `public.outbox`, `public.outbox_channel`, `public.outbox_status` (0017); `public.notification_settings` (0028/0044); `public.assert_resort_role(uuid, boolean, variadic resort_role[])` (0043); `render_template` (0045); `mapPostgrestError`, `supabaseProvider`, `currentResortProvider`.
- Produces (SQL; later tasks replace only bodies):
  - enum value `public.outbox_status` `'dry_run'`
  - columns `public.outbox.next_attempt_at timestamptz not null default now()`, `last_attempt_at timestamptz`, `provider_message_id text`; index `outbox_due_idx`
  - table `public.outbox_channel_status (channel public.outbox_channel pk, mode text check in ('live','dry_run'), provider text not null, detail text, last_run_at timestamptz not null)`
  - `public.outbox_retry_delay(p_attempts int) returns interval`
  - `public.outbox_template_context(p_reservation_id uuid) returns jsonb`
  - `public.claim_outbox_batch(p_limit int default 25) returns table (id uuid, property_id uuid, reservation_id uuid, channel public.outbox_channel, recipient text, template text, subject text, body text, attempts int, vars jsonb)`
  - `public.complete_outbox_message(p_id uuid, p_outcome text, p_error text default null, p_provider_id text default null) returns public.outbox_status`
  - `public.record_outbox_dispatch_run(p_channels jsonb) returns void`
  - `public.outbox_delivery_status(p_property uuid) returns table (channel public.outbox_channel, mode text, provider text, detail text, last_run_at timestamptz)`
  - `public.retry_outbox_message(p_message uuid) returns void`
  - `public.outbox_dispatch_post(p_url text, p_key text) returns text`
  - `public.outbox_dispatch_tick() returns text`
- Produces (Dart):
  - `enum OutboxStatus { pending, sent, failed, skipped, dryRun }`, `OutboxStatus outboxStatusFromDb(String)`, `const outboxMaxAttempts = 5`
  - `OutboxMessage` gains `DateTime? nextAttemptAt`, `DateTime? lastAttemptAt` (constructor params of the same names)
  - `enum DeliveryMode { live, dryRun, unavailable, notRunning }`, `DeliveryMode deliveryModeFromDb(String)`
  - `class ChannelDelivery { OutboxChannel channel; DeliveryMode mode; String? provider; String? detail; DateTime? lastRunAt }` with a `const` constructor and `fromJson`
  - `abstract class OutboxSource { Future<List<OutboxMessage>> messages(String propertyId); Future<List<ChannelDelivery>> deliveryStatus(String propertyId); Future<void> retry(String messageId); }`
  - `outboxDeliveryStatusProvider`: `FutureProvider.family<List<ChannelDelivery>, String>`
  - `class NotRetryable extends BookingFailure` (P0037)
  - `test/support/fake_outbox_source.dart`: `FakeOutboxSource` with `rows`, `statuses`, `error`, `statusError`, `retryError`, `listedPropertyIds`, `statusPropertyIds`, `retried`
- Produces (Deno, `supabase/functions/outbox-dispatch/`):
  - `types.ts`: `Channel`, `ClaimedMessage`, `Outcome`, `SendResult`, `EmailMessage`, `EmailSender`, `SmsMessage`, `SmsSender`, `ChannelMode`, `OutboxStore`, `DispatchSummary`, `FetchFn`, `EmailConfig`, `SmsConfig`, `Setup<T>`, `DispatchConfig`
  - `util.ts`: `safeJson(text): Record<string, unknown> | null`, `clip(text, max = 1000): string`, `errorText(e): string`, `isRetryableStatus(status): boolean`
  - `testing.ts`: `stubFetch(answers: Array<Response | Error>): { fetch: FetchFn; calls: RecordedCall[] }`, `jsonResponse(status, body): Response`, `interface RecordedCall { url; method; headers (lower-case keys); body (parsed JSON) }`

- [ ] **Step 1: Record the baseline and check the local stack**

```bash
flutter analyze 2>&1 | tail -3
```
Expected: `2 issues found`, both infos in `lib/features/stay/service_request_screen.dart`. Note the exact count; no task may add to it.

```bash
supabase status >/dev/null 2>&1 || supabase start
psql postgresql://postgres:postgres@127.0.0.1:54322/postgres -Atc \
  "select extname from pg_extension where extname in ('pg_cron','pg_net','supabase_vault') order by 1"
```
Expected: three lines, `pg_cron`, `pg_net` and `supabase_vault`. If `supabase_vault` is missing, carry on: `outbox_dispatch_tick` is written to answer `not_configured` without Vault. Say so in the task report.

```bash
psql postgresql://postgres:postgres@127.0.0.1:54322/postgres -Atc \
  "begin; set local role service_role; create temp table p7_probe(x int); select 'service_role ok'; rollback;"
deno --version | head -1
```
Expected: `service_role ok` and `deno 2.9.x`.

- [ ] **Step 2: Write the pgTAP fixtures and contract section**

Create `supabase/tests/46_email_sms_delivery_test.sql`:

```sql
-- P7: email and SMS delivery (0056_email_sms_delivery.sql). Sections are
-- added task by task; each relies on the state the earlier ones leave.
begin;
select plan(20);

-- === fixtures ===============================================================
-- The seed's confirmed booking queued outbox rows of its own; clear them
-- (inside this transaction) so every claim below sees only this file's rows.
delete from public.outbox;
delete from public.outbox_channel_status;

insert into auth.users (id, email) values
  ('d7000000-0000-0000-0000-0000000000a1','p7-a-owner@example.com'),
  ('d7000000-0000-0000-0000-0000000000a2','p7-a-admin@example.com'),
  ('d7000000-0000-0000-0000-0000000000a3','p7-a-staff@example.com'),
  ('d7000000-0000-0000-0000-0000000000a4','p7-a-acct@example.com'),
  ('d7000000-0000-0000-0000-0000000000b1','p7-b-owner@example.com'),
  ('d7000000-0000-0000-0000-0000000000c1','p7-asha@example.com'),
  ('d7000000-0000-0000-0000-0000000000c2','p7-bala@example.com');

-- Asha has a phone on file; Bala does not.
update public.profiles set full_name = 'Asha Rao', phone = '+91 98765 43210'
 where id = 'd7000000-0000-0000-0000-0000000000c1';
update public.profiles set full_name = 'Bala Iyer', phone = null
 where id = 'd7000000-0000-0000-0000-0000000000c2';

insert into public.properties (id, name, slug) values
  ('d7a00000-0000-4000-8000-000000000001','P7 Resort A','p7-a'),
  ('d7b00000-0000-4000-8000-000000000001','P7 Resort B','p7-b');

insert into public.resort_members (property_id, user_id, role) values
  ('d7a00000-0000-4000-8000-000000000001','d7000000-0000-0000-0000-0000000000a1','owner'),
  ('d7a00000-0000-4000-8000-000000000001','d7000000-0000-0000-0000-0000000000a2','admin'),
  ('d7a00000-0000-4000-8000-000000000001','d7000000-0000-0000-0000-0000000000a3','staff'),
  ('d7a00000-0000-4000-8000-000000000001','d7000000-0000-0000-0000-0000000000a4','accountant'),
  ('d7b00000-0000-4000-8000-000000000001','d7000000-0000-0000-0000-0000000000b1','owner');

insert into public.units (id, property_id, name, capacity_base, capacity_max) values
  ('d7a00000-0000-4000-8000-000000000011','d7a00000-0000-4000-8000-000000000001','Mango Cottage',2,4),
  ('d7b00000-0000-4000-8000-000000000011','d7b00000-0000-4000-8000-000000000001','Neem Villa',2,4);

-- Confirmed bookings queue their messages through the reservations trigger.
-- A (Asha, phone on file): booking_confirmation (email), booking_confirmation_sms,
--   booking_confirmation_whatsapp and payment_success (email) -- all pending.
-- B (Bala, no phone): the two emails pending; sms and whatsapp skipped.
insert into public.reservations (id, unit_id, period, kind, status, customer_id, guests) values
  ('d7a00000-0000-4000-8000-000000000021','d7a00000-0000-4000-8000-000000000011',
   tstzrange('2027-03-01 14:00+05:30','2027-03-02 11:00+05:30','[)'),
   'booking','confirmed','d7000000-0000-0000-0000-0000000000c1',2),
  ('d7b00000-0000-4000-8000-000000000021','d7b00000-0000-4000-8000-000000000011',
   tstzrange('2027-03-01 14:00+05:30','2027-03-02 11:00+05:30','[)'),
   'booking','confirmed','d7000000-0000-0000-0000-0000000000c2',2);

-- === Task 1: contract ========================================================
select is((select count(*)::int from public.outbox where status = 'pending'), 6,
  'fixture: six messages are pending (four for A, two for B)');

select enum_has_labels('public', 'outbox_status',
  array['pending','sent','failed','skipped','dry_run'],
  'outbox_status gains dry_run');

select has_column('public', 'outbox', 'next_attempt_at', 'outbox.next_attempt_at exists');
select col_not_null('public', 'outbox', 'next_attempt_at', 'next_attempt_at is required');
select has_column('public', 'outbox', 'last_attempt_at', 'outbox.last_attempt_at exists');
select has_column('public', 'outbox', 'provider_message_id', 'outbox.provider_message_id exists');

select has_table('public', 'outbox_channel_status', 'outbox_channel_status exists');
select ok((select relrowsecurity from pg_class
            where oid = 'public.outbox_channel_status'::regclass),
  'outbox_channel_status has RLS on');
select ok(not has_table_privilege('authenticated', 'public.outbox_channel_status', 'select')
      and not has_table_privilege('anon', 'public.outbox_channel_status', 'select'),
  'clients cannot read outbox_channel_status directly');

select has_function('public', 'claim_outbox_batch', array['integer'],
  'claim_outbox_batch(int) exists');
select has_function('public', 'complete_outbox_message', array['uuid','text','text','text'],
  'complete_outbox_message(uuid, text, text, text) exists');
select has_function('public', 'record_outbox_dispatch_run', array['jsonb'],
  'record_outbox_dispatch_run(jsonb) exists');
select has_function('public', 'outbox_delivery_status', array['uuid'],
  'outbox_delivery_status(uuid) exists');
select has_function('public', 'retry_outbox_message', array['uuid'],
  'retry_outbox_message(uuid) exists');
select has_function('public', 'outbox_template_context', array['uuid'],
  'outbox_template_context(uuid) exists');
select has_function('public', 'outbox_dispatch_post', array['text','text'],
  'outbox_dispatch_post(text, text) exists');
select has_function('public', 'outbox_dispatch_tick', array[]::name[],
  'outbox_dispatch_tick() exists');
select has_function('public', 'outbox_retry_delay', array['integer'],
  'outbox_retry_delay(int) exists');

-- Who may execute what: the dispatcher's three functions run only as
-- service_role, the app's two only as authenticated, the internals for
-- no client role at all.
select is(
  (select array_agg(fn || ':' || r order by fn, r)
     from unnest(array[
            'public.claim_outbox_batch(integer)',
            'public.complete_outbox_message(uuid,text,text,text)',
            'public.record_outbox_dispatch_run(jsonb)',
            'public.outbox_delivery_status(uuid)',
            'public.retry_outbox_message(uuid)',
            'public.outbox_template_context(uuid)',
            'public.outbox_dispatch_post(text,text)',
            'public.outbox_dispatch_tick()']) as fn,
          unnest(array['anon','authenticated','service_role']) as r
    where has_function_privilege(r, fn, 'execute')),
  array[
    'public.claim_outbox_batch(integer):service_role',
    'public.complete_outbox_message(uuid,text,text,text):service_role',
    'public.outbox_delivery_status(uuid):authenticated',
    'public.record_outbox_dispatch_run(jsonb):service_role',
    'public.retry_outbox_message(uuid):authenticated'],
  'execute grants: dispatcher functions for service_role, app functions for authenticated, internals for nobody');

select is(
  (select array_agg(p.proname::text order by p.proname)
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in ('claim_outbox_batch','complete_outbox_message',
                        'record_outbox_dispatch_run','outbox_delivery_status',
                        'retry_outbox_message','outbox_template_context',
                        'outbox_dispatch_tick')
      and p.prosecdef
      and p.proconfig @> array['search_path=public, pg_temp']),
  array['claim_outbox_batch','complete_outbox_message','outbox_delivery_status',
        'outbox_dispatch_tick','outbox_template_context',
        'record_outbox_dispatch_run','retry_outbox_message'],
  'the seven new definer functions pin their search_path');

select * from finish();
rollback;
```

- [ ] **Step 3: Run it to verify it fails**

Run: `supabase test db supabase/tests/46_email_sms_delivery_test.sql`
Expected: FAIL. The fixture line `delete from public.outbox_channel_status` errors with `relation "public.outbox_channel_status" does not exist`.

- [ ] **Step 4: Write the migration (schema, stubs, grants)**

Create `supabase/migrations/0056_email_sms_delivery.sql`:

```sql
-- Email and SMS delivery (P7). See
-- docs/superpowers/specs/2026-09-25-p7-email-and-sms-delivery-design.md
-- and docs/email-and-sms-delivery.md.
--
-- The outbox-dispatch Edge Function sends due outbox rows. pg_cron calls
-- outbox_dispatch_tick() every minute, which POSTs to the function with
-- the service role key it reads from Vault. The function claims rows with
-- claim_outbox_batch (one attempt each, 5-minute lease), sends email
-- through Resend and SMS through MSG91 -- or, without their keys, records
-- a dry run -- and reports each result with complete_outbox_message,
-- which owns the retry backoff and the five-attempt limit. WhatsApp rows
-- are never claimed and stay pending.
--
-- 'dry_run' is added to outbox_status here and used only inside function
-- bodies: a new enum value cannot be used in the transaction that adds it.

alter type public.outbox_status add value if not exists 'dry_run';

alter table public.outbox
  add column next_attempt_at     timestamptz not null default now(),
  add column last_attempt_at     timestamptz,
  add column provider_message_id text;

create index outbox_due_idx on public.outbox (next_attempt_at)
  where status = 'pending';

-- What the dispatcher found on its last run, per channel. Deployment
-- facts, not resort data, so no property_id. Read only through
-- outbox_delivery_status; written only by record_outbox_dispatch_run.
create table public.outbox_channel_status (
  channel     public.outbox_channel primary key,
  mode        text not null check (mode in ('live', 'dry_run')),
  provider    text not null,
  detail      text,
  last_run_at timestamptz not null
);

alter table public.outbox_channel_status enable row level security;
revoke all on public.outbox_channel_status from anon, authenticated, service_role;

-- ---------------------------------------------------------------------
-- outbox_retry_delay (Task 3 replaces this stub)

create function public.outbox_retry_delay(p_attempts int)
returns interval
language plpgsql
immutable
set search_path = public, pg_temp
as $$
begin
  raise exception using errcode = '0A000', message = 'not_implemented';
end;
$$;

-- ---------------------------------------------------------------------
-- outbox_template_context (Task 2 replaces this stub)

create function public.outbox_template_context(p_reservation_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  raise exception using errcode = '0A000', message = 'not_implemented';
end;
$$;

-- ---------------------------------------------------------------------
-- claim_outbox_batch (Task 2 replaces this stub)

create function public.claim_outbox_batch(p_limit int default 25)
returns table (id uuid, property_id uuid, reservation_id uuid,
               channel public.outbox_channel, recipient text, template text,
               subject text, body text, attempts int, vars jsonb)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  raise exception using errcode = '0A000', message = 'not_implemented';
end;
$$;

-- ---------------------------------------------------------------------
-- complete_outbox_message (Task 3 replaces this stub)

create function public.complete_outbox_message(
  p_id          uuid,
  p_outcome     text,
  p_error       text default null,
  p_provider_id text default null
) returns public.outbox_status
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  raise exception using errcode = '0A000', message = 'not_implemented';
end;
$$;

-- ---------------------------------------------------------------------
-- retry_outbox_message (Task 3 replaces this stub)

create function public.retry_outbox_message(p_message uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  raise exception using errcode = '0A000', message = 'not_implemented';
end;
$$;

-- ---------------------------------------------------------------------
-- record_outbox_dispatch_run (Task 4 replaces this stub)

create function public.record_outbox_dispatch_run(p_channels jsonb)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  raise exception using errcode = '0A000', message = 'not_implemented';
end;
$$;

-- ---------------------------------------------------------------------
-- outbox_delivery_status (Task 4 replaces this stub)

create function public.outbox_delivery_status(p_property uuid)
returns table (channel public.outbox_channel, mode text, provider text,
               detail text, last_run_at timestamptz)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  raise exception using errcode = '0A000', message = 'not_implemented';
end;
$$;

-- ---------------------------------------------------------------------
-- outbox_dispatch_post (Task 4 replaces this stub)

create function public.outbox_dispatch_post(p_url text, p_key text)
returns text
language plpgsql
set search_path = public, pg_temp
as $$
begin
  raise exception using errcode = '0A000', message = 'not_implemented';
end;
$$;

-- ---------------------------------------------------------------------
-- outbox_dispatch_tick (Task 4 replaces this stub)

create function public.outbox_dispatch_tick()
returns text
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  raise exception using errcode = '0A000', message = 'not_implemented';
end;
$$;

-- ---------------------------------------------------------------------
-- Grants. The dispatcher's three functions run only as service_role; the
-- app's two only as authenticated; the internals for no client role.

revoke execute on function public.claim_outbox_batch(int) from public, anon, authenticated;
grant  execute on function public.claim_outbox_batch(int) to service_role;
revoke execute on function public.complete_outbox_message(uuid, text, text, text) from public, anon, authenticated;
grant  execute on function public.complete_outbox_message(uuid, text, text, text) to service_role;
revoke execute on function public.record_outbox_dispatch_run(jsonb) from public, anon, authenticated;
grant  execute on function public.record_outbox_dispatch_run(jsonb) to service_role;

revoke execute on function public.outbox_delivery_status(uuid) from public, anon, service_role;
grant  execute on function public.outbox_delivery_status(uuid) to authenticated;
revoke execute on function public.retry_outbox_message(uuid) from public, anon, service_role;
grant  execute on function public.retry_outbox_message(uuid) to authenticated;

revoke execute on function public.outbox_template_context(uuid) from public, anon, authenticated, service_role;
revoke execute on function public.outbox_dispatch_post(text, text) from public, anon, authenticated, service_role;
revoke execute on function public.outbox_dispatch_tick() from public, anon, authenticated, service_role;
```

- [ ] **Step 5: Add the seven definer functions to the allow-list**

In `supabase/tests/37_tenancy_isolation_test.sql`, in the `array[...]` of the last `select is(...)` (the "every security definer function is on the reviewed allow-list" check), insert this block directly after the line `'report_collections','report_ledger','report_settlements','finance_summary',`:

```sql
        -- 0056: email and SMS delivery. claim/complete/record run only as
        -- service_role (the outbox-dispatch Edge Function);
        -- outbox_delivery_status asserts the caller's role at the resort
        -- it is given and retry_outbox_message at the message's resort;
        -- outbox_template_context and outbox_dispatch_tick run for no
        -- client role.
        'claim_outbox_batch','complete_outbox_message','record_outbox_dispatch_run',
        'outbox_delivery_status','retry_outbox_message','outbox_template_context',
        'outbox_dispatch_tick',
```

Leave `select plan(77);` as it is. No assertion is added.

- [ ] **Step 6: Rebuild and run the database tests**

```bash
supabase db reset
supabase test db supabase/tests/46_email_sms_delivery_test.sql
supabase test db supabase/tests/37_tenancy_isolation_test.sql
supabase test db supabase/tests/13_outbox_test.sql
supabase test db supabase/tests/24_notification_settings_test.sql
```
Expected: all PASS (46: 20/20).

- [ ] **Step 7: Write the failing Dart tests**

Append to `test/data/outbox_message_test.dart`, inside `main()` after the last test:

```dart
  test('parses a dry_run row and the retry timestamps', () {
    final message = OutboxMessage.fromJson(const {
      'id': 'm4',
      'reservation_id': 'r4',
      'channel': 'sms',
      'recipient': '+919876543210',
      'template': 'booking_confirmation_sms',
      'status': 'dry_run',
      'attempts': 1,
      'last_error': 'Dry run: MSG91_AUTH_KEY is not set',
      'created_at': '2026-08-01T10:00:00Z',
      'next_attempt_at': '2026-08-01T10:05:00Z',
      'last_attempt_at': '2026-08-01T10:00:30Z',
    });

    expect(message.status, OutboxStatus.dryRun);
    expect(message.nextAttemptAt, DateTime.utc(2026, 8, 1, 10, 5));
    expect(message.lastAttemptAt, DateTime.utc(2026, 8, 1, 10, 0, 30));
  });

  test('rows without retry timestamps parse them as null', () {
    final message = OutboxMessage.fromJson(const {
      'id': 'm5',
      'reservation_id': 'r5',
      'channel': 'email',
      'recipient': 'guest@example.com',
      'template': 'booking_confirmation',
      'status': 'pending',
      'attempts': 0,
      'created_at': '2026-08-01T10:00:00Z',
    });

    expect(message.nextAttemptAt, isNull);
    expect(message.lastAttemptAt, isNull);
  });

  test('every database status maps, and an unknown one is rejected', () {
    expect(outboxStatusFromDb('pending'), OutboxStatus.pending);
    expect(outboxStatusFromDb('sent'), OutboxStatus.sent);
    expect(outboxStatusFromDb('failed'), OutboxStatus.failed);
    expect(outboxStatusFromDb('skipped'), OutboxStatus.skipped);
    expect(outboxStatusFromDb('dry_run'), OutboxStatus.dryRun);
    expect(() => outboxStatusFromDb('queued'), throwsArgumentError);
  });

  test('the attempt limit mirrors the database', () {
    expect(outboxMaxAttempts, 5);
  });
```

Create `test/data/channel_delivery_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/data/models/channel_delivery.dart';
import 'package:pasala/data/models/outbox_message.dart';

void main() {
  test('parses a live channel with its run time', () {
    final d = ChannelDelivery.fromJson(const {
      'channel': 'email',
      'mode': 'live',
      'provider': 'resend',
      'detail': null,
      'last_run_at': '2026-09-25T04:30:00Z',
    });

    expect(d.channel, OutboxChannel.email);
    expect(d.mode, DeliveryMode.live);
    expect(d.provider, 'resend');
    expect(d.detail, isNull);
    expect(d.lastRunAt, DateTime.utc(2026, 9, 25, 4, 30));
  });

  test('parses a dry-run channel with its reason', () {
    final d = ChannelDelivery.fromJson(const {
      'channel': 'sms',
      'mode': 'dry_run',
      'provider': 'msg91',
      'detail': 'MSG91_AUTH_KEY is not set',
      'last_run_at': '2026-09-25T04:30:00Z',
    });

    expect(d.mode, DeliveryMode.dryRun);
    expect(d.detail, 'MSG91_AUTH_KEY is not set');
  });

  test('a channel that never ran has no provider and no run time', () {
    final d = ChannelDelivery.fromJson(const {
      'channel': 'whatsapp',
      'mode': 'unavailable',
      'provider': null,
      'detail': null,
      'last_run_at': null,
    });

    expect(d.mode, DeliveryMode.unavailable);
    expect(d.provider, isNull);
    expect(d.lastRunAt, isNull);
  });

  test('every mode maps, and an unknown one is rejected', () {
    expect(deliveryModeFromDb('live'), DeliveryMode.live);
    expect(deliveryModeFromDb('dry_run'), DeliveryMode.dryRun);
    expect(deliveryModeFromDb('unavailable'), DeliveryMode.unavailable);
    expect(deliveryModeFromDb('not_running'), DeliveryMode.notRunning);
    expect(() => deliveryModeFromDb('paused'), throwsArgumentError);
  });
}
```

Append to `test/core/errors_test.dart`, after the P0031 test:

```dart
  test('P0037 maps to NotRetryable with readable copy', () {
    final failure = map('P0037', 'not_retryable');
    expect(failure, isA<NotRetryable>());
    expect(failure.message, 'Only failed or dry-run messages can be sent again.');
  });
```

- [ ] **Step 8: Run them to verify they fail**

Run: `flutter test test/data/outbox_message_test.dart test/data/channel_delivery_test.dart test/core/errors_test.dart`
Expected: FAIL to compile (`outboxStatusFromDb`, `ChannelDelivery` and `NotRetryable` are not defined).

- [ ] **Step 9: Implement the Dart contract**

Replace `lib/data/models/outbox_message.dart` with:

```dart
/// The delivery channels `public.outbox_channel` knows about. Email and SMS
/// are sent by the `outbox-dispatch` Edge Function; WhatsApp rows are only
/// queued (see docs/email-and-sms-delivery.md).
enum OutboxChannel { email, sms, whatsapp }

/// `public.outbox_status`:
/// - [pending]: waiting for the sender, or waiting to retry.
/// - [sent]: the provider accepted it.
/// - [failed]: a permanent error, or the last allowed attempt failed.
/// - [skipped]: never sendable (no address on file, channel turned off).
/// - [dryRun] (`dry_run`): handled while the channel's provider key was not
///   set, so nothing was sent.
enum OutboxStatus { pending, sent, failed, skipped, dryRun }

/// The sender gives up after this many attempts. Mirrors
/// `complete_outbox_message` in 0056_email_sms_delivery.sql.
const outboxMaxAttempts = 5;

OutboxChannel _channelFromDb(String raw) => OutboxChannel.values.byName(raw);

/// Unknown status text is rejected, not defaulted -- a silent fallback
/// would hide a new server status the app does not know how to show.
OutboxStatus outboxStatusFromDb(String raw) => switch (raw) {
      'pending' => OutboxStatus.pending,
      'sent' => OutboxStatus.sent,
      'failed' => OutboxStatus.failed,
      'skipped' => OutboxStatus.skipped,
      'dry_run' => OutboxStatus.dryRun,
      _ => throw ArgumentError('Unknown outbox status: $raw'),
    };

DateTime? _timeOrNull(Object? raw) =>
    raw == null ? null : DateTime.parse(raw as String).toUtc();

/// One row of `public.outbox`: a single notification for one reservation,
/// on one channel.
class OutboxMessage {
  const OutboxMessage({
    required this.id,
    required this.reservationId,
    required this.channel,
    required this.recipient,
    required this.template,
    required this.status,
    required this.attempts,
    required this.createdAt,
    this.subject,
    this.body,
    this.lastError,
    this.sentAt,
    this.nextAttemptAt,
    this.lastAttemptAt,
  });

  final String id;
  final String reservationId;
  final OutboxChannel channel;

  /// The address/number the sender delivers to, OR -- when [status] is
  /// [OutboxStatus.skipped] for a missing contact -- a short readable
  /// reason (e.g. `"no phone on file"`). `outbox_recipient_not_empty`
  /// guarantees this is never blank.
  final String recipient;

  final String template;
  final String? subject;
  final String? body;
  final OutboxStatus status;
  final int attempts;

  /// The provider's refusal, the retry reason, the skip reason, or -- on a
  /// [OutboxStatus.dryRun] row -- why it was a dry run.
  final String? lastError;
  final DateTime createdAt;
  final DateTime? sentAt;

  /// When the row is next due. While a run holds the row this is the end
  /// of its 5-minute lease; after a failed attempt it is the retry time.
  final DateTime? nextAttemptAt;
  final DateTime? lastAttemptAt;

  factory OutboxMessage.fromJson(Map<String, dynamic> json) => OutboxMessage(
        id: json['id'] as String,
        reservationId: json['reservation_id'] as String,
        channel: _channelFromDb(json['channel'] as String),
        recipient: json['recipient'] as String,
        template: json['template'] as String,
        subject: json['subject'] as String?,
        body: json['body'] as String?,
        status: outboxStatusFromDb(json['status'] as String),
        attempts: (json['attempts'] as num?)?.toInt() ?? 0,
        lastError: json['last_error'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String).toUtc(),
        sentAt: _timeOrNull(json['sent_at']),
        nextAttemptAt: _timeOrNull(json['next_attempt_at']),
        lastAttemptAt: _timeOrNull(json['last_attempt_at']),
      );
}
```

Create `lib/data/models/channel_delivery.dart`:

```dart
import 'outbox_message.dart';

/// How one channel is being delivered, from `outbox_delivery_status`
/// (0056_email_sms_delivery.sql).
enum DeliveryMode {
  /// The provider key is set and the sender sends.
  live,

  /// The sender runs but the provider key is not set: rows are marked
  /// dry run and nothing is sent.
  dryRun,

  /// There is no sender for this channel at all (WhatsApp).
  unavailable,

  /// The sender has never reported a run.
  notRunning,
}

/// Unknown mode text is rejected, not defaulted.
DeliveryMode deliveryModeFromDb(String raw) => switch (raw) {
      'live' => DeliveryMode.live,
      'dry_run' => DeliveryMode.dryRun,
      'unavailable' => DeliveryMode.unavailable,
      'not_running' => DeliveryMode.notRunning,
      _ => throw ArgumentError('Unknown delivery mode: $raw'),
    };

/// One row of `outbox_delivery_status`.
class ChannelDelivery {
  const ChannelDelivery({
    required this.channel,
    required this.mode,
    this.provider,
    this.detail,
    this.lastRunAt,
  });

  final OutboxChannel channel;
  final DeliveryMode mode;

  /// `resend` or `msg91` once the sender has run; null otherwise.
  final String? provider;

  /// Why a channel is a dry run, e.g. `RESEND_API_KEY is not set`.
  final String? detail;

  /// When the sender last reported this channel; null if it never has.
  final DateTime? lastRunAt;

  factory ChannelDelivery.fromJson(Map<String, dynamic> json) => ChannelDelivery(
        channel: OutboxChannel.values.byName(json['channel'] as String),
        mode: deliveryModeFromDb(json['mode'] as String),
        provider: json['provider'] as String?,
        detail: json['detail'] as String?,
        lastRunAt: json['last_run_at'] == null
            ? null
            : DateTime.parse(json['last_run_at'] as String).toUtc(),
      );
}
```

Replace `lib/data/repositories/outbox_repository.dart` with:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors.dart';
import '../../core/supabase_client.dart';
import '../models/channel_delivery.dart';
import '../models/outbox_message.dart';

/// The slice of [OutboxRepository] that [OutboxScreen] needs. Tests
/// override [outboxSourceProvider] with `FakeOutboxSource`
/// (test/support/fake_outbox_source.dart) instead of a real client.
abstract class OutboxSource {
  Future<List<OutboxMessage>> messages(String propertyId);

  /// One row per channel (email, sms, whatsapp), from
  /// `outbox_delivery_status`.
  Future<List<ChannelDelivery>> deliveryStatus(String propertyId);

  /// Puts a failed or dry-run message back in the queue
  /// (`retry_outbox_message`). Owner/admin only, enforced server-side.
  Future<void> retry(String messageId);
}

/// Reads `public.outbox` (RLS `outbox_read`: staff and above at the
/// resort) and calls the two app-facing functions from
/// 0056_email_sms_delivery.sql. Clients still cannot write `outbox`
/// directly: only definer functions change a row, and only the
/// `outbox-dispatch` Edge Function (as service_role) marks one sent.
class OutboxRepository implements OutboxSource {
  OutboxRepository(this._db);
  final SupabaseClient _db;

  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } catch (e) {
      throw mapPostgrestError(e);
    }
  }

  @override
  Future<List<OutboxMessage>> messages(String propertyId) => _guard(() async {
        final rows = await _db
            .from('outbox')
            .select()
            .eq('property_id', propertyId)
            .order('created_at', ascending: false);
        return rows.map(OutboxMessage.fromJson).toList();
      });

  @override
  Future<List<ChannelDelivery>> deliveryStatus(String propertyId) =>
      _guard(() async {
        final rows = await _db.rpc(
          'outbox_delivery_status',
          params: {'p_property': propertyId},
        ) as List<dynamic>;
        return rows
            .map((e) => ChannelDelivery.fromJson(e as Map<String, dynamic>))
            .toList();
      });

  @override
  Future<void> retry(String messageId) => _guard(() async {
        await _db.rpc('retry_outbox_message', params: {'p_message': messageId});
      });
}

final outboxRepositoryProvider = Provider<OutboxRepository>(
  (ref) => OutboxRepository(ref.watch(supabaseProvider)),
);

/// [OutboxSource] seam around [outboxRepositoryProvider], so tests can
/// override just this provider with a fake.
final outboxSourceProvider = Provider<OutboxSource>(
  (ref) => ref.watch(outboxRepositoryProvider),
);
```

Replace `lib/features/outbox/providers.dart` with:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/channel_delivery.dart';
import '../../data/models/outbox_message.dart';
import '../../data/repositories/outbox_repository.dart';

/// Every outbox row the signed-in member may see at the current resort
/// (RLS `outbox_read`). Keyed by property id so switching resorts never
/// shows another resort's cached queue. Backs [OutboxScreen].
final outboxMessagesProvider = FutureProvider.family<List<OutboxMessage>, String>(
  (ref, propertyId) => ref.watch(outboxSourceProvider).messages(propertyId),
);

/// Each channel's delivery mode and when the sender last ran
/// (`outbox_delivery_status`), for the Outbox screen's status panel. Keyed
/// by property id like [outboxMessagesProvider].
final outboxDeliveryStatusProvider =
    FutureProvider.family<List<ChannelDelivery>, String>(
  (ref, propertyId) =>
      ref.watch(outboxSourceProvider).deliveryStatus(propertyId),
);
```

In `lib/features/outbox/outbox_screen.dart`, make the two existing switches cover the new status. Replace `_statusLabel` and `_statusOrder` (lines 27–44) with:

```dart
String _statusLabel(OutboxStatus status) => switch (status) {
      OutboxStatus.pending => 'Pending',
      OutboxStatus.sent => 'Sent',
      OutboxStatus.failed => 'Failed',
      OutboxStatus.skipped => 'Skipped',
      OutboxStatus.dryRun => 'Dry run',
    };

/// The order sections appear in (Task 9 of the P7 plan rewrites this
/// screen around the delivery status panel).
const _statusOrder = [
  OutboxStatus.pending,
  OutboxStatus.failed,
  OutboxStatus.dryRun,
  OutboxStatus.skipped,
  OutboxStatus.sent,
];
```

In `lib/core/errors.dart`, add after the `AlreadyDispatched` class:

```dart
/// P0037 -- `retry_outbox_message` refused a message that is not failed or
/// dry run (it is already queued again, sent, or skipped).
class NotRetryable extends BookingFailure {
  const NotRetryable()
      : super('Only failed or dry-run messages can be sent again.');
}
```

and in `mapPostgrestError`'s switch, directly after `'P0031' => const AlreadyDispatched(),`:

```dart
    // P0037: outbox delivery (0056). Only retry_outbox_message reaches the
    // app; complete_outbox_message's P0037 is service_role-only.
    'P0037' => const NotRetryable(),
```

Create `test/support/fake_outbox_source.dart`:

```dart
import 'package:pasala/data/models/channel_delivery.dart';
import 'package:pasala/data/models/outbox_message.dart';
import 'package:pasala/data/repositories/outbox_repository.dart';

/// In-memory [OutboxSource]. Set [rows]/[statuses] for what the server
/// would return and an `...Error` to make that call throw; read the call
/// logs to assert what a screen asked for.
class FakeOutboxSource implements OutboxSource {
  List<OutboxMessage> rows = [];
  List<ChannelDelivery> statuses = [];
  Object? error;
  Object? statusError;
  Object? retryError;

  final List<String> listedPropertyIds = [];
  final List<String> statusPropertyIds = [];
  final List<String> retried = [];

  @override
  Future<List<OutboxMessage>> messages(String propertyId) async {
    listedPropertyIds.add(propertyId);
    if (error != null) throw error!;
    return rows;
  }

  @override
  Future<List<ChannelDelivery>> deliveryStatus(String propertyId) async {
    statusPropertyIds.add(propertyId);
    if (statusError != null) throw statusError!;
    return statuses;
  }

  @override
  Future<void> retry(String messageId) async {
    retried.add(messageId);
    if (retryError != null) throw retryError!;
  }
}
```

In `test/features/outbox/outbox_screen_test.dart`, delete the local `FakeOutboxSource` class (its doc comment and body, lines 18–31). Add this import after the package imports:

```dart
import '../../support/fake_outbox_source.dart';
```

Keep the `outbox_repository.dart` import, because `outboxSourceProvider` comes from it. Change nothing else in this file in this task.

- [ ] **Step 10: Run the Dart tests and analyze**

```bash
flutter test test/data/outbox_message_test.dart test/data/channel_delivery_test.dart test/core/errors_test.dart test/features/outbox
flutter analyze 2>&1 | tail -3
```
Expected: all PASS; analyze shows the baseline count from Step 1.

- [ ] **Step 11: Write the failing Deno util test**

Create `supabase/functions/outbox-dispatch/util_test.ts`:

```ts
import { assertEquals, assertRejects } from "@std/assert";
import { clip, errorText, isRetryableStatus, safeJson } from "./util.ts";
import { jsonResponse, stubFetch } from "./testing.ts";

Deno.test("safeJson returns objects and null for everything else", () => {
  assertEquals(safeJson('{"id":"x"}'), { id: "x" });
  assertEquals(safeJson("[1]"), null);
  assertEquals(safeJson('"text"'), null);
  assertEquals(safeJson("not json"), null);
  assertEquals(safeJson(""), null);
});

Deno.test("clip keeps short text and cuts long text to the limit", () => {
  assertEquals(clip("abc", 5), "abc");
  assertEquals(clip("abcdefgh", 5), "abcd…");
  assertEquals(clip("x".repeat(1200)).length, 1000);
});

Deno.test("errorText reads Error messages and stringifies the rest", () => {
  assertEquals(errorText(new Error("boom")), "boom");
  assertEquals(errorText(42), "42");
});

Deno.test("isRetryableStatus: timeouts, rate limits and server errors only", () => {
  for (const s of [408, 429, 500, 502, 503]) {
    assertEquals(isRetryableStatus(s), true, String(s));
  }
  for (const s of [400, 401, 403, 404, 422]) {
    assertEquals(isRetryableStatus(s), false, String(s));
  }
});

Deno.test("stubFetch answers in order, records requests and refuses surprises", async () => {
  const { fetch, calls } = stubFetch([jsonResponse(200, { ok: 1 })]);
  const res = await fetch("https://example.test/a", {
    method: "POST",
    headers: { "X-Key": "k" },
    body: JSON.stringify({ a: 1 }),
  });
  assertEquals(await res.json(), { ok: 1 });
  assertEquals(calls, [{
    url: "https://example.test/a",
    method: "POST",
    headers: { "x-key": "k" },
    body: { a: 1 },
  }]);
  await assertRejects(() => fetch("https://example.test/b"), Error, "unexpected fetch");
});
```

Run: `(cd supabase/functions/outbox-dispatch && deno test)`
Expected: FAIL (no `deno.json`, so `@std/assert` does not resolve, and `util.ts` and `testing.ts` are missing).

- [ ] **Step 12: Write the Deno contract files**

Create `supabase/functions/outbox-dispatch/deno.json`:

```json
{
  "imports": {
    "@std/assert": "jsr:@std/assert@^1.0.13"
  },
  "tasks": {
    "test": "deno test",
    "check": "deno check index.ts"
  }
}
```

Create `supabase/functions/outbox-dispatch/types.ts`:

```ts
// The contract between the outbox-dispatch Edge Function and
// supabase/migrations/0056_email_sms_delivery.sql, and between this
// function's modules. See
// docs/superpowers/specs/2026-09-25-p7-email-and-sms-delivery-design.md.

export type Channel = "email" | "sms" | "whatsapp";

/** One row returned by `claim_outbox_batch`. */
export interface ClaimedMessage {
  id: string;
  property_id: string;
  reservation_id: string;
  channel: Channel;
  recipient: string;
  template: string;
  subject: string | null;
  body: string | null;
  /** Attempts so far, including this one. */
  attempts: number;
  /** `outbox_template_context` without customer_email / customer_phone. */
  vars: Record<string, string>;
}

/** What `complete_outbox_message` is told about one claimed row. */
export type Outcome =
  | { kind: "sent"; providerId: string | null }
  | { kind: "dry_run"; reason: string }
  | { kind: "retry"; error: string }
  | { kind: "failed"; error: string };

/** A provider's answer for one message. */
export type SendResult =
  | { ok: true; providerId: string | null }
  | { ok: false; retryable: boolean; error: string };

export interface EmailMessage {
  to: string;
  /** The resort's name; shown as the sender's display name. */
  fromName: string;
  subject: string;
  text: string;
  /** The outbox row id, so a repeat of the same row is not delivered twice. */
  idempotencyKey: string;
}

export interface EmailSender {
  send(message: EmailMessage): Promise<SendResult>;
}

export interface SmsMessage {
  /** `91` followed by a 10-digit Indian mobile number. */
  mobile: string;
  templateId: string;
  vars: Record<string, string>;
}

export interface SmsSender {
  send(message: SmsMessage): Promise<SendResult>;
}

/** One element of `record_outbox_dispatch_run`'s p_channels. */
export interface ChannelMode {
  channel: "email" | "sms";
  mode: "live" | "dry_run";
  provider: string;
  detail: string | null;
}

/** The three RPCs this function calls, all granted to service_role only. */
export interface OutboxStore {
  claim(limit: number): Promise<ClaimedMessage[]>;
  /** Returns the row's new `outbox_status`. */
  complete(id: string, outcome: Outcome): Promise<string>;
  recordRun(modes: ChannelMode[]): Promise<void>;
}

export interface DispatchSummary {
  claimed: number;
  sent: number;
  dry_run: number;
  retry: number;
  failed: number;
  /** Rows whose result could not be recorded, plus a failed run record. */
  errors: number;
  modes: { email: "live" | "dry_run"; sms: "live" | "dry_run" };
}

export type FetchFn = (input: string, init?: RequestInit) => Promise<Response>;

export interface EmailConfig {
  apiKey: string;
  /** A bare address, e.g. bookings@mail.example.com. */
  from: string;
}

export interface SmsConfig {
  authKey: string;
  senderId: string | null;
  /** Outbox template name -> MSG91 template id. */
  templates: Record<string, string>;
}

/** A channel is either live with its config, or a dry run with a reason. */
export type Setup<T> =
  | { mode: "live"; provider: string; config: T }
  | { mode: "dry_run"; provider: string; detail: string };

export interface DispatchConfig {
  supabaseUrl: string;
  serviceKey: string;
  batchSize: number;
  email: Setup<EmailConfig>;
  sms: Setup<SmsConfig>;
}
```

Create `supabase/functions/outbox-dispatch/util.ts`:

```ts
/** Parses a JSON object, or returns null for anything else. */
export function safeJson(text: string): Record<string, unknown> | null {
  try {
    const value: unknown = JSON.parse(text);
    return value !== null && typeof value === "object" && !Array.isArray(value)
      ? value as Record<string, unknown>
      : null;
  } catch {
    return null;
  }
}

/** Cuts text to what `outbox.last_error` keeps (1000 characters). */
export function clip(text: string, max = 1000): string {
  return text.length <= max ? text : text.slice(0, max - 1) + "…";
}

export function errorText(e: unknown): string {
  return e instanceof Error ? e.message : String(e);
}

/** HTTP statuses worth another attempt later. */
export function isRetryableStatus(status: number): boolean {
  return status === 408 || status === 429 || status >= 500;
}
```

Create `supabase/functions/outbox-dispatch/testing.ts`:

```ts
// Test-only helpers. Not a *_test.ts file and never imported by index.ts,
// so it is neither run as a test nor deployed.
import type { FetchFn } from "./types.ts";

export interface RecordedCall {
  url: string;
  method: string;
  /** Header names are lower-case (the Headers API normalises them). */
  headers: Record<string, string>;
  /** The JSON-parsed body, the raw text if it is not JSON, or null. */
  body: unknown;
}

/**
 * A fetch that answers from a queue and records every request. An empty
 * queue rejects, so an unexpected call fails the test instead of reaching
 * the network.
 */
export function stubFetch(
  answers: Array<Response | Error>,
): { fetch: FetchFn; calls: RecordedCall[] } {
  const calls: RecordedCall[] = [];
  const fetch: FetchFn = (input, init) => {
    const headers: Record<string, string> = {};
    new Headers(init?.headers).forEach((value, key) => {
      headers[key] = value;
    });
    const raw = init?.body;
    let body: unknown = raw ?? null;
    if (typeof raw === "string") {
      try {
        body = JSON.parse(raw);
      } catch {
        body = raw;
      }
    }
    calls.push({ url: input, method: init?.method ?? "GET", headers, body });
    const next = answers.shift();
    if (next === undefined) {
      return Promise.reject(new Error(`unexpected fetch to ${input}`));
    }
    return next instanceof Error ? Promise.reject(next) : Promise.resolve(next);
  };
  return { fetch, calls };
}

export function jsonResponse(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
```

- [ ] **Step 13: Run the Deno tests and type-check**

```bash
(cd supabase/functions/outbox-dispatch && deno test && deno check types.ts util.ts testing.ts)
```
Expected: 5 tests PASS, no type errors. A `deno.lock` now exists in the folder.

- [ ] **Step 14: Commit**

```bash
git add supabase/migrations/0056_email_sms_delivery.sql \
  supabase/tests/46_email_sms_delivery_test.sql \
  supabase/tests/37_tenancy_isolation_test.sql \
  lib/data/models/outbox_message.dart lib/data/models/channel_delivery.dart \
  lib/data/repositories/outbox_repository.dart lib/features/outbox/providers.dart \
  lib/features/outbox/outbox_screen.dart lib/core/errors.dart \
  test/support/fake_outbox_source.dart test/features/outbox/outbox_screen_test.dart \
  test/data/outbox_message_test.dart test/data/channel_delivery_test.dart \
  test/core/errors_test.dart \
  supabase/functions/outbox-dispatch/deno.json supabase/functions/outbox-dispatch/deno.lock \
  supabase/functions/outbox-dispatch/types.ts supabase/functions/outbox-dispatch/util.ts \
  supabase/functions/outbox-dispatch/testing.ts supabase/functions/outbox-dispatch/util_test.ts
git commit -m "feat(outbox): P7 delivery contract -- schema, function stubs, Dart and Deno types" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Phase 1: Database track (sequential)

### Task 2: Template context and claiming

**Track:** DB. Depends on Task 1.

**Files:**
- Modify: `supabase/migrations/0056_email_sms_delivery.sql` (replace the `outbox_template_context` and `claim_outbox_batch` stubs; add the `render_template` copy)
- Modify: `supabase/tests/46_email_sms_delivery_test.sql` (plan 20 → 37; new section before `select * from finish();`)

**Interfaces:**
- Consumes: Task 1's fixtures (A: 4 pending rows for Asha; B: 2 pending emails for Bala), `public.notification_settings`, `render_template`'s latest body (0045 lines 1863–1935).
- Produces:
  - `outbox_template_context(p_reservation_id uuid) returns jsonb` with the keys `guest_name`, `unit_name`, `property_name`, `check_in`, `check_out`, `total`, `currency`, `cancel_reason`, `customer_email`, `customer_phone` (all strings); P0002 for an unknown reservation.
  - `render_template` renders through `outbox_template_context` (same output as before).
  - `claim_outbox_batch(p_limit)` as specified: due `pending` email/sms rows, oldest `next_attempt_at` first, `FOR UPDATE SKIP LOCKED`, the limit clamped to 1..200. Channel off → `skipped`; `attempts >= 5` → `failed`; otherwise `attempts + 1`, `last_attempt_at = now()`, `next_attempt_at = now() + 5 min`, returned with `vars` (context minus `customer_email`/`customer_phone`).
  - State this section leaves for Task 3:
    - A `booking_confirmation`: pending, attempts 2, leased
    - A `payment_success`: failed (attempts 5)
    - A `booking_confirmation_sms`: skipped
    - A whatsapp: pending, attempts 0
    - B `booking_confirmation` and B `payment_success`: pending, attempts 1, leased

- [ ] **Step 1: Write the failing tests**

In `supabase/tests/46_email_sms_delivery_test.sql` change `select plan(20);` to `select plan(37);`, and insert before `select * from finish();`:

```sql
-- === Task 2: template context and claiming =====================================
select is(public.outbox_template_context('d7a00000-0000-4000-8000-000000000021') ->> 'guest_name',
  'Asha Rao', 'the template context names the guest');
select is(public.outbox_template_context('d7a00000-0000-4000-8000-000000000021') ->> 'property_name',
  'P7 Resort A', 'the template context names the resort');
select is(public.render_template('booking_confirmation', 'd7a00000-0000-4000-8000-000000000021') ->> 'subject',
  'Your stay at P7 Resort A is confirmed',
  'render_template still renders, through the shared context');
select throws_ok($$select public.outbox_template_context('d7a00000-0000-4000-8000-0000000000ff')$$,
  'P0002', null, 'an unknown reservation has no context');

-- A turns SMS off after its messages were queued.
insert into public.notification_settings (property_id, email_enabled, sms_enabled)
values ('d7a00000-0000-4000-8000-000000000001', true, false);

set local role authenticated;
set local request.jwt.claims to '{"sub":"d7000000-0000-0000-0000-0000000000a1","role":"authenticated"}';
select throws_ok($$select * from public.claim_outbox_batch(10)$$,
  '42501', null, 'a resort owner cannot claim outbox rows');
reset role;
set local request.jwt.claims to '';

set local role service_role;
create temp table p7_claim1 as select * from public.claim_outbox_batch(10);
reset role;

select is((select count(*)::int from p7_claim1), 4,
  'the claim returns the four due email rows (A''s SMS is off, WhatsApp is never claimed)');
select is((select count(*)::int from p7_claim1 where channel = 'whatsapp'), 0,
  'whatsapp rows are never claimed');
select is(
  (select status::text || ' / ' || last_error from public.outbox
    where template = 'booking_confirmation_sms'
      and property_id = 'd7a00000-0000-4000-8000-000000000001'),
  'skipped / sms notifications are disabled in this property''s settings',
  'a queued SMS whose channel was switched off is skipped at claim time');
select is((select status::text from public.outbox where template = 'booking_confirmation_whatsapp'),
  'pending', 'the whatsapp row stays pending');
select is((select array_agg(distinct attempts) from p7_claim1), array[1],
  'each claimed row counts one attempt');
select is(
  (select count(*)::int from public.outbox o join p7_claim1 c on c.id = o.id
    where o.attempts = 1 and o.last_attempt_at = now()
      and o.next_attempt_at = now() + interval '5 minutes'),
  4, 'claimed rows are leased for five minutes');
select ok(
  (select bool_and(vars ->> 'property_name' is not null
                   and not vars ? 'customer_email'
                   and not vars ? 'customer_phone')
     from p7_claim1),
  'claimed rows carry template variables without contact details');
select is(
  (select vars ->> 'property_name' from p7_claim1
    where property_id = 'd7b00000-0000-4000-8000-000000000001' limit 1),
  'P7 Resort B', 'each row carries its own resort''s variables');

set local role service_role;
select is((select count(*)::int from public.claim_outbox_batch(10)), 0,
  'a second run in the same minute claims nothing (the rows are leased)');
reset role;

-- The lease on two A rows runs out; the one due longest comes first.
update public.outbox set next_attempt_at = now() - interval '2 minutes'
 where template = 'booking_confirmation' and property_id = 'd7a00000-0000-4000-8000-000000000001';
update public.outbox set next_attempt_at = now() - interval '1 minute'
 where template = 'payment_success' and property_id = 'd7a00000-0000-4000-8000-000000000001';

set local role service_role;
create temp table p7_claim2 as select * from public.claim_outbox_batch(1);
reset role;
select is((select template || ' #' || attempts from p7_claim2), 'booking_confirmation #2',
  'p_limit is honoured and the longest-due row comes first, on its second attempt');

-- A row that has used all five attempts is failed, not sent a sixth time.
update public.outbox set attempts = 5
 where template = 'payment_success' and property_id = 'd7a00000-0000-4000-8000-000000000001';
set local role service_role;
select is((select count(*)::int from public.claim_outbox_batch(10)), 0,
  'a row at the attempt limit is not claimed');
reset role;
select is(
  (select status::text from public.outbox
    where template = 'payment_success' and property_id = 'd7a00000-0000-4000-8000-000000000001'),
  'failed', 'a row at the attempt limit is failed');
```

- [ ] **Step 2: Run it to verify it fails**

Run: `supabase test db supabase/tests/46_email_sms_delivery_test.sql`
Expected: FAIL on "the template context names the guest" (`0A000 not_implemented`).

- [ ] **Step 3: Implement the context, the render_template copy and the claim**

In `supabase/migrations/0056_email_sms_delivery.sql`, replace the whole `outbox_template_context` stub block (from `-- outbox_template_context (Task 2 replaces this stub)` to its closing `$$;`) with the block below. It includes the `render_template` copy.

```sql
-- outbox_template_context: the variables a template can use. Moved out of
-- render_template (0045) unchanged, so the email text and the SMS
-- variables MSG91 receives come from the same place.

create function public.outbox_template_context(p_reservation_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_row      public.reservations;
  v_unit     public.units;
  v_property public.properties;
  v_profile  public.profiles;
  v_email    text;
begin
  select * into v_row from public.reservations where id = p_reservation_id;
  if not found then
    raise exception 'reservation not found' using errcode = 'P0002';
  end if;

  select * into v_unit from public.units where id = v_row.unit_id;
  select * into v_property from public.properties where id = v_unit.property_id;
  select * into v_profile from public.profiles where id = v_row.customer_id;
  select email into v_email from auth.users where id = v_row.customer_id;

  -- Every value is coalesced: replace() returns NULL if any argument is
  -- NULL, which would collapse the whole rendered text (see 0017).
  return jsonb_build_object(
    'guest_name',     coalesce(v_profile.full_name, 'Guest'),
    'unit_name',      coalesce(v_unit.name, 'your unit'),
    'property_name',  coalesce(v_property.name, 'Pasala Resorts'),
    'check_in',       coalesce(to_char(
                         lower(v_row.period) at time zone v_property.timezone,
                         'DD Mon YYYY'), ''),
    'check_out',      coalesce(to_char(
                         upper(v_row.period) at time zone v_property.timezone,
                         'DD Mon YYYY'), ''),
    'total',          coalesce(v_row.quote ->> 'total', '0'),
    'currency',       coalesce(v_row.quote ->> 'currency', 'INR'),
    'cancel_reason',  coalesce(v_row.cancel_reason, 'no reason given'),
    'customer_email', coalesce(v_email, ''),
    'customer_phone', coalesce(v_profile.phone, '')
  );
end;
$$;

-- render_template, copied from its latest definition (0045, lines
-- 1863-1935); only the context block now calls outbox_template_context.
-- create or replace keeps its ACL (revoked from every client role in 0017).
create or replace function public.render_template(
  p_template       text,
  p_reservation_id uuid
) returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_tpl      public.outbox_templates;
  v_property uuid;
  v_ctx      jsonb;
  v_subject  text;
  v_body     text;
  v_key      text;
begin
  select property_id into v_property from public.reservations where id = p_reservation_id;
  if not found then
    raise exception 'reservation not found' using errcode = 'P0002';
  end if;

  select * into v_tpl from public.outbox_templates
  where name = p_template
    and (property_id = v_property or property_id is null)
  order by property_id nulls last
  limit 1;
  if not found then
    raise exception 'unknown outbox template %', p_template
      using errcode = 'P0002';
  end if;

  v_ctx := public.outbox_template_context(p_reservation_id);

  v_subject := v_tpl.subject_template;
  v_body    := v_tpl.body_template;

  for v_key in select jsonb_object_keys(v_ctx) loop
    if v_subject is not null then
      v_subject := replace(v_subject, '{{' || v_key || '}}', v_ctx ->> v_key);
    end if;
    v_body := replace(v_body, '{{' || v_key || '}}', v_ctx ->> v_key);
  end loop;

  return jsonb_build_object('subject', v_subject, 'body', v_body);
end;
$$;
```

Replace the whole `claim_outbox_batch` stub block (from `-- claim_outbox_batch (Task 2 replaces this stub)` to its closing `$$;`) with:

```sql
-- claim_outbox_batch: up to p_limit due email/SMS rows for one dispatcher
-- run. Each claimed row counts one attempt and is leased for 5 minutes
-- (next_attempt_at), so an overlapping run skips it and a run that dies
-- halfway gives it back. The row lock ends when this returns, before the
-- provider call -- hence the lease. A row whose channel was switched off
-- after it was queued is skipped, with the same reason
-- enqueue_outbox_message uses; a row already at the attempt limit is
-- failed, never sent a sixth time. WhatsApp rows are never claimed.

create function public.claim_outbox_batch(p_limit int default 25)
returns table (id uuid, property_id uuid, reservation_id uuid,
               channel public.outbox_channel, recipient text, template text,
               subject text, body text, attempts int, vars jsonb)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
#variable_conflict use_column
declare
  v_limit   int := least(greatest(coalesce(p_limit, 25), 1), 200);
  v_row     public.outbox;
  v_enabled boolean;
begin
  for v_row in
    select o.*
      from public.outbox o
     where o.status = 'pending'
       and o.channel in ('email', 'sms')
       and o.next_attempt_at <= now()
     order by o.next_attempt_at, o.created_at, o.id
     limit v_limit
     for update skip locked
  loop
    v_enabled := coalesce(
      (select case v_row.channel
                when 'email' then ns.email_enabled
                when 'sms'   then ns.sms_enabled
              end
         from public.notification_settings ns
        where ns.property_id = v_row.property_id),
      true);

    if not v_enabled then
      update public.outbox o
         set status = 'skipped',
             last_error = format('%s notifications are disabled in this property''s settings',
                                 v_row.channel)
       where o.id = v_row.id;
      continue;
    end if;

    if v_row.attempts >= 5 then
      update public.outbox o
         set status = 'failed',
             last_error = coalesce(v_row.last_error, 'gave up after 5 attempts')
       where o.id = v_row.id;
      continue;
    end if;

    update public.outbox o
       set attempts        = o.attempts + 1,
           last_attempt_at = now(),
           next_attempt_at = now() + interval '5 minutes'
     where o.id = v_row.id;

    id             := v_row.id;
    property_id    := v_row.property_id;
    reservation_id := v_row.reservation_id;
    channel        := v_row.channel;
    recipient      := v_row.recipient;
    template       := v_row.template;
    subject        := v_row.subject;
    body           := v_row.body;
    attempts       := v_row.attempts + 1;
    vars           := public.outbox_template_context(v_row.reservation_id)
                        - 'customer_email' - 'customer_phone';
    return next;
  end loop;
end;
$$;
```

- [ ] **Step 4: Rebuild and run**

```bash
supabase db reset
supabase test db supabase/tests/46_email_sms_delivery_test.sql
supabase test db supabase/tests/13_outbox_test.sql
supabase test db supabase/tests/24_notification_settings_test.sql
supabase test db supabase/tests/37_tenancy_isolation_test.sql
```
Expected: all PASS (46: 37/37). 13 and 24 prove that `render_template` and `enqueue_outbox_message` behave as before.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/0056_email_sms_delivery.sql supabase/tests/46_email_sms_delivery_test.sql
git commit -m "feat(outbox): claim due email/SMS rows with a lease and shared template variables" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Completing, backoff and Send again

**Track:** DB. Depends on Task 2.

**Files:**
- Modify: `supabase/migrations/0056_email_sms_delivery.sql` (replace the `outbox_retry_delay`, `complete_outbox_message` and `retry_outbox_message` stubs)
- Modify: `supabase/tests/46_email_sms_delivery_test.sql` (plan 37 → 66; new section before `select * from finish();`)

**Interfaces:**
- Consumes: the state Task 2 leaves (see Task 2's Produces), `public.assert_resort_role`, `public.audit_log (property_id, actor_id, entity, entity_id, action, before, after)`.
- Produces:
  - `outbox_retry_delay(p_attempts int) returns interval`: `2^(greatest(p_attempts,1)-1)` minutes. Plain SQL, immutable.
  - `complete_outbox_message(p_id, p_outcome, p_error, p_provider_id) returns outbox_status`:
    - `sent` → `sent`, with `sent_at` and `provider_message_id` set and `last_error` null
    - `dry_run` → `dry_run`, keeping the reason
    - `retry` → `pending` after `outbox_retry_delay(attempts)`, or `failed` once attempts ≥ 5
    - `failed` → `failed`
    - Errors: 22023 for an unknown outcome, P0002 for an unknown id, P0037 when the row is not in flight (not `pending`, or `attempts = 0`). `last_error` is trimmed to 1000 characters.
  - `retry_outbox_message(p_message)`: owner/admin at the row's resort, which must be active (write check). The row must be `failed` or `dry_run`, else P0037. It is reset to `pending`, `attempts 0`, `next_attempt_at now()`, and `last_attempt_at`, `last_error` and `provider_message_id` are cleared. It writes an `audit_log` row (`entity 'outbox'`, `action 'retry'`).

- [ ] **Step 1: Write the failing tests**

Change `select plan(37);` to `select plan(66);` and insert before `select * from finish();`:

```sql
-- === Task 3: completing, backoff and Send again ================================
select is(public.outbox_retry_delay(1), interval '1 minute', 'the first retry waits one minute');
select is(public.outbox_retry_delay(2), interval '2 minutes', 'the second retry waits two');
select is(public.outbox_retry_delay(4), interval '8 minutes', 'the fourth retry waits eight');
select is(public.outbox_retry_delay(0), interval '1 minute', 'zero attempts counts as one');

-- The rows this section works on, by name.
select set_config('p7.a1', (select id::text from public.outbox where template = 'booking_confirmation'
  and property_id = 'd7a00000-0000-4000-8000-000000000001'), true);
select set_config('p7.a2', (select id::text from public.outbox where template = 'payment_success'
  and property_id = 'd7a00000-0000-4000-8000-000000000001'), true);
select set_config('p7.b1', (select id::text from public.outbox where template = 'booking_confirmation'
  and property_id = 'd7b00000-0000-4000-8000-000000000001'), true);
select set_config('p7.b2', (select id::text from public.outbox where template = 'payment_success'
  and property_id = 'd7b00000-0000-4000-8000-000000000001'), true);

set local role authenticated;
set local request.jwt.claims to '{"sub":"d7000000-0000-0000-0000-0000000000a1","role":"authenticated"}';
select throws_ok($$select public.complete_outbox_message(current_setting('p7.b1')::uuid, 'sent')$$,
  '42501', null, 'a resort owner cannot complete outbox rows');
reset role;
set local request.jwt.claims to '';

set local role service_role;
select is(public.complete_outbox_message(current_setting('p7.b1')::uuid, 'sent', null, 're_b1')::text,
  'sent', 'a delivered row is marked sent');
select throws_ok($$select public.complete_outbox_message(current_setting('p7.b1')::uuid, 'sent')$$,
  'P0037', null, 'a row that is no longer in flight cannot be completed again');
select is(public.complete_outbox_message(current_setting('p7.b2')::uuid, 'retry', 'resend 503: busy')::text,
  'pending', 'a retryable failure goes back to pending');
select is(public.complete_outbox_message(current_setting('p7.a1')::uuid, 'dry_run',
                                         'Dry run: RESEND_API_KEY is not set')::text,
  'dry_run', 'a dry run is recorded as dry_run');
select throws_ok($$select public.complete_outbox_message(current_setting('p7.a1')::uuid, 'bogus')$$,
  '22023', null, 'an unknown outcome is refused');
select throws_ok($$select public.complete_outbox_message('d7a00000-0000-4000-8000-0000000000ff', 'sent')$$,
  'P0002', null, 'an unknown row is refused');
reset role;

select is(
  (select sent_at is not null and provider_message_id = 're_b1' and last_error is null
     from public.outbox where id = current_setting('p7.b1')::uuid),
  true, 'a sent row keeps the provider id and the send time');
select is(
  (select status::text || ' / ' || attempts || ' / ' || last_error
     from public.outbox where id = current_setting('p7.b2')::uuid),
  'pending / 1 / resend 503: busy', 'a retried row keeps its attempt count and error');
select is((select next_attempt_at from public.outbox where id = current_setting('p7.b2')::uuid),
  now() + interval '1 minute', 'after the first attempt the row waits one minute');
select is((select last_error from public.outbox where id = current_setting('p7.a1')::uuid),
  'Dry run: RESEND_API_KEY is not set', 'the dry-run reason is kept');

-- The fifth failed attempt is final.
update public.outbox set attempts = 5, next_attempt_at = now() + interval '5 minutes'
 where id = current_setting('p7.b2')::uuid;
set local role service_role;
select is(public.complete_outbox_message(current_setting('p7.b2')::uuid, 'retry',
                                         'resend 503: still busy')::text,
  'failed', 'the fifth failed attempt fails the row');
reset role;

-- A permanent failure is final at once.
insert into public.outbox (id, reservation_id, channel, recipient, template, subject, body, attempts)
values ('d7b00000-0000-4000-8000-000000000031', 'd7b00000-0000-4000-8000-000000000021', 'email',
        'p7-bala@example.com', 'cancellation', 'Cancelled', 'Your booking was cancelled.', 1);
set local role service_role;
select is(public.complete_outbox_message('d7b00000-0000-4000-8000-000000000031', 'failed',
                                         'resend 422: invalid to')::text,
  'failed', 'a permanent failure is final at once');
reset role;

-- Nothing that is sent, failed, dry run or skipped is claimed again.
update public.outbox set next_attempt_at = now() - interval '1 minute';
set local role service_role;
select is((select count(*)::int from public.claim_outbox_batch(10)), 0,
  'sent, failed, dry-run and skipped rows are never claimed');
reset role;

-- Send again: owner or admin of the message's resort, failed or dry-run rows only.
set local role authenticated;
set local request.jwt.claims to '{"sub":"d7000000-0000-0000-0000-0000000000a3","role":"authenticated"}';
select throws_ok($$select public.retry_outbox_message(current_setting('p7.a2')::uuid)$$,
  'P0020', null, 'staff cannot send a message again');
set local request.jwt.claims to '{"sub":"d7000000-0000-0000-0000-0000000000a4","role":"authenticated"}';
select throws_ok($$select public.retry_outbox_message(current_setting('p7.a2')::uuid)$$,
  'P0020', null, 'an accountant cannot send a message again');
set local request.jwt.claims to '{"sub":"d7000000-0000-0000-0000-0000000000b1","role":"authenticated"}';
select throws_ok($$select public.retry_outbox_message(current_setting('p7.a2')::uuid)$$,
  'P0020', null, 'another resort''s owner cannot send A''s message again');
set local request.jwt.claims to '{"sub":"d7000000-0000-0000-0000-0000000000a2","role":"authenticated"}';
select lives_ok($$select public.retry_outbox_message(current_setting('p7.a2')::uuid)$$,
  'an admin sends a failed message again');
select throws_ok($$select public.retry_outbox_message(current_setting('p7.a2')::uuid)$$,
  'P0037', null, 'a message already queued again cannot be retried twice');
set local request.jwt.claims to '{"sub":"d7000000-0000-0000-0000-0000000000a1","role":"authenticated"}';
select lives_ok($$select public.retry_outbox_message(current_setting('p7.a1')::uuid)$$,
  'an owner sends a dry-run message again');
select throws_ok($$select public.retry_outbox_message('d7a00000-0000-4000-8000-0000000000ff')$$,
  'P0002', null, 'an unknown message is refused');
reset role;
set local request.jwt.claims to '';

select is(
  (select status::text || ' / ' || attempts || ' / ' || coalesce(last_error, '-')
          || ' / ' || (next_attempt_at = now())::text
     from public.outbox where id = current_setting('p7.a2')::uuid),
  'pending / 0 / - / true', 'Send again resets the row to a fresh, due pending row');
select is(
  (select count(*)::int from public.audit_log
    where entity = 'outbox' and action = 'retry'
      and entity_id in (current_setting('p7.a1')::uuid, current_setting('p7.a2')::uuid)
      and property_id = 'd7a00000-0000-4000-8000-000000000001'),
  2, 'each Send again writes an audit row at the message''s resort');

set local role authenticated;
set local request.jwt.claims to '{"sub":"d7000000-0000-0000-0000-0000000000b1","role":"authenticated"}';
select throws_ok($$select public.retry_outbox_message(current_setting('p7.b1')::uuid)$$,
  'P0037', null, 'a sent message cannot be sent again');
reset role;
set local request.jwt.claims to '';

-- A suspended resort's owner cannot send again (reads stay allowed).
update public.properties set status = 'suspended' where id = 'd7b00000-0000-4000-8000-000000000001';
set local role authenticated;
set local request.jwt.claims to '{"sub":"d7000000-0000-0000-0000-0000000000b1","role":"authenticated"}';
select throws_ok($$select public.retry_outbox_message(current_setting('p7.b2')::uuid)$$,
  'P0022', null, 'no Send again at a suspended resort');
reset role;
set local request.jwt.claims to '';
update public.properties set status = 'active' where id = 'd7b00000-0000-4000-8000-000000000001';
```

- [ ] **Step 2: Run it to verify it fails**

Run: `supabase test db supabase/tests/46_email_sms_delivery_test.sql`
Expected: FAIL at "the first retry waits one minute" (`0A000 not_implemented`).

- [ ] **Step 3: Implement the three functions**

Replace the whole `outbox_retry_delay` stub block (from `-- outbox_retry_delay (Task 3 replaces this stub)` to its closing `$$;`) with:

```sql
-- outbox_retry_delay: how long a row waits after its n-th failed attempt:
-- 1, 2, 4, 8 minutes. Not security definer; it reads nothing.

create function public.outbox_retry_delay(p_attempts int)
returns interval
language sql
immutable
set search_path = public, pg_temp
as $$
  select make_interval(mins => power(2, greatest(coalesce(p_attempts, 1), 1) - 1)::int);
$$;
```

Replace the whole `complete_outbox_message` stub block with:

```sql
-- complete_outbox_message: records one claimed row's result. The
-- dispatcher only says what happened; this decides what it means. A
-- retryable failure waits outbox_retry_delay(attempts), and the fifth
-- attempt is final. Only a row in flight (pending, claimed at least once)
-- can be completed.

create function public.complete_outbox_message(
  p_id          uuid,
  p_outcome     text,
  p_error       text default null,
  p_provider_id text default null
) returns public.outbox_status
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_row   public.outbox;
  v_error text := left(nullif(btrim(coalesce(p_error, '')), ''), 1000);
begin
  if p_outcome is null or p_outcome not in ('sent', 'dry_run', 'retry', 'failed') then
    raise exception using errcode = '22023', message = 'unknown_outcome';
  end if;

  select * into v_row from public.outbox where id = p_id for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'not_found';
  end if;
  if v_row.status <> 'pending' or v_row.attempts = 0 then
    raise exception using errcode = 'P0037', message = 'outbox_not_in_flight';
  end if;

  if p_outcome = 'sent' then
    update public.outbox
       set status = 'sent',
           sent_at = now(),
           provider_message_id = nullif(btrim(coalesce(p_provider_id, '')), ''),
           last_error = null
     where id = p_id;
    return 'sent';
  elsif p_outcome = 'dry_run' then
    update public.outbox
       set status = 'dry_run',
           last_error = coalesce(v_error, 'Dry run: no provider key is set')
     where id = p_id;
    return 'dry_run';
  elsif p_outcome = 'failed' or v_row.attempts >= 5 then
    update public.outbox
       set status = 'failed',
           last_error = coalesce(v_error, 'delivery failed')
     where id = p_id;
    return 'failed';
  else
    update public.outbox
       set next_attempt_at = now() + public.outbox_retry_delay(v_row.attempts),
           last_error = coalesce(v_error, 'delivery failed')
     where id = p_id;
    return 'pending';
  end if;
end;
$$;
```

Replace the whole `retry_outbox_message` stub block with:

```sql
-- retry_outbox_message: Send again, for a failed or dry-run message. The
-- resort comes from the row, never from the client; owner/admin at an
-- active resort only. The row starts over as a fresh, due pending row and
-- the change is audited.

create function public.retry_outbox_message(p_message uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_row public.outbox;
begin
  select * into v_row from public.outbox where id = p_message;
  if not found then
    raise exception using errcode = 'P0002', message = 'not_found';
  end if;
  perform public.assert_resort_role(v_row.property_id, true, 'owner', 'admin');

  select * into v_row from public.outbox where id = p_message for update;
  if v_row.status not in ('failed', 'dry_run') then
    raise exception using errcode = 'P0037', message = 'not_retryable';
  end if;

  update public.outbox
     set status = 'pending',
         attempts = 0,
         next_attempt_at = now(),
         last_attempt_at = null,
         last_error = null,
         provider_message_id = null
   where id = p_message;

  insert into public.audit_log (property_id, actor_id, entity, entity_id, action, before, after)
  values (v_row.property_id, auth.uid(), 'outbox', p_message, 'retry',
          jsonb_build_object('status', v_row.status, 'attempts', v_row.attempts,
                             'last_error', v_row.last_error),
          jsonb_build_object('status', 'pending', 'attempts', 0));
end;
$$;
```

- [ ] **Step 4: Rebuild and run**

```bash
supabase db reset
supabase test db supabase/tests/46_email_sms_delivery_test.sql
supabase test db supabase/tests/37_tenancy_isolation_test.sql
```
Expected: PASS (46: 66/66).

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/0056_email_sms_delivery.sql supabase/tests/46_email_sms_delivery_test.sql
git commit -m "feat(outbox): record send outcomes with backoff and let owners send again" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Delivery status, dispatcher heartbeat and the cron tick

**Track:** DB. Depends on Task 3.

**Files:**
- Modify: `supabase/migrations/0056_email_sms_delivery.sql` (replace the `record_outbox_dispatch_run`, `outbox_delivery_status`, `outbox_dispatch_post` and `outbox_dispatch_tick` stubs; append the cron schedule)
- Modify: `supabase/tests/46_email_sms_delivery_test.sql` (plan 66 → 84; new section before `select * from finish();`)

**Interfaces:**
- Consumes: `public.outbox_channel_status`, `public.assert_resort_role`, `net.http_post(url text, body jsonb, params jsonb, headers jsonb, timeout_milliseconds int)` (pg_net), `vault.decrypted_secrets (name, decrypted_secret)`, `cron.schedule(name, schedule, command)`.
- Produces:
  - `record_outbox_dispatch_run(p_channels jsonb)`: upserts `{channel, mode, provider, detail}` for `email`/`sms` only, with `last_run_at = now()`. A bad mode raises 23514.
  - `outbox_delivery_status(p_property)`: Staff+ read at `p_property` (P0020 otherwise). Always returns the three rows email, sms, whatsapp. WhatsApp is `unavailable`, and a channel that has never been reported is `not_running`.
  - `outbox_dispatch_post(p_url, p_key) returns text`: `not_configured` if either argument is blank. Otherwise it sends one `net.http_post` with `Authorization: Bearer <key>` and a 30 s timeout, and returns `requested`.
  - `outbox_dispatch_tick() returns text`: reads the Vault secrets `outbox_dispatch_url` and `outbox_dispatch_key` with dynamic SQL. It returns `not_configured` when there is no Vault or a secret is missing; otherwise it returns `outbox_dispatch_post(...)`.
  - pg_cron job `outbox-dispatch`, `* * * * *`, `select public.outbox_dispatch_tick()`.

- [ ] **Step 1: Write the failing tests**

Change `select plan(66);` to `select plan(84);` and insert before `select * from finish();`:

```sql
-- === Task 4: delivery status, heartbeat and the cron tick ======================
set local role authenticated;
set local request.jwt.claims to '{"sub":"d7000000-0000-0000-0000-0000000000a3","role":"authenticated"}';
select is(
  (select array_agg(channel::text || ':' || mode order by channel)
     from public.outbox_delivery_status('d7a00000-0000-4000-8000-000000000001')),
  array['email:not_running','sms:not_running','whatsapp:unavailable'],
  'before any run every channel is waiting and whatsapp is unavailable');
select throws_ok($$select * from public.outbox_delivery_status('d7b00000-0000-4000-8000-000000000001')$$,
  'P0020', null, 'A staff cannot read B''s delivery status');
select throws_ok($$select public.record_outbox_dispatch_run('[]'::jsonb)$$,
  '42501', null, 'staff cannot record a dispatcher run');
set local request.jwt.claims to '{"sub":"d7000000-0000-0000-0000-0000000000c1","role":"authenticated"}';
select throws_ok($$select * from public.outbox_delivery_status('d7a00000-0000-4000-8000-000000000001')$$,
  'P0020', null, 'a guest cannot read delivery status');
reset role;
set local request.jwt.claims to '';
set local role anon;
select throws_ok($$select * from public.outbox_delivery_status('d7a00000-0000-4000-8000-000000000001')$$,
  '42501', null, 'anon cannot read delivery status');
reset role;

set local role service_role;
select lives_ok($$select public.record_outbox_dispatch_run('[
    {"channel":"email","mode":"live","provider":"resend","detail":null},
    {"channel":"sms","mode":"dry_run","provider":"msg91","detail":"MSG91_AUTH_KEY is not set"},
    {"channel":"whatsapp","mode":"live","provider":"meta","detail":null}]'::jsonb)$$,
  'the dispatcher records its run');
select throws_ok($$select public.record_outbox_dispatch_run(
    '[{"channel":"email","mode":"bogus","provider":"resend"}]'::jsonb)$$,
  '23514', null, 'an unknown mode is refused');
reset role;
select is((select count(*)::int from public.outbox_channel_status), 2,
  'only email and sms are recorded');

set local role authenticated;
set local request.jwt.claims to '{"sub":"d7000000-0000-0000-0000-0000000000a4","role":"authenticated"}';
select is(
  (select array_agg(channel::text || ':' || mode || ':' || coalesce(provider, '-')
                    || ':' || coalesce(detail, '-') order by channel)
     from public.outbox_delivery_status('d7a00000-0000-4000-8000-000000000001')),
  array['email:live:resend:-',
        'sms:dry_run:msg91:MSG91_AUTH_KEY is not set',
        'whatsapp:unavailable:-:-'],
  'after a run every member sees each channel''s mode');
select is(
  (select last_run_at from public.outbox_delivery_status('d7a00000-0000-4000-8000-000000000001')
    where channel = 'email'),
  now(), 'the run time is recorded');
reset role;
set local request.jwt.claims to '';

-- The POST the cron tick makes (tested without touching Vault).
select is(public.outbox_dispatch_post(null, 'k'), 'not_configured',
  'no URL: nothing is requested');
select is(public.outbox_dispatch_post('http://outbox.test/functions/v1/outbox-dispatch', '  '),
  'not_configured', 'a blank key: nothing is requested');
select is(public.outbox_dispatch_post('http://outbox.test/functions/v1/outbox-dispatch',
                                      'test-service-key'),
  'requested', 'with a URL and a key the function is called');
select is(
  (select count(*)::int from net.http_request_queue
    where url = 'http://outbox.test/functions/v1/outbox-dispatch'
      and method = 'POST'
      and headers ->> 'Authorization' = 'Bearer test-service-key'),
  1, 'one POST is queued, carrying the service key');
select ok(public.outbox_dispatch_tick() in ('not_configured', 'requested'),
  'the tick runs and answers not_configured or requested');
select is((select schedule from cron.job where jobname = 'outbox-dispatch'), '* * * * *',
  'pg_cron runs the tick every minute');

set local role authenticated;
set local request.jwt.claims to '{"sub":"d7000000-0000-0000-0000-0000000000a1","role":"authenticated"}';
select throws_ok($$select public.outbox_dispatch_tick()$$,
  '42501', null, 'clients cannot fire the tick');
select throws_ok($$select public.outbox_dispatch_post('http://x', 'k')$$,
  '42501', null, 'clients cannot make the dispatcher POST');
reset role;
set local request.jwt.claims to '';
```

- [ ] **Step 2: Run it to verify it fails**

Run: `supabase test db supabase/tests/46_email_sms_delivery_test.sql`
Expected: FAIL at "before any run every channel is waiting …" (`0A000 not_implemented`).

- [ ] **Step 3: Implement the four functions and the schedule**

Replace the whole `record_outbox_dispatch_run` stub block with:

```sql
-- record_outbox_dispatch_run: the dispatcher's heartbeat, one row per
-- channel it handles (email, sms). Anything else in p_channels is ignored.

create function public.record_outbox_dispatch_run(p_channels jsonb)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  insert into public.outbox_channel_status as s (channel, mode, provider, detail, last_run_at)
  select (c ->> 'channel')::public.outbox_channel,
         c ->> 'mode',
         coalesce(nullif(c ->> 'provider', ''), 'unknown'),
         nullif(c ->> 'detail', ''),
         now()
    from jsonb_array_elements(coalesce(p_channels, '[]'::jsonb)) as c
   where c ->> 'channel' in ('email', 'sms')
  on conflict (channel) do update
     set mode        = excluded.mode,
         provider    = excluded.provider,
         detail      = excluded.detail,
         last_run_at = excluded.last_run_at;
end;
$$;
```

Replace the whole `outbox_delivery_status` stub block with:

```sql
-- outbox_delivery_status: each channel's delivery mode for the Outbox
-- screen. Deployment-wide facts, shown only to members of the resort asked
-- about. WhatsApp has no sender; a channel never reported is not_running.

create function public.outbox_delivery_status(p_property uuid)
returns table (channel public.outbox_channel, mode text, provider text,
               detail text, last_run_at timestamptz)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  perform public.assert_resort_role(p_property, false, 'owner', 'admin', 'staff', 'accountant');

  return query
  select c.ch,
         case when c.ch = 'whatsapp' then 'unavailable'
              else coalesce(s.mode, 'not_running') end,
         case when c.ch = 'whatsapp' then null else s.provider end,
         case when c.ch = 'whatsapp' then null else s.detail end,
         case when c.ch = 'whatsapp' then null else s.last_run_at end
    from unnest(enum_range(null::public.outbox_channel)) as c(ch)
    left join public.outbox_channel_status s on s.channel = c.ch
   order by c.ch;
end;
$$;
```

Replace the whole `outbox_dispatch_post` stub block with:

```sql
-- outbox_dispatch_post: the POST the cron tick makes. Kept apart from the
-- tick so tests can check it without writing Vault secrets. Not security
-- definer: only the tick (running as its owner) and superusers call it.

create function public.outbox_dispatch_post(p_url text, p_key text)
returns text
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if coalesce(btrim(p_url), '') = '' or coalesce(btrim(p_key), '') = '' then
    return 'not_configured';
  end if;

  perform net.http_post(
    url                  := btrim(p_url),
    body                 := '{}'::jsonb,
    headers              := jsonb_build_object(
                              'Content-Type', 'application/json',
                              'Authorization', 'Bearer ' || btrim(p_key)),
    timeout_milliseconds := 30000);
  return 'requested';
end;
$$;
```

Replace the whole `outbox_dispatch_tick` stub block with:

```sql
-- outbox_dispatch_tick: what pg_cron runs every minute. Reads the function
-- URL and the service role key from Vault (docs/email-and-sms-delivery.md
-- says how to set them); without them it sends nothing. Vault is read with
-- dynamic SQL, so a database without the vault extension still answers
-- not_configured instead of failing.

create function public.outbox_dispatch_tick()
returns text
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_url text;
  v_key text;
begin
  if to_regclass('vault.decrypted_secrets') is null then
    return 'not_configured';
  end if;

  execute 'select decrypted_secret from vault.decrypted_secrets where name = $1 limit 1'
     into v_url using 'outbox_dispatch_url';
  execute 'select decrypted_secret from vault.decrypted_secrets where name = $1 limit 1'
     into v_key using 'outbox_dispatch_key';

  return public.outbox_dispatch_post(v_url, v_key);
end;
$$;
```

Append at the very end of the migration, after the grants:

```sql
-- ---------------------------------------------------------------------
-- Every minute. Without the two Vault secrets the tick answers
-- 'not_configured' and sends nothing, so a fresh `supabase db reset`
-- never calls out.

select cron.schedule(
  'outbox-dispatch', '* * * * *',
  $$select public.outbox_dispatch_tick()$$);
```

- [ ] **Step 4: Rebuild and run the whole suite**

```bash
supabase db reset
supabase test db supabase/tests/46_email_sms_delivery_test.sql
supabase test db
```
Expected: 46 PASS (84/84). The whole suite passes except the three known time-window failures (25/9, 26/3, 34/2), and those appear only between 00:00 and 05:30 IST.

- [ ] **Step 5: Check that a fresh database never calls out**

```bash
psql postgresql://postgres:postgres@127.0.0.1:54322/postgres -Atc "select public.outbox_dispatch_tick()"
```
Expected: `not_configured`, because `db reset` leaves no Vault secrets.

- [ ] **Step 6: Commit**

```bash
git add supabase/migrations/0056_email_sms_delivery.sql supabase/tests/46_email_sms_delivery_test.sql
git commit -m "feat(outbox): delivery status for the app, dispatcher heartbeat and the pg_cron tick" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Phase 2: Edge Function track (Deno; no database)

All commands in this phase run from the function folder: `(cd supabase/functions/outbox-dispatch && …)`. `deno test` runs with **no** permission flags, so a test that tried to reach the network would fail with a permission error. It never reaches Resend or MSG91.

### Task 5: Resend and MSG91 senders

**Track:** Deno. Depends on Task 1. It can run alongside Task 6.

**Files:**
- Create: `supabase/functions/outbox-dispatch/resend.ts`
- Create: `supabase/functions/outbox-dispatch/msg91.ts`
- Test: `supabase/functions/outbox-dispatch/resend_test.ts`, `supabase/functions/outbox-dispatch/msg91_test.ts`

**Interfaces:**
- Consumes: `EmailSender`, `EmailMessage`, `SmsSender`, `SmsMessage`, `SendResult`, `FetchFn` (`types.ts`); `safeJson`, `clip`, `errorText`, `isRetryableStatus` (`util.ts`); `stubFetch`, `jsonResponse` (`testing.ts`).
- Produces:
  - `resend.ts`:
    - `RESEND_URL = "https://api.resend.com/emails"`
    - `displayName(raw: string | undefined | null): string`
    - `class ResendEmailSender implements EmailSender { constructor(apiKey: string, from: string, fetchFn: FetchFn = fetch) }`
  - `msg91.ts`:
    - `MSG91_FLOW_URL = "https://control.msg91.com/api/v5/flow"`, `DLT_VAR_MAX = 30`
    - `normalizeIndianMobile(raw: string): string | null`
    - `smsVars(vars: Record<string, unknown>): Record<string, string>`
    - `class Msg91SmsSender implements SmsSender { constructor(authKey: string, senderId: string | null, fetchFn: FetchFn = fetch) }`
  - Result rules:
    - 2xx → `{ok: true, providerId}`
    - network error, 408, 429 or 5xx → `{ok: false, retryable: true}`
    - any other 4xx → `{ok: false, retryable: false}`
    - MSG91 HTTP 200 without `"type":"success"` → `{ok: false, retryable: false}`
    - Error text is `resend <status>: <message>`, `resend: network error: <msg>`, `msg91 <status>: <message>`, `msg91: <message>` or `msg91: network error: <msg>`.

- [ ] **Step 1: Write the failing Resend tests**

Create `supabase/functions/outbox-dispatch/resend_test.ts`:

```ts
import { assertEquals } from "@std/assert";
import { displayName, RESEND_URL, ResendEmailSender } from "./resend.ts";
import { jsonResponse, stubFetch } from "./testing.ts";
import type { EmailMessage } from "./types.ts";

const message: EmailMessage = {
  to: "asha@example.com",
  fromName: "Pasala Farm House",
  subject: "Your stay at Pasala Farm House is confirmed",
  text: "Hi Asha Rao, your booking is confirmed.",
  idempotencyKey: "0b7f5c1e-0000-4000-8000-000000000001",
};

Deno.test("sends one POST to Resend with the key, the idempotency key and a plain-text body", async () => {
  const { fetch, calls } = stubFetch([jsonResponse(200, { id: "re_123" })]);
  const sender = new ResendEmailSender("re_test_key", "bookings@mail.example.com", fetch);

  assertEquals(await sender.send(message), { ok: true, providerId: "re_123" });
  assertEquals(calls.length, 1);
  assertEquals(calls[0].url, RESEND_URL);
  assertEquals(calls[0].method, "POST");
  assertEquals(calls[0].headers["authorization"], "Bearer re_test_key");
  assertEquals(calls[0].headers["content-type"], "application/json");
  assertEquals(calls[0].headers["idempotency-key"], message.idempotencyKey);
  assertEquals(calls[0].body, {
    from: "Pasala Farm House <bookings@mail.example.com>",
    to: ["asha@example.com"],
    subject: message.subject,
    text: message.text,
  });
});

Deno.test("a 2xx without an id is still sent", async () => {
  const { fetch } = stubFetch([new Response("", { status: 200 })]);
  const result = await new ResendEmailSender("k", "b@example.com", fetch).send(message);
  assertEquals(result, { ok: true, providerId: null });
});

Deno.test("a 422 is a permanent failure carrying Resend's message", async () => {
  const { fetch } = stubFetch([
    jsonResponse(422, { statusCode: 422, name: "validation_error", message: "Invalid `to` field." }),
  ]);
  const result = await new ResendEmailSender("k", "b@example.com", fetch).send(message);
  assertEquals(result, { ok: false, retryable: false, error: "resend 422: Invalid `to` field." });
});

Deno.test("401 and 403 are permanent (a key or domain problem to fix, not to hammer)", async () => {
  for (const status of [401, 403]) {
    const { fetch } = stubFetch([jsonResponse(status, { message: "nope" })]);
    const result = await new ResendEmailSender("k", "b@example.com", fetch).send(message);
    assertEquals(result, { ok: false, retryable: false, error: `resend ${status}: nope` });
  }
});

Deno.test("429 and 5xx are retryable", async () => {
  for (const status of [429, 500, 503]) {
    const { fetch } = stubFetch([jsonResponse(status, { message: "try later" })]);
    const result = await new ResendEmailSender("k", "b@example.com", fetch).send(message);
    assertEquals(result, { ok: false, retryable: true, error: `resend ${status}: try later` });
  }
});

Deno.test("a network error is retryable", async () => {
  const { fetch } = stubFetch([new TypeError("connection reset")]);
  const result = await new ResendEmailSender("k", "b@example.com", fetch).send(message);
  assertEquals(result, { ok: false, retryable: true, error: "resend: network error: connection reset" });
});

Deno.test("a non-JSON error body is reported as text", async () => {
  const { fetch } = stubFetch([new Response("Bad Gateway", { status: 502 })]);
  const result = await new ResendEmailSender("k", "b@example.com", fetch).send(message);
  assertEquals(result, { ok: false, retryable: true, error: "resend 502: Bad Gateway" });
});

Deno.test("displayName strips header-breaking characters and falls back to ResortHub", () => {
  assertEquals(displayName('Sea "View", <Goa>;\r\nResort'), "Sea View Goa Resort");
  assertEquals(displayName("   "), "ResortHub");
  assertEquals(displayName(undefined), "ResortHub");
  assertEquals(displayName(null), "ResortHub");
});
```

- [ ] **Step 2: Write the failing MSG91 tests**

Create `supabase/functions/outbox-dispatch/msg91_test.ts`:

```ts
import { assertEquals } from "@std/assert";
import { DLT_VAR_MAX, MSG91_FLOW_URL, Msg91SmsSender, normalizeIndianMobile, smsVars } from "./msg91.ts";
import { jsonResponse, stubFetch } from "./testing.ts";

const vars = {
  guest_name: "Asha Rao",
  unit_name: "Mango Cottage",
  property_name: "Pasala Farm House",
  check_in: "01 Mar 2027",
  check_out: "02 Mar 2027",
  total: "11500",
  currency: "INR",
  cancel_reason: "no reason given",
};

Deno.test("normalizeIndianMobile accepts the usual ways of writing an Indian mobile", () => {
  const cases: Array<[string, string | null]> = [
    ["9876543210", "919876543210"],
    ["+91 98765 43210", "919876543210"],
    ["+91-98765-43210", "919876543210"],
    ["098765 43210", "919876543210"],
    ["0091 98765 43210", "919876543210"],
    ["919876543210", "919876543210"],
    ["6000000000", "916000000000"],
    ["5876543210", null], // Indian mobiles start with 6-9
    ["98765 4321", null], // nine digits
    ["+44 7700 900123", null], // not Indian
    ["", null],
    ["no phone on file", null],
  ];
  for (const [raw, expected] of cases) {
    assertEquals(normalizeIndianMobile(raw), expected, raw);
  }
});

Deno.test("smsVars stringifies every variable and cuts it to the DLT limit", () => {
  assertEquals(DLT_VAR_MAX, 30);
  assertEquals(
    smsVars({ guest_name: "A".repeat(40), total: 11500, cancel_reason: null }),
    { guest_name: "A".repeat(30), total: "11500", cancel_reason: "" },
  );
});

Deno.test("sends the flow request with template id, sender, mobile and variables", async () => {
  const { fetch, calls } = stubFetch([
    jsonResponse(200, { type: "success", message: "3567686b6f78313233343536" }),
  ]);
  const result = await new Msg91SmsSender("auth-key", "RSTHUB", fetch).send({
    mobile: "919876543210",
    templateId: "tmpl-confirm",
    vars,
  });

  assertEquals(result, { ok: true, providerId: "3567686b6f78313233343536" });
  assertEquals(calls[0].url, MSG91_FLOW_URL);
  assertEquals(calls[0].method, "POST");
  assertEquals(calls[0].headers["authkey"], "auth-key");
  assertEquals(calls[0].body, {
    template_id: "tmpl-confirm",
    short_url: "0",
    sender: "RSTHUB",
    recipients: [{ ...vars, mobiles: "919876543210" }],
  });
});

Deno.test("no sender field when MSG91_SENDER_ID is not set", async () => {
  const { fetch, calls } = stubFetch([jsonResponse(200, { type: "success", message: "r1" })]);
  await new Msg91SmsSender("auth-key", null, fetch).send({ mobile: "919876543210", templateId: "t", vars });
  assertEquals("sender" in (calls[0].body as Record<string, unknown>), false);
});

Deno.test("a variable named mobiles cannot replace the recipient", async () => {
  const { fetch, calls } = stubFetch([jsonResponse(200, { type: "success", message: "r1" })]);
  await new Msg91SmsSender("k", null, fetch).send({
    mobile: "919876543210",
    templateId: "t",
    vars: { mobiles: "910000000000" },
  });
  const body = calls[0].body as { recipients: Array<Record<string, string>> };
  assertEquals(body.recipients[0].mobiles, "919876543210");
});

Deno.test("HTTP 200 with type error is a permanent failure, never sent", async () => {
  const { fetch } = stubFetch([jsonResponse(200, { type: "error", message: "Template ID is not valid" })]);
  const result = await new Msg91SmsSender("k", null, fetch).send({ mobile: "919876543210", templateId: "t", vars });
  assertEquals(result, { ok: false, retryable: false, error: "msg91: Template ID is not valid" });
});

Deno.test("401 is permanent; 5xx is retryable", async () => {
  const unauthorized = stubFetch([jsonResponse(401, { type: "error", message: "Authentication failure" })]);
  assertEquals(
    await new Msg91SmsSender("k", null, unauthorized.fetch).send({ mobile: "919876543210", templateId: "t", vars }),
    { ok: false, retryable: false, error: "msg91 401: Authentication failure" },
  );
  const down = stubFetch([new Response("Service Unavailable", { status: 503 })]);
  assertEquals(
    await new Msg91SmsSender("k", null, down.fetch).send({ mobile: "919876543210", templateId: "t", vars }),
    { ok: false, retryable: true, error: "msg91 503: Service Unavailable" },
  );
});

Deno.test("a network error is retryable", async () => {
  const { fetch } = stubFetch([new TypeError("dns failure")]);
  const result = await new Msg91SmsSender("k", null, fetch).send({ mobile: "919876543210", templateId: "t", vars });
  assertEquals(result, { ok: false, retryable: true, error: "msg91: network error: dns failure" });
});
```

- [ ] **Step 3: Run them to verify they fail**

Run: `(cd supabase/functions/outbox-dispatch && deno test resend_test.ts msg91_test.ts)`
Expected: FAIL (`Module not found "…/resend.ts"` and `"…/msg91.ts"`).

- [ ] **Step 4: Implement the senders**

Create `supabase/functions/outbox-dispatch/resend.ts`:

```ts
// Email through the Resend HTTP API (https://resend.com/docs/api-reference/emails/send-email).
import type { EmailMessage, EmailSender, FetchFn, SendResult } from "./types.ts";
import { clip, errorText, isRetryableStatus, safeJson } from "./util.ts";

export const RESEND_URL = "https://api.resend.com/emails";

/**
 * The sender's display name: the resort's name without the characters
 * that would break a `Name <address>` header; "ResortHub" when empty.
 */
export function displayName(raw: string | undefined | null): string {
  const cleaned = (raw ?? "").replace(/[<>",;\r\n]/g, " ").replace(/\s+/g, " ").trim();
  return cleaned === "" ? "ResortHub" : cleaned;
}

export class ResendEmailSender implements EmailSender {
  constructor(
    private readonly apiKey: string,
    private readonly from: string,
    private readonly fetchFn: FetchFn = fetch,
  ) {}

  async send(message: EmailMessage): Promise<SendResult> {
    let response: Response;
    try {
      response = await this.fetchFn(RESEND_URL, {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${this.apiKey}`,
          "Content-Type": "application/json",
          // The outbox row id: if a run dies after Resend accepted the
          // email, the retry of the same row is not delivered twice.
          "Idempotency-Key": message.idempotencyKey,
        },
        body: JSON.stringify({
          from: `${displayName(message.fromName)} <${this.from}>`,
          to: [message.to],
          subject: message.subject,
          text: message.text,
        }),
      });
    } catch (e) {
      return { ok: false, retryable: true, error: clip(`resend: network error: ${errorText(e)}`) };
    }

    const text = await response.text();
    const json = safeJson(text);
    if (response.ok) {
      return { ok: true, providerId: typeof json?.id === "string" ? json.id : null };
    }
    const detail = typeof json?.message === "string" ? json.message : text;
    return {
      ok: false,
      retryable: isRetryableStatus(response.status),
      error: clip(`resend ${response.status}: ${detail}`),
    };
  }
}
```

Create `supabase/functions/outbox-dispatch/msg91.ts`:

```ts
// SMS through the MSG91 Flow API (DLT-registered templates, India).
import type { FetchFn, SendResult, SmsMessage, SmsSender } from "./types.ts";
import { clip, errorText, isRetryableStatus, safeJson } from "./util.ts";

export const MSG91_FLOW_URL = "https://control.msg91.com/api/v5/flow";

/** DLT (TRAI) templates allow at most 30 characters per variable. */
export const DLT_VAR_MAX = 30;

/**
 * `91` + a 10-digit Indian mobile number (first digit 6-9), however the
 * guest typed it ("+91 98765 43210", "098765 43210", "0091 …"), or null
 * when it is not an Indian mobile number.
 */
export function normalizeIndianMobile(raw: string): string | null {
  let digits = raw.replace(/\D/g, "");
  if (digits.startsWith("00")) digits = digits.slice(2);
  let national: string;
  if (digits.length === 10) {
    national = digits;
  } else if (digits.length === 11 && digits.startsWith("0")) {
    national = digits.slice(1);
  } else if (digits.length === 12 && digits.startsWith("91")) {
    national = digits.slice(2);
  } else {
    return null;
  }
  return /^[6-9]\d{9}$/.test(national) ? `91${national}` : null;
}

/** Template variables as MSG91 wants them: strings, each cut to the DLT limit. */
export function smsVars(vars: Record<string, unknown>): Record<string, string> {
  const out: Record<string, string> = {};
  for (const [key, value] of Object.entries(vars)) {
    out[key] = String(value ?? "").slice(0, DLT_VAR_MAX);
  }
  return out;
}

export class Msg91SmsSender implements SmsSender {
  constructor(
    private readonly authKey: string,
    private readonly senderId: string | null,
    private readonly fetchFn: FetchFn = fetch,
  ) {}

  async send(message: SmsMessage): Promise<SendResult> {
    const payload: Record<string, unknown> = {
      template_id: message.templateId,
      short_url: "0",
      // mobiles last, so no template variable can replace the recipient.
      recipients: [{ ...smsVars(message.vars), mobiles: message.mobile }],
    };
    if (this.senderId) payload.sender = this.senderId;

    let response: Response;
    try {
      response = await this.fetchFn(MSG91_FLOW_URL, {
        method: "POST",
        headers: {
          "authkey": this.authKey,
          "Content-Type": "application/json",
          "Accept": "application/json",
        },
        body: JSON.stringify(payload),
      });
    } catch (e) {
      return { ok: false, retryable: true, error: clip(`msg91: network error: ${errorText(e)}`) };
    }

    const text = await response.text();
    const json = safeJson(text);
    const detail = typeof json?.message === "string" ? json.message : text;
    if (!response.ok) {
      return {
        ok: false,
        retryable: isRetryableStatus(response.status),
        error: clip(`msg91 ${response.status}: ${detail}`),
      };
    }
    if (json?.type === "success") {
      return { ok: true, providerId: typeof json.message === "string" ? json.message : null };
    }
    // MSG91 reports many refusals (bad template, DLT mismatch, no balance)
    // as HTTP 200 with type "error". Retrying will not fix them.
    return { ok: false, retryable: false, error: clip(`msg91: ${detail}`) };
  }
}
```

- [ ] **Step 5: Run the tests and type-check**

```bash
(cd supabase/functions/outbox-dispatch && deno test resend_test.ts msg91_test.ts && deno check resend.ts msg91.ts)
```
Expected: all PASS, no type errors.

- [ ] **Step 6: Commit**

```bash
git add supabase/functions/outbox-dispatch/resend.ts supabase/functions/outbox-dispatch/msg91.ts \
  supabase/functions/outbox-dispatch/resend_test.ts supabase/functions/outbox-dispatch/msg91_test.ts
git commit -m "feat(outbox-dispatch): Resend email and MSG91 SMS senders" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Configuration and the PostgREST store

**Track:** Deno. Depends on Task 1. It can run alongside Task 5.

**Files:**
- Create: `supabase/functions/outbox-dispatch/config.ts`
- Create: `supabase/functions/outbox-dispatch/store.ts`
- Test: `supabase/functions/outbox-dispatch/config_test.ts`, `supabase/functions/outbox-dispatch/store_test.ts`

**Interfaces:**
- Consumes: `DispatchConfig`, `Setup`, `EmailConfig`, `SmsConfig`, `OutboxStore`, `ClaimedMessage`, `Outcome`, `ChannelMode`, `FetchFn` (`types.ts`); `clip` (`util.ts`); `stubFetch`, `jsonResponse` (`testing.ts`). The SQL contract: RPC names and argument names from Task 1.
- Produces:
  - `config.ts`:
    - `class ConfigError extends Error`
    - `parseBatchSize(raw?: string): number` (default 50, clamped to 1..200, non-integers give 50)
    - `loadConfig(env: (name: string) => string | undefined): DispatchConfig`. Values are trimmed, and blank counts as unset. `SUPABASE_URL` loses any trailing slash; it and `SUPABASE_SERVICE_ROLE_KEY` are required (`ConfigError "<NAME> is not set"`).
    - Email is live only with `RESEND_API_KEY` and a bare-address `RESEND_FROM`. Otherwise it is a `dry_run` with detail `RESEND_API_KEY is not set`, `RESEND_FROM is not set` or `RESEND_FROM is not an email address`.
    - SMS is live only with `MSG91_AUTH_KEY` and a JSON-object `MSG91_TEMPLATES`. Otherwise it is a `dry_run` with detail `MSG91_AUTH_KEY is not set`, `MSG91_TEMPLATES is not set`, `MSG91_TEMPLATES is not valid JSON` or `MSG91_TEMPLATES must be a JSON object`. Non-string or blank template ids are dropped. `MSG91_SENDER_ID` is optional.
    - Providers: `resend` and `msg91`.
  - `store.ts`:
    - `class StoreError extends Error { status: number }`
    - `outcomeArgs(id, outcome): { p_id, p_outcome, p_error, p_provider_id }`
    - `class RestOutboxStore implements OutboxStore { constructor(supabaseUrl: string, serviceKey: string, fetchFn: FetchFn = fetch) }`. It POSTs to `<url>/rest/v1/rpc/<name>` with the headers `apikey`, `Authorization: Bearer` and `Content-Type: application/json`.

- [ ] **Step 1: Write the failing config tests**

Create `supabase/functions/outbox-dispatch/config_test.ts`:

```ts
import { assertEquals, assertThrows } from "@std/assert";
import { ConfigError, loadConfig, parseBatchSize } from "./config.ts";

function envOf(values: Record<string, string>): (name: string) => string | undefined {
  return (name) => values[name];
}

const base = {
  SUPABASE_URL: "http://127.0.0.1:54321/",
  SUPABASE_SERVICE_ROLE_KEY: "service-key",
};

Deno.test("with no provider keys both channels are a dry run with a reason", () => {
  const config = loadConfig(envOf(base));
  assertEquals(config.supabaseUrl, "http://127.0.0.1:54321");
  assertEquals(config.serviceKey, "service-key");
  assertEquals(config.batchSize, 50);
  assertEquals(config.email, { mode: "dry_run", provider: "resend", detail: "RESEND_API_KEY is not set" });
  assertEquals(config.sms, { mode: "dry_run", provider: "msg91", detail: "MSG91_AUTH_KEY is not set" });
});

Deno.test("email needs a key and a bare sender address", () => {
  assertEquals(
    loadConfig(envOf({ ...base, RESEND_API_KEY: "re_k" })).email,
    { mode: "dry_run", provider: "resend", detail: "RESEND_FROM is not set" },
  );
  assertEquals(
    loadConfig(envOf({ ...base, RESEND_API_KEY: "re_k", RESEND_FROM: "Bookings <b@x.com>" })).email,
    { mode: "dry_run", provider: "resend", detail: "RESEND_FROM is not an email address" },
  );
  assertEquals(
    loadConfig(envOf({ ...base, RESEND_API_KEY: " re_k ", RESEND_FROM: "bookings@mail.example.com" })).email,
    { mode: "live", provider: "resend", config: { apiKey: "re_k", from: "bookings@mail.example.com" } },
  );
});

Deno.test("a blank key counts as unset", () => {
  assertEquals(
    loadConfig(envOf({ ...base, RESEND_API_KEY: "   ", MSG91_AUTH_KEY: "" })).email.mode,
    "dry_run",
  );
});

Deno.test("SMS needs a key and a JSON object of template ids", () => {
  const withKey = { ...base, MSG91_AUTH_KEY: "auth" };
  assertEquals(
    loadConfig(envOf(withKey)).sms,
    { mode: "dry_run", provider: "msg91", detail: "MSG91_TEMPLATES is not set" },
  );
  assertEquals(
    loadConfig(envOf({ ...withKey, MSG91_TEMPLATES: "{oops" })).sms,
    { mode: "dry_run", provider: "msg91", detail: "MSG91_TEMPLATES is not valid JSON" },
  );
  assertEquals(
    loadConfig(envOf({ ...withKey, MSG91_TEMPLATES: '["a"]' })).sms,
    { mode: "dry_run", provider: "msg91", detail: "MSG91_TEMPLATES must be a JSON object" },
  );
  assertEquals(
    loadConfig(envOf({
      ...withKey,
      MSG91_SENDER_ID: "RSTHUB",
      MSG91_TEMPLATES: '{"booking_confirmation_sms":" t1 ","cancellation_sms":"","x":5}',
    })).sms,
    {
      mode: "live",
      provider: "msg91",
      config: { authKey: "auth", senderId: "RSTHUB", templates: { booking_confirmation_sms: "t1" } },
    },
  );
  assertEquals(
    loadConfig(envOf({ ...withKey, MSG91_TEMPLATES: "{}" })).sms,
    { mode: "live", provider: "msg91", config: { authKey: "auth", senderId: null, templates: {} } },
  );
});

Deno.test("OUTBOX_BATCH_SIZE is clamped to 1..200 and defaults to 50", () => {
  assertEquals(parseBatchSize(undefined), 50);
  assertEquals(parseBatchSize("abc"), 50);
  assertEquals(parseBatchSize("2.5"), 50);
  assertEquals(parseBatchSize("0"), 1);
  assertEquals(parseBatchSize("500"), 200);
  assertEquals(parseBatchSize("25"), 25);
  assertEquals(loadConfig(envOf({ ...base, OUTBOX_BATCH_SIZE: "10" })).batchSize, 10);
});

Deno.test("the Supabase URL and service key are required", () => {
  assertThrows(() => loadConfig(envOf({ SUPABASE_SERVICE_ROLE_KEY: "k" })), ConfigError, "SUPABASE_URL is not set");
  assertThrows(() => loadConfig(envOf({ SUPABASE_URL: "http://x" })), ConfigError, "SUPABASE_SERVICE_ROLE_KEY is not set");
});
```

- [ ] **Step 2: Write the failing store tests**

Create `supabase/functions/outbox-dispatch/store_test.ts`:

```ts
import { assertEquals, assertRejects } from "@std/assert";
import { outcomeArgs, RestOutboxStore, StoreError } from "./store.ts";
import { jsonResponse, stubFetch } from "./testing.ts";
import type { ChannelMode, ClaimedMessage } from "./types.ts";

const url = "http://127.0.0.1:54321";

const row: ClaimedMessage = {
  id: "m1",
  property_id: "p1",
  reservation_id: "r1",
  channel: "email",
  recipient: "asha@example.com",
  template: "booking_confirmation",
  subject: "s",
  body: "b",
  attempts: 1,
  vars: { property_name: "Pasala Farm House" },
};

Deno.test("claim posts p_limit to claim_outbox_batch with the service key", async () => {
  const { fetch, calls } = stubFetch([jsonResponse(200, [row])]);
  const rows = await new RestOutboxStore(url, "service-key", fetch).claim(50);

  assertEquals(rows, [row]);
  assertEquals(calls[0].url, `${url}/rest/v1/rpc/claim_outbox_batch`);
  assertEquals(calls[0].method, "POST");
  assertEquals(calls[0].headers["apikey"], "service-key");
  assertEquals(calls[0].headers["authorization"], "Bearer service-key");
  assertEquals(calls[0].headers["content-type"], "application/json");
  assertEquals(calls[0].body, { p_limit: 50 });
});

Deno.test("an empty or odd claim reply is no rows", async () => {
  const { fetch } = stubFetch([jsonResponse(200, []), jsonResponse(200, null)]);
  const store = new RestOutboxStore(url, "k", fetch);
  assertEquals(await store.claim(10), []);
  assertEquals(await store.claim(10), []);
});

Deno.test("complete sends each outcome's arguments and returns the new status", async () => {
  const { fetch, calls } = stubFetch([jsonResponse(200, "sent"), jsonResponse(200, "pending")]);
  const store = new RestOutboxStore(url, "k", fetch);

  assertEquals(await store.complete("m1", { kind: "sent", providerId: "re_1" }), "sent");
  assertEquals(await store.complete("m2", { kind: "retry", error: "resend 503: busy" }), "pending");
  assertEquals(calls[0].url, `${url}/rest/v1/rpc/complete_outbox_message`);
  assertEquals(calls[0].body, { p_id: "m1", p_outcome: "sent", p_error: null, p_provider_id: "re_1" });
  assertEquals(calls[1].body, { p_id: "m2", p_outcome: "retry", p_error: "resend 503: busy", p_provider_id: null });
});

Deno.test("outcomeArgs maps dry_run and failed", () => {
  assertEquals(
    outcomeArgs("m3", { kind: "dry_run", reason: "Dry run: RESEND_API_KEY is not set" }),
    { p_id: "m3", p_outcome: "dry_run", p_error: "Dry run: RESEND_API_KEY is not set", p_provider_id: null },
  );
  assertEquals(
    outcomeArgs("m4", { kind: "failed", error: "resend 422: bad to" }),
    { p_id: "m4", p_outcome: "failed", p_error: "resend 422: bad to", p_provider_id: null },
  );
});

Deno.test("recordRun sends p_channels and accepts an empty reply", async () => {
  const { fetch, calls } = stubFetch([new Response(null, { status: 204 })]);
  const modes: ChannelMode[] = [
    { channel: "email", mode: "dry_run", provider: "resend", detail: "RESEND_API_KEY is not set" },
    { channel: "sms", mode: "live", provider: "msg91", detail: null },
  ];
  await new RestOutboxStore(url, "k", fetch).recordRun(modes);
  assertEquals(calls[0].url, `${url}/rest/v1/rpc/record_outbox_dispatch_run`);
  assertEquals(calls[0].body, { p_channels: modes });
});

Deno.test("a PostgREST error becomes a StoreError with the status", async () => {
  const { fetch } = stubFetch([
    jsonResponse(403, { code: "42501", message: "permission denied for function claim_outbox_batch" }),
  ]);
  const error = await assertRejects(() => new RestOutboxStore(url, "k", fetch).claim(10), StoreError);
  assertEquals(error.status, 403);
  assertEquals(error.message.startsWith("claim_outbox_batch 403: "), true);
});
```

- [ ] **Step 3: Run them to verify they fail**

Run: `(cd supabase/functions/outbox-dispatch && deno test config_test.ts store_test.ts)`
Expected: FAIL (`Module not found "…/config.ts"` and `"…/store.ts"`).

- [ ] **Step 4: Implement config and store**

Create `supabase/functions/outbox-dispatch/config.ts`:

```ts
// Reads the function's configuration from its environment (Supabase Edge
// Function secrets). Each channel is live only when its provider's keys
// are set; otherwise it is a dry run with the reason, and nothing is sent.
import type { DispatchConfig, EmailConfig, Setup, SmsConfig } from "./types.ts";

export class ConfigError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "ConfigError";
  }
}

type Get = (name: string) => string | undefined;

// A bare address only: the display name is the resort's name.
const EMAIL_RE = /^[^\s@<>"]+@[^\s@<>"]+\.[^\s@<>"]+$/;

export function parseBatchSize(raw?: string): number {
  const n = raw === undefined ? NaN : Number(raw);
  if (!Number.isInteger(n)) return 50;
  return Math.min(Math.max(n, 1), 200);
}

function emailSetup(get: Get): Setup<EmailConfig> {
  const dry = (detail: string): Setup<EmailConfig> => ({ mode: "dry_run", provider: "resend", detail });
  const apiKey = get("RESEND_API_KEY");
  if (!apiKey) return dry("RESEND_API_KEY is not set");
  const from = get("RESEND_FROM");
  if (!from) return dry("RESEND_FROM is not set");
  if (!EMAIL_RE.test(from)) return dry("RESEND_FROM is not an email address");
  return { mode: "live", provider: "resend", config: { apiKey, from } };
}

function smsSetup(get: Get): Setup<SmsConfig> {
  const dry = (detail: string): Setup<SmsConfig> => ({ mode: "dry_run", provider: "msg91", detail });
  const authKey = get("MSG91_AUTH_KEY");
  if (!authKey) return dry("MSG91_AUTH_KEY is not set");
  const raw = get("MSG91_TEMPLATES");
  if (!raw) return dry("MSG91_TEMPLATES is not set");
  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch {
    return dry("MSG91_TEMPLATES is not valid JSON");
  }
  if (parsed === null || typeof parsed !== "object" || Array.isArray(parsed)) {
    return dry("MSG91_TEMPLATES must be a JSON object");
  }
  const templates: Record<string, string> = {};
  for (const [name, id] of Object.entries(parsed as Record<string, unknown>)) {
    if (typeof id === "string" && id.trim() !== "") templates[name] = id.trim();
  }
  return {
    mode: "live",
    provider: "msg91",
    config: { authKey, senderId: get("MSG91_SENDER_ID") ?? null, templates },
  };
}

export function loadConfig(env: (name: string) => string | undefined): DispatchConfig {
  const get: Get = (name) => {
    const value = env(name)?.trim();
    return value ? value : undefined;
  };
  const supabaseUrl = get("SUPABASE_URL");
  if (!supabaseUrl) throw new ConfigError("SUPABASE_URL is not set");
  const serviceKey = get("SUPABASE_SERVICE_ROLE_KEY");
  if (!serviceKey) throw new ConfigError("SUPABASE_SERVICE_ROLE_KEY is not set");
  return {
    supabaseUrl: supabaseUrl.replace(/\/+$/, ""),
    serviceKey,
    batchSize: parseBatchSize(get("OUTBOX_BATCH_SIZE")),
    email: emailSetup(get),
    sms: smsSetup(get),
  };
}
```

Create `supabase/functions/outbox-dispatch/store.ts`:

```ts
// The dispatcher's three RPCs (0056_email_sms_delivery.sql), called
// through PostgREST with the service role key -- the only role they are
// granted to.
import type { ChannelMode, ClaimedMessage, FetchFn, Outcome, OutboxStore } from "./types.ts";
import { clip } from "./util.ts";

export class StoreError extends Error {
  constructor(readonly status: number, message: string) {
    super(message);
    this.name = "StoreError";
  }
}

/** `complete_outbox_message`'s arguments for one outcome. */
export function outcomeArgs(id: string, outcome: Outcome): Record<string, string | null> {
  switch (outcome.kind) {
    case "sent":
      return { p_id: id, p_outcome: "sent", p_error: null, p_provider_id: outcome.providerId };
    case "dry_run":
      return { p_id: id, p_outcome: "dry_run", p_error: outcome.reason, p_provider_id: null };
    case "retry":
      return { p_id: id, p_outcome: "retry", p_error: outcome.error, p_provider_id: null };
    case "failed":
      return { p_id: id, p_outcome: "failed", p_error: outcome.error, p_provider_id: null };
  }
}

export class RestOutboxStore implements OutboxStore {
  constructor(
    private readonly supabaseUrl: string,
    private readonly serviceKey: string,
    private readonly fetchFn: FetchFn = fetch,
  ) {}

  private async rpc(name: string, args: Record<string, unknown>): Promise<unknown> {
    const response = await this.fetchFn(`${this.supabaseUrl}/rest/v1/rpc/${name}`, {
      method: "POST",
      headers: {
        "apikey": this.serviceKey,
        "Authorization": `Bearer ${this.serviceKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(args),
    });
    const text = await response.text();
    if (!response.ok) {
      throw new StoreError(response.status, clip(`${name} ${response.status}: ${text}`));
    }
    return text.trim() === "" ? null : JSON.parse(text);
  }

  async claim(limit: number): Promise<ClaimedMessage[]> {
    const rows = await this.rpc("claim_outbox_batch", { p_limit: limit });
    return Array.isArray(rows) ? rows as ClaimedMessage[] : [];
  }

  async complete(id: string, outcome: Outcome): Promise<string> {
    return String(await this.rpc("complete_outbox_message", outcomeArgs(id, outcome)));
  }

  async recordRun(modes: ChannelMode[]): Promise<void> {
    await this.rpc("record_outbox_dispatch_run", { p_channels: modes });
  }
}
```

- [ ] **Step 5: Run the tests and type-check**

```bash
(cd supabase/functions/outbox-dispatch && deno test config_test.ts store_test.ts && deno check config.ts store.ts)
```
Expected: all PASS, no type errors.

- [ ] **Step 6: Commit**

```bash
git add supabase/functions/outbox-dispatch/config.ts supabase/functions/outbox-dispatch/store.ts \
  supabase/functions/outbox-dispatch/config_test.ts supabase/functions/outbox-dispatch/store_test.ts
git commit -m "feat(outbox-dispatch): per-channel config with dry-run reasons, PostgREST store" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Dispatch loop, HTTP handler, wiring and docs

**Track:** Deno. Depends on Tasks 5 and 6.

**Files:**
- Create: `supabase/functions/outbox-dispatch/dispatch.ts`, `handler.ts`, `deps.ts`, `index.ts`, `fakes.ts`
- Test: `supabase/functions/outbox-dispatch/dispatch_test.ts`, `handler_test.ts`, `deps_test.ts`
- Create: `docs/email-and-sms-delivery.md`
- Modify: `README.md` (the "Notification outbox (phase 2)" bullets near line 107, the out-of-scope bullet near line 169, and the known-limitations bullet near line 437)
- Modify: `docs/STATUS.md` (the "notification outbox is queued, never sent" bullet near line 82, and item 3 near line 115)

**Interfaces:**
- Consumes: everything in `types.ts`, `util.ts` and `testing.ts`; `normalizeIndianMobile`, `Msg91SmsSender`, `MSG91_FLOW_URL` (Task 5); `ResendEmailSender`, `RESEND_URL` (Task 5); `loadConfig`, `ConfigError` (Task 6); `RestOutboxStore` (Task 6).
- Produces:
  - `dispatch.ts`:
    - `interface DispatchDeps { config: DispatchConfig; store: OutboxStore; email: EmailSender | null; sms: SmsSender | null; log(entry: Record<string, unknown>): void }`
    - `channelModes(config): ChannelMode[]`
    - `deliver(row, deps): Promise<Outcome>`
    - `dispatchOnce(deps): Promise<DispatchSummary>`
  - `handler.ts`:
    - `timingSafeEqual(a, b): boolean`
    - `bearerMatches(header: string | null, key: string): boolean`
    - `handleRequest(req: Request, makeDeps: () => DispatchDeps): Promise<Response>`. Its replies:
      - 405 `{error:"method_not_allowed"}`
      - 500 `{error:"not_configured", detail}`
      - 401 `{error:"unauthorized"}`
      - 200 with the summary
      - 502 `{error:"store_unavailable"}`
  - `deps.ts`: `buildDeps(env, fetchFn = fetch, log = console JSON line): DispatchDeps`
  - `index.ts`: `Deno.serve`
  - `fakes.ts`: `FakeStore`, `FakeEmailSender`, `FakeSmsSender`, `liveConfig`, `dryConfig`, `emailRow(overrides)`, `smsRow(overrides)`

- [ ] **Step 1: Write the test doubles**

Create `supabase/functions/outbox-dispatch/fakes.ts`:

```ts
// Test-only doubles. Not a *_test.ts file and never imported by index.ts.
import type {
  ChannelMode,
  ClaimedMessage,
  DispatchConfig,
  EmailMessage,
  EmailSender,
  Outcome,
  OutboxStore,
  SendResult,
  SmsMessage,
  SmsSender,
} from "./types.ts";

export const liveConfig: DispatchConfig = {
  supabaseUrl: "http://127.0.0.1:54321",
  serviceKey: "service-key",
  batchSize: 50,
  email: { mode: "live", provider: "resend", config: { apiKey: "re_k", from: "bookings@mail.example.com" } },
  sms: {
    mode: "live",
    provider: "msg91",
    config: { authKey: "auth", senderId: null, templates: { booking_confirmation_sms: "tmpl-confirm" } },
  },
};

export const dryConfig: DispatchConfig = {
  ...liveConfig,
  email: { mode: "dry_run", provider: "resend", detail: "RESEND_API_KEY is not set" },
  sms: { mode: "dry_run", provider: "msg91", detail: "MSG91_AUTH_KEY is not set" },
};

export function emailRow(overrides: Partial<ClaimedMessage> = {}): ClaimedMessage {
  return {
    id: "0b7f5c1e-0000-4000-8000-000000000001",
    property_id: "p1",
    reservation_id: "r1",
    channel: "email",
    recipient: "asha@example.com",
    template: "booking_confirmation",
    subject: "Your stay at Pasala Farm House is confirmed",
    body: "Hi Asha Rao, your booking for Mango Cottage is confirmed.",
    attempts: 1,
    vars: { guest_name: "Asha Rao", unit_name: "Mango Cottage", property_name: "Pasala Farm House" },
    ...overrides,
  };
}

export function smsRow(overrides: Partial<ClaimedMessage> = {}): ClaimedMessage {
  return {
    id: "0b7f5c1e-0000-4000-8000-000000000002",
    property_id: "p1",
    reservation_id: "r1",
    channel: "sms",
    recipient: "+91 98765 43210",
    template: "booking_confirmation_sms",
    subject: null,
    body: "Pasala Resorts: Hi Asha Rao, your stay at Mango Cottage is confirmed.",
    attempts: 1,
    vars: { guest_name: "Asha Rao", unit_name: "Mango Cottage", property_name: "Pasala Farm House" },
    ...overrides,
  };
}

export class FakeStore implements OutboxStore {
  rows: ClaimedMessage[] = [];
  claimError: Error | null = null;
  recordError: Error | null = null;
  readonly failCompleteFor = new Set<string>();
  readonly claimLimits: number[] = [];
  readonly completed: Array<{ id: string; outcome: Outcome }> = [];
  readonly runs: ChannelMode[][] = [];

  claim(limit: number): Promise<ClaimedMessage[]> {
    this.claimLimits.push(limit);
    return this.claimError ? Promise.reject(this.claimError) : Promise.resolve(this.rows);
  }

  complete(id: string, outcome: Outcome): Promise<string> {
    if (this.failCompleteFor.has(id)) return Promise.reject(new Error(`complete failed for ${id}`));
    this.completed.push({ id, outcome });
    return Promise.resolve(outcome.kind === "retry" ? "pending" : outcome.kind);
  }

  recordRun(modes: ChannelMode[]): Promise<void> {
    if (this.recordError) return Promise.reject(this.recordError);
    this.runs.push(modes);
    return Promise.resolve();
  }
}

export class FakeEmailSender implements EmailSender {
  readonly sent: EmailMessage[] = [];
  results: Array<SendResult | Error> = [];

  send(message: EmailMessage): Promise<SendResult> {
    this.sent.push(message);
    const fallback: SendResult = { ok: true, providerId: "re_default" };
    const next = this.results.shift() ?? fallback;
    return next instanceof Error ? Promise.reject(next) : Promise.resolve(next);
  }
}

export class FakeSmsSender implements SmsSender {
  readonly sent: SmsMessage[] = [];
  results: Array<SendResult | Error> = [];

  send(message: SmsMessage): Promise<SendResult> {
    this.sent.push(message);
    const fallback: SendResult = { ok: true, providerId: "msg91_default" };
    const next = this.results.shift() ?? fallback;
    return next instanceof Error ? Promise.reject(next) : Promise.resolve(next);
  }
}
```

- [ ] **Step 2: Write the failing dispatch tests**

Create `supabase/functions/outbox-dispatch/dispatch_test.ts`:

```ts
import { assertEquals } from "@std/assert";
import { channelModes, deliver, type DispatchDeps, dispatchOnce } from "./dispatch.ts";
import { dryConfig, emailRow, FakeEmailSender, FakeSmsSender, FakeStore, liveConfig, smsRow } from "./fakes.ts";
import type { DispatchConfig } from "./types.ts";

function depsFor(
  config: DispatchConfig,
  store: FakeStore = new FakeStore(),
  email: FakeEmailSender | null = null,
  sms: FakeSmsSender | null = null,
) {
  const logs: Record<string, unknown>[] = [];
  const deps: DispatchDeps = { config, store, email, sms, log: (entry) => logs.push(entry) };
  return { deps, store, logs };
}

Deno.test("without keys every row is a dry run with its reason, and nothing is sent", async () => {
  const store = new FakeStore();
  store.rows = [emailRow(), smsRow()];
  const { deps } = depsFor(dryConfig, store);

  const summary = await dispatchOnce(deps);

  assertEquals(store.completed, [
    { id: emailRow().id, outcome: { kind: "dry_run", reason: "Dry run: RESEND_API_KEY is not set" } },
    { id: smsRow().id, outcome: { kind: "dry_run", reason: "Dry run: MSG91_AUTH_KEY is not set" } },
  ]);
  assertEquals(summary, {
    claimed: 2, sent: 0, dry_run: 2, retry: 0, failed: 0, errors: 0,
    modes: { email: "dry_run", sms: "dry_run" },
  });
  assertEquals(store.runs, [channelModes(dryConfig)]);
  assertEquals(store.claimLimits, [50]);
});

Deno.test("channelModes reports each channel's mode, provider and reason", () => {
  assertEquals(channelModes(dryConfig), [
    { channel: "email", mode: "dry_run", provider: "resend", detail: "RESEND_API_KEY is not set" },
    { channel: "sms", mode: "dry_run", provider: "msg91", detail: "MSG91_AUTH_KEY is not set" },
  ]);
  assertEquals(channelModes(liveConfig), [
    { channel: "email", mode: "live", provider: "resend", detail: null },
    { channel: "sms", mode: "live", provider: "msg91", detail: null },
  ]);
});

Deno.test("a live email goes out with the resort name and the row id as idempotency key", async () => {
  const email = new FakeEmailSender();
  email.results = [{ ok: true, providerId: "re_123" }];
  const { deps } = depsFor(liveConfig, undefined, email, new FakeSmsSender());

  assertEquals(await deliver(emailRow(), deps), { kind: "sent", providerId: "re_123" });
  assertEquals(email.sent, [{
    to: "asha@example.com",
    fromName: "Pasala Farm House",
    subject: emailRow().subject!,
    text: emailRow().body!,
    idempotencyKey: emailRow().id,
  }]);
});

Deno.test("provider failures become retry or failed", async () => {
  const email = new FakeEmailSender();
  email.results = [
    { ok: false, retryable: true, error: "resend 503: busy" },
    { ok: false, retryable: false, error: "resend 422: bad to" },
  ];
  const { deps } = depsFor(liveConfig, undefined, email, new FakeSmsSender());

  assertEquals(await deliver(emailRow(), deps), { kind: "retry", error: "resend 503: busy" });
  assertEquals(await deliver(emailRow(), deps), { kind: "failed", error: "resend 422: bad to" });
});

Deno.test("an email row with no body fails without calling Resend", async () => {
  const email = new FakeEmailSender();
  const { deps } = depsFor(liveConfig, undefined, email, new FakeSmsSender());

  assertEquals(await deliver(emailRow({ body: null }), deps), {
    kind: "failed",
    error: "nothing to send: the message has no subject or body",
  });
  assertEquals(email.sent.length, 0);
});

Deno.test("SMS: normalised mobile, template id from the map, variables passed through", async () => {
  const sms = new FakeSmsSender();
  sms.results = [{ ok: true, providerId: "msg91-req-1" }];
  const { deps } = depsFor(liveConfig, undefined, new FakeEmailSender(), sms);

  assertEquals(await deliver(smsRow(), deps), { kind: "sent", providerId: "msg91-req-1" });
  assertEquals(sms.sent, [{ mobile: "919876543210", templateId: "tmpl-confirm", vars: smsRow().vars }]);
});

Deno.test("SMS with no template id, or to a non-Indian number, fails at once", async () => {
  const sms = new FakeSmsSender();
  const { deps } = depsFor(liveConfig, undefined, new FakeEmailSender(), sms);

  assertEquals(await deliver(smsRow({ template: "cancellation_sms" }), deps), {
    kind: "failed",
    error: "no MSG91 template id for cancellation_sms in MSG91_TEMPLATES",
  });
  assertEquals(await deliver(smsRow({ recipient: "+44 7700 900123" }), deps), {
    kind: "failed",
    error: "the phone number on file is not a valid Indian mobile number",
  });
  assertEquals(sms.sent.length, 0);
});

Deno.test("email can be live while SMS is a dry run", async () => {
  const config: DispatchConfig = { ...liveConfig, sms: dryConfig.sms };
  const store = new FakeStore();
  store.rows = [emailRow(), smsRow()];
  const { deps } = depsFor(config, store, new FakeEmailSender(), null);

  const summary = await dispatchOnce(deps);

  assertEquals(summary.sent, 1);
  assertEquals(summary.dry_run, 1);
  assertEquals(summary.modes, { email: "live", sms: "dry_run" });
});

Deno.test("a sender that throws is retried later", async () => {
  const email = new FakeEmailSender();
  email.results = [new Error("boom")];
  const store = new FakeStore();
  store.rows = [emailRow()];
  const { deps } = depsFor(liveConfig, store, email, new FakeSmsSender());

  const summary = await dispatchOnce(deps);

  assertEquals(store.completed, [{ id: emailRow().id, outcome: { kind: "retry", error: "unexpected error: boom" } }]);
  assertEquals(summary.retry, 1);
});

Deno.test("if recording one row fails the run carries on with the next", async () => {
  const store = new FakeStore();
  store.rows = [emailRow({ id: "m1" }), emailRow({ id: "m2" })];
  store.failCompleteFor.add("m1");
  const { deps, logs } = depsFor(liveConfig, store, new FakeEmailSender(), new FakeSmsSender());

  const summary = await dispatchOnce(deps);

  assertEquals(store.completed.map((c) => c.id), ["m2"]);
  assertEquals(summary.errors, 1);
  assertEquals(summary.sent, 1);
  assertEquals(logs.some((l) => l.event === "outbox_complete_failed" && l.id === "m1"), true);
});

Deno.test("a failed run record is counted, not fatal", async () => {
  const store = new FakeStore();
  store.rows = [emailRow()];
  store.recordError = new Error("db down");
  const { deps } = depsFor(dryConfig, store);

  const summary = await dispatchOnce(deps);

  assertEquals(summary.dry_run, 1);
  assertEquals(summary.errors, 1);
});

Deno.test("logs never carry a recipient, subject or body", async () => {
  const store = new FakeStore();
  store.rows = [emailRow(), smsRow()];
  const email = new FakeEmailSender();
  email.results = [{ ok: false, retryable: false, error: "resend 422: asha@example.com is invalid" }];
  const { deps, logs } = depsFor(liveConfig, store, email, new FakeSmsSender());

  await dispatchOnce(deps);

  const text = JSON.stringify(logs);
  for (const personal of ["asha@example.com", "98765", emailRow().subject!, emailRow().body!, smsRow().body!]) {
    assertEquals(text.includes(personal), false, personal);
  }
});
```

- [ ] **Step 3: Write the failing handler and wiring tests**

Create `supabase/functions/outbox-dispatch/handler_test.ts`:

```ts
import { assertEquals } from "@std/assert";
import { ConfigError } from "./config.ts";
import type { DispatchDeps } from "./dispatch.ts";
import { dryConfig, emailRow, FakeStore } from "./fakes.ts";
import { bearerMatches, handleRequest, timingSafeEqual } from "./handler.ts";

function depsWith(store: FakeStore): () => DispatchDeps {
  return () => ({ config: dryConfig, store, email: null, sms: null, log: () => {} });
}

function post(authorization?: string): Request {
  const headers: Record<string, string> = {};
  if (authorization !== undefined) headers["Authorization"] = authorization;
  return new Request("http://localhost/functions/v1/outbox-dispatch", { method: "POST", headers });
}

Deno.test("only POST is accepted", async () => {
  const store = new FakeStore();
  const res = await handleRequest(
    new Request("http://localhost/functions/v1/outbox-dispatch", { method: "GET" }),
    depsWith(store),
  );
  assertEquals(res.status, 405);
  assertEquals(await res.json(), { error: "method_not_allowed" });
  assertEquals(store.claimLimits.length, 0);
});

Deno.test("a missing or wrong bearer is refused before anything is claimed", async () => {
  for (const auth of [undefined, "Bearer nope", "service-key", "Basic service-key", "Bearer service-key-x"]) {
    const store = new FakeStore();
    const res = await handleRequest(post(auth), depsWith(store));
    assertEquals(res.status, 401, String(auth));
    assertEquals(await res.json(), { error: "unauthorized" });
    assertEquals(store.claimLimits.length, 0, String(auth));
  }
});

Deno.test("the service key runs one dispatch and returns the summary", async () => {
  const store = new FakeStore();
  store.rows = [emailRow()];
  const res = await handleRequest(post("Bearer service-key"), depsWith(store));

  assertEquals(res.status, 200);
  assertEquals(await res.json(), {
    claimed: 1, sent: 0, dry_run: 1, retry: 0, failed: 0, errors: 0,
    modes: { email: "dry_run", sms: "dry_run" },
  });
});

Deno.test("missing configuration is a 500 naming the missing variable", async () => {
  const res = await handleRequest(post("Bearer service-key"), () => {
    throw new ConfigError("SUPABASE_URL is not set");
  });
  assertEquals(res.status, 500);
  assertEquals(await res.json(), { error: "not_configured", detail: "SUPABASE_URL is not set" });
});

Deno.test("a store failure is a 502", async () => {
  const store = new FakeStore();
  store.claimError = new Error("connection refused");
  const res = await handleRequest(post("Bearer service-key"), depsWith(store));
  assertEquals(res.status, 502);
  assertEquals(await res.json(), { error: "store_unavailable" });
});

Deno.test("bearerMatches is exact, with a case-insensitive scheme", () => {
  assertEquals(bearerMatches("Bearer service-key", "service-key"), true);
  assertEquals(bearerMatches("bearer service-key", "service-key"), true);
  assertEquals(bearerMatches("  Bearer   service-key  ", "service-key"), true);
  assertEquals(bearerMatches("Bearer service-ke", "service-key"), false);
  assertEquals(bearerMatches(null, "service-key"), false);
  assertEquals(bearerMatches("Bearer ", "service-key"), false);
});

Deno.test("timingSafeEqual compares whole strings", () => {
  assertEquals(timingSafeEqual("abc", "abc"), true);
  assertEquals(timingSafeEqual("abc", "abd"), false);
  assertEquals(timingSafeEqual("abc", "abcd"), false);
  assertEquals(timingSafeEqual("", ""), true);
});
```

Create `supabase/functions/outbox-dispatch/deps_test.ts`:

```ts
import { assertEquals, assertInstanceOf } from "@std/assert";
import { buildDeps } from "./deps.ts";
import { handleRequest } from "./handler.ts";
import { Msg91SmsSender } from "./msg91.ts";
import { RESEND_URL, ResendEmailSender } from "./resend.ts";
import { RestOutboxStore } from "./store.ts";
import { jsonResponse, stubFetch } from "./testing.ts";

function envOf(values: Record<string, string>): (name: string) => string | undefined {
  return (name) => values[name];
}

const base = { SUPABASE_URL: "http://127.0.0.1:54321", SUPABASE_SERVICE_ROLE_KEY: "service-key" };

Deno.test("without provider keys there are no senders", () => {
  const deps = buildDeps(envOf(base), stubFetch([]).fetch, () => {});
  assertEquals(deps.email, null);
  assertEquals(deps.sms, null);
  assertInstanceOf(deps.store, RestOutboxStore);
});

Deno.test("with keys both senders are wired to the given fetch", async () => {
  const { fetch, calls } = stubFetch([jsonResponse(200, { id: "re_1" })]);
  const deps = buildDeps(envOf({
    ...base,
    RESEND_API_KEY: "re_k",
    RESEND_FROM: "bookings@mail.example.com",
    MSG91_AUTH_KEY: "auth",
    MSG91_TEMPLATES: "{}",
  }), fetch, () => {});

  assertInstanceOf(deps.email, ResendEmailSender);
  assertInstanceOf(deps.sms, Msg91SmsSender);
  await deps.email!.send({ to: "a@example.com", fromName: "R", subject: "s", text: "t", idempotencyKey: "k" });
  assertEquals(calls[0].url, RESEND_URL);
});

Deno.test("a dry run end to end through the real store: claim, complete, record", async () => {
  const row = {
    id: "m1", property_id: "p1", reservation_id: "r1", channel: "email",
    recipient: "asha@example.com", template: "booking_confirmation",
    subject: "s", body: "b", attempts: 1, vars: { property_name: "P" },
  };
  const { fetch, calls } = stubFetch([
    jsonResponse(200, [row]),
    jsonResponse(200, "dry_run"),
    new Response(null, { status: 204 }),
  ]);
  const deps = buildDeps(envOf(base), fetch, () => {});

  const res = await handleRequest(
    new Request("http://localhost/functions/v1/outbox-dispatch", {
      method: "POST",
      headers: { Authorization: "Bearer service-key" },
    }),
    () => deps,
  );

  assertEquals(res.status, 200);
  assertEquals(calls.map((c) => c.url.split("/rpc/")[1]), [
    "claim_outbox_batch",
    "complete_outbox_message",
    "record_outbox_dispatch_run",
  ]);
  assertEquals(calls[1].body, {
    p_id: "m1", p_outcome: "dry_run", p_error: "Dry run: RESEND_API_KEY is not set", p_provider_id: null,
  });
});
```

- [ ] **Step 4: Run them to verify they fail**

Run: `(cd supabase/functions/outbox-dispatch && deno test dispatch_test.ts handler_test.ts deps_test.ts)`
Expected: FAIL (`Module not found` for `dispatch.ts`, `handler.ts` and `deps.ts`).

- [ ] **Step 5: Implement dispatch, handler, wiring and entry point**

Create `supabase/functions/outbox-dispatch/dispatch.ts`:

```ts
// One dispatcher run: claim a batch, send each row (or record a dry run),
// report each result, then record the run. State changes (backoff, the
// attempt limit, statuses) are decided in SQL by complete_outbox_message.
import { normalizeIndianMobile } from "./msg91.ts";
import type {
  ChannelMode,
  ClaimedMessage,
  DispatchConfig,
  DispatchSummary,
  EmailSender,
  Outcome,
  OutboxStore,
  SendResult,
  SmsSender,
} from "./types.ts";
import { clip, errorText } from "./util.ts";

export interface DispatchDeps {
  config: DispatchConfig;
  store: OutboxStore;
  /** Null when email is a dry run. */
  email: EmailSender | null;
  /** Null when SMS is a dry run. */
  sms: SmsSender | null;
  /** One structured line per event. Never given a recipient, subject or body. */
  log: (entry: Record<string, unknown>) => void;
}

export function channelModes(config: DispatchConfig): ChannelMode[] {
  return [
    {
      channel: "email",
      mode: config.email.mode,
      provider: config.email.provider,
      detail: config.email.mode === "dry_run" ? config.email.detail : null,
    },
    {
      channel: "sms",
      mode: config.sms.mode,
      provider: config.sms.provider,
      detail: config.sms.mode === "dry_run" ? config.sms.detail : null,
    },
  ];
}

function fromSendResult(result: SendResult): Outcome {
  if (result.ok) return { kind: "sent", providerId: result.providerId };
  return result.retryable ? { kind: "retry", error: result.error } : { kind: "failed", error: result.error };
}

export async function deliver(row: ClaimedMessage, deps: DispatchDeps): Promise<Outcome> {
  if (row.channel === "email") {
    const setup = deps.config.email;
    if (setup.mode === "dry_run" || deps.email === null) {
      return { kind: "dry_run", reason: `Dry run: ${setup.mode === "dry_run" ? setup.detail : "no email sender"}` };
    }
    if (!row.subject || !row.body) {
      return { kind: "failed", error: "nothing to send: the message has no subject or body" };
    }
    return fromSendResult(
      await deps.email.send({
        to: row.recipient,
        fromName: row.vars?.property_name ?? "",
        subject: row.subject,
        text: row.body,
        idempotencyKey: row.id,
      }),
    );
  }

  if (row.channel === "sms") {
    const setup = deps.config.sms;
    if (setup.mode === "dry_run" || deps.sms === null) {
      return { kind: "dry_run", reason: `Dry run: ${setup.mode === "dry_run" ? setup.detail : "no SMS sender"}` };
    }
    const templateId = setup.config.templates[row.template];
    if (!templateId) {
      return { kind: "failed", error: `no MSG91 template id for ${row.template} in MSG91_TEMPLATES` };
    }
    const mobile = normalizeIndianMobile(row.recipient);
    if (mobile === null) {
      return { kind: "failed", error: "the phone number on file is not a valid Indian mobile number" };
    }
    return fromSendResult(await deps.sms.send({ mobile, templateId, vars: row.vars ?? {} }));
  }

  // claim_outbox_batch never returns WhatsApp rows; this is a backstop.
  return { kind: "failed", error: `no sender for the ${row.channel} channel` };
}

export async function dispatchOnce(deps: DispatchDeps): Promise<DispatchSummary> {
  const summary: DispatchSummary = {
    claimed: 0,
    sent: 0,
    dry_run: 0,
    retry: 0,
    failed: 0,
    errors: 0,
    modes: { email: deps.config.email.mode, sms: deps.config.sms.mode },
  };

  const rows = await deps.store.claim(deps.config.batchSize);
  summary.claimed = rows.length;

  for (const row of rows) {
    let outcome: Outcome;
    try {
      outcome = await deliver(row, deps);
    } catch (e) {
      outcome = { kind: "retry", error: clip(`unexpected error: ${errorText(e)}`) };
    }
    try {
      await deps.store.complete(row.id, outcome);
      summary[outcome.kind] += 1;
      deps.log({ event: "outbox_message", id: row.id, channel: row.channel, template: row.template, outcome: outcome.kind });
    } catch (e) {
      // The row's lease runs out and a later run claims it again.
      summary.errors += 1;
      deps.log({ event: "outbox_complete_failed", id: row.id, outcome: outcome.kind, error: errorText(e) });
    }
  }

  try {
    await deps.store.recordRun(channelModes(deps.config));
  } catch (e) {
    summary.errors += 1;
    deps.log({ event: "outbox_record_run_failed", error: errorText(e) });
  }

  deps.log({ event: "outbox_dispatch_run", ...summary });
  return summary;
}
```

Create `supabase/functions/outbox-dispatch/handler.ts`:

```ts
// HTTP entry: POST only, and only with the service role key (pg_cron's
// outbox_dispatch_tick sends it from Vault; a person running it by hand
// passes it too).
import { ConfigError } from "./config.ts";
import { type DispatchDeps, dispatchOnce } from "./dispatch.ts";
import { errorText } from "./util.ts";

/** Compares every byte, so the time taken does not reveal how much matched. */
export function timingSafeEqual(a: string, b: string): boolean {
  const left = new TextEncoder().encode(a);
  const right = new TextEncoder().encode(b);
  let diff = left.length ^ right.length;
  const length = Math.max(left.length, right.length);
  for (let i = 0; i < length; i++) {
    diff |= (left[i] ?? 0) ^ (right[i] ?? 0);
  }
  return diff === 0;
}

export function bearerMatches(header: string | null, key: string): boolean {
  if (header === null) return false;
  const match = /^Bearer\s+(\S+)$/i.exec(header.trim());
  return match !== null && timingSafeEqual(match[1], key);
}

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

export async function handleRequest(req: Request, makeDeps: () => DispatchDeps): Promise<Response> {
  if (req.method !== "POST") return json(405, { error: "method_not_allowed" });

  let deps: DispatchDeps;
  try {
    deps = makeDeps();
  } catch (e) {
    const detail = e instanceof ConfigError ? e.message : "configuration error";
    return json(500, { error: "not_configured", detail });
  }

  if (!bearerMatches(req.headers.get("Authorization"), deps.config.serviceKey)) {
    return json(401, { error: "unauthorized" });
  }

  try {
    return json(200, await dispatchOnce(deps));
  } catch (e) {
    deps.log({ event: "outbox_dispatch_failed", error: errorText(e) });
    return json(502, { error: "store_unavailable" });
  }
}
```

Create `supabase/functions/outbox-dispatch/deps.ts`:

```ts
// Wires the real store and senders from the environment. A channel whose
// keys are missing gets no sender and is a dry run.
import { loadConfig } from "./config.ts";
import type { DispatchDeps } from "./dispatch.ts";
import { Msg91SmsSender } from "./msg91.ts";
import { ResendEmailSender } from "./resend.ts";
import { RestOutboxStore } from "./store.ts";
import type { FetchFn } from "./types.ts";

export function buildDeps(
  env: (name: string) => string | undefined,
  fetchFn: FetchFn = fetch,
  log: (entry: Record<string, unknown>) => void = (entry) => console.log(JSON.stringify(entry)),
): DispatchDeps {
  const config = loadConfig(env);
  return {
    config,
    store: new RestOutboxStore(config.supabaseUrl, config.serviceKey, fetchFn),
    email: config.email.mode === "live"
      ? new ResendEmailSender(config.email.config.apiKey, config.email.config.from, fetchFn)
      : null,
    sms: config.sms.mode === "live"
      ? new Msg91SmsSender(config.sms.config.authKey, config.sms.config.senderId, fetchFn)
      : null,
    log,
  };
}
```

Create `supabase/functions/outbox-dispatch/index.ts`:

```ts
// outbox-dispatch: sends due outbox email/SMS rows. pg_cron calls it every
// minute (0056's outbox_dispatch_tick), and it can be run by hand; see
// docs/email-and-sms-delivery.md. The configuration is read on every
// request, so new secrets take effect without a redeploy.
import { buildDeps } from "./deps.ts";
import { handleRequest } from "./handler.ts";

Deno.serve((req) => handleRequest(req, () => buildDeps((name) => Deno.env.get(name))));
```

- [ ] **Step 6: Run the whole function test suite, lint and type-check**

```bash
(cd supabase/functions/outbox-dispatch && deno test && deno check index.ts && deno lint)
```
Expected: every test PASS (util, resend, msg91, config, store, dispatch, handler, deps); no type errors; no lint errors.

- [ ] **Step 7: Write the operator docs**

Create `docs/email-and-sms-delivery.md`:

````markdown
# Email and SMS delivery

Booking confirmations, payment receipts and cancellation notices are
queued in `public.outbox` when they happen. The `outbox-dispatch` Edge
Function (`supabase/functions/outbox-dispatch/`) sends them: email
through [Resend](https://resend.com), SMS through [MSG91](https://msg91.com).
WhatsApp messages are queued but not sent; there is no WhatsApp provider
yet.

## How it runs

- pg_cron runs `public.outbox_dispatch_tick()` every minute (job
  `outbox-dispatch`). It reads two Vault secrets, the function URL and the
  service role key, and POSTs to the function. Without the secrets it does
  nothing and answers `not_configured`.
- The function claims up to `OUTBOX_BATCH_SIZE` (default 50) due email and
  SMS rows and sends each one. Each row then ends up in one of these
  states:
  - **sent**: the provider accepted it.
  - **pending again**: a temporary failure (network, 408, 429, 5xx). The
    row retries after 1, 2, 4 and 8 minutes.
  - **failed**: the fifth failed attempt, or a permanent error such as a
    rejected address, a missing MSG91 template, or a phone number that is
    not an Indian mobile.
  - **dry_run**: the channel's provider key is not set, so nothing was
    sent.
- A queued message whose channel an owner has since turned off (Owner →
  Settings → Notification settings) is marked **skipped** and not sent.
- `/admin/outbox` shows, for each channel, whether it is sending, in dry
  run or not connected, and when the sender last ran. If the sender has
  not run for 10 minutes, or has never run, the screen says so. Owners and
  admins can press **Send again** on a failed or dry-run message.

## Dry run (the default)

Until a channel's keys are set, its messages are marked `dry_run` with the
reason (for example `Dry run: RESEND_API_KEY is not set`) and nothing is
sent. Email can be live while SMS is still a dry run. Dry-run messages are
**not** sent automatically once keys arrive; use **Send again** for any
that still matter.

## 1. Email: Resend

1. Create a Resend account and verify your sending domain (add the DNS
   records Resend shows).
2. Create an API key with sending access.
3. Set the secrets:

   ```bash
   supabase secrets set RESEND_API_KEY=re_xxx RESEND_FROM=bookings@mail.yourdomain.in
   ```

   `RESEND_FROM` is a bare address on the verified domain. Each email goes
   out as `"<resort name> <RESEND_FROM>"`, in plain text.

## 2. SMS: MSG91

Indian SMS needs DLT registration: the sender id (header) and every
template text must be registered on a DLT portal before MSG91 will
deliver them.

1. Register a sender id (for example `RSTHUB`) and one template for each
   SMS the app sends: `booking_confirmation_sms` and `cancellation_sms`.
2. Add the templates in MSG91 and note each template id. The variables
   must use exactly these names, and each value is cut to 30 characters:
   `guest_name`, `unit_name`, `property_name`, `check_in`, `check_out`,
   `total`, `currency`, `cancel_reason`. Example:
   `Hi ##guest_name##, your stay at ##unit_name## (##check_in## - ##check_out##) is confirmed. - ##property_name##`
3. Set the secrets:

   ```bash
   supabase secrets set MSG91_AUTH_KEY=xxx MSG91_SENDER_ID=RSTHUB \
     MSG91_TEMPLATES='{"booking_confirmation_sms":"<template id>","cancellation_sms":"<template id>"}'
   ```

   A message whose template has no id in `MSG91_TEMPLATES` fails with "no
   MSG91 template id for …". Guests' phone numbers may be written any
   common way (`+91 98765 43210`, `098765 43210`). A number that is not an
   Indian mobile fails with a clear reason.

## 3. Deploy the function

```bash
supabase functions deploy outbox-dispatch
```

`SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are provided to the
function by Supabase. The function accepts only `POST` with
`Authorization: Bearer <service role key>`. The configuration is read on
every call, so `supabase secrets set` takes effect without a redeploy.

## 4. Point the cron job at it (once per project)

In the SQL editor:

```sql
select vault.create_secret('https://<project-ref>.supabase.co/functions/v1/outbox-dispatch', 'outbox_dispatch_url');
select vault.create_secret('<service role key>', 'outbox_dispatch_key');
```

To change one later:
`select vault.update_secret((select id from vault.secrets where name = 'outbox_dispatch_key'), '<new key>');`

To check it: `select public.outbox_dispatch_tick();` answers `requested`,
and `select status_code, content from net._http_response order by created desc limit 5;`
shows the function's replies (`200` with a JSON summary).

## Running locally

1. `supabase start` and `supabase db reset`. The seed's booking queues a
   few messages.
2. Optional provider keys go in `supabase/functions/.env`. The root
   `.gitignore` rule `.env` keeps this file out of git; check with
   `git check-ignore supabase/functions/.env`. Leave the file out to stay
   in dry run.
3. Serve the functions: `supabase functions serve --env-file supabase/functions/.env`
   (drop `--env-file …` for a dry run).
4. Run the function by hand:

   ```bash
   SERVICE_KEY=$(supabase status -o env | grep '^SERVICE_ROLE_KEY=' | cut -d= -f2 | tr -d '"')
   curl -s -X POST http://127.0.0.1:54321/functions/v1/outbox-dispatch \
     -H "Authorization: Bearer $SERVICE_KEY"
   ```

   The reply looks like
   `{"claimed":3,"sent":0,"dry_run":3,"retry":0,"failed":0,"errors":0,"modes":{"email":"dry_run","sms":"dry_run"}}`.
5. Optional, to let local pg_cron call it every minute: create the two
   Vault secrets as in step 4 above, with the URL
   `http://host.docker.internal:54321/functions/v1/outbox-dispatch` (Docker
   Desktop) and the local service role key. `supabase db reset` removes
   them again.

## Tests

```bash
(cd supabase/functions/outbox-dispatch && deno test)   # no network; providers are stubbed
supabase test db supabase/tests/46_email_sms_delivery_test.sql
```
````

- [ ] **Step 8: Update the README and STATUS**

In `README.md`, replace the second and third bullets under **Notification outbox (phase 2)**. These are the bullets from "- `/admin/outbox` (staff-or-above) shows the queue honestly, including a" through "`42501` before RLS is even evaluated — proven in `13_outbox_test.sql`.". The replacement:

```markdown
- The `outbox-dispatch` Edge Function sends email (Resend) and SMS
  (MSG91), called every minute by pg_cron, with retries (1, 2, 4, 8
  minutes; failed after 5 attempts). Without provider keys it runs as a
  **dry run**: messages are marked `dry_run` and nothing is sent. WhatsApp
  is queued only. Setup: [docs/email-and-sms-delivery.md](docs/email-and-sms-delivery.md).
- `/admin/outbox` (staff-or-above) shows each channel's delivery mode and
  when the sender last ran, and lets owners/admins send a failed or
  dry-run message again.
- Clients still cannot write `outbox`: there is no INSERT/UPDATE/DELETE
  grant to `authenticated` or `anon` (proven in `13_outbox_test.sql`).
  Only `security definer` functions change rows, and only the service
  role (the Edge Function) marks one sent (`46_email_sms_delivery_test.sql`).
```

In **What is still out of scope**, replace the bullet that starts "- **SMS/WhatsApp/email actually being delivered.**" (three lines) with:

```markdown
- **WhatsApp delivery.** Email and SMS are sent once their provider keys
  are set (see [docs/email-and-sms-delivery.md](docs/email-and-sms-delivery.md));
  WhatsApp needs Meta Business API verification, which has a multi-week
  lead time, and is queued only.
```

In **Known limitations → From phase 2**, replace the bullet that starts "- **Nothing in the notification outbox has ever been sent.**" (four lines) with:

```markdown
- **Email and SMS go out only once provider keys are set.** Until then the
  sender runs as a dry run and the Outbox screen says so per channel.
  WhatsApp is never sent. See `docs/email-and-sms-delivery.md`.
```

In `docs/STATUS.md`, replace the bullet that starts "- **The notification outbox is queued, never sent.**" (through "configured away.") with:

```markdown
- **Email and SMS are sent by the `outbox-dispatch` Edge Function** once
  a Resend key (email) and an MSG91 key and DLT templates (SMS) are set.
  Until then every message is recorded as a dry run and nothing is sent.
  The admin Outbox screen shows each channel's mode and when the sender
  last ran. WhatsApp messages are queued only. Setup:
  `docs/email-and-sms-delivery.md`.
```

and replace item 3 ("**An email and/or SMS provider account …**" through "…unless someone manually tells them.") with:

```markdown
3. **A Resend account with a verified sending domain (email) and an MSG91
   account with DLT-registered templates (SMS).** Consequence while
   missing: **the sender runs as a dry run, so no guest receives a
   booking confirmation, payment receipt or cancellation notice.** The
   Outbox screen says so for each channel. Setup takes minutes once the
   accounts exist; see `docs/email-and-sms-delivery.md`.
```

- [ ] **Step 9: Check the docs mention no secret values, then commit**

```bash
git diff --cached --name-only; git status --short
grep -nE "re_[A-Za-z0-9]{8,}|eyJ[A-Za-z0-9_-]{20,}" docs/email-and-sms-delivery.md README.md docs/STATUS.md || echo "no key-like strings"
```
Expected: `no key-like strings`.

```bash
git add supabase/functions/outbox-dispatch/dispatch.ts supabase/functions/outbox-dispatch/handler.ts \
  supabase/functions/outbox-dispatch/deps.ts supabase/functions/outbox-dispatch/index.ts \
  supabase/functions/outbox-dispatch/fakes.ts supabase/functions/outbox-dispatch/dispatch_test.ts \
  supabase/functions/outbox-dispatch/handler_test.ts supabase/functions/outbox-dispatch/deps_test.ts \
  docs/email-and-sms-delivery.md README.md docs/STATUS.md
git commit -m "feat(outbox-dispatch): dispatch loop, service-key handler, wiring and setup docs" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Phase 3: App track (Flutter; no database)

### Task 8: Delivery status panel

**Track:** App. Depends on Task 1.

**Files:**
- Create: `lib/features/outbox/delivery_status_panel.dart`
- Test: `test/features/outbox/delivery_status_panel_test.dart`

**Interfaces:**
- Consumes: `ChannelDelivery`, `DeliveryMode` (`lib/data/models/channel_delivery.dart`); `OutboxChannel` (`lib/data/models/outbox_message.dart`); `Spacing` (`lib/core/theme/tokens.dart`); Riverpod's `AsyncValue`.
- Produces (all public, in `delivery_status_panel.dart`):
  - `const staleAfter = Duration(minutes: 10)`
  - `String channelLabel(OutboxChannel)` → `Email` / `SMS` / `WhatsApp`
  - `String providerLabel(String?)` → `Resend` / `MSG91` / the raw name / `the provider`
  - `String deliveryLine(ChannelDelivery)`
  - `DateTime? lastRunOf(List<ChannelDelivery>)`
  - `String sinceLabel(DateTime from, DateTime now)`
  - `bool senderLooksStopped(DateTime? lastRun, DateTime now)`
  - `String runLine(DateTime? lastRun, DateTime now)`
  - `class DeliveryStatusPanel extends StatelessWidget { const DeliveryStatusPanel({Key? key, required AsyncValue<List<ChannelDelivery>> status, required DateTime now}) }`. Its keys are `delivery-status-panel` (the container) and `delivery-run-line` (the run line).

- [ ] **Step 1: Write the failing tests**

Create `test/features/outbox/delivery_status_panel_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/data/models/channel_delivery.dart';
import 'package:pasala/data/models/outbox_message.dart';
import 'package:pasala/features/outbox/delivery_status_panel.dart';

final _now = DateTime.utc(2026, 9, 25, 5, 0);

Future<void> _pump(
  WidgetTester tester,
  AsyncValue<List<ChannelDelivery>> status,
) =>
    tester.pumpWidget(MaterialApp(
      home: Scaffold(body: DeliveryStatusPanel(status: status, now: _now)),
    ));

List<ChannelDelivery> _rows({required Duration ago}) => [
      ChannelDelivery(
        channel: OutboxChannel.email,
        mode: DeliveryMode.live,
        provider: 'resend',
        lastRunAt: _now.subtract(ago),
      ),
      ChannelDelivery(
        channel: OutboxChannel.sms,
        mode: DeliveryMode.dryRun,
        provider: 'msg91',
        detail: 'MSG91_AUTH_KEY is not set',
        lastRunAt: _now.subtract(ago),
      ),
      const ChannelDelivery(
        channel: OutboxChannel.whatsapp,
        mode: DeliveryMode.unavailable,
      ),
    ];

void main() {
  group('deliveryLine', () {
    test('live names the provider', () {
      expect(
        deliveryLine(const ChannelDelivery(
            channel: OutboxChannel.email, mode: DeliveryMode.live, provider: 'resend')),
        'Email: sending via Resend',
      );
      expect(
        deliveryLine(const ChannelDelivery(
            channel: OutboxChannel.sms, mode: DeliveryMode.live, provider: 'msg91')),
        'SMS: sending via MSG91',
      );
    });

    test('dry run, unavailable and not running', () {
      expect(
        deliveryLine(const ChannelDelivery(
            channel: OutboxChannel.sms, mode: DeliveryMode.dryRun)),
        'SMS: dry run, nothing is sent',
      );
      expect(
        deliveryLine(const ChannelDelivery(
            channel: OutboxChannel.whatsapp, mode: DeliveryMode.unavailable)),
        'WhatsApp: not connected, messages stay queued',
      );
      expect(
        deliveryLine(const ChannelDelivery(
            channel: OutboxChannel.email, mode: DeliveryMode.notRunning)),
        'Email: waiting for the sender to run',
      );
    });

    test('an unknown or missing provider still reads well', () {
      expect(providerLabel('twilio'), 'twilio');
      expect(providerLabel(''), 'the provider');
      expect(providerLabel(null), 'the provider');
    });
  });

  test('sinceLabel buckets minutes, hours and days', () {
    expect(sinceLabel(_now.subtract(const Duration(seconds: 30)), _now), 'just now');
    expect(sinceLabel(_now.subtract(const Duration(minutes: 3)), _now), '3 min ago');
    expect(sinceLabel(_now.subtract(const Duration(minutes: 59)), _now), '59 min ago');
    expect(sinceLabel(_now.subtract(const Duration(hours: 2)), _now), '2 h ago');
    expect(sinceLabel(_now.subtract(const Duration(days: 1)), _now), '1 day ago');
    expect(sinceLabel(_now.subtract(const Duration(days: 3)), _now), '3 days ago');
  });

  test('runLine: never ran, fresh, the 10-minute edge, and stale', () {
    expect(runLine(null, _now),
        'The sender has not run yet. Pending messages wait until it does.');
    expect(runLine(_now.subtract(const Duration(minutes: 3)), _now),
        'Last checked 3 min ago.');
    expect(runLine(_now.subtract(const Duration(minutes: 10)), _now),
        'Last checked 10 min ago.');
    expect(runLine(_now.subtract(const Duration(minutes: 11)), _now),
        'The sender last ran 11 min ago. Pending messages are waiting.');
    expect(runLine(_now.subtract(const Duration(hours: 2)), _now),
        'The sender last ran 2 h ago. Pending messages are waiting.');
    expect(senderLooksStopped(null, _now), isTrue);
    expect(senderLooksStopped(_now.subtract(const Duration(minutes: 10)), _now), isFalse);
  });

  test('lastRunOf picks the latest run and ignores channels that never ran', () {
    final older = _now.subtract(const Duration(minutes: 9));
    final newer = _now.subtract(const Duration(minutes: 2));
    expect(
      lastRunOf([
        ChannelDelivery(channel: OutboxChannel.email, mode: DeliveryMode.live, lastRunAt: older),
        ChannelDelivery(channel: OutboxChannel.sms, mode: DeliveryMode.live, lastRunAt: newer),
        const ChannelDelivery(channel: OutboxChannel.whatsapp, mode: DeliveryMode.unavailable),
      ]),
      newer,
    );
    expect(lastRunOf(const []), isNull);
  });

  testWidgets('renders a line per channel, and the dry-run reason under SMS only',
      (tester) async {
    await _pump(tester, AsyncData(_rows(ago: const Duration(minutes: 3))));

    expect(find.byKey(const Key('delivery-status-panel')), findsOneWidget);
    expect(find.text('Email: sending via Resend'), findsOneWidget);
    expect(find.text('SMS: dry run, nothing is sent'), findsOneWidget);
    expect(find.text('MSG91_AUTH_KEY is not set'), findsOneWidget);
    expect(find.text('WhatsApp: not connected, messages stay queued'), findsOneWidget);
    expect(find.text('Last checked 3 min ago.'), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_outlined), findsNothing);
  });

  testWidgets('a stale sender shows the warning line and icon', (tester) async {
    await _pump(tester, AsyncData(_rows(ago: const Duration(hours: 2))));

    expect(find.text('The sender last ran 2 h ago. Pending messages are waiting.'),
        findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('delivery-run-line')),
        matching: find.byIcon(Icons.warning_amber_outlined),
      ),
      findsOneWidget,
    );
  });

  testWidgets('a sender that never ran warns too', (tester) async {
    await _pump(tester, const AsyncData(<ChannelDelivery>[]));

    expect(find.text('The sender has not run yet. Pending messages wait until it does.'),
        findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_outlined), findsOneWidget);
  });

  testWidgets('loading shows a thin progress bar', (tester) async {
    await _pump(tester, const AsyncLoading<List<ChannelDelivery>>());
    await tester.pump();

    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('an error says the status is unavailable', (tester) async {
    await _pump(
      tester,
      AsyncError<List<ChannelDelivery>>(Exception('boom'), StackTrace.empty),
    );

    expect(find.text('Delivery status is unavailable right now.'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/features/outbox/delivery_status_panel_test.dart`
Expected: FAIL to compile (`delivery_status_panel.dart` does not exist).

- [ ] **Step 3: Implement the panel**

Create `lib/features/outbox/delivery_status_panel.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../../data/models/channel_delivery.dart';
import '../../data/models/outbox_message.dart';

/// After this long without a run, the panel warns that the sender stopped
/// (pg_cron calls it every minute).
const staleAfter = Duration(minutes: 10);

String channelLabel(OutboxChannel channel) => switch (channel) {
      OutboxChannel.email => 'Email',
      OutboxChannel.sms => 'SMS',
      OutboxChannel.whatsapp => 'WhatsApp',
    };

String providerLabel(String? provider) => switch (provider) {
      'resend' => 'Resend',
      'msg91' => 'MSG91',
      final String p when p.isNotEmpty => p,
      _ => 'the provider',
    };

String deliveryLine(ChannelDelivery d) {
  final channel = channelLabel(d.channel);
  return switch (d.mode) {
    DeliveryMode.live => '$channel: sending via ${providerLabel(d.provider)}',
    DeliveryMode.dryRun => '$channel: dry run, nothing is sent',
    DeliveryMode.unavailable => '$channel: not connected, messages stay queued',
    DeliveryMode.notRunning => '$channel: waiting for the sender to run',
  };
}

DateTime? lastRunOf(List<ChannelDelivery> rows) {
  DateTime? latest;
  for (final row in rows) {
    final at = row.lastRunAt;
    if (at != null && (latest == null || at.isAfter(latest))) latest = at;
  }
  return latest;
}

String sinceLabel(DateTime from, DateTime now) {
  final diff = now.difference(from);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inHours < 1) return '${diff.inMinutes} min ago';
  if (diff.inDays < 1) return '${diff.inHours} h ago';
  return '${diff.inDays} day${diff.inDays == 1 ? '' : 's'} ago';
}

bool senderLooksStopped(DateTime? lastRun, DateTime now) =>
    lastRun == null || now.difference(lastRun) > staleAfter;

String runLine(DateTime? lastRun, DateTime now) {
  if (lastRun == null) {
    return 'The sender has not run yet. Pending messages wait until it does.';
  }
  final since = sinceLabel(lastRun, now);
  if (senderLooksStopped(lastRun, now)) {
    return 'The sender last ran $since. Pending messages are waiting.';
  }
  return 'Last checked $since.';
}

IconData _modeIcon(DeliveryMode mode) => switch (mode) {
      DeliveryMode.live => Icons.check_circle_outline,
      DeliveryMode.dryRun => Icons.science_outlined,
      DeliveryMode.unavailable => Icons.block,
      DeliveryMode.notRunning => Icons.hourglass_empty,
    };

/// The top of the Outbox screen: how each channel is being delivered
/// (`outbox_delivery_status`) and when the sender last ran. Replaces the
/// old permanent "no provider" banner. States are shown with an icon and
/// words, never by colour alone.
class DeliveryStatusPanel extends StatelessWidget {
  const DeliveryStatusPanel({super.key, required this.status, required this.now});

  final AsyncValue<List<ChannelDelivery>> status;

  /// Injected so "3 min ago" is testable.
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      key: const Key('delivery-status-panel'),
      width: double.infinity,
      color: scheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.md,
        vertical: Spacing.sm,
      ),
      child: status.when(
        loading: () => const LinearProgressIndicator(minHeight: 2),
        error: (_, _) => _PanelLine(
          icon: Icons.cloud_off_outlined,
          text: 'Delivery status is unavailable right now.',
          color: scheme.onSurfaceVariant,
        ),
        data: (rows) {
          final lastRun = lastRunOf(rows);
          final stopped = senderLooksStopped(lastRun, now);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final row in rows) ...[
                _PanelLine(
                  icon: _modeIcon(row.mode),
                  text: deliveryLine(row),
                  color: scheme.onSurface,
                ),
                if (row.mode == DeliveryMode.dryRun && row.detail != null)
                  Padding(
                    padding: const EdgeInsets.only(left: Spacing.xl),
                    child: Text(
                      row.detail!,
                      style: textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
              ],
              _PanelLine(
                key: const Key('delivery-run-line'),
                icon: stopped ? Icons.warning_amber_outlined : Icons.schedule,
                text: runLine(lastRun, now),
                color: stopped ? scheme.error : scheme.onSurfaceVariant,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PanelLine extends StatelessWidget {
  const _PanelLine({
    super.key,
    required this.icon,
    required this.text,
    required this.color,
  });

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: Spacing.xs / 2),
        child: Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: Spacing.sm),
            Expanded(
              child: Text(
                text,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: color),
              ),
            ),
          ],
        ),
      );
}
```

- [ ] **Step 4: Run the tests and analyze**

```bash
flutter test test/features/outbox/delivery_status_panel_test.dart
flutter analyze lib/features/outbox/delivery_status_panel.dart test/features/outbox/delivery_status_panel_test.dart
```
Expected: all PASS; `No issues found!`.

- [ ] **Step 5: Commit**

```bash
git add lib/features/outbox/delivery_status_panel.dart test/features/outbox/delivery_status_panel_test.dart
git commit -m "feat(outbox): delivery status panel with per-channel mode and a stale-sender warning" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: Outbox screen, Send again, and copy that no longer says "nothing sends"

**Track:** App. Depends on Task 8.

**Files:**
- Modify: `lib/features/outbox/outbox_screen.dart` (whole file)
- Modify: `test/features/outbox/outbox_screen_test.dart` (whole file)
- Modify: `lib/features/owner/notification_settings_screen.dart:11-17` (class doc) and `:57-63` (card text)
- Modify: `lib/data/models/notification_settings.dart:1-4` (class doc)
- Modify: `lib/features/admin/admin_more_screen.dart:37` (Outbox subtitle)
- Test: `test/features/owner/notification_settings_screen_test.dart`

**Interfaces:**
- Consumes:
  - `outboxMessagesProvider`, `outboxDeliveryStatusProvider` (`providers.dart`)
  - `outboxSourceProvider`, `OutboxSource.retry` (Task 1)
  - `DeliveryStatusPanel`, `channelLabel` (Task 8)
  - `OutboxMessage`, `OutboxStatus`, `outboxMaxAttempts` (Task 1)
  - `currentResortProvider`, `ResortRole`, `BookingFailure`, `NotRetryable`, `FailureView.messageFor`
  - `FakeOutboxSource` (`test/support/fake_outbox_source.dart`)
- Produces:
  - `OutboxScreen({Key? key, DateTime Function()? clock})` (null means `DateTime.now`)
  - public helpers `String outboxStatusLabel(OutboxStatus)`, `const outboxStatusOrder`, `String? attemptLine(OutboxMessage)`, `bool canSendAgain(OutboxMessage)`
  - widget keys `outbox-refresh`, `outbox-row-<id>`, `outbox-send-again-<id>`
  - The key `no-provider-banner` no longer exists.

- [ ] **Step 1: Write the failing screen tests**

Replace `test/features/outbox/outbox_screen_test.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:pasala/core/current_resort.dart';
import 'package:pasala/core/errors.dart';
import 'package:pasala/data/models/channel_delivery.dart';
import 'package:pasala/data/models/outbox_message.dart';
import 'package:pasala/data/models/resort_membership.dart';
import 'package:pasala/data/repositories/outbox_repository.dart';
import 'package:pasala/features/outbox/outbox_screen.dart';

import '../../support/fake_outbox_source.dart';

final _now = DateTime.utc(2026, 9, 25, 5, 0);

class _FixedResort extends CurrentResort {
  _FixedResort(this.role);
  final ResortRole role;

  @override
  ResortMembership? build() =>
      ResortMembership(propertyId: 'p1', resortName: 'Pasala', role: role);
}

OutboxMessage _row({
  String id = 'm1',
  OutboxChannel channel = OutboxChannel.email,
  String recipient = 'guest@example.com',
  String template = 'booking_confirmation',
  OutboxStatus status = OutboxStatus.pending,
  int attempts = 0,
  String? lastError,
  DateTime? nextAttemptAt,
  DateTime? sentAt,
}) =>
    OutboxMessage(
      id: id,
      reservationId: 'r1',
      channel: channel,
      recipient: recipient,
      template: template,
      status: status,
      attempts: attempts,
      lastError: lastError,
      nextAttemptAt: nextAttemptAt,
      sentAt: sentAt,
      createdAt: DateTime.utc(2026, 8, 1, 10, 30),
    );

Future<void> _pump(
  WidgetTester tester,
  FakeOutboxSource source, {
  ResortRole role = ResortRole.admin,
}) async {
  tester.view.physicalSize = const Size(1200, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(
    // A fresh scope per pump: some tests pump again with another role.
    key: UniqueKey(),
    retry: (_, _) => null,
    overrides: [
      outboxSourceProvider.overrideWithValue(source),
      currentResortProvider.overrideWith(() => _FixedResort(role)),
    ],
    child: MaterialApp(home: OutboxScreen(clock: () => _now)),
  ));
  await tester.pumpAndSettle();
}

List<OutboxMessage> _oneOfEach() => [
      _row(id: 's', status: OutboxStatus.sent, attempts: 1,
          sentAt: DateTime.utc(2026, 8, 1, 10, 31)),
      _row(id: 'k', status: OutboxStatus.skipped, channel: OutboxChannel.sms,
          recipient: 'no phone on file', lastError: 'cannot deliver via sms'),
      _row(id: 'd', status: OutboxStatus.dryRun, attempts: 1,
          lastError: 'Dry run: RESEND_API_KEY is not set'),
      _row(id: 'f', status: OutboxStatus.failed, attempts: 5,
          lastError: 'resend 503: busy'),
      _row(id: 'p', status: OutboxStatus.pending),
    ];

void main() {
  testWidgets("shows each channel's delivery mode and when the sender last ran",
      (tester) async {
    final ran = _now.subtract(const Duration(minutes: 3));
    final source = FakeOutboxSource()
      ..statuses = [
        ChannelDelivery(channel: OutboxChannel.email, mode: DeliveryMode.live,
            provider: 'resend', lastRunAt: ran),
        ChannelDelivery(channel: OutboxChannel.sms, mode: DeliveryMode.dryRun,
            provider: 'msg91', detail: 'MSG91_AUTH_KEY is not set', lastRunAt: ran),
        const ChannelDelivery(channel: OutboxChannel.whatsapp,
            mode: DeliveryMode.unavailable),
      ];
    await _pump(tester, source);

    expect(find.text('Email: sending via Resend'), findsOneWidget);
    expect(find.text('SMS: dry run, nothing is sent'), findsOneWidget);
    expect(find.text('MSG91_AUTH_KEY is not set'), findsOneWidget);
    expect(find.text('WhatsApp: not connected, messages stay queued'), findsOneWidget);
    expect(find.text('Last checked 3 min ago.'), findsOneWidget);
    expect(source.statusPropertyIds, everyElement('p1'));
    expect(source.listedPropertyIds, everyElement('p1'));
  });

  testWidgets('the old "no delivery provider" banner is gone', (tester) async {
    await _pump(tester, FakeOutboxSource()..rows = [_row()]);

    expect(find.byKey(const Key('no-provider-banner')), findsNothing);
    expect(find.textContaining('No delivery provider'), findsNothing);
  });

  testWidgets('an empty queue shows an EmptyState and the never-ran warning',
      (tester) async {
    await _pump(tester, FakeOutboxSource());

    expect(find.text('Nothing queued yet'), findsOneWidget);
    expect(find.text('The sender has not run yet. Pending messages wait until it does.'),
        findsOneWidget);
  });

  testWidgets('sections run Pending, Failed, Dry run, Skipped, Sent',
      (tester) async {
    await _pump(tester, FakeOutboxSource()..rows = _oneOfEach());

    const headers = ['Pending (1)', 'Failed (1)', 'Dry run (1)', 'Skipped (1)', 'Sent (1)'];
    final ys = [for (final h in headers) tester.getTopLeft(find.text(h)).dy];
    expect(ys, orderedEquals([...ys]..sort()));
  });

  testWidgets('rows show their retry, failure or sent line', (tester) async {
    final next = DateTime.utc(2026, 8, 1, 10, 34);
    final sentAt = DateTime.utc(2026, 8, 1, 10, 31);
    await _pump(
      tester,
      FakeOutboxSource()
        ..rows = [
          _row(id: 'p', attempts: 2, lastError: 'resend 503: busy', nextAttemptAt: next),
          _row(id: 'f', status: OutboxStatus.failed, attempts: 5, lastError: 'resend 422: bad to'),
          _row(id: 's', status: OutboxStatus.sent, attempts: 1, sentAt: sentAt),
          _row(id: 'q'),
        ],
    );

    expect(
      find.text('Attempt 2 of 5 failed · next try '
          '${DateFormat('HH:mm').format(next.toLocal())}'),
      findsOneWidget,
    );
    expect(find.text('Failed after 5 attempts'), findsOneWidget);
    expect(
      find.text('Sent ${DateFormat('d MMM yyyy, HH:mm').format(sentAt.toLocal())}'),
      findsOneWidget,
    );
    expect(find.textContaining('Attempt 0'), findsNothing);
  });

  test('attemptLine: nothing while the first attempt is in flight; singular for one', () {
    expect(attemptLine(_row(attempts: 1)), isNull);
    expect(attemptLine(_row(status: OutboxStatus.failed, attempts: 1)),
        'Failed after 1 attempt');
    expect(attemptLine(_row(status: OutboxStatus.skipped)), isNull);
    expect(attemptLine(_row(status: OutboxStatus.dryRun, attempts: 1)), isNull);
  });

  testWidgets('a dry-run reason is muted; a failure is in the error colour',
      (tester) async {
    await _pump(tester, FakeOutboxSource()..rows = _oneOfEach());

    final scheme = Theme.of(tester.element(find.byType(OutboxScreen))).colorScheme;
    expect(
      tester.widget<Text>(find.text('Dry run: RESEND_API_KEY is not set')).style?.color,
      scheme.onSurfaceVariant,
    );
    expect(tester.widget<Text>(find.text('resend 503: busy')).style?.color, scheme.error);
  });

  testWidgets('owners and admins get Send again on failed and dry-run rows only',
      (tester) async {
    for (final role in [ResortRole.owner, ResortRole.admin]) {
      await _pump(tester, FakeOutboxSource()..rows = _oneOfEach(), role: role);

      expect(find.byKey(const Key('outbox-send-again-f')), findsOneWidget, reason: '$role');
      expect(find.byKey(const Key('outbox-send-again-d')), findsOneWidget, reason: '$role');
      for (final id in ['p', 'k', 's']) {
        expect(find.byKey(Key('outbox-send-again-$id')), findsNothing, reason: '$role $id');
      }
    }
  });

  testWidgets('staff and accountants see no Send again', (tester) async {
    for (final role in [ResortRole.staff, ResortRole.accountant]) {
      await _pump(tester, FakeOutboxSource()..rows = _oneOfEach(), role: role);

      expect(find.text('Send again'), findsNothing, reason: '$role');
    }
  });

  testWidgets('Send again retries the row, confirms, and reloads the list',
      (tester) async {
    final source = FakeOutboxSource()..rows = _oneOfEach();
    await _pump(tester, source);

    await tester.tap(find.byKey(const Key('outbox-send-again-f')));
    await tester.pumpAndSettle();

    expect(source.retried, ['f']);
    expect(find.text('Queued to send again.'), findsOneWidget);
    expect(source.listedPropertyIds.length, 2);
  });

  testWidgets('a refused Send again shows the readable reason', (tester) async {
    final source = FakeOutboxSource()
      ..rows = _oneOfEach()
      ..retryError = const NotRetryable();
    await _pump(tester, source);

    await tester.tap(find.byKey(const Key('outbox-send-again-d')));
    await tester.pumpAndSettle();

    expect(find.text('Only failed or dry-run messages can be sent again.'), findsOneWidget);
  });

  testWidgets('a status error does not hide the queue', (tester) async {
    await _pump(
      tester,
      FakeOutboxSource()
        ..rows = [_row(recipient: 'priya@example.com')]
        ..statusError = Exception('boom'),
    );

    expect(find.text('Delivery status is unavailable right now.'), findsOneWidget);
    expect(find.text('priya@example.com'), findsOneWidget);
  });

  testWidgets('a queue error goes through FailureView and keeps the panel',
      (tester) async {
    await _pump(tester, FakeOutboxSource()..error = Exception('boom'));

    expect(find.text('Something went wrong.'), findsOneWidget);
    expect(find.byKey(const Key('delivery-status-panel')), findsOneWidget);
  });

  testWidgets('Refresh reloads both the status and the queue', (tester) async {
    final source = FakeOutboxSource()..rows = [_row()];
    await _pump(tester, source);

    await tester.tap(find.byKey(const Key('outbox-refresh')));
    await tester.pumpAndSettle();

    expect(source.listedPropertyIds.length, 2);
    expect(source.statusPropertyIds.length, 2);
  });

  testWidgets('pull to refresh reloads the queue', (tester) async {
    final source = FakeOutboxSource()..rows = [_row()];
    await _pump(tester, source);

    await tester.fling(find.byType(ListView), const Offset(0, 400), 1000);
    await tester.pumpAndSettle();

    expect(source.listedPropertyIds.length, 2);
  });
}
```

Add to `test/features/owner/notification_settings_screen_test.dart`, inside `main()` after the last test:

```dart
  testWidgets('explains what a switch does, without claiming nothing sends',
      (tester) async {
    await tester.pumpWidget(_appFor(FakeNotificationSettingsRepository()));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Turn a channel off to stop sending it for this resort. Messages '
        'already queued for that channel are skipped too. The Outbox shows '
        'what was sent.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('nothing sends'), findsNothing);
  });
```

- [ ] **Step 2: Run them to verify they fail**

Run: `flutter test test/features/outbox/outbox_screen_test.dart test/features/owner/notification_settings_screen_test.dart`
Expected: FAIL. `OutboxScreen` has no `clock` parameter and `attemptLine` is not defined (compile error), and the settings copy test fails.

- [ ] **Step 3: Rewrite the Outbox screen**

Replace `lib/features/outbox/outbox_screen.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/current_resort.dart';
import '../../core/errors.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/failure_view.dart';
import '../../core/widgets/section_header.dart';
import '../../data/models/outbox_message.dart';
import '../../data/models/resort_membership.dart';
import '../../data/repositories/outbox_repository.dart';
import 'delivery_status_panel.dart';
import 'providers.dart';

final _timestamp = DateFormat('d MMM yyyy, HH:mm');
final _clockTime = DateFormat('HH:mm');

IconData _channelIcon(OutboxChannel channel) => switch (channel) {
      OutboxChannel.email => Icons.mail_outline,
      OutboxChannel.sms => Icons.sms_outlined,
      OutboxChannel.whatsapp => Icons.chat_outlined,
    };

String outboxStatusLabel(OutboxStatus status) => switch (status) {
      OutboxStatus.pending => 'Pending',
      OutboxStatus.sent => 'Sent',
      OutboxStatus.failed => 'Failed',
      OutboxStatus.skipped => 'Skipped',
      OutboxStatus.dryRun => 'Dry run',
    };

/// Section order: what is still on its way, what did not go out, then what
/// did.
const outboxStatusOrder = [
  OutboxStatus.pending,
  OutboxStatus.failed,
  OutboxStatus.dryRun,
  OutboxStatus.skipped,
  OutboxStatus.sent,
];

/// The one extra line under a row's channel and template, or null. A row
/// on its first attempt (no error yet) has none.
String? attemptLine(OutboxMessage m) => switch (m.status) {
      OutboxStatus.pending
          when m.attempts > 0 && m.lastError != null && m.nextAttemptAt != null =>
        'Attempt ${m.attempts} of $outboxMaxAttempts failed · next try '
            '${_clockTime.format(m.nextAttemptAt!.toLocal())}',
      OutboxStatus.failed =>
        'Failed after ${m.attempts} attempt${m.attempts == 1 ? '' : 's'}',
      OutboxStatus.sent when m.sentAt != null =>
        'Sent ${_timestamp.format(m.sentAt!.toLocal())}',
      _ => null,
    };

/// Only a failed or dry-run message can be sent again
/// (`retry_outbox_message`, P0037 otherwise).
bool canSendAgain(OutboxMessage m) =>
    m.status == OutboxStatus.failed || m.status == OutboxStatus.dryRun;

/// `/admin/outbox` -- every guest notification for the current resort,
/// grouped by status, under a panel that says how each channel is being
/// delivered and when the sender last ran. Reachable by staff and above
/// (RLS `outbox_read` underneath); Send again is for owners and admins,
/// which `retry_outbox_message` enforces too.
class OutboxScreen extends ConsumerWidget {
  const OutboxScreen({super.key, this.clock});

  /// Injected so tests can pin "now" for the panel's "last checked" line;
  /// null means the real clock.
  final DateTime Function()? clock;

  Future<void> _sendAgain(
    BuildContext context,
    WidgetRef ref,
    String propertyId,
    OutboxMessage message,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(outboxSourceProvider).retry(message.id);
      ref.invalidate(outboxMessagesProvider(propertyId));
      messenger.showSnackBar(
        const SnackBar(content: Text('Queued to send again.')),
      );
    } on BookingFailure catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(FailureView.messageFor(e))),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resort = ref.watch(currentResortProvider)!;
    final propertyId = resort.propertyId;
    final canRetry =
        const {ResortRole.owner, ResortRole.admin}.contains(resort.role);
    final messagesAsync = ref.watch(outboxMessagesProvider(propertyId));
    final statusAsync = ref.watch(outboxDeliveryStatusProvider(propertyId));

    void refresh() {
      ref.invalidate(outboxDeliveryStatusProvider(propertyId));
      ref.invalidate(outboxMessagesProvider(propertyId));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Outbox'),
        actions: [
          IconButton(
            key: const Key('outbox-refresh'),
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: refresh,
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DeliveryStatusPanel(status: statusAsync, now: (clock ?? DateTime.now)()),
          Expanded(
            child: AsyncView(
              value: messagesAsync,
              onRetry: () => ref.invalidate(outboxMessagesProvider(propertyId)),
              empty: () => const EmptyState(
                icon: Icons.mail_outline,
                title: 'Nothing queued yet',
                message:
                    'Messages appear here as bookings are confirmed or '
                    'cancelled.',
              ),
              data: (messages) => RefreshIndicator(
                onRefresh: () async => refresh(),
                child: _GroupedList(
                  messages: messages,
                  onSendAgain: canRetry
                      ? (m) => _sendAgain(context, ref, propertyId, m)
                      : null,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupedList extends StatelessWidget {
  const _GroupedList({required this.messages, required this.onSendAgain});

  final List<OutboxMessage> messages;

  /// Null when the viewer may not send messages again.
  final void Function(OutboxMessage message)? onSendAgain;

  @override
  Widget build(BuildContext context) {
    final groups = <OutboxStatus, List<OutboxMessage>>{};
    for (final message in messages) {
      groups.putIfAbsent(message.status, () => []).add(message);
    }
    final sections = [
      for (final status in outboxStatusOrder)
        if (groups[status]?.isNotEmpty ?? false) status,
    ];
    final send = onSendAgain;

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: Spacing.lg),
      itemCount: sections.length,
      itemBuilder: (context, i) {
        final status = sections[i];
        final rows = groups[status]!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(title: '${outboxStatusLabel(status)} (${rows.length})'),
            for (final message in rows)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: Spacing.md,
                  vertical: Spacing.xs,
                ),
                child: _OutboxTile(
                  message: message,
                  onSendAgain: send != null && canSendAgain(message)
                      ? () => send(message)
                      : null,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _OutboxTile extends StatelessWidget {
  const _OutboxTile({required this.message, required this.onSendAgain});

  final OutboxMessage message;
  final VoidCallback? onSendAgain;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final extra = attemptLine(message);
    // A dry run is expected until keys are set -- not an error to alarm on.
    final errorColor = message.status == OutboxStatus.dryRun
        ? scheme.onSurfaceVariant
        : scheme.error;

    return Card(
      key: Key('outbox-row-${message.id}'),
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(_channelIcon(message.channel), color: scheme.onSurfaceVariant),
            const SizedBox(width: Spacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(message.recipient, style: textTheme.bodyLarge),
                  const SizedBox(height: Spacing.xs),
                  Text(
                    '${channelLabel(message.channel)} · ${message.template}',
                    style: textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  if (extra != null) ...[
                    const SizedBox(height: Spacing.xs),
                    Text(extra, style: textTheme.bodySmall),
                  ],
                  if (message.lastError != null) ...[
                    const SizedBox(height: Spacing.xs),
                    Text(
                      message.lastError!,
                      style: textTheme.bodySmall?.copyWith(color: errorColor),
                    ),
                  ],
                  if (onSendAgain != null) ...[
                    const SizedBox(height: Spacing.xs),
                    TextButton.icon(
                      key: Key('outbox-send-again-${message.id}'),
                      onPressed: onSendAgain,
                      icon: const Icon(Icons.replay),
                      label: const Text('Send again'),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: Spacing.sm),
            Text(
              _timestamp.format(message.createdAt.toLocal()),
              style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Update the copy that said nothing sends**

In `lib/features/owner/notification_settings_screen.dart`, replace the class doc comment (lines 11–17, from `/// Notification settings -- per-channel enable/disable toggles` to `/// not change.`) with:

```dart
/// Notification settings -- per-channel enable/disable toggles
/// (`0028_notification_settings.sql`). Every channel defaults to enabled.
/// Turning one off skips that channel's messages, both when they are
/// queued (`enqueue_outbox_message`) and when the sender claims them
/// (`claim_outbox_batch`, 0056), so messages already queued are not sent
/// either.
```

and replace the card's `Text(...)` (the three string lines starting `'These toggles only decide whether a message is queued. No '`) with:

```dart
                child: Text(
                  'Turn a channel off to stop sending it for this resort. '
                  'Messages already queued for that channel are skipped too. '
                  'The Outbox shows what was sent.',
                ),
```

In `lib/data/models/notification_settings.dart`, replace the class doc comment (lines 1–4) with:

```dart
/// One row of `notification_settings` -- whether each outbox channel is
/// used for a property. A channel that is off is skipped both when a
/// message is queued and when the sender claims it (0056).
```

In `lib/features/admin/admin_more_screen.dart` line 37, replace:

```dart
      subtitle: 'Queued booking notifications -- not yet sent to anyone',
```

with:

```dart
      subtitle: 'Booking emails and SMS, and whether each was sent',
```

- [ ] **Step 5: Run the tests and analyze**

```bash
flutter test test/features/outbox test/features/owner/notification_settings_screen_test.dart test/features/admin/admin_more_screen_test.dart test/core/router_test.dart
flutter analyze 2>&1 | tail -3
grep -rn "No delivery provider\|not yet sent to anyone\|nothing sends regardless" lib test || echo "old copy gone"
```
Expected: all PASS; analyze shows the baseline count; `old copy gone`.

- [ ] **Step 6: Commit**

```bash
git add lib/features/outbox/outbox_screen.dart test/features/outbox/outbox_screen_test.dart \
  lib/features/owner/notification_settings_screen.dart lib/data/models/notification_settings.dart \
  lib/features/admin/admin_more_screen.dart test/features/owner/notification_settings_screen_test.dart
git commit -m "feat(outbox): show delivery status, retry details and Send again on the Outbox screen" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Phase 4: Integration

### Task 10: Integration and live dry run

**Track:** all. Depends on Tasks 2–9, all merged onto one branch.

**Files:** none are expected to change. If a check fails, fix it in the file the owning task produced and commit that fix separately (`fix(outbox): …`).

**Interfaces:**
- Consumes: everything above.
- Produces: a verified branch.

- [ ] **Step 1: Full automated suites**

```bash
supabase db reset
supabase test db
flutter analyze 2>&1 | tail -3
flutter test
(cd supabase/functions/outbox-dispatch && deno test && deno check index.ts && deno lint)
git checkout pubspec.lock 2>/dev/null; git status --short
```
Expected:
- pgTAP all pass, apart from the three known time-window failures if run between 00:00 and 05:30 IST.
- Analyze shows the baseline 2 infos.
- Every Flutter test and every Deno test passes.
- `git status` shows no changes.

- [ ] **Step 2: Live dry run through the real function**

Start the functions server as a background process (it keeps running):

```bash
supabase functions serve
```

In another shell:

```bash
DB=postgresql://postgres:postgres@127.0.0.1:54322/postgres
psql $DB -Atc "select channel, status, count(*) from public.outbox group by 1,2 order by 1,2"
SERVICE_KEY=$(supabase status -o env | grep '^SERVICE_ROLE_KEY=' | cut -d= -f2 | tr -d '"')
curl -s -X POST http://127.0.0.1:54321/functions/v1/outbox-dispatch -H "Authorization: Bearer $SERVICE_KEY"; echo
curl -s -o /dev/null -w "%{http_code}\n" -X POST http://127.0.0.1:54321/functions/v1/outbox-dispatch -H "Authorization: Bearer wrong"
psql $DB -Atc "select channel, status, count(*) from public.outbox group by 1,2 order by 1,2"
psql $DB -Atc "select channel, mode, provider, detail from public.outbox_channel_status order by 1"
```
Expected:
- The first query shows the seed booking's rows `pending`.
- The good curl returns `{"claimed":N,…,"dry_run":N,…,"modes":{"email":"dry_run","sms":"dry_run"}}` with N ≥ 1. The bad curl prints `401` (or `401` from the gateway's JWT check; either way it is not 200).
- Afterwards the email/SMS rows are `dry_run`, WhatsApp rows are still `pending`, and `outbox_channel_status` has `email|dry_run|resend|RESEND_API_KEY is not set` and `sms|dry_run|msg91|MSG91_AUTH_KEY is not set`.

- [ ] **Step 3: The cron path end to end (then clean up)**

```bash
psql $DB -c "select vault.create_secret('http://host.docker.internal:54321/functions/v1/outbox-dispatch', 'outbox_dispatch_url')"
psql $DB -c "select vault.create_secret('$SERVICE_KEY', 'outbox_dispatch_key')"
psql $DB -Atc "select public.outbox_dispatch_tick()"
```
Expected: `requested`. Wait about 70 seconds (use a Monitor or an until-loop, not a foreground sleep), then:

```bash
psql $DB -Atc "select status_code, left(content, 120) from net._http_response order by created desc limit 3"
psql $DB -Atc "select last_run_at > now() - interval '3 minutes' from public.outbox_channel_status where channel = 'email'"
psql $DB -c "delete from vault.secrets where name in ('outbox_dispatch_url','outbox_dispatch_key')"
```
Expected: at least one `200` with a JSON summary, and `t`. If `host.docker.internal` is unreachable on this machine, record that in the report and treat Step 2 as the proof. The URL is a local Docker setting, not a defect.

Stop the background `supabase functions serve` process.

- [ ] **Step 4: The app against the real database**

Run the web app (`make run-web`, or the `run` skill), sign in as the seeded admin (see README → Seeded accounts) and open `/admin/outbox`. Check:
- The panel shows "Email: dry run, nothing is sent" with "RESEND_API_KEY is not set", the same for SMS, and "WhatsApp: not connected, messages stay queued", with "Last checked … ago." (or the stale warning if more than 10 minutes passed since Step 2).
- There is a "Dry run (N)" section, each row with a Send again button.
- Tap Send again on one row: the snackbar reads "Queued to send again." and the row moves to "Pending".

Take a screenshot for the report. Then reset the database: `supabase db reset`.

- [ ] **Step 5: Confirm that no secret is committed, then report**

```bash
git log --oneline feat/gaps..HEAD
git diff feat/gaps..HEAD | grep -nE "re_[A-Za-z0-9]{12,}|eyJ[A-Za-z0-9_-]{30,}|authkey\s*[:=]\s*['\"][A-Za-z0-9]{10,}" || echo "no secrets in the diff"
```
Expected: the task commits, and `no secrets in the diff`. Report the pgTAP, Flutter and Deno totals, the dry-run curl output, and the cron result.
