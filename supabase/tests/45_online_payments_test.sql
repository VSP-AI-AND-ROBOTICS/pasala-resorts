-- Online payments through Razorpay (P6), added in 0055_online_payments.sql.
-- See docs/superpowers/specs/2026-09-25-p6-razorpay-online-payments-design.md.
--
-- One file, built up by the plan's database tasks in order: each section
-- relies on the state the sections before it leave behind.
--
-- Fixtures: resort A "Online A" (advance 50%) with an owner and a staff
-- member; resort B "Online B" (advance 100%) with an owner; guests Gita
-- (profile name and phone set) and Om. Reservations:
--   R1 ...31  A, hold, Gita, total 10000, expires in 10 minutes
--   R2 ...32  A, checked in, Gita, total 6000, 3000 paid -> 3000 due
--   R3 ...33  A, hold, Gita, total 4000, expired a minute ago (not swept)
--   R4 ...34  B, hold, Om, total 2000, expires in 10 minutes
--   R6 ...36  A, checked in, Om, total 1000, nothing paid
--   R7 ...37  A, hold, Gita, total 1000, expires in 10 minutes
-- and one Razorpay order, order_fixture_r1 (R1, advance 5000).
begin;
select plan(115);

insert into auth.users (id, email) values
  ('a6000000-0000-0000-0000-000000000001','p6-a-owner@example.com'),
  ('a6000000-0000-0000-0000-000000000002','p6-a-staff@example.com'),
  ('a6000000-0000-0000-0000-000000000003','p6-b-owner@example.com'),
  ('a6000000-0000-0000-0000-000000000004','p6-gita@example.com'),
  ('a6000000-0000-0000-0000-000000000005','p6-om@example.com');
update public.profiles set full_name = 'Gita Guest', phone = '+919800000001'
  where id = 'a6000000-0000-0000-0000-000000000004';

insert into public.properties (id, name, slug, advance_pct) values
  ('a6100000-0000-4000-8000-000000000001','Online A','online-a', 50),
  ('a6100000-0000-4000-8000-000000000002','Online B','online-b', 100);

insert into public.resort_members (property_id, user_id, role) values
  ('a6100000-0000-4000-8000-000000000001','a6000000-0000-0000-0000-000000000001','owner'),
  ('a6100000-0000-4000-8000-000000000001','a6000000-0000-0000-0000-000000000002','staff'),
  ('a6100000-0000-4000-8000-000000000002','a6000000-0000-0000-0000-000000000003','owner');

insert into public.units (id, property_id, name, capacity_base, capacity_max) values
  ('a6100000-0000-4000-8000-000000000011','a6100000-0000-4000-8000-000000000001','A Cottage 1',2,4),
  ('a6100000-0000-4000-8000-000000000012','a6100000-0000-4000-8000-000000000001','A Cottage 2',2,4),
  ('a6100000-0000-4000-8000-000000000013','a6100000-0000-4000-8000-000000000001','A Cottage 3',2,4),
  ('a6100000-0000-4000-8000-000000000021','a6100000-0000-4000-8000-000000000002','B Cottage 1',2,4);

