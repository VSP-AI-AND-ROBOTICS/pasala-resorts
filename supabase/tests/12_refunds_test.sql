-- The refund policy engine (`refund_rules`/`compute_refund`, wired into
-- `cancel_booking`) and the advance/balance split (`confirm_booking`'s
-- equality check replaced by a range against `properties.advance_pct`).
--
-- The default ladder used throughout this file -- 0% within 48 hours (tier
-- min_days_before=0), 50% within 7 days (tier min_days_before=2), 100%
-- beyond 7 days (tier min_days_before=8) -- matches the brief's own
-- language ("full refund more than 7 days before check-in, 50% within 7
-- days, none within 48 hours") and is exercised at 10/5/1 days out, exactly
-- the three points the brief names. Every reservation below carries a
-- fixture-controlled `quote.total` of 10000, so the worked arithmetic
-- (10000 / 5000 / 0) can be read straight off the assertions without
-- re-deriving anything.

begin;
select plan(44);

select has_table('public', 'refund_rules', 'refund_rules table exists');
select has_column('public', 'reservations', 'refund_pct',
  'reservations gains a refund_pct column');
select has_column('public', 'reservations', 'refund_amount',
  'reservations gains a refund_amount column');
select has_column('public', 'properties', 'advance_pct',
  'properties gains an advance_pct column');
select has_function('public', 'compute_refund', 'compute_refund() exists');

-- === fixtures ===============================================================

insert into auth.users (id, email) values
  ('c1111111-1111-1111-1111-111111111111', 'refundcust1@example.com'),
  ('c2222222-2222-2222-2222-222222222222', 'refundadmin@example.com'),
  ('c3333333-3333-3333-3333-333333333333', 'refundcust2@example.com');
update public.profiles set role = 'admin'
  where id = 'c2222222-2222-2222-2222-222222222222';

-- P1: the default ladder, exercised at 10/5/1 days out.
insert into public.properties (id, name, slug)
values ('a1000000-0000-0000-0000-000000000001', 'RefundLadder', 'refund-ladder');
insert into public.units (id, property_id, name, capacity_base, capacity_max)
values ('b1000000-0000-0000-0000-000000000001',
        'a1000000-0000-0000-0000-000000000001', 'RefundLadderUnit', 2, 4);
insert into public.refund_rules (property_id, min_days_before, refund_pct)
values
  ('a1000000-0000-0000-0000-000000000001', 0,   0),
  ('a1000000-0000-0000-0000-000000000001', 2,  50),
  ('a1000000-0000-0000-0000-000000000001', 8, 100);

select is(
  (select count(*)::int from public.refund_rules
    where property_id = 'a1000000-0000-0000-0000-000000000001'),
  3,
  'the ladder fixture seeds exactly 3 tiers for this property');

-- P2: no refund_rules at all.
insert into public.properties (id, name, slug)
values ('a1000000-0000-0000-0000-000000000002', 'RefundNoRules', 'refund-no-rules');
insert into public.units (id, property_id, name, capacity_base, capacity_max)
values ('b1000000-0000-0000-0000-000000000002',
        'a1000000-0000-0000-0000-000000000002', 'RefundNoRulesUnit', 2, 4);

-- P3: advance_pct = 50, for the advance/balance range check.
insert into public.properties (id, name, slug, advance_pct)
values ('a1000000-0000-0000-0000-000000000003', 'RefundAdvance', 'refund-advance', 50);
insert into public.units (id, property_id, name, capacity_base, capacity_max)
values ('b1000000-0000-0000-0000-000000000003',
        'a1000000-0000-0000-0000-000000000003', 'RefundAdvanceUnit', 2, 4);
insert into public.rate_rules
  (unit_id, kind, price, extra_guest_price, cleaning_fee, priority)
values ('b1000000-0000-0000-0000-000000000003', 'base', 10000, 0, 0, 0);

-- P4: advance_pct left at its default (100) -- proves the default
-- preserves today's exact-total behaviour byte-for-byte.
insert into public.properties (id, name, slug)
values ('a1000000-0000-0000-0000-000000000004', 'RefundDefaultAdvance',
        'refund-default-advance');
insert into public.units (id, property_id, name, capacity_base, capacity_max)
values ('b1000000-0000-0000-0000-000000000004',
        'a1000000-0000-0000-0000-000000000004', 'RefundDefaultUnit', 2, 4);
insert into public.rate_rules
  (unit_id, kind, price, extra_guest_price, cleaning_fee, priority)
values ('b1000000-0000-0000-0000-000000000004', 'base', 10000, 0, 0, 0);

insert into public.resort_members (property_id, user_id, role) values
  ('a1000000-0000-0000-0000-000000000001','c2222222-2222-2222-2222-222222222222','admin'),
  ('a1000000-0000-0000-0000-000000000002','c2222222-2222-2222-2222-222222222222','admin'),
  ('a1000000-0000-0000-0000-000000000003','c2222222-2222-2222-2222-222222222222','admin'),
  ('a1000000-0000-0000-0000-000000000004','c2222222-2222-2222-2222-222222222222','admin');

select is(
  (select advance_pct from public.properties
    where id = 'a1000000-0000-0000-0000-000000000004'),
  100.00::numeric,
  'advance_pct defaults to 100 when a property never sets it');

-- Reservations at 10/5/1 days out, all with a fixture-controlled quote
-- total of 10000. Direct inserts (role postgres, bypassing RLS) --
-- `reservations` has no customer INSERT policy, same reasoning as every
-- other direct-insert fixture in this suite (see 06_booking_flow_test.sql).
-- `build_period` computes the period using the PROPERTY's own timezone and
-- check-in/check-out times, so `compute_refund`'s days-before arithmetic
-- below is exercised against the real property-local period, not a
-- hand-rolled one.
insert into public.reservations
  (id, unit_id, period, kind, status, customer_id, guests, quote, source)
values
  ('d1000000-0000-0000-0000-000000000001',
   'b1000000-0000-0000-0000-000000000001',
   public.build_period('b1000000-0000-0000-0000-000000000001',
     (now() at time zone 'Asia/Kolkata')::date + 10,
     (now() at time zone 'Asia/Kolkata')::date + 11),
   'booking', 'confirmed', 'c1111111-1111-1111-1111-111111111111', 2,
   jsonb_build_object('total', 10000.00), 'app'),
  ('d1000000-0000-0000-0000-000000000002',
   'b1000000-0000-0000-0000-000000000001',
   public.build_period('b1000000-0000-0000-0000-000000000001',
     (now() at time zone 'Asia/Kolkata')::date + 5,
     (now() at time zone 'Asia/Kolkata')::date + 6),
   'booking', 'confirmed', 'c1111111-1111-1111-1111-111111111111', 2,
   jsonb_build_object('total', 10000.00), 'app'),
  ('d1000000-0000-0000-0000-000000000003',
   'b1000000-0000-0000-0000-000000000001',
   public.build_period('b1000000-0000-0000-0000-000000000001',
     (now() at time zone 'Asia/Kolkata')::date + 1,
     (now() at time zone 'Asia/Kolkata')::date + 2),
   'booking', 'confirmed', 'c1111111-1111-1111-1111-111111111111', 2,
   jsonb_build_object('total', 10000.00), 'app'),
  ('d1000000-0000-0000-0000-000000000004',
   'b1000000-0000-0000-0000-000000000002',
   public.build_period('b1000000-0000-0000-0000-000000000002',
     (now() at time zone 'Asia/Kolkata')::date + 10,
     (now() at time zone 'Asia/Kolkata')::date + 11),
   'booking', 'confirmed', 'c1111111-1111-1111-1111-111111111111', 2,
   jsonb_build_object('total', 10000.00), 'app');

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"c1111111-1111-1111-1111-111111111111","role":"authenticated"}';

