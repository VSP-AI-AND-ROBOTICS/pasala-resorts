-- Reporting and dashboard layer: revenue, occupancy, and the staff
-- dashboard summary. Every figure is computed in the database so the
-- client never performs arithmetic on money.
--
-- Beyond the brief's 6 assertions, this file adds coverage the owner will
-- actually rely on to make decisions:
--   - report_revenue's gross/net/refunded numbers are checked against an
--     exact figure planted by this file's own fixture (not re-derived),
--     so the test cannot pass by re-implementing the same arithmetic bug.
--   - a cancelled booking's total lands in `refunded`, never in `net`.
--   - report_occupancy's night count is exercised across a booking whose
--     checkout, expressed in UTC, falls on a different calendar date than
--     it does in the property's Asia/Kolkata timezone -- the exact trap
--     described in the task brief for the `least(upper(period)::date, ...)`
--     arithmetic.
--   - report_revenue/report_occupancy (not just dashboard_summary) are
--     each individually proven to gate a customer with P0008.
--   - a property filter is proven to actually filter, not just accepted.
--   - dashboard_summary is proven to succeed for an accountant, since
--     accountant is staff-or-above and must see the numbers too.

begin;
select plan(21);

select has_function('public','dashboard_summary','dashboard_summary() exists');
select has_function('public','report_revenue','report_revenue() exists');
select has_function('public','report_occupancy','report_occupancy() exists');

insert into auth.users (id, email)
values ('cccc0000-0000-0000-0000-000000000001','repcust@example.com'),
       ('cccc0000-0000-0000-0000-000000000002','repstaff@example.com');

-- This test no longer depends on the app's real seeded properties (see
-- docs/superpowers/specs/2026-08-13-single-property-onboarding-design.md
-- section 3.3) -- it proves report_revenue/report_occupancy don't leak
-- one property's figures into another's using two properties it owns
-- entirely, so it stays correct regardless of what the real seed data
-- looks like.
insert into public.properties (id, name, slug)
values
  ('e0000000-0000-0000-0000-000000000001','Report Test Property A','report-test-a'),
  ('e0000000-0000-0000-0000-000000000002','Report Test Property B','report-test-b');

-- Fixture units under this file's own properties (A/B), so the
-- property-filter assertion below exercises the actual filter path.
insert into public.units (id, property_id, name, capacity_base, capacity_max, booking_mode)
values
  ('d0000000-0000-0000-0000-000000000001','e0000000-0000-0000-0000-000000000001',
   'Report Test Property A Unit A', 2, 4, 'nightly'),
  ('d0000000-0000-0000-0000-000000000002','e0000000-0000-0000-0000-000000000002',
   'Report Test Property B Unit B', 2, 4, 'nightly'),
  ('d0000000-0000-0000-0000-000000000003','e0000000-0000-0000-0000-000000000001',
   'Report Test Property A Unit C', 2, 4, 'nightly');

insert into public.resort_members (property_id, user_id, role) values
  ('e0000000-0000-0000-0000-000000000001','cccc0000-0000-0000-0000-000000000002','staff'),
  ('e0000000-0000-0000-0000-000000000002','cccc0000-0000-0000-0000-000000000002','staff'),
  ('e0000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000004','accountant');

-- R1: a confirmed Property A booking on 2027-03-01 with a total this file
-- controls directly -- report_revenue must echo this number back exactly.
insert into public.reservations
  (unit_id, period, kind, status, customer_id, guests, quote, source)
values
  ('d0000000-0000-0000-0000-000000000001',
   public.build_period('d0000000-0000-0000-0000-000000000001',
                       date '2027-03-01', date '2027-03-03'),
   'booking','confirmed','cccc0000-0000-0000-0000-000000000001',2,
   jsonb_build_object('total', 20000.00), 'app');

-- R4: a confirmed Property B booking on the SAME day, with a different total.
-- If the property filter leaked, the Property A-scoped query below would
-- either pick up a second row or a contaminated sum.
insert into public.reservations
  (unit_id, period, kind, status, customer_id, guests, quote, source)
