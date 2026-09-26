-- Food and spa tax (P4): a food & drink rate and a spa & activities rate
-- per resort, and the tax inside every food order, order item, activity
-- booking and walk-in sale, stored on the row when it is made.
-- See docs/superpowers/specs/2026-09-25-p4-food-and-spa-tax-design.md.
--
-- Prices include tax: the tax inside a price is price * pct / (100 + pct),
-- rounded to paise (public.inclusive_tax). Triggers fill tax_pct and
-- tax_amount on every insert and update, so place_food_order,
-- book_activity and the walk-in sales form work unchanged, and a client
-- never sets tax. Rows that exist before this migration keep tax 0.
--
-- Error code raised: P0035 tax_rate_out_of_range.

-- ---------------------------------------------------------------------
-- Rates. 0 to 28, the highest GST slab. properties.tax_pct stays the
-- room rate, added on top at booking time (0025, get_quote).
alter table public.properties
  add column fnb_tax_pct numeric(5,2) not null default 0
    constraint properties_fnb_tax_pct_range check (fnb_tax_pct >= 0 and fnb_tax_pct <= 28),
  add column spa_tax_pct numeric(5,2) not null default 0
    constraint properties_spa_tax_pct_range check (spa_tax_pct >= 0 and spa_tax_pct <= 28);

-- ---------------------------------------------------------------------
-- The tax inside each sale, at the rate of the day it was made. Adding a
-- column with a default fills existing rows with 0 and fires no trigger.
alter table public.food_orders
  add column tax_pct numeric(5,2) not null default 0
    constraint food_orders_tax_pct_range check (tax_pct >= 0 and tax_pct <= 28),
  add column tax_amount numeric(12,2) not null default 0
    constraint food_orders_tax_amount_nonneg check (tax_amount >= 0);

alter table public.food_order_items
  add column tax_pct numeric(5,2) not null default 0
    constraint food_order_items_tax_pct_range check (tax_pct >= 0 and tax_pct <= 28),
  add column tax_amount numeric(12,2) not null default 0
    constraint food_order_items_tax_amount_nonneg check (tax_amount >= 0);

alter table public.activity_bookings
  add column tax_pct numeric(5,2) not null default 0
    constraint activity_bookings_tax_pct_range check (tax_pct >= 0 and tax_pct <= 28),
  add column tax_amount numeric(12,2) not null default 0
    constraint activity_bookings_tax_amount_nonneg check (tax_amount >= 0);

alter table public.food_activity_sales
  add column tax_pct numeric(5,2) not null default 0
    constraint food_activity_sales_tax_pct_range check (tax_pct >= 0 and tax_pct <= 28),
  add column tax_amount numeric(12,2) not null default 0
    constraint food_activity_sales_tax_amount_nonneg check (tax_amount >= 0);

-- ---------------------------------------------------------------------
-- The tax inside a tax-inclusive price, rounded to paise: 105 at 5%
-- holds 5.00; 200 at 18% holds 30.51. Not security definer: the walk-in
-- trigger runs as the staff member and calls it.
create function public.inclusive_tax(p_amount numeric, p_pct numeric)
returns numeric
language sql
immutable
set search_path = public, pg_temp
as $$
  select round(coalesce(p_amount, 0) * coalesce(p_pct, 0) / (100 + coalesce(p_pct, 0)), 2);
$$;

revoke execute on function public.inclusive_tax(numeric, numeric) from public, anon;
grant execute on function public.inclusive_tax(numeric, numeric) to authenticated;

-- ---------------------------------------------------------------------
-- Tax stored on the row. Each trigger fixes tax_pct on insert from the
-- resort's current rate -- read through the row's own parent, never from
-- what the client sent -- keeps it on update, and works tax_amount out
-- again from the row's amount every time. So a client can neither set nor
-- clear tax, and a later rate change never rewrites an old sale.
--
-- They run with the caller's rights: inside place_food_order and
-- book_activity (security definer) that is the function owner; for a
-- walk-in sale it is the staff member, who can read their own resort's
-- properties row. None is security definer, so the allow-list in
-- 37_tenancy_isolation_test.sql does not change.

create function public.food_orders_set_tax()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if tg_op = 'INSERT' then
    -- Through the reservation, not new.property_id, so this does not
    -- depend on food_orders_fill_property having run first.
    new.tax_pct := coalesce((select p.fnb_tax_pct
                               from public.reservations r
                               join public.properties p on p.id = r.property_id
                              where r.id = new.reservation_id), 0);
  else
    new.tax_pct := old.tax_pct;
  end if;
  -- place_food_order inserts the order with total 0 and sets the total
  -- afterwards; that update recomputes the tax at the fixed rate.
  new.tax_amount := public.inclusive_tax(new.total, new.tax_pct);
  return new;
