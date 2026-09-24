-- Finance ledger and collections (REQ-07), added in 0048_finance_ledger.sql.
-- See docs/superpowers/specs/2026-09-25-finance-ledger-design.md.
--
-- One file, built up by the plan's database tasks in order: each section
-- relies on the state the sections before it leave behind.
--
-- Resort R (Asia/Kolkata, 12% tax, a GSTIN) has an owner (Olga), an admin
-- (Arun), a staff member (Sita) and an accountant (Anil). Resort S has an
-- accountant (Sara). Gita and Ravi are guests.
--
-- "Today" fixtures (C1-C6 checked in now, B8 cancelled now, B9 arriving
-- today, W4 sold today) feed the checkout, summary and settlements tests.
-- "August 2026" fixtures (B1-B7, SX, W1-W3) feed Collections and the
-- Ledger, with every amount worked out in the test that reads it.
begin;
select plan(63);

-- Before any fixture: every payment the seed already holds became gateway.
select is((select count(*)::int from public.payments where method <> 'gateway'), 0,
  'every payment that existed before 0048 is gateway');

insert into auth.users (id, email) values
  ('f0000000-0000-0000-0000-000000000001','fin-r-owner@example.com'),
  ('f0000000-0000-0000-0000-000000000002','fin-r-admin@example.com'),
  ('f0000000-0000-0000-0000-000000000003','fin-r-staff@example.com'),
  ('f0000000-0000-0000-0000-000000000004','fin-r-accountant@example.com'),
  ('f0000000-0000-0000-0000-000000000005','fin-s-accountant@example.com'),
  ('f0000000-0000-0000-0000-000000000006','fin-gita@example.com'),
  ('f0000000-0000-0000-0000-000000000007','fin-ravi@example.com');
update public.profiles set full_name = 'Sita Staff'  where id = 'f0000000-0000-0000-0000-000000000003';
update public.profiles set full_name = 'Anil Accounts' where id = 'f0000000-0000-0000-0000-000000000004';
update public.profiles set full_name = 'Sara Other'  where id = 'f0000000-0000-0000-0000-000000000005';
update public.profiles set full_name = 'Gita Guest'  where id = 'f0000000-0000-0000-0000-000000000006';
update public.profiles set full_name = 'Ravi Guest'  where id = 'f0000000-0000-0000-0000-000000000007';

insert into public.properties (id, name, slug, tax_pct, gstin) values
  ('ffffffff-0000-4000-8000-000000000001','Resort R','fin-r',12,'29ABCDE1234F1Z5'),
  ('ffffffff-0000-4000-8000-000000000002','Resort S','fin-s',0,null);

insert into public.resort_members (property_id, user_id, role) values
  ('ffffffff-0000-4000-8000-000000000001','f0000000-0000-0000-0000-000000000001','owner'),
  ('ffffffff-0000-4000-8000-000000000001','f0000000-0000-0000-0000-000000000002','admin'),
  ('ffffffff-0000-4000-8000-000000000001','f0000000-0000-0000-0000-000000000003','staff'),
  ('ffffffff-0000-4000-8000-000000000001','f0000000-0000-0000-0000-000000000004','accountant'),
  ('ffffffff-0000-4000-8000-000000000002','f0000000-0000-0000-0000-000000000005','accountant');

insert into public.units (id, property_id, name, capacity_base, capacity_max) values
  ('ffffffff-0000-4000-8000-000000000011','ffffffff-0000-4000-8000-000000000001','Cottage 1',2,4),
  ('ffffffff-0000-4000-8000-000000000012','ffffffff-0000-4000-8000-000000000001','Cottage 2',2,4),
  ('ffffffff-0000-4000-8000-000000000013','ffffffff-0000-4000-8000-000000000001','Cottage 3',2,4),
  ('ffffffff-0000-4000-8000-000000000014','ffffffff-0000-4000-8000-000000000001','Cottage 4',2,4),
  ('ffffffff-0000-4000-8000-000000000015','ffffffff-0000-4000-8000-000000000001','Cottage 5',2,4),
  ('ffffffff-0000-4000-8000-000000000016','ffffffff-0000-4000-8000-000000000001','Cottage 6',2,4),
  ('ffffffff-0000-4000-8000-000000000017','ffffffff-0000-4000-8000-000000000002','S Villa',2,4);

insert into public.activities (id, property_id, name, price_per_person, capacity_per_slot) values
  ('ffffffff-0000-4000-8000-000000000041','ffffffff-0000-4000-8000-000000000001','Kayak',600,10);