-- === the ladder resolves correctly at 10/5/1 days out =====================

select is(
  (public.compute_refund('d1000000-0000-0000-0000-000000000001')
    ->> 'days_before')::int,
  10,
  '10 days out: days_before is 10');
select is(
  (public.compute_refund('d1000000-0000-0000-0000-000000000001')
    ->> 'refund_pct')::numeric,
  100.00::numeric,
  '10 days out (more than 7): the full-refund tier matches -- 100%');
select is(
  (public.compute_refund('d1000000-0000-0000-0000-000000000001')
    ->> 'refund_amount')::numeric,
  10000.00::numeric,
  '10 days out: refund_amount is 100% of the 10000 quote total');

select is(
  (public.compute_refund('d1000000-0000-0000-0000-000000000002')
    ->> 'days_before')::int,
  5,
  '5 days out: days_before is 5');
select is(
  (public.compute_refund('d1000000-0000-0000-0000-000000000002')
    ->> 'refund_pct')::numeric,
  50.00::numeric,
  '5 days out (within 7): the half-refund tier matches -- 50%');
select is(
  (public.compute_refund('d1000000-0000-0000-0000-000000000002')
    ->> 'refund_amount')::numeric,
  5000.00::numeric,
  '5 days out: refund_amount is 50% of the 10000 quote total, not the raw pct');

