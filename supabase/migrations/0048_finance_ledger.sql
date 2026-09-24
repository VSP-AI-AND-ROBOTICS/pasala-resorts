-- Finance ledger and collections (REQ-07): how every payment was taken
-- and by whom, and four read-only reports over one resort's money.
-- See docs/superpowers/specs/2026-09-25-finance-ledger-design.md.
--
-- No new tables and no triggers: the reports work every figure out from
-- payments, reservations, food_orders, activity_bookings and
-- food_activity_sales. Error codes raised: P0008, P0002, P0009 (a guest
-- recording a desk method, a wrong amount), P0020 not_a_member, P0022
-- resort_suspended.

create type public.payment_method as enum
  ('gateway', 'cash', 'card', 'upi', 'bank_transfer', 'other');

-- ---------------------------------------------------------------------
-- payments: every payment so far went through the (mock) gateway, so the
-- default is also the right backfill. `reference` is the receipt,
-- card-slip or UTR number typed at the desk; it is not unique, because
-- two resorts (or two bookings) can both issue receipt 001.
-- `recorded_by` defaults to the caller, which for a gateway payment is
-- the guest who paid. auth.uid() is null while this migration runs, so
-- existing rows stay null (unknown).
alter table public.payments
  add column method public.payment_method not null default 'gateway',
  add column reference text
    constraint payments_reference_length check (reference is null or length(reference) <= 64),
  add column recorded_by uuid default auth.uid()
    references public.profiles(id) on delete set null;

create index payments_property_created_idx on public.payments (property_id, created_at);

-- ---------------------------------------------------------------------
-- food_activity_sales.payment_method: free text (no screen ever set it)
-- becomes the enum. Walk-in sales are front-desk money, so never gateway.
create function public.payment_method_from_text(p_text text)
returns public.payment_method
language sql
immutable
set search_path = public, pg_temp
as $$
  select (case lower(btrim(p_text))
    when 'cash'          then 'cash'
    when 'card'          then 'card'
    when 'upi'           then 'upi'
    when 'bank transfer' then 'bank_transfer'
    when 'bank_transfer' then 'bank_transfer'
    when 'neft'          then 'bank_transfer'
    when 'imps'          then 'bank_transfer'
    else 'other'
  end)::public.payment_method;
$$;
revoke execute on function public.payment_method_from_text(text) from public, anon;
grant execute on function public.payment_method_from_text(text) to authenticated;

alter table public.food_activity_sales
  alter column payment_method type public.payment_method
    using public.payment_method_from_text(payment_method);
alter table public.food_activity_sales
  alter column payment_method set default 'cash',
  alter column payment_method set not null,
  add constraint food_activity_sales_not_gateway check (payment_method <> 'gateway');

-- ---------------------------------------------------------------------
-- checkout_booking gains p_method. Postgres cannot add a parameter with
-- CREATE OR REPLACE, so the three-argument function is dropped and the
-- four-argument one created and re-granted, as 0045 did for the report
-- functions. Existing three-argument callers (the app, pgTAP) resolve to
-- it through the default. The body is copied from its latest definition,
-- 0047_room_status.sql (it marks the room dirty); the method handling is
-- marked 0048.
drop function if exists public.checkout_booking(uuid, text, numeric);

