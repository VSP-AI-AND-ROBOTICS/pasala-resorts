-- I1: `checkout_booking` was staff-or-above only, but the customer-facing
-- checkout screen in the Guest Stay Experience feature calls it directly --
-- every self-checkout attempt failed with "not permitted." The source
-- document's own checkout step ("Customer selects Checkout... Customer
-- pays remaining balance") describes guest self-checkout, matching the
-- pattern this app already uses for the original booking flow
-- (`confirm_booking` is likewise callable by the owning customer, not
-- staff). Widened here rather than in 0037 directly, following this
-- repo's own convention of layering a fix as its own migration
-- (`0013_refund_policy.sql`/`0016_release_coupon_on_cancel.sql`) rather
-- than editing an already-applied file.
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

  if v_row.customer_id is distinct from v_uid and not public.is_staff_or_above() then
    raise exception 'not permitted' using errcode = 'P0008';
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

revoke execute on function public.checkout_booking(uuid, text, numeric) from public;
revoke execute on function public.checkout_booking(uuid, text, numeric) from anon;
