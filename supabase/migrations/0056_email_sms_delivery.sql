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
