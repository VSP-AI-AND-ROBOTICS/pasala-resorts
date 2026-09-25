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
declare
  v_uid      uuid := auth.uid();
  v_row      public.reservations;
  v_property public.properties;
  v_profile  public.profiles;
  v_email    text;
  v_total    numeric;
  v_min      numeric;
  v_balance  numeric;
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode = 'P0008';
  end if;

  select * into v_row from public.reservations where id = p_reservation;
  if not found then
    raise exception 'reservation not found' using errcode = 'P0002';
  end if;

  -- Only the guest pays online for their own booking (spec decision 14).
  if v_row.customer_id is distinct from v_uid then
    raise exception 'only the booking''s guest can pay online' using errcode = 'P0008';
  end if;

  if p_amount is null or p_amount <= 0 or p_amount <> round(p_amount, 2) then
    raise exception 'payment amount % is not valid', p_amount using errcode = 'P0009';
  end if;

  select * into v_property from public.properties where id = v_row.property_id;

  if p_kind = 'advance' then
    -- The same checks, in the same order, as confirm_booking (0045).
    if v_property.status is distinct from 'active' then
      raise exception using errcode = 'P0022', message = 'resort_suspended';
    end if;
    if v_row.status <> 'hold' then
      raise exception 'reservation is %', v_row.status using errcode = 'P0009';
    end if;
    if v_row.hold_expires_at < now() then
      raise exception 'hold expired' using errcode = 'P0006';
    end if;
    if v_row.quote is null then
      raise exception 'reservation has no quote' using errcode = 'P0009';
    end if;
    v_total := (v_row.quote ->> 'total')::numeric;
    v_min   := round(v_total * coalesce(v_property.advance_pct, 100) / 100, 2);
    if p_amount < v_min or p_amount > v_total then
      raise exception 'payment amount % is outside the accepted range % to %',
        p_amount, v_min, v_total
        using errcode = 'P0009';
    end if;
  elsif p_kind = 'balance' then
    -- The same rule as checkout_booking (0048): exactly what is due.
    if v_row.status <> 'checked_in' then
      raise exception 'reservation is %', v_row.status using errcode = 'P0009';
    end if;
    v_balance := (public.current_charges(p_reservation) ->> 'balance')::numeric;
    if p_amount is distinct from v_balance then
      raise exception 'payment amount % does not match balance due %', p_amount, v_balance
        using errcode = 'P0009';
    end if;
  else
    raise exception 'unknown payment kind' using errcode = 'P0009';
  end if;

  select * into v_profile from public.profiles where id = v_uid;
  select email into v_email from auth.users where id = v_uid;

  return jsonb_build_object(
    'reservation_id', v_row.id,
    'property_id',    v_row.property_id,
    'property_name',  v_property.name,
    'customer_id',    v_uid,
    'kind',           p_kind,
    'amount',         round(p_amount, 2),
    'amount_paise',   (round(p_amount, 2) * 100)::bigint,
    'currency',       'INR',
    'receipt',        v_row.id::text,
    'description',    v_property.name || case p_kind
                        when 'advance' then ': booking advance'
                        else ': stay balance' end,
    'prefill',        jsonb_build_object(
                        'name',    v_profile.full_name,
                        'email',   v_email,
                        'contact', v_profile.phone)
  );
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
declare
  v_row   public.reservations;
  v_order public.payment_orders;
begin
  if p_razorpay_order_id is null or btrim(p_razorpay_order_id) = '' then
    raise exception 'a Razorpay order id is required' using errcode = 'P0009';
  end if;
  if p_amount is null or p_amount <= 0 then
    raise exception 'payment amount % is not valid', p_amount using errcode = 'P0009';
  end if;

  select * into v_row from public.reservations where id = p_reservation;
  if not found then
    raise exception 'reservation not found' using errcode = 'P0002';
  end if;

  -- payments-create-order quoted as this guest a moment ago; check again.
  if p_customer is null or v_row.customer_id is distinct from p_customer then
    raise exception 'only the booking''s guest can pay online' using errcode = 'P0008';
  end if;

  if p_kind is null
     or (p_kind = 'advance' and v_row.status <> 'hold')
     or (p_kind = 'balance' and v_row.status <> 'checked_in') then
    raise exception 'reservation is %', v_row.status using errcode = 'P0009';
  end if;

  -- The hold is not extended (spec decision 9). property_id comes from
  -- the reservation (payment_orders_fill_property).
  insert into public.payment_orders
    (reservation_id, customer_id, kind, amount, razorpay_order_id)
  values (p_reservation, p_customer, p_kind, p_amount, btrim(p_razorpay_order_id))
  returning * into v_order;

  return v_order;