-- Today. C1-C6 are checked in now; their advances were paid two days ago.
insert into public.reservations (id, unit_id, period, kind, status, customer_id, guests, quote, checked_in_at) values
  ('ffffffff-0000-4000-8000-000000000021','ffffffff-0000-4000-8000-000000000011',
   tstzrange(now() - interval '1 day', now() + interval '1 day', '[)'),
   'booking','checked_in','f0000000-0000-0000-0000-000000000006',2, '{"total":3000}', now() - interval '1 day'),
  ('ffffffff-0000-4000-8000-000000000022','ffffffff-0000-4000-8000-000000000012',
   tstzrange(now() - interval '1 day', now() + interval '1 day', '[)'),
   'booking','checked_in','f0000000-0000-0000-0000-000000000007',2, '{"total":1500}', now() - interval '1 day'),
  ('ffffffff-0000-4000-8000-000000000023','ffffffff-0000-4000-8000-000000000017',
   tstzrange(now() - interval '1 day', now() + interval '1 day', '[)'),
   'booking','checked_in','f0000000-0000-0000-0000-000000000006',2, '{"total":2000}', now() - interval '1 day'),
  ('ffffffff-0000-4000-8000-000000000024','ffffffff-0000-4000-8000-000000000013',
   tstzrange(now() - interval '1 day', now() + interval '1 day', '[)'),
   'booking','checked_in','f0000000-0000-0000-0000-000000000007',2, '{"total":1000}', now() - interval '1 day'),
  -- Sita (staff at R) staying at her own resort.
  ('ffffffff-0000-4000-8000-000000000025','ffffffff-0000-4000-8000-000000000014',
   tstzrange(now() - interval '1 day', now() + interval '1 day', '[)'),
   'booking','checked_in','f0000000-0000-0000-0000-000000000003',2, '{"total":800}', now() - interval '1 day'),
  -- Sara (accountant at S) staying at R as a guest.
  ('ffffffff-0000-4000-8000-000000000026','ffffffff-0000-4000-8000-000000000015',
   tstzrange(now() - interval '1 day', now() + interval '1 day', '[)'),
   'booking','checked_in','f0000000-0000-0000-0000-000000000005',2, '{"total":1200}', now() - interval '1 day');

-- B9 arrives at 14:00 today (resort time): 2,000 of room at 12% = 240 tax.
-- B8 was cancelled just now with 600 paid and 600 refunded.
insert into public.reservations (id, unit_id, period, kind, status, customer_id, guests, quote, cancelled_at, refund_amount) values
  ('ffffffff-0000-4000-8000-000000000027','ffffffff-0000-4000-8000-000000000016',
   tstzrange(((now() at time zone 'Asia/Kolkata')::date + time '14:00') at time zone 'Asia/Kolkata',
             ((now() at time zone 'Asia/Kolkata')::date + 1 + time '11:00') at time zone 'Asia/Kolkata', '[)'),
   'booking','confirmed','f0000000-0000-0000-0000-000000000007',2,
   '{"subtotal":2000,"cleaning_fee":0,"coupon":null,"tax_pct":12,"tax_amount":240,"total":2240}', null, null),
  ('ffffffff-0000-4000-8000-000000000028','ffffffff-0000-4000-8000-000000000016',
   tstzrange('2026-12-01 14:00+05:30','2026-12-02 11:00+05:30','[)'),
   'booking','cancelled','f0000000-0000-0000-0000-000000000006',2, '{"total":1000}', now(), 600);

insert into public.payments (reservation_id, amount, kind, status, gateway_ref, created_at) values
  ('ffffffff-0000-4000-8000-000000000021',1000,'advance','succeeded','fin-c1-adv', now() - interval '2 days'),
  ('ffffffff-0000-4000-8000-000000000022', 500,'advance','succeeded','fin-c2-adv', now() - interval '2 days'),
  ('ffffffff-0000-4000-8000-000000000023',1000,'advance','succeeded','fin-c3-adv', now() - interval '2 days'),
  ('ffffffff-0000-4000-8000-000000000024',1000,'advance','succeeded','fin-c4-adv', now() - interval '2 days'),
  ('ffffffff-0000-4000-8000-000000000028', 600,'advance','succeeded','fin-b8-adv', now() - interval '2 days');