select is(
  (public.compute_refund('d1000000-0000-0000-0000-000000000003')
    ->> 'days_before')::int,
  1,
  '1 day out: days_before is 1');
select is(
  (public.compute_refund('d1000000-0000-0000-0000-000000000003')
    ->> 'refund_pct')::numeric,
  0.00::numeric,
  '1 day out (within 48 hours): the no-refund tier matches -- 0%');
select is(
  (public.compute_refund('d1000000-0000-0000-0000-000000000003')
    ->> 'refund_amount')::numeric,
  0.00::numeric,
  '1 day out: refund_amount is 0, not NULL and not an error');
select isnt(
  (public.compute_refund('d1000000-0000-0000-0000-000000000003')
    ->> 'rule_id'),
  null,
  '1 day out: a rule DID match (the 0% tier) -- rule_id is not null even '
  'though the refund itself is zero');

-- === the timezone trap: the check-in side of the days-before arithmetic ===
-- === uses the PROPERTY's timezone, never the session's/UTC's ==============
--
-- The 10/5/1-day assertions above already run against a real Asia/Kolkata
-- property, but whether they'd actually CATCH a UTC-instead-of-property-tz
-- regression depends on what real wall-clock hour this suite happens to run
-- at (IST and UTC only disagree on the calendar date during a ~5.5-hour
-- window each day) -- not a reliable proof on its own.
--
-- This test is deterministic regardless of when it runs. Two checkin
-- instants exactly 2 hours apart, both on the SAME UTC calendar date
-- (2099-06-15), but on DIFFERENT Honolulu-local calendar dates
-- (2099-06-14 vs 2099-06-15) -- Honolulu is a fixed UTC-10 offset with no
-- DST, so this never drifts. Both reservations are evaluated by
-- compute_refund at the SAME real "now()" (this transaction's fixed
-- timestamp, per Postgres semantics), so SUBTRACTING their two
-- days_before values cancels out whatever "today" actually is and
-- isolates exactly one thing: whether the CHECK-IN side of the
-- subtraction was converted through the property's timezone. A version
-- that cast the check-in instant under the session's UTC timezone instead
-- -- the exact bug this task's brief warns about -- would see both
-- instants land on the same UTC date and report a difference of 0, not 1.
set local role postgres;
insert into public.properties (id, name, slug, timezone)
values ('a1000000-0000-0000-0000-000000000009',
        'RefundHonolulu', 'refund-honolulu', 'Pacific/Honolulu');
insert into public.units (id, property_id, name, capacity_base, capacity_max)
values ('b1000000-0000-0000-0000-000000000009',
        'a1000000-0000-0000-0000-000000000009', 'RefundHonoluluUnit', 2, 4);
insert into public.resort_members (property_id, user_id, role) values
  ('a1000000-0000-0000-0000-000000000009','c2222222-2222-2222-2222-222222222222','admin');
insert into public.reservations
  (id, unit_id, period, kind, status, customer_id, guests, quote, source)
