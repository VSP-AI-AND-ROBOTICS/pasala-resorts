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