insert into public.reservations
  (id, unit_id, period, kind, status, customer_id, guests, quote, hold_expires_at, checked_in_at) values
  ('a6100000-0000-4000-8000-000000000031','a6100000-0000-4000-8000-000000000011',
   public.build_period('a6100000-0000-4000-8000-000000000011', current_date + 10, current_date + 12),
   'booking','hold','a6000000-0000-0000-0000-000000000004',2,'{"total":10000}',
   now() + interval '10 minutes', null),
  ('a6100000-0000-4000-8000-000000000032','a6100000-0000-4000-8000-000000000012',
   tstzrange(now() - interval '1 day', now() + interval '1 day', '[)'),
   'booking','checked_in','a6000000-0000-0000-0000-000000000004',2,'{"total":6000}',
   null, now() - interval '1 day'),
  ('a6100000-0000-4000-8000-000000000033','a6100000-0000-4000-8000-000000000013',
   public.build_period('a6100000-0000-4000-8000-000000000013', current_date + 10, current_date + 11),
   'booking','hold','a6000000-0000-0000-0000-000000000004',2,'{"total":4000}',
   now() - interval '1 minute', null),
  ('a6100000-0000-4000-8000-000000000034','a6100000-0000-4000-8000-000000000021',
   public.build_period('a6100000-0000-4000-8000-000000000021', current_date + 10, current_date + 11),
   'booking','hold','a6000000-0000-0000-0000-000000000005',2,'{"total":2000}',
   now() + interval '10 minutes', null),
  ('a6100000-0000-4000-8000-000000000036','a6100000-0000-4000-8000-000000000013',
   tstzrange(now() - interval '1 day', now() + interval '1 day', '[)'),
   'booking','checked_in','a6000000-0000-0000-0000-000000000005',2,'{"total":1000}',
   null, now() - interval '1 day'),
  ('a6100000-0000-4000-8000-000000000037','a6100000-0000-4000-8000-000000000012',
   public.build_period('a6100000-0000-4000-8000-000000000012', current_date + 30, current_date + 31),
   'booking','hold','a6000000-0000-0000-0000-000000000004',2,'{"total":1000}',
   now() + interval '10 minutes', null);

insert into public.payments (reservation_id, amount, kind, status, gateway, gateway_ref)
values ('a6100000-0000-4000-8000-000000000032', 3000, 'advance', 'succeeded', 'mock', 'p6-r2-advance');

insert into public.payment_orders (reservation_id, customer_id, kind, amount, razorpay_order_id)
values ('a6100000-0000-4000-8000-000000000031','a6000000-0000-0000-0000-000000000004',
        'advance', 5000, 'order_fixture_r1');

-- === Task 1: the contract ===================================================

select has_table('public', 'payment_orders', 'payment_orders exists');
select has_table('public', 'payment_webhook_events', 'payment_webhook_events exists');
select has_table('public', 'payment_gateway_config', 'payment_gateway_config exists');
select enum_has_labels('public', 'payment_order_status',
  array['created','paid','unapplied','failed','refunded'],
  'payment_order_status is created, paid, unapplied, failed, refunded');
select is((select array_agg(column_name::text order by ordinal_position)
             from information_schema.columns
            where table_schema = 'public' and table_name = 'payment_orders'),
  array['id','property_id','reservation_id','customer_id','kind','amount','currency',
        'razorpay_order_id','razorpay_payment_id','status','payment_id','refunded_amount',
        'refund_ids','failure_reason','created_at','updated_at'],
  'payment_orders has the columns the functions and the app read');
select is((select count(*)::int from public.payment_gateway_config where not live), 1,
  'the gateway switch is one row, off');
select is(public.online_payments_live(), false, 'online payments start switched off');
select is((select array_agg(f::text order by f::text)
             from unnest(array[
               'public.payment_order_quote(uuid, public.payment_kind, numeric)',
               'public.payment_order_open(uuid, uuid, public.payment_kind, numeric, text)',
               'public.payment_order_settle(text, text)',
               'public.payment_order_failed(text, text)',
               'public.payment_order_refunded(text, text, numeric)',
               'public.payment_webhook_begin(text, text, jsonb)',
               'public.payment_webhook_done(text, text)',
               'public.payments_set_live(boolean, text)']::regprocedure[]) f
            where has_function_privilege('anon', f, 'execute')),
  null, 'anon can execute none of the payment functions');
select is((select count(*)::int
             from unnest(array[
               'public.payment_order_quote(uuid, public.payment_kind, numeric)',
               'public.payment_order_open(uuid, uuid, public.payment_kind, numeric, text)',
               'public.payment_order_settle(text, text)',
               'public.payment_order_failed(text, text)',
               'public.payment_order_refunded(text, text, numeric)',
               'public.payment_webhook_begin(text, text, jsonb)',
               'public.payment_webhook_done(text, text)',
               'public.payments_set_live(boolean, text)']::regprocedure[]) f
            where has_function_privilege('authenticated', f, 'execute')
              and f::oid <> 'public.payment_order_quote(uuid, public.payment_kind, numeric)'::regprocedure::oid),
  0, 'authenticated can execute only payment_order_quote');
