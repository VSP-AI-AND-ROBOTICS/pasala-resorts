-- Food and spa tax (P4), added in 0053_food_spa_tax.sql.
-- See docs/superpowers/specs/2026-09-25-p4-food-and-spa-tax-design.md.
--
-- One file, built up by the plan's database tasks in order: each section
-- relies on the state the sections before it leave behind.
--
-- Resort T (Asia/Kolkata, 12% room tax) has an owner (Olga), a staff
-- member (Sita) and an accountant (Anil). Gita is a guest: R1 is her stay
-- in Cottage 1, checked in since yesterday (a total-only quote of 5,000,
-- nothing paid); R2 is her booking of Cottage 2 arriving at 14:00 today
-- (2,000 of room at 12% = 240 tax, total 2,240).
begin;
select plan(20);

-- Rows a statement changed, run as the current role (0 when RLS filters it).
create function pg_temp.rows_affected(p_sql text) returns int
language plpgsql as $f$
declare n int;
begin
  execute p_sql;
  get diagnostics n = row_count;
  return n;
end;
$f$;

-- Before any fixture: every row that existed before 0053 carries no tax.
select is(
  (select count(*)::int from (
     select tax_pct, tax_amount from public.food_orders
     union all select tax_pct, tax_amount from public.food_order_items
     union all select tax_pct, tax_amount from public.activity_bookings
     union all select tax_pct, tax_amount from public.food_activity_sales) t
    where t.tax_pct <> 0 or t.tax_amount <> 0),
  0, 'every row that existed before 0053 has tax 0');

insert into auth.users (id, email) values
  ('44000000-0000-0000-0000-000000000001','tax-owner@example.com'),
  ('44000000-0000-0000-0000-000000000002','tax-staff@example.com'),
  ('44000000-0000-0000-0000-000000000003','tax-accountant@example.com'),
  ('44000000-0000-0000-0000-000000000004','tax-gita@example.com');

insert into public.properties (id, name, slug, tax_pct) values
  ('44444444-0000-4000-8000-000000000001','Resort T','tax-t',12);

insert into public.resort_members (property_id, user_id, role) values
  ('44444444-0000-4000-8000-000000000001','44000000-0000-0000-0000-000000000001','owner'),
  ('44444444-0000-4000-8000-000000000001','44000000-0000-0000-0000-000000000002','staff'),
  ('44444444-0000-4000-8000-000000000001','44000000-0000-0000-0000-000000000003','accountant');

insert into public.units (id, property_id, name, capacity_base, capacity_max) values
  ('44444444-0000-4000-8000-000000000011','44444444-0000-4000-8000-000000000001','Cottage 1',2,4),
  ('44444444-0000-4000-8000-000000000012','44444444-0000-4000-8000-000000000001','Cottage 2',2,4);

insert into public.food_categories (id, property_id, name) values
  ('44444444-0000-4000-8000-000000000021','44444444-0000-4000-8000-000000000001','Mains');
insert into public.food_items (id, category_id, name, price) values
  ('44444444-0000-4000-8000-000000000031','44444444-0000-4000-8000-000000000021','Thali',210),
  ('44444444-0000-4000-8000-000000000032','44444444-0000-4000-8000-000000000021','Lassi',105);

insert into public.activities (id, property_id, name, price_per_person, capacity_per_slot) values
  ('44444444-0000-4000-8000-000000000041','44444444-0000-4000-8000-000000000001','Spa massage',1180,4);

insert into public.reservations (id, unit_id, period, kind, status, customer_id, guests, quote, checked_in_at) values
  ('44444444-0000-4000-8000-000000000051','44444444-0000-4000-8000-000000000011',
   tstzrange(now() - interval '1 day', now() + interval '1 day', '[)'),
   'booking','checked_in','44000000-0000-0000-0000-000000000004',2,
   '{"total":5000}', now() - interval '1 day');
insert into public.reservations (id, unit_id, period, kind, status, customer_id, guests, quote) values
  ('44444444-0000-4000-8000-000000000052','44444444-0000-4000-8000-000000000012',
   tstzrange(((now() at time zone 'Asia/Kolkata')::date + time '14:00') at time zone 'Asia/Kolkata',
             ((now() at time zone 'Asia/Kolkata')::date + 1 + time '11:00') at time zone 'Asia/Kolkata', '[)'),
   'booking','confirmed','44000000-0000-0000-0000-000000000004',2,
   '{"subtotal":2000,"cleaning_fee":0,"coupon":null,"tax_pct":12,"tax_amount":240,"total":2240}');

-- ---------------------------------------------------------------------
-- Task 1: the contract.

select col_type_is('public','properties','fnb_tax_pct','numeric(5,2)',
  'properties.fnb_tax_pct is numeric(5,2)');
select col_type_is('public','properties','spa_tax_pct','numeric(5,2)',
  'properties.spa_tax_pct is numeric(5,2)');
select col_has_check('public','properties','fnb_tax_pct',
  'properties.fnb_tax_pct has a range check');
select col_has_check('public','properties','spa_tax_pct',
  'properties.spa_tax_pct has a range check');
select is((select fnb_tax_pct + spa_tax_pct from public.properties
            where id = '44444444-0000-4000-8000-000000000001'),
  0::numeric, 'a resort starts with food and spa rates of 0');

select col_type_is('public','food_orders','tax_pct','numeric(5,2)','food_orders.tax_pct is numeric(5,2)');
select col_type_is('public','food_orders','tax_amount','numeric(12,2)','food_orders.tax_amount is numeric(12,2)');
select col_type_is('public','food_order_items','tax_pct','numeric(5,2)','food_order_items.tax_pct is numeric(5,2)');
select col_type_is('public','food_order_items','tax_amount','numeric(12,2)','food_order_items.tax_amount is numeric(12,2)');
select col_type_is('public','activity_bookings','tax_pct','numeric(5,2)','activity_bookings.tax_pct is numeric(5,2)');
select col_type_is('public','activity_bookings','tax_amount','numeric(12,2)','activity_bookings.tax_amount is numeric(12,2)');
select col_type_is('public','food_activity_sales','tax_pct','numeric(5,2)','food_activity_sales.tax_pct is numeric(5,2)');
select col_type_is('public','food_activity_sales','tax_amount','numeric(12,2)','food_activity_sales.tax_amount is numeric(12,2)');
select is(
  (select count(*)::int from information_schema.columns
    where table_schema = 'public'
      and table_name in ('food_orders','food_order_items','activity_bookings','food_activity_sales')
      and column_name in ('tax_pct','tax_amount')
      and is_nullable = 'NO' and column_default is not null),
  8, 'the eight tax columns are not null and have a default');

select has_function('public','inclusive_tax',array['numeric','numeric'],
  'inclusive_tax(numeric, numeric) exists');
select function_returns('public','inclusive_tax',array['numeric','numeric'],'numeric',
  'inclusive_tax returns numeric');
select isnt_definer('public','inclusive_tax',array['numeric','numeric'],
  'inclusive_tax is not security definer');
select ok(has_function_privilege('authenticated','public.inclusive_tax(numeric, numeric)','execute'),
  'authenticated may call inclusive_tax');
select ok(not has_function_privilege('anon','public.inclusive_tax(numeric, numeric)','execute'),
  'anon may not call inclusive_tax');

select * from finish();
rollback;
