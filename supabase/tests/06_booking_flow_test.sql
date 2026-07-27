begin;
select plan(26);

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

-- a second customer, for the authorization boundary
set local role postgres;
insert into auth.users (id, email)
values ('99999999-9999-9999-9999-999999999999','other@example.com');

insert into public.reservations
  (id, unit_id, period, kind, status, block_reason)
values ('ffffffff-0000-0000-0000-000000000001',
        'bbbbbbbb-0000-0000-0000-000000000001',
        tstzrange('2027-02-01 14:00+05:30','2027-02-03 11:00+05:30','[)'),
        'block','confirmed','maintenance');

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"99999999-9999-9999-9999-999999999999","role":"authenticated"}';

-- the NULL-trap regression test: this is the one that was exploitable
select throws_ok(
  $$select public.cancel_booking(
      'ffffffff-0000-0000-0000-000000000001','sneaky')$$,
  'P0008', null, 'a customer cannot cancel an admin block');

set local role postgres;
select is(
  (select status from public.reservations
    where id = 'ffffffff-0000-0000-0000-000000000001'),
  'confirmed'::public.reservation_status,
  'the admin block survived the attempt');

-- a session with no subject claim has no identity and must be refused,
-- even against a block row whose customer_id is also NULL
set local role authenticated;
set local request.jwt.claims to '{"role":"authenticated"}';

select throws_ok(
  $$select public.cancel_booking(
      'ffffffff-0000-0000-0000-000000000001','no identity')$$,
  'P0008', null, 'a session without a subject cannot cancel a block');

set local role postgres;
select is(
  (select status from public.reservations
    where id = 'ffffffff-0000-0000-0000-000000000001'),
  'confirmed'::public.reservation_status,
  'the block still survived the anonymous attempt');

reset role;
set local role postgres;

-- Capture the other customer's confirmed-booking id while RLS is bypassed
-- (role postgres). The coordinator's literal test resolves this id via a
-- subquery run *as the second customer*; but reservations_select_own only
-- lets a customer SELECT their own rows, so that subquery is invisible
-- under RLS and returns NULL -- cancel_booking(null, ...) then raises
-- P0002 ("reservation not found") instead of exercising the P0008
-- ownership check the assertion is meant to prove. Verified: running the
-- literal form produced exactly that failure ("caught: P0002: reservation
-- not found, wanted: P0008"). Fix: resolve the id once under role postgres
-- into a transaction-local GUC, then build the RPC call text against that
-- captured id while running as the second customer, so the RPC's own
-- SECURITY DEFINER authorization check (not the caller's SELECT
-- visibility) is what gets exercised.
select set_config('app.other_booking_id',
  (select id::text from public.reservations
    where kind = 'booking' and status = 'confirmed' limit 1),
  true);

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"99999999-9999-9999-9999-999999999999","role":"authenticated"}';

select throws_ok(
  format($$select public.cancel_booking('%s','not mine')$$,
         current_setting('app.other_booking_id')),
  'P0008', null, 'a customer cannot cancel another customer booking');

select throws_ok(
  $$select public.block_dates('bbbbbbbb-0000-0000-0000-000000000001',
      array[daterange('2027-03-01','2027-03-03')], 'nope')$$,
  'P0008', null, 'a customer cannot block dates');

select throws_ok(
  $$select public.release_expired_holds()$$,
  '42501', null, 'release_expired_holds is not callable by a client');

select throws_ok(
  $$select public.cancel_booking(
      '00000000-0000-0000-0000-0000000000ff','ghost')$$,
  'P0002', null, 'cancelling a nonexistent reservation raises P0002');

reset role;

-- block_dates happy path and its all-or-nothing promise, as an admin
set local role postgres;
insert into auth.users (id, email)
values ('88888888-8888-8888-8888-888888888888','blockadmin@example.com');
update public.profiles set role = 'admin'
  where id = '88888888-8888-8888-8888-888888888888';

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"88888888-8888-8888-8888-888888888888","role":"authenticated"}';

select is(
  (select count(*)::int from public.block_dates(
     'bbbbbbbb-0000-0000-0000-000000000001',
     array[daterange('2027-05-01','2027-05-03'),
           daterange('2027-05-10','2027-05-12')],
     'maintenance')),
  2,
  'block_dates creates one row per range');

-- all-or-nothing: the second range collides with the block just made
select throws_ok(
  $$select public.block_dates('bbbbbbbb-0000-0000-0000-000000000001',
      array[daterange('2027-06-01','2027-06-03'),
            daterange('2027-05-02','2027-05-04')], 'clash')$$,
  '23P01', null, 'a conflicting range aborts the whole block call');

set local role postgres;
select is(
  (select count(*)::int from public.reservations
    where unit_id = 'bbbbbbbb-0000-0000-0000-000000000001'
      and lower(period) >= '2027-06-01'
      and lower(period) <  '2027-06-04'),
  0,
  'no partial rows persisted from the aborted block call');

reset role;

-- confirm_booking must reject an amount that does not match the stored quote
--
-- 2027-09-01..2027-09-02 does not collide with any earlier assertion on
-- this unit (checked: 2026-08-03/04, 2026-09-03/04, 2026-10-03/04,
-- 2026-12-03/04, 2027-02-01/03, 2027-03-01/03, 2027-05-01/03, 2027-05-10/12,
-- 2027-06-01/03, 2027-05-02/04 are all in use elsewhere in this file).
--
-- The subselect inside throws_ok runs as the authenticated customer who
-- owns the hold it just created, so reservations_select_own (customer_id =
-- auth.uid()) makes it visible under RLS -- unlike the earlier cross-
-- customer lookup, no set_config capture is needed here. Verified by hand
-- against a running local instance before relying on it (a customer
-- creating and then immediately re-selecting their own hold resolves the
-- row correctly).
set local role authenticated;
set local request.jwt.claims to
  '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

select is(
  (select status from public.create_hold(
     'bbbbbbbb-0000-0000-0000-000000000001',
     '2027-09-01','2027-09-02', 4)),
  'hold'::public.reservation_status,
  'a hold exists for the amount-mismatch check');

select throws_ok(
  $$select public.confirm_booking(
      (select id from public.reservations
        where status = 'hold'
          and lower(period) >= '2027-09-01'
          and lower(period) <  '2027-09-02'
        limit 1),
      'mock_ref_underpay', 1)$$,
  'P0009', null, 'an amount below the quoted total is rejected');

set local role postgres;
select is(
  (select count(*)::int from public.payments
    where gateway_ref = 'mock_ref_underpay'),
  0,
  'the rejected payment was not recorded');

reset role;

-- confirm the hold properly so it does not linger as a stale hold
set local role authenticated;
set local request.jwt.claims to
  '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

select is(
  (select status from public.confirm_booking(
     (select id from public.reservations
        where status = 'hold'
          and lower(period) >= '2027-09-01'
          and lower(period) <  '2027-09-02'
        limit 1),
     'mock_ref_underpay_fixed', 11500)),
  'confirmed'::public.reservation_status,
  'the same hold confirms once the correct amount is passed');

reset role;

select * from finish();
rollback;
