-- create_hold's new optional p_occasion parameter: a free-text note
-- captured at hold time, never read by get_quote or any pricing path,
-- stored as-is on the reservation row. See
-- docs/superpowers/specs/2026-08-13-single-property-onboarding-design.md
-- section 3.2.

begin;
select plan(3);

select has_column('public', 'reservations', 'occasion',
  'reservations gains an occasion column');

insert into auth.users (id, email)
values ('d1111111-1111-1111-1111-111111111111','occasioncust@example.com');

insert into public.properties (id, name, slug)
values ('cccccccc-0000-0000-0000-000000000001',
        'Occasion Test Property','occasion-test');
insert into public.units (id, property_id, name, capacity_base, capacity_max)
values ('dddddddd-0000-0000-0000-000000000001',
        'cccccccc-0000-0000-0000-000000000001','Occasion Test Unit',4,6);
insert into public.rate_rules
  (unit_id, kind, price, extra_guest_price, cleaning_fee, priority)
values ('dddddddd-0000-0000-0000-000000000001','base',10000,1500,1500,0);

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"d1111111-1111-1111-1111-111111111111","role":"authenticated"}';

-- occasion is stored verbatim when supplied
select is(
  (select occasion from public.create_hold(
     'dddddddd-0000-0000-0000-000000000001',
     '2026-08-03','2026-08-04', 4, null, null, null,
     'Anniversary weekend')),
  'Anniversary weekend',
  'create_hold stores the supplied occasion');

-- omitting occasion defaults to null, matching every existing caller that
-- doesn't know this parameter exists
select is(
  (select occasion from public.create_hold(
     'dddddddd-0000-0000-0000-000000000001',
     '2026-09-03','2026-09-04', 4)),
  null,
  'create_hold defaults occasion to null when omitted');

reset role;

select * from finish();
rollback;