select is((select count(*)::int
             from unnest(array[
               'public.payment_order_open(uuid, uuid, public.payment_kind, numeric, text)',
               'public.payment_order_settle(text, text)',
               'public.payment_order_failed(text, text)',
               'public.payment_order_refunded(text, text, numeric)',
               'public.payment_webhook_begin(text, text, jsonb)',
               'public.payment_webhook_done(text, text)',
               'public.payments_set_live(boolean, text)']::regprocedure[]) f
            where has_function_privilege('service_role', f, 'execute')),
  7, 'the service role executes the seven server-only functions');

-- Reads: the guest's own orders, and the resort's staff roles. No direct
-- writes for anyone; the two server tables are closed to clients.
set local role authenticated;
set local request.jwt.claims to '{"sub":"a6000000-0000-0000-0000-000000000004","role":"authenticated"}';
select is((select count(*)::int from public.payment_orders), 1,
  'the guest reads their own payment order');
select throws_ok($$insert into public.payment_orders (reservation_id, customer_id, kind, amount, razorpay_order_id)
  values ('a6100000-0000-4000-8000-000000000031','a6000000-0000-0000-0000-000000000004','advance',5000,'order_forged')$$,
  '42501', null, 'a guest cannot write payment orders');
select throws_ok($$select * from public.payment_webhook_events$$,
  '42501', null, 'webhook events are server-only');
select throws_ok($$select * from public.payment_gateway_config$$,
  '42501', null, 'the gateway switch is server-only');
set local request.jwt.claims to '{"sub":"a6000000-0000-0000-0000-000000000005","role":"authenticated"}';
select is((select count(*)::int from public.payment_orders), 0,
  'another guest reads none of them');
set local request.jwt.claims to '{"sub":"a6000000-0000-0000-0000-000000000002","role":"authenticated"}';
select is((select count(*)::int from public.payment_orders), 1,
  'staff read their resort''s payment orders');
set local request.jwt.claims to '{"sub":"a6000000-0000-0000-0000-000000000003","role":"authenticated"}';
select is((select count(*)::int from public.payment_orders), 0,
  'another resort''s owner reads none of them');
reset role;
set local request.jwt.claims to '';

-- === Task 2: quoting and opening an order ====================================

set local role authenticated;
set local request.jwt.claims to '{"sub":"a6000000-0000-0000-0000-000000000004","role":"authenticated"}';

select is(public.payment_order_quote('a6100000-0000-4000-8000-000000000031', 'advance', 5000) ->> 'amount_paise',
  '500000', 'a 50% advance is quoted in paise');
select is(public.payment_order_quote('a6100000-0000-4000-8000-000000000031', 'advance', 5000) ->> 'customer_id',
  'a6000000-0000-0000-0000-000000000004', 'the quote names the paying guest');
select is(public.payment_order_quote('a6100000-0000-4000-8000-000000000031', 'advance', 5000) ->> 'receipt',
  'a6100000-0000-4000-8000-000000000031', 'the receipt is the reservation id');
select is(public.payment_order_quote('a6100000-0000-4000-8000-000000000031', 'advance', 5000) ->> 'description',
  'Online A: booking advance', 'an advance is described with the resort''s name');
select is(public.payment_order_quote('a6100000-0000-4000-8000-000000000031', 'advance', 5000) -> 'prefill',
  jsonb_build_object('name', 'Gita Guest', 'email', 'p6-gita@example.com', 'contact', '+919800000001'),
  'the payment window is prefilled from the guest''s profile');
select lives_ok($$select public.payment_order_quote('a6100000-0000-4000-8000-000000000031', 'advance', 10000)$$,
  'paying the full total is accepted');
select throws_ok($$select public.payment_order_quote('a6100000-0000-4000-8000-000000000031', 'advance', 4999.99)$$,
  'P0009', null, 'less than the advance is refused');
select throws_ok($$select public.payment_order_quote('a6100000-0000-4000-8000-000000000031', 'advance', 10000.01)$$,
  'P0009', null, 'more than the total is refused');
select throws_ok($$select public.payment_order_quote('a6100000-0000-4000-8000-000000000031', 'advance', null)$$,
  'P0009', null, 'a missing amount is refused');
