-- ResortHub tenancy, part 3: every `security definer` function checks the
-- caller's role at the resort the data belongs to.
-- See docs/superpowers/specs/2026-09-24-resorthub-tenancy-design.md.
--
-- Each function below is its latest definition copied forward, with the old
-- global role check (`is_admin()` and friends) replaced by a check at the
-- row's resort. Error codes: P0020 not_a_member, P0022 resort_suspended.

-- ---------------------------------------------------------------------
-- Booking, quote, coupon and refund functions.
--
-- `release_expired_holds()` (cron only) and `release_reservation_coupon()`
-- (internal helper) are not redefined: neither is callable by a client and
-- neither needs a resort check.

-- Guest browse: a resort that is not `active` offers nothing, whether it
-- is asked for by id or found through an unfiltered search.
create or replace function public.search_availability(
  p_property_id  uuid,
  p_from         date,
  p_to           date,
  p_guests       int default 1,
  p_slot_type_id uuid default null
) returns table (
  unit_id      uuid,
  property_id  uuid,
  unit_name    text,
  booking_mode public.booking_mode,
  is_available boolean,
  busy_periods tstzrange[]
)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select
    u.id,
    u.property_id,
    u.name,
    u.booking_mode,
    not exists (
      select 1 from public.reservations r
      where r.unit_id = u.id
        and r.status <> 'cancelled'
        and r.period && public.build_period(u.id, p_from, p_to, p_slot_type_id)
    ),
    coalesce((
      select array_agg(r.period order by lower(r.period))
      from public.reservations r
      where r.unit_id = u.id
        and r.status <> 'cancelled'
        and r.period && tstzrange(
              (p_from - 1)::timestamptz, (p_to + 1)::timestamptz, '[)')
    ), '{}')
  from public.units u
  join public.properties p on p.id = u.property_id
  where u.is_active
    and p.is_active
    and p.status = 'active'
    and (p_property_id is null or u.property_id = p_property_id)
    and u.capacity_max >= p_guests
  order by u.name;
$$;

-- Coupons belong to one resort. A code from another resort resolves exactly
-- like an unknown code (P0010), so it reveals nothing about other resorts.
drop function if exists public.resolve_coupon(text, uuid, numeric);

create function public.resolve_coupon(
  p_property_id uuid,
  p_code        text,
  p_uid         uuid,
  p_amount      numeric
) returns public.coupons
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_coupon public.coupons;
begin
  select * into v_coupon
  from public.coupons c
  where c.code = p_code
    and c.property_id = p_property_id
    and c.is_active
    -- A coupon restricted to another customer must look exactly like it
    -- doesn't exist -- P0010, not a different code.
    and (c.customer_id is null or c.customer_id = p_uid);

  if not found then
    raise exception 'coupon not found or inactive' using errcode = 'P0010';
  end if;

  if (v_coupon.valid_from is not null and now() < v_coupon.valid_from)
     or (v_coupon.valid_to is not null and now() > v_coupon.valid_to) then
    raise exception 'coupon % has expired', p_code using errcode = 'P0011';
  end if;

  if v_coupon.max_redemptions is not null
     and v_coupon.redeemed_count >= v_coupon.max_redemptions then
    raise exception 'coupon % has reached its usage limit', p_code
      using errcode = 'P0012';
  end if;

  if v_coupon.min_booking_value is not null
     and p_amount < v_coupon.min_booking_value then
    raise exception
      'this booking is below the minimum of % for coupon %',
      v_coupon.min_booking_value, p_code
      using errcode = 'P0013';
  end if;

  return v_coupon;
end;
$$;

-- Internal helper for get_quote/create_hold only (see 0012).
revoke execute on function public.resolve_coupon(uuid, text, uuid, numeric)
  from public;
revoke execute on function public.resolve_coupon(uuid, text, uuid, numeric)
  from anon, authenticated;

-- Quotes are refused at a resort that is not `active`.
create or replace function public.get_quote(
  p_unit_id      uuid,
  p_period       tstzrange,
  p_guests       int,
  p_slot_type_id uuid default null,
  p_coupon_code  text default null
) returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_unit        public.units;
  v_tz          text;
  v_status      text;
  v_tax_pct     numeric(5,2);
  v_min_nights  int;
  v_max_nights  int;
  v_rule        public.rate_rules;
  v_date        date;
  v_end_date    date;
  v_nights      int;
  v_lines       jsonb := '[]'::jsonb;
  v_subtotal    numeric(12,2) := 0;
  v_cleaning    numeric(12,2) := 0;
  v_extra       int;
  v_extra_amt   numeric(12,2);
  v_coupon      public.coupons;
  v_discount    numeric(12,2) := 0;
  v_taxable     numeric(12,2);
  v_tax_amount  numeric(12,2);
begin
  select * into v_unit from public.units where id = p_unit_id and is_active;
  if not found then
    raise exception 'unit not found or inactive' using errcode = 'P0002';
  end if;

  select p.timezone, p.status, p.tax_pct, p.min_nights, p.max_nights
  into v_tz, v_status, v_tax_pct, v_min_nights, v_max_nights
  from public.properties p where p.id = v_unit.property_id;

  if v_status is distinct from 'active' then
    raise exception using errcode = 'P0022', message = 'resort_suspended';
  end if;

  if p_guests is null or p_guests < 1 or p_guests > v_unit.capacity_max then
    raise exception 'guest count out of range (max %)', v_unit.capacity_max
      using errcode = 'P0003';
  end if;

  v_extra := greatest(p_guests - v_unit.capacity_base, 0);

  -- One line per calendar night (nightly) or per slot day (slot bookings).
  v_date     := (lower(p_period) at time zone v_tz)::date;
  v_end_date := (upper(p_period) at time zone v_tz)::date;
  v_nights   := v_end_date - v_date;
  if p_slot_type_id is not null then
    v_end_date := v_date + 1;   -- a slot occupies exactly one dated line
  end if;

  if p_slot_type_id is null and v_nights > 0 then
    if v_min_nights is not null and v_nights < v_min_nights then
      raise exception 'this unit requires a minimum stay of % nights', v_min_nights
        using errcode = 'P0015';
    end if;
    if v_max_nights is not null and v_nights > v_max_nights then
      raise exception 'this unit allows a maximum stay of % nights', v_max_nights
        using errcode = 'P0015';
    end if;
  end if;

  while v_date < v_end_date loop
    v_rule := public.resolve_rate_rule(p_unit_id, v_date, p_slot_type_id);
    if v_rule.id is null then
      raise exception 'no rate rule for unit % on %', p_unit_id, v_date
        using errcode = 'P0004';
    end if;

    v_extra_amt := v_extra * v_rule.extra_guest_price;
    v_subtotal  := v_subtotal + v_rule.price + v_extra_amt;
    v_cleaning  := greatest(v_cleaning, v_rule.cleaning_fee);

    v_lines := v_lines || jsonb_build_object(
      'date',               to_char(v_date, 'YYYY-MM-DD'),
      'label',              coalesce(v_rule.label, initcap(v_rule.kind::text) || ' rate'),
      'amount',             v_rule.price,
      'rate_rule_id',       v_rule.id,
      'extra_guests',       v_extra,
      'extra_guest_amount', v_extra_amt
    );

    v_date := v_date + 1;
  end loop;

  if jsonb_array_length(v_lines) = 0 then
    raise exception 'period covers no nights' using errcode = 'P0005';
  end if;

  if p_coupon_code is not null then
    v_coupon := public.resolve_coupon(v_unit.property_id, p_coupon_code,
                                       auth.uid(), v_subtotal + v_cleaning);
    v_discount := case v_coupon.kind
      when 'percent' then round((v_subtotal + v_cleaning) * v_coupon.value / 100, 2)
      when 'fixed'   then round(v_coupon.value, 2)
    end;
    -- Never let a coupon drive the total below zero, regardless of how
    -- `value` is configured.
    v_discount := least(v_discount, v_subtotal + v_cleaning);
  end if;

  v_taxable    := v_subtotal + v_cleaning - v_discount;
  v_tax_amount := round(v_taxable * coalesce(v_tax_pct, 0) / 100, 2);

  return jsonb_build_object(
    'unit_id',      p_unit_id,
    'currency',     'INR',
    'guests',       p_guests,
    'lines',        v_lines,
    'subtotal',     v_subtotal,
    'cleaning_fee', v_cleaning,
    'coupon',       case when v_coupon.id is not null
                      then jsonb_build_object(
                        'code',     v_coupon.code,
                        'kind',     v_coupon.kind,
                        'value',    v_coupon.value,
                        'discount', v_discount)
                      else null end,
    'tax_pct',      coalesce(v_tax_pct, 0),
    'tax_amount',   v_tax_amount,
    'total',        v_taxable + v_tax_amount
  );
