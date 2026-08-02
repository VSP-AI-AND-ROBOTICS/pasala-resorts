-- The notification outbox. The owner has no email, SMS or WhatsApp
-- provider configured yet, and cannot get WhatsApp for weeks -- so this
-- migration builds everything up to the moment of sending, and stops
-- there, honestly. `outbox_status` includes `sent` only because it is a
-- real future state a sender service will eventually reach; NOTHING in
-- this migration ever writes it. `outbox` has no INSERT/UPDATE/DELETE
-- grant to `authenticated` (or `anon`) at all -- the only writer is
-- `enqueue_outbox_message`, a SECURITY DEFINER function invoked solely by
-- the trigger below, which never once sets `status = 'sent'`. That is not
-- a policy choice that could be bypassed by a forged request; it is the
-- literal absence of any GRANT that would let a client write here, so the
-- table-privilege check (42501) rejects any write before RLS is even
-- evaluated, regardless of role.

create type public.outbox_channel as enum ('email', 'sms', 'whatsapp');
create type public.outbox_status  as enum
  ('pending', 'sent', 'failed', 'skipped');

-- Templates live in their own table, keyed by name, so copy can change
-- without a migration. `event` groups the channel-specific variants of the
-- same SRS message (e.g. `booking_confirmation`/`booking_confirmation_sms`/
-- `booking_confirmation_whatsapp` all share `event = 'booking_confirmation'`)
-- so the trigger below can fan out to every configured channel for an
-- event data-drivenly, rather than the channel list being hard-coded in
-- PL/pgSQL and needing a migration of its own every time a channel is
-- added or removed for one event.
create table public.outbox_templates (
  name             text primary key,
  event            text not null,
  channel          public.outbox_channel not null,
  subject_template text,
  body_template    text not null,
  created_at       timestamptz not null default now(),
  unique (event, channel)
);

grant select on public.outbox_templates to authenticated;
grant insert, update, delete on public.outbox_templates to authenticated;

alter table public.outbox_templates enable row level security;

create policy outbox_templates_read on public.outbox_templates
  for select to authenticated
  using (public.is_staff_or_above());

create policy outbox_templates_admin_write on public.outbox_templates
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

create table public.outbox (
  id             uuid primary key default gen_random_uuid(),
  reservation_id uuid not null references public.reservations(id) on delete cascade,
  channel        public.outbox_channel not null,
  recipient      text not null,
  template       text not null references public.outbox_templates(name),
  subject        text,
  body           text,
  status         public.outbox_status not null default 'pending',
  attempts       int not null default 0 check (attempts >= 0),
  last_error     text,
  created_at     timestamptz not null default now(),
  sent_at        timestamptz,
  -- A queue full of rows that could never be sent is worse than a queue
  -- that tells you which contacts are missing (see `enqueue_outbox_message`
  -- below) -- so a row with nothing in `recipient` may never exist at all,
  -- enforced here, not just by application code that a future change could
  -- accidentally bypass.
  constraint outbox_recipient_not_empty check (btrim(recipient) <> ''),
  -- `sent_at` and `status = 'sent'` can only ever be true together. Nothing
  -- in this phase sets either -- see the migration header -- but this is
  -- what makes "sent_at implies sent" (and vice versa) a schema-level fact
  -- rather than a convention some future write path could violate.
  constraint outbox_sent_at_matches_status check (
    (status = 'sent') = (sent_at is not null)
  )
);

create index outbox_reservation_idx on public.outbox(reservation_id);
create index outbox_status_idx on public.outbox(status);

-- Staff-and-above read only. Deliberately NO insert/update/delete grant to
-- `authenticated` or `anon` -- see the migration header. Even an admin
-- cannot write a row directly; only `enqueue_outbox_message` (SECURITY
-- DEFINER, run solely from the trigger below) can.
grant select on public.outbox to authenticated;

alter table public.outbox enable row level security;

create policy outbox_read on public.outbox
  for select to authenticated
  using (public.is_staff_or_above());

