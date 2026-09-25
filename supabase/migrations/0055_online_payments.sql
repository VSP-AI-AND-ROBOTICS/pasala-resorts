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