end;
$$;

-- New holds are refused at a resort that is not `active`, and a coupon is
-- redeemed only at the resort it belongs to.
create or replace function public.create_hold(
  p_unit_id        uuid,
  p_from           date,
  p_to             date,
  p_guests         int,
  p_slot_type_id   uuid default null,
  p_expected_total numeric default null,
  p_coupon_code    text default null,
  p_occasion       text default null
) returns public.reservations
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid       uuid := auth.uid();
  v_mode      public.booking_mode;
  v_property  uuid;
  v_period    tstzrange;
  v_quote     jsonb;
  v_row       public.reservations;
  v_coupon_id uuid;
  v_discount  numeric(12,2);
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode = 'P0008';
  end if;

  -- If the unit doesn't exist `v_mode`/`v_property` stay NULL, so neither
  -- check below fires and `build_period`'s own "unit not found" raise does.
  select booking_mode, property_id into v_mode, v_property
  from public.units where id = p_unit_id;

  if v_property is not null and not exists (
    select 1 from public.properties where id = v_property and status = 'active'
  ) then
    raise exception using errcode = 'P0022', message = 'resort_suspended';
  end if;

  -- I3: `booking_mode` enforced in SQL, not just in the client (see 0007).
  if v_mode = 'nightly' and p_slot_type_id is not null then
    raise exception 'this unit does not support slot bookings'
      using errcode = 'P0003';
  end if;
  if v_mode = 'slot' and p_slot_type_id is null then
    raise exception 'this unit requires a slot type' using errcode = 'P0003';
  end if;

  v_period := public.build_period(p_unit_id, p_from, p_to, p_slot_type_id);
  v_quote  := public.get_quote(p_unit_id, v_period, p_guests, p_slot_type_id,
                                p_coupon_code);

  -- The client displayed a total; refuse to hold at a price it never saw.
  if p_expected_total is not null
     and (v_quote ->> 'total')::numeric <> p_expected_total then
    raise exception 'price changed to %', (v_quote ->> 'total')
      using errcode = 'P0007';
  end if;

  insert into public.reservations
    (unit_id, slot_type_id, period, kind, status, customer_id, guests,
     quote, hold_expires_at, created_by, occasion)
  values
    (p_unit_id, p_slot_type_id, v_period, 'booking', 'hold', v_uid, p_guests,
     v_quote, now() + interval '15 minutes', v_uid, p_occasion)
  returning * into v_row;

  if p_coupon_code is not null then
    -- Race-safe redemption: the max_redemptions check and the increment
    -- are the SAME statement, serialized by the coupon row's lock (see
    -- 0012 for the full reasoning).
    update public.coupons
       set redeemed_count = redeemed_count + 1
     where code = p_coupon_code
       and property_id = v_property
       and is_active
       and (max_redemptions is null or redeemed_count < max_redemptions)
    returning id into v_coupon_id;

    if v_coupon_id is null then
      raise exception 'coupon % has reached its usage limit', p_coupon_code
        using errcode = 'P0012';
    end if;

    v_discount := coalesce(((v_quote -> 'coupon') ->> 'discount')::numeric, 0);

    insert into public.coupon_redemptions
      (coupon_id, reservation_id, customer_id, amount)
    values (v_coupon_id, v_row.id, v_uid, v_discount);
  end if;

  return v_row;
end;
$$;

-- The hold's own customer, or an admin of the hold's resort, confirms it --
-- and only while the resort is `active`.
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

  if not exists (select 1 from public.properties
                  where id = v_row.property_id and status = 'active') then
    raise exception using errcode = 'P0022', message = 'resort_suspended';
  end if;

  if v_row.status = 'confirmed' then
    return v_row;   -- idempotent: a retried webhook must not double-charge
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

  insert into public.payments
    (reservation_id, amount, kind, status, gateway, gateway_ref)
  values (p_reservation_id, p_amount, 'advance', 'succeeded', 'mock',
          p_payment_ref);

  update public.reservations
     set status = 'confirmed', hold_expires_at = null
   where id = p_reservation_id
  returning * into v_row;

  return v_row;
end;
$$;

-- A refund preview: the reservation's own customer, or any staff role at
-- its resort (read-only, so allowed while the resort is suspended).
create or replace function public.compute_refund(p_reservation_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid         uuid := auth.uid();
  v_row         public.reservations;
  v_tz          text;
  v_total       numeric;
  v_days_before int;
  v_rule        public.refund_rules;
  v_pct         numeric(5,2) := 0;
  v_amount      numeric(12,2) := 0;
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode = 'P0008';
  end if;

  select * into v_row from public.reservations where id = p_reservation_id;
  if not found then
    raise exception 'reservation not found' using errcode = 'P0002';
  end if;

  if v_row.customer_id is distinct from v_uid then
    perform public.assert_resort_role(v_row.property_id, false,
      'owner','admin','staff','accountant');
  end if;

  select p.timezone into v_tz
  from public.properties p where p.id = v_row.property_id;

  -- Property-local calendar dates, not raw elapsed hours (see 0013).
  v_days_before := (lower(v_row.period) at time zone v_tz)::date
                  - (now() at time zone v_tz)::date;

  select * into v_rule
  from public.refund_rules
  where property_id = v_row.property_id
    and min_days_before <= v_days_before
  order by min_days_before desc
  limit 1;

  -- `v_row.quote` is NULL for an admin block (no customer, no price).
  v_total := coalesce((v_row.quote ->> 'total')::numeric, 0);

  if v_rule.id is not null then
    v_pct    := v_rule.refund_pct;
    v_amount := round(v_total * v_pct / 100, 2);
  end if;

  return jsonb_build_object(
    'days_before',   v_days_before,
    'refund_pct',    v_pct,
    'refund_amount', v_amount,
    'rule_id',       v_rule.id
  );
end;
$$;

-- The reservation's own customer cancels it (also while the resort is
-- suspended); otherwise only an admin of its resort, while it is active.
create or replace function public.cancel_booking(
  p_reservation_id uuid,
  p_reason         text
) returns public.reservations
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid    uuid := auth.uid();
  v_row    public.reservations;
  v_refund jsonb;
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

  if v_row.status = 'cancelled' then
    return v_row;
  end if;

  v_refund := public.compute_refund(p_reservation_id);

  update public.reservations
     set status        = 'cancelled',
         cancel_reason  = p_reason,
         cancelled_at   = now(),
         refund_pct     = (v_refund ->> 'refund_pct')::numeric,
         refund_amount  = (v_refund ->> 'refund_amount')::numeric
   where id = p_reservation_id
  returning * into v_row;

  perform public.release_reservation_coupon(p_reservation_id);

  return v_row;
end;
$$;

-- Admin blocking, by an admin of the unit's resort. All ranges land or none
-- do: one transaction, one statement.
create or replace function public.block_dates(
  p_unit_id uuid,
  p_ranges  daterange[],
  p_reason  text
) returns setof public.reservations
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_range    daterange;
  v_property uuid;
begin
  select property_id into v_property from public.units where id = p_unit_id;
  if v_property is null then
    raise exception using errcode = 'P0002', message = 'not_found';
  end if;
  perform public.assert_resort_role(v_property, true, 'owner','admin');

  foreach v_range in array p_ranges loop
    return query
      insert into public.reservations
        (unit_id, period, kind, status, block_reason, created_by, source)
      values (p_unit_id,
              public.build_period(p_unit_id, lower(v_range), upper(v_range)),
              'block', 'confirmed', p_reason, auth.uid(), 'admin')
      returning *;
  end loop;
end;
$$;

-- ---------------------------------------------------------------------
-- Stay and guest-service functions.

