create function public.create_hold(
  p_unit_id        uuid,
  p_from           date,
  p_to             date,
  p_guests         int,
  p_slot_type_id   uuid default null,
  p_expected_total numeric default null
) returns public.reservations
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid    uuid := auth.uid();
  v_mode   public.booking_mode;
  v_period tstzrange;
  v_quote  jsonb;
  v_row    public.reservations;
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
  v_quote  := public.get_quote(p_unit_id, v_period, p_guests, p_slot_type_id);

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

  return v_row;
end;
$$;

create function public.confirm_booking(
  p_reservation_id uuid,
  p_payment_ref    text,
  p_amount         numeric
) returns public.reservations
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_row public.reservations;
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode = 'P0008';
  end if;

  select * into v_row from public.reservations
  where id = p_reservation_id for update;

  if not found then
    raise exception 'reservation not found' using errcode = 'P0002';
  end if;

  if v_row.customer_id is distinct from v_uid and not public.is_admin() then
    raise exception 'not permitted' using errcode = 'P0008';
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

  -- Phase 1 collects the full quoted total. When phase 2 introduces the
  -- advance/balance split this becomes a range check against the advance
  -- policy, but it must never simply trust the client's number.
  --
  -- m8: `p_amount <> (NULL ->> 'total')::numeric` is NULL, not TRUE, when
  -- `v_row.quote` is NULL -- the same NULL-comparison family as I2/the
  -- Task-8 Critical -- so the raise below was silently skipped and ANY
  -- amount was accepted against a quote-less hold. `is distinct from` is
  -- NULL-safe on both sides, so a NULL quote or a NULL amount now compares
  -- as "different" rather than "unknown".
  if p_amount is null
     or v_row.quote is null
     or p_amount is distinct from (v_row.quote ->> 'total')::numeric then
    raise exception 'payment amount % does not match quoted total %',
      p_amount, (v_row.quote ->> 'total')
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

create function public.cancel_booking(
  p_reservation_id uuid,
  p_reason         text
) returns public.reservations
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_row public.reservations;
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode = 'P0008';
  end if;

  select * into v_row from public.reservations
  where id = p_reservation_id for update;

  if not found then
    raise exception 'reservation not found' using errcode = 'P0002';
  end if;

  if v_row.customer_id is distinct from v_uid and not public.is_admin() then
    raise exception 'not permitted' using errcode = 'P0008';
  end if;

  if v_row.status = 'cancelled' then
    return v_row;
  end if;

  update public.reservations
     set status = 'cancelled',
         cancel_reason = p_reason,
         cancelled_at = now()
   where id = p_reservation_id
  returning * into v_row;

  return v_row;
end;
$$;

-- Admin blocking. All ranges land or none do: one transaction, one statement.
create function public.block_dates(
  p_unit_id uuid,
  p_ranges  daterange[],
  p_reason  text
) returns setof public.reservations
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_range daterange;
begin
  if not public.is_admin() then
    raise exception 'not permitted' using errcode = 'P0008';
  end if;

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

create function public.release_expired_holds()
returns int
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_count int;
begin
  update public.reservations
     set status = 'cancelled',
         cancel_reason = 'hold expired',
         cancelled_at = now()
   where status = 'hold'
     and hold_expires_at < now();
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

revoke execute on function public.release_expired_holds() from public;
revoke execute on function public.release_expired_holds() from anon, authenticated;

grant execute on function public.create_hold      to authenticated;
grant execute on function public.confirm_booking  to authenticated;
grant execute on function public.cancel_booking   to authenticated;
grant execute on function public.block_dates      to authenticated;

select cron.schedule(
  'release-expired-holds', '* * * * *',
  $$select public.release_expired_holds()$$);
