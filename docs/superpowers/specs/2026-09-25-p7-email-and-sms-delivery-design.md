# Email and SMS Delivery (P7) — Design

## Why

Every booking confirmation, payment receipt and cancellation notice already
lands in `public.outbox` (`0017_outbox.sql`, made resort-aware in
`0045_resort_functions.sql`), rendered and addressed, and then nothing
happens: no code anywhere sends a row or marks it `sent`. The Outbox screen
(`lib/features/outbox/outbox_screen.dart`) says so with a permanent "No
delivery provider is configured" banner, the Notification settings screen
says "nothing sends regardless", and the README lists delivery as out of
scope.

The product owner accepted this gap-closing round on 2026-09-25 ("OK all ...
auto approve", `gaps-decisions.md` section P7): send email through Resend and
SMS through MSG91 from a Supabase Edge Function that pg_cron calls every
minute, with retries, and fall back to a dry run that sends nothing when the
provider keys are not set.

WhatsApp stays unsent: it needs a Meta Business account, which is a separate
project. Its rows keep being queued exactly as today.

## Decisions (accepted 2026-09-25; items marked *judgment* were left open by the decision file and are settled here)

1. **One Edge Function, `outbox-dispatch`** (`supabase/functions/outbox-dispatch/`,
   Deno, its own `deno.json`). It claims a batch of due rows, sends each one,
   and reports each result back. pg_cron calls it every minute through
   `pg_net`, and a person can run it by hand with `curl` or
   `supabase functions invoke`.
2. **Providers:** email through the Resend HTTP API (`RESEND_API_KEY`,
   `RESEND_FROM` = the deployment's sender address). SMS through the MSG91
   Flow API (`MSG91_AUTH_KEY`, optional `MSG91_SENDER_ID`, and
   `MSG91_TEMPLATES`, a JSON map from outbox template name to MSG91 template
   id). The keys live only in Edge Function secrets and never in the Flutter
   app or the repository.
3. **Dry run is per channel.** When a channel's keys are missing, its rows are
   claimed and marked with the new status **`dry_run`**, with the reason (for
   example `Dry run: RESEND_API_KEY is not set`) in `last_error`. Nothing is
   sent. The function logs the row id, channel, template and outcome.
   Email can be live while SMS is still a dry run.
4. **Retries:** each claim counts as one attempt. A failure that might succeed
   later (network error, HTTP 408, 429 or 5xx) goes back to `pending` with
   `next_attempt_at = now() + 2^(attempts-1) minutes`: 1, 2, 4 and 8 minutes.
   The fifth failure, or any permanent failure (another 4xx, a missing MSG91
   template, a phone number that is not an Indian mobile), sets `failed`.
   *Judgment:* backoff and the attempt limit live in SQL
   (`complete_outbox_message`), so the server enforces them whatever the
   function does.
5. **Claiming** uses `FOR UPDATE SKIP LOCKED` inside the definer function
   `claim_outbox_batch`, which also sets a **5-minute lease**
   (`next_attempt_at = now() + 5 min`). A second run in the same minute skips
   leased rows. If a run dies halfway, its rows come back after the lease.
   *Judgment:* the lease is needed because the row lock ends when the RPC
   returns, before the provider call.
6. **Notification settings are checked twice:** when a message is queued (as
   today) and again when it is claimed. A row queued before its channel was
   turned off is marked `skipped` with the reason text `enqueue_outbox_message`
   already uses, and is not sent.
7. **Only email and SMS rows are claimed.** WhatsApp rows stay `pending`, and
   the Outbox screen says "WhatsApp: not connected, messages stay queued".
   *Judgment:* they are not marked `dry_run` or `skipped`, so a later
   WhatsApp sender can pick them up.
8. **Rows are not re-sent automatically when keys arrive.** A `dry_run` row is
   final. *Judgment:* an owner or admin can press **Send again** on a
   `failed` or `dry_run` row (`retry_outbox_message`). The row goes back to
   `pending` with zero attempts, and an audit row is written. Without this, a
   failed message could never be recovered.
9. **The Outbox screen shows the delivery state for each channel**, not a
   fixed banner. The function records each run in `outbox_channel_status`
   (mode, provider, detail, time), and the screen reads it through
   `outbox_delivery_status(p_property)`. If the last run is older than 10
   minutes, or no run has ever happened, the screen shows a warning.
10. **The pg_cron job reads its target from Supabase Vault.** The job calls
    `outbox_dispatch_tick()`, which reads the secrets `outbox_dispatch_url`
    and `outbox_dispatch_key` (the service role key). If either is missing,
    it returns `not_configured` and sends no request, so a fresh
    `supabase db reset` never calls anything. *Judgment:* Vault, not a
    table, because the key is a secret.
11. **The function trusts only the service role.** It accepts `POST` with
    `Authorization: Bearer <SUPABASE_SERVICE_ROLE_KEY>`, compared in constant
    time, and returns 401 for anything else. The three RPCs it calls are
    granted to `service_role` only.
12. **Resend request details** (*judgment*): the sender is
    `"<resort name> <RESEND_FROM>"`, with `<>",;` and line breaks removed
    from the name; the body is plain text; `Idempotency-Key` is the outbox
    row id, so a row re-sent after a lost reply is not delivered twice.
13. **MSG91 request details** (*judgment*): `POST
    https://control.msg91.com/api/v5/flow` with header `authkey`, body
    `{template_id, short_url: "0", recipients: [{mobiles: "91XXXXXXXXXX",
    guest_name, unit_name, property_name, check_in, check_out, total,
    currency, cancel_reason}]}`, plus `sender` when `MSG91_SENDER_ID` is set.
    Each variable is cut to 30 characters (the DLT per-variable limit). The
    MSG91 templates must use these variable names. A reply of HTTP 200 with
    `"type":"error"` counts as a permanent failure. Phone numbers are
    normalised to `91` plus a 10-digit mobile number starting with 6 to 9;
    anything else fails with "not a valid Indian mobile number".
14. **Template variables** come from a new internal function,
    `outbox_template_context(reservation)`. It holds the context that
    `render_template` builds today, and `render_template` now calls it, so the
    email text and the SMS variables cannot drift apart. The claim returns
    the variables without `customer_email` and `customer_phone`.
15. **Error code P0037** (`outbox_not_in_flight` / `not_retryable`): completing
    a row that is not in flight, or retrying a row that is not `failed` or
    `dry_run`. The app shows "Only failed or dry-run messages can be sent
    again."
16. *Judgment:* suspended and archived resorts still get their guest
    messages sent (a cancellation notice matters more then, not less).
    Blocking sends by resort status is out of scope.
17. *Judgment:* one run handles one batch (`OUTBOX_BATCH_SIZE`, default 50,
    limited to 1 to 200). A run every minute is ample for resort volumes.

## Data model — `supabase/migrations/0056_email_sms_delivery.sql`

- `public.outbox_status` gains the value `dry_run`. The migration does not
  use the new value outside function bodies, because a new enum value
  cannot be used in the transaction that adds it.
- `public.outbox` gains:
  - `next_attempt_at timestamptz not null default now()`: when the row is
    next due, which is also the lease end while a run holds it
  - `last_attempt_at timestamptz`
  - `provider_message_id text`: Resend's email id or MSG91's request id
  - index `outbox_due_idx on outbox (next_attempt_at) where status = 'pending'`
  - Rows already queued are not sent. Nothing sent the outbox before this
    migration, so on a live database every pending email and SMS row is
    old, and the `now()` default would make them all due on the first run.
    The migration marks them `failed` with no attempts and the reason
    `Not sent: queued before email/SMS delivery was enabled.`; an owner can
    still send one again from the Outbox screen. WhatsApp rows are left
    as they are. (Changed after the final review; the first version sent
    the backlog.)
- New platform-owned table `public.outbox_channel_status`:
  - `channel public.outbox_channel primary key`
  - `mode text not null check (mode in ('live','dry_run'))`
  - `provider text not null`, `detail text`, `last_run_at timestamptz not null`
  - It has no `property_id`, because it holds deployment facts and no resort
    data. RLS is enabled with no policies, and there are no grants to
    `anon`/`authenticated`. It is read only through `outbox_delivery_status`.

## Functions (security definer, `search_path = public, pg_temp`, revoked from `public` and `anon`, on the allow-list in `37_tenancy_isolation_test.sql`)

For the service role only (also revoked from `authenticated`, granted to
`service_role`):

- `claim_outbox_batch(p_limit int default 25) returns table (id uuid,
  property_id uuid, reservation_id uuid, channel public.outbox_channel,
  recipient text, template text, subject text, body text, attempts int,
  vars jsonb)`. The limit is clamped to 1 to 200. The function locks due
  rows (`status = 'pending'`, channel `email` or `sms`,
  `next_attempt_at <= now()`, oldest due first) with `FOR UPDATE SKIP LOCKED`,
  then handles each row:
  - channel now disabled for the resort: marked `skipped` with the disabled
    reason, not returned
  - `attempts >= 5`: marked `failed`, not returned
  - otherwise: `attempts + 1`, `last_attempt_at = now()`,
    `next_attempt_at = now() + 5 min`, and the row is returned with `vars`
- `complete_outbox_message(p_id uuid, p_outcome text, p_error text default
  null, p_provider_id text default null) returns public.outbox_status`.
  - `p_outcome` must be `sent`, `dry_run`, `retry` or `failed` (else 22023).
  - An unknown id raises P0002. A row that is not `pending` with
    `attempts > 0` raises **P0037**.
  - `sent` sets `sent_at` and `provider_message_id` and clears `last_error`.
  - `dry_run` stores the reason.
  - `retry` goes back to `pending` with the backoff, or to `failed` once
    `attempts >= 5`.
  - `failed` is final.
  - `last_error` is trimmed to 1000 characters.
- `record_outbox_dispatch_run(p_channels jsonb) returns void`. It upserts one
  `outbox_channel_status` row for each `email`/`sms` element
  (`{channel, mode, provider, detail}`) with `last_run_at = now()`, and
  ignores any other channel.

For the app (granted to `authenticated`):

- `outbox_delivery_status(p_property uuid) returns table (channel
  public.outbox_channel, mode text, provider text, detail text, last_run_at
  timestamptz)` asserts read access for `owner, admin, staff, accountant` at
  `p_property`. It always returns three rows (email, sms, whatsapp).
  WhatsApp is `unavailable`; a channel that has never run is `not_running`.
- `retry_outbox_message(p_message uuid) returns void` reads the row's
  `property_id` and asserts write access for `owner, admin` (so a suspended
  resort gets P0022). The row must be `failed` or `dry_run`, else P0037. It
  resets the row to `pending` with `attempts = 0`,
  `next_attempt_at = now()`, and no error or provider id, and writes
  `audit_log (entity 'outbox', action 'retry')`.

Internal (revoked from every client role):

- `outbox_template_context(p_reservation_id uuid) returns jsonb`: the
  context block from `render_template` (0045), unchanged.
- `render_template` is copied from its latest definition
  (`0045_resort_functions.sql`, lines 1863–1935), and its context block is
  replaced by a call to `outbox_template_context`.
- `outbox_dispatch_tick() returns text` reads the two Vault secrets with
  dynamic SQL (and returns `not_configured` if Vault is missing), then
  returns `outbox_dispatch_post(url, key)`.
- `outbox_dispatch_post(p_url text, p_key text) returns text` (not
  definer) returns `not_configured` if either argument is blank.
  Otherwise it calls `net.http_post(url, body '{}', headers
  {Content-Type, Authorization: Bearer <key>}, timeout 30 s)` and returns
  `requested`. *Judgment:* it is split from the tick so tests can check
  the POST without writing Vault secrets that may belong to a developer's
  setup.
- `outbox_retry_delay(p_attempts int) returns interval` (plain SQL,
  immutable, not definer) gives `2^(greatest(p_attempts,1)-1)` minutes.
- `cron.schedule('outbox-dispatch', '* * * * *', 'select public.outbox_dispatch_tick()')`.

## Edge Function — `supabase/functions/outbox-dispatch/`

| File | Responsibility |
|---|---|
| `deno.json` | imports (`@std/assert` for tests), tasks `test` and `check` |
| `types.ts` | `ClaimedMessage`, `Outcome`, `SendResult`, `EmailSender`, `SmsSender`, `OutboxStore`, `ChannelMode`, `DispatchSummary`, `FetchFn` |
| `util.ts` | `safeJson`, `clip`, `errorText`, `isRetryableStatus` |
| `config.ts` | `loadConfig(env)`: reads the Supabase URL and service key (required), the batch size, and the per-channel `live`/`dry_run` setup with the reason |
| `resend.ts` | `ResendEmailSender`, `displayName` |
| `msg91.ts` | `Msg91SmsSender`, `normalizeIndianMobile`, `smsVars` |
| `store.ts` | `RestOutboxStore`: the three RPCs over PostgREST with the service key; `outcomeArgs` |
| `dispatch.ts` | `deliver(row)` and `dispatchOnce()`: claims one batch, sends each row, completes each row, records the run |
| `handler.ts` | `handleRequest(req, makeDeps)`: `POST` only, bearer check, 200 summary / 401 / 405 / 500 not configured / 502 store unavailable |
| `deps.ts` | `buildDeps(env, fetch)`: wires the real store and senders |
| `index.ts` | `Deno.serve(...)` only |

Rules:
- Logs never contain a recipient, subject or body.
- A sender that throws counts as `retry`.
- If completing one row fails, the function counts the error and moves on
  to the next row; the lease brings the failed row back later.
- Response body: `{claimed, sent, dry_run, retry, failed, errors, modes: {email, sms}}`.

## App

- `lib/data/models/outbox_message.dart`: `OutboxStatus.dryRun` (`dry_run`,
  parsed with an explicit switch that rejects unknown values),
  `nextAttemptAt`, `lastAttemptAt`, and `outboxMaxAttempts = 5`.
- `lib/data/models/channel_delivery.dart`: `DeliveryMode { live, dryRun,
  unavailable, notRunning }` and `ChannelDelivery.fromJson`.
- `lib/data/repositories/outbox_repository.dart`: `OutboxSource` gains
  `deliveryStatus(propertyId)` and `retry(messageId)`.
  `lib/features/outbox/providers.dart` gains `outboxDeliveryStatusProvider`,
  a family keyed by property id.
- `lib/core/errors.dart`: P0037 maps to `NotRetryable` ("Only failed or
  dry-run messages can be sent again.").
- Outbox screen (`/admin/outbox`, staff and above, unchanged route):
  - The fixed "No delivery provider" banner is removed. In its place is a
    delivery status panel with one line per channel:
    - "Email: sending via Resend"
    - "SMS: dry run, nothing is sent", with the reason below it
    - "WhatsApp: not connected, messages stay queued"
    - "Email: waiting for the sender to run"
  - A footer under the channel lines reads "Last checked 3 min ago". If the
    last run is more than 10 minutes old, it warns "The sender last ran 2 h
    ago. Pending messages are waiting.". If the sender has never run, it
    reads "The sender has not run yet. Pending messages wait until it
    does.".
  - If the status cannot load, the panel says "Delivery status is
    unavailable right now." and the list still shows.
  - Sections, in order: Pending, Failed, Dry run, Skipped, Sent.
  - Each row can show one extra line:
    - "Attempt 2 of 5 failed · next try 10:32"
    - "Failed after 5 attempts"
    - "Sent 1 Aug 2026, 10:31"
  - `last_error` is shown in the error colour, except on dry-run rows,
    where it is shown muted.
  - Owners and admins get a **Send again** button on Failed and Dry run
    rows. It shows "Queued to send again.", or the failure message if the
    retry fails.
  - A Refresh action in the app bar and pull-to-refresh on the list reload
    both the status and the list.
- Notification settings copy becomes: "Turn a channel off to stop sending it
  for this resort. Messages already queued for that channel are skipped too.
  The Outbox shows what was sent."
- Admin More subtitle for Outbox becomes "Booking emails and SMS, and
  whether each was sent".
- Docs: a new `docs/email-and-sms-delivery.md` covers:
  - the secrets (`supabase secrets set ...`)
  - Resend domain verification
  - the MSG91 DLT templates and their variable names
  - deploying the function
  - the two Vault secrets for the cron job (hosted and local URLs)
  - running the function by hand
  - dry-run behaviour and Send again

  In the README, the out-of-scope bullet and the known-limitations bullet
  change to point at the new doc (WhatsApp is still unsent).

## Rules

- No client role can write `outbox` directly; this is unchanged, and every
  write goes through a definer function.
- `retry_outbox_message` derives the resort from the row and never takes a
  resort id from the client.
- No secret is committed. With no secrets set, nothing is ever sent: the
  cron job is `not_configured`, and a manual run is a dry run.
- Tests never reach Resend, MSG91 or the network: `deno test` runs without
  `--allow-net` and uses stub `fetch` functions.

## Testing

- pgTAP `supabase/tests/46_email_sms_delivery_test.sql`:
  - contract: enum value, columns, table and RLS, function signatures,
    execute grants per role, definer functions with a pinned search_path
  - claim: due rows only, oldest first, no WhatsApp, the channel-disabled
    skip, attempts and lease, limit, the attempt cap, variables without
    contact fields
  - complete: each outcome, backoff, fifth failure, P0037, 22023, P0002
  - retry: role matrix, other resort, suspended resort, wrong state, audit
  - delivery status: never run, after a run, whatsapp, bad mode, other
    resort, customer and anon refused
  - dispatcher POST: `not_configured` without a URL or key; with both it
    queues one `pg_net` request with the bearer header. The tick itself
    answers `not_configured` or `requested`.
  - the cron job exists
  - The 37 allow-list gains the seven new definer names.
- Deno (`deno test` in the function folder, no permissions):
  - config parsing
  - Resend and MSG91 request shapes, and how each HTTP status maps to sent,
    retry or failed
  - phone number normalisation
  - PostgREST store calls
  - dispatch orchestration with a fake store: dry run, live, retry,
    permanent failure, sender throwing, complete failing, summary, and no
    personal data in logs
  - handler auth and status codes
  - dependency wiring
- Flutter:
  - `OutboxMessage`/`ChannelDelivery` parsing and the P0037 mapping
  - delivery panel lines and the stale, never-run and error states
  - Outbox screen sections, extra lines, Send again for owner/admin only,
    refresh, and the resort id passed through
  - notification settings copy

## Out of scope

- WhatsApp delivery.
- Automatically re-sending `dry_run` rows once keys are set.
- Per-resort sender addresses or per-resort provider accounts.
- Delivery receipts and bounce webhooks from Resend or MSG91.
- Messages without a reservation. `outbox.reservation_id` stays `not null`;
  P10's owner notifications will need that relaxed in P10's own migration.
- Blocking sends for suspended or archived resorts.
- Editing templates in the app.