-- Staff-or-above of the reservation's resort only -- moves a paid booking
-- to `checked_in` once the guest has arrived and been verified.
create or replace function public.check_in_booking(
  p_reservation_id uuid
) returns public.reservations
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_row public.reservations;
begin
  select * into v_row from public.reservations
  where id = p_reservation_id for update;

  if not found then
    raise exception 'reservation not found' using errcode = 'P0002';
  end if;

  perform public.assert_resort_role(v_row.property_id, true, 'owner','admin','staff','accountant');

  if v_row.status = 'checked_in' then
    return v_row;   -- idempotent: re-tapping Check In does nothing harmful
  end if;

  if v_row.status <> 'confirmed' then
    raise exception 'reservation is %', v_row.status using errcode = 'P0009';
  end if;

  update public.reservations
     set status = 'checked_in', checked_in_at = clock_timestamp()
   where id = p_reservation_id
  returning * into v_row;

  return v_row;
end;
$$;

-- Computed fresh on every call. Callable by the reservation's own
-- customer, or any staff role at its resort (read-only, so allowed while
-- the resort is suspended).
create or replace function public.current_charges(
  p_reservation_id uuid
) returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid       uuid := auth.uid();
  v_res       public.reservations;
  v_stay      numeric(12,2);
  v_food      numeric(12,2);
  v_activity  numeric(12,2);
  v_paid      numeric(12,2);
  v_total     numeric(12,2);
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode = 'P0008';
  end if;

  select * into v_res from public.reservations where id = p_reservation_id;
  if not found then
    raise exception 'reservation not found' using errcode = 'P0002';
  end if;

  if v_res.customer_id is distinct from v_uid then
    perform public.assert_resort_role(v_res.property_id, false,
      'owner','admin','staff','accountant');
  end if;

  v_stay := coalesce((v_res.quote ->> 'total')::numeric, 0);

  select coalesce(sum(total), 0) into v_food
  from public.food_orders
  where reservation_id = p_reservation_id and status <> 'cancelled';

  select coalesce(sum(amount), 0) into v_activity
  from public.activity_bookings
  where reservation_id = p_reservation_id and status <> 'cancelled';

  select coalesce(sum(amount), 0) into v_paid
  from public.payments
  where reservation_id = p_reservation_id and status = 'succeeded';

  v_total := v_stay + v_food + v_activity;

  return jsonb_build_object(
    'stay_amount', v_stay,
    'food_amount', v_food,
    'activity_amount', v_activity,
    'total', v_total,
    'paid', v_paid,
    'balance', greatest(v_total - v_paid, 0)
  );
end;
$$;