select throws_ok($$select public.payment_order_quote('a6100000-0000-4000-8000-000000000031', 'advance', 5000.005)$$,
  'P0009', null, 'fractions of a paisa are refused');
select throws_ok($$select public.payment_order_quote('a6100000-0000-4000-8000-000000000033', 'advance', 4000)$$,
  'P0006', null, 'an expired hold cannot be paid for');
select throws_ok($$select public.payment_order_quote('a6100000-0000-4000-8000-000000000032', 'advance', 3000)$$,
  'P0009', null, 'a checked-in stay takes no advance');
select is(public.payment_order_quote('a6100000-0000-4000-8000-000000000032', 'balance', 3000) ->> 'kind',
  'balance', 'the balance of a checked-in stay is quoted');
select is(public.payment_order_quote('a6100000-0000-4000-8000-000000000032', 'balance', 3000) ->> 'description',
  'Online A: stay balance', 'a balance is described with the resort''s name');
select throws_ok($$select public.payment_order_quote('a6100000-0000-4000-8000-000000000032', 'balance', 2999)$$,
  'P0009', null, 'a balance must match what is due');
select throws_ok($$select public.payment_order_quote('a6100000-0000-4000-8000-000000000031', 'balance', 5000)$$,
  'P0009', null, 'a hold has no balance to pay');
select throws_ok($$select public.payment_order_quote('a6100000-0000-4000-8000-0000000000ff', 'advance', 1)$$,
  'P0002', null, 'an unknown booking is not found');
set local request.jwt.claims to '{"sub":"a6000000-0000-0000-0000-000000000005","role":"authenticated"}';
select throws_ok($$select public.payment_order_quote('a6100000-0000-4000-8000-000000000031', 'advance', 5000)$$,
  'P0008', null, 'another guest cannot pay for Gita''s hold');
set local request.jwt.claims to '';
select throws_ok($$select public.payment_order_quote('a6100000-0000-4000-8000-000000000031', 'advance', 5000)$$,
  'P0008', null, 'a caller with no identity is refused');

-- Resort B is suspended for one assertion.
reset role;
update public.properties set status = 'suspended' where id = 'a6100000-0000-4000-8000-000000000002';
set local role authenticated;
set local request.jwt.claims to '{"sub":"a6000000-0000-0000-0000-000000000005","role":"authenticated"}';
select throws_ok($$select public.payment_order_quote('a6100000-0000-4000-8000-000000000034', 'advance', 2000)$$,
  'P0022', null, 'a suspended resort takes no advance');
reset role;
set local request.jwt.claims to '';
update public.properties set status = 'active' where id = 'a6100000-0000-4000-8000-000000000002';

-- Opening orders, as the Edge Functions do.
set local role service_role;
set local request.jwt.claims to '{"role":"service_role"}';
select is((select o.status::text from public.payment_order_open('a6100000-0000-4000-8000-000000000031',
            'a6000000-0000-0000-0000-000000000004', 'advance', 5000, 'order_A1') o),
  'created', 'the service role opens an order');
select throws_ok($$select public.payment_order_open('a6100000-0000-4000-8000-000000000031',
  'a6000000-0000-0000-0000-000000000004', 'advance', 5000, 'order_A1')$$,
  '23505', null, 'a Razorpay order id is recorded once');
select throws_ok($$select public.payment_order_open('a6100000-0000-4000-8000-000000000031',
  'a6000000-0000-0000-0000-000000000005', 'advance', 5000, 'order_X1')$$,
  'P0008', null, 'an order is only for the booking''s own guest');
select throws_ok($$select public.payment_order_open('a6100000-0000-4000-8000-000000000031',
  'a6000000-0000-0000-0000-000000000004', 'balance', 5000, 'order_X2')$$,
  'P0009', null, 'a hold takes no balance order');
select throws_ok($$select public.payment_order_open('a6100000-0000-4000-8000-000000000031',
  'a6000000-0000-0000-0000-000000000004', 'advance', 0, 'order_X3')$$,
  'P0009', null, 'an order needs a positive amount');
