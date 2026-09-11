-- Per-property notification channel toggles. Nothing in this app has ever
-- sent an email/SMS/WhatsApp message (see 0017_outbox.sql's header) --
-- these toggles do not change that; they only decide whether a channel's
-- outbox row gets queued as `pending` at all, or is skipped up front with
-- an honest reason, exactly like the existing "no email on file" skip path
-- `enqueue_outbox_message` already has. See
-- docs/superpowers/specs/2026-08-31-owner-super-admin-flow-design.md.
-- All three channels default to enabled: this table is an opt-OUT control,
-- not opt-in. Before this migration every channel was already reachable
-- whenever the customer had the relevant contact info on file, gated only
-- by that (see `enqueue_outbox_message`'s existing "no phone on file" skip
-- path) -- defaulting `sms_enabled`/`whatsapp_enabled` to false here would
-- have silently disabled messaging for every property that never visits
-- the new Settings screen, which is exactly the behaviour change this
-- migration's own header promises NOT to make.
create table public.notification_settings (
  property_id      uuid primary key references public.properties(id) on delete cascade,
  email_enabled    boolean not null default true,
  sms_enabled      boolean not null default true,
  whatsapp_enabled boolean not null default true,
  updated_at       timestamptz not null default now()
);

grant select, insert, update, delete on public.notification_settings to authenticated;

alter table public.notification_settings enable row level security;

create policy notification_settings_read on public.notification_settings
  for select to authenticated
  using (public.is_staff_or_above());

create policy notification_settings_admin_write on public.notification_settings
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- Backfill one row per existing property with today's implicit behaviour
-- (email on, sms/whatsapp off) -- see 0013_refund_policy.sql's identical
-- backfill-on-migrate precedent. A property with no row here is treated as
-- this same default by `enqueue_outbox_message` below (`coalesce`d), so
-- this backfill is a convenience for the Settings screen to have something
-- to show immediately, not a correctness requirement.
insert into public.notification_settings (property_id)
select id from public.properties;

-- Re-derives the reservation's property (the original had no reason to)
-- and skips the channel outright, before rendering or even checking for a
-- recipient, when that channel is disabled for the property. The skip
-- reason is deliberately distinct from "no email/phone on file" so the
-- outbox screen can tell the two apart.
create or replace function public.enqueue_outbox_message(
  p_reservation_id uuid,
  p_template       text
) returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_tpl       public.outbox_templates;
  v_row       public.reservations;
  v_profile   public.profiles;
  v_settings  public.notification_settings;
  v_email     text;
  v_recipient text;
  v_rendered  jsonb;
  v_channel_enabled boolean;
begin
  select * into v_tpl from public.outbox_templates where name = p_template;
  if not found then
    return;
  end if;

  select * into v_row from public.reservations where id = p_reservation_id;
  select * into v_profile from public.profiles where id = v_row.customer_id;
  select email into v_email from auth.users where id = v_row.customer_id;

  select ns.* into v_settings
  from public.units u
  join public.notification_settings ns on ns.property_id = u.property_id
  where u.id = v_row.unit_id;

  -- A property with no settings row at all (created after this migration
  -- ran, before anyone has visited its Settings screen) is treated as
  -- "every channel enabled" -- the same opt-out default the table's own
  -- column defaults establish for a row that does exist.
  v_channel_enabled := case v_tpl.channel
    when 'email'    then coalesce(v_settings.email_enabled, true)
    when 'sms'      then coalesce(v_settings.sms_enabled, true)
    when 'whatsapp' then coalesce(v_settings.whatsapp_enabled, true)
  end;

  if not v_channel_enabled then
    insert into public.outbox
      (reservation_id, channel, recipient, template, subject, body,
       status, last_error)
    values (
      p_reservation_id, v_tpl.channel, format('%s (channel disabled)', v_tpl.channel),
      p_template, null, null, 'skipped',
      format('%s notifications are disabled in this property''s settings',
             v_tpl.channel));
    return;
  end if;

  v_recipient := case v_tpl.channel
    when 'email' then nullif(btrim(coalesce(v_email, '')), '')
    else nullif(btrim(coalesce(v_profile.phone, '')), '')
  end;

  if v_recipient is null then
    insert into public.outbox
      (reservation_id, channel, recipient, template, subject, body,
       status, last_error)
    values (
      p_reservation_id, v_tpl.channel,
      case v_tpl.channel when 'email' then 'no email on file'
                          else 'no phone on file' end,
      p_template, null, null, 'skipped',
      format('cannot deliver via %s: customer %s has no %s on file',
             v_tpl.channel, v_row.customer_id,
             case v_tpl.channel when 'email' then 'email address'
                                 else 'phone number' end));
    return;
  end if;

  v_rendered := public.render_template(p_template, p_reservation_id);

  insert into public.outbox
    (reservation_id, channel, recipient, template, subject, body, status)
  values (
    p_reservation_id, v_tpl.channel, v_recipient, p_template,
    v_rendered ->> 'subject', v_rendered ->> 'body', 'pending');
end;
$$;

-- `create or replace` does not reset a function's ACL, but this function
-- was already revoked from every client role in 0017_outbox.sql -- repeated
-- here for the same belt-and-suspenders reason `cancel_booking` repeats its
-- revoke in 0013/0016.
revoke execute on function public.enqueue_outbox_message(uuid, text)
  from public;
revoke execute on function public.enqueue_outbox_message(uuid, text)
  from anon, authenticated;
