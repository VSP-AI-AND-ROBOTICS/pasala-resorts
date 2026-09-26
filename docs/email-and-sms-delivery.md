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
- Messages queued before this delivery existed are never sent
  automatically. Migration 0056 marks every email and SMS still pending at
  that point **failed** with the reason `Not sent: queued before email/SMS
  delivery was enabled.`, so the first run does not send months of old
  confirmations to guests. Use **Send again** for any that still matter.
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