select throws_ok($$select public.payment_order_open('a6100000-0000-4000-8000-000000000031',
  'a6000000-0000-0000-0000-000000000004', 'advance', 5000, '  ')$$,
  'P0009', null, 'an order needs a Razorpay order id');
select lives_ok($$select public.payment_order_open('a6100000-0000-4000-8000-000000000032',
  'a6000000-0000-0000-0000-000000000004', 'balance', 3000, 'order_B1')$$,
  'a balance order for the checked-in stay');
select lives_ok($$select public.payment_order_open('a6100000-0000-4000-8000-000000000033',
  'a6000000-0000-0000-0000-000000000004', 'advance', 4000, 'order_C1')$$,
  'an order for a hold that has just expired but is not swept yet');
select lives_ok($$select public.payment_order_open('a6100000-0000-4000-8000-000000000034',
  'a6000000-0000-0000-0000-000000000005', 'advance', 2000, 'order_D1')$$,
  'an order at resort B');
set local role authenticated;
set local request.jwt.claims to '{"sub":"a6000000-0000-0000-0000-000000000004","role":"authenticated"}';
select throws_ok($$select public.payment_order_open('a6100000-0000-4000-8000-000000000031',
  'a6000000-0000-0000-0000-000000000004', 'advance', 5000, 'order_X4')$$,
  '42501', null, 'a guest cannot open orders directly');
reset role;
set local request.jwt.claims to '';
select is((select property_id from public.payment_orders where razorpay_order_id = 'order_A1'),
  'a6100000-0000-4000-8000-000000000001'::uuid, 'the order takes the reservation''s resort');
select is((select hold_expires_at from public.reservations where id = 'a6100000-0000-4000-8000-000000000031'),
  now() + interval '10 minutes', 'opening an order does not extend the hold');

-- === Task 3: the live switch and settling ======================================

-- More fixtures: R9 is checked in at A with 2000 due, and its balance
-- changes before the payment lands; R10 is a hold at B, which is
-- suspended before the payment lands.
insert into public.reservations
  (id, unit_id, period, kind, status, customer_id, guests, quote, hold_expires_at, checked_in_at) values
  ('a6100000-0000-4000-8000-000000000039','a6100000-0000-4000-8000-000000000011',
   tstzrange(now() - interval '1 day', now() + interval '1 day', '[)'),
   'booking','checked_in','a6000000-0000-0000-0000-000000000004',2,'{"total":2000}',
   null, now() - interval '1 day'),
  ('a6100000-0000-4000-8000-000000000040','a6100000-0000-4000-8000-000000000021',
   public.build_period('a6100000-0000-4000-8000-000000000021', current_date + 50, current_date + 51),
   'booking','hold','a6000000-0000-0000-0000-000000000005',2,'{"total":2000}',
   now() + interval '10 minutes', null);

set local role service_role;
set local request.jwt.claims to '{"role":"service_role"}';
select lives_ok($$select public.payment_order_open('a6100000-0000-4000-8000-000000000039',
  'a6000000-0000-0000-0000-000000000004', 'balance', 2000, 'order_G1')$$, 'a balance order for R9');
select lives_ok($$select public.payment_order_open('a6100000-0000-4000-8000-000000000040',
  'a6000000-0000-0000-0000-000000000005', 'advance', 2000, 'order_H1')$$, 'an advance order for R10');
select lives_ok($$select public.payments_set_live(true, 'rzp_test_p6')$$,
  'the service role switches online payments on');
reset role;
select is(public.online_payments_live(), true, 'online payments are live');
select is((select key_id from public.payment_gateway_config), 'rzp_test_p6', 'the live key id is recorded');

-- While live, the guest's own mock payments are refused.
set local role authenticated;
set local request.jwt.claims to '{"sub":"a6000000-0000-0000-0000-000000000004","role":"authenticated"}';
select throws_ok($$select public.confirm_booking('a6100000-0000-4000-8000-000000000037', 'mock_r7', 1000)$$,
  'P0036', null, 'while live, a guest cannot confirm with a mock payment');
select throws_ok($$select public.checkout_booking('a6100000-0000-4000-8000-000000000032', 'mock_r2', 3000)$$,
  'P0036', null, 'while live, a guest cannot pay a balance with a mock payment');