create function public.checkout_booking(
  p_reservation_id uuid,
  p_payment_ref    text,
  p_amount         numeric,
  p_method         public.payment_method default 'gateway'
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
  v_method  public.payment_method := coalesce(p_method, 'gateway');   -- 0048
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

  -- 0048: only resort staff record a desk method, and only at the
  -- booking's own resort. A guest's own checkout (the branch above
  -- skipped) can only be gateway; a staff member checking out their own
  -- stay passes this check. Before the early return, so a guest never
  -- gets a desk method accepted, even as a no-op.
  if v_method <> 'gateway'
     and not public.has_resort_role(v_row.property_id, true,
                                    'owner','admin','staff','accountant') then
    raise exception 'desk payment methods are recorded by resort staff'
      using errcode = 'P0009';
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
    if v_method = 'gateway' then
      insert into public.payments
        (reservation_id, amount, kind, status, gateway, gateway_ref, method, recorded_by)
      values (p_reservation_id, v_balance, 'balance', 'succeeded', 'mock', p_payment_ref,
              'gateway', v_uid);
    else
      -- 0048: one balance payment per booking, so 'desk-<id>' stays unique
      -- under unique (gateway, gateway_ref) and doubles as a retry guard.
      -- The receipt/UTR number goes in `reference`, which is not unique.
      insert into public.payments
        (reservation_id, amount, kind, status, gateway, gateway_ref, method, reference, recorded_by)
      values (p_reservation_id, v_balance, 'balance', 'succeeded', 'desk',
              'desk-' || p_reservation_id, v_method,
              nullif(btrim(p_payment_ref), ''), v_uid);
    end if;
  end if;

  update public.reservations
     set status = 'checked_out', checked_out_at = clock_timestamp()
   where id = p_reservation_id
  returning * into v_row;

  -- 0047: the room needs cleaning now.
  insert into public.unit_room_status as s
    (unit_id, property_id, state, reason, updated_by, updated_at)
  values (v_row.unit_id, v_row.property_id, 'dirty', null, v_uid, now())
  on conflict (unit_id) do update
    set state      = 'dirty',
        reason     = null,
        updated_by = excluded.updated_by,
        updated_at = excluded.updated_at
    where s.state <> 'out_of_order';

  return v_row;
end;
$$;

revoke execute on function public.checkout_booking(uuid, text, numeric, public.payment_method) from public, anon;
grant execute on function public.checkout_booking(uuid, text, numeric, public.payment_method) to authenticated;

-- ---------------------------------------------------------------------
-- Reports. Owner, admin and accountant of p_property_id only; read-only,
-- so a suspended resort can still read them. The signatures are the
-- contract the app is built against; Tasks 3-5 replace the stub bodies.

create function public.report_collections(p_from date, p_to date, p_property_id uuid)
returns table (
  day       date,
  channel   text,
  source    text,
  method    public.payment_method,
  txn_count int,
  amount    numeric
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_tz text;
begin
  perform public.assert_resort_role(p_property_id, false, 'owner','admin','accountant');

  select p.timezone into v_tz from public.properties p where p.id = p_property_id;

  -- Cash basis: money in (payments, walk-in sales) and out (refunds) on
  -- the resort-local day it moved. Column names are prefixed (l_*) so
  -- they never collide with this function's OUT parameters.
  return query
  with paid as (
    select pm.reservation_id as res_id, sum(pm.amount) as paid_total
      from public.payments pm
     where pm.property_id = p_property_id and pm.status = 'succeeded'
     group by pm.reservation_id
  ),
  lines as (
    select (pm.created_at at time zone v_tz)::date as l_day,
           case when pm.method = 'gateway' then 'online' else 'front_desk' end as l_channel,
           case pm.kind when 'advance' then 'booking_advance' else 'checkout_balance' end as l_source,
           pm.method as l_method,
           pm.amount as l_amount
      from public.payments pm
     where pm.property_id = p_property_id
       and pm.status = 'succeeded'
       and pm.created_at >= (p_from::timestamp at time zone v_tz)
       and pm.created_at <  ((p_to + 1)::timestamp at time zone v_tz)
    union all
    select s.sale_date, 'front_desk', 'walk_in_sale', s.payment_method, s.amount
      from public.food_activity_sales s
     where s.property_id = p_property_id
       and s.sale_date between p_from and p_to
    union all
    -- A refund goes back the way the advance came in, and never exceeds
    -- what the booking actually paid (compute_refund works on the quote
    -- total, not on the money received).
    select (r.cancelled_at at time zone v_tz)::date, 'online', 'refund',
           'gateway'::public.payment_method,
           -least(coalesce(r.refund_amount, 0), coalesce(pd.paid_total, 0))
      from public.reservations r
      left join paid pd on pd.res_id = r.id
     where r.property_id = p_property_id
       and r.status = 'cancelled'
       and r.cancelled_at >= (p_from::timestamp at time zone v_tz)
       and r.cancelled_at <  ((p_to + 1)::timestamp at time zone v_tz)
       and least(coalesce(r.refund_amount, 0), coalesce(pd.paid_total, 0)) > 0
  )
  select l.l_day, l.l_channel, l.l_source, l.l_method,
         count(*)::int, round(sum(l.l_amount), 2)
    from lines l
   group by l.l_day, l.l_channel, l.l_source, l.l_method
   order by l.l_day, l.l_channel, l.l_source, l.l_method;
end;
$$;

create function public.report_ledger(p_from date, p_to date, p_property_id uuid)
returns table (
  day      date,
  category text,
  source   text,
  gross    numeric,
  discount numeric,
  taxable  numeric,
  tax      numeric,
  net      numeric
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_tz text;
begin
  perform public.assert_resort_role(p_property_id, false, 'owner','admin','accountant');

  select p.timezone into v_tz from public.properties p where p.id = p_property_id;

  -- Accrual basis: revenue earned, by category. Room revenue falls on the
  -- arrival date (as in report_revenue). Tax is room tax only, exactly as
  -- fixed in each booking's quote (get_quote taxes subtotal + cleaning_fee
  -- - discount); it is split between the room line and the cleaning-fee
  -- line so the two add up to the quote's tax_amount and total.
  return query
  with bk as (
    select (lower(r.period) at time zone v_tz)::date as b_day,
           coalesce(r.quote ? 'subtotal', false) as b_itemised,
           coalesce((r.quote ->> 'subtotal')::numeric, (r.quote ->> 'total')::numeric, 0) as b_sub,
           coalesce((r.quote ->> 'cleaning_fee')::numeric, 0) as b_clean,
           coalesce((r.quote -> 'coupon' ->> 'discount')::numeric, 0) as b_disc,
           coalesce((r.quote ->> 'tax_pct')::numeric, 0) as b_pct,
           coalesce((r.quote ->> 'tax_amount')::numeric, 0) as b_tax
      from public.reservations r
     where r.property_id = p_property_id
       and r.kind = 'booking'
       and r.quote is not null
       and r.status in ('confirmed', 'checked_in', 'checked_out')
       and (lower(r.period) at time zone v_tz)::date between p_from and p_to
  ),
  bk2 as (
    select b.*,
           case when b.b_itemised then least(b.b_disc, b.b_sub) else 0 end as room_disc
      from bk b
  ),
  bk3 as (
    select b.*,
           case when b.b_itemised
                then round((b.b_sub - b.room_disc) * b.b_pct / 100, 2) else 0 end as room_tax,
           case when b.b_itemised
                then least(b.b_disc - b.room_disc, b.b_clean) else 0 end as clean_disc
      from bk2 b
  ),
  paid as (
    select pm.reservation_id as res_id, sum(pm.amount) as paid_total
      from public.payments pm
     where pm.property_id = p_property_id and pm.status = 'succeeded'
     group by pm.reservation_id
  ),
  lines as (
    select b.b_day as l_day, 'room' as l_cat, 'booking' as l_src,
           b.b_sub as l_gross, b.room_disc as l_disc, b.room_tax as l_tax
      from bk3 b
    union all
    select b.b_day, 'ancillary', 'cleaning_fee',
           b.b_clean, b.clean_disc, b.b_tax - b.room_tax
      from bk3 b
     where b.b_itemised and (b.b_clean > 0 or b.b_tax - b.room_tax <> 0)
    union all
    select (r.cancelled_at at time zone v_tz)::date, 'ancillary', 'cancellation_fee',
           coalesce(pd.paid_total, 0) - least(coalesce(r.refund_amount, 0), coalesce(pd.paid_total, 0)),
           0, 0
      from public.reservations r
      left join paid pd on pd.res_id = r.id
     where r.property_id = p_property_id
       and r.status = 'cancelled'
       and r.cancelled_at >= (p_from::timestamp at time zone v_tz)
       and r.cancelled_at <  ((p_to + 1)::timestamp at time zone v_tz)
       and coalesce(pd.paid_total, 0)
           - least(coalesce(r.refund_amount, 0), coalesce(pd.paid_total, 0)) > 0
    union all
    select (fo.created_at at time zone v_tz)::date, 'food_beverage', 'in_stay_order',
           fo.total, 0, 0
      from public.food_orders fo
     where fo.property_id = p_property_id
       and fo.status <> 'cancelled'
       and fo.created_at >= (p_from::timestamp at time zone v_tz)
       and fo.created_at <  ((p_to + 1)::timestamp at time zone v_tz)
    union all
    select s.sale_date,
           case s.category when 'food' then 'food_beverage' else 'spa_activities' end,
           'walk_in', s.amount, 0, 0
      from public.food_activity_sales s
     where s.property_id = p_property_id
       and s.sale_date between p_from and p_to
    union all
    select ab.booking_date, 'spa_activities', 'activity_booking', ab.amount, 0, 0
      from public.activity_bookings ab
     where ab.property_id = p_property_id
       and ab.status = 'booked'
       and ab.booking_date between p_from and p_to
  )
  select l.l_day, l.l_cat, l.l_src,
         round(sum(l.l_gross), 2),
         round(sum(l.l_disc), 2),
         round(sum(l.l_gross - l.l_disc), 2),
         round(sum(l.l_tax), 2),
         round(sum(l.l_gross - l.l_disc + l.l_tax), 2)
    from lines l
   group by l.l_day, l.l_cat, l.l_src
   order by l.l_day, l.l_cat, l.l_src;
end;
$$;

create function public.report_settlements(p_from date, p_to date, p_property_id uuid)
returns table (
  reservation_id   uuid,
  guest_name       text,
  unit_name        text,
  arrival          date,
  departure        date,
  room             numeric,
  cleaning_fee     numeric,
  tax_pct          numeric,
  tax              numeric,
  food             numeric,
  activities       numeric,
  total            numeric,
  advance_paid     numeric,
  balance_online   numeric,
  balance_desk     numeric,
  desk_method      public.payment_method,
  desk_reference   text,
  recorded_by_name text,
  outstanding      numeric
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_tz text;
begin
  perform public.assert_resort_role(p_property_id, false, 'owner','admin','accountant');

  select p.timezone into v_tz from public.properties p where p.id = p_property_id;

  -- One row per booking checked out in the range. room + cleaning_fee +
  -- tax + food + activities = total, where total is what current_charges
  -- bills (quote total + food + activities), and outstanding is total
  -- minus every succeeded payment.
  return query
  select r.id,
         coalesce(nullif(btrim(pr.full_name), ''), 'Guest'),
         u.name,
         (lower(r.period) at time zone v_tz)::date,
         (upper(r.period) at time zone v_tz)::date,
         round(q.q_room, 2),
         round(q.q_clean, 2),
         round(q.q_pct, 2),
         round(q.q_tax, 2),
         round(f.f_total, 2),
         round(a.a_total, 2),
         round(q.q_total + f.f_total + a.a_total, 2),
         round(pay.adv, 2),
         round(pay.bal_online, 2),
         round(pay.bal_desk, 2),
         case when bal.b_method <> 'gateway' then bal.b_method end,
         case when bal.b_method <> 'gateway' then bal.b_reference end,
         rb.full_name,
         round(q.q_total + f.f_total + a.a_total - pay.paid_all, 2)
    from public.reservations r
    join public.units u on u.id = r.unit_id
    left join public.profiles pr on pr.id = r.customer_id
    cross join lateral (
      select case when v.it then v.sub - least(v.disc, v.sub) else v.tot end as q_room,
             case when v.it then v.clean - least(v.disc - least(v.disc, v.sub), v.clean) else 0 end as q_clean,
             case when v.it then v.pct else 0 end as q_pct,
             case when v.it then v.taxamt else 0 end as q_tax,
             v.tot as q_total
        from (select coalesce(r.quote ? 'subtotal', false) as it,
                     coalesce((r.quote ->> 'subtotal')::numeric, 0) as sub,
                     coalesce((r.quote ->> 'cleaning_fee')::numeric, 0) as clean,
                     coalesce((r.quote -> 'coupon' ->> 'discount')::numeric, 0) as disc,
                     coalesce((r.quote ->> 'tax_pct')::numeric, 0) as pct,
                     coalesce((r.quote ->> 'tax_amount')::numeric, 0) as taxamt,
                     coalesce((r.quote ->> 'total')::numeric, 0) as tot) v
    ) q
    cross join lateral (
      select coalesce(sum(fo.total), 0) as f_total
        from public.food_orders fo
       where fo.reservation_id = r.id and fo.status <> 'cancelled'
    ) f
    cross join lateral (
      select coalesce(sum(ab.amount), 0) as a_total
        from public.activity_bookings ab
       where ab.reservation_id = r.id and ab.status <> 'cancelled'
    ) a
    cross join lateral (
      select coalesce(sum(pm.amount) filter (where pm.kind = 'advance'), 0) as adv,
             coalesce(sum(pm.amount) filter (where pm.kind = 'balance' and pm.method = 'gateway'), 0) as bal_online,
             coalesce(sum(pm.amount) filter (where pm.kind = 'balance' and pm.method <> 'gateway'), 0) as bal_desk,
             coalesce(sum(pm.amount), 0) as paid_all
        from public.payments pm
       where pm.reservation_id = r.id and pm.status = 'succeeded'
    ) pay
    left join lateral (
      select pm.method as b_method, pm.reference as b_reference, pm.recorded_by as b_by
        from public.payments pm
       where pm.reservation_id = r.id and pm.status = 'succeeded' and pm.kind = 'balance'
       order by pm.created_at desc
       limit 1
    ) bal on true
    left join public.profiles rb on rb.id = bal.b_by
   where r.property_id = p_property_id
     and r.kind = 'booking'
     and r.checked_out_at >= (p_from::timestamp at time zone v_tz)
     and r.checked_out_at <  ((p_to + 1)::timestamp at time zone v_tz)
   order by r.checked_out_at, r.id;
end;
$$;

create function public.finance_summary(p_property_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_prop       public.properties;
  v_today      date;
  v_online     numeric;
  v_desk       numeric;
  v_cash       numeric;
  v_card       numeric;
  v_upi        numeric;
  v_bank       numeric;
  v_other      numeric;
  v_refunds    numeric;
  v_room_tax   numeric;
  v_in_count   int;
  v_in_balance numeric;
begin
  perform public.assert_resort_role(p_property_id, false, 'owner','admin','accountant');

  select * into v_prop from public.properties where id = p_property_id;
  v_today := (now() at time zone v_prop.timezone)::date;

  -- From today's Collections, so the Today tab and the Collections tab
  -- can never disagree. Refunds are reported as a positive amount.
  select coalesce(sum(c.amount) filter (where c.channel = 'online' and c.source <> 'refund'), 0),
         coalesce(sum(c.amount) filter (where c.channel = 'front_desk'), 0),
         coalesce(sum(c.amount) filter (where c.channel = 'front_desk' and c.method = 'cash'), 0),
         coalesce(sum(c.amount) filter (where c.channel = 'front_desk' and c.method = 'card'), 0),
         coalesce(sum(c.amount) filter (where c.channel = 'front_desk' and c.method = 'upi'), 0),
         coalesce(sum(c.amount) filter (where c.channel = 'front_desk' and c.method = 'bank_transfer'), 0),
         coalesce(sum(c.amount) filter (where c.channel = 'front_desk' and c.method = 'other'), 0),
         coalesce(-sum(c.amount) filter (where c.source = 'refund'), 0)
    into v_online, v_desk, v_cash, v_card, v_upi, v_bank, v_other, v_refunds
    from public.report_collections(v_today, v_today, p_property_id) c;

  -- Tax exists only on bookings: the room and cleaning-fee lines together.
  select coalesce(sum(l.tax), 0) into v_room_tax
    from public.report_ledger(v_today, v_today, p_property_id) l;

  -- Checked-in guests and what they still owe, worked out as
  -- current_charges does, but in one query rather than one call each.
  select count(*)::int,
         coalesce(sum(greatest(coalesce((r.quote ->> 'total')::numeric, 0)
                               + coalesce(fo.t, 0) + coalesce(ab.t, 0) - coalesce(pm.t, 0), 0)), 0)
    into v_in_count, v_in_balance
    from public.reservations r
    left join (select o.reservation_id, sum(o.total) as t
                 from public.food_orders o
                where o.property_id = p_property_id and o.status <> 'cancelled'
                group by o.reservation_id) fo on fo.reservation_id = r.id
    left join (select b.reservation_id, sum(b.amount) as t
                 from public.activity_bookings b
                where b.property_id = p_property_id and b.status <> 'cancelled'
                group by b.reservation_id) ab on ab.reservation_id = r.id
    left join (select p.reservation_id, sum(p.amount) as t
                 from public.payments p
                where p.property_id = p_property_id and p.status = 'succeeded'
                group by p.reservation_id) pm on pm.reservation_id = r.id
   where r.property_id = p_property_id
     and r.kind = 'booking'
     and r.status = 'checked_in';

  return jsonb_build_object(
    'resort', jsonb_build_object(
      'name',     v_prop.name,
      'slug',     v_prop.slug,
      'gstin',    v_prop.gstin,
      'tax_pct',  v_prop.tax_pct,
      'timezone', v_prop.timezone,
      'today',    to_char(v_today, 'YYYY-MM-DD')),
    'online_collected', round(v_online, 2),
    'desk_collected', jsonb_build_object(
      'total',         round(v_desk, 2),
      'cash',          round(v_cash, 2),
      'card',          round(v_card, 2),
      'upi',           round(v_upi, 2),
      'bank_transfer', round(v_bank, 2),
      'other',         round(v_other, 2)),
    'refunds',          round(v_refunds, 2),
    'net_collected',    round(v_online + v_desk - v_refunds, 2),
    'room_tax',         round(v_room_tax, 2),
    'in_house_count',   v_in_count,
    'in_house_balance', round(v_in_balance, 2)
  );
end;
$$;

revoke execute on function public.report_collections(date, date, uuid) from public, anon;
revoke execute on function public.report_ledger(date, date, uuid) from public, anon;
revoke execute on function public.report_settlements(date, date, uuid) from public, anon;
revoke execute on function public.finance_summary(uuid) from public, anon;
grant execute on function public.report_collections(date, date, uuid) to authenticated;
grant execute on function public.report_ledger(date, date, uuid) to authenticated;
grant execute on function public.report_settlements(date, date, uuid) to authenticated;
grant execute on function public.finance_summary(uuid) to authenticated;