end;
$$;
revoke execute on function public.payment_order_open(uuid, uuid, public.payment_kind, numeric, text) from public, anon, authenticated;
grant execute on function public.payment_order_open(uuid, uuid, public.payment_kind, numeric, text) to service_role;

-- What settle returns; one place, so the idempotent and the first answer
-- have the same shape. Internal (no client grants).
create function public.payment_order_json(p_order public.payment_orders)
returns jsonb
language sql
immutable
set search_path = public, pg_temp
as $$
  select jsonb_build_object(
    'order_id',            p_order.id,
    'reservation_id',      p_order.reservation_id,
    'kind',                p_order.kind,
    'amount',              p_order.amount,
    'status',              p_order.status,
    'razorpay_payment_id', p_order.razorpay_payment_id,
    'reason',              p_order.failure_reason,
    'refund_needed',       p_order.status = 'unapplied' and cardinality(p_order.refund_ids) = 0
  );
$$;
revoke execute on function public.payment_order_json(public.payment_orders) from public, anon, authenticated;

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
declare
  v_order       public.payment_orders;
  v_res         public.reservations;
  v_payment     uuid;
  v_reason      text;
  v_prev_claims text := current_setting('request.jwt.claims', true);
  v_prev_sub    text := current_setting('request.jwt.claim.sub', true);
  v_prev_gw     text := current_setting('app.payment_gateway', true);
begin
  if p_razorpay_payment_id is null or btrim(p_razorpay_payment_id) = '' then
    raise exception 'a Razorpay payment id is required' using errcode = 'P0009';
  end if;

  select * into v_order from public.payment_orders
   where razorpay_order_id = p_razorpay_order_id
   for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'payment_order_not_found';
  end if;

  -- payments-verify and payments-webhook both land here for one payment:
  -- an order that is already settled is reported, never applied twice.
  if v_order.status in ('paid', 'unapplied', 'refunded') then
    return public.payment_order_json(v_order);
  end if;

  select * into v_res from public.reservations
   where id = v_order.reservation_id
   for update;

  -- Captured before release_expired_holds swept the hold: the dates are
  -- still held for this guest, so the payment wins (spec decision 9).
  if v_order.kind = 'advance' and v_res.status = 'hold' and v_res.hold_expires_at < now() then
    update public.reservations
       set hold_expires_at = now() + interval '1 minute'
     where id = v_res.id;
  end if;

  if (v_order.kind = 'advance' and v_res.status <> 'hold')
     or (v_order.kind = 'balance' and v_res.status <> 'checked_in') then
    v_reason := format('reservation is %s', v_res.status);
  else
    begin
      -- Act as the order's guest for the rest of this transaction, so the
      -- existing functions run their guest path unchanged (spec decision 7).
      perform set_config('request.jwt.claim.sub', v_order.customer_id::text, true);
      perform set_config('request.jwt.claims',
        json_build_object('sub', v_order.customer_id, 'role', 'authenticated')::text, true);
      perform set_config('app.payment_gateway', 'razorpay', true);

      if v_order.kind = 'advance' then
        perform public.confirm_booking(v_order.reservation_id, btrim(p_razorpay_payment_id), v_order.amount);
      else
        perform public.checkout_booking(v_order.reservation_id, btrim(p_razorpay_payment_id), v_order.amount, 'gateway');
      end if;

      select id into v_payment from public.payments
       where gateway = 'razorpay' and gateway_ref = btrim(p_razorpay_payment_id);
    exception when others then
      -- Money was taken but cannot be applied: unapplied, refunded by the
      -- caller (spec decision 10). The block's own settings roll back.
      v_reason  := sqlerrm;
      v_payment := null;
    end;
  end if;

  perform set_config('request.jwt.claim.sub', coalesce(v_prev_sub, ''), true);
  perform set_config('request.jwt.claims', coalesce(v_prev_claims, ''), true);
  perform set_config('app.payment_gateway', coalesce(v_prev_gw, ''), true);

  update public.payment_orders
     set status              = case when v_payment is null then 'unapplied' else 'paid' end
                                 ::public.payment_order_status,
         razorpay_payment_id = btrim(p_razorpay_payment_id),
         payment_id          = v_payment,
         failure_reason      = left(v_reason, 500),
         updated_at          = now()
   where id = v_order.id
  returning * into v_order;

  return public.payment_order_json(v_order);
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
declare
  v_live   boolean := coalesce(p_live, false);
  v_key_id text    := case when coalesce(p_live, false) then nullif(btrim(p_key_id), '') end;