end;
$$;
revoke execute on function public.food_orders_set_tax() from public, anon, authenticated;

create trigger food_orders_set_tax
  before insert or update on public.food_orders
  for each row execute function public.food_orders_set_tax();

-- An item takes its order's rate. Item taxes are per line and can differ
-- from the order's own tax (worked out on the order total) by a paisa of
-- rounding; the order's figure is the one reports and bills add up.
create function public.food_order_items_set_tax()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if tg_op = 'INSERT' then
    new.tax_pct := coalesce((select o.tax_pct from public.food_orders o
                              where o.id = new.order_id), 0);
  else
    new.tax_pct := old.tax_pct;
  end if;
  new.tax_amount := public.inclusive_tax(new.line_total, new.tax_pct);
  return new;
end;
$$;
revoke execute on function public.food_order_items_set_tax() from public, anon, authenticated;

create trigger food_order_items_set_tax
  before insert or update on public.food_order_items
  for each row execute function public.food_order_items_set_tax();

create function public.activity_bookings_set_tax()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if tg_op = 'INSERT' then
    new.tax_pct := coalesce((select p.spa_tax_pct
                               from public.reservations r
                               join public.properties p on p.id = r.property_id
                              where r.id = new.reservation_id), 0);
  else
    new.tax_pct := old.tax_pct;
  end if;
  new.tax_amount := public.inclusive_tax(new.amount, new.tax_pct);
  return new;
end;
$$;
revoke execute on function public.activity_bookings_set_tax() from public, anon, authenticated;

create trigger activity_bookings_set_tax
  before insert or update on public.activity_bookings
  for each row execute function public.activity_bookings_set_tax();

-- A walk-in sale takes the rate of its category. Correcting its amount
-- keeps the rate it was sold at; moving it to the other category takes
-- that category's current rate. (OLD is null on insert, so old.category
-- reads as null there.)
create function public.food_activity_sales_set_tax()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if tg_op = 'INSERT' or new.category is distinct from old.category then
    new.tax_pct := coalesce((select case new.category
                                      when 'food' then p.fnb_tax_pct
                                      else p.spa_tax_pct
                                    end
                               from public.properties p
                              where p.id = new.property_id), 0);
  else
    new.tax_pct := old.tax_pct;
  end if;
  new.tax_amount := public.inclusive_tax(new.amount, new.tax_pct);
  return new;
end;
$$;
revoke execute on function public.food_activity_sales_set_tax() from public, anon, authenticated;

create trigger food_activity_sales_set_tax
  before insert or update on public.food_activity_sales
  for each row execute function public.food_activity_sales_set_tax();

-- ---------------------------------------------------------------------
-- Rates outside 0..28 get a readable code before the check constraints
-- (which stay as the backstop) would refuse them with a bare 23514.
create function public.properties_check_service_tax()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if new.fnb_tax_pct is null or new.fnb_tax_pct < 0 or new.fnb_tax_pct > 28
     or new.spa_tax_pct is null or new.spa_tax_pct < 0 or new.spa_tax_pct > 28 then
    raise exception using errcode = 'P0035', message = 'tax_rate_out_of_range';
  end if;
  return new;
end;
$$;
revoke execute on function public.properties_check_service_tax() from public, anon, authenticated;

create trigger properties_check_service_tax
  before insert or update of fnb_tax_pct, spa_tax_pct on public.properties
  for each row execute function public.properties_check_service_tax();

