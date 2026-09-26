-- Final-review minors, fixed in 0061_final_review_minors.sql:
--   4. search_resorts matches properties.city (added in 0059).
--   5. Coupon codes match whatever case the app sends (0051 stores them
--      upper-cased; older app builds may send lower case).
--   6. Two same-name listing applications at once do not collide on the
--      slug: apply_for_listing retries with a fresh slug.
--   7. payment_webhook_events keeps only the ids and fields needed for
--      idempotency and audit, and processed rows older than 90 days are
--      pruned by a pg_cron job.
begin;
select plan(23);

-- ---------------------------------------------------------------------
-- 4. search_resorts matches the city column.
insert into public.properties
  (id, name, slug, description, address, city, status, is_active)
values
  ('d6100000-0000-4000-8000-000000000001', 'Mango Grove', 'm61-mango',
   'Orchard cottages', 'Survey No. 12, Main Road', 'Vikarabad', 'active', true);

select is(
  (select array_agg(s.name) from public.search_resorts('vikarabad') s
    where s.slug like 'm61-%'),
  array['Mango Grove'],
  'search_resorts matches a word that appears only in the city column');

select is(
  (select array_agg(s.name) from public.search_resorts('mango VIKARABAD') s
    where s.slug like 'm61-%'),
  array['Mango Grove'],
  'every word may match a different field, the city included');

update public.properties set city = null
 where id = 'd6100000-0000-4000-8000-000000000001';
select is(
  (select count(*)::int from public.search_resorts('vikarabad') s
    where s.slug like 'm61-%'),
  0,
  'a resort with no city simply does not match on it');

-- ---------------------------------------------------------------------
-- 5. Coupon codes are case-insensitive at redemption.
insert into public.properties (id, name, slug)
values ('d6100000-0000-4000-8000-000000000002', 'M61 Coupons', 'm61-coupons');
insert into public.units (id, property_id, name, capacity_base, capacity_max)
values ('d6100000-0000-4000-8000-000000000012',
        'd6100000-0000-4000-8000-000000000002', 'U1', 4, 6);
insert into public.rate_rules
  (unit_id, kind, price, extra_guest_price, cleaning_fee, priority)
values ('d6100000-0000-4000-8000-000000000012', 'base', 10000, 1500, 1500, 0);
insert into public.coupons (property_id, code, kind, value, max_redemptions) values
  ('d6100000-0000-4000-8000-000000000002', 'SAVE10', 'percent', 10, 5);

insert into auth.users (id, email) values
  ('d6100000-0000-4000-8000-0000000000a1', 'm61-guest@example.com'),
  ('d6100000-0000-4000-8000-0000000000a2', 'm61-applicant@example.com');

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"d6100000-0000-4000-8000-0000000000a1","role":"authenticated"}';

select is(
  (public.get_quote('d6100000-0000-4000-8000-000000000012',
     tstzrange('2027-01-05 14:00+05:30', '2027-01-06 11:00+05:30'),
     4, null, 'save10') -> 'coupon' ->> 'discount')::numeric,
  1150::numeric,
  'get_quote applies a stored upper-case coupon sent in lower case');

select is(
  (public.get_quote('d6100000-0000-4000-8000-000000000012',
     tstzrange('2027-01-05 14:00+05:30', '2027-01-06 11:00+05:30'),
     4, null, '  Save10 ') -> 'coupon' ->> 'code'),
  'SAVE10',
  'surrounding spaces and mixed case are ignored; the quote shows the stored code');

select lives_ok(
  $$select public.create_hold('d6100000-0000-4000-8000-000000000012',
      '2027-01-05', '2027-01-06', 4, null, 10350, 'save10')$$,
  'create_hold redeems a lower-case code at the discounted total');

reset role;
select is(
  (select redeemed_count from public.coupons
    where property_id = 'd6100000-0000-4000-8000-000000000002' and code = 'SAVE10'),
  1,
  'the lower-case hold counted one redemption against the stored coupon');
