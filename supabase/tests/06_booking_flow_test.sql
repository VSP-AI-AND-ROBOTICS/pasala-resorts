begin;
select plan(11);

insert into auth.users (id, email)
values ('11111111-1111-1111-1111-111111111111','cust@example.com');

insert into public.properties (id, name, slug)
values ('aaaaaaaa-0000-0000-0000-000000000001','P1','p1');
insert into public.units (id, property_id, name, capacity_base, capacity_max)
values ('bbbbbbbb-0000-0000-0000-000000000001',
        'aaaaaaaa-0000-0000-0000-000000000001','U1',4,6);
insert into public.rate_rules
  (unit_id, kind, price, extra_guest_price, cleaning_fee, priority)
values ('bbbbbbbb-0000-0000-0000-000000000001','base',10000,1500,1500,0);

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

-- hold is created with a future expiry
select is(
  (select status from public.create_hold(
     'bbbbbbbb-0000-0000-0000-000000000001',
     '2026-08-03','2026-08-04', 4)),
  'hold'::public.reservation_status,
  'create_hold returns a hold');

-- a second hold on the same range is rejected
select throws_ok(
  $$select public.create_hold('bbbbbbbb-0000-0000-0000-000000000001',
      '2026-08-03','2026-08-04', 4)$$,
  '23P01', null, 'concurrent hold on same range is rejected');

-- a stale expected total is rejected
select throws_ok(
  $$select public.create_hold('bbbbbbbb-0000-0000-0000-000000000001',
      '2026-09-03','2026-09-04', 4, null, 999)$$,
  'P0007', null, 'stale quote is rejected');

-- confirm turns the hold into a confirmed booking and records the payment
select is(
  (select status from public.confirm_booking(
     (select id from public.reservations where status = 'hold' limit 1),
     'mock_ref_1', 11500)),
  'confirmed'::public.reservation_status,
  'confirm_booking confirms the hold');

select is(
  (select count(*)::int from public.payments where gateway_ref = 'mock_ref_1'),
  1,
  'payment row recorded');

-- expired holds are released
--
-- NOTE ON DEVIATION FROM THE BRIEF: the brief's Step 1 script performs this
-- seed insert while `role = authenticated` (a plain customer, not admin).
-- The `reservations` table intentionally has no INSERT policy for
-- customers -- migration 0005's own comment says "Customers never write
-- here directly -- every write goes through the SECURITY DEFINER RPC in
-- Task 8" -- so that insert is rejected with 42501 "new row violates
-- row-level security policy for table reservations". Verified by hand
-- against a running local instance (reproducible outside this test file).
-- Fix: switch to `role postgres` (superuser, bypasses RLS) before the raw
-- seed insert, exactly as the brief's own "additional coverage" idempotency
-- test does for its analogous seed insert below. No constraint, revoke, or
-- check was touched -- only this test's role ordering.
set local role postgres;
insert into public.reservations
  (unit_id, period, kind, status, customer_id, guests, hold_expires_at)
values ('bbbbbbbb-0000-0000-0000-000000000001',
        tstzrange('2026-10-03 14:00+05:30','2026-10-04 11:00+05:30','[)'),
        'booking','hold','11111111-1111-1111-1111-111111111111',4,
        now() - interval '1 minute');

select is(public.release_expired_holds(), 1, 'expired hold released');

-- confirm_booking is idempotent: a replayed gateway callback must not
-- create a second payment row or change the reservation again
set local role authenticated;
set local request.jwt.claims to
  '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

select is(
  (select status from public.confirm_booking(
     (select id from public.reservations
       where status = 'confirmed' and kind = 'booking' limit 1),
     'mock_ref_1', 11500)),
  'confirmed'::public.reservation_status,
  'confirm_booking on an already-confirmed reservation is a no-op');

set local role postgres;
select is(
  (select count(*)::int from public.payments where gateway_ref = 'mock_ref_1'),
  1,
  'replayed confirmation creates no second payment row');

-- an expired hold cannot be confirmed
insert into public.reservations
  (id, unit_id, period, kind, status, customer_id, guests, hold_expires_at)
values ('eeeeeeee-0000-0000-0000-000000000001',
        'bbbbbbbb-0000-0000-0000-000000000001',
        tstzrange('2026-12-03 14:00+05:30','2026-12-04 11:00+05:30','[)'),
        'booking','hold','11111111-1111-1111-1111-111111111111',4,
        now() - interval '1 minute');

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

select throws_ok(
  $$select public.confirm_booking(
      'eeeeeeee-0000-0000-0000-000000000001','mock_ref_expired', 11500)$$,
  'P0006', null, 'an expired hold cannot be confirmed');

-- cancelling frees the dates for an immediate rebooking through the RPC
select lives_ok(
  $$select public.cancel_booking(
      'eeeeeeee-0000-0000-0000-000000000001','changed plans')$$,
  'cancel_booking succeeds');

select lives_ok(
  $$select public.create_hold('bbbbbbbb-0000-0000-0000-000000000001',
      '2026-12-03','2026-12-04', 4)$$,
  'cancelled dates can be re-held immediately');

select * from finish();
rollback;