values
  ('d0000000-0000-0000-0000-000000000002',
   public.build_period('d0000000-0000-0000-0000-000000000002',
                       date '2027-03-01', date '2027-03-03'),
   'booking','confirmed','cccc0000-0000-0000-0000-000000000001',2,
   jsonb_build_object('total', 9999.00), 'app');

-- R3: a cancelled Property A booking on a different day, own known total --
-- and, deliberately, a `refund_amount` (2000.00) that DIFFERS from that
-- quoted total (8000.00). C2: `report_revenue`'s `refunded` used to sum
-- the whole cancelled booking's quoted total, ignoring `refund_amount`
-- entirely (the policy-computed figure `cancel_booking` actually stores) --
-- a fixture where the two numbers happen to be equal cannot tell a fixed
-- "refunded" bug apart from a correct one. Reproduced live before this
-- fix: a cancelled Rs10,000 booking with `refund_amount = 0` reported
-- `refunded = 10000`.
insert into public.reservations
  (unit_id, period, kind, status, customer_id, guests, quote,
   cancelled_at, cancel_reason, source, refund_pct, refund_amount)
values
  ('d0000000-0000-0000-0000-000000000001',
   public.build_period('d0000000-0000-0000-0000-000000000001',
                       date '2027-03-05', date '2027-03-06'),
   'booking','cancelled','cccc0000-0000-0000-0000-000000000001',2,
   jsonb_build_object('total', 8000.00), now(), 'test cancellation', 'app',
   25.00, 2000.00);

-- R5: the timezone trap. Check-in 2027-04-05 22:00 IST, checkout
-- 2027-04-07 02:00 IST -- a real 2-night stay in the property's local
-- calendar. Converted to UTC, checkout (02:00 IST) lands at 2027-04-06
-- 20:30 UTC: the UTC calendar date is one day EARLIER than the IST date.
-- A night count that casts `upper(period)::date` under the session's UTC
-- timezone, instead of the property's Asia/Kolkata, will therefore see a
-- 1-night stay, not 2.
insert into public.reservations
  (unit_id, period, kind, status, customer_id, guests, quote, source)
values
  ('d0000000-0000-0000-0000-000000000003',
   tstzrange('2027-04-05 22:00:00+05:30'::timestamptz,
             '2027-04-07 02:00:00+05:30'::timestamptz, '[)'),
   'booking','confirmed','cccc0000-0000-0000-0000-000000000001',2,
   jsonb_build_object('total', 15000.00), 'app');

-- I6: a checked_in booking and a checked_out booking must both still count
-- as revenue -- 0031_stay_lifecycle.sql added these statuses to the
-- reservation lifecycle after report_revenue was written, and the fix
-- being tested here is that neither one silently vanishes from the
-- numbers just because the guest actually completed (or is completing)
-- their stay.
insert into public.reservations
  (unit_id, period, kind, status, customer_id, guests, quote, source)
values
  ('d0000000-0000-0000-0000-000000000001',
   public.build_period('d0000000-0000-0000-0000-000000000001',
                       date '2027-03-08', date '2027-03-09'),
   'booking','checked_in','cccc0000-0000-0000-0000-000000000001',2,
   jsonb_build_object('total', 5000.00), 'app'),
  ('d0000000-0000-0000-0000-000000000001',
   public.build_period('d0000000-0000-0000-0000-000000000001',
                       date '2027-03-09', date '2027-03-10'),
   'booking','checked_out','cccc0000-0000-0000-0000-000000000001',2,
   jsonb_build_object('total', 6000.00), 'app');

-- I6: a checked_in booking must still count toward occupied nights.
insert into public.reservations
  (unit_id, period, kind, status, customer_id, guests, quote, source)
values
  ('d0000000-0000-0000-0000-000000000003',
   public.build_period('d0000000-0000-0000-0000-000000000003',
                       date '2027-05-01', date '2027-05-03'),
   'booking','checked_in','cccc0000-0000-0000-0000-000000000001',2,
   jsonb_build_object('total', 10000.00), 'app');

-- === a customer must not be able to read the business's numbers ==========

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"cccc0000-0000-0000-0000-000000000001","role":"authenticated"}';

select throws_ok(
  $$select public.dashboard_summary('e0000000-0000-0000-0000-000000000001')$$,
  'P0020', null, 'a customer cannot read the dashboard');