values
  ('d1000000-0000-0000-0000-000000000009',
   'b1000000-0000-0000-0000-000000000009',
   tstzrange('2099-06-15 09:00:00+00', '2099-06-15 10:00:00+00', '[)'),
   'booking', 'confirmed', 'c1111111-1111-1111-1111-111111111111', 2,
   jsonb_build_object('total', 10000.00), 'app'),
  ('d1000000-0000-0000-0000-000000000010',
   'b1000000-0000-0000-0000-000000000009',
   tstzrange('2099-06-15 11:00:00+00', '2099-06-15 12:00:00+00', '[)'),
   'booking', 'confirmed', 'c1111111-1111-1111-1111-111111111111', 2,
   jsonb_build_object('total', 10000.00), 'app');
set local role authenticated;
set local request.jwt.claims to
  '{"sub":"c1111111-1111-1111-1111-111111111111","role":"authenticated"}';

select is(
  (public.compute_refund('d1000000-0000-0000-0000-000000000010')
    ->> 'days_before')::int
  -
  (public.compute_refund('d1000000-0000-0000-0000-000000000009')
    ->> 'days_before')::int,
  1,
  'two check-ins 2 hours apart but on the same UTC calendar date land on '
  'DIFFERENT Honolulu-local dates -- days_before differs by exactly 1, '
  'proving the check-in side is converted through the property''s own '
  'timezone, not the session''s UTC -- deterministic regardless of when '
  'this suite runs');

-- === compute_refund's days_before is invariant to the SESSION's own ======
-- === timezone -- carried-forward fix from Task 8's review =================
--
-- Task 8's review found a gap in the Honolulu test above: both of its
-- calls share the same real `now()` AND the same property, so the `now()
-- at time zone v_tz` conversion on the CHECK-OUT/"today" side of the
-- `days_before` subtraction cancels out of the comparison and is never
-- actually exercised -- only the check-in side is. A regression that
-- swapped that side back to a bare `now()::date` (silently reading the
-- SESSION's timezone instead of the property's `v_tz`) would pass every
-- assertion above undetected, and that side is exactly what this task's
-- brief warns about with its "cancellation at 01:00 IST" example.
--
-- This closes the gap directly: call compute_refund on the SAME
-- reservation, in the SAME transaction (so the real wall-clock instant
-- `now()` resolves to never changes), under two `set local timezone`
-- values chosen to span MORE than 24 hours apart -- `Etc/GMT+12` (UTC-12)
-- and `Pacific/Kiritimati` (UTC+14), a 26-hour spread. (Task 10 fix-round
-- Finding 4: the original pair here was UTC and Pacific/Kiritimati, only
-- 14 hours apart -- since 14 < 24, there is roughly a 10-hour window each
-- day where both zones land on the same calendar date, so a run inside
-- that window would not have caught a regression. Spanning more than 24
-- hours guarantees the two zones can never agree on the calendar date,
-- so the guard holds regardless of when the suite runs.) Because both
-- `lower(period) at time zone v_tz` and `now() at time zone v_tz` name
-- the property's timezone EXPLICITLY, the session's own TimeZone GUC
-- must never leak into the result -- days_before has to land on the same
-- value (10, the figure already proven correct for this reservation
-- above) under both.
set local timezone = 'Etc/GMT+12';
select is(
  (public.compute_refund('d1000000-0000-0000-0000-000000000001')
    ->> 'days_before')::int,
  10,
  'days_before under session timezone Etc/GMT+12 (UTC-12) is 10, matching '
  'the baseline');

set local timezone = 'Pacific/Kiritimati';
select is(
  (public.compute_refund('d1000000-0000-0000-0000-000000000001')
    ->> 'days_before')::int,
  10,
  'days_before under session timezone Pacific/Kiritimati (UTC+14, 26 '
  'hours apart from the Etc/GMT+12 run above) is IDENTICAL -- proving '
  'the session''s own timezone never leaks into the computation, only '
  'the property''s v_tz does');
reset timezone;

-- === a property with no rules yields a zero refund, never an error =========

