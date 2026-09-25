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

create function public.set_plan_razorpay_id(
  p_tier    public.subscription_tier,
  p_plan_id text
) returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  raise exception 'set_plan_razorpay_id is not implemented yet' using errcode = '0A000';
end;
$$;

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
  raise exception 'my_resort_billing is not implemented yet' using errcode = '0A000';
end;
$$;

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
  raise exception 'platform_billing is not implemented yet' using errcode = '0A000';
end;
$$;

create function public.billing_subscribe_state(
  p_property uuid,
  p_tier     public.subscription_tier default null
) returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  raise exception 'billing_subscribe_state is not implemented yet' using errcode = '0A000';
end;
$$;

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
begin
  raise exception 'billing_subscription_opened is not implemented yet' using errcode = '0A000';
end;
$$;

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
begin
  raise exception 'billing_subscription_cancel_requested is not implemented yet' using errcode = '0A000';
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