-- August 2026.
-- B1: two nights of 4,000 + 1,000 extra guest = 10,000 subtotal; cleaning
-- 500; coupon 1,000; tax 12% of 9,500 = 1,140; total 10,640. Paid 5,000
-- online on 1 Aug and 7,540 in cash at the desk on checkout (10,640 +
-- 700 food + 1,200 kayak - 5,000).
insert into public.reservations (id, unit_id, period, kind, status, customer_id, guests, quote,
                                 checked_in_at, checked_out_at, cancelled_at, refund_amount) values
  ('ffffffff-0000-4000-8000-000000000031','ffffffff-0000-4000-8000-000000000011',
   tstzrange('2026-08-10 14:00+05:30','2026-08-12 11:00+05:30','[)'),
   'booking','checked_out','f0000000-0000-0000-0000-000000000006',3,
   jsonb_build_object(
     'subtotal',10000,'cleaning_fee',500,
     'coupon',jsonb_build_object('code','AUG10','kind','fixed','value',1000,'discount',1000),
     'tax_pct',12,'tax_amount',1140,'total',10640,
     'lines',jsonb_build_array(
       jsonb_build_object('date','2026-08-10','amount',4000,'extra_guests',1,'extra_guest_amount',1000),
       jsonb_build_object('date','2026-08-11','amount',4000,'extra_guests',1,'extra_guest_amount',1000))),
   '2026-08-10 14:05+05:30','2026-08-12 10:30+05:30', null, null),
  -- B2: the coupon (1,200) is bigger than the subtotal (1,000); 200 spills
  -- onto the cleaning fee, which carries all 36 of tax.
  ('ffffffff-0000-4000-8000-000000000032','ffffffff-0000-4000-8000-000000000012',
   tstzrange('2026-08-13 14:00+05:30','2026-08-14 11:00+05:30','[)'),
   'booking','confirmed','f0000000-0000-0000-0000-000000000007',2,
   jsonb_build_object(
     'subtotal',1000,'cleaning_fee',500,
     'coupon',jsonb_build_object('code','BIG','kind','fixed','value',1200,'discount',1200),
     'tax_pct',12,'tax_amount',36,'total',336),
   null, null, null, null),
  -- B3: a hand-made quote with only a total.
  ('ffffffff-0000-4000-8000-000000000033','ffffffff-0000-4000-8000-000000000013',
   tstzrange('2026-08-14 14:00+05:30','2026-08-15 11:00+05:30','[)'),
   'booking','confirmed','f0000000-0000-0000-0000-000000000007',2, '{"total":2000}',
   null, null, null, null),
  -- B4: paid 2,000, cancelled on 5 Aug with 1,500 refunded; 500 kept.
  ('ffffffff-0000-4000-8000-000000000034','ffffffff-0000-4000-8000-000000000014',
   tstzrange('2026-08-20 14:00+05:30','2026-08-21 11:00+05:30','[)'),
   'booking','cancelled','f0000000-0000-0000-0000-000000000006',2, '{"total":4000}',
   null, null, '2026-08-05 12:00+05:30', 1500),
  -- B5: an unpaid hold cancelled on 6 Aug; its 800 "refund" was never paid.
  ('ffffffff-0000-4000-8000-000000000035','ffffffff-0000-4000-8000-000000000014',
   tstzrange('2026-08-22 14:00+05:30','2026-08-23 11:00+05:30','[)'),
   'booking','cancelled','f0000000-0000-0000-0000-000000000007',2, '{"total":3000}',
   null, null, '2026-08-06 12:00+05:30', 800),
  -- B6: paid 1,000, cancelled on 7 Aug with a 3,000 refund on the books.
  ('ffffffff-0000-4000-8000-000000000036','ffffffff-0000-4000-8000-000000000013',
   tstzrange('2026-08-24 14:00+05:30','2026-08-25 11:00+05:30','[)'),
   'booking','cancelled','f0000000-0000-0000-0000-000000000006',2, '{"total":6000}',
   null, null, '2026-08-07 12:00+05:30', 3000),
  -- B7: 1,000 advance, 2,000 balance paid online at self-checkout.
  ('ffffffff-0000-4000-8000-000000000037','ffffffff-0000-4000-8000-000000000012',
   tstzrange('2026-08-20 14:00+05:30','2026-08-21 11:00+05:30','[)'),
   'booking','checked_out','f0000000-0000-0000-0000-000000000006',2, '{"total":3000}',
   '2026-08-20 14:10+05:30','2026-08-21 10:00+05:30', null, null),
  -- SX: resort S's booking; none of it may show up at R.
  ('ffffffff-0000-4000-8000-000000000038','ffffffff-0000-4000-8000-000000000017',
   tstzrange('2026-08-10 14:00+05:30','2026-08-11 11:00+05:30','[)'),
   'booking','confirmed','f0000000-0000-0000-0000-000000000007',2, '{"total":9999}',
   null, null, null, null);

insert into public.payments (reservation_id, amount, kind, status, gateway, gateway_ref, method, reference, recorded_by, created_at) values
  ('ffffffff-0000-4000-8000-000000000031',5000,'advance','succeeded','mock','fin-b1-adv','gateway',null,null,'2026-08-01 10:00+05:30'),
  ('ffffffff-0000-4000-8000-000000000031',7540,'balance','succeeded','desk','desk-ffffffff-0000-4000-8000-000000000031','cash','R-101',
   'f0000000-0000-0000-0000-000000000003','2026-08-12 10:30+05:30'),
  ('ffffffff-0000-4000-8000-000000000032', 336,'advance','succeeded','mock','fin-b2-adv','gateway',null,null,'2026-08-02 09:00+05:30'),
  ('ffffffff-0000-4000-8000-000000000032', 999,'advance','failed',   'mock','fin-b2-failed','gateway',null,null,'2026-08-02 09:05+05:30'),
  -- B3 is paid in two halves either side of midnight, resort time: 23:30
  -- on 24 Aug, and 00:15 on 25 Aug (still 24 Aug in UTC).
  ('ffffffff-0000-4000-8000-000000000033', 500,'advance','succeeded','mock','fin-b3-late','gateway',null,null,'2026-08-24 23:30+05:30'),
  ('ffffffff-0000-4000-8000-000000000033', 500,'advance','succeeded','mock','fin-b3-early','gateway',null,null,'2026-08-25 00:15+05:30'),
  ('ffffffff-0000-4000-8000-000000000034',2000,'advance','succeeded','mock','fin-b4-adv','gateway',null,null,'2026-08-03 11:00+05:30'),
  ('ffffffff-0000-4000-8000-000000000036',1000,'advance','succeeded','mock','fin-b6-adv','gateway',null,null,'2026-08-04 11:00+05:30'),
  ('ffffffff-0000-4000-8000-000000000037',1000,'advance','succeeded','mock','fin-b7-adv','gateway',null,null,'2026-08-15 11:00+05:30'),
  ('ffffffff-0000-4000-8000-000000000037',2000,'balance','succeeded','mock','fin-b7-bal','gateway',null,null,'2026-08-21 10:00+05:30'),
  ('ffffffff-0000-4000-8000-000000000038',9999,'advance','succeeded','mock','fin-sx-adv','gateway',null,null,'2026-08-01 10:00+05:30');

