begin;
select plan(4);

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

select * from finish();
rollback;
