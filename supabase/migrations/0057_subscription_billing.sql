-- Subscription auto-billing (P8): Razorpay Subscriptions on top of the
-- manual plans of 0049. The platform admin stores a Razorpay plan id per
-- tier; a resort owner starts, changes or cancels auto-pay through the
-- billing-subscribe Edge Function; the billing-webhook Edge Function hands
-- Razorpay's subscription events to billing_webhook_apply. Without
-- Razorpay secrets nothing here is ever called and plans stay manual.
-- See docs/superpowers/specs/2026-09-25-p8-subscription-auto-billing-design.md.
--
-- Errors: P0038 billing_unavailable (the tier has no Razorpay plan id),
-- P0005 bad input (messages written for the admin, shown verbatim), P0002
-- unknown row, P0008 not the platform admin, P0020 not the resort's owner,
-- P0021 a subscription id at another resort.

-- ---------------------------------------------------------------------
-- The Razorpay plan behind each tier (spec decision 3). Readable like the
-- rest of subscription_plans; written only by set_plan_razorpay_id.
alter table public.subscription_plans
  add column razorpay_plan_id text
    constraint subscription_plans_razorpay_plan_id_format
      check (razorpay_plan_id ~ '^plan_[A-Za-z0-9]{6,40}$');
create unique index subscription_plans_razorpay_plan_id_key
  on public.subscription_plans (razorpay_plan_id);

-- ---------------------------------------------------------------------
-- billing_subscriptions: every Razorpay subscription created for a
-- resort. The row with superseded_at null is the resort's current one
-- (spec decision 5). Read by the resort's owner; written only by the
-- service-role functions below.
create table public.billing_subscriptions (
  id                       uuid primary key default gen_random_uuid(),
  property_id              uuid not null references public.properties(id) on delete cascade,
  tier                     public.subscription_tier not null
                             references public.subscription_plans(tier),
  razorpay_plan_id         text not null,
  razorpay_subscription_id text not null unique
    constraint billing_subscriptions_id_format
      check (razorpay_subscription_id ~ '^sub_[A-Za-z0-9]{6,40}$'),
  -- Razorpay's own lifecycle, stored as sent.
  status                   text not null default 'created'
    constraint billing_subscriptions_status_known
      check (status in ('created','authenticated','active','pending','halted',
                        'cancelled','completed','expired','paused')),
  short_url                text,
  start_at                 timestamptz,
  current_start            timestamptz,
  current_end              timestamptz,
  cancel_at_cycle_end      boolean not null default false,
  superseded_at            timestamptz,
  -- created_at of the newest webhook event applied (spec decision 13).
  last_event_at            timestamptz,
  created_by               uuid,
  created_at               timestamptz not null default now(),
  updated_at               timestamptz not null default now()
);
create index billing_subscriptions_property_idx on public.billing_subscriptions (property_id);
create unique index billing_subscriptions_one_current
  on public.billing_subscriptions (property_id) where superseded_at is null;

alter table public.billing_subscriptions enable row level security;
revoke all on public.billing_subscriptions from anon, authenticated;
grant select on public.billing_subscriptions to authenticated;
create policy billing_subscriptions_read on public.billing_subscriptions
  for select to authenticated
  using (public.has_resort_role(property_id, false, 'owner'));

-- ---------------------------------------------------------------------
-- subscription_invoices: one row per successful Razorpay charge (spec
-- decisions 10 and 18). property_id is filled from, and checked against,
-- the subscription (P0021 on a mismatch).
create table public.subscription_invoices (
  id                      uuid primary key default gen_random_uuid(),
  property_id             uuid not null references public.properties(id) on delete cascade,
  billing_subscription_id uuid not null
                            references public.billing_subscriptions(id) on delete cascade,
  tier                    public.subscription_tier not null,
  razorpay_payment_id     text not null unique,
  razorpay_invoice_id     text,
  amount_inr              numeric(12,2) not null
    constraint subscription_invoices_amount_not_negative check (amount_inr >= 0),
  currency                text not null default 'INR',
  period_start            date,
  period_end              date,
  paid_at                 timestamptz not null,
  created_at              timestamptz not null default now()
);
create index subscription_invoices_property_idx
  on public.subscription_invoices (property_id, paid_at desc);
create index subscription_invoices_subscription_idx
  on public.subscription_invoices (billing_subscription_id);