select throws_ok(
  $$select * from public.report_revenue(current_date, current_date,
     'e0000000-0000-0000-0000-000000000001')$$,
  'P0020', null, 'a customer cannot call report_revenue directly');

select throws_ok(
  $$select * from public.report_occupancy(current_date, current_date,
     'e0000000-0000-0000-0000-000000000001')$$,
  'P0020', null, 'a customer cannot call report_occupancy directly');

-- === staff can ============================================================

set local request.jwt.claims to
  '{"sub":"cccc0000-0000-0000-0000-000000000002","role":"authenticated"}';

select lives_ok(
  $$select public.dashboard_summary('e0000000-0000-0000-0000-000000000001')$$,
  'staff can read the dashboard');

select is(
  (select jsonb_typeof(public.dashboard_summary('e0000000-0000-0000-0000-000000000001') -> 'month_revenue')),
  'number',
  'month_revenue is a number');

-- === report_revenue: exact figure planted by this fixture, and the ======
-- === property filter actually filters =====================================

select is(
  (select count(*)::int from public.report_revenue(
     date '2027-03-01', date '2027-03-01',
     'e0000000-0000-0000-0000-000000000001')),
  1,
  'report_revenue scoped to Property A returns one row, not the Property B one too');

select is(
  (select gross from public.report_revenue(
     date '2027-03-01', date '2027-03-01',
     'e0000000-0000-0000-0000-000000000001')),
  20000.00::numeric,
  'report_revenue gross matches the exact total planted in the fixture, not 20000+9999');

-- === a cancelled booking is refunded, never net ===========================
-- === C2: refunded is the ACTUAL refund_amount, not the quoted total ======

select is(
  (select refunded from public.report_revenue(
     date '2027-03-05', date '2027-03-05',
     'e0000000-0000-0000-0000-000000000001')),
  2000.00::numeric,
  'C2: refunded is R3''s actual refund_amount (2000), not its quoted '
  'total (8000) -- the two are deliberately different in this fixture so '
  'a fabricated-refund bug cannot hide behind a coincidentally-equal '
  'number');

select isnt(
  (select refunded from public.report_revenue(
     date '2027-03-05', date '2027-03-05',
     'e0000000-0000-0000-0000-000000000001')),
  8000.00::numeric,
  'C2: refunded is explicitly NOT the cancelled booking''s full quoted '
  'total -- this is the exact fabrication the fix removes');

select is(
  (select net from public.report_revenue(
     date '2027-03-05', date '2027-03-05',
     'e0000000-0000-0000-0000-000000000001')),
  -2000.00::numeric,
  'C2: net is gross (0, no confirmed booking that day) minus the actual '
  'refund (2000) -- net can go negative on a refund-only day, proving it '
  'is real subtraction, not a copy of gross');

-- === I6: checked_in/checked_out bookings still count as revenue =========

select is(
  (select gross from public.report_revenue(
     date '2027-03-08', date '2027-03-08',
     'e0000000-0000-0000-0000-000000000001')),
  5000.00::numeric,
  'I6: a checked_in booking still contributes its total to gross revenue');

select is(
  (select gross from public.report_revenue(
     date '2027-03-09', date '2027-03-09',
     'e0000000-0000-0000-0000-000000000001')),
  6000.00::numeric,
  'I6: a checked_out booking still contributes its total to gross revenue');

-- === report_occupancy: night count survives the UTC/IST boundary =========

select is(
  (select nights_booked from public.report_occupancy(
     date '2027-04-01', date '2027-04-11',
     'e0000000-0000-0000-0000-000000000001')
   where unit_id = 'd0000000-0000-0000-0000-000000000003'),
  2,
  'a 2-night stay whose checkout crosses the UTC/IST date boundary is still counted as 2 nights');

select is(
  (select occupancy_pct from public.report_occupancy(
     date '2027-04-01', date '2027-04-11',
     'e0000000-0000-0000-0000-000000000001')
   where unit_id = 'd0000000-0000-0000-0000-000000000003'),
  20.0::numeric,
  '2 nights in a 10-day window is 20.0 percent occupancy');

-- === I6: a checked_in booking still counts toward occupied nights =======