select lives_ok(
  $$select public.compute_refund('d1000000-0000-0000-0000-000000000004')$$,
  'a property with no refund_rules at all does not raise');
select is(
  (public.compute_refund('d1000000-0000-0000-0000-000000000004')
    ->> 'refund_pct')::numeric,
  0.00::numeric,
  'no matching rule: refund_pct is 0');
select is(
  (public.compute_refund('d1000000-0000-0000-0000-000000000004')
    ->> 'refund_amount')::numeric,
  0.00::numeric,
  'no matching rule: refund_amount is 0, not NULL');
select is(
  (public.compute_refund('d1000000-0000-0000-0000-000000000004')
    ->> 'rule_id'),
  null,
  'no matching rule: rule_id is null, proving nothing was silently guessed');

-- === cancelling records both percentage and amount on the reservation =====

select is(
  (select status from public.cancel_booking(
     'd1000000-0000-0000-0000-000000000002', 'change of plans'))::text,
  'cancelled',
  'cancel_booking on the 5-days-out reservation succeeds');

set local role postgres;
select is(
  (select refund_pct from public.reservations
    where id = 'd1000000-0000-0000-0000-000000000002'),
  50.00::numeric,
  'the cancelled reservation records the matched refund_pct');
select is(
  (select refund_amount from public.reservations
    where id = 'd1000000-0000-0000-0000-000000000002'),
  5000.00::numeric,
  'the cancelled reservation records the computed refund_amount');
set local role authenticated;
set local request.jwt.claims to
  '{"sub":"c1111111-1111-1111-1111-111111111111","role":"authenticated"}';

-- === compute_refund authorization mirrors cancel_booking's own ============

set local request.jwt.claims to
  '{"sub":"c3333333-3333-3333-3333-333333333333","role":"authenticated"}';
select throws_ok(
  $$select public.compute_refund('d1000000-0000-0000-0000-000000000001')$$,
  'P0020', null,
  'a different customer cannot preview another customer''s refund');

set local request.jwt.claims to
  '{"sub":"c2222222-2222-2222-2222-222222222222","role":"authenticated"}';
select lives_ok(
  $$select public.compute_refund('d1000000-0000-0000-0000-000000000001')$$,
  'an admin can preview any customer''s refund');

reset role;

-- === confirm_booking accepts the advance minimum, rejects below and =======
-- === above =================================================================

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"c1111111-1111-1111-1111-111111111111","role":"authenticated"}';

-- advance_pct = 50 on a 10000 quote: the accepted range is [5000, 10000].
select is(
  (select status from public.create_hold(
     'b1000000-0000-0000-0000-000000000003',
     '2029-01-10', '2029-01-11', 2))::text,
  'hold',
  'a hold exists on the advance_pct=50 unit');

select is(
  (select status from public.confirm_booking(
     (select id from public.reservations
       where status = 'hold'
         and unit_id = 'b1000000-0000-0000-0000-000000000003'
         and lower(period) >= '2029-01-10' and lower(period) < '2029-01-11'
       limit 1),
     'refund_advance_exact', 5000))::text,
  'confirmed',
  'confirm_booking accepts an advance exactly equal to advance_pct (50%) '
  'of the total');

select is(
  (select status from public.create_hold(
     'b1000000-0000-0000-0000-000000000003',
     '2029-02-10', '2029-02-11', 2))::text,
  'hold',
  'a second hold exists for the below-minimum case');

select throws_ok(
  $$select public.confirm_booking(
      (select id from public.reservations
        where status = 'hold'
          and unit_id = 'b1000000-0000-0000-0000-000000000003'
          and lower(period) >= '2029-02-10' and lower(period) < '2029-02-11'
        limit 1),
      'refund_advance_below', 4999)$$,
  'P0009', null,
  'confirm_booking rejects an advance below advance_pct of the total');

select is(
  (select status from public.create_hold(
     'b1000000-0000-0000-0000-000000000003',
     '2029-03-10', '2029-03-11', 2))::text,
  'hold',
  'a third hold exists for the above-total case');