create trigger subscription_invoices_fill_property
  before insert or update on public.subscription_invoices
  for each row execute function public.fill_property_id('billing_subscriptions', 'billing_subscription_id');

alter table public.subscription_invoices enable row level security;
revoke all on public.subscription_invoices from anon, authenticated;
grant select on public.subscription_invoices to authenticated;
create policy subscription_invoices_read on public.subscription_invoices
  for select to authenticated
  using (public.has_resort_role(property_id, false, 'owner'));

-- ---------------------------------------------------------------------
-- Functions. The signatures are the contract the app and the Edge
-- Functions are built against; Tasks 2-4 of the plan replace the bodies.

-- The platform admin sets or clears (blank) the Razorpay plan behind a
-- tier (spec decision 3). A platform event: the audit row has no
-- property_id.
create function public.set_plan_razorpay_id(
  p_tier    public.subscription_tier,
  p_plan_id text
) returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_old public.subscription_plans;
  v_id  text := nullif(btrim(p_plan_id), '');
begin
  if not public.is_platform_admin() then
    raise exception 'not permitted' using errcode = 'P0008';
  end if;

  if p_tier is null then
    raise exception 'Choose a plan.' using errcode = 'P0005';
  end if;

  if v_id is not null and v_id !~ '^plan_[A-Za-z0-9]{6,40}$' then
    raise exception 'A Razorpay plan id looks like plan_ followed by letters and digits.'
      using errcode = 'P0005';
  end if;

  select * into v_old from public.subscription_plans where tier = p_tier for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'not_found';
  end if;

  if v_old.razorpay_plan_id is not distinct from v_id then
    return;
  end if;

  if v_id is not null and exists (
       select 1 from public.subscription_plans
        where razorpay_plan_id = v_id and tier <> p_tier) then
    raise exception 'That Razorpay plan id is already used by another plan.'
      using errcode = 'P0005';
  end if;

  update public.subscription_plans
     set razorpay_plan_id = v_id,
         updated_at = now()
   where tier = p_tier;

  insert into public.audit_log (actor_id, entity, entity_id, action, before, after, property_id)
  values (auth.uid(), 'subscription_plan', v_old.id,
          'razorpay_plan:' || coalesce(v_old.razorpay_plan_id, 'none') || '->' || coalesce(v_id, 'none'),
          jsonb_build_object('razorpay_plan_id', v_old.razorpay_plan_id),
          jsonb_build_object('razorpay_plan_id', v_id),
          null);
end;
$$;