-- ---------------------------------------------------------------------
-- The guest's bill gains the tax inside its food and activities. Body
-- copied from 0045_resort_functions.sql; the 0053 lines are marked.
-- total and balance do not change: the tax is already inside the amounts.
create or replace function public.current_charges(
  p_reservation_id uuid
) returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid          uuid := auth.uid();
  v_res          public.reservations;
  v_stay         numeric(12,2);
  v_food         numeric(12,2);
  v_food_tax     numeric(12,2);   -- 0053
  v_activity     numeric(12,2);
  v_activity_tax numeric(12,2);   -- 0053
  v_paid         numeric(12,2);
  v_total        numeric(12,2);
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode = 'P0008';
  end if;

  select * into v_res from public.reservations where id = p_reservation_id;
  if not found then
    raise exception 'reservation not found' using errcode = 'P0002';
  end if;

  if v_res.customer_id is distinct from v_uid then
    perform public.assert_resort_role(v_res.property_id, false,
      'owner','admin','staff','accountant');
  end if;

  v_stay := coalesce((v_res.quote ->> 'total')::numeric, 0);

  select coalesce(sum(total), 0), coalesce(sum(tax_amount), 0)   -- 0053
    into v_food, v_food_tax
  from public.food_orders
  where reservation_id = p_reservation_id and status <> 'cancelled';

  select coalesce(sum(amount), 0), coalesce(sum(tax_amount), 0)  -- 0053
    into v_activity, v_activity_tax
  from public.activity_bookings
  where reservation_id = p_reservation_id and status <> 'cancelled';

  select coalesce(sum(amount), 0) into v_paid
  from public.payments
  where reservation_id = p_reservation_id and status = 'succeeded';

  v_total := v_stay + v_food + v_activity;

  return jsonb_build_object(
    'stay_amount', v_stay,
    'food_amount', v_food,
    'food_tax', v_food_tax,                -- 0053
    'activity_amount', v_activity,
    'activity_tax', v_activity_tax,        -- 0053
    'total', v_total,
    'paid', v_paid,
    'balance', greatest(v_total - v_paid, 0)
  );
end;
$$;

-- ---------------------------------------------------------------------
-- The Ledger splits tax-inclusive lines into pre-tax and tax. Body copied
-- from 0048_finance_ledger.sql; only the three 0053 lines change.
create or replace function public.report_ledger(p_from date, p_to date, p_property_id uuid)
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
  -- arrival date (as in report_revenue). Room tax is exactly as fixed in
  -- each booking's quote (get_quote taxes subtotal + cleaning_fee -
  -- discount); it is split between the room line and the cleaning-fee
  -- line so the two add up to the quote's tax_amount and total. Food,
  -- activity and walk-in prices include their tax (0053): gross is the
  -- amount without the tax stored on the row, so net is still the amount.
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
           fo.total - fo.tax_amount, 0, fo.tax_amount                         -- 0053
      from public.food_orders fo
     where fo.property_id = p_property_id
       and fo.status <> 'cancelled'
       and fo.created_at >= (p_from::timestamp at time zone v_tz)
       and fo.created_at <  ((p_to + 1)::timestamp at time zone v_tz)
    union all
    select s.sale_date,
           case s.category when 'food' then 'food_beverage' else 'spa_activities' end,
           'walk_in', s.amount - s.tax_amount, 0, s.tax_amount                -- 0053
      from public.food_activity_sales s
     where s.property_id = p_property_id
       and s.sale_date between p_from and p_to
    union all
    select ab.booking_date, 'spa_activities', 'activity_booking',
           ab.amount - ab.tax_amount, 0, ab.tax_amount                        -- 0053
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

-- ---------------------------------------------------------------------
-- Today's summary reports tax by category and the resort's two new
-- rates. Body copied from 0048_finance_ledger.sql; the 0053 lines are
-- marked.
create or replace function public.finance_summary(p_property_id uuid)
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
  v_food_tax   numeric;   -- 0053
  v_spa_tax    numeric;   -- 0053
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

  -- 0053: today's Ledger tax by category. Room tax is the room and
  -- cleaning-fee (ancillary) lines of bookings; food and spa tax are the
  -- tax inside their prices.
  select coalesce(sum(l.tax) filter (where l.category in ('room', 'ancillary')), 0),
         coalesce(sum(l.tax) filter (where l.category = 'food_beverage'), 0),
         coalesce(sum(l.tax) filter (where l.category = 'spa_activities'), 0)
    into v_room_tax, v_food_tax, v_spa_tax
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
      'name',        v_prop.name,
      'slug',        v_prop.slug,
      'gstin',       v_prop.gstin,
      'tax_pct',     v_prop.tax_pct,
      'fnb_tax_pct', v_prop.fnb_tax_pct,   -- 0053
      'spa_tax_pct', v_prop.spa_tax_pct,   -- 0053
      'timezone',    v_prop.timezone,
      'today',       to_char(v_today, 'YYYY-MM-DD')),
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
    'food_tax',         round(v_food_tax, 2),   -- 0053
    'spa_tax',          round(v_spa_tax, 2),    -- 0053
    'in_house_count',   v_in_count,
    'in_house_balance', round(v_in_balance, 2)
  );
end;
$$;