set local app.payment_gateway = 'razorpay';
select throws_ok($$select public.confirm_booking('a6100000-0000-4000-8000-000000000037', 'mock_r7', 1000)$$,
  'P0036', null, 'a guest who sets app.payment_gateway still gets P0036');
set local app.payment_gateway = '';
set local request.jwt.claims to '{"sub":"a6000000-0000-0000-0000-000000000002","role":"authenticated"}';
select lives_ok($$select public.checkout_booking('a6100000-0000-4000-8000-000000000036', 'RCPT-1', 1000, 'cash')$$,
  'desk payments are unaffected while live');

-- Settling, as payments-verify and payments-webhook do.
set local role service_role;
set local request.jwt.claims to '{"role":"service_role"}';
select is(public.payment_order_settle('order_fixture_r1', 'pay_A1') ->> 'status', 'paid',
  'a verified advance is paid');
select is(auth.uid(), null, 'settling leaves no guest identity behind');
select is(coalesce(nullif(current_setting('app.payment_gateway', true), ''), 'unset'), 'unset',
  'settling leaves no gateway label behind');
select is(public.payment_order_settle('order_fixture_r1', 'pay_A1') ->> 'refund_needed', 'false',
  'settling again reports the same paid order');
reset role;
select is((select status::text from public.reservations where id = 'a6100000-0000-4000-8000-000000000031'),
  'confirmed', 'the hold is confirmed');
select is((select gateway || ':' || method || ':' || kind || ':' || amount || ':' || recorded_by
             from public.payments where gateway_ref = 'pay_A1'),
  'razorpay:gateway:advance:5000.00:a6000000-0000-0000-0000-000000000004',
  'the payment is recorded as Razorpay, by the guest');
select is((select count(*)::int from public.payments
            where reservation_id = 'a6100000-0000-4000-8000-000000000031'),
  1, 'one payment, however often it is settled');
select is((select payment_id is not null from public.payment_orders where razorpay_order_id = 'order_fixture_r1'),
  true, 'the order links its payment');

set local role service_role;
set local request.jwt.claims to '{"role":"service_role"}';
select is(public.payment_order_settle('order_A1', 'pay_A2') ->> 'status', 'unapplied',
  'a second payment for a confirmed booking is unapplied');
select is(public.payment_order_settle('order_A1', 'pay_A2') ->> 'refund_needed', 'true',
  'it stays refund-needed until a refund is recorded');
select is(public.payment_order_settle('order_B1', 'pay_B1') ->> 'status', 'paid',
  'a verified balance is paid');
select is(public.payment_order_settle('order_C1', 'pay_C1') ->> 'status', 'paid',
  'a payment for an expired but unswept hold still confirms');
reset role;
select is((select failure_reason from public.payment_orders where razorpay_order_id = 'order_A1'),
  'reservation is confirmed', 'the unapplied reason is kept');
select is((select status::text from public.reservations where id = 'a6100000-0000-4000-8000-000000000032'),
  'checked_out', 'the balance checks the guest out');
select is((select kind || ':' || gateway || ':' || amount from public.payments where gateway_ref = 'pay_B1'),
  'balance:razorpay:3000.00', 'the balance is recorded as Razorpay');
select is((select state::text from public.unit_room_status where unit_id = 'a6100000-0000-4000-8000-000000000012'),
  'dirty', 'the room needs cleaning after an online checkout');
select is((select status::text from public.reservations where id = 'a6100000-0000-4000-8000-000000000033'),
  'confirmed', 'the late hold is confirmed');

-- Before their payments land: R4's hold is swept, R9's balance changes
-- (a desk payment of 500), and resort B is suspended.
set local request.jwt.claims to '';
update public.reservations
   set status = 'cancelled', cancel_reason = 'hold expired', cancelled_at = now()
 where id = 'a6100000-0000-4000-8000-000000000034';
insert into public.payments (reservation_id, amount, kind, status, gateway, gateway_ref, method)
values ('a6100000-0000-4000-8000-000000000039', 500, 'balance', 'succeeded', 'desk', 'desk-p6-r9', 'cash');
update public.properties set status = 'suspended' where id = 'a6100000-0000-4000-8000-000000000002';
set local role service_role;
set local request.jwt.claims to '{"role":"service_role"}';
select is(public.payment_order_settle('order_D1', 'pay_D1') ->> 'status', 'unapplied',
  'a payment for a swept hold is unapplied');
