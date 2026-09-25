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
