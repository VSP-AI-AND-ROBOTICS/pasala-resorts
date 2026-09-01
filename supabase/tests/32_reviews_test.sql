-- reviews, added in 0036_reviews.sql.

begin;
select plan(7);

select has_table('public', 'reviews', 'reviews table exists');

insert into public.properties (id, name, slug)
values ('aaaaaaaa-0000-0000-0000-000000000032','P32','p32');
insert into public.units (id, property_id, name, capacity_base, capacity_max)
values ('bbbbbbbb-0000-0000-0000-000000000032',
        'aaaaaaaa-0000-0000-0000-000000000032','U32', 4, 6);
insert into public.reservations (id, unit_id, period, kind, status, customer_id)
values
  ('97800000-0000-0000-0000-000000000001', 'bbbbbbbb-0000-0000-0000-000000000032',
   public.build_period('bbbbbbbb-0000-0000-0000-000000000032', current_date-3, current_date-1),
   'booking', 'checked_out', '10000000-0000-0000-0000-000000000005'),
  ('97800000-0000-0000-0000-000000000002', 'bbbbbbbb-0000-0000-0000-000000000032',
   public.build_period('bbbbbbbb-0000-0000-0000-000000000032', current_date+5, current_date+6),
   'booking', 'confirmed', '10000000-0000-0000-0000-000000000006');

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"10000000-0000-0000-0000-000000000005","role":"authenticated"}';

select lives_ok(
  $$insert into public.reviews
      (reservation_id, customer_id, farmhouse_rating, cleanliness_rating,
       food_rating, service_rating, activities_rating, overall_rating, feedback)
    values ('97800000-0000-0000-0000-000000000001',
            '10000000-0000-0000-0000-000000000005', 5, 5, 4, 5, 4, 5, 'Loved it')$$,
  'a customer can review their own checked-out stay'
);

select throws_ok(
  $$insert into public.reviews
      (reservation_id, customer_id, farmhouse_rating, cleanliness_rating,
       food_rating, service_rating, activities_rating, overall_rating)
    values ('97800000-0000-0000-0000-000000000001',
            '10000000-0000-0000-0000-000000000005', 5, 5, 5, 5, 5, 5)$$,
  '23505', null,
  'a second review for the same reservation is rejected'
);

set local request.jwt.claims to
  '{"sub":"10000000-0000-0000-0000-000000000006","role":"authenticated"}';

select throws_ok(
  $$insert into public.reviews
      (reservation_id, customer_id, farmhouse_rating, cleanliness_rating,
       food_rating, service_rating, activities_rating, overall_rating)
    values ('97800000-0000-0000-0000-000000000002',
            '10000000-0000-0000-0000-000000000006', 5, 5, 5, 5, 5, 5)$$,
  '42501', null,
  'a stay that has not been checked out yet cannot be reviewed'
);

select is(
  (select count(*)::int from public.reviews
    where reservation_id = '97800000-0000-0000-0000-000000000001'),
  0,
  'a different customer cannot see ravi''s review'
);

set local request.jwt.claims to
  '{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}';

select is(
  (select count(*)::int from public.reviews
    where reservation_id = '97800000-0000-0000-0000-000000000001'),
  1,
  'staff-or-above can see every review'
);

set local request.jwt.claims to
  '{"sub":"10000000-0000-0000-0000-000000000005","role":"authenticated"}';

select throws_ok(
  $$insert into public.reviews
      (reservation_id, customer_id, farmhouse_rating, cleanliness_rating,
       food_rating, service_rating, activities_rating, overall_rating)
    values ('97800000-0000-0000-0000-000000000002',
            '10000000-0000-0000-0000-000000000005', 5, 5, 5, 5, 5, 5)$$,
  '42501', null,
  'a customer cannot review a reservation they do not own'
);

reset role;
select * from finish();
rollback;