-- The resort's current auto-pay and its latest payment, for its owner
-- only (spec decision 4). A read, so it works at a suspended resort.
-- Zero rows when the resort never had auto-pay or a payment.
create function public.my_resort_billing(p_property uuid)
returns table(
  billing_status      text,
  billing_tier        public.subscription_tier,
  short_url           text,
  cancel_at_cycle_end boolean,
  current_end         timestamptz,
  last_payment_at     timestamptz,
  last_payment_inr    numeric
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  perform public.assert_resort_role(p_property, false, 'owner');

  return query
    select b.status, b.tier, b.short_url, coalesce(b.cancel_at_cycle_end, false),
           b.current_end, i.paid_at, i.amount_inr
      from (select 1) as one
      left join public.billing_subscriptions b
        on b.property_id = p_property and b.superseded_at is null
      left join lateral (
        select si.paid_at, si.amount_inr
          from public.subscription_invoices si
         where si.property_id = p_property
         order by si.paid_at desc
         limit 1
      ) i on true
     where b.id is not null or i.paid_at is not null;
end;
$$;

-- The console's billing column (spec decision 16): per resort, the
-- current auto-pay state and the latest payment. Only resorts that ever
-- had auto-pay or a payment.
create function public.platform_billing()
returns table(
  property_id      uuid,
  billing_status   text,
  billing_tier     public.subscription_tier,
  last_payment_at  timestamptz,
  last_payment_inr numeric
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  if not public.is_platform_admin() then
    raise exception 'not permitted' using errcode = 'P0008';
  end if;

  return query
    select p.id, b.status, b.tier, i.paid_at, i.amount_inr
      from public.properties p
      left join public.billing_subscriptions b
        on b.property_id = p.id and b.superseded_at is null
      left join lateral (
        select si.paid_at, si.amount_inr
          from public.subscription_invoices si
         where si.property_id = p.id
         order by si.paid_at desc
         limit 1
      ) i on true
     where b.id is not null or i.paid_at is not null
     order by p.created_at, p.name;
end;
$$;

-- Everything billing-subscribe needs to decide, read as the owner (spec
-- decisions 4, 6, 8 and 14). Read mode, so a suspended resort's owner can
-- still pay. With a tier that has no Razorpay plan: P0038. start_at is
-- midnight Asia/Kolkata after the trial or paid period, when that period
-- has not ended yet; otherwise null (start now).
create function public.billing_subscribe_state(
  p_property uuid,
  p_tier     public.subscription_tier default null
) returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_name    text;
  v_plan_id text;
  v_sub     public.resort_subscriptions;
  v_cur     public.billing_subscriptions;
  v_today   date := (now() at time zone 'Asia/Kolkata')::date;
  v_end     date;
  v_start   timestamptz;
begin
  perform public.assert_resort_role(p_property, false, 'owner');

  select name into v_name from public.properties where id = p_property;

  if p_tier is not null then
    select razorpay_plan_id into v_plan_id
      from public.subscription_plans where tier = p_tier;
    if v_plan_id is null then
      raise exception using errcode = 'P0038', message = 'billing_unavailable';
    end if;
  end if;

  select * into v_sub from public.resort_subscriptions where property_id = p_property;
  v_end := case v_sub.status
             when 'trial' then v_sub.trial_ends_on
             when 'active' then v_sub.paid_through
           end;
  if v_end is not null and v_end >= v_today then
    v_start := (v_end + 1)::timestamp at time zone 'Asia/Kolkata';
  end if;

  select * into v_cur from public.billing_subscriptions
   where property_id = p_property and superseded_at is null;

  return jsonb_build_object(
    'property_id', p_property,
    'property_name', v_name,
    'caller_id', auth.uid(),
    'notify_email', (select u.email::text from auth.users u where u.id = auth.uid()),
    'tier', p_tier,
    'plan_id', v_plan_id,
    'start_at', case when v_start is null then null
                     else extract(epoch from v_start)::bigint end,
    'current', case when v_cur.id is null then null else jsonb_build_object(
        'razorpay_subscription_id', v_cur.razorpay_subscription_id,
        'tier', v_cur.tier,
        'status', v_cur.status,
        'short_url', v_cur.short_url,
        'cancel_at_cycle_end', v_cur.cancel_at_cycle_end) end,
    'stale', coalesce((
        select jsonb_agg(b.razorpay_subscription_id order by b.created_at)
          from public.billing_subscriptions b
         where b.property_id = p_property
           and b.superseded_at is not null
           and b.status in ('created','authenticated','active','pending','paused')),
      '[]'::jsonb));
end;
$$;

-- billing-subscribe records a subscription it just created in Razorpay
-- (spec decisions 5, 7 and 14). The resort's current row is superseded and
-- the new one becomes current, one opening at a time per resort. Returns
-- the row id and every replaced subscription still live, which the caller
-- cancels in Razorpay. Recording a known id again changes nothing.
create function public.billing_subscription_opened(
  p_property                 uuid,
  p_tier                     public.subscription_tier,
  p_razorpay_plan_id         text,
  p_razorpay_subscription_id text,
  p_status                   text,
  p_short_url                text,
  p_start_at                 timestamptz,
  p_created_by               uuid
) returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_row public.billing_subscriptions;
begin
  if p_property is null or p_tier is null
     or coalesce(btrim(p_razorpay_plan_id), '') = ''
     or coalesce(btrim(p_razorpay_subscription_id), '') = '' then
    raise exception 'A resort, a tier, a plan and a subscription are required.'
      using errcode = 'P0005';
  end if;

  perform 1 from public.properties where id = p_property;
  if not found then
    raise exception using errcode = 'P0002', message = 'not_found';
  end if;

  -- Two taps at once apply one after the other, so a resort never ends up
  -- with two current rows.
  perform pg_advisory_xact_lock(hashtextextended('billing_subscriptions:' || p_property::text, 0));

  select * into v_row from public.billing_subscriptions
   where razorpay_subscription_id = p_razorpay_subscription_id;

  if found then
    if v_row.property_id <> p_property then
      raise exception using errcode = 'P0021', message = 'resort_mismatch';
    end if;
  else
    update public.billing_subscriptions
       set superseded_at = now(),
           updated_at = now()
     where property_id = p_property and superseded_at is null;

    insert into public.billing_subscriptions
      (property_id, tier, razorpay_plan_id, razorpay_subscription_id, status,
       short_url, start_at, created_by)
    values
      (p_property, p_tier, btrim(p_razorpay_plan_id), btrim(p_razorpay_subscription_id),
       coalesce(p_status, 'created'), p_short_url, p_start_at, p_created_by)
    returning * into v_row;

    insert into public.audit_log (actor_id, entity, entity_id, action, before, after, property_id)
    values (p_created_by, 'subscription', p_property,
            'billing:opened ' || v_row.razorpay_subscription_id || ' ' || p_tier::text,
            null, to_jsonb(v_row), p_property);
  end if;

  return jsonb_build_object(
    'id', v_row.id,
    'stale', coalesce((
        select jsonb_agg(b.razorpay_subscription_id order by b.created_at)
          from public.billing_subscriptions b
         where b.property_id = p_property
           and b.superseded_at is not null
           and b.status in ('created','authenticated','active','pending','paused')),
      '[]'::jsonb));
end;
$$;

-- billing-subscribe (the owner's cancel, or cleaning up a replaced
-- subscription) or billing-webhook records a cancellation Razorpay
-- accepted (spec decisions 9 and 14). The plan itself changes only when
-- Razorpay's subscription.cancelled arrives (billing_webhook_apply).
create function public.billing_subscription_cancel_requested(
  p_razorpay_subscription_id text,
  p_at_cycle_end             boolean,
  p_status                   text,
  p_actor                    uuid default null
) returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_old public.billing_subscriptions;
  v_new public.billing_subscriptions;
begin
  select * into v_old from public.billing_subscriptions
   where razorpay_subscription_id = p_razorpay_subscription_id
   for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'not_found';
  end if;

  update public.billing_subscriptions b
     set cancel_at_cycle_end = coalesce(p_at_cycle_end, false),
         status = case
                    when p_status in ('created','authenticated','active','pending','halted',
                                      'cancelled','completed','expired','paused')
                      then p_status
                    else b.status
                  end,
         updated_at = now()
   where b.id = v_old.id
  returning * into v_new;

  insert into public.audit_log (actor_id, entity, entity_id, action, before, after, property_id)
  values (p_actor, 'subscription', v_new.property_id,
          'billing:cancel_requested ' || p_razorpay_subscription_id,
          to_jsonb(v_old), to_jsonb(v_new), v_new.property_id);
end;
$$;

create function public.billing_webhook_apply(
  p_event        text,
  p_event_at     timestamptz,
  p_subscription jsonb,
  p_payment      jsonb
) returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  raise exception 'billing_webhook_apply is not implemented yet' using errcode = '0A000';
end;
$$;

-- Client-callable: the reads and the platform admin's plan id.
revoke execute on function public.set_plan_razorpay_id(public.subscription_tier, text) from public, anon;
revoke execute on function public.my_resort_billing(uuid) from public, anon;
revoke execute on function public.platform_billing() from public, anon;
revoke execute on function public.billing_subscribe_state(uuid, public.subscription_tier) from public, anon;
grant execute on function public.set_plan_razorpay_id(public.subscription_tier, text) to authenticated;
grant execute on function public.my_resort_billing(uuid) to authenticated;
grant execute on function public.platform_billing() to authenticated;
grant execute on function public.billing_subscribe_state(uuid, public.subscription_tier) to authenticated;

-- Service role only: the Edge Functions record what Razorpay did.
revoke execute on function public.billing_subscription_opened(uuid, public.subscription_tier, text, text, text, text, timestamptz, uuid) from public, anon, authenticated;
revoke execute on function public.billing_subscription_cancel_requested(text, boolean, text, uuid) from public, anon, authenticated;
revoke execute on function public.billing_webhook_apply(text, timestamptz, jsonb, jsonb) from public, anon, authenticated;
grant execute on function public.billing_subscription_opened(uuid, public.subscription_tier, text, text, text, text, timestamptz, uuid) to service_role;
grant execute on function public.billing_subscription_cancel_requested(text, boolean, text, uuid) to service_role;
grant execute on function public.billing_webhook_apply(text, timestamptz, jsonb, jsonb) to service_role;
