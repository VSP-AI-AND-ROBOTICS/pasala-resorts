-- Check-in, the live running bill, and checkout-with-balance-payment.
-- `get_quote`/`create_hold`/`confirm_booking` are completely untouched by
-- this feature -- everything ordered during the stay (food, activities)
-- settles here, at checkout, never by re-touching the original quote. See
-- this repo's plan/spec docs for the reasoning.
--
-- Both `check_in_booking` and `checkout_booking` stamp their timestamp
-- with `clock_timestamp()`, not `now()` -- `now()` is frozen at
-- transaction start, so a checkout issued in the same transaction as its
-- own check-in (as pgTAP's tests do) would set `checked_out_at` equal to
-- `checked_in_at` and fail `reservations_checkout_after_checkin`'s strict
-- `>` check even though the two calls happened in the intended order.

-- Staff-or-above only (reception) -- moves a paid booking to `checked_in`
-- once the guest has physically arrived and been verified against their
-- QR/booking details, per the doc's "Arrival / Check-In" step.
create function public.check_in_booking(
  p_reservation_id uuid
) returns public.reservations
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_row public.reservations;
begin
  if not public.is_staff_or_above() then
    raise exception 'not permitted' using errcode = 'P0008';
  end if;

  select * into v_row from public.reservations
  where id = p_reservation_id for update;

  if not found then
    raise exception 'reservation not found' using errcode = 'P0002';
  end if;

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

-- Computed fresh on every call, never stored: the stay's quoted total plus
-- live sums of every non-cancelled food order and activity booking, minus
-- payments already captured (`advance` at booking time, any prior
-- `balance` payments -- though in practice checkout only ever happens
-- once). Callable by the owning customer (the "Current Charges" screen)
-- or staff-or-above (front desk, at checkout time).
create function public.current_charges(
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

  if v_res.customer_id is distinct from v_uid and not public.is_staff_or_above() then
    raise exception 'not permitted' using errcode = 'P0008';
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

-- Staff-or-above only. Requires `checked_in`, requires the payment covers
-- the exact outstanding balance from `current_charges` (never trusts a
-- client-supplied amount, same discipline as `confirm_booking`), records a
-- `payments` row with `kind = 'balance'` -- the first use of that enum
-- value in this codebase -- and moves the reservation to `checked_out`.
create function public.checkout_booking(
  p_reservation_id uuid,
  p_payment_ref    text,
  p_amount         numeric
) returns public.reservations
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_row     public.reservations;
  v_charges jsonb;
  v_balance numeric(12,2);
begin
  if not public.is_staff_or_above() then
    raise exception 'not permitted' using errcode = 'P0008';
  end if;

  select * into v_row from public.reservations
  where id = p_reservation_id for update;

  if not found then
    raise exception 'reservation not found' using errcode = 'P0002';
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

grant execute on function public.check_in_booking(uuid) to authenticated;
grant execute on function public.current_charges(uuid) to authenticated;
grant execute on function public.checkout_booking(uuid, text, numeric) to authenticated;

revoke execute on function public.check_in_booking(uuid) from public;
revoke execute on function public.check_in_booking(uuid) from anon;
revoke execute on function public.current_charges(uuid) from public;
revoke execute on function public.current_charges(uuid) from anon;
revoke execute on function public.checkout_booking(uuid, text, numeric) from public;
revoke execute on function public.checkout_booking(uuid, text, numeric) from anon;