select throws_ok(
  $$select public.confirm_booking(
      (select id from public.reservations
        where status = 'hold'
          and unit_id = 'b1000000-0000-0000-0000-000000000003'
          and lower(period) >= '2029-03-10' and lower(period) < '2029-03-11'
        limit 1),
      'refund_advance_above', 10001)$$,
  'P0009', null,
  'confirm_booking rejects an advance above the quoted total');

set local role postgres;
select is(
  (select count(*)::int from public.payments
    where gateway_ref in ('refund_advance_below', 'refund_advance_above')),
  0,
  'neither the below-minimum nor the above-total attempt recorded a payment');
set local role authenticated;
set local request.jwt.claims to
  '{"sub":"c1111111-1111-1111-1111-111111111111","role":"authenticated"}';

-- === advance_pct=100 (the default) still requires the exact total =========

select is(
  (select status from public.create_hold(
     'b1000000-0000-0000-0000-000000000004',
     '2029-01-10', '2029-01-11', 2))::text,
  'hold',
  'a hold exists on the default (advance_pct=100) unit');

select is(
  (select status from public.confirm_booking(
     (select id from public.reservations
       where status = 'hold'
         and unit_id = 'b1000000-0000-0000-0000-000000000004'
         and lower(period) >= '2029-01-10' and lower(period) < '2029-01-11'
       limit 1),
     'refund_default_exact', 10000))::text,
  'confirmed',
  'a property that never sets advance_pct still accepts the exact total');

select is(
  (select status from public.create_hold(
     'b1000000-0000-0000-0000-000000000004',
     '2029-02-10', '2029-02-11', 2))::text,
  'hold',
  'a second hold exists for the default-property underpay case');

select throws_ok(
  $$select public.confirm_booking(
      (select id from public.reservations
        where status = 'hold'
          and unit_id = 'b1000000-0000-0000-0000-000000000004'
          and lower(period) >= '2029-02-10' and lower(period) < '2029-02-11'
        limit 1),
      'refund_default_below', 9999)$$,
  'P0009', null,
  'a property that never sets advance_pct still rejects anything below the '
  'exact total -- the default of 100 collapses the range to a single point');

-- === the NULL holes m8/I2 closed stay closed under the new range check ====

set local role postgres;
insert into public.reservations
  (id, unit_id, period, kind, status, customer_id, guests, quote,
   hold_expires_at)
values ('d1000000-0000-0000-0000-000000000005',
        'b1000000-0000-0000-0000-000000000004',
        public.build_period('b1000000-0000-0000-0000-000000000004',
          date '2029-04-10', date '2029-04-11'),
        'booking', 'hold', 'c1111111-1111-1111-1111-111111111111', 2,
        null, now() + interval '15 minutes');
set local role authenticated;
set local request.jwt.claims to
  '{"sub":"c1111111-1111-1111-1111-111111111111","role":"authenticated"}';

select throws_ok(
  $$select public.confirm_booking(
      'd1000000-0000-0000-0000-000000000005','refund_null_quote', 999999)$$,
  'P0009', null,
  'confirm_booking rejects any amount when the stored quote is NULL, no '
  'matter how large');

select is(
  (select status from public.create_hold(
     'b1000000-0000-0000-0000-000000000004',
     '2029-05-10', '2029-05-11', 2))::text,
  'hold',
  'a hold with a real quote exists for the NULL-amount case');

select throws_ok(
  $$select public.confirm_booking(
      (select id from public.reservations
        where status = 'hold'
          and unit_id = 'b1000000-0000-0000-0000-000000000004'
          and lower(period) >= '2029-05-10' and lower(period) < '2029-05-11'
        limit 1),
      'refund_null_amount', null)$$,
  'P0009', null,
  'confirm_booking rejects a NULL payment amount, even against a hold with '
  'a perfectly good quote');

set local role postgres;
select is(
  (select count(*)::int from public.payments
    where gateway_ref in ('refund_null_quote', 'refund_null_amount')),
  0,
  'neither NULL-hole attempt recorded a payment');

reset role;

select * from finish();
rollback;