-- B1's stay: 700 of food and a 1,200 kayak count; the cancelled order
-- and the cancelled kayak do not.
insert into public.food_orders (reservation_id, status, total, created_at) values
  ('ffffffff-0000-4000-8000-000000000031','delivered',700,'2026-08-11 20:00+05:30'),
  ('ffffffff-0000-4000-8000-000000000031','cancelled',300,'2026-08-11 21:00+05:30');
insert into public.activity_bookings (reservation_id, activity_id, booking_date, start_time, people, amount, status) values
  ('ffffffff-0000-4000-8000-000000000031','ffffffff-0000-4000-8000-000000000041','2026-08-11','10:00',2,1200,'booked'),
  ('ffffffff-0000-4000-8000-000000000031','ffffffff-0000-4000-8000-000000000041','2026-08-11','16:00',1,600,'cancelled');

-- Walk-in sales. W3 ("Tea") gives no method, so it takes the default.
insert into public.food_activity_sales (property_id, sale_date, category, item_name, quantity, unit_price, amount, payment_method, recorded_by) values
  ('ffffffff-0000-4000-8000-000000000001','2026-08-10','food','Thali',2,250,500,'cash','f0000000-0000-0000-0000-000000000003'),
  ('ffffffff-0000-4000-8000-000000000001','2026-08-10','activity','Pool pass',1,300,300,'upi','f0000000-0000-0000-0000-000000000003'),
  ('ffffffff-0000-4000-8000-000000000001',(now() at time zone 'Asia/Kolkata')::date,'food','Coffee',1,120,120,'card','f0000000-0000-0000-0000-000000000003'),
  ('ffffffff-0000-4000-8000-000000000002','2026-08-10','food','S snack',1,100,100,'cash','f0000000-0000-0000-0000-000000000005');
insert into public.food_activity_sales (property_id, sale_date, category, item_name, quantity, unit_price, amount, recorded_by) values
  ('ffffffff-0000-4000-8000-000000000001','2026-08-10','food','Tea',1,50,50,'f0000000-0000-0000-0000-000000000003');

-- === Task 1: the contract ===================================================

select enum_has_labels('public', 'payment_method',
  array['gateway','cash','card','upi','bank_transfer','other'],
  'payment_method is gateway, cash, card, upi, bank_transfer, other');
select is((select array_agg(column_name::text order by column_name)
             from information_schema.columns
            where table_schema = 'public' and table_name = 'payments'
              and column_name in ('method','reference','recorded_by')),
  array['method','recorded_by','reference'], 'payments gains method, reference and recorded_by');

-- A probe row on S's booking. It is `failed`, so no report counts it.
set local request.jwt.claims to '{"sub":"f0000000-0000-0000-0000-000000000005","role":"authenticated"}';
insert into public.payments (reservation_id, amount, kind, status, gateway_ref, created_at)
  values ('ffffffff-0000-4000-8000-000000000023', 1, 'advance', 'failed', 'fin-probe', '2025-01-01 10:00+05:30');
set local request.jwt.claims to '';
select is((select method::text || '|' || (recorded_by = 'f0000000-0000-0000-0000-000000000005')::text
             from public.payments where gateway_ref = 'fin-probe'),
  'gateway|true', 'a payment written without a method is gateway and records who wrote it');
select throws_ok($$insert into public.payments (reservation_id, amount, kind, status, gateway_ref, reference)
  values ('ffffffff-0000-4000-8000-000000000023', 1, 'advance', 'failed', 'fin-probe-2', repeat('x', 65))$$,
  '23514', null, 'a reference longer than 64 characters is refused');
select has_index('public', 'payments', 'payments_property_created_idx',
  'payments are indexed by resort and date for the reports');

select is((select payment_method::text from public.food_activity_sales where item_name = 'Tea'),
  'cash', 'a walk-in sale without a method is cash');