begin
  -- Called on every payments-create-order request: write only on change.
  update public.payment_gateway_config
     set live = v_live, key_id = v_key_id, updated_at = now()
   where id
     and (live is distinct from v_live or key_id is distinct from v_key_id);
end;
$$;
revoke execute on function public.payments_set_live(boolean, text) from public, anon, authenticated;
grant execute on function public.payments_set_live(boolean, text) to service_role;

-- ---------------------------------------------------------------------
-- The gateway label and the live switch. A payment is labelled
-- `razorpay` only when payment_order_settle calls in (it sets
-- app.payment_gateway) AND the session role is service_role, so a client
-- that managed to set the setting still gets `mock`. While online
-- payments are live, the guest's own mock payment raises P0036
-- (spec decisions 5 and 7).
--
-- confirm_booking: copied from its latest definition,
-- 0045_resort_functions.sql; the changes are marked 0055.
create or replace function public.confirm_booking(
  p_reservation_id uuid,
  p_payment_ref    text,
  p_amount         numeric
) returns public.reservations
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid         uuid := auth.uid();
  v_row         public.reservations;
  v_total       numeric;
  v_advance_pct numeric;
  v_min         numeric;
  v_gateway     text := case                                        -- 0055
                          when current_setting('app.payment_gateway', true) = 'razorpay'
                           and current_setting('role', true) = 'service_role'
                          then 'razorpay' else 'mock' end;
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode = 'P0008';
  end if;

  select * into v_row from public.reservations
  where id = p_reservation_id for update;

  if not found then
    raise exception 'reservation not found' using errcode = 'P0002';
  end if;

  if v_row.customer_id is distinct from v_uid then
    perform public.assert_resort_role(v_row.property_id, true, 'owner','admin');
  end if;

  -- Before the resort-status check: a retried webhook for a booking that
  -- was already paid must get the row back even if the resort has since
  -- been suspended.
  if v_row.status = 'confirmed' then
    return v_row;   -- idempotent: a retried webhook must not double-charge
  end if;

  if not exists (select 1 from public.properties
                  where id = v_row.property_id and status = 'active') then
    raise exception using errcode = 'P0022', message = 'resort_suspended';
  end if;

  if v_row.status <> 'hold' then
    raise exception 'reservation is %', v_row.status using errcode = 'P0009';
  end if;

  if v_row.hold_expires_at < now() then
    raise exception 'hold expired' using errcode = 'P0006';
  end if;

  -- A NULL `p_amount` or NULL `quote` must hit this raise (see 0014).
  if p_amount is null or v_row.quote is null then
    raise exception 'payment amount % does not match quoted total %',
      p_amount, (v_row.quote ->> 'total')
      using errcode = 'P0009';
  end if;

  v_total := (v_row.quote ->> 'total')::numeric;

  select coalesce(p.advance_pct, 100) into v_advance_pct
  from public.properties p
  where p.id = v_row.property_id;

  v_min := round(v_total * coalesce(v_advance_pct, 100) / 100, 2);

  if p_amount < v_min or p_amount > v_total then
    raise exception
      'payment amount % is outside the accepted range % to %',
      p_amount, v_min, v_total
      using errcode = 'P0009';
  end if;

  -- 0055: once online payments are live, the guest's own confirmation
  -- comes only through payment_order_settle. An owner/admin confirming a
  -- hold (an offline payment) is unaffected.
  if v_gateway = 'mock' and v_row.customer_id = v_uid and public.online_payments_live() then
    raise exception using errcode = 'P0036', message = 'online_payment_required';
  end if;

  insert into public.payments
    (reservation_id, amount, kind, status, gateway, gateway_ref)
  values (p_reservation_id, p_amount, 'advance', 'succeeded', v_gateway,   -- 0055
          p_payment_ref);

  update public.reservations
     set status = 'confirmed', hold_expires_at = null
   where id = p_reservation_id
  returning * into v_row;

  return v_row;
