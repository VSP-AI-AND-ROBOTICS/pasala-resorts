-- properties.tax_pct/min_nights/max_nights + get_quote's additive tax/
-- night-range enforcement, added in 0025_property_settings.sql.

begin;
select plan(9);

insert into public.properties (id, name, slug)
values ('aaaaaaaa-0000-0000-0000-000000000021','P21','p21');

insert into public.units (id, property_id, name, capacity_base, capacity_max)
values ('bbbbbbbb-0000-0000-0000-000000000021',
        'aaaaaaaa-0000-0000-0000-000000000021','U21', 4, 6);

insert into public.rate_rules
  (unit_id, kind, price, extra_guest_price, cleaning_fee, priority)
values ('bbbbbbbb-0000-0000-0000-000000000021','base',10000,0,1500,0);

-- Default tax_pct = 0 -- a property that never visits Settings keeps
-- today's total byte-for-byte.
select is(
  (public.get_quote('bbbbbbbb-0000-0000-0000-000000000021',
     tstzrange('2026-08-03 14:00+05:30','2026-08-04 11:00+05:30','[)'),
     4) ->> 'total')::numeric,
  11500::numeric,
  'zero-tax property prices exactly as before this migration'
);

update public.properties set tax_pct = 18
  where id = 'aaaaaaaa-0000-0000-0000-000000000021';

-- subtotal 10000 + cleaning 1500 = 11500; 18% tax = 2070; total = 13570.
select is(
  (public.get_quote('bbbbbbbb-0000-0000-0000-000000000021',
     tstzrange('2026-08-03 14:00+05:30','2026-08-04 11:00+05:30','[)'),
     4) ->> 'tax_amount')::numeric,
  2070::numeric,
  '18% tax on an 11500 subtotal is 2070'
);

select is(
  (public.get_quote('bbbbbbbb-0000-0000-0000-000000000021',
     tstzrange('2026-08-03 14:00+05:30','2026-08-04 11:00+05:30','[)'),
     4) ->> 'total')::numeric,
  13570::numeric,
  'total includes tax on top of subtotal + cleaning'
);

-- No night limits set yet -- a one-night stay is accepted.
select lives_ok(
  $$select public.get_quote('bbbbbbbb-0000-0000-0000-000000000021',
      tstzrange('2026-08-03 14:00+05:30','2026-08-04 11:00+05:30','[)'), 4)$$,
  'a one-night stay is fine with no night limits set'
);

update public.properties
  set min_nights = 2, max_nights = 5
  where id = 'aaaaaaaa-0000-0000-0000-000000000021';

select throws_ok(
  $$select public.get_quote('bbbbbbbb-0000-0000-0000-000000000021',
      tstzrange('2026-08-03 14:00+05:30','2026-08-04 11:00+05:30','[)'), 4)$$,
  'P0015', null,
  'a one-night stay is rejected once min_nights = 2'
);

select lives_ok(
  $$select public.get_quote('bbbbbbbb-0000-0000-0000-000000000021',
      tstzrange('2026-08-03 14:00+05:30','2026-08-05 11:00+05:30','[)'), 4)$$,
  'a two-night stay satisfies min_nights = 2'
);

select throws_ok(
  $$select public.get_quote('bbbbbbbb-0000-0000-0000-000000000021',
      tstzrange('2026-08-03 14:00+05:30','2026-08-09 11:00+05:30','[)'), 4)$$,
  'P0015', null,
  'a six-night stay is rejected once max_nights = 5'
);

-- Night limits are skipped entirely for slot bookings.
insert into public.slot_types (id, property_id, code, start_time, end_time)
values ('55550000-0000-0000-0000-000000000021',
        'aaaaaaaa-0000-0000-0000-000000000021','night','18:00','09:00');

insert into public.rate_rules
  (unit_id, kind, price, extra_guest_price, cleaning_fee, priority, slot_type_id)
values ('bbbbbbbb-0000-0000-0000-000000000021','base',7000,0,500,0,
        '55550000-0000-0000-0000-000000000021');

select lives_ok(
  $$select public.get_quote('bbbbbbbb-0000-0000-0000-000000000021',
      tstzrange('2026-08-03 18:00+05:30','2026-08-04 09:00+05:30','[)'),
      4, '55550000-0000-0000-0000-000000000021')$$,
  'a slot booking is exempt from the nightly min/max-nights check'
);

-- properties_write RLS (0003_properties_units.sql) already covers the new
-- columns -- confirm a non-admin still cannot set them. `properties_write`
-- is a plain `using (is_admin())` policy (not the `using (true)` +
-- enforcement-trigger pattern `tasks_admin_delete` uses), so a non-admin's
-- update matches zero rows and returns success with no rows changed,
-- rather than throwing -- same "silently affects zero rows, not insecure"
-- shape `20_tasks_test.sql` proves for the analogous case.
set local role authenticated;
set local request.jwt.claims to
  '{"sub":"10000000-0000-0000-0000-000000000005","role":"authenticated"}';

with attempted as (
  update public.properties set tax_pct = 5
  where id = 'aaaaaaaa-0000-0000-0000-000000000021'
  returning 1
)
select is(
  (select count(*)::int from attempted),
  0,
  'a customer cannot edit property settings -- the update matches zero rows'
);

reset role;
select * from finish();
rollback;