select throws_ok($$insert into public.food_activity_sales (property_id, category, item_name, unit_price, amount, payment_method, recorded_by)
  values ('ffffffff-0000-4000-8000-000000000001', 'food', 'Probe', 10, 10, 'gateway', 'f0000000-0000-0000-0000-000000000003')$$,
  '23514', null, 'a walk-in sale can never be gateway');
select throws_ok($$insert into public.food_activity_sales (property_id, category, item_name, unit_price, amount, payment_method, recorded_by)
  values ('ffffffff-0000-4000-8000-000000000001', 'food', 'Probe', 10, 10, null, 'f0000000-0000-0000-0000-000000000003')$$,
  '23502', null, 'a walk-in sale always has a method');
select is(array[public.payment_method_from_text('Cash'),
                public.payment_method_from_text('  NEFT '),
                public.payment_method_from_text('Bank Transfer'),
                public.payment_method_from_text('bank_transfer'),
                public.payment_method_from_text('IMPS'),
                public.payment_method_from_text('upi'),
                public.payment_method_from_text('CARD'),
                public.payment_method_from_text('xyz'),
                public.payment_method_from_text(null),
                public.payment_method_from_text('gateway')]::text[],
  array['cash','bank_transfer','bank_transfer','bank_transfer','bank_transfer','upi','card','other','other','other'],
  'legacy walk-in text maps onto the method list');

select ok(to_regprocedure('public.checkout_booking(uuid, text, numeric, public.payment_method)') is not null,
  'checkout_booking takes a payment method');
select ok(to_regprocedure('public.checkout_booking(uuid, text, numeric)') is null,
  'the three-argument checkout_booking is gone');
select is((select array_agg(p.parameter_name::text order by p.ordinal_position)
             from information_schema.parameters p
             join information_schema.routines r
               on r.specific_schema = p.specific_schema and r.specific_name = p.specific_name
            where r.routine_schema = 'public' and r.routine_name = 'report_collections'
              and p.parameter_mode = 'OUT'),
  array['day','channel','source','method','txn_count','amount'],
  'report_collections returns the columns CollectionRow.fromJson reads');
select is((select array_agg(p.parameter_name::text order by p.ordinal_position)
             from information_schema.parameters p
             join information_schema.routines r
               on r.specific_schema = p.specific_schema and r.specific_name = p.specific_name
            where r.routine_schema = 'public' and r.routine_name = 'report_ledger'
              and p.parameter_mode = 'OUT'),
  array['day','category','source','gross','discount','taxable','tax','net'],
  'report_ledger returns the columns LedgerRow.fromJson reads');
select is((select array_agg(p.parameter_name::text order by p.ordinal_position)
             from information_schema.parameters p
             join information_schema.routines r
               on r.specific_schema = p.specific_schema and r.specific_name = p.specific_name
            where r.routine_schema = 'public' and r.routine_name = 'report_settlements'
              and p.parameter_mode = 'OUT'),
  array['reservation_id','guest_name','unit_name','arrival','departure','room','cleaning_fee',
        'tax_pct','tax','food','activities','total','advance_paid','balance_online',
        'balance_desk','desk_method','desk_reference','recorded_by_name','outstanding'],
  'report_settlements returns the columns SettlementRow.fromJson reads');
select is((select data_type::text from information_schema.routines
            where routine_schema = 'public' and routine_name = 'finance_summary'),
  'jsonb', 'finance_summary returns jsonb');
select is((select array_agg(f::text order by f::text)
             from unnest(array[
               'public.report_collections(date, date, uuid)',
               'public.report_ledger(date, date, uuid)',
               'public.report_settlements(date, date, uuid)',
               'public.finance_summary(uuid)',
               'public.checkout_booking(uuid, text, numeric, public.payment_method)']::regprocedure[]) f
            where has_function_privilege('anon', f, 'execute')),
  null, 'anon can execute none of the finance functions');
select is((select count(*)::int
             from unnest(array[
               'public.report_collections(date, date, uuid)',
               'public.report_ledger(date, date, uuid)',
               'public.report_settlements(date, date, uuid)',
               'public.finance_summary(uuid)',
               'public.checkout_booking(uuid, text, numeric, public.payment_method)']::regprocedure[]) f
            where has_function_privilege('authenticated', f, 'execute')),
  5, 'authenticated can execute all five finance functions');

-- === Task 2: checkout_booking records the payment method =================

set local role authenticated;
-- A guest cannot record a desk method, even for the exact balance.
set local request.jwt.claims to '{"sub":"f0000000-0000-0000-0000-000000000007","role":"authenticated"}';
select throws_ok($$select public.checkout_booking('ffffffff-0000-4000-8000-000000000022', 'x', 1000, 'cash')$$,
  'P0009', 'desk payment methods are recorded by resort staff',
  'a guest passing a desk method is refused');
-- Review Focus 1: Sara is an accountant, but at resort S, not here.
set local request.jwt.claims to '{"sub":"f0000000-0000-0000-0000-000000000005","role":"authenticated"}';
select throws_ok($$select public.checkout_booking('ffffffff-0000-4000-8000-000000000026', null, 1200, 'cash')$$,
  'P0009', 'desk payment methods are recorded by resort staff',
  'a member of another resort cannot record a desk method here');

