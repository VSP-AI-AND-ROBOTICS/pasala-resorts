-- activities/activity_bookings + book_activity, added in 0033_activity_booking.sql.

begin;
select plan(9);

select has_table('public', 'activity_bookings', 'activity_bookings table exists');
select has_function('public', 'book_activity', 'book_activity exists');

insert into public.properties (id, name, slug)
values ('aaaaaaaa-0000-0000-0000-000000000029','P29','p29');
insert into public.units (id, property_id, name, capacity_base, capacity_max)
values ('bbbbbbbb-0000-0000-0000-000000000029',
        'aaaaaaaa-0000-0000-0000-000000000029','U29', 4, 6);
insert into public.activities (id, property_id, name, price_per_person, capacity_per_slot)
values ('63000000-0000-0000-0000-000000000001',
        'aaaaaaaa-0000-0000-0000-000000000029', 'Badminton', 100, 4);

insert into public.reservations (id, unit_id, period, kind, status, customer_id)
values
  ('97500000-0000-0000-0000-000000000001', 'bbbbbbbb-0000-0000-0000-000000000029',
   public.build_period('bbbbbbbb-0000-0000-0000-000000000029', current_date+1, current_date+2),
   'booking', 'confirmed', '10000000-0000-0000-0000-000000000005'),
  ('97500000-0000-0000-0000-000000000002', 'bbbbbbbb-0000-0000-0000-000000000029',
   public.build_period('bbbbbbbb-0000-0000-0000-000000000029', current_date+5, current_date+6),
   'booking', 'confirmed', '10000000-0000-0000-0000-000000000006');

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"10000000-0000-0000-0000-000000000005","role":"authenticated"}';

select lives_ok(
  $$select public.book_activity('97500000-0000-0000-0000-000000000001',
      '63000000-0000-0000-0000-000000000001', current_date+2, '17:00', 3)$$,
  'a confirmed guest can book an activity slot'
);

select is(
  (select amount from public.activity_bookings
    where reservation_id = '97500000-0000-0000-0000-000000000001'),
  300::numeric,
  'amount is priced server-side: 3 people x 100 = 300'
);

set local request.jwt.claims to
  '{"sub":"10000000-0000-0000-0000-000000000006","role":"authenticated"}';

select throws_ok(
  $$select public.book_activity('97500000-0000-0000-0000-000000000002',
      '63000000-0000-0000-0000-000000000001', current_date+2, '17:00', 2)$$,
  'P0010', null,
  'a second booking that would exceed the 4-person slot capacity is rejected'
);

select lives_ok(
  $$select public.book_activity('97500000-0000-0000-0000-000000000002',
      '63000000-0000-0000-0000-000000000001', current_date+2, '17:00', 1)$$,
  'a booking that exactly fills the remaining slot capacity succeeds'
);

select throws_ok(
  $$select public.book_activity('97500000-0000-0000-0000-000000000001',
      '63000000-0000-0000-0000-000000000001', current_date+2, '18:00', 1)$$,
  'P0008', null,
  'a customer cannot book activities against someone else''s reservation'
);

-- Owner can cancel their own booking directly (no RPC needed); nobody else
-- can update someone else's booking to any status.
with attempted as (
  update public.activity_bookings set status = 'cancelled'
  where reservation_id = '97500000-0000-0000-0000-000000000001'
  returning 1
)
select is(
  (select count(*)::int from attempted), 0,
  'a customer cannot cancel someone else''s activity booking'
);

set local request.jwt.claims to
  '{"sub":"10000000-0000-0000-0000-000000000005","role":"authenticated"}';

select lives_ok(
  $$update public.activity_bookings set status = 'cancelled'
    where reservation_id = '97500000-0000-0000-0000-000000000001'$$,
  'the owning customer can cancel their own activity booking'
);

reset role;
select * from finish();
rollback;