select is(
  (select count(*)::int from public.coupon_redemptions cr
     join public.coupons c on c.id = cr.coupon_id
    where c.property_id = 'd6100000-0000-4000-8000-000000000002'),
  1,
  'and recorded the redemption row');

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"d6100000-0000-4000-8000-0000000000a1","role":"authenticated"}';
select throws_ok(
  $$select public.get_quote('d6100000-0000-4000-8000-000000000012',
      tstzrange('2027-01-05 14:00+05:30', '2027-01-06 11:00+05:30'),
      4, null, 'save11')$$,
  'P0010', null,
  'an unknown code still raises P0010');
reset role;

-- ---------------------------------------------------------------------
-- 6. apply_for_listing survives a slug taken between the check and the
-- insert. The race is simulated by a resort_slug_for that returns a taken
-- slug on its first call only, as a concurrent applicant's commit would
-- make it; the replacement is rolled back with the rest of the test.
insert into public.properties (id, name, slug, status)
values ('d6100000-0000-4000-8000-000000000003', 'Twin Pines', 'm61-twin-pines', 'active');

-- A sequence, not a table: the failed attempt's subtransaction is rolled
-- back, and a counter row would be rolled back with it.
create sequence pg_temp.slug_calls;

create or replace function public.resort_slug_for(p_name text)
returns text
language plpgsql
volatile
set search_path = public, pg_temp
as $f$
declare v_n int;
begin
  v_n := nextval('pg_temp.slug_calls');
  return case when v_n = 1 then 'm61-twin-pines' else 'm61-twin-pines-' || v_n end;
end;
$f$;

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"d6100000-0000-4000-8000-0000000000a2","role":"authenticated"}';

select lives_ok(
  $$select public.apply_for_listing('Twin Pines', 'Ooty', '4 Lake Road, Ooty',
      '+919876543210', 'Pine cabins above the lake, with a bonfire every night.')$$,
  'apply_for_listing retries when its slug was taken by a concurrent application');
reset role;

select is(
  (select p.slug from public.properties p
     join public.listing_applications a on a.property_id = p.id
    where a.applicant_id = 'd6100000-0000-4000-8000-0000000000a2'),
  'm61-twin-pines-2',
  'the retried application got the next free slug');
select is((select last_value from pg_temp.slug_calls)::int, 2,
  'the slug was computed exactly twice: the stale one and the retry');
select is(
  (select count(*)::int from public.resort_members m
     join public.listing_applications a on a.property_id = m.property_id
    where a.applicant_id = 'd6100000-0000-4000-8000-0000000000a2'
      and m.user_id = 'd6100000-0000-4000-8000-0000000000a2'
      and m.role = 'owner'),
  1,
  'the rest of the application (membership) was written once');

-- A unique violation that is not about the slug is not swallowed.
select ok(
  position('properties_slug_key' in
    (select pg_get_functiondef('public.apply_for_listing(text, text, text, text, text, public.subscription_tier)'::regprocedure))) > 0,
  'apply_for_listing only retries on the properties_slug_key violation');

-- ---------------------------------------------------------------------
-- 7. The webhook ledger stores ids, not guest contact details.
select is(
  public.payment_webhook_begin('evt_m61_1', 'payment.captured', jsonb_build_object(
    'entity', 'event',
    'account_id', 'acc_1',
    'event', 'payment.captured',
    'contains', jsonb_build_array('payment'),
    'created_at', 1790000000,
    'payload', jsonb_build_object(
      'payment', jsonb_build_object('entity', jsonb_build_object(
        'id', 'pay_1', 'entity', 'payment', 'amount', 1035000, 'currency', 'INR',
        'status', 'captured', 'order_id', 'order_1', 'method', 'upi',
        'captured', true, 'amount_refunded', 0,
        'email', 'guest@example.com', 'contact', '+919876543210',
        'vpa', 'guest@okbank', 'notes', jsonb_build_object('name', 'Gita'),
        'card', jsonb_build_object('last4', '1111'),
        'acquirer_data', jsonb_build_object('rrn', '123'),
        'error_code', null, 'created_at', 1790000000))))),
  true,
  'a new webhook event is begun');