-- Reception takes cash with a receipt number (typed with stray spaces).
set local request.jwt.claims to '{"sub":"f0000000-0000-0000-0000-000000000003","role":"authenticated"}';
select lives_ok($$select public.checkout_booking('ffffffff-0000-4000-8000-000000000021', ' R-555 ', 2000, 'cash')$$,
  'staff record a cash balance with a receipt number');
select is((select gateway || '|' || gateway_ref || '|' || method::text || '|' || reference || '|'
                  || amount::text || '|' || (recorded_by = 'f0000000-0000-0000-0000-000000000003')::text
             from public.payments
            where reservation_id = 'ffffffff-0000-4000-8000-000000000021' and kind = 'balance'),
  'desk|desk-ffffffff-0000-4000-8000-000000000021|cash|R-555|2000.00|true',
  'the desk row: gateway desk, one ref per booking, the method, the trimmed reference, who recorded it');

-- Review Focus 2: a retry, even with another method, changes nothing.
select lives_ok($$select public.checkout_booking('ffffffff-0000-4000-8000-000000000021', 'R-999', 2000, 'card')$$,
  'a retried checkout returns the booking');
select is((select count(*)::text || '|' || min(method::text) || '|' || min(reference)
             from public.payments
            where reservation_id = 'ffffffff-0000-4000-8000-000000000021' and kind = 'balance'),
  '1|cash|R-555', 'the retry writes no second payment and changes nothing');
select is((select state::text from public.unit_room_status
            where unit_id = 'ffffffff-0000-4000-8000-000000000011'),
  'dirty', 'checkout still marks the room for cleaning (0047)');

-- Guest self-checkout is unchanged, and still takes three arguments.
set local request.jwt.claims to '{"sub":"f0000000-0000-0000-0000-000000000007","role":"authenticated"}';
select lives_ok($$select public.checkout_booking('ffffffff-0000-4000-8000-000000000022', 'fin-c2-bal', 1000)$$,
  'a guest''s own checkout still works with three arguments');
select is((select gateway || '|' || gateway_ref || '|' || method::text || '|' || coalesce(reference, '-') || '|'
                  || amount::text || '|' || (recorded_by = 'f0000000-0000-0000-0000-000000000007')::text
             from public.payments
            where reservation_id = 'ffffffff-0000-4000-8000-000000000022' and kind = 'balance'),
  'mock|fin-c2-bal|gateway|-|1000.00|true', 'guest self-checkout is an online gateway payment');

-- Another resort may issue the same receipt number.
set local request.jwt.claims to '{"sub":"f0000000-0000-0000-0000-000000000005","role":"authenticated"}';
select lives_ok($$select public.checkout_booking('ffffffff-0000-4000-8000-000000000023', 'R-555', 1000, 'card')$$,
  'resort S''s accountant records a card payment with the same receipt number');
reset role;
set local request.jwt.claims to '';
select is((select count(*)::text || '|' || count(distinct property_id)::text
             from public.payments where reference = 'R-555'),
  '2|2', 'two resorts using the same reference both succeed');
set local role authenticated;

-- Review Focus 4: nothing left to pay writes nothing.
set local request.jwt.claims to '{"sub":"f0000000-0000-0000-0000-000000000002","role":"authenticated"}';
select lives_ok($$select public.checkout_booking('ffffffff-0000-4000-8000-000000000024', null, 0, 'upi')$$,
  'a fully paid booking checks out at the desk');
select is((select count(*)::int from public.payments
            where reservation_id = 'ffffffff-0000-4000-8000-000000000024' and kind = 'balance'),
  0, 'nothing left to pay writes no payment');

-- A staff member checking out their own stay may still use a desk method.
set local request.jwt.claims to '{"sub":"f0000000-0000-0000-0000-000000000003","role":"authenticated"}';
select lives_ok($$select public.checkout_booking('ffffffff-0000-4000-8000-000000000025', '   ', 800, 'cash')$$,
  'a staff member checking out their own stay may record cash');
select is((select method::text || '|' || coalesce(reference, '-') || '|' || amount::text
             from public.payments
            where reservation_id = 'ffffffff-0000-4000-8000-000000000025' and kind = 'balance'),
  'cash|-|800.00', 'a blank reference is stored as none');
select is((select status::text from public.reservations
            where id = 'ffffffff-0000-4000-8000-000000000026'),
  'checked_in', 'the refused desk checkout left the booking checked in');

reset role;
set local request.jwt.claims to '';

-- === Task 3: report_collections =============================================

set local role authenticated;
set local request.jwt.claims to '{"sub":"f0000000-0000-0000-0000-000000000004","role":"authenticated"}';
select is((select count(*)::int
             from public.report_collections('2026-08-01', '2026-08-31', 'ffffffff-0000-4000-8000-000000000001')),
  13, 'August has 13 collection lines');
