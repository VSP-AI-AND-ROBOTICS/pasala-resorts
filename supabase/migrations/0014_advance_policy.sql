-- The advance/balance split. `properties.advance_pct` is the minimum share
-- of the quoted total a customer must pay to confirm a hold; the rest is
-- collected later as a `balance` payment (out of scope here -- this
-- migration only widens what `confirm_booking` accepts). The default of
-- 100 collapses the accepted range to a single point, the exact total, so
-- every property that never sets `advance_pct` keeps today's behaviour
-- byte-for-byte.

alter table public.properties
  add column advance_pct numeric(5,2) not null default 100
    check (advance_pct > 0 and advance_pct <= 100);

-- `confirm_booking`'s old check was `p_amount is distinct from
-- (quote ->> 'total')::numeric` -- an equality. This replaces it with a
-- range: `p_amount` must be at least `advance_pct` percent of the quoted
-- total, and at most the total itself (never MORE than what was quoted).
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

  -- m8/I2 closed a NULL-comparison hole where `p_amount <> (NULL ->>
  -- 'total')::numeric` evaluates to NULL, not TRUE, so the raise below it
  -- was silently skipped for a quote-less hold. Reopening that hole here
  -- would be exactly the trap this task's brief calls out by name.
  --
  -- These two guards are each a plain `x IS NULL` test, which -- unlike an
  -- equality or `<>` mixed into the same expression -- can never itself be
  -- NULL. In three-valued logic `TRUE OR anything` is always TRUE, so
  -- whichever guard is true here decides the whole `if` deterministically
  -- regardless of what the (possibly NULL-valued) other guard would have
  -- evaluated to. A NULL `p_amount` or a NULL `quote` is therefore
  -- guaranteed to hit this raise -- the same guarantee `is distinct from`
  -- gave the old equality check, just carried over to a range instead.
  if p_amount is null or v_row.quote is null then
    raise exception 'payment amount % does not match quoted total %',
      p_amount, (v_row.quote ->> 'total')
      using errcode = 'P0009';
  end if;

  -- Past the two guards above, `v_row.quote` is known non-NULL, so `total`
  -- is a real number, not NULL -- `<`/`>` against it below are ordinary,
  -- NULL-safe comparisons, not the NULL-swallowing kind I2/m8 warn about.
  v_total := (v_row.quote ->> 'total')::numeric;

  select coalesce(p.advance_pct, 100) into v_advance_pct
  from public.units u
  join public.properties p on p.id = u.property_id
  where u.id = v_row.unit_id;

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

grant execute on function public.confirm_booking to authenticated;
-- C1 sweep: same defense-in-depth as 0013's `compute_refund`/
-- `cancel_booking` -- see 0018_ical.sql's header comment on
-- `ical_import_event` for the full reasoning behind revoking PUBLIC
-- EXECUTE consistently across every phase-2 function.
revoke execute on function public.confirm_booking from public;
revoke execute on function public.confirm_booking from anon;
