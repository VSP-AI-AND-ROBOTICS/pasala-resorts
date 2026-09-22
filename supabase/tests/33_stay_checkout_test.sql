-- check_in_booking / current_charges / checkout_booking, added in
-- 0037_stay_checkout.sql.

begin;
select plan(11);

select has_function('public', 'check_in_booking', 'check_in_booking exists');
select has_function('public', 'current_charges', 'current_charges exists');
select has_function('public', 'checkout_booking', 'checkout_booking exists');

insert into public.properties (id, name, slug)
values ('aaaaaaaa-0000-0000-0000-000000000037','P37','p37');
insert into public.units (id, property_id, name, capacity_base, capacity_max)
values ('bbbbbbbb-0000-0000-0000-000000000037',
        'aaaaaaaa-0000-0000-0000-000000000037','U37', 4, 6);
insert into public.reservations (id, unit_id, period, kind, status, customer_id, quote)
values ('97900000-0000-0000-0000-000000000001', 'bbbbbbbb-0000-0000-0000-000000000037',
   public.build_period('bbbbbbbb-0000-0000-0000-000000000037', current_date+1, current_date+2),
   'booking', 'confirmed', '10000000-0000-0000-0000-000000000005',
   jsonb_build_object('total', 8000));
insert into public.payments (reservation_id, amount, kind, status, gateway, gateway_ref)
values ('97900000-0000-0000-0000-000000000001', 8000, 'advance', 'succeeded', 'mock', 'ref-37-adv');

insert into public.food_categories (id, property_id, name)
values ('64000000-0000-0000-0000-000000000037', 'aaaaaaaa-0000-0000-0000-000000000037', 'Snacks');
insert into public.food_items (id, category_id, name, price)
values ('64100000-0000-0000-0000-000000000037', '64000000-0000-0000-0000-000000000037', 'Fries', 500);

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"10000000-0000-0000-0000-000000000005","role":"authenticated"}';

select throws_ok(
  $$select public.check_in_booking('97900000-0000-0000-0000-000000000001')$$,
  'P0008', null, 'a customer cannot check themselves in'
);

set local request.jwt.claims to
  '{"sub":"10000000-0000-0000-0000-000000000003","role":"authenticated"}';

select lives_ok(
  $$select public.check_in_booking('97900000-0000-0000-0000-000000000001')$$,
  'staff can check a confirmed guest in'
);

select is(
  (select status::text from public.reservations
    where id = '97900000-0000-0000-0000-000000000001'),
  'checked_in',
  'the reservation is now checked_in'
);

set local request.jwt.claims to
  '{"sub":"10000000-0000-0000-0000-000000000005","role":"authenticated"}';

select public.place_food_order('97900000-0000-0000-0000-000000000001',
  '[{"food_item_id":"64100000-0000-0000-0000-000000000037","quantity":1}]'::jsonb);

select is(
  ((public.current_charges('97900000-0000-0000-0000-000000000001')) ->> 'balance')::numeric,
  500::numeric,
  'current_charges reflects the stay (paid) plus the unpaid food order'
);

set local request.jwt.claims to
  '{"sub":"10000000-0000-0000-0000-000000000003","role":"authenticated"}';

select throws_ok(
  $$select public.checkout_booking('97900000-0000-0000-0000-000000000001', 'ref-37-bal', 100)$$,
  'P0009', null, 'checkout rejects a payment that does not match the outstanding balance'
);

select lives_ok(
  $$select public.checkout_booking('97900000-0000-0000-0000-000000000001', 'ref-37-bal', 500)$$,
  'checkout succeeds when the payment matches the balance exactly'
);

select is(
  (select status::text from public.reservations
    where id = '97900000-0000-0000-0000-000000000001'),
  'checked_out',
  'the reservation is now checked_out'
);

select is(
  (select count(*)::int from public.payments
    where reservation_id = '97900000-0000-0000-0000-000000000001' and kind = 'balance'),
  1,
  'a balance payment was recorded'
);

reset role;
select * from finish();
rollback;
