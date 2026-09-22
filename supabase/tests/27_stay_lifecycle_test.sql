-- reservation_status gains checked_in/checked_out + reservations gains
-- checked_in_at/checked_out_at, added in 0031_stay_lifecycle.sql.

begin;
select plan(6);

select enum_has_labels(
  'public', 'reservation_status',
  array['hold','pending_payment','confirmed','checked_in','checked_out','cancelled']
);

select has_column('public', 'reservations', 'checked_in_at', 'reservations has checked_in_at');
select has_column('public', 'reservations', 'checked_out_at', 'reservations has checked_out_at');

insert into public.properties (id, name, slug)
values ('aaaaaaaa-0000-0000-0000-000000000027','P27','p27');
insert into public.units (id, property_id, name, capacity_base, capacity_max)
values ('bbbbbbbb-0000-0000-0000-000000000027',
        'aaaaaaaa-0000-0000-0000-000000000027','U27', 4, 6);

select lives_ok(
  $$insert into public.reservations
      (unit_id, period, kind, status, customer_id, checked_in_at, checked_out_at)
    values ('bbbbbbbb-0000-0000-0000-000000000027',
            public.build_period('bbbbbbbb-0000-0000-0000-000000000027',
              current_date + 1, current_date + 2),
            'booking', 'checked_out', '10000000-0000-0000-0000-000000000005',
            now() - interval '1 day', now())$$,
  'checked_out_at after checked_in_at is accepted'
);

select throws_ok(
  $$insert into public.reservations
      (unit_id, period, kind, status, customer_id, checked_in_at, checked_out_at)
    values ('bbbbbbbb-0000-0000-0000-000000000027',
            public.build_period('bbbbbbbb-0000-0000-0000-000000000027',
              current_date + 5, current_date + 6),
            'booking', 'checked_out', '10000000-0000-0000-0000-000000000005',
            now(), now() - interval '1 day')$$,
  '23514', null,
  'checked_out_at before checked_in_at is rejected'
);

select is(
  (select status::text from public.reservations
    where unit_id = 'bbbbbbbb-0000-0000-0000-000000000027'
      and checked_out_at is not null),
  'checked_out',
  'the new enum value round-trips through a real row'
);

select * from finish();
rollback;