-- Staff-or-above of the reservation's resort, or the reservation's own
-- customer (self-checkout, widened in 0039).
create or replace function public.checkout_booking(
  p_reservation_id uuid,
  p_payment_ref    text,
  p_amount         numeric
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
    insert into public.payments
      (reservation_id, amount, kind, status, gateway, gateway_ref)
    values (p_reservation_id, v_balance, 'balance', 'succeeded', 'mock', p_payment_ref);
  end if;

  update public.reservations
     set status = 'checked_out', checked_out_at = clock_timestamp()
   where id = p_reservation_id
  returning * into v_row;

  return v_row;
end;
$$;

-- In-stay food ordering. Guest-facing: only the reservation's own customer
-- may order, and only while their resort is `active`.
create or replace function public.place_food_order(
  p_reservation_id uuid,
  p_items          jsonb,
  p_notes          text default null
) returns public.food_orders
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid   uuid := auth.uid();
  v_res   public.reservations;
  v_item  jsonb;
  v_food  public.food_items;
  v_qty   int;
  v_order public.food_orders;
  v_total numeric(12,2) := 0;
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode = 'P0008';
  end if;

  select * into v_res from public.reservations where id = p_reservation_id;
  if not found or v_res.customer_id is distinct from v_uid then
    raise exception 'not permitted' using errcode = 'P0008';
  end if;

  if not exists (select 1 from public.properties
                  where id = v_res.property_id and status = 'active') then
    raise exception using errcode = 'P0022', message = 'resort_suspended';
  end if;

  if v_res.status not in ('confirmed', 'checked_in') then
    raise exception 'this stay is not open for ordering' using errcode = 'P0009';
  end if;

  if jsonb_array_length(p_items) = 0 then
    raise exception 'an order needs at least one item' using errcode = 'P0003';
  end if;

  insert into public.food_orders (reservation_id, status, total, notes)
  values (p_reservation_id, 'placed', 0, p_notes)
  returning * into v_order;

  for v_item in select jsonb_array_elements(p_items) loop
    select * into v_food from public.food_items
    where id = (v_item ->> 'food_item_id')::uuid and is_available;
    if not found then
      raise exception 'menu item % is not available', v_item ->> 'food_item_id'
        using errcode = 'P0002';
    end if;

    v_qty := (v_item ->> 'quantity')::int;
    if v_qty is null or v_qty <= 0 then
      raise exception 'quantity must be positive' using errcode = 'P0003';
    end if;

    insert into public.food_order_items
      (order_id, food_item_id, item_name, unit_price, quantity, line_total)
    values
      (v_order.id, v_food.id, v_food.name, v_food.price, v_qty, v_food.price * v_qty);

    v_total := v_total + v_food.price * v_qty;
  end loop;

  update public.food_orders set total = v_total where id = v_order.id
  returning * into v_order;

  return v_order;
end;
$$;

-- In-stay activity booking. Guest-facing: only the reservation's own
-- customer may book, and only while their resort is `active`.
create or replace function public.book_activity(
  p_reservation_id uuid,
  p_activity_id    uuid,
  p_booking_date   date,
  p_start_time     time,
  p_people         int
) returns public.activity_bookings
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid      uuid := auth.uid();
  v_res      public.reservations;
  v_activity public.activities;
  v_booked   int;
  v_booking  public.activity_bookings;
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode = 'P0008';
  end if;

  select * into v_res from public.reservations where id = p_reservation_id;
  if not found or v_res.customer_id is distinct from v_uid then
    raise exception 'not permitted' using errcode = 'P0008';
  end if;

  if not exists (select 1 from public.properties
                  where id = v_res.property_id and status = 'active') then
    raise exception using errcode = 'P0022', message = 'resort_suspended';
  end if;

  if v_res.status not in ('confirmed', 'checked_in') then
    raise exception 'this stay is not open for activity booking' using errcode = 'P0009';
  end if;

  if p_people <= 0 then
    raise exception 'people must be positive' using errcode = 'P0003';
  end if;

  -- Locks the activity row itself, not the (aggregate) booking count --
  -- `for update` cannot target an aggregate directly. This serializes every
  -- concurrent booking attempt on the same activity behind one lock, which
  -- is coarser than locking just this slot, but activity capacity is
  -- advisory (see this function's own header comment) so contention across
  -- unrelated slots on a popular activity is an acceptable tradeoff for a
  -- correct, simple capacity check.
  select * into v_activity from public.activities
  where id = p_activity_id and is_available
  for update;
  if not found then
    raise exception 'activity is not available' using errcode = 'P0002';
  end if;

  select coalesce(sum(people), 0) into v_booked
  from public.activity_bookings
  where activity_id = p_activity_id
    and booking_date = p_booking_date
    and start_time = p_start_time
    and status = 'booked';

  if v_booked + p_people > v_activity.capacity_per_slot then
    raise exception 'this slot is full' using errcode = 'P0010';
  end if;

  insert into public.activity_bookings
    (reservation_id, activity_id, booking_date, start_time, people, amount)
  values
    (p_reservation_id, p_activity_id, p_booking_date, p_start_time, p_people,
     v_activity.price_per_person * p_people)
  returning * into v_booking;

  return v_booking;
end;
$$;

-- In-stay service requests (cleaning, water, ...). Guest-facing: only the
-- reservation's own customer may request, and only while their resort is
-- `active`.
create or replace function public.create_service_request(
  p_reservation_id uuid,
  p_category       public.service_request_category,
  p_description    text default ''
) returns public.service_requests
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_res public.reservations;
  v_req public.service_requests;
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode = 'P0008';
  end if;

  select * into v_res from public.reservations where id = p_reservation_id;
  if not found or v_res.customer_id is distinct from v_uid then
    raise exception 'not permitted' using errcode = 'P0008';
  end if;

  if not exists (select 1 from public.properties
                  where id = v_res.property_id and status = 'active') then
    raise exception using errcode = 'P0022', message = 'resort_suspended';
  end if;

  if v_res.status not in ('confirmed', 'checked_in') then
    raise exception 'this stay is not open for service requests' using errcode = 'P0009';
  end if;

  insert into public.service_requests (reservation_id, category, description)
  values (p_reservation_id, p_category, p_description)
  returning * into v_req;

  return v_req;
end;
$$;

-- Maintenance issue reporting. The reservation's own customer, or
-- staff-or-above of its resort, may file a report.
create or replace function public.report_maintenance_issue(
  p_reservation_id uuid,
  p_category       public.maintenance_category,
  p_description    text default '',
  p_photo_url      text default null,
  p_priority       public.maintenance_priority default 'medium'
) returns public.maintenance_issues
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid   uuid := auth.uid();
  v_res   public.reservations;
  v_issue public.maintenance_issues;
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode = 'P0008';
  end if;

  select * into v_res from public.reservations where id = p_reservation_id;
  if not found then
    raise exception 'reservation not found' using errcode = 'P0002';
  end if;

  if v_res.customer_id is distinct from v_uid then
    perform public.assert_resort_role(v_res.property_id, true, 'owner','admin','staff','accountant');
  end if;

  if v_res.status not in ('confirmed', 'checked_in') then
    raise exception 'this stay is not open for maintenance reports' using errcode = 'P0009';
  end if;

  insert into public.maintenance_issues
    (reservation_id, category, description, photo_url, priority)
  values (p_reservation_id, p_category, p_description, p_photo_url, p_priority)
  returning * into v_issue;

  return v_issue;
end;
$$;

-- ---------------------------------------------------------------------
-- Reports, dashboard, performance summary and shift listing.
--
-- `report_revenue`/`report_occupancy`/`report_food_sales`/`report_expenses`
-- already accepted an optional `p_property_id` (added when the app was
-- single-property, to let one owner compare figures across two of their
-- own resorts). It becomes REQUIRED here, for the same reason `assert_staff`
-- is retired in favour of `assert_resort_role`: an optional filter that
-- silently defaults to "every resort" is exactly backwards once a caller
-- can be staff at one resort and nothing at another -- the old
-- `is_staff_or_above()` check would happily hand resort A's staff every
-- other resort's revenue, occupancy and expenses the moment they omitted
-- the filter.

-- Staff-or-above of the resort only. Every inner query is now filtered to
-- p_property_id -- dashboard_summary used to simply read whatever
-- report_revenue/report_occupancy/report_food_sales and the reservations/
-- expenses tables returned, which was safe only because there was ever
-- just the one resort in reach.
drop function if exists public.dashboard_summary();

create function public.dashboard_summary(p_property_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_today date := (now() at time zone 'Asia/Kolkata')::date;
  v_month_start date := date_trunc('month', v_today)::date;
  v_food_sales_today numeric;
  v_expenses_month numeric;
begin
  perform public.assert_resort_role(p_property_id, false, 'owner','admin','staff','accountant');

  select coalesce(sum(gross), 0) into v_food_sales_today
  from public.report_food_sales(v_today, v_today, p_property_id);

  select coalesce(sum(amount), 0) into v_expenses_month
  from public.expenses
  where property_id = p_property_id
    and expense_date between v_month_start and v_today;

  return jsonb_build_object(
    'today_revenue', coalesce((
      select sum(net) from public.report_revenue(v_today, v_today, p_property_id)), 0),
    'month_revenue', coalesce((
      select sum(net) from public.report_revenue(v_month_start, v_today, p_property_id)), 0),
    'occupancy_pct', coalesce((
      select round(avg(occupancy_pct), 1)
      from public.report_occupancy(v_month_start, v_today, p_property_id)), 0),
    'upcoming_arrivals', (
      select count(*)::int from public.reservations
      where property_id = p_property_id
        and kind = 'booking' and status = 'confirmed'
        and lower(period) >= now()
        and lower(period) < now() + interval '7 days'),
    'cancellations_this_month', (
      select count(*)::int from public.reservations
      where property_id = p_property_id
        and kind = 'booking' and status = 'cancelled'
        and cancelled_at >= v_month_start),
    'active_holds', (
      select count(*)::int from public.reservations
      where property_id = p_property_id
        and status = 'hold' and hold_expires_at > now()),
    'food_sales_today', v_food_sales_today,
    'expenses_month_total', v_expenses_month,
    'net_profit_month', coalesce((
      select sum(net) from public.report_revenue(v_month_start, v_today, p_property_id)), 0)
      - v_expenses_month,
    'checked_in_today', (
      select count(*)::int from public.reservations
      where property_id = p_property_id
        and kind = 'booking' and checked_in_at::date = v_today),
    'checked_out_today', (
      select count(*)::int from public.reservations
      where property_id = p_property_id
        and kind = 'booking' and checked_out_at::date = v_today),
    'currently_in_house', (
      select count(*)::int from public.reservations
      where property_id = p_property_id
        and kind = 'booking' and status = 'checked_in')
  );
end;
$$;

grant execute on function public.dashboard_summary(uuid) to authenticated;
revoke execute on function public.dashboard_summary(uuid) from public;
revoke execute on function public.dashboard_summary(uuid) from anon;

-- p_property_id is now required (no default). The argument types are
-- unchanged from 0042's, but Postgres refuses to drop a parameter default
-- via CREATE OR REPLACE ("cannot remove parameter defaults from existing
-- function"), so the old signature is dropped and recreated, then
-- re-granted exactly as it was.
drop function if exists public.report_revenue(date, date, uuid);

create function public.report_revenue(p_from date, p_to date, p_property_id uuid)
 returns table(day date, property_id uuid, bookings integer, gross numeric, refunded numeric, net numeric)
 language plpgsql
 stable security definer
 set search_path to 'public', 'pg_temp'
as $function$
begin
  perform public.assert_resort_role(p_property_id, false, 'owner','admin','staff','accountant');

  return query
  select
    (lower(r.period) at time zone p.timezone)::date as day,
    p.id,
    count(*)::int,
    coalesce(sum((r.quote ->> 'total')::numeric)
             filter (where r.status in ('confirmed','checked_in','checked_out')), 0),
    coalesce(sum(r.refund_amount)
             filter (where r.status = 'cancelled'), 0),
    coalesce(sum((r.quote ->> 'total')::numeric)
             filter (where r.status in ('confirmed','checked_in','checked_out')), 0)
    - coalesce(sum(r.refund_amount)
               filter (where r.status = 'cancelled'), 0)
  from public.reservations r
  join public.units u on u.id = r.unit_id
  join public.properties p on p.id = u.property_id
  where r.kind = 'booking'
    and r.quote is not null
    and (lower(r.period) at time zone p.timezone)::date between p_from and p_to
    and p.id = p_property_id
  group by 1, 2
  order by 1;
end;
$function$;

grant execute on function public.report_revenue to authenticated;
revoke execute on function public.report_revenue from public;
revoke execute on function public.report_revenue from anon;

-- Same treatment as report_revenue: p_property_id required, resort role
-- required at that resort, old signature dropped and re-granted.
drop function if exists public.report_occupancy(date, date, uuid);

create function public.report_occupancy(p_from date, p_to date, p_property_id uuid)
 returns table(unit_id uuid, unit_name text, nights_available integer, nights_booked integer, occupancy_pct numeric)
 language plpgsql
 stable security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare
  v_span int := greatest((p_to - p_from), 1);
begin
  perform public.assert_resort_role(p_property_id, false, 'owner','admin','staff','accountant');

  return query
  select
    u.id,
    u.name,
    v_span,
    coalesce((
      select sum(
        least((upper(r.period) at time zone p.timezone)::date, p_to)
        - greatest((lower(r.period) at time zone p.timezone)::date, p_from)
      )::int
      from public.reservations r
      where r.unit_id = u.id
        and r.kind = 'booking'
        and r.status in ('confirmed','checked_in','checked_out')
        and r.period && tstzrange(p_from::timestamp at time zone p.timezone,
                                   p_to::timestamp at time zone p.timezone, '[)')
    ), 0),
    round(
      coalesce((
        select sum(
          least((upper(r.period) at time zone p.timezone)::date, p_to)
          - greatest((lower(r.period) at time zone p.timezone)::date, p_from)
        )::numeric
        from public.reservations r
        where r.unit_id = u.id
          and r.kind = 'booking'
          and r.status in ('confirmed','checked_in','checked_out')
          and r.period && tstzrange(p_from::timestamp at time zone p.timezone,
                                     p_to::timestamp at time zone p.timezone, '[)')
      ), 0) * 100 / v_span, 1)
  from public.units u
  join public.properties p on p.id = u.property_id
  where u.is_active
    and p.id = p_property_id
  order by u.name;
end;
$function$;

grant execute on function public.report_occupancy to authenticated;
revoke execute on function public.report_occupancy from public;
revoke execute on function public.report_occupancy from anon;

-- Same treatment: p_property_id required, Staff+ at that resort (matching
-- the food_activity_sales_read policy's own role list). Old signature
-- dropped and re-granted, same reason as report_revenue above.
drop function if exists public.report_food_sales(date, date, uuid);

create function public.report_food_sales(
  p_from        date,
  p_to          date,
  p_property_id uuid
) returns table (
  day         date,
  category    public.sale_category,
  items_sold  int,
  gross       numeric
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  perform public.assert_resort_role(p_property_id, false, 'owner','admin','staff','accountant');

  return query
  select
    s.sale_date,
    s.category,
    sum(s.quantity)::int,
    sum(s.amount)
  from public.food_activity_sales s
  where s.sale_date between p_from and p_to
    and s.property_id = p_property_id
  group by 1, 2
  order by 1, 2;
end;
$$;

grant execute on function public.report_food_sales to authenticated;
revoke execute on function public.report_food_sales from public;
revoke execute on function public.report_food_sales from anon;

-- p_property_id required; the role check moves from a plain global
-- current_role() test to assert_resort_role at the resort itself -- same
-- owner/admin/accountant role list as the expenses_read policy, still
-- deliberately excluding plain staff. Old signature dropped and
-- re-granted, same reason as report_revenue above.
drop function if exists public.report_expenses(date, date, uuid);

create function public.report_expenses(
  p_from        date,
  p_to          date,
  p_property_id uuid
) returns table (
  day    date,
  category text,
  total  numeric
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  perform public.assert_resort_role(p_property_id, false, 'owner','admin','accountant');

  return query
  select
    e.expense_date,
    e.category,
    sum(e.amount)
  from public.expenses e
  where e.expense_date between p_from and p_to
    and e.property_id = p_property_id
  group by 1, 2
  order by 1, 2;
end;
$$;

grant execute on function public.report_expenses to authenticated;
revoke execute on function public.report_expenses from public;
revoke execute on function public.report_expenses from anon;

-- Staff performance reporting is resort-scoped: p_property_id is a new
-- required first parameter, and the "which staff members exist" source
-- switches from the global profiles.role column (a role that no longer
-- means anything resort-specific) to this resort's own resort_members
-- roster. Still security invoker -- relies on the caller's own RLS on
-- tasks/attendance_records/leave_requests/staff_shifts, which is already
-- resort-scoped (0044) -- plus an explicit assert_resort_role and
-- property_id filter on every query so an admin who belongs to more than
-- one resort never blends another resort's figures into this one.
drop function if exists public.staff_performance_summary(uuid, date, date);

create function public.staff_performance_summary(
  p_property_id uuid,
  p_staff_id    uuid default null,
  p_from        date default (now() at time zone 'Asia/Kolkata')::date - 30,
  p_to          date default (now() at time zone 'Asia/Kolkata')::date
) returns table (
  staff_id                  uuid,
  staff_name                text,
  tasks_assigned            int,
  tasks_completed           int,
  completion_rate_pct       numeric,
  avg_completion_hours      numeric,
  days_present              int,
  leave_days_approved       int,
  avg_checkin_delay_minutes numeric
)
language plpgsql
stable
security invoker
as $$
begin
  perform public.assert_resort_role(p_property_id, false, 'owner','admin');

  return query
  with staff as (
    select p.id, p.full_name
    from public.resort_members m
    join public.profiles p on p.id = m.user_id
    where m.property_id = p_property_id
      and (p_staff_id is null or p.id = p_staff_id)
  ),
  task_stats as (
    select
      t.assignee_id,
      count(*)::int as assigned,
      count(*) filter (where t.status = 'done')::int as completed,
      avg(extract(epoch from (t.completed_at - t.created_at)) / 3600.0)
        filter (where t.completed_at is not null) as avg_hours
    from public.tasks t
    where t.property_id = p_property_id
      and t.created_at::date between p_from and p_to
    group by t.assignee_id
  ),
  attendance_stats as (
    select
      a.staff_id,
      count(*)::int as present,
      avg(
        extract(epoch from (
          a.check_in_at - (a.work_date + s.start_time)
        )) / 60.0
      ) filter (where s.start_time is not null) as avg_delay
    from public.attendance_records a
    left join public.staff_shifts s
      on s.staff_id = a.staff_id and s.shift_date = a.work_date
         and s.property_id = p_property_id
    where a.property_id = p_property_id
      and a.work_date between p_from and p_to
    group by a.staff_id
  ),
  leave_stats as (
    select
      l.staff_id,
      sum(l.end_date - l.start_date + 1)::int as leave_days
    from public.leave_requests l
    where l.property_id = p_property_id
      and l.status = 'approved'
      and l.start_date <= p_to and l.end_date >= p_from
    group by l.staff_id
  )
  select
    s.id,
    coalesce(s.full_name, ''),
    coalesce(ts.assigned, 0),
    coalesce(ts.completed, 0),
    case when coalesce(ts.assigned, 0) = 0 then 0
         else round(ts.completed * 100.0 / ts.assigned, 1) end,
    round(ts.avg_hours, 1),
    coalesce(ast.present, 0),
    coalesce(ls.leave_days, 0),
    round(ast.avg_delay, 1)
  from staff s
  left join task_stats ts on ts.assignee_id = s.id
  left join attendance_stats ast on ast.staff_id = s.id
  left join leave_stats ls on ls.staff_id = s.id
  order by s.full_name nulls last;
end;
$$;

grant execute on function public.staff_performance_summary to authenticated;
revoke execute on function public.staff_performance_summary from public;
revoke execute on function public.staff_performance_summary from anon;

-- list_staff_shifts gains a required p_property_id first parameter and
-- filters on it directly; it deliberately still runs (as before) without
-- assert_resort_role or security definer -- RLS on staff_shifts (0044)
-- already scopes every row to its own resort, exactly as this function's
-- original 0021 header explained for the single-property RLS it relied on
-- then.
drop function if exists public.list_staff_shifts(uuid, date, date);

create function public.list_staff_shifts(
  p_property_id uuid,
  p_staff_id    uuid default null,
  p_from        date default null,
  p_to          date default null
) returns table(
  id         uuid,
  staff_id   uuid,
  staff_name text,
  shift_date date,
  start_time time,
  end_time   time,
  notes      text,
  created_at timestamptz
)
language sql
stable
set search_path = public, pg_temp
as $$
  select s.id, s.staff_id, p.full_name, s.shift_date, s.start_time,
         s.end_time, s.notes, s.created_at
  from public.staff_shifts s
  join public.profiles p on p.id = s.staff_id
  where s.property_id = p_property_id
    and (p_staff_id is null or s.staff_id = p_staff_id)
    and (p_from is null or s.shift_date >= p_from)
    and (p_to is null or s.shift_date <= p_to)
  order by s.shift_date, s.start_time;
$$;

grant execute on function public.list_staff_shifts(uuid, uuid, date, date) to authenticated;
-- C1-sweep convention (see 0018_ical.sql / 0019_user_admin.sql): a `grant`
-- to `authenticated` never removes the default PUBLIC EXECUTE a function
-- holds since creation, so `anon` (and PUBLIC) must be revoked explicitly.
revoke execute on function public.list_staff_shifts(uuid, uuid, date, date) from public;
revoke execute on function public.list_staff_shifts(uuid, uuid, date, date) from anon;

-- ---------------------------------------------------------------------
-- Staff operations, outbox, audit and iCal.
--
-- Not redefined, because none of them checks a role:
-- `attendance_records_enforce_own_checkout()` (own-row checkout guard),
-- `attendance_records_force_checkin_time()`, `ical_build_document()`
-- (internal; reached only through ical_export/ical_export_public) and
-- `ical_poll_all_feeds()` (cron only).
--
-- The write-guard triggers below back the resort-scoped policies in 0044.
-- Where a row could be moved, the caller must hold the role at both the
-- old and the new resort.

create or replace function public.staff_shifts_enforce_admin_write()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if not public.has_resort_role(old.property_id, true, 'owner','admin')
     or (TG_OP = 'UPDATE'
         and not public.has_resort_role(new.property_id, true, 'owner','admin')) then
    raise sqlstate '42501' using
      message = 'permission denied for table staff_shifts',
      hint = 'only administrators can modify shift assignments';
  end if;

  if TG_OP = 'UPDATE' then
    return new;
  else  -- DELETE
    return old;
  end if;
end;
$$;

-- Admin+ of the request's resort decides; the resort itself is part of
-- the request's content and never changes.
create or replace function public.leave_requests_enforce_admin_decision()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if not public.has_resort_role(old.property_id, true, 'owner','admin') then
    raise sqlstate '42501' using
      message = 'permission denied for table leave_requests',
      hint = 'only administrators can decide leave requests';
  end if;

  if new.staff_id is distinct from old.staff_id
      or new.start_date is distinct from old.start_date
      or new.end_date is distinct from old.end_date
      or new.reason is distinct from old.reason
      or new.property_id is distinct from old.property_id then
    raise sqlstate '42501' using
      message = 'only status, decided_by, and decided_at may be changed',
      hint = 'admins decide requests, they do not edit their content';
  end if;

  if old.status <> 'pending' then
    raise sqlstate '42501' using
      message = 'a decided leave request cannot be changed',
      hint = 'once approved or rejected, a decision is final';
  end if;

  if new.status not in ('approved', 'rejected') then
    raise sqlstate '42501' using
      message = 'leave request status must be approved or rejected',
      hint = 'a decision must decide: approved or rejected, not pending or any other value';
  end if;

  return new;
end;
$$;

-- Own row only, and only while the resort is active.
create or replace function public.check_out_attendance(p_id uuid)
returns public.attendance_records
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_record public.attendance_records;
begin
  select * into v_record from public.attendance_records where id = p_id;
  if not found then
    raise sqlstate 'P0002' using message = 'attendance record not found';
  end if;

  if v_record.staff_id <> auth.uid() then
    raise sqlstate '42501' using
      message = 'permission denied for table attendance_records',
      hint = 'only the staff member who checked in may check themselves out';
  end if;

  if not exists (select 1 from public.properties
                  where id = v_record.property_id and status = 'active') then
    raise exception using errcode = 'P0022', message = 'resort_suspended';
  end if;

  if v_record.check_out_at is not null then
    raise sqlstate '42501' using
      message = 'this record is already checked out',
      hint = 'a check-out cannot be changed once recorded';
  end if;

  update public.attendance_records
    set check_out_at = clock_timestamp()
    where id = p_id;

  select * into v_record from public.attendance_records where id = p_id;
  return v_record;
end;
$$;

-- Admin+ of the task's resort edits anything (but cannot move the task to
-- a resort where they are not Admin+); the assignee may change only the
-- status of their own task, never its resort.
create or replace function public.tasks_enforce_write()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_admin boolean := public.has_resort_role(old.property_id, true, 'owner','admin');
begin
  if TG_OP = 'DELETE' then
    if not v_admin then
      raise sqlstate '42501' using
        message = 'permission denied for table tasks',
        hint = 'only an administrator can delete a task';
    end if;
    return old;
  end if;

  if v_admin and public.has_resort_role(new.property_id, true, 'owner','admin') then
    new.updated_at := clock_timestamp();
    if new.status = 'done' and old.completed_at is null then
      new.completed_at := clock_timestamp();
    end if;
    return new;
  end if;

  if new.assignee_id <> old.assignee_id then
    raise sqlstate '42501' using
      message = 'permission denied for table tasks',
      hint = 'only an administrator can reassign a task';
  end if;

  if new.id is distinct from old.id
      or new.title is distinct from old.title
      or new.description is distinct from old.description
      or new.created_by is distinct from old.created_by
      or new.created_at is distinct from old.created_at
      or new.property_id is distinct from old.property_id then
    raise sqlstate '42501' using
      message = 'permission denied for table tasks',
      hint = 'only an administrator can edit a task''s details';
  end if;

  if old.assignee_id <> auth.uid() then
    raise sqlstate '42501' using
      message = 'permission denied for table tasks',
      hint = 'you can only update the status of your own tasks';
  end if;

  new.updated_at := clock_timestamp();
  if new.status = 'done' and old.completed_at is null then
    new.completed_at := clock_timestamp();
  end if;
  return new;
end;
$$;

-- Staff+ of the request's resort has full write; the assigned staff
-- member's status-only path is unchanged.
create or replace function public.service_requests_enforce_write()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if public.has_resort_role(old.property_id, true, 'owner','admin','staff','accountant')
     and public.has_resort_role(new.property_id, true, 'owner','admin','staff','accountant') then
    if new.assigned_staff_id is distinct from old.assigned_staff_id
        and old.assigned_staff_id is null
        and new.assigned_staff_id is not null
        and old.status = 'requested' then
      new.status := 'assigned';
    end if;
    new.updated_at := clock_timestamp();
    return new;
  end if;

  if old.assigned_staff_id is distinct from auth.uid() then
    raise sqlstate '42501' using
      message = 'permission denied for table service_requests',
      hint = 'you can only update requests assigned to you';
  end if;

  if new.id is distinct from old.id
      or new.reservation_id is distinct from old.reservation_id
      or new.category is distinct from old.category
      or new.description is distinct from old.description
      or new.assigned_staff_id is distinct from old.assigned_staff_id
      or new.created_at is distinct from old.created_at
      or new.property_id is distinct from old.property_id then
    raise sqlstate '42501' using
      message = 'permission denied for table service_requests',
      hint = 'only staff can reassign or edit a request''s details';
  end if;

  new.updated_at := clock_timestamp();
  return new;
end;
$$;

create or replace function public.maintenance_issues_enforce_write()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if public.has_resort_role(old.property_id, true, 'owner','admin','staff','accountant')
     and public.has_resort_role(new.property_id, true, 'owner','admin','staff','accountant') then
    if new.assigned_staff_id is distinct from old.assigned_staff_id
        and old.assigned_staff_id is null
        and new.assigned_staff_id is not null
        and old.status = 'reported' then
      new.status := 'assigned';
    end if;
    new.updated_at := clock_timestamp();
    return new;
  end if;

  if old.assigned_staff_id is distinct from auth.uid() then
    raise sqlstate '42501' using
      message = 'permission denied for table maintenance_issues',
      hint = 'you can only update issues assigned to you';
  end if;

  if new.id is distinct from old.id
      or new.reservation_id is distinct from old.reservation_id
      or new.category is distinct from old.category
      or new.description is distinct from old.description
      or new.photo_url is distinct from old.photo_url
      or new.priority is distinct from old.priority
      or new.assigned_staff_id is distinct from old.assigned_staff_id
      or new.created_at is distinct from old.created_at
      or new.property_id is distinct from old.property_id then
    raise sqlstate '42501' using
      message = 'permission denied for table maintenance_issues',
      hint = 'only staff can reassign or edit an issue''s details';
  end if;

  new.updated_at := clock_timestamp();
  return new;
end;
$$;

-- Templates: a resort uses its own templates and the platform defaults
-- (property_id null), never another resort's. For one channel of an
-- event, the resort's own template wins over a default.
create or replace function public.enqueue_reservation_outbox()
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
      select distinct on (channel) name from public.outbox_templates
      where event = 'booking_confirmation'
        and (property_id = new.property_id or property_id is null)
      order by channel, property_id nulls last
    loop
      perform public.enqueue_outbox_message(new.id, v_name);
    end loop;

    for v_name in
      select distinct on (channel) name from public.outbox_templates
      where event = 'payment_success'
        and (property_id = new.property_id or property_id is null)
      order by channel, property_id nulls last
    loop
      perform public.enqueue_outbox_message(new.id, v_name);
    end loop;
  end if;

  if tg_op = 'UPDATE' and old.status = 'confirmed' and new.status = 'cancelled' then
    for v_name in
      select distinct on (channel) name from public.outbox_templates
      where event = 'cancellation'
        and (property_id = new.property_id or property_id is null)
      order by channel, property_id nulls last
    loop
      perform public.enqueue_outbox_message(new.id, v_name);
    end loop;
  end if;

  return new;
end;
$$;

-- Enqueues one outbox row, tagged with the reservation's resort. Two
-- callers:
--   * the reservations trigger above, on a status change that whoever
--     made it was already allowed to make (a guest cancelling, staff
--     checking in, the hold-release cron) -- no further check;
--   * a direct call (staff re-sending a message), which needs Staff+ at
--     the reservation's resort. `pg_trigger_depth() = 0` tells the two
--     apart: a client cannot call this from inside a trigger.
-- A template that belongs to another resort is treated like a missing
-- one (silently skipped).
create or replace function public.enqueue_outbox_message(
  p_reservation_id uuid,
  p_template       text
) returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_property  uuid;
  v_tpl       public.outbox_templates;
  v_row       public.reservations;
  v_profile   public.profiles;
  v_settings  public.notification_settings;
  v_email     text;
  v_recipient text;
  v_rendered  jsonb;
  v_channel_enabled boolean;
begin
  select property_id into v_property from public.reservations where id = p_reservation_id;
  if v_property is null then
    raise exception using errcode = 'P0002', message = 'not_found';
  end if;
  if pg_trigger_depth() = 0 then
    perform public.assert_resort_role(v_property, true, 'owner','admin','staff','accountant');
  end if;

  select * into v_tpl from public.outbox_templates
  where name = p_template
    and (property_id = v_property or property_id is null);
  if not found then
    return;
  end if;

  select * into v_row from public.reservations where id = p_reservation_id;
  select * into v_profile from public.profiles where id = v_row.customer_id;
  select email into v_email from auth.users where id = v_row.customer_id;

  select * into v_settings
  from public.notification_settings
  where property_id = v_property;

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
      (property_id, reservation_id, channel, recipient, template, subject, body,
       status, last_error)
    values (
      v_property, p_reservation_id, v_tpl.channel,
      format('%s (channel disabled)', v_tpl.channel),
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
      (property_id, reservation_id, channel, recipient, template, subject, body,
       status, last_error)
    values (
      v_property, p_reservation_id, v_tpl.channel,
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
    (property_id, reservation_id, channel, recipient, template, subject, body, status)
  values (
    v_property, p_reservation_id, v_tpl.channel, v_recipient, p_template,
    v_rendered ->> 'subject', v_rendered ->> 'body', 'pending');
end;
$$;

grant execute on function public.enqueue_outbox_message(uuid, text) to authenticated;
revoke execute on function public.enqueue_outbox_message(uuid, text) from public;
revoke execute on function public.enqueue_outbox_message(uuid, text) from anon;

-- Internal (still revoked from every client role, see 0017). Renders only
-- a template available to the reservation's resort: its own, preferred,
-- or a platform default.
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
  select * into v_row from public.reservations where id = p_reservation_id;
  if not found then
    raise exception 'reservation not found' using errcode = 'P0002';
  end if;

  select * into v_tpl from public.outbox_templates
  where name = p_template
    and (property_id = v_row.property_id or property_id is null)
  order by property_id nulls last
  limit 1;
  if not found then
    raise exception 'unknown outbox template %', p_template
      using errcode = 'P0002';
  end if;

  select * into v_unit from public.units where id = v_row.unit_id;
  select * into v_property from public.properties where id = v_unit.property_id;
  select * into v_profile from public.profiles where id = v_row.customer_id;
  select email into v_email from auth.users where id = v_row.customer_id;

  -- Every value is coalesced: replace() returns NULL if any argument is
  -- NULL, which would collapse the whole rendered text (see 0017).
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

-- One audit row per status transition, tagged with the reservation's
-- resort.
create or replace function public.record_reservation_transition()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if tg_op = 'INSERT' then
    insert into public.audit_log (property_id, actor_id, entity, entity_id, action, after)
    values (new.property_id, auth.uid(), 'reservation', new.id,
            'created:' || new.status::text, to_jsonb(new));
  elsif new.status is distinct from old.status then
    insert into public.audit_log
      (property_id, actor_id, entity, entity_id, action, before, after)
    values (new.property_id, auth.uid(), 'reservation', new.id,
            'status:' || old.status::text || '->' || new.status::text,
            to_jsonb(old), to_jsonb(new));
  end if;
  return new;
end;
$$;

create or replace function public.sync_unit_calendar_event()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if tg_op = 'DELETE' then
    delete from public.unit_calendar_events where reservation_id = old.id;
    return old;
  end if;

  if new.status = 'cancelled' then
    delete from public.unit_calendar_events where reservation_id = new.id;
    return new;
  end if;

  insert into public.unit_calendar_events
    (reservation_id, property_id, unit_id, period, kind, status, updated_at)
  values (new.id, new.property_id, new.unit_id, new.period, new.kind, new.status, now())
  on conflict (reservation_id) do update
    set property_id = excluded.property_id,
        unit_id = excluded.unit_id,
        period  = excluded.period,
        kind    = excluded.kind,
        status  = excluded.status,
        updated_at = now();
  return new;
end;
$$;

create or replace function public.ical_provision_token()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  insert into public.ical_export_tokens (unit_id, property_id)
  values (new.id, new.property_id)
  on conflict (unit_id) do nothing;
  return new;
end;
$$;

-- Admin+ of the unit's resort.
create or replace function public.rotate_ical_token(p_unit_id uuid)
returns text
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_property uuid;
  v_token    text;
begin
  select property_id into v_property from public.units where id = p_unit_id;
  if v_property is null then
    raise exception using errcode = 'P0002', message = 'not_found';
  end if;
  perform public.assert_resort_role(v_property, true, 'owner','admin');

  v_token := encode(extensions.gen_random_bytes(24), 'hex');

  insert into public.ical_export_tokens (unit_id, token, rotated_at)
  values (p_unit_id, v_token, now())
  on conflict (unit_id) do update
    set token = excluded.token, rotated_at = now();

  return v_token;
end;
$$;

-- Admin+ of the unit's resort (read, so allowed while suspended).
create or replace function public.ical_export(p_unit_id uuid)
returns text
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_property uuid;
begin
  select property_id into v_property from public.units where id = p_unit_id;
  if v_property is null then
    raise exception using errcode = 'P0002', message = 'not_found';
  end if;
  perform public.assert_resort_role(v_property, false, 'owner','admin');
  return public.ical_build_document(p_unit_id);
end;
$$;

-- Token-gated, for OTAs. A resort that is not active publishes nothing
-- (null) -- not an empty calendar, which an OTA would read as "every date
-- is free".
create or replace function public.ical_export_public(p_token text)
returns text
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_unit_id  uuid;
  v_property uuid;
begin
  select unit_id, property_id into v_unit_id, v_property
  from public.ical_export_tokens
  where token = p_token;

  if not found then
    raise exception 'invalid or unknown iCal token' using errcode = 'P0002';
  end if;

  if not exists (select 1 from public.properties
                  where id = v_property and status = 'active') then
    return null;
  end if;

  return public.ical_build_document(v_unit_id);
end;
$$;

-- Called in-database by ical_poll_feed (an admin's Sync, or the cron job
-- with no JWT). A PostgREST caller -- including the admin's Sync, whose
-- JWT is still set -- must be Admin+ of the unit's resort. See 0018 for
-- why the guard keys on request.jwt.claims rather than auth.uid().
create or replace function public.ical_import_event(
  p_unit_id uuid,
  p_uid     text,
  p_start   timestamptz,
  p_end     timestamptz
) returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_property uuid;
  v_existing public.reservations;
  v_period   tstzrange;
  v_id       uuid;
begin
  if nullif(current_setting('request.jwt.claims', true), '') is not null then
    select property_id into v_property from public.units where id = p_unit_id;
    if v_property is null then
      raise exception using errcode = 'P0002', message = 'not_found';
    end if;
    perform public.assert_resort_role(v_property, true, 'owner','admin');
  end if;

  if p_uid is null or btrim(p_uid) = '' then
    raise exception 'external UID is required' using errcode = 'P0005';
  end if;
  if p_start is null or p_end is null or p_end <= p_start then
    raise exception 'invalid event period' using errcode = 'P0005';
  end if;

  v_period := tstzrange(p_start, p_end, '[)');

  select * into v_existing
  from public.reservations
  where unit_id = p_unit_id and external_uid = p_uid;

  if found then
    if v_existing.status <> 'cancelled' and v_existing.period = v_period then
      return jsonb_build_object(
        'status', 'unchanged', 'reservation_id', v_existing.id, 'conflict', null);
    end if;

    begin
      update public.reservations
        set period = v_period, status = 'confirmed'
        where id = v_existing.id
        returning id into v_id;

      return jsonb_build_object(
        'status', 'updated', 'reservation_id', v_id, 'conflict', null);
    exception when exclusion_violation then
      return jsonb_build_object(
        'status', 'conflict', 'reservation_id', null,
        'conflict', jsonb_build_object(
          'unit_id', p_unit_id, 'start', p_start, 'end', p_end));
    end;
  end if;

  begin
    insert into public.reservations
      (unit_id, period, kind, status, external_uid, source)
    values (p_unit_id, v_period, 'ota', 'confirmed', p_uid, 'ical')
    returning id into v_id;

    return jsonb_build_object(
      'status', 'created', 'reservation_id', v_id, 'conflict', null);
  exception when exclusion_violation then
    return jsonb_build_object(
      'status', 'conflict', 'reservation_id', null,
      'conflict', jsonb_build_object(
        'unit_id', p_unit_id, 'start', p_start, 'end', p_end));
  end;
end;
$$;

-- Admin+ of the feed's resort for a PostgREST caller (the Sync button);
-- the cron job (no JWT) is not checked. See 0018 for the state machine.
create or replace function public.ical_poll_feed(p_feed_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_property    uuid;
  v_feed        public.ical_feeds;
  v_resp        record;
  v_body        text;
  v_event       record;
  v_created     int := 0;
  v_updated     int := 0;
  v_unchanged   int := 0;
  v_conflicts   int := 0;
  v_failed      int := 0;
  v_failed_note text;
  v_import      jsonb;
  v_error       text;
  v_req_id      bigint;
  v_result      jsonb;
begin
  if nullif(current_setting('request.jwt.claims', true), '') is not null then
    select property_id into v_property from public.ical_feeds where id = p_feed_id;
    if v_property is null then
      raise exception 'feed not found or inactive' using errcode = 'P0002';
    end if;
    perform public.assert_resort_role(v_property, true, 'owner','admin');
  end if;

  -- `for update`: a cron tick and a Sync press for the same feed must not
  -- both fire a request.
  select * into v_feed
  from public.ical_feeds
  where id = p_feed_id and is_active
  for update;

  if not found then
    raise exception 'feed not found or inactive' using errcode = 'P0002';
  end if;

  -- A request stuck far longer than pg_net's own timeout is abandoned.
  if v_feed.pending_request_id is not null
     and v_feed.pending_since < now() - interval '30 minutes' then
    v_feed.pending_request_id := null;
  end if;

  if v_feed.pending_request_id is not null then
    select status_code, content, error_msg, timed_out
      into v_resp
      from net._http_response
      where id = v_feed.pending_request_id;

    if not found then
      return jsonb_build_object('status', 'pending');
    end if;

    -- Every path must reach the `update ical_feeds` below, so an
    -- unexpected error cannot wedge the feed.
    begin
      if v_resp.timed_out or v_resp.error_msg is not null
         or v_resp.status_code is distinct from 200 then
        v_error := coalesce(
          v_resp.error_msg,
          case when v_resp.timed_out then 'request timed out'
               else 'HTTP ' || coalesce(v_resp.status_code::text, 'unknown') end);
        v_result := jsonb_build_object('status', 'error', 'error', v_error);
      else
        v_body := v_resp.content;

        for v_event in select * from public.ical_parse_events(v_body) loop
          -- One malformed event skips itself; the rest still import.
          begin
            v_import := public.ical_import_event(
              v_feed.unit_id, v_event.uid, v_event.dtstart, v_event.dtend);
            case v_import ->> 'status'
              when 'created'   then v_created   := v_created + 1;
              when 'updated'   then v_updated   := v_updated + 1;
              when 'unchanged' then v_unchanged := v_unchanged + 1;
              when 'conflict'  then v_conflicts := v_conflicts + 1;
              else null;
            end case;
          exception when others then
            v_failed := v_failed + 1;
            v_failed_note := coalesce(nullif(btrim(v_event.uid), ''), '(blank uid)')
              || ': ' || sqlerrm;
          end;
        end loop;

        v_error := nullif(trim(both ', ' from concat_ws(', ',
          case when v_conflicts > 0 then
            v_conflicts || ' event(s) conflicted with an existing booking '
            'and were skipped'
          end,
          case when v_failed > 0 then
            v_failed || ' event(s) failed to import and were skipped '
            '(last error: ' || v_failed_note || ')'
          end
        )), '');
        v_result := jsonb_build_object('status', 'ok', 'created', v_created,
          'updated', v_updated, 'unchanged', v_unchanged, 'conflicts', v_conflicts,
          'failed', v_failed);
      end if;
    exception when others then
      v_error := 'poll failed while processing response: ' || sqlerrm;
      v_result := jsonb_build_object('status', 'error', 'error', v_error);
    end;

    update public.ical_feeds
      set last_synced_at = now(), last_error = v_error,
          pending_request_id = null, pending_since = null
      where id = p_feed_id;
  end if;

  -- Fire the next request (the first, or the follow-up to the one just
  -- collected).
  begin
    v_req_id := net.http_get(url := v_feed.url, timeout_milliseconds := 15000);
  exception when others then
    update public.ical_feeds
      set last_error = 'fetch failed: ' || sqlerrm,
          pending_request_id = null, pending_since = null
      where id = p_feed_id;
    return coalesce(v_result, jsonb_build_object('status', 'error', 'error', sqlerrm));
  end;

  update public.ical_feeds
    set pending_request_id = v_req_id, pending_since = now()
    where id = p_feed_id;

  return coalesce(v_result, jsonb_build_object('status', 'requested'));
end;
$$;

-- ---------------------------------------------------------------------
-- The six "no link" tables that stayed nullable in 0043 now require a
-- resort: every writer above and every client insert supplies one.
-- Backfill any stragglers first (outbox from its reservation, the rest to
-- the first property, as 0043 did), with user triggers disabled for the
-- same reason as 0043.

do $$
declare
  v_first uuid;
  t text;
begin
  select id into v_first from public.properties order by created_at limit 1;

  alter table public.outbox disable trigger user;
  update public.outbox o
     set property_id = r.property_id
    from public.reservations r
   where r.id = o.reservation_id
     and o.property_id is null;
  alter table public.outbox enable trigger user;

  foreach t in array array['coupons','staff_shifts','leave_requests',
                           'attendance_records','tasks']
  loop
    execute format('alter table public.%I disable trigger user', t);
    execute format('update public.%I set property_id = $1 where property_id is null', t)
      using v_first;
    execute format('alter table public.%I enable trigger user', t);
  end loop;

  foreach t in array array['coupons','outbox','staff_shifts','leave_requests',
                           'attendance_records','tasks']
  loop
    execute format('alter table public.%I alter column property_id set not null', t);
  end loop;
end;
$$;

-- A coupon code is unique within its resort, not across the platform:
-- one resort's SUMMER10 must not block another's.
alter table public.coupons drop constraint coupons_code_key;
alter table public.coupons add constraint coupons_property_code_key unique (property_id, code);

-- ---------------------------------------------------------------------
-- maintenance-photos bucket. Objects live at `{guest uid}/{file}` (see
-- MaintenanceRepository.uploadPhoto) and are uploaded before the issue
-- exists, so the path names no resort. Staff read a photo only once an
-- issue at their resort links to it (maintenance_issues.photo_url) and
-- the photo sits in that stay's guest's own folder -- so a guest cannot
-- expose someone else's upload by pasting its path into a report. The
-- guest's own upload/read policies (0035) are unchanged.

drop policy if exists maintenance_photos_staff_read on storage.objects;
create policy maintenance_photos_staff_read on storage.objects
  for select to authenticated
  using (bucket_id = 'maintenance-photos'
         and exists (
           select 1
             from public.maintenance_issues mi
             join public.reservations r on r.id = mi.reservation_id
            where mi.photo_url = objects.name
              and r.customer_id::text = (storage.foldername(objects.name))[1]
              and public.has_resort_role(mi.property_id, false,
                    'owner','admin','staff','accountant')));