select is(
  (select nights_booked from public.report_occupancy(
     date '2027-05-01', date '2027-05-11',
     'e0000000-0000-0000-0000-000000000001')
   where unit_id = 'd0000000-0000-0000-0000-000000000003'),
  2,
  'I6: a checked_in booking still counts its nights toward occupancy');

-- === carried-forward fix: the range filter, not just the night-count =====
-- === arithmetic, must use property-local midnight =========================
--
-- Asia/Kolkata (a positive UTC offset) cannot demonstrate this bug through
-- report_occupancy's *output*: the skew band the buggy filter mis-handles
-- always lands exactly on the query's own p_from/p_to boundary date, which
-- the night-count's `least`/`greatest` clipping already zeroes out
-- regardless of whether the row is included. Proven by exhaustive
-- brute-force search over reservation timings before writing this comment,
-- not just argued. A property WEST of UTC does not get this accidental
-- cancellation -- Pacific/Honolulu (UTC-10, no DST to complicate the
-- arithmetic) is used here purely to make the bug observable, not because
-- the business operates one; `properties.timezone` is free text and the
-- report must not corrupt itself the day a westward property is added.
set local role postgres;

insert into public.properties (id, name, slug, timezone)
values ('a0000000-0000-0000-0000-000000000009',
        'Report Test Honolulu','report-test-honolulu','Pacific/Honolulu');

insert into public.units (id, property_id, name, capacity_base, capacity_max, booking_mode)
values ('d0000000-0000-0000-0000-000000000009',
        'a0000000-0000-0000-0000-000000000009','Report Test Honolulu A',
        2, 4, 'nightly');

insert into public.resort_members (property_id, user_id, role) values
  ('a0000000-0000-0000-0000-000000000009','cccc0000-0000-0000-0000-000000000002','staff');

-- Check-in 2027-06-05 12:00 UTC (comfortably before the query window).
-- Check-out 2027-06-10 05:00 UTC: in Pacific/Honolulu (UTC-10) that is
-- 2027-06-09 19:00 HST -- LOCAL DATE 2027-06-09, one full day before the
-- query's p_from of 2027-06-10. This booking has no real local-date
-- overlap with the window at all and must contribute zero nights.
--
-- The buggy filter instead builds its range as literal UTC-midnight
-- instants (`tstzrange('2027-06-10'::timestamptz, ...)` = starts at
-- 2027-06-10 00:00 UTC), and the checkout instant (05:00 UTC) falls just
-- after that -- so the buggy filter wrongly INCLUDES this row, and its
-- (already-fixed) night-count arithmetic then computes
-- `2027-06-09 - 2027-06-10 = -1`, corrupting the sum with a negative
-- night count. Reproduced live against the unfixed migration before this
-- fix: `nights_booked = -1, occupancy_pct = -20.0`.
insert into public.reservations
  (unit_id, period, kind, status, customer_id, guests, source)
values
  ('d0000000-0000-0000-0000-000000000009',
   tstzrange('2027-06-05 12:00:00+00','2027-06-10 05:00:00+00','[)'),
   'booking','confirmed','cccc0000-0000-0000-0000-000000000001',2,'app');

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"cccc0000-0000-0000-0000-000000000002","role":"authenticated"}';

select is(
  (select nights_booked from public.report_occupancy(
     date '2027-06-10', date '2027-06-15',
     'a0000000-0000-0000-0000-000000000009')
   where unit_id = 'd0000000-0000-0000-0000-000000000009'),
  0,
  'a booking with no real local-date overlap contributes zero nights, '
  'not a negative count, once the filter uses property-local midnight');

select is(
  (select occupancy_pct from public.report_occupancy(
     date '2027-06-10', date '2027-06-15',
     'a0000000-0000-0000-0000-000000000009')
   where unit_id = 'd0000000-0000-0000-0000-000000000009'),
  0.0::numeric,
  'occupancy_pct is never negative for a booking outside the window');

-- === accountant is staff-or-above and must see the numbers too ===========

set local request.jwt.claims to
  '{"sub":"10000000-0000-0000-0000-000000000004","role":"authenticated"}';

select lives_ok(
  $$select public.dashboard_summary('e0000000-0000-0000-0000-000000000001')$$,
  'an accountant can read the dashboard');

select * from finish();
rollback;
