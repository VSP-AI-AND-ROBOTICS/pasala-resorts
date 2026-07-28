-- unit_calendar_events: the identity-free mirror of reservation occupancy
-- (Task 15 fix round). Covers: the sync trigger keeps the mirror in step
-- with reservations (insert/cancel/update/delete), and -- the point of the
-- whole exercise -- a customer can read another customer's occupancy via
-- the mirror even though `reservations` itself still hides it from them.

begin;
select plan(13);

insert into public.properties (id, name, slug)
values ('aaaaaaaa-0000-0000-0000-000000000001','P1','p1');
insert into public.units (id, property_id, name, capacity_base, capacity_max)
values ('bbbbbbbb-0000-0000-0000-000000000001',
        'aaaaaaaa-0000-0000-0000-000000000001','U1',4,6);

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111','custa@example.com'),
  ('22222222-2222-2222-2222-222222222222','custb@example.com');

-- === trigger behaviour (run as postgres, bypassing reservations RLS, same
-- === convention as 04_reservations_test.sql) ===============================

-- fixture kept alive through the whole file for the RLS contrast below:
-- a confirmed booking owned by customer B.
insert into public.reservations
  (id, unit_id, period, kind, status, customer_id, guests)
values ('cccccccc-0000-0000-0000-000000000001',
        'bbbbbbbb-0000-0000-0000-000000000001',
        tstzrange('2026-08-03 14:00+05:30','2026-08-05 11:00+05:30','[)'),
        'booking','confirmed','22222222-2222-2222-2222-222222222222',2);

select is(
  (select count(*)::int from public.unit_calendar_events
    where reservation_id = 'cccccccc-0000-0000-0000-000000000001'),
  1, 'insert creates exactly one mirror row');

select is(
  (select unit_id from public.unit_calendar_events
    where reservation_id = 'cccccccc-0000-0000-0000-000000000001'),
  'bbbbbbbb-0000-0000-0000-000000000001'::uuid,
  'mirror row carries the same unit_id');

select is(
  (select period from public.unit_calendar_events
    where reservation_id = 'cccccccc-0000-0000-0000-000000000001'),
  tstzrange('2026-08-03 14:00+05:30','2026-08-05 11:00+05:30','[)'),
  'mirror row carries the same period');

select is(
  (select kind from public.unit_calendar_events
    where reservation_id = 'cccccccc-0000-0000-0000-000000000001'),
  'booking'::public.reservation_kind,
  'mirror row carries the same kind');

-- cancelling a reservation removes its mirror row
insert into public.reservations (id, unit_id, period, kind, status, block_reason)
values ('cccccccc-0000-0000-0000-000000000002',
        'bbbbbbbb-0000-0000-0000-000000000001',
        tstzrange('2026-09-01 00:00+05:30','2026-09-02 00:00+05:30','[)'),
        'block','confirmed','maintenance');

update public.reservations set status = 'cancelled'
where id = 'cccccccc-0000-0000-0000-000000000002';

select is(
  (select count(*)::int from public.unit_calendar_events
    where reservation_id = 'cccccccc-0000-0000-0000-000000000002'),
  0, 'cancelling a reservation removes its mirror row');

-- updating a reservation's period updates the mirror row
insert into public.reservations (id, unit_id, period, kind, status, block_reason)
values ('cccccccc-0000-0000-0000-000000000003',
        'bbbbbbbb-0000-0000-0000-000000000001',
        tstzrange('2026-10-01 00:00+05:30','2026-10-02 00:00+05:30','[)'),
        'block','confirmed','maintenance');

update public.reservations
  set period = tstzrange('2026-10-05 00:00+05:30','2026-10-06 00:00+05:30','[)')
where id = 'cccccccc-0000-0000-0000-000000000003';

select is(
  (select period from public.unit_calendar_events
    where reservation_id = 'cccccccc-0000-0000-0000-000000000003'),
  tstzrange('2026-10-05 00:00+05:30','2026-10-06 00:00+05:30','[)'),
  'updating a reservation period updates the mirror row');

select is(
  (select count(*)::int from public.unit_calendar_events
    where reservation_id = 'cccccccc-0000-0000-0000-000000000003'),
  1, 'update does not duplicate the mirror row');

-- deleting a reservation removes the mirror row
insert into public.reservations (id, unit_id, period, kind, status, block_reason)
values ('cccccccc-0000-0000-0000-000000000004',
        'bbbbbbbb-0000-0000-0000-000000000001',
        tstzrange('2026-11-01 00:00+05:30','2026-11-02 00:00+05:30','[)'),
        'block','confirmed','maintenance');

delete from public.reservations
where id = 'cccccccc-0000-0000-0000-000000000004';

select is(
  (select count(*)::int from public.unit_calendar_events
    where reservation_id = 'cccccccc-0000-0000-0000-000000000004'),
  0, 'deleting a reservation removes the mirror row');

-- the mirror exposes no customer identity, structurally
select hasnt_column('public','unit_calendar_events','customer_id',
  'mirror exposes no customer_id column');

-- === the point of the whole exercise: customer A can see customer B's ======
-- === occupancy via the mirror, but not via reservations itself =============

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

select is(
  (select count(*)::int from public.unit_calendar_events
    where reservation_id = 'cccccccc-0000-0000-0000-000000000001'),
  1,
  'customer A can read the mirror row for a booking owned by customer B');

select is(
  (select count(*)::int from public.reservations
    where id = 'cccccccc-0000-0000-0000-000000000001'),
  0,
  'customer A cannot read that same booking from reservations directly');

-- anon can read the mirror too
set local role anon;
set local request.jwt.claims to '{"role":"anon"}';

select is(
  (select count(*)::int from public.unit_calendar_events
    where reservation_id = 'cccccccc-0000-0000-0000-000000000001'),
  1,
  'anon can read the mirror');

-- no client can write the mirror directly: no insert grant at all
set local role authenticated;
set local request.jwt.claims to
  '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

select throws_ok(
  $$insert into public.unit_calendar_events
      (reservation_id, unit_id, period, kind, status)
    values ('cccccccc-0000-0000-0000-000000000001',
      'bbbbbbbb-0000-0000-0000-000000000001',
      tstzrange('2027-01-01 00:00+05:30','2027-01-02 00:00+05:30','[)'),
      'block','confirmed')$$,
  '42501', null, 'customer cannot insert into the mirror directly');

select * from finish();
rollback;