select is(public.payment_order_settle('order_G1', 'pay_G1') ->> 'status', 'unapplied',
  'a balance that changed meanwhile is unapplied');
select is(public.payment_order_settle('order_H1', 'pay_H1') ->> 'reason', 'resort_suspended',
  'a resort suspended meanwhile leaves the payment unapplied');
select throws_ok($$select public.payment_order_settle('order_nope', 'pay_x')$$,
  'P0002', null, 'an unknown order is not found');
select throws_ok($$select public.payment_order_settle('order_fixture_r1', '')$$,
  'P0009', null, 'a payment id is required');
reset role;
set local request.jwt.claims to '';
update public.properties set status = 'active' where id = 'a6100000-0000-4000-8000-000000000002';
select is((select status::text from public.reservations where id = 'a6100000-0000-4000-8000-000000000039'),
  'checked_in', 'the stay whose balance changed is not checked out');

set local role authenticated;
set local request.jwt.claims to '{"sub":"a6000000-0000-0000-0000-000000000004","role":"authenticated"}';
select throws_ok($$select public.payment_order_settle('order_B1', 'pay_B1')$$,
  '42501', null, 'a guest cannot settle a payment');
select throws_ok($$select public.payments_set_live(false, null)$$,
  '42501', null, 'a guest cannot flip the switch');

-- Switched off again, the mock confirms exactly as before P6.
set local role service_role;
set local request.jwt.claims to '{"role":"service_role"}';
select lives_ok($$select public.payments_set_live(false, null)$$,
  'the switch goes off when the keys are removed');
set local role authenticated;
set local request.jwt.claims to '{"sub":"a6000000-0000-0000-0000-000000000004","role":"authenticated"}';
select lives_ok($$select public.confirm_booking('a6100000-0000-4000-8000-000000000037', 'mock_r7', 1000)$$,
  'with the switch off, the mock confirms as before');
reset role;
select is((select gateway from public.payments where reservation_id = 'a6100000-0000-4000-8000-000000000037'),
  'mock', 'and records a mock payment');
set local request.jwt.claims to '';

-- === Task 4: failures, refunds, the webhook ledger, isolation =================

-- R8: a hold at B whose first payment attempt fails.
insert into public.reservations
  (id, unit_id, period, kind, status, customer_id, guests, quote, hold_expires_at) values
  ('a6100000-0000-4000-8000-000000000038','a6100000-0000-4000-8000-000000000021',
   public.build_period('a6100000-0000-4000-8000-000000000021', current_date + 40, current_date + 41),
   'booking','hold','a6000000-0000-0000-0000-000000000005',2,'{"total":2000}',
   now() + interval '10 minutes');

set local role service_role;
set local request.jwt.claims to '{"role":"service_role"}';
select lives_ok($$select public.payment_order_open('a6100000-0000-4000-8000-000000000038',
  'a6000000-0000-0000-0000-000000000005', 'advance', 2000, 'order_F1')$$, 'an order for R8');
select lives_ok($$select public.payment_order_failed('order_F1', 'Card declined by bank')$$,
  'a failed attempt is recorded');
select lives_ok($$select public.payment_order_failed('order_fixture_r1', 'late failure')$$,
  'a failure event for a paid order is accepted');
select lives_ok($$select public.payment_order_failed('order_unknown', 'x')$$,
  'a failure for an unknown order is ignored');
reset role;
select is((select status || ':' || failure_reason from public.payment_orders where razorpay_order_id = 'order_F1'),
  'failed:Card declined by bank', 'the order is failed, with Razorpay''s reason');
select is((select status::text from public.payment_orders where razorpay_order_id = 'order_fixture_r1'),
  'paid', 'a failure never downgrades a paid order');
set local role service_role;
set local request.jwt.claims to '{"role":"service_role"}';
select is(public.payment_order_settle('order_F1', 'pay_F1') ->> 'status', 'paid',
  'a retry that succeeds on the same order settles');
