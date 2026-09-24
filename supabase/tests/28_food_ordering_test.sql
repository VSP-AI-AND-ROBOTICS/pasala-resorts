-- food_categories/food_items/food_orders/food_order_items +
-- place_food_order, added in 0032_food_ordering.sql.

begin;
select plan(12);

select has_table('public', 'food_orders', 'food_orders table exists');
select has_function('public', 'place_food_order', 'place_food_order exists');

insert into public.properties (id, name, slug)
values ('aaaaaaaa-0000-0000-0000-000000000028','P28','p28');

-- The seed users' roles are memberships at the seed resort only; give them
-- the same roles at this file's property.
insert into public.resort_members (property_id, user_id, role) values
  ('aaaaaaaa-0000-0000-0000-000000000028','10000000-0000-0000-0000-000000000001','owner'),
  ('aaaaaaaa-0000-0000-0000-000000000028','10000000-0000-0000-0000-000000000002','admin'),
  ('aaaaaaaa-0000-0000-0000-000000000028','10000000-0000-0000-0000-000000000003','staff'),
  ('aaaaaaaa-0000-0000-0000-000000000028','10000000-0000-0000-0000-000000000004','accountant');
insert into public.units (id, property_id, name, capacity_base, capacity_max)
values ('bbbbbbbb-0000-0000-0000-000000000028',
        'aaaaaaaa-0000-0000-0000-000000000028','U28', 4, 6);
insert into public.food_categories (id, property_id, name)
values ('60000000-0000-0000-0000-000000000028',
        'aaaaaaaa-0000-0000-0000-000000000028', 'Snacks');
insert into public.food_items (id, category_id, name, price) values
  ('61000000-0000-0000-0000-000000000001', '60000000-0000-0000-0000-000000000028',
   'Fries', 100),
  ('61000000-0000-0000-0000-000000000002', '60000000-0000-0000-0000-000000000028',
   'Soda', 50);

-- A confirmed booking for ravi (seeded customer ...005), and a still-on-hold
-- reservation for meera (...006), to test the status gate.
insert into public.reservations (id, unit_id, period, kind, status, customer_id)
values
  ('97400000-0000-0000-0000-000000000001', 'bbbbbbbb-0000-0000-0000-000000000028',
   public.build_period('bbbbbbbb-0000-0000-0000-000000000028', current_date+1, current_date+2),
   'booking', 'confirmed', '10000000-0000-0000-0000-000000000005'),
  ('97400000-0000-0000-0000-000000000002', 'bbbbbbbb-0000-0000-0000-000000000028',
   public.build_period('bbbbbbbb-0000-0000-0000-000000000028', current_date+5, current_date+6),
   'booking', 'hold', '10000000-0000-0000-0000-000000000006');

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"10000000-0000-0000-0000-000000000005","role":"authenticated"}';

select lives_ok(
  $$select public.place_food_order('97400000-0000-0000-0000-000000000001',
      '[{"food_item_id":"61000000-0000-0000-0000-000000000001","quantity":2},
        {"food_item_id":"61000000-0000-0000-0000-000000000002","quantity":1}]'::jsonb)$$,
  'a confirmed guest can place a food order'
);

select is(
  (select total from public.food_orders
    where reservation_id = '97400000-0000-0000-0000-000000000001'),
  250::numeric,
  'total is priced server-side: 2x100 + 1x50 = 250'
);

select is(
  (select count(*)::int from public.food_order_items fi
    join public.food_orders o on o.id = fi.order_id
    where o.reservation_id = '97400000-0000-0000-0000-000000000001'),
  2,
  'both line items were recorded'
);

select throws_ok(
  $$select public.place_food_order('97400000-0000-0000-0000-000000000001', '[]'::jsonb)$$,
  'P0003', null, 'an empty order is rejected'
);

set local request.jwt.claims to
  '{"sub":"10000000-0000-0000-0000-000000000006","role":"authenticated"}';

select throws_ok(
  $$select public.place_food_order('97400000-0000-0000-0000-000000000002',
      '[{"food_item_id":"61000000-0000-0000-0000-000000000001","quantity":1}]'::jsonb)$$,
  'P0009', null, 'a still-on-hold reservation cannot order food yet'
);

select throws_ok(
  $$select public.place_food_order('97400000-0000-0000-0000-000000000001',
      '[{"food_item_id":"61000000-0000-0000-0000-000000000001","quantity":1}]'::jsonb)$$,
  'P0008', null, 'a customer cannot order food against someone else''s reservation'
);

-- === read: owner + staff-or-above only ======================================

select is(
  (select count(*)::int from public.food_orders
    where reservation_id = '97400000-0000-0000-0000-000000000001'),
  0,
  'a different customer cannot see ravi''s order'
);

set local request.jwt.claims to
  '{"sub":"10000000-0000-0000-0000-000000000003","role":"authenticated"}';

select is(
  (select count(*)::int from public.food_orders
    where reservation_id = '97400000-0000-0000-0000-000000000001'),
  1,
  'staff can see every order'
);

-- === status updates: staff-or-above only, silently affects zero rows for =
-- === anyone else (same `properties_write` shape as elsewhere) ================

select lives_ok(
  $$update public.food_orders set status = 'accepted'
    where reservation_id = '97400000-0000-0000-0000-000000000001'$$,
  'staff can move an order to accepted'
);

set local request.jwt.claims to
  '{"sub":"10000000-0000-0000-0000-000000000005","role":"authenticated"}';

with attempted as (
  update public.food_orders set status = 'delivered'
  where reservation_id = '97400000-0000-0000-0000-000000000001'
  returning 1
)
select is(
  (select count(*)::int from attempted),
  0,
  'the customer who placed the order cannot change its status themselves'
);

reset role;
select * from finish();
rollback;
