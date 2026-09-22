-- Carried-forward fix from Task 7's review: an abandoned or expired hold
-- never released its coupon redemption. `cancel_booking` and
-- `release_expired_holds` only ever flipped `reservations.status` to
-- 'cancelled' -- neither touched `coupons.redeemed_count` or deleted the
-- `coupon_redemptions` row, so a single abandoned hold against a
-- `max_redemptions = 1` coupon exhausted it FOREVER, for every future
-- customer, not just the one who abandoned it.
--
-- `release_reservation_coupon` is the single place this is fixed, called
-- from both write paths that can move a reservation to 'cancelled'. It is
-- self-idempotent by construction: `DELETE ... RETURNING` only finds a row
-- (and only then decrements) the FIRST time it runs for a given
-- reservation -- a second call for the same reservation deletes nothing,
-- so nothing decrements a second time. This is a stronger guarantee than
-- relying on the callers' own "already cancelled" guards, though both of
-- those still also gate on the correct thing (`cancel_booking`'s early
-- return, `release_expired_holds`'s `where status = 'hold'`).
create function public.release_reservation_coupon(p_reservation_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_coupon_id uuid;
begin
  delete from public.coupon_redemptions
   where reservation_id = p_reservation_id
  returning coupon_id into v_coupon_id;

  if v_coupon_id is not null then
    -- `greatest(..., 0)` is defence in depth, not the primary safety net --
    -- the DELETE above is what actually prevents a double-decrement. This
    -- just makes "redeemed_count must never go negative" true even if some
    -- future caller ever invokes this function without a matching
    -- redemption row existing.
    update public.coupons
       set redeemed_count = greatest(redeemed_count - 1, 0)
     where id = v_coupon_id;
  end if;
end;
$$;

-- Internal helper only, called from within the SECURITY DEFINER functions
-- below (which run with this function's owner privileges regardless of the
-- calling role) -- never meant to be invoked directly by a client.
revoke execute on function public.release_reservation_coupon(uuid)
  from public;
revoke execute on function public.release_reservation_coupon(uuid)
  from anon, authenticated;

-- `cancel_booking`, unchanged apart from the one added `perform` call right
-- before returning. Everything else -- ownership check, idempotent early
-- return for an already-cancelled reservation, refund bookkeeping from
-- migration 0014 -- is identical.
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

  if v_row.customer_id is distinct from v_uid and not public.is_admin() then
    raise exception 'not permitted' using errcode = 'P0008';
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

grant execute on function public.cancel_booking to authenticated;
-- C1 sweep: repeated here for the same reason `release_expired_holds`
-- below repeats its own revoke after being redefined -- see 0013's first
-- revoke of `cancel_booking` for the full reasoning.
revoke execute on function public.cancel_booking from public;
revoke execute on function public.cancel_booking from anon;

-- `release_expired_holds`, the unattended path an ABANDONED hold actually
-- takes -- nobody ever calls `cancel_booking` for it, the 15-minute expiry
-- just passes and the pg_cron job sweeps it. Before this fix that sweep
-- left the coupon's `redeemed_count` incremented forever. Rewritten as a
-- `FOR ... IN UPDATE ... RETURNING id LOOP` (rather than a plain bulk
-- UPDATE) so each released reservation's coupon can be individually
-- released too, in the SAME transaction as the status change.
create or replace function public.release_expired_holds()
returns int
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_count int := 0;
  v_id    uuid;
begin
  for v_id in
    update public.reservations
       set status = 'cancelled',
           cancel_reason = 'hold expired',
           cancelled_at = now()
     where status = 'hold'
       and hold_expires_at < now()
    returning id
  loop
    perform public.release_reservation_coupon(v_id);
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;

revoke execute on function public.release_expired_holds() from public;
revoke execute on function public.release_expired_holds()
  from anon, authenticated;
