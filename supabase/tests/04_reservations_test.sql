begin;
select plan(10);

insert into public.properties (id, name, slug, check_in_time, check_out_time)
values ('aaaaaaaa-0000-0000-0000-000000000001','P1','p1','14:00','11:00');

insert into public.units (id, property_id, name, capacity_base, capacity_max)
values ('bbbbbbbb-0000-0000-0000-000000000001',
        'aaaaaaaa-0000-0000-0000-000000000001','U1',4,6);

insert into auth.users (id, email)
values ('dddddddd-0000-0000-0000-000000000001','guest@example.com');

insert into public.reservations
  (unit_id, period, kind, status, customer_id, guests)
values ('bbbbbbbb-0000-0000-0000-000000000001',
        tstzrange('2026-08-03 14:00+05:30','2026-08-05 11:00+05:30','[)'),
        'booking','confirmed','dddddddd-0000-0000-0000-000000000001',2);

-- overlapping insert is rejected by the constraint
select throws_ok(
  $$insert into public.reservations
      (unit_id, period, kind, status, customer_id, guests)
    values ('bbbbbbbb-0000-0000-0000-000000000001',
      tstzrange('2026-08-04 14:00+05:30','2026-08-06 11:00+05:30','[)'),
      'booking','confirmed','dddddddd-0000-0000-0000-000000000001',2)$$,
  '23P01', null, 'overlapping reservation is rejected');

-- an admin block over a confirmed booking hits the same constraint
select throws_ok(
  $$insert into public.reservations (unit_id, period, kind, status, block_reason)
    values ('bbbbbbbb-0000-0000-0000-000000000001',
      tstzrange('2026-08-04 00:00+05:30','2026-08-04 23:59+05:30','[)'),
      'block','confirmed','maintenance')$$,
  '23P01', null, 'block cannot overlap a confirmed booking');

-- back-to-back checkout 11:00 / checkin 14:00 does not conflict
select lives_ok(
  $$insert into public.reservations
      (unit_id, period, kind, status, customer_id, guests)
    values ('bbbbbbbb-0000-0000-0000-000000000001',
      tstzrange('2026-08-05 14:00+05:30','2026-08-06 11:00+05:30','[)'),
      'booking','confirmed','dddddddd-0000-0000-0000-000000000001',2)$$,
  'back-to-back stays do not conflict');

-- cancelling frees the range immediately
update public.reservations set status = 'cancelled'
where period && tstzrange('2026-08-03 14:00+05:30','2026-08-05 11:00+05:30','[)');

select lives_ok(
  $$insert into public.reservations
      (unit_id, period, kind, status, customer_id, guests)
    values ('bbbbbbbb-0000-0000-0000-000000000001',
      tstzrange('2026-08-03 14:00+05:30','2026-08-05 11:00+05:30','[)'),
      'booking','confirmed','dddddddd-0000-0000-0000-000000000001',2)$$,
  'cancelled reservation frees its range');

-- a booking without a customer is rejected
select throws_ok(
  $$insert into public.reservations (unit_id, period, kind, status)
    values ('bbbbbbbb-0000-0000-0000-000000000001',
      tstzrange('2027-01-03 14:00+05:30','2027-01-04 11:00+05:30','[)'),
      'booking','confirmed')$$,
  '23514', null, 'a booking without a customer is rejected');

-- build_period applies the property check-in and check-out times
select is(
  public.build_period('bbbbbbbb-0000-0000-0000-000000000001',
                      '2026-09-01'::date, '2026-09-03'::date),
  tstzrange('2026-09-01 14:00+05:30','2026-09-03 11:00+05:30','[)'),
  'nightly period uses property check-in/out times');

-- I2: a NULL check-in date used to sail straight through
-- `p_to <= p_from` (NULL, not TRUE) and come out as an unbounded,
-- non-empty tstzrange. Both dates are mandatory input.
select throws_ok(
  $$select public.build_period('bbbbbbbb-0000-0000-0000-000000000001',
      null, '2026-09-03'::date)$$,
  'P0005', null,
  'I2: build_period raises P0005 when check-in date is NULL');

select throws_ok(
  $$select public.build_period('bbbbbbbb-0000-0000-0000-000000000001',
      '2026-09-01'::date, null)$$,
  'P0005', null,
  'I2: build_period raises P0005 when check-out date is NULL (nightly)');

-- I2 belt-and-braces (0010_period_bounds.sql): the table itself must
-- reject an unbounded period even from a direct insert that bypasses
-- build_period entirely (e.g. a future write path, or admin-policy access).
select throws_ok(
  $$insert into public.reservations
      (unit_id, period, kind, status, block_reason)
    values ('bbbbbbbb-0000-0000-0000-000000000001',
      tstzrange('2029-01-01 14:00+05:30', null, '[)'),
      'block','confirmed','unbounded test')$$,
  '23514', null,
  'I2: an unbounded period is rejected by reservations_period_bounded');

-- search_availability reports the unit busy for an overlapping window
select is(
  (select is_available from public.search_availability(
     'aaaaaaaa-0000-0000-0000-000000000001',
     '2026-08-04'::date, '2026-08-05'::date, 4)),
  false,
  'busy unit reported unavailable');

select * from finish();
rollback;