reset role;
select is((select status::text from public.reservations where id = 'a6100000-0000-4000-8000-000000000038'),
  'confirmed', 'and confirms the hold');

set local role service_role;
set local request.jwt.claims to '{"role":"service_role"}';
select lives_ok($$select public.payment_order_refunded('pay_A2', 'rfnd_1', 5000)$$,
  'the service role records a refund');
select lives_ok($$select public.payment_order_refunded('pay_A2', 'rfnd_1', 5000)$$,
  'recording the same refund again is harmless');
select is(public.payment_order_settle('order_A1', 'pay_A2') ->> 'refund_needed', 'false',
  'a refunded order needs no refund');
select lives_ok($$select public.payment_order_refunded('pay_A1', 'rfnd_2', 1000)$$,
  'a partial refund of a paid order');
select lives_ok($$select public.payment_order_refunded('pay_unknown', 'rfnd_3', 100)$$,
  'a refund for an unknown payment is ignored');
select throws_ok($$select public.payment_order_refunded('pay_A1', '', 100)$$,
  'P0009', null, 'a refund needs its id');
reset role;
select is((select status || ':' || refunded_amount || ':' || cardinality(refund_ids)
             from public.payment_orders where razorpay_order_id = 'order_A1'),
  'refunded:5000.00:1', 'a full refund, counted once');
select is((select status || ':' || refunded_amount
             from public.payment_orders where razorpay_order_id = 'order_fixture_r1'),
  'paid:1000.00', 'a partial refund keeps the order paid');
select is((select status::text from public.payments where gateway_ref = 'pay_A1'),
  'succeeded', 'refunds never change the payments ledger');

set local role service_role;
set local request.jwt.claims to '{"role":"service_role"}';
select is(public.payment_webhook_begin('evt_p6_1', 'payment.captured', '{"n":1}'), true,
  'a new webhook event is to be processed');
select is(public.payment_webhook_begin('evt_p6_1', 'payment.captured', '{"n":1}'), true,
  'an event that was never finished is processed again');
select lives_ok($$select public.payment_webhook_done('evt_p6_1', 'settled:paid')$$,
  'the event is finished');
select is(public.payment_webhook_begin('evt_p6_1', 'payment.captured', '{"n":1}'), false,
  'a finished event is not processed twice');
select throws_ok($$select public.payment_webhook_begin('', 'x', '{}')$$,
  'P0009', null, 'an event needs its id');
reset role;
select is((select outcome from public.payment_webhook_events where event_id = 'evt_p6_1'),
  'settled:paid', 'the outcome is kept');

set local role authenticated;
set local request.jwt.claims to '{"sub":"a6000000-0000-0000-0000-000000000004","role":"authenticated"}';
select throws_ok($$select public.payment_webhook_begin('evt_x', 'x', '{}')$$,
  '42501', null, 'a guest cannot write the webhook ledger');
select throws_ok($$select public.payment_order_refunded('pay_A1', 'rfnd_x', 1)$$,
  '42501', null, 'a guest cannot record refunds');
set local request.jwt.claims to '{"sub":"a6000000-0000-0000-0000-000000000001","role":"authenticated"}';
select is((select count(*)::int from public.payment_orders
            where property_id = 'a6100000-0000-4000-8000-000000000002'),
  0, 'A''s owner reads none of B''s payment orders');
set local request.jwt.claims to '{"sub":"a6000000-0000-0000-0000-000000000003","role":"authenticated"}';
select is((select count(*)::int from public.payment_orders), 3,
  'B''s owner reads B''s three payment orders');
set local request.jwt.claims to '{"sub":"a6000000-0000-0000-0000-000000000005","role":"authenticated"}';
select is((select count(*)::int from public.payment_orders), 3,
  'Om reads his own three payment orders');
set local request.jwt.claims to '{"sub":"a6000000-0000-0000-0000-000000000002","role":"authenticated"}';
select throws_ok($$select public.payment_order_settle('order_F1', 'pay_F1')$$,
  '42501', null, 'resort staff cannot settle payments either');
reset role;
set local request.jwt.claims to '';

select * from finish();
rollback;
