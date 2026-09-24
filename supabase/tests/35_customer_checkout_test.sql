-- checkout_booking widened to allow the owning customer to self-checkout,
-- added in 0039_customer_checkout.sql. The doc's own checkout step
-- ("Customer selects Checkout... Customer pays remaining balance")
-- describes guest self-checkout, matching `confirm_booking`'s own
-- customer-callable precedent.

begin;
select plan(4);

insert into public.properties (id, name, slug)
values ('aaaaaaaa-0000-0000-0000-000000000039','P39','p39');
insert into public.units (id, property_id, name, capacity_base, capacity_max)
values ('bbbbbbbb-0000-0000-0000-000000000039',
        'aaaaaaaa-0000-0000-0000-000000000039','U39', 4, 6);
insert into public.reservations (id, unit_id, period, kind, status, customer_id, quote)
values ('97b00000-0000-0000-0000-000000000001', 'bbbbbbbb-0000-0000-0000-000000000039',
   public.build_period('bbbbbbbb-0000-0000-0000-000000000039', current_date+1, current_date+2),
   'booking', 'checked_in', '10000000-0000-0000-0000-000000000005',
   jsonb_build_object('total', 5000));
insert into public.payments (reservation_id, amount, kind, status, gateway, gateway_ref)
values ('97b00000-0000-0000-0000-000000000001', 5000, 'advance', 'succeeded', 'mock', 'ref-39-adv');

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"10000000-0000-0000-0000-000000000006","role":"authenticated"}';

select throws_ok(
  $$select public.checkout_booking('97b00000-0000-0000-0000-000000000001', 'ref-39-x', 0)$$,
  'P0020', null,
  'a different customer cannot check someone else out'
);

set local request.jwt.claims to
  '{"sub":"10000000-0000-0000-0000-000000000005","role":"authenticated"}';

select lives_ok(
  $$select public.checkout_booking('97b00000-0000-0000-0000-000000000001', 'ref-39-self', 0)$$,
  'the owning guest can check themselves out with nothing further to pay'
);

select is(
  (select status::text from public.reservations
    where id = '97b00000-0000-0000-0000-000000000001'),
  'checked_out',
  'the reservation is now checked_out via self-checkout'
);

select is(
  (select count(*)::int from public.payments
    where reservation_id = '97b00000-0000-0000-0000-000000000001' and kind = 'balance'),
  0,
  'no balance payment was recorded when the balance was already zero'
);

reset role;
select * from finish();
rollback;
