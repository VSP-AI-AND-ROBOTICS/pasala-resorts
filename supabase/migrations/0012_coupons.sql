-- Coupons, applied server-side inside the quote. `get_quote` is where the
-- server already owns every price the customer sees, so the discount is
-- computed there -- never in Dart -- and `create_hold` re-quotes internally
-- using the SAME coupon code, so a couponed hold is checked against the
-- SAME discounted total the customer was quoted (see the trailing
-- `p_coupon_code` threading below: skipping it here is exactly the trap
-- that would make every couponed booking fail create_hold's own
-- expected-total check with P0007).

create type public.coupon_kind as enum ('percent', 'fixed');

create table public.coupons (
  id                uuid primary key default gen_random_uuid(),
  code              text not null unique,
  kind              public.coupon_kind not null,
  value             numeric(12,2) not null check (value >= 0),
  valid_from        timestamptz,
  valid_to          timestamptz,
  max_redemptions   int check (max_redemptions is null or max_redemptions > 0),
  -- Denormalized, incremented atomically (see `create_hold` below) rather
  -- than derived from `count(*) from coupon_redemptions` on every hold --
  -- that would be exactly the read-then-write race this column exists to
  -- avoid. It is the single source of truth for "how many times has this
  -- coupon been used," checked and incremented in the same UPDATE
  -- statement that reserves the slot.
  redeemed_count    int not null default 0 check (redeemed_count >= 0),
  min_booking_value numeric(12,2),
  -- NULL means any customer. Set, it restricts the coupon to exactly one
  -- customer -- redeeming it as anyone else must look exactly like the
  -- code not existing (P0010), not reveal that a customer-restricted code
  -- exists for someone else.
  customer_id       uuid references auth.users(id) on delete cascade,
  is_active         boolean not null default true,
  created_at        timestamptz not null default now(),
  constraint coupons_valid_range check (
    valid_from is null or valid_to is null or valid_to >= valid_from
  ),
  constraint coupons_percent_range check (
    kind <> 'percent' or (value >= 0 and value <= 100)
  )
);

grant select on public.coupons to anon, authenticated;
grant insert, update, delete on public.coupons to authenticated;

alter table public.coupons enable row level security;

-- Defense-in-depth only: `get_quote`/`create_hold` are SECURITY DEFINER and
-- do their own explicit active/customer-scoping checks (see
-- `resolve_coupon` below) rather than relying on RLS, since a SECURITY
-- DEFINER function executes as its owner and would otherwise bypass this
-- policy anyway. This still matters for any future direct client read.
create policy coupons_read_active on public.coupons
  for select to anon, authenticated
  using (is_active and (customer_id is null or customer_id = auth.uid()));

create policy coupons_admin_write on public.coupons
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

create table public.coupon_redemptions (
  id             uuid primary key default gen_random_uuid(),
  coupon_id      uuid not null references public.coupons(id) on delete cascade,
  -- A reservation can carry at most one redemption -- this is what makes
  -- "a redemption cannot exist without a reservation" a real guarantee
  -- rather than a convention: the row is inserted in the same transaction
  -- as the hold it belongs to, and this UNIQUE stops it ever being
  -- attached to a second one.
  reservation_id uuid not null unique
    references public.reservations(id) on delete cascade,
  customer_id    uuid not null references auth.users(id) on delete cascade,
  amount         numeric(12,2) not null check (amount >= 0),
  redeemed_at    timestamptz not null default now()
);

create index coupon_redemptions_coupon_idx
  on public.coupon_redemptions(coupon_id);

grant select on public.coupon_redemptions to authenticated;
grant insert on public.coupon_redemptions to authenticated;

alter table public.coupon_redemptions enable row level security;

create policy coupon_redemptions_select on public.coupon_redemptions
  for select to authenticated
  using (public.is_staff_or_above() or customer_id = auth.uid());

