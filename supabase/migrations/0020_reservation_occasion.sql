-- A free-text note captured at hold time (create_hold), purely
-- informational -- never read by get_quote or any pricing path. See
-- docs/superpowers/specs/2026-08-13-single-property-onboarding-design.md
-- section 3.2.

alter table public.reservations add column occasion text;

-- Drop the old 7-parameter version so we can create the new 8-parameter one
-- without ambiguity (same pattern as in 0012_coupons.sql).
drop function if exists
  public.create_hold(uuid, date, date, int, uuid, numeric, text);

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
     quote, hold_expires_at, created_by, occasion)
  values
    (p_unit_id, p_slot_type_id, v_period, 'booking', 'hold', v_uid, p_guests,
     v_quote, now() + interval '15 minutes', v_uid, p_occasion)
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
-- C1 sweep: same defense-in-depth pattern as 0012_coupons.sql (see notes there).
revoke execute on function public.create_hold from public;
revoke execute on function public.create_hold from anon;
