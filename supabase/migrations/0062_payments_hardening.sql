-- Payments hardening (final review minor 1). When payments-verify and
-- payments-webhook settle the same unapplied payment at the same moment,
-- both used to be told `refund_needed` and both asked Razorpay for the
-- refund. Razorpay refused the second, so no money was lost, but it logged a
-- failed refund.
--
-- payment_order_settle now hands the refund to one caller: it records a
-- claim (refund_claimed_at) in the same locked transaction and answers
-- `refund_needed` true only to the caller that took it. A caller whose
-- refund fails gives the claim back with payment_order_refund_release, so
-- the next settle call tries again; a claim that is never given back (the
-- function died mid-way) lapses after 10 minutes. The Edge Functions also
-- send a per-payment idempotency key with the refund, so a repeat after a
-- lapsed claim returns Razorpay's first refund instead of a second one.

alter table public.payment_orders
  add column refund_claimed_at timestamptz;

comment on column public.payment_orders.refund_claimed_at is
  'When payment_order_settle handed the refund of this unapplied payment to a caller; '
  'cleared by payment_order_refund_release, lapses after 10 minutes.';

-- payment_order_settle: copied from its latest definition,
-- 0055_online_payments.sql; the changes are marked 0062. The body that
-- applies the payment is unchanged, only nested under `if` so that both
-- the first and a repeated call reach the refund claim at the end.
create or replace function public.payment_order_settle(
  p_razorpay_order_id   text,
  p_razorpay_payment_id text
) returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_order       public.payment_orders;
  v_res         public.reservations;
  v_payment     uuid;
  v_reason      text;
  v_claimed     boolean := false;                                   -- 0062
  v_prev_claims text := current_setting('request.jwt.claims', true);
  v_prev_sub    text := current_setting('request.jwt.claim.sub', true);
  v_prev_gw     text := current_setting('app.payment_gateway', true);
begin
  if p_razorpay_payment_id is null or btrim(p_razorpay_payment_id) = '' then
    raise exception 'a Razorpay payment id is required' using errcode = 'P0009';
  end if;

  select * into v_order from public.payment_orders
   where razorpay_order_id = p_razorpay_order_id
   for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'payment_order_not_found';
  end if;

  -- payments-verify and payments-webhook both land here for one payment:
  -- an order that is already settled is reported, never applied twice.
  -- 0062: it still goes on to the refund claim below.
  if v_order.status not in ('paid', 'unapplied', 'refunded') then
    select * into v_res from public.reservations
     where id = v_order.reservation_id
     for update;

    -- Captured before release_expired_holds swept the hold: the dates are
    -- still held for this guest, so the payment wins (spec decision 9).
    if v_order.kind = 'advance' and v_res.status = 'hold' and v_res.hold_expires_at < now() then
      update public.reservations
         set hold_expires_at = now() + interval '1 minute'
       where id = v_res.id;
    end if;

    if (v_order.kind = 'advance' and v_res.status <> 'hold')
       or (v_order.kind = 'balance' and v_res.status <> 'checked_in') then
      v_reason := format('reservation is %s', v_res.status);
    else
      begin
        -- Act as the order's guest for the rest of this transaction, so the
        -- existing functions run their guest path unchanged (spec decision 7).
        perform set_config('request.jwt.claim.sub', v_order.customer_id::text, true);
        perform set_config('request.jwt.claims',
          json_build_object('sub', v_order.customer_id, 'role', 'authenticated')::text, true);
        perform set_config('app.payment_gateway', 'razorpay', true);

        if v_order.kind = 'advance' then
          perform public.confirm_booking(v_order.reservation_id, btrim(p_razorpay_payment_id), v_order.amount);
        else
          perform public.checkout_booking(v_order.reservation_id, btrim(p_razorpay_payment_id), v_order.amount, 'gateway');
        end if;

        select id into v_payment from public.payments
         where gateway = 'razorpay' and gateway_ref = btrim(p_razorpay_payment_id);
      exception when others then
        -- Money was taken but cannot be applied: unapplied, refunded by the
        -- caller (spec decision 10). The block's own settings roll back.
        v_reason  := sqlerrm;
        v_payment := null;
      end;
    end if;

    perform set_config('request.jwt.claim.sub', coalesce(v_prev_sub, ''), true);
    perform set_config('request.jwt.claims', coalesce(v_prev_claims, ''), true);
    perform set_config('app.payment_gateway', coalesce(v_prev_gw, ''), true);

    update public.payment_orders
       set status              = case when v_payment is null then 'unapplied' else 'paid' end
                                   ::public.payment_order_status,
           razorpay_payment_id = btrim(p_razorpay_payment_id),
           payment_id          = v_payment,
           failure_reason      = left(v_reason, 500),
           updated_at          = now()
     where id = v_order.id
    returning * into v_order;
  end if;

  -- 0062: the refund of an unapplied payment goes to one caller. The row
  -- is locked (for update above), so a concurrent call waits here and then
  -- sees the claim. A claim older than 10 minutes has lapsed.
  if v_order.status = 'unapplied'
     and cardinality(v_order.refund_ids) = 0
     and (v_order.refund_claimed_at is null
          or v_order.refund_claimed_at < now() - interval '10 minutes') then
    update public.payment_orders
       set refund_claimed_at = now(),
           updated_at        = now()
     where id = v_order.id
    returning * into v_order;
    v_claimed := true;
  end if;

  return public.payment_order_json(v_order)
         || jsonb_build_object('refund_needed', v_claimed);          -- 0062
end;
$$;
revoke execute on function public.payment_order_settle(text, text) from public, anon, authenticated;
grant execute on function public.payment_order_settle(text, text) to service_role;

-- Service role only: gives back the refund claim of a refund that failed,
-- so the next settle call tries it again. A no-op once a refund is recorded.
create function public.payment_order_refund_release(
  p_razorpay_payment_id text
) returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  update public.payment_orders
     set refund_claimed_at = null,
         updated_at        = now()
   where razorpay_payment_id = btrim(p_razorpay_payment_id)
     and refund_claimed_at is not null
     and cardinality(refund_ids) = 0;
end;
$$;
revoke execute on function public.payment_order_refund_release(text) from public, anon, authenticated;
grant execute on function public.payment_order_refund_release(text) to service_role;
