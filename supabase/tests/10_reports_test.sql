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
select plan(15);

select has_function('public','dashboard_summary','dashboard_summary() exists');
select has_function('public','report_revenue','report_revenue() exists');
select has_function('public','report_occupancy','report_occupancy() exists');

insert into auth.users (id, email)
values ('cccc0000-0000-0000-0000-000000000001','repcust@example.com'),
       ('cccc0000-0000-0000-0000-000000000002','repstaff@example.com');

update public.profiles set role = 'staff'
  where id = 'cccc0000-0000-0000-0000-000000000002';

-- Fixture units under the real seeded properties (Riverside/Hilltop), so
-- the property-filter assertion below exercises the actual filter path.
insert into public.units (id, property_id, name, capacity_base, capacity_max, booking_mode)
values
  ('d0000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001',
   'Report Test Riverside A', 2, 4, 'nightly'),
  ('d0000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000002',
   'Report Test Hilltop B', 2, 4, 'nightly'),
  ('d0000000-0000-0000-0000-000000000003','a0000000-0000-0000-0000-000000000001',
   'Report Test Riverside C', 2, 4, 'nightly');

-- R1: a confirmed Riverside booking on 2027-03-01 with a total this file
-- controls directly -- report_revenue must echo this number back exactly.
insert into public.reservations
  (unit_id, period, kind, status, customer_id, guests, quote, source)
values
  ('d0000000-0000-0000-0000-000000000001',
   public.build_period('d0000000-0000-0000-0000-000000000001',
                       date '2027-03-01', date '2027-03-03'),
   'booking','confirmed','cccc0000-0000-0000-0000-000000000001',2,
   jsonb_build_object('total', 20000.00), 'app');

-- R4: a confirmed Hilltop booking on the SAME day, with a different total.
-- If the property filter leaked, the Riverside-scoped query below would
-- either pick up a second row or a contaminated sum.
insert into public.reservations
  (unit_id, period, kind, status, customer_id, guests, quote, source)
values
  ('d0000000-0000-0000-0000-000000000002',
   public.build_period('d0000000-0000-0000-0000-000000000002',
                       date '2027-03-01', date '2027-03-03'),
   'booking','confirmed','cccc0000-0000-0000-0000-000000000001',2,
   jsonb_build_object('total', 9999.00), 'app');

-- R3: a cancelled Riverside booking on a different day, own known total.
insert into public.reservations
  (unit_id, period, kind, status, customer_id, guests, quote,
   cancelled_at, cancel_reason, source)
values
  ('d0000000-0000-0000-0000-000000000001',
   public.build_period('d0000000-0000-0000-0000-000000000001',
                       date '2027-03-05', date '2027-03-06'),
   'booking','cancelled','cccc0000-0000-0000-0000-000000000001',2,
   jsonb_build_object('total', 8000.00), now(), 'test cancellation', 'app');

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

-- === a customer must not be able to read the business's numbers ==========

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"cccc0000-0000-0000-0000-000000000001","role":"authenticated"}';

select throws_ok(
  $$select public.dashboard_summary()$$,
  'P0008', null, 'a customer cannot read the dashboard');

select throws_ok(
  $$select * from public.report_revenue(current_date, current_date)$$,
  'P0008', null, 'a customer cannot call report_revenue directly');

select throws_ok(
  $$select * from public.report_occupancy(current_date, current_date)$$,
  'P0008', null, 'a customer cannot call report_occupancy directly');

-- === staff can ============================================================

set local request.jwt.claims to
  '{"sub":"cccc0000-0000-0000-0000-000000000002","role":"authenticated"}';

select lives_ok(
  $$select public.dashboard_summary()$$,
  'staff can read the dashboard');

select is(
  (select jsonb_typeof(public.dashboard_summary() -> 'month_revenue')),
  'number',
  'month_revenue is a number');

-- === report_revenue: exact figure planted by this fixture, and the ======
-- === property filter actually filters =====================================

select is(
  (select count(*)::int from public.report_revenue(
     date '2027-03-01', date '2027-03-01',
     'a0000000-0000-0000-0000-000000000001')),
  1,
  'report_revenue scoped to Riverside returns one row, not the Hilltop one too');

select is(
  (select gross from public.report_revenue(
     date '2027-03-01', date '2027-03-01',
     'a0000000-0000-0000-0000-000000000001')),
  20000.00::numeric,
  'report_revenue gross matches the exact total planted in the fixture, not 20000+9999');

-- === a cancelled booking is refunded, never net ===========================

select is(
  (select refunded from public.report_revenue(
     date '2027-03-05', date '2027-03-05',
     'a0000000-0000-0000-0000-000000000001')),
  8000.00::numeric,
  'a cancelled booking''s total appears in refunded');

select is(
  (select net from public.report_revenue(
     date '2027-03-05', date '2027-03-05',
     'a0000000-0000-0000-0000-000000000001')),
  0::numeric,
  'a cancelled booking''s total does not appear in net');

-- === report_occupancy: night count survives the UTC/IST boundary =========

select is(
  (select nights_booked from public.report_occupancy(
     date '2027-04-01', date '2027-04-11',
     'a0000000-0000-0000-0000-000000000001')
   where unit_id = 'd0000000-0000-0000-0000-000000000003'),
  2,
  'a 2-night stay whose checkout crosses the UTC/IST date boundary is still counted as 2 nights');

select is(
  (select occupancy_pct from public.report_occupancy(
     date '2027-04-01', date '2027-04-11',
     'a0000000-0000-0000-0000-000000000001')
   where unit_id = 'd0000000-0000-0000-0000-000000000003'),
  20.0::numeric,
  '2 nights in a 10-day window is 20.0 percent occupancy');

-- === accountant is staff-or-above and must see the numbers too ===========

set local request.jwt.claims to
  '{"sub":"10000000-0000-0000-0000-000000000004","role":"authenticated"}';

select lives_ok(
  $$select public.dashboard_summary()$$,
  'an accountant can read the dashboard');

select * from finish();
rollback;
