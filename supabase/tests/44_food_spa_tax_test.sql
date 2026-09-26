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
select plan(67);

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

-- ---------------------------------------------------------------------
-- Task 2: rates, inclusive_tax, and tax stored on every sale.
--
-- Rates over the section: fnb 5 -> (orders O1) -> 12 -> (O2, walk-ins)
-- -> 5 while W1 is corrected -> 12; spa 18 throughout.

set local role authenticated;

-- Olga (owner) sets food & drink to 5% and spa & activities to 18%.
set local request.jwt.claims to '{"sub":"44000000-0000-0000-0000-000000000001","role":"authenticated"}';
select is(pg_temp.rows_affected($$update public.properties set fnb_tax_pct = 5, spa_tax_pct = 18
  where id = '44444444-0000-4000-8000-000000000001'$$), 1,
  'the owner sets the food and spa rates');

-- Sita (staff) cannot.
set local request.jwt.claims to '{"sub":"44000000-0000-0000-0000-000000000002","role":"authenticated"}';
select is(pg_temp.rows_affected($$update public.properties set fnb_tax_pct = 0
  where id = '44444444-0000-4000-8000-000000000001'$$), 0,
  'staff cannot change the rates');
select is((select fnb_tax_pct::text || '/' || spa_tax_pct::text from public.properties
            where id = '44444444-0000-4000-8000-000000000001'),
  '5.00/18.00', 'the rates are 5% and 18%');

set local request.jwt.claims to '{"sub":"44000000-0000-0000-0000-000000000001","role":"authenticated"}';
select throws_ok($$update public.properties set fnb_tax_pct = 28.01
  where id = '44444444-0000-4000-8000-000000000001'$$,
  'P0035', 'tax_rate_out_of_range', 'a food rate above 28 is refused');
select throws_ok($$update public.properties set spa_tax_pct = -1
  where id = '44444444-0000-4000-8000-000000000001'$$,
  'P0035', 'tax_rate_out_of_range', 'a negative spa rate is refused');
select lives_ok($$update public.properties set fnb_tax_pct = 28
  where id = '44444444-0000-4000-8000-000000000001'$$, 'a rate of exactly 28 is allowed');
update public.properties set fnb_tax_pct = 5 where id = '44444444-0000-4000-8000-000000000001';

select is(public.inclusive_tax(105, 5), 5.00, '105 at 5% includes 5.00 of tax');
select is(public.inclusive_tax(200, 18), 30.51, '200 at 18% includes 30.51 (30.508 rounded)');
select is(public.inclusive_tax(1, 5), 0.05, '1 at 5% includes 0.05 (0.0476 rounded)');
select is(public.inclusive_tax(999, 0), 0.00, 'a 0% rate means no tax');

-- O1: Gita orders two thalis and a lassi, 525 at 5%.
set local request.jwt.claims to '{"sub":"44000000-0000-0000-0000-000000000004","role":"authenticated"}';
select lives_ok($$select public.place_food_order('44444444-0000-4000-8000-000000000051',
  '[{"food_item_id":"44444444-0000-4000-8000-000000000031","quantity":2},
    {"food_item_id":"44444444-0000-4000-8000-000000000032","quantity":1}]'::jsonb)$$,
  'Gita orders two thalis and a lassi (525)');
select is((select tax_pct::text || '/' || tax_amount::text from public.food_orders
            where reservation_id = '44444444-0000-4000-8000-000000000051' and total = 525),
  '5.00/25.00', 'the order records 5% and 25.00 of tax');
select is((select string_agg(i.tax_pct::text || '/' || i.tax_amount::text, ',' order by i.line_total)
             from public.food_order_items i
             join public.food_orders o on o.id = i.order_id
            where o.reservation_id = '44444444-0000-4000-8000-000000000051' and o.total = 525),
  '5.00/5.00,5.00/20.00', 'each item records its tax at the order''s rate');

-- The kitchen (Sita) accepts O1 and tries to zero its tax.
set local request.jwt.claims to '{"sub":"44000000-0000-0000-0000-000000000002","role":"authenticated"}';
select is(pg_temp.rows_affected($$update public.food_orders
     set status = 'accepted', tax_pct = 0, tax_amount = 0
   where reservation_id = '44444444-0000-4000-8000-000000000051' and total = 525$$), 1,
  'the kitchen accepts the order, sending tax 0');
select is((select tax_pct::text || '/' || tax_amount::text from public.food_orders
            where reservation_id = '44444444-0000-4000-8000-000000000051' and total = 525),
  '5.00/25.00', 'the tax cannot be changed by an update');

-- Olga raises the food rate to 12%.
set local request.jwt.claims to '{"sub":"44000000-0000-0000-0000-000000000001","role":"authenticated"}';
update public.properties set fnb_tax_pct = 12 where id = '44444444-0000-4000-8000-000000000001';
select is((select tax_pct::text || '/' || tax_amount::text from public.food_orders
            where reservation_id = '44444444-0000-4000-8000-000000000051' and total = 525),
  '5.00/25.00', 'raising the food rate leaves the earlier order at 5%');