create policy coupon_redemptions_admin_write on public.coupon_redemptions
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- Resolves and validates a coupon code for customer `p_uid` against a
-- booking worth `p_amount` (subtotal + cleaning_fee, pre-discount). Shared
-- by `get_quote` (a read-only preview) and `create_hold` (which re-runs
-- this same validation before atomically consuming a redemption slot).
-- Raises exactly one of P0010-P0013; never returns a row silently invalid.
create function public.resolve_coupon(
  p_code   text,
  p_uid    uuid,
  p_amount numeric
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
    and c.is_active
    -- A coupon restricted to another customer must look exactly like it
    -- doesn't exist -- P0010, not a different code, and not visible in the
    -- WHERE clause result at all (no separate "wrong customer" branch that
    -- could leak which codes exist for someone else).
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

-- `create or replace function` cannot change an existing function's
-- signature -- adding a trailing parameter would otherwise leave the old
-- 4-argument `get_quote` in place as a second, stale overload that every
-- existing 4-argument call site keeps silently resolving to (never
-- gaining coupon support, never hitting this file's fix). Dropping the
-- old signature first is what makes "existing calls keep working" mean
-- "keep working against this one updated function," not "keep working
-- against a shadowed old one."
drop function if exists public.get_quote(uuid, tstzrange, int, uuid);

-- Applies `p_coupon_code` on top of the rate-rule pricing already computed
-- above. Discount rounds to 2 decimal places and is capped at
-- `subtotal + cleaning_fee` (via `least`) so a coupon can never drive the
-- total below zero, no matter how large `value` is misconfigured to be.
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
  v_unit      public.units;
  v_tz        text;
  v_rule      public.rate_rules;
  v_date      date;
  v_end_date  date;
  v_lines     jsonb := '[]'::jsonb;
  v_subtotal  numeric(12,2) := 0;
  v_cleaning  numeric(12,2) := 0;
  v_extra     int;
  v_extra_amt numeric(12,2);
  v_coupon    public.coupons;
  v_discount  numeric(12,2) := 0;
begin
  select * into v_unit from public.units where id = p_unit_id and is_active;
  if not found then
    raise exception 'unit not found or inactive' using errcode = 'P0002';
  end if;

  select p.timezone into v_tz
  from public.properties p where p.id = v_unit.property_id;

  if p_guests is null or p_guests < 1 or p_guests > v_unit.capacity_max then
    raise exception 'guest count out of range (max %)', v_unit.capacity_max
      using errcode = 'P0003';
  end if;

  v_extra := greatest(p_guests - v_unit.capacity_base, 0);

  -- One line per calendar night (nightly) or per slot day (slot bookings).
  v_date     := (lower(p_period) at time zone v_tz)::date;
  v_end_date := (upper(p_period) at time zone v_tz)::date;
  if p_slot_type_id is not null then
    v_end_date := v_date + 1;   -- a slot occupies exactly one dated line
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
    v_coupon := public.resolve_coupon(p_coupon_code, auth.uid(),
                                       v_subtotal + v_cleaning);
    v_discount := case v_coupon.kind
      when 'percent' then round((v_subtotal + v_cleaning) * v_coupon.value / 100, 2)
      when 'fixed'   then round(v_coupon.value, 2)
    end;
    -- Never let a coupon drive the total below zero, regardless of how
    -- `value` is configured.
    v_discount := least(v_discount, v_subtotal + v_cleaning);
  end if;

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
    'total',        v_subtotal + v_cleaning - v_discount
  );
end;
$$;

grant execute on function public.get_quote to anon, authenticated;

-- `create_hold` re-quotes internally to price the hold; it must pass
-- `p_coupon_code` through to that internal `get_quote` call. Skipping this
-- would re-quote WITHOUT the coupon, so `v_quote ->> 'total'` would come
-- back higher than `p_expected_total` (which the client computed WITH the
-- discount applied) and every couponed booking would fail with P0007 --
-- the exact trap this task's brief calls out.
--
-- Same reasoning as `get_quote` above: drop the old 6-argument signature
-- first so no stale, coupon-blind overload survives alongside this one.
drop function if exists
  public.create_hold(uuid, date, date, int, uuid, numeric);

create or replace function public.create_hold(
  p_unit_id        uuid,
  p_from           date,
  p_to             date,
  p_guests         int,
  p_slot_type_id   uuid default null,
  p_expected_total numeric default null,
  p_coupon_code    text default null
) returns public.reservations
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid       uuid := auth.uid();
  v_mode      public.booking_mode;
  v_period    tstzrange;
  v_quote     jsonb;
  v_row       public.reservations;
  v_coupon_id uuid;
  v_discount  numeric(12,2);
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode = 'P0008';
  end if;

  -- I3: `booking_mode` was enforced nowhere -- a slot-only unit could be
  -- held for three nights, and a nightly-only unit could be held with a
  -- slot (occupying just 09:00-18:00 instead of 14:00->11:00, leaving the
  -- very same physical room bookable overnight -- a real double
  -- -allocation `reservations_no_overlap` cannot see, since the two
  -- periods never overlap). Enforced here in SQL, not just in the client,
  -- so a buggy or malicious caller invoking this RPC directly is held to
  -- the same rule. If the unit doesn't exist `v_mode` stays NULL, matching
  -- neither branch below, so `build_period`'s own "unit not found" raise
  -- still fires -- this doesn't duplicate that check.
  select booking_mode into v_mode from public.units where id = p_unit_id;
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
     quote, hold_expires_at, created_by)
  values
    (p_unit_id, p_slot_type_id, v_period, 'booking', 'hold', v_uid, p_guests,
     v_quote, now() + interval '15 minutes', v_uid)
  returning * into v_row;

  if p_coupon_code is not null then
    -- Race-safe redemption: the max_redemptions check and the increment
    -- are the SAME statement. Two concurrent holds racing for the last
    -- slot both run this UPDATE; Postgres's row-level lock on the coupon
    -- row serializes them -- whichever commits first moves
    -- redeemed_count to the limit, and the second's WHERE clause is
    -- re-evaluated against that committed value once its lock is granted,
    -- so it affects zero rows and this raises P0012. There is no separate
    -- SELECT anywhere in this path for a second transaction to read stale
    -- data from -- that gap is exactly what a naive
    -- "SELECT count(*) < max_redemptions, THEN INSERT" implementation
    -- would leave open.
    update public.coupons
       set redeemed_count = redeemed_count + 1
     where code = p_coupon_code
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

grant execute on function public.create_hold to authenticated;
