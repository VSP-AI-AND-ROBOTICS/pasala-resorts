-- Payments hardening, added in 0062_payments_hardening.sql (final review
-- minor 1): payment_order_settle hands the refund of an unapplied payment
-- to one caller, and payment_order_refund_release gives a failed one back.
--
-- Fixtures: resort "Hardening A" (advance 50%) and guest Hema. Reservations:
--   ...41  hold, total 4000, expires in 10 minutes (order_H_paid)
--   ...42  cancelled                               (order_H_unapplied)
begin;
select plan(20);

insert into auth.users (id, email) values
  ('a6200000-0000-0000-0000-000000000001','p6h-hema@example.com');

insert into public.properties (id, name, slug, advance_pct) values
  ('a6210000-0000-4000-8000-000000000001','Hardening A','hardening-a', 50);

insert into public.units (id, property_id, name, capacity_base, capacity_max) values
  ('a6210000-0000-4000-8000-000000000011','a6210000-0000-4000-8000-000000000001','H Cottage 1',2,4),
  ('a6210000-0000-4000-8000-000000000012','a6210000-0000-4000-8000-000000000001','H Cottage 2',2,4);

insert into public.reservations
  (id, unit_id, period, kind, status, customer_id, guests, quote, hold_expires_at) values
  ('a6210000-0000-4000-8000-000000000041','a6210000-0000-4000-8000-000000000011',
   public.build_period('a6210000-0000-4000-8000-000000000011', current_date + 10, current_date + 12),
   'booking','hold','a6200000-0000-0000-0000-000000000001',2,'{"total":4000}',
   now() + interval '10 minutes'),
  ('a6210000-0000-4000-8000-000000000042','a6210000-0000-4000-8000-000000000012',
   public.build_period('a6210000-0000-4000-8000-000000000012', current_date + 10, current_date + 12),
   'booking','cancelled','a6200000-0000-0000-0000-000000000001',2,'{"total":4000}', null);

insert into public.payment_orders (reservation_id, customer_id, kind, amount, razorpay_order_id) values
  ('a6210000-0000-4000-8000-000000000041','a6200000-0000-0000-0000-000000000001','advance', 2000, 'order_H_paid'),
  ('a6210000-0000-4000-8000-000000000042','a6200000-0000-0000-0000-000000000001','advance', 2000, 'order_H_unapplied');

select has_column('public', 'payment_orders', 'refund_claimed_at', 'payment_orders records the refund claim');

-- verify and the webhook settle the same unapplied payment: one refund.
set local role service_role;
set local request.jwt.claims to '{"role":"service_role"}';
select is(public.payment_order_settle('order_H_unapplied', 'pay_H1') ->> 'refund_needed', 'true',
  'the first caller is handed the refund');
select is(public.payment_order_settle('order_H_unapplied', 'pay_H1') ->> 'refund_needed', 'false',
  'a second caller is not, while the claim holds');
select is(public.payment_order_settle('order_H_unapplied', 'pay_H1') ->> 'status', 'unapplied',
  'and is still told the payment is unapplied');
reset role;
select is((select status || ':' || (refund_claimed_at is not null)
             from public.payment_orders where razorpay_order_id = 'order_H_unapplied'),
  'unapplied:true', 'the claim is recorded on the unapplied order');

-- Only the service role gives a claim back.
set local role authenticated;
set local request.jwt.claims to '{"sub":"a6200000-0000-0000-0000-000000000001","role":"authenticated"}';
select throws_ok($$select public.payment_order_refund_release('pay_H1')$$,
  '42501', null, 'a guest cannot release a refund claim');
set local role anon;
set local request.jwt.claims to '{"role":"anon"}';
select throws_ok($$select public.payment_order_refund_release('pay_H1')$$,
  '42501', null, 'anon cannot release a refund claim');

-- A failed refund gives the claim back; the next settle call retries.
set local role service_role;
set local request.jwt.claims to '{"role":"service_role"}';
select lives_ok($$select public.payment_order_refund_release('pay_H1')$$,
  'the service role releases a failed refund''s claim');
reset role;
select is((select refund_claimed_at from public.payment_orders where razorpay_order_id = 'order_H_unapplied'),
  null, 'the claim is cleared');
set local role service_role;
set local request.jwt.claims to '{"role":"service_role"}';
select is(public.payment_order_settle('order_H_unapplied', 'pay_H1') ->> 'refund_needed', 'true',
  'after a release the next caller is handed the refund again');
select is(public.payment_order_settle('order_H_unapplied', 'pay_H1') ->> 'refund_needed', 'false',
  'and only that caller');

-- A claim nobody gives back (the function died mid-way) lapses.
reset role;
update public.payment_orders set refund_claimed_at = now() - interval '9 minutes'
 where razorpay_order_id = 'order_H_unapplied';
set local role service_role;
set local request.jwt.claims to '{"role":"service_role"}';
select is(public.payment_order_settle('order_H_unapplied', 'pay_H1') ->> 'refund_needed', 'false',
  'a claim 9 minutes old still holds');
reset role;
update public.payment_orders set refund_claimed_at = now() - interval '11 minutes'
 where razorpay_order_id = 'order_H_unapplied';
set local role service_role;
set local request.jwt.claims to '{"role":"service_role"}';
select is(public.payment_order_settle('order_H_unapplied', 'pay_H1') ->> 'refund_needed', 'true',
  'a claim 11 minutes old has lapsed and is handed out again');

-- Once a refund is recorded there is nothing to claim or release.
select lives_ok($$select public.payment_order_refunded('pay_H1', 'rfnd_H1', 2000)$$,
  'the refund is recorded');
select lives_ok($$select public.payment_order_refund_release('pay_H1')$$,
  'a release after the refund is harmless');
select is(public.payment_order_settle('order_H_unapplied', 'pay_H1') ->> 'refund_needed', 'false',
  'a refunded order is never handed out for refund');
select lives_ok($$select public.payment_order_refund_release('pay_unknown')$$,
  'releasing an unknown payment is harmless');

-- A paid order never needs a refund and is never claimed.
select is(public.payment_order_settle('order_H_paid', 'pay_H2') ->> 'status', 'paid',
  'a payment for a live hold is paid');
select is(public.payment_order_settle('order_H_paid', 'pay_H2') ->> 'refund_needed', 'false',
  'a paid order needs no refund');
reset role;
select is((select refund_claimed_at from public.payment_orders where razorpay_order_id = 'order_H_paid'),
  null, 'a paid order has no refund claim');
set local request.jwt.claims to '';

select * from finish();
rollback;
