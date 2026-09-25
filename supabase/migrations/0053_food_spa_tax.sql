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
-- The tax inside a tax-inclusive price. Not security definer: the
-- walk-in trigger runs as the staff member and calls it.
-- CONTRACT STUB: Task 2 replaces this body.
create function public.inclusive_tax(p_amount numeric, p_pct numeric)
returns numeric
language plpgsql
immutable
set search_path = public, pg_temp
as $$
begin
  raise exception 'inclusive_tax is not implemented yet' using errcode = '0A000';
end;
$$;

revoke execute on function public.inclusive_tax(numeric, numeric) from public, anon;
grant execute on function public.inclusive_tax(numeric, numeric) to authenticated;