-- O2: one more lassi, 105 at 12%.
set local request.jwt.claims to '{"sub":"44000000-0000-0000-0000-000000000004","role":"authenticated"}';
select lives_ok($$select public.place_food_order('44444444-0000-4000-8000-000000000051',
  '[{"food_item_id":"44444444-0000-4000-8000-000000000032","quantity":1}]'::jsonb)$$,
  'Gita orders one more lassi (105)');
select is((select tax_pct::text || '/' || tax_amount::text from public.food_orders
            where reservation_id = '44444444-0000-4000-8000-000000000051' and total = 105),
  '12.00/11.25', 'the new order records 12% and 11.25 of tax');

-- A1: a massage for two (2,360) today; A2: a massage for one (1,180),
-- which Gita cancels.
select lives_ok($$select public.book_activity('44444444-0000-4000-8000-000000000051',
  '44444444-0000-4000-8000-000000000041', (now() at time zone 'Asia/Kolkata')::date, '10:00', 2)$$,
  'Gita books a massage for two (2,360)');
select is((select tax_pct::text || '/' || tax_amount::text from public.activity_bookings
            where reservation_id = '44444444-0000-4000-8000-000000000051' and people = 2),
  '18.00/360.00', 'the activity booking records 18% and 360.00 of tax');
select lives_ok($$select public.book_activity('44444444-0000-4000-8000-000000000051',
  '44444444-0000-4000-8000-000000000041', (now() at time zone 'Asia/Kolkata')::date, '10:00', 1)$$,
  'Gita books a massage for one (1,180)');
select is(pg_temp.rows_affected($$update public.activity_bookings set status = 'cancelled'
   where reservation_id = '44444444-0000-4000-8000-000000000051' and people = 1$$), 1,
  'Gita cancels the massage for one');
select is((select status::text || ' ' || tax_pct::text || '/' || tax_amount::text
             from public.activity_bookings
            where reservation_id = '44444444-0000-4000-8000-000000000051' and people = 1),
  'cancelled 18.00/180.00', 'a cancelled booking keeps its tax');

-- Walk-ins logged by Sita today.
set local request.jwt.claims to '{"sub":"44000000-0000-0000-0000-000000000002","role":"authenticated"}';
select lives_ok($$insert into public.food_activity_sales
    (property_id, category, item_name, unit_price, amount, payment_method, tax_pct, tax_amount)
  values ('44444444-0000-4000-8000-000000000001','food','Walk-in thali',210,210,'cash',0,0)$$,
  'Sita logs a walk-in thali (210), sending tax 0');
select is((select tax_pct::text || '/' || tax_amount::text from public.food_activity_sales
            where item_name = 'Walk-in thali'),
  '12.00/22.50', 'the sale records the current food rate, not what was sent');
select lives_ok($$insert into public.food_activity_sales
    (property_id, category, item_name, unit_price, amount, payment_method)
  values ('44444444-0000-4000-8000-000000000001','activity','Walk-in yoga',590,590,'upi')$$,
  'Sita logs a walk-in yoga session (590)');
select is((select tax_pct::text || '/' || tax_amount::text from public.food_activity_sales
            where item_name = 'Walk-in yoga'),
  '18.00/90.00', 'an activity sale records the spa rate');

-- Olga lowers the food rate to 5% and then corrects the thali to 336.
set local request.jwt.claims to '{"sub":"44000000-0000-0000-0000-000000000001","role":"authenticated"}';
update public.properties set fnb_tax_pct = 5 where id = '44444444-0000-4000-8000-000000000001';
select is(pg_temp.rows_affected($$update public.food_activity_sales
     set amount = 336, unit_price = 336
   where item_name = 'Walk-in thali'$$), 1,
  'the owner corrects the thali sale to 336 while the food rate is 5%');
select is((select tax_pct::text || '/' || tax_amount::text from public.food_activity_sales
            where item_name = 'Walk-in thali'),
  '12.00/36.00', 'the corrected sale keeps the 12% it was sold at');
update public.properties set fnb_tax_pct = 12 where id = '44444444-0000-4000-8000-000000000001';

-- A snack logged as food, then moved to activities as a sauna session.
set local request.jwt.claims to '{"sub":"44000000-0000-0000-0000-000000000002","role":"authenticated"}';
select lives_ok($$insert into public.food_activity_sales
    (property_id, category, item_name, unit_price, amount, payment_method)
  values ('44444444-0000-4000-8000-000000000001','food','Walk-in snack',118,118,'cash')$$,
  'Sita logs a walk-in snack (118) as food');
select is((select tax_pct::text || '/' || tax_amount::text from public.food_activity_sales
            where item_name = 'Walk-in snack'),
  '12.00/12.64', 'the snack records 12% and 12.64 of tax');
set local request.jwt.claims to '{"sub":"44000000-0000-0000-0000-000000000001","role":"authenticated"}';
select is(pg_temp.rows_affected($$update public.food_activity_sales
     set category = 'activity', item_name = 'Walk-in sauna'
   where item_name = 'Walk-in snack'$$), 1,
  'the owner moves it to activities as a sauna session');