end;
$$;

-- checkout_booking: copied from its latest definition,
-- 0048_finance_ledger.sql; the changes are marked 0055.
create or replace function public.checkout_booking(
  p_reservation_id uuid,
  p_payment_ref    text,
  p_amount         numeric,
  p_method         public.payment_method default 'gateway'
) returns public.reservations
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid     uuid := auth.uid();
  v_row     public.reservations;
  v_charges jsonb;
  v_balance numeric(12,2);
  v_method  public.payment_method := coalesce(p_method, 'gateway');   -- 0048
  v_gateway text := case                                                -- 0055
                      when current_setting('app.payment_gateway', true) = 'razorpay'
                       and current_setting('role', true) = 'service_role'
                      then 'razorpay' else 'mock' end;
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode = 'P0008';
  end if;

  select * into v_row from public.reservations
  where id = p_reservation_id for update;

  if not found then
    raise exception 'reservation not found' using errcode = 'P0002';
  end if;

  if v_row.customer_id is distinct from v_uid then
    perform public.assert_resort_role(v_row.property_id, true, 'owner','admin','staff','accountant');
  end if;

  -- 0048: only resort staff record a desk method, and only at the
  -- booking's own resort. A guest's own checkout (the branch above
  -- skipped) can only be gateway; a staff member checking out their own
  -- stay passes this check. Before the early return, so a guest never
  -- gets a desk method accepted, even as a no-op.
  if v_method <> 'gateway'
     and not public.has_resort_role(v_row.property_id, true,
                                    'owner','admin','staff','accountant') then
    raise exception 'desk payment methods are recorded by resort staff'
      using errcode = 'P0009';
  end if;

  if v_row.status = 'checked_out' then
    return v_row;   -- idempotent: a retried checkout must not double-charge
  end if;

  if v_row.status <> 'checked_in' then
    raise exception 'reservation is %', v_row.status using errcode = 'P0009';
  end if;

  v_charges := public.current_charges(p_reservation_id);
  v_balance := (v_charges ->> 'balance')::numeric;

  if v_balance > 0 and (p_amount is null or p_amount is distinct from v_balance) then
    raise exception 'payment amount % does not match balance due %',
      p_amount, v_balance
      using errcode = 'P0009';
  end if;

  if v_balance > 0 then
    if v_method = 'gateway' then
      -- 0055: see confirm_booking.
      if v_gateway = 'mock' and v_row.customer_id = v_uid and public.online_payments_live() then
        raise exception using errcode = 'P0036', message = 'online_payment_required';
      end if;
      insert into public.payments
        (reservation_id, amount, kind, status, gateway, gateway_ref, method, recorded_by)
      values (p_reservation_id, v_balance, 'balance', 'succeeded', v_gateway, p_payment_ref,   -- 0055
              'gateway', v_uid);
    else
      -- 0048: one balance payment per booking, so 'desk-<id>' stays unique
      -- under unique (gateway, gateway_ref) and doubles as a retry guard.
      -- The receipt/UTR number goes in `reference`, which is not unique.
      insert into public.payments
        (reservation_id, amount, kind, status, gateway, gateway_ref, method, reference, recorded_by)
      values (p_reservation_id, v_balance, 'balance', 'succeeded', 'desk',
              'desk-' || p_reservation_id, v_method,
              nullif(btrim(p_payment_ref), ''), v_uid);
    end if;
  end if;

  update public.reservations
     set status = 'checked_out', checked_out_at = clock_timestamp()
   where id = p_reservation_id
  returning * into v_row;

  -- 0047: the room needs cleaning now.
  insert into public.unit_room_status as s
    (unit_id, property_id, state, reason, updated_by, updated_at)
  values (v_row.unit_id, v_row.property_id, 'dirty', null, v_uid, now())
  on conflict (unit_id) do update
    set state      = 'dirty',
        reason     = null,
        updated_by = excluded.updated_by,
        updated_at = excluded.updated_at
    where s.state <> 'out_of_order';

  return v_row;
end;
$$;