select is(
  (select payload from public.payment_webhook_events where event_id = 'evt_m61_1'),
  jsonb_build_object(
    'entity', 'event',
    'account_id', 'acc_1',
    'event', 'payment.captured',
    'contains', jsonb_build_array('payment'),
    'created_at', 1790000000,
    'payload', jsonb_build_object(
      'payment', jsonb_build_object('entity', jsonb_build_object(
        'id', 'pay_1', 'entity', 'payment', 'amount', 1035000, 'currency', 'INR',
        'status', 'captured', 'order_id', 'order_1', 'method', 'upi',
        'captured', true, 'amount_refunded', 0,
        'error_code', null, 'created_at', 1790000000)))),
  'the stored payload keeps the event and payment ids, amounts and status, and drops email, phone, VPA, card, notes and acquirer data');

select is(
  public.payment_webhook_redact(jsonb_build_object(
    'event', 'refund.processed',
    'payload', jsonb_build_object(
      'refund', jsonb_build_object('entity', jsonb_build_object(
        'id', 'rfnd_1', 'payment_id', 'pay_1', 'amount', 500000, 'currency', 'INR',
        'status', 'processed', 'notes', jsonb_build_object('email', 'x@example.com'),
        'receipt', 'r1')),
      'payment', jsonb_build_object('entity', jsonb_build_object(
        'id', 'pay_1', 'order_id', 'order_1', 'email', 'x@example.com',
        'contact', '+911234567890')),
      'order', jsonb_build_object('entity', jsonb_build_object(
        'id', 'order_1', 'status', 'paid', 'amount', 1035000, 'amount_paid', 1035000,
        'receipt', 'res_1', 'notes', jsonb_build_object('phone', '+911234567890')))))),
  jsonb_build_object(
    'event', 'refund.processed',
    'payload', jsonb_build_object(
      'refund', jsonb_build_object('entity', jsonb_build_object(
        'id', 'rfnd_1', 'payment_id', 'pay_1', 'amount', 500000, 'currency', 'INR',
        'status', 'processed', 'receipt', 'r1')),
      'payment', jsonb_build_object('entity', jsonb_build_object(
        'id', 'pay_1', 'order_id', 'order_1')),
      'order', jsonb_build_object('entity', jsonb_build_object(
        'id', 'order_1', 'status', 'paid', 'amount', 1035000, 'amount_paid', 1035000,
        'receipt', 'res_1')))),
  'refund and order entities keep their ids, amounts and status only');

select is(public.payment_webhook_redact('"not an object"'::jsonb), '{}'::jsonb,
  'a payload that is not an object is stored as {}');
select is(public.payment_webhook_redact(null), '{}'::jsonb,
  'a null payload is stored as {}');

-- Retention: processed rows older than 90 days go; recent or unfinished
-- rows stay.
insert into public.payment_webhook_events (event_id, event, payload, received_at, processed_at, outcome)
values
  ('evt_m61_old_done', 'payment.captured', '{}', now() - interval '91 days', now() - interval '91 days', 'settled:paid'),
  ('evt_m61_new_done', 'payment.captured', '{}', now() - interval '89 days', now() - interval '89 days', 'settled:paid'),
  ('evt_m61_old_open', 'payment.captured', '{}', now() - interval '120 days', null, null);

select is(public.payment_webhook_prune() >= 1, true,
  'payment_webhook_prune reports the rows it deleted');
select is(
  (select array_agg(event_id order by event_id) from public.payment_webhook_events
    where event_id like 'evt_m61_%'),
  array['evt_m61_1', 'evt_m61_new_done', 'evt_m61_old_open'],
  'only processed rows older than 90 days are pruned');

select is(
  (select count(*)::int from cron.job
    where jobname = 'payment-webhook-prune'
      and command ilike '%payment_webhook_prune()%'),
  1,
  'a pg_cron job runs the prune');

select ok(
  not has_function_privilege('authenticated', 'public.payment_webhook_prune()', 'execute')
  and not has_function_privilege('anon', 'public.payment_webhook_prune()', 'execute')
  and not has_function_privilege('service_role', 'public.payment_webhook_prune()', 'execute'),
  'no API role may run the prune');

select * from finish();
rollback;