-- Builds the `{subject, body}` for `p_template` against `p_reservation_id`,
-- substituting simple `{{placeholder}}` tokens over a context built from
-- the reservation, its unit, property and customer. Read-only and internal
-- -- called only from `enqueue_outbox_message` below -- so it is revoked
-- from every client role at the end of this file, same as
-- `release_reservation_coupon` in migration 0016.
create function public.render_template(
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
  v_row      public.reservations;
  v_unit     public.units;
  v_property public.properties;
  v_profile  public.profiles;
  v_email    text;
  v_ctx      jsonb;
  v_subject  text;
  v_body     text;
  v_key      text;
begin
  select * into v_tpl from public.outbox_templates where name = p_template;
  if not found then
    raise exception 'unknown outbox template %', p_template
      using errcode = 'P0002';
  end if;

  select * into v_row from public.reservations where id = p_reservation_id;
  if not found then
    raise exception 'reservation not found' using errcode = 'P0002';
  end if;

  select * into v_unit from public.units where id = v_row.unit_id;
  select * into v_property from public.properties where id = v_unit.property_id;
  select * into v_profile from public.profiles where id = v_row.customer_id;
  select email into v_email from auth.users where id = v_row.customer_id;

  -- Every value here is `coalesce`d, even columns currently `not null`
  -- (`unit_name`, `property_name`) -- Postgres's `replace()` returns NULL if
  -- ANY argument is NULL, so a single NULL context value would silently
  -- collapse the ENTIRE rendered subject/body to NULL in the substitution
  -- loop below, not just leave that one token unreplaced. Those two columns
  -- cannot be NULL today, so this is currently unreachable in practice, but
  -- relying on a `not null` constraint two joins away to keep this function
  -- safe is exactly the kind of inconsistency that breaks silently the
  -- moment either constraint is ever relaxed. Defence in depth, applied
  -- uniformly rather than selectively.
  v_ctx := jsonb_build_object(
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

-- Enqueues one outbox row for `p_template` against `p_reservation_id`.
-- Silently does nothing if `p_template` is not configured -- an event with
-- no template for some channel is not an error, it just means that
-- channel is not offered yet.
--
-- The recipient comes from the customer's profile: `email` for an email
-- channel, `profiles.phone` for sms/whatsapp. `profiles.phone` is nullable
-- and most seeded customers have no phone, so an sms/whatsapp send would
-- have nothing to send TO. Rather than enqueueing an undeliverable
-- message with an empty recipient, that channel is SKIPPED and the row
-- still records why -- `status = 'skipped'`, a human-readable `recipient`
-- placeholder (never an empty string -- `outbox_recipient_not_empty`
-- enforces that at the schema level too), and `last_error` with detail.
-- A queue full of rows that could never be sent is worse than a queue
-- that tells you which contacts are missing.
create function public.enqueue_outbox_message(
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
  v_email     text;
  v_recipient text;
  v_rendered  jsonb;
begin
  select * into v_tpl from public.outbox_templates where name = p_template;
  if not found then
    return;
  end if;

  select * into v_row from public.reservations where id = p_reservation_id;
  select * into v_profile from public.profiles where id = v_row.customer_id;
  select email into v_email from auth.users where id = v_row.customer_id;

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

-- Fires on every reservation status transition and enqueues the SRS
-- messages: `booking_confirmation` and `payment_success` both ride the
-- SAME transition to `confirmed` -- `confirm_booking` both confirms the
-- reservation AND records the advance payment in one atomic call, so
-- there is no separate "payment succeeded" status to key off. Guards
-- against re-firing on every subsequent UPDATE of an already-confirmed/
-- cancelled row (e.g. `touch_updated_at`-driven updates elsewhere), and
-- against blocks/OTA rows and customer-less reservations, which have no
-- one to notify.
--
-- `cancellation` fires ONLY on a `confirmed -> cancelled` transition, not
-- `hold -> cancelled`. An abandoned or expired HOLD was never confirmed to
-- the guest in the first place -- `release_expired_holds` sweeps these
-- every minute via `pg_cron`, and `06_booking_flow_test.sql` cancels
-- still-`hold` reservations directly -- so treating either as "your
-- booking was cancelled" would fire a guest-facing notification for
-- something the guest never knew was a booking. Only a reservation that
-- actually reached `confirmed` has anything to cancel from the guest's
-- perspective.
create function public.enqueue_reservation_outbox()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_name text;
begin
  if new.kind <> 'booking' or new.customer_id is null then
    return new;
  end if;

  if new.status = 'confirmed'
     and (tg_op = 'INSERT' or old.status is distinct from 'confirmed') then
    for v_name in
      select name from public.outbox_templates
      where event = 'booking_confirmation'
    loop
      perform public.enqueue_outbox_message(new.id, v_name);
    end loop;

    for v_name in
      select name from public.outbox_templates where event = 'payment_success'
    loop
      perform public.enqueue_outbox_message(new.id, v_name);
    end loop;
  end if;

  if tg_op = 'UPDATE' and old.status = 'confirmed' and new.status = 'cancelled' then
    for v_name in
      select name from public.outbox_templates where event = 'cancellation'
    loop
      perform public.enqueue_outbox_message(new.id, v_name);
    end loop;
  end if;

  return new;
end;
$$;

create trigger reservations_enqueue_outbox
  after insert or update on public.reservations
  for each row execute function public.enqueue_reservation_outbox();

-- Internal helpers only, invoked from the SECURITY DEFINER functions above
-- (which run as their owner regardless of the calling role). Never meant
-- to be called directly by a client -- same reasoning, and same pattern,
-- as `release_reservation_coupon` in migration 0016.
revoke execute on function public.render_template(text, uuid) from public;
revoke execute on function public.render_template(text, uuid)
  from anon, authenticated;
revoke execute on function public.enqueue_outbox_message(uuid, text)
  from public;
revoke execute on function public.enqueue_outbox_message(uuid, text)
  from anon, authenticated;

-- Seed copy. Every guest-facing event (booking confirmed, cancelled) has
-- email/sms/whatsapp variants, so `enqueue_reservation_outbox` above
-- exercises the deliverable-vs-skipped fork for all three; `payment_success`
-- is treated as an email receipt only, matching how most booking systems
-- treat a payment confirmation versus a booking confirmation.
insert into public.outbox_templates (name, event, channel, subject_template, body_template)
values
  ('booking_confirmation', 'booking_confirmation', 'email',
   'Your stay at {{property_name}} is confirmed',
   'Hi {{guest_name}}, your booking for {{unit_name}} at {{property_name}} '
   'from {{check_in}} to {{check_out}} is confirmed. Total: {{currency}} '
   '{{total}}. We look forward to hosting you.'),
  ('booking_confirmation_sms', 'booking_confirmation', 'sms',
   null,
   'Pasala Resorts: Hi {{guest_name}}, your stay at {{unit_name}} '
   '({{check_in}} - {{check_out}}) is confirmed.'),
  ('booking_confirmation_whatsapp', 'booking_confirmation', 'whatsapp',
   null,
   'Hi {{guest_name}}! Your booking for {{unit_name}} at {{property_name}} '
   '({{check_in}} to {{check_out}}) is confirmed. See you soon!'),
  ('payment_success', 'payment_success', 'email',
   'Payment received -- {{property_name}}',
   'Hi {{guest_name}}, we''ve received your payment of {{currency}} '
   '{{total}} for {{unit_name}} at {{property_name}} ({{check_in}} to '
   '{{check_out}}). Thank you.'),
  ('cancellation', 'cancellation', 'email',
   'Your booking at {{property_name}} has been cancelled',
   'Hi {{guest_name}}, your booking for {{unit_name}} at {{property_name}} '
   '({{check_in}} to {{check_out}}) has been cancelled. Reason: '
   '{{cancel_reason}}.'),
  ('cancellation_sms', 'cancellation', 'sms',
   null,
   'Pasala Resorts: {{guest_name}}, your booking for {{unit_name}} '
   '({{check_in}} - {{check_out}}) has been cancelled.'),
  ('cancellation_whatsapp', 'cancellation', 'whatsapp',
   null,
   'Hi {{guest_name}}, your booking for {{unit_name}} at {{property_name}} '
   '({{check_in}} to {{check_out}}) has been cancelled.');