select is((select string_agg(c.channel || '|' || c.source || '|' || c.method::text || '|' || c.txn_count || '|' || c.amount,
                             ';' order by c.channel, c.source, c.method)
             from public.report_collections('2026-08-01', '2026-08-31', 'ffffffff-0000-4000-8000-000000000001') c
            where c.day = '2026-08-01'),
  'online|booking_advance|gateway|1|5000.00',
  'an online advance is dated by its payment, and resort S''s payment stays out');
select is((select string_agg(c.channel || '|' || c.source || '|' || c.method::text || '|' || c.txn_count || '|' || c.amount, ';')
             from public.report_collections('2026-08-01', '2026-08-31', 'ffffffff-0000-4000-8000-000000000001') c
            where c.day = '2026-08-02'),
  'online|booking_advance|gateway|1|336.00', 'a failed payment is not a collection');
select is((select string_agg(c.channel || '|' || c.source || '|' || c.method::text || '|' || c.txn_count || '|' || c.amount, ';')
             from public.report_collections('2026-08-01', '2026-08-31', 'ffffffff-0000-4000-8000-000000000001') c
            where c.day = '2026-08-05'),
  'online|refund|gateway|1|-1500.00', 'a refund is negative, online, on the cancel date');
select is((select count(*)::int
             from public.report_collections('2026-08-01', '2026-08-31', 'ffffffff-0000-4000-8000-000000000001') c
            where c.day = '2026-08-06'),
  0, 'a cancelled unpaid hold shows no refund');
select is((select string_agg(c.channel || '|' || c.source || '|' || c.method::text || '|' || c.txn_count || '|' || c.amount, ';')
             from public.report_collections('2026-08-01', '2026-08-31', 'ffffffff-0000-4000-8000-000000000001') c
            where c.day = '2026-08-07'),
  'online|refund|gateway|1|-1000.00', 'a refund larger than the amount paid is capped at what was paid');
select is((select string_agg(c.channel || '|' || c.source || '|' || c.method::text || '|' || c.txn_count || '|' || c.amount,
                             ';' order by c.method)
             from public.report_collections('2026-08-01', '2026-08-31', 'ffffffff-0000-4000-8000-000000000001') c
            where c.day = '2026-08-10'),
  'front_desk|walk_in_sale|cash|2|550.00;front_desk|walk_in_sale|upi|1|300.00',
  'walk-in sales are front-desk money, by method');
select is((select string_agg(c.channel || '|' || c.source || '|' || c.method::text || '|' || c.txn_count || '|' || c.amount, ';')
             from public.report_collections('2026-08-01', '2026-08-31', 'ffffffff-0000-4000-8000-000000000001') c
            where c.day = '2026-08-12'),
  'front_desk|checkout_balance|cash|1|7540.00', 'a desk balance is front-desk money by its method');
select is((select string_agg(c.channel || '|' || c.source || '|' || c.method::text || '|' || c.txn_count || '|' || c.amount, ';')
             from public.report_collections('2026-08-01', '2026-08-31', 'ffffffff-0000-4000-8000-000000000001') c
            where c.day = '2026-08-21'),
  'online|checkout_balance|gateway|1|2000.00', 'a self-checkout balance is online money');
select is((select array_agg(c.day order by c.day)
             from public.report_collections('2026-08-24', '2026-08-25', 'ffffffff-0000-4000-8000-000000000001') c),
  array['2026-08-24', '2026-08-25']::date[],
  'payments at 23:30 and 00:15 resort time fall on their resort-local days');
select is((select count(*)::int
             from public.report_collections('2026-08-10', '2026-08-10', 'ffffffff-0000-4000-8000-000000000001')),
  2, 'a one-day range returns that day only');
select is((select sum(c.amount)
             from public.report_collections('2026-08-01', '2026-08-31', 'ffffffff-0000-4000-8000-000000000001') c),
  18226.00::numeric, 'August nets to 18,226.00');
-- Today, after Task 2: C1 and C5 were paid in cash at the desk.
select is((select c.method::text || '|' || c.txn_count || '|' || c.amount
             from public.report_collections((now() at time zone 'Asia/Kolkata')::date,
                                            (now() at time zone 'Asia/Kolkata')::date,
                                            'ffffffff-0000-4000-8000-000000000001') c
            where c.channel = 'front_desk' and c.source = 'checkout_balance'),
  'cash|2|2800.00', 'today''s desk checkouts are collected under cash');

reset role;
set local request.jwt.claims to '';

-- === Task 4: report_ledger ==================================================

set local role authenticated;
set local request.jwt.claims to '{"sub":"f0000000-0000-0000-0000-000000000004","role":"authenticated"}';
select is((select count(*)::int
             from public.report_ledger('2026-08-01', '2026-08-31', 'ffffffff-0000-4000-8000-000000000001')),
  11, 'August has 11 ledger lines');