select is((select tax_pct::text || '/' || tax_amount::text from public.food_activity_sales
            where item_name = 'Walk-in sauna'),
  '18.00/18.00', 'a changed category takes the new category''s current rate');
select is(pg_temp.rows_affected($$update public.food_activity_sales
     set tax_pct = 0, tax_amount = 0
   where item_name = 'Walk-in sauna'$$), 1,
  'the owner tries to zero a sale''s tax');
select is((select tax_pct::text || '/' || tax_amount::text from public.food_activity_sales
            where item_name = 'Walk-in sauna'),
  '18.00/18.00', 'a sale''s tax cannot be changed by an update');

-- ---------------------------------------------------------------------
-- Task 3: the bill, the Ledger and today's summary.
--
-- R1 now has O1 (525, tax 25.00), O2 (105, tax 11.25), A1 (2,360, tax
-- 360.00) and the cancelled A2. Today's walk-ins: the thali (336, tax
-- 36.00), yoga (590, tax 90.00) and the sauna (118, tax 18.00). R2
-- arrives today: 2,000 of room with 240 of tax.

set local request.jwt.claims to '{"sub":"44000000-0000-0000-0000-000000000004","role":"authenticated"}';
select is((public.current_charges('44444444-0000-4000-8000-000000000051') ->> 'food_amount')::numeric,
  630::numeric, 'the bill has 630 of food (525 + 105)');
select is((public.current_charges('44444444-0000-4000-8000-000000000051') ->> 'food_tax')::numeric,
  36.25, 'which includes 36.25 of tax (25.00 + 11.25)');
select is((public.current_charges('44444444-0000-4000-8000-000000000051') ->> 'activity_amount')::numeric,
  2360::numeric, 'a massage for one that was cancelled is not on the bill');
select is((public.current_charges('44444444-0000-4000-8000-000000000051') ->> 'activity_tax')::numeric,
  360.00, 'the activities include 360.00 of tax');
select is((public.current_charges('44444444-0000-4000-8000-000000000051') ->> 'total')::numeric,
  7990::numeric, 'tax is inside the amounts, so the total is 5,000 + 630 + 2,360');

-- Anil (accountant) reads today's Ledger and summary.
set local request.jwt.claims to '{"sub":"44000000-0000-0000-0000-000000000003","role":"authenticated"}';
select is(
  (select string_agg(l.category || '/' || l.source || '/' || l.gross || '/' || l.tax || '/' || l.net,
                     '; ' order by l.category, l.source)
     from public.report_ledger((now() at time zone 'Asia/Kolkata')::date,
                               (now() at time zone 'Asia/Kolkata')::date,
                               '44444444-0000-4000-8000-000000000001') l),
  'food_beverage/in_stay_order/593.75/36.25/630.00; '
  'food_beverage/walk_in/300.00/36.00/336.00; '
  'room/booking/2000.00/240.00/2240.00; '
  'spa_activities/activity_booking/2000.00/360.00/2360.00; '
  'spa_activities/walk_in/600.00/108.00/708.00',
  'the Ledger splits food, activities and walk-ins into pre-tax and tax');
select is(
  (select count(*)::int
     from public.report_ledger((now() at time zone 'Asia/Kolkata')::date,
                               (now() at time zone 'Asia/Kolkata')::date,
                               '44444444-0000-4000-8000-000000000001') l
    where l.taxable + l.tax <> l.net),
  0, 'every Ledger line has taxable + tax = net');
select is((public.finance_summary('44444444-0000-4000-8000-000000000001') ->> 'room_tax')::numeric,
  240.00, 'room tax is the booking''s tax only');
select is((public.finance_summary('44444444-0000-4000-8000-000000000001') ->> 'food_tax')::numeric,
  72.25, 'food tax is today''s orders and food walk-ins (36.25 + 36.00)');
select is((public.finance_summary('44444444-0000-4000-8000-000000000001') ->> 'spa_tax')::numeric,
  468.00, 'spa tax is today''s bookings and activity walk-ins (360.00 + 108.00)');
select is(
  (select (s -> 'resort' ->> 'fnb_tax_pct') || '/' || (s -> 'resort' ->> 'spa_tax_pct')
     from public.finance_summary('44444444-0000-4000-8000-000000000001') s),
  '12.00/18.00', 'the summary carries the resort''s food and spa rates');

-- The kitchen cancels O2; its tax leaves Gita's bill.
set local request.jwt.claims to '{"sub":"44000000-0000-0000-0000-000000000002","role":"authenticated"}';
update public.food_orders set status = 'cancelled'
 where reservation_id = '44444444-0000-4000-8000-000000000051' and total = 105;
set local request.jwt.claims to '{"sub":"44000000-0000-0000-0000-000000000004","role":"authenticated"}';
select is((public.current_charges('44444444-0000-4000-8000-000000000051') ->> 'food_tax')::numeric,
  25.00, 'a cancelled order''s tax leaves the bill');

select * from finish();
rollback;
