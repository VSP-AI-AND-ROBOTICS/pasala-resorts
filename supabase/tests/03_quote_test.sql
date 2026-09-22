begin;
select plan(12);

insert into public.properties (id, name, slug)
values ('aaaaaaaa-0000-0000-0000-000000000001','P1','p1');

insert into public.units (id, property_id, name, capacity_base, capacity_max)
values ('bbbbbbbb-0000-0000-0000-000000000001',
        'aaaaaaaa-0000-0000-0000-000000000001','U1', 4, 6);

-- base 10000/night, +1500 per extra guest, 1500 cleaning
insert into public.rate_rules
  (unit_id, kind, price, extra_guest_price, cleaning_fee, priority)
values ('bbbbbbbb-0000-0000-0000-000000000001','base',10000,1500,1500,0);

-- weekend 12000, Sat+Sun (ISO dow 6,7)
insert into public.rate_rules
  (unit_id, kind, price, extra_guest_price, cleaning_fee, priority, weekdays)
values ('bbbbbbbb-0000-0000-0000-000000000001','weekend',12000,1500,1500,10,
        array[6,7]);

-- Mon 2026-08-03 to Tue 2026-08-04: one weekday night
select is(
  (public.get_quote('bbbbbbbb-0000-0000-0000-000000000001',
     tstzrange('2026-08-03 14:00+05:30','2026-08-04 11:00+05:30','[)'),
     4) ->> 'total')::numeric,
  11500::numeric,
  'weekday night = 10000 + 1500 cleaning'
);

-- Sat 2026-08-08 to Sun 2026-08-09: one weekend night
select is(
  (public.get_quote('bbbbbbbb-0000-0000-0000-000000000001',
     tstzrange('2026-08-08 14:00+05:30','2026-08-09 11:00+05:30','[)'),
     4) ->> 'total')::numeric,
  13500::numeric,
  'weekend rule outranks base by priority'
);

-- 6 guests on a weekday night: 2 extra guests
select is(
  (public.get_quote('bbbbbbbb-0000-0000-0000-000000000001',
     tstzrange('2026-08-03 14:00+05:30','2026-08-04 11:00+05:30','[)'),
     6) ->> 'total')::numeric,
  14500::numeric,
  'two extra guests add 3000'
);

-- a unit with no base rule cannot be quoted
insert into public.units (id, property_id, name, capacity_base, capacity_max)
values ('bbbbbbbb-0000-0000-0000-000000000002',
        'aaaaaaaa-0000-0000-0000-000000000001','U2', 2, 2);

select throws_ok(
  $$select public.get_quote('bbbbbbbb-0000-0000-0000-000000000002',
      tstzrange('2026-08-03 14:00+05:30','2026-08-04 11:00+05:30','[)'), 2)$$,
  'P0004',
  null,
  'missing base rate is rejected'
);

-- A slot-specific rule must beat a same-priority generic rule. Both are
-- created in this one transaction, so their created_at values are identical --
-- this is the case that silently mispriced before the ordering fix.
insert into public.slot_types (id, property_id, code, start_time, end_time)
values ('55550000-0000-0000-0000-000000000001',
        'aaaaaaaa-0000-0000-0000-000000000001','night','18:00','09:00');

insert into public.rate_rules
  (unit_id, kind, price, extra_guest_price, cleaning_fee, priority, slot_type_id)
values ('bbbbbbbb-0000-0000-0000-000000000001','base',7000,0,500,0,
        '55550000-0000-0000-0000-000000000001');

select is(
  (public.get_quote('bbbbbbbb-0000-0000-0000-000000000001',
     tstzrange('2026-08-03 18:00+05:30','2026-08-04 09:00+05:30','[)'),
     4, '55550000-0000-0000-0000-000000000001') ->> 'total')::numeric,
  7500::numeric,
  'slot-specific rule beats same-priority generic rule');

select is(
  jsonb_array_length(
    public.get_quote('bbbbbbbb-0000-0000-0000-000000000001',
      tstzrange('2026-08-03 18:00+05:30','2026-08-04 09:00+05:30','[)'),
      4, '55550000-0000-0000-0000-000000000001') -> 'lines'),
  1,
  'a night slot crossing midnight yields exactly one line');

-- error-code contract: Task 11 Dart maps on these SQLSTATEs
select throws_ok(
  $$select public.get_quote('bbbbbbbb-0000-0000-0000-0000000000ff',
      tstzrange('2026-08-03 14:00+05:30','2026-08-04 11:00+05:30','[)'), 4)$$,
  'P0002', null, 'unknown unit raises P0002');

select throws_ok(
  $$select public.get_quote('bbbbbbbb-0000-0000-0000-000000000001',
      tstzrange('2026-08-03 14:00+05:30','2026-08-04 11:00+05:30','[)'), 99)$$,
  'P0003', null, 'guest count over capacity raises P0003');

select throws_ok(
  $$select public.get_quote('bbbbbbbb-0000-0000-0000-000000000001',
      tstzrange('2026-08-03 14:00+05:30','2026-08-04 11:00+05:30','[)'), null)$$,
  'P0003', null, 'null guest count raises P0003');

select throws_ok(
  $$select public.get_quote('bbbbbbbb-0000-0000-0000-000000000001',
      tstzrange('2026-08-03 14:00+05:30','2026-08-03 14:00+05:30','[)'), 4)$$,
  'P0005', null, 'empty period raises P0005');

-- RLS on rate_rules, under real roles
set local role anon;

select ok(
  (select count(*) from public.rate_rules) > 0,
  'anon can read rate rules');

select throws_ok(
  $$insert into public.rate_rules (unit_id, kind, price, priority)
    values ('bbbbbbbb-0000-0000-0000-000000000001','base',1,0)$$,
  '42501', null, 'anon cannot write rate rules');

reset role;

select * from finish();
rollback;