select is((select l.gross || '|' || l.discount || '|' || l.taxable || '|' || l.tax || '|' || l.net
             from public.report_ledger('2026-08-10', '2026-08-10', 'ffffffff-0000-4000-8000-000000000001') l
            where l.category = 'room'),
  '10000.00|1000.00|9000.00|1080.00|10080.00',
  'nightly rates and extra guests are room gross; the coupon is its discount; tax is on what is left');
select is((select l.gross || '|' || l.discount || '|' || l.taxable || '|' || l.tax || '|' || l.net
             from public.report_ledger('2026-08-10', '2026-08-10', 'ffffffff-0000-4000-8000-000000000001') l
            where l.source = 'cleaning_fee'),
  '500.00|0.00|500.00|60.00|560.00', 'the cleaning fee is ancillary revenue with its share of the tax');
select is((select sum(l.tax)
             from public.report_ledger('2026-08-10', '2026-08-10', 'ffffffff-0000-4000-8000-000000000001') l
            where l.source in ('booking', 'cleaning_fee')),
  1140.00::numeric, 'room + cleaning tax equals the quote''s tax_amount (1,140)');
select is((select sum(l.net)
             from public.report_ledger('2026-08-10', '2026-08-10', 'ffffffff-0000-4000-8000-000000000001') l
            where l.source in ('booking', 'cleaning_fee')),
  10640.00::numeric, 'room + cleaning net equals the quote total (10,640)');
select is((select l.gross || '|' || l.discount || '|' || l.taxable || '|' || l.tax || '|' || l.net
             from public.report_ledger('2026-08-13', '2026-08-13', 'ffffffff-0000-4000-8000-000000000001') l
            where l.category = 'room'),
  '1000.00|1000.00|0.00|0.00|0.00', 'a coupon larger than the subtotal takes the whole room line');
select is((select l.gross || '|' || l.discount || '|' || l.taxable || '|' || l.tax || '|' || l.net
             from public.report_ledger('2026-08-13', '2026-08-13', 'ffffffff-0000-4000-8000-000000000001') l
            where l.source = 'cleaning_fee'),
  '500.00|200.00|300.00|36.00|336.00', 'the rest of the coupon spills onto the cleaning fee, which carries the tax');
select is((select string_agg(l.category || '|' || l.source || '|' || l.gross || '|' || l.discount || '|'
                             || l.taxable || '|' || l.tax || '|' || l.net, ';')
             from public.report_ledger('2026-08-14', '2026-08-14', 'ffffffff-0000-4000-8000-000000000001') l),
  'room|booking|2000.00|0.00|2000.00|0.00|2000.00', 'a total-only quote is all room gross, untaxed');
select is((select l.gross
             from public.report_ledger('2026-08-11', '2026-08-11', 'ffffffff-0000-4000-8000-000000000001') l
            where l.category = 'food_beverage' and l.source = 'in_stay_order'),
  700.00::numeric, 'in-stay food orders are F&B; a cancelled order is not');
select is((select l.gross
             from public.report_ledger('2026-08-11', '2026-08-11', 'ffffffff-0000-4000-8000-000000000001') l
            where l.category = 'spa_activities' and l.source = 'activity_booking'),
  1200.00::numeric, 'activity bookings are Spa/Activities; a cancelled one is not');
select is((select string_agg(l.category || '|' || l.gross, ';' order by l.category)
             from public.report_ledger('2026-08-10', '2026-08-10', 'ffffffff-0000-4000-8000-000000000001') l
            where l.source = 'walk_in'),
  'food_beverage|550.00;spa_activities|300.00', 'walk-in food is F&B and walk-in activities are Spa/Activities');
select is((select l.gross
             from public.report_ledger('2026-08-05', '2026-08-05', 'ffffffff-0000-4000-8000-000000000001') l
            where l.source = 'cancellation_fee'),
  500.00::numeric, 'the part of a paid booking kept on cancellation is an ancillary fee');
select is((select count(*)::int
             from public.report_ledger('2026-08-06', '2026-08-07', 'ffffffff-0000-4000-8000-000000000001')),
  0, 'no fee is kept from an unpaid hold or from a refund that took everything paid');
select is((select l.gross
             from public.report_ledger('2026-08-20', '2026-08-20', 'ffffffff-0000-4000-8000-000000000001') l
            where l.category = 'room'),
  3000.00::numeric, 'a cancelled booking is not room revenue');
select is((select bool_and(l.taxable = l.gross - l.discount and l.net = l.taxable + l.tax)
             from public.report_ledger('2026-08-01', '2026-08-31', 'ffffffff-0000-4000-8000-000000000001') l),
  true, 'every line has taxable = gross - discount and net = taxable + tax');
-- Today: B9 arrives with 2,000 of room at 12%.
select is((select l.tax
             from public.report_ledger((now() at time zone 'Asia/Kolkata')::date,
                                       (now() at time zone 'Asia/Kolkata')::date,
                                       'ffffffff-0000-4000-8000-000000000001') l
            where l.category = 'room'),
  240.00::numeric, 'today''s arrival carries its room tax on today');

reset role;
set local request.jwt.claims to '';

select * from finish();
rollback;
