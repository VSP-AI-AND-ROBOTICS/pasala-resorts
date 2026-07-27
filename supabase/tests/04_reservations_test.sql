begin;
select plan(6);

insert into public.properties (id, name, slug, check_in_time, check_out_time)
values ('aaaaaaaa-0000-0000-0000-000000000001','P1','p1','14:00','11:00');

insert into public.units (id, property_id, name, capacity_base, capacity_max)
values ('bbbbbbbb-0000-0000-0000-000000000001',
        'aaaaaaaa-0000-0000-0000-000000000001','U1',4,6);

insert into public.reservations (unit_id, period, kind, status)
values ('bbbbbbbb-0000-0000-0000-000000000001',
        tstzrange('2026-08-03 14:00+05:30','2026-08-05 11:00+05:30','[)'),
        'booking','confirmed');

-- overlapping insert is rejected by the constraint
select throws_ok(
  $$insert into public.reservations (unit_id, period, kind, status)
    values ('bbbbbbbb-0000-0000-0000-000000000001',
      tstzrange('2026-08-04 14:00+05:30','2026-08-06 11:00+05:30','[)'),
      'booking','confirmed')$$,
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
  $$insert into public.reservations (unit_id, period, kind, status)
    values ('bbbbbbbb-0000-0000-0000-000000000001',
      tstzrange('2026-08-05 14:00+05:30','2026-08-06 11:00+05:30','[)'),
      'booking','confirmed')$$,
  'back-to-back stays do not conflict');

-- cancelling frees the range immediately
update public.reservations set status = 'cancelled'
where period && tstzrange('2026-08-03 14:00+05:30','2026-08-05 11:00+05:30','[)');

select lives_ok(
  $$insert into public.reservations (unit_id, period, kind, status)
    values ('bbbbbbbb-0000-0000-0000-000000000001',
      tstzrange('2026-08-03 14:00+05:30','2026-08-05 11:00+05:30','[)'),
      'booking','confirmed')$$,
  'cancelled reservation frees its range');

-- build_period applies the property check-in and check-out times
select is(
  public.build_period('bbbbbbbb-0000-0000-0000-000000000001',
                      '2026-09-01'::date, '2026-09-03'::date),
  tstzrange('2026-09-01 14:00+05:30','2026-09-03 11:00+05:30','[)'),
  'nightly period uses property check-in/out times');

-- search_availability reports the unit busy for an overlapping window
select is(
  (select is_available from public.search_availability(
     'aaaaaaaa-0000-0000-0000-000000000001',
     '2026-08-04'::date, '2026-08-05'::date, 4)),
  false,
  'busy unit reported unavailable');

select * from finish();
rollback;
