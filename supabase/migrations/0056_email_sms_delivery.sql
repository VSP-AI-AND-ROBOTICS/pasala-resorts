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

-- The backlog. Until now nothing sent the outbox (0017 never marks a row
-- sent), so on a live database every pending email and SMS row is old:
-- confirmations, reminders and cancellations for stays long past. With
-- the default above they would all be due on the dispatcher's first run
-- and go out to real guests at once. Retire them before the dispatcher
-- exists. 'failed' with no attempts, so the Outbox screen shows why and
-- an owner can still send a single one again (retry_outbox_message).
-- WhatsApp rows are never claimed and are left as they are.
update public.outbox
   set status = 'failed',
       last_error = 'Not sent: queued before email/SMS delivery was enabled.'
 where status = 'pending'
   and channel in ('email', 'sms');

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

-- ---------------------------------------------------------------------
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

-- ---------------------------------------------------------------------
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

-- ---------------------------------------------------------------------
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

-- ---------------------------------------------------------------------
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

-- ---------------------------------------------------------------------
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

-- ---------------------------------------------------------------------
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

-- ---------------------------------------------------------------------
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

-- ---------------------------------------------------------------------
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

-- ---------------------------------------------------------------------
-- Every minute. Without the two Vault secrets the tick answers
-- 'not_configured' and sends nothing, so a fresh `supabase db reset`
-- never calls out.

select cron.schedule(
  'outbox-dispatch', '* * * * *',
  $$select public.outbox_dispatch_tick()$$);
