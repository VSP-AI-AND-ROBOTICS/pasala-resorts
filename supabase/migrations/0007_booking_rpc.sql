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
  v_period tstzrange;
  v_quote  jsonb;
  v_row    public.reservations;
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode = 'P0008';
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
  if p_amount is null
     or p_amount <> (v_row.quote ->> 'total')::numeric then
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
