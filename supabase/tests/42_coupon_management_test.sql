-- Coupon management (P1), added in 0051_coupon_management.sql. See
-- docs/superpowers/specs/2026-09-25-p1-coupon-management-design.md.
--
-- One file, built up by the plan's database tasks in order: each section
-- relies on the state the sections before it leave behind.
--
-- Fixtures: resort R with an owner, an admin, a staff member and an
-- accountant; resort S with an owner. Guests: Gita (a confirmed booking at
-- R), Olu (a confirmed booking at S only), Hana (only a hold at R) and
-- Kiran (only a cancelled booking at R). A platform admin with no
-- membership. R has one rate rule (10,000 a night) and two coupons written
-- straight into the table: OLD5 (3 of 5 uses taken) and KIRANVIP
-- (restricted to Kiran).
begin;
select plan(89);

insert into auth.users (id, email) values
  ('c0000000-0000-0000-0000-000000000001','cp-r-owner@example.com'),
  ('c0000000-0000-0000-0000-000000000002','cp-r-admin@example.com'),
  ('c0000000-0000-0000-0000-000000000003','cp-r-staff@example.com'),
  ('c0000000-0000-0000-0000-000000000004','cp-r-accountant@example.com'),
  ('c0000000-0000-0000-0000-000000000005','cp-s-owner@example.com'),
  ('c0000000-0000-0000-0000-000000000006','Gita.Guest@Example.com'),
  ('c0000000-0000-0000-0000-000000000007','cp-olu@example.com'),
  ('c0000000-0000-0000-0000-000000000008','cp-hana@example.com'),
  ('c0000000-0000-0000-0000-000000000009','cp-kiran@example.com'),
  ('c0000000-0000-0000-0000-00000000000a','cp-platform@example.com');
update public.profiles set full_name = 'Gita Guest'
 where id = 'c0000000-0000-0000-0000-000000000006';
update public.profiles set role = 'platform_admin'
 where id = 'c0000000-0000-0000-0000-00000000000a';

insert into public.properties (id, name, slug) values
  ('c1000000-0000-4000-8000-000000000001','Coupon R','coupons-r'),
  ('c1000000-0000-4000-8000-000000000002','Coupon S','coupons-s');

insert into public.resort_members (property_id, user_id, role) values
  ('c1000000-0000-4000-8000-000000000001','c0000000-0000-0000-0000-000000000001','owner'),
  ('c1000000-0000-4000-8000-000000000001','c0000000-0000-0000-0000-000000000002','admin'),
  ('c1000000-0000-4000-8000-000000000001','c0000000-0000-0000-0000-000000000003','staff'),
  ('c1000000-0000-4000-8000-000000000001','c0000000-0000-0000-0000-000000000004','accountant'),
  ('c1000000-0000-4000-8000-000000000002','c0000000-0000-0000-0000-000000000005','owner');

insert into public.units (id, property_id, name, capacity_base, capacity_max) values
  ('c1000000-0000-4000-8000-000000000011','c1000000-0000-4000-8000-000000000001','R Cottage',2,4),
  ('c1000000-0000-4000-8000-000000000012','c1000000-0000-4000-8000-000000000002','S Cottage',2,4);

insert into public.rate_rules (unit_id, kind, price, extra_guest_price, cleaning_fee, priority)
values ('c1000000-0000-4000-8000-000000000011', 'base', 10000, 0, 0, 0);

insert into public.reservations
  (id, unit_id, period, kind, status, customer_id, guests, hold_expires_at) values
  ('c1000000-0000-4000-8000-000000000021','c1000000-0000-4000-8000-000000000011',
   tstzrange(now() + interval '10 days', now() + interval '11 days', '[)'),
   'booking','confirmed','c0000000-0000-0000-0000-000000000006',2,null),
  ('c1000000-0000-4000-8000-000000000022','c1000000-0000-4000-8000-000000000012',
   tstzrange(now() + interval '10 days', now() + interval '11 days', '[)'),
   'booking','confirmed','c0000000-0000-0000-0000-000000000007',2,null),
  ('c1000000-0000-4000-8000-000000000023','c1000000-0000-4000-8000-000000000011',
   tstzrange(now() + interval '20 days', now() + interval '21 days', '[)'),
   'booking','hold','c0000000-0000-0000-0000-000000000008',2, now() + interval '15 minutes'),
  ('c1000000-0000-4000-8000-000000000024','c1000000-0000-4000-8000-000000000011',
   tstzrange(now() + interval '30 days', now() + interval '31 days', '[)'),
   'booking','cancelled','c0000000-0000-0000-0000-000000000009',2,null);

insert into public.coupons (id, property_id, code, kind, value, max_redemptions, redeemed_count) values
  ('c1000000-0000-4000-8000-000000000031','c1000000-0000-4000-8000-000000000001','OLD5','fixed',500,5,3);
insert into public.coupons (id, property_id, code, kind, value, customer_id) values
  ('c1000000-0000-4000-8000-000000000032','c1000000-0000-4000-8000-000000000001','KIRANVIP','percent',20,
   'c0000000-0000-0000-0000-000000000009');

-- === Task 1: the contract ===================================================

select ok(to_regprocedure('public.create_coupon(uuid, text, public.coupon_kind, numeric, numeric, date, date, integer, uuid)') is not null,
  'create_coupon has the agreed signature');
select ok(to_regprocedure('public.update_coupon(uuid, text, public.coupon_kind, numeric, numeric, date, date, integer, uuid)') is not null,
  'update_coupon has the agreed signature');
select ok(to_regprocedure('public.set_coupon_active(uuid, boolean)') is not null,
  'set_coupon_active has the agreed signature');
select ok(to_regprocedure('public.list_coupons(uuid)') is not null,
  'list_coupons has the agreed signature');
select ok(to_regprocedure('public.find_resort_guest(uuid, text)') is not null,
  'find_resort_guest has the agreed signature');

-- The parameter names are the JSON keys CouponRepository sends.
select is((select array_to_string(p.proargnames, ',') from pg_proc p
            where p.oid = to_regprocedure('public.create_coupon(uuid, text, public.coupon_kind, numeric, numeric, date, date, integer, uuid)')),
  'p_property,p_code,p_kind,p_value,p_min_amount,p_valid_from,p_valid_until,p_usage_limit,p_customer',
  'create_coupon takes the parameter names CouponRepository sends');
select is((select array_to_string(p.proargnames, ',') from pg_proc p
            where p.oid = to_regprocedure('public.update_coupon(uuid, text, public.coupon_kind, numeric, numeric, date, date, integer, uuid)')),
  'p_coupon,p_code,p_kind,p_value,p_min_amount,p_valid_from,p_valid_until,p_usage_limit,p_customer',
  'update_coupon takes the parameter names CouponRepository sends');
select is((select array_to_string(p.proargnames, ',') from pg_proc p
            where p.oid = to_regprocedure('public.set_coupon_active(uuid, boolean)')),
  'p_coupon,p_active', 'set_coupon_active takes p_coupon and p_active');
select is((select array_to_string(p.proargnames[1:2], ',') from pg_proc p
            where p.oid = to_regprocedure('public.find_resort_guest(uuid, text)')),
  'p_property,p_email', 'find_resort_guest takes p_property and p_email');

select is((select array_agg(p.parameter_name::text order by p.ordinal_position)
             from information_schema.parameters p
             join information_schema.routines r
               on r.specific_schema = p.specific_schema and r.specific_name = p.specific_name
            where r.routine_schema = 'public' and r.routine_name = 'list_coupons'
              and p.parameter_mode = 'OUT'),
  array['id','code','kind','value','min_booking_value','valid_from','valid_until',
        'max_redemptions','redeemed_count','customer_id','customer_email',
        'customer_name','is_active','status','created_at'],
  'list_coupons returns the columns Coupon.fromJson reads');
select is((select array_agg(p.parameter_name::text order by p.ordinal_position)
             from information_schema.parameters p
             join information_schema.routines r
               on r.specific_schema = p.specific_schema and r.specific_name = p.specific_name
            where r.routine_schema = 'public' and r.routine_name = 'find_resort_guest'
              and p.parameter_mode = 'OUT'),
  array['user_id','email','full_name'], 'find_resort_guest returns user_id, email and full_name');

select is((select count(*)::int
             from unnest(array[
               'public.create_coupon(uuid, text, public.coupon_kind, numeric, numeric, date, date, integer, uuid)',
               'public.update_coupon(uuid, text, public.coupon_kind, numeric, numeric, date, date, integer, uuid)',
               'public.set_coupon_active(uuid, boolean)',
               'public.list_coupons(uuid)',
               'public.find_resort_guest(uuid, text)']::regprocedure[]) f
             join pg_proc p on p.oid = f
            where p.prosecdef and p.proconfig @> array['search_path=public, pg_temp']),
  5, 'all five coupon functions are security definer with a pinned search_path');
select is((select array_agg(f::text order by f::text)
             from unnest(array[
               'public.create_coupon(uuid, text, public.coupon_kind, numeric, numeric, date, date, integer, uuid)',
               'public.update_coupon(uuid, text, public.coupon_kind, numeric, numeric, date, date, integer, uuid)',
               'public.set_coupon_active(uuid, boolean)',
               'public.list_coupons(uuid)',
               'public.find_resort_guest(uuid, text)']::regprocedure[]) f
            where has_function_privilege('anon', f, 'execute')),
  null, 'anon can execute none of the coupon functions');
select is((select count(*)::int
             from unnest(array[
               'public.create_coupon(uuid, text, public.coupon_kind, numeric, numeric, date, date, integer, uuid)',
               'public.update_coupon(uuid, text, public.coupon_kind, numeric, numeric, date, date, integer, uuid)',
               'public.set_coupon_active(uuid, boolean)',
               'public.list_coupons(uuid)',
               'public.find_resort_guest(uuid, text)']::regprocedure[]) f
            where has_function_privilege('authenticated', f, 'execute')),
  5, 'authenticated can execute all five coupon functions');

select ok(exists (select 1 from pg_constraint
                   where conrelid = 'public.coupons'::regclass
                     and conname = 'coupons_code_upper'),
  'coupons carries the upper-case code check');
select throws_ok($$insert into public.coupons (property_id, code, kind, value)
  values ('c1000000-0000-4000-8000-000000000001','lower1','fixed',100)$$,
  '23514', null, 'a lower-case code is refused by the table itself');
select throws_ok($$insert into public.coupons (property_id, code, kind, value)
  values ('c1000000-0000-4000-8000-000000000001',' PAD1','fixed',100)$$,
  '23514', null, 'a code with surrounding spaces is refused by the table itself');

-- === Task 2: create, update, activate ======================================

select is((select array_agg(p.proname::text order by p.proname)
             from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'public'
              and p.proname in ('coupon_check_input', 'is_resort_guest')
              and not p.prosecdef
              and not has_function_privilege('authenticated', p.oid, 'execute')
              and not has_function_privilege('anon', p.oid, 'execute')),
  array['coupon_check_input', 'is_resort_guest'],
  'the input check and the guest rule are internal helpers nobody calls directly');

set local role authenticated;
set local request.jwt.claims to '{"sub":"c0000000-0000-0000-0000-000000000002","role":"authenticated"}';

select ok(public.create_coupon('c1000000-0000-4000-8000-000000000001', '  save10 ', 'percent', 10) is not null,
  'an admin creates a coupon and gets its id back');
select is((select code from public.coupons
            where property_id = 'c1000000-0000-4000-8000-000000000001'
              and kind = 'percent' and value = 10),
  'SAVE10', 'the code is trimmed and upper-cased');
select lives_ok($$select public.create_coupon('c1000000-0000-4000-8000-000000000001', 'SUMMER', 'fixed', 500,
    5000, '2026-10-01', '2026-10-31', 10, 'c0000000-0000-0000-0000-000000000006')$$,
  'an admin creates a coupon with every field, for a guest who booked here');
select is((select min_booking_value || '|' || max_redemptions || '|' || customer_id || '|' ||
                  (valid_from at time zone 'Asia/Kolkata') || '|' ||
                  (valid_to at time zone 'Asia/Kolkata')
             from public.coupons
            where property_id = 'c1000000-0000-4000-8000-000000000001' and code = 'SUMMER'),
  '5000.00|10|c0000000-0000-0000-0000-000000000006|2026-10-01 00:00:00|2026-10-31 23:59:59.999999',
  'valid from/until cover whole days in the resort''s time zone');

select throws_ok($$select public.create_coupon('c1000000-0000-4000-8000-000000000001', 'AB', 'percent', 10)$$,
  'P0033', 'code_invalid', 'a two-character code is refused');
select throws_ok($$select public.create_coupon('c1000000-0000-4000-8000-000000000001', 'SAVE 20', 'percent', 10)$$,
  'P0033', 'code_invalid', 'a code with a space inside is refused');
select throws_ok($$select public.create_coupon('c1000000-0000-4000-8000-000000000001', 'ZERO', 'fixed', 0)$$,
  'P0033', 'value_invalid', 'a zero discount is refused');
select throws_ok($$select public.create_coupon('c1000000-0000-4000-8000-000000000001', 'MOST', 'percent', 101)$$,
  'P0033', 'value_invalid', 'a percentage above 100 is refused');
select throws_ok($$select public.create_coupon('c1000000-0000-4000-8000-000000000001', 'NOKIND', null, 10)$$,
  'P0033', 'kind_required', 'a coupon needs a kind');
select throws_ok($$select public.create_coupon('c1000000-0000-4000-8000-000000000001', 'NEGMIN', 'fixed', 100, -1)$$,
  'P0033', 'min_amount_invalid', 'a negative minimum is refused');
select throws_ok($$select public.create_coupon('c1000000-0000-4000-8000-000000000001', 'BACKWARD', 'fixed', 100,
    null, '2026-10-10', '2026-10-01')$$,
  'P0033', 'dates_invalid', 'an end date before the start date is refused');
select lives_ok($$select public.create_coupon('c1000000-0000-4000-8000-000000000001', 'ONEDAY', 'fixed', 100,
    null, '2026-10-10', '2026-10-10')$$,
  'a coupon valid for one day is fine');
select throws_ok($$select public.create_coupon('c1000000-0000-4000-8000-000000000001', 'NOUSE', 'fixed', 100,
    null, null, null, 0)$$,
  'P0033', 'usage_limit_invalid', 'a usage limit of 0 is refused');
select throws_ok($$select public.create_coupon('c1000000-0000-4000-8000-000000000001', 'FOROLU', 'fixed', 100,
    null, null, null, null, 'c0000000-0000-0000-0000-000000000007')$$,
  'P0033', 'guest_not_eligible', 'a guest who booked only at another resort cannot be chosen');
select throws_ok($$select public.create_coupon('c1000000-0000-4000-8000-000000000001', 'FORHANA', 'fixed', 100,
    null, null, null, null, 'c0000000-0000-0000-0000-000000000008')$$,
  'P0033', 'guest_not_eligible', 'a guest with only a hold cannot be chosen');
select throws_ok($$select public.create_coupon('c1000000-0000-4000-8000-000000000001', 'FORKIRAN', 'fixed', 100,
    null, null, null, null, 'c0000000-0000-0000-0000-000000000009')$$,
  'P0033', 'guest_not_eligible', 'a guest whose only booking was cancelled cannot be chosen');
select throws_ok($$select public.create_coupon('c1000000-0000-4000-8000-000000000001', 'save10', 'fixed', 100)$$,
  'P0033', 'code_taken', 'a code already used at this resort is refused, whatever its case');

set local request.jwt.claims to '{"sub":"c0000000-0000-0000-0000-000000000003","role":"authenticated"}';
select throws_ok($$select public.create_coupon('c1000000-0000-4000-8000-000000000001', 'STAFF1', 'fixed', 100)$$,
  'P0020', null, 'staff cannot create coupons');
set local request.jwt.claims to '{"sub":"c0000000-0000-0000-0000-000000000004","role":"authenticated"}';
select throws_ok($$select public.create_coupon('c1000000-0000-4000-8000-000000000001', 'ACCT1', 'fixed', 100)$$,
  'P0020', null, 'an accountant cannot create coupons');
set local request.jwt.claims to '{"sub":"c0000000-0000-0000-0000-000000000006","role":"authenticated"}';
select throws_ok($$select public.create_coupon('c1000000-0000-4000-8000-000000000001', 'GUEST1', 'fixed', 100)$$,
  'P0020', null, 'a guest cannot create coupons');
set local request.jwt.claims to '{"sub":"c0000000-0000-0000-0000-00000000000a","role":"authenticated"}';
select throws_ok($$select public.create_coupon('c1000000-0000-4000-8000-000000000001', 'PLAT1', 'fixed', 100)$$,
  'P0020', null, 'the platform admin cannot create coupons at a resort');
set local request.jwt.claims to '{"sub":"c0000000-0000-0000-0000-000000000001","role":"authenticated"}';
select lives_ok($$select public.create_coupon('c1000000-0000-4000-8000-000000000001', 'OWNER1', 'fixed', 250)$$,
  'the owner creates coupons');
set local request.jwt.claims to '{"sub":"c0000000-0000-0000-0000-000000000005","role":"authenticated"}';
select lives_ok($$select public.create_coupon('c1000000-0000-4000-8000-000000000002', 'SAVE10', 'percent', 5)$$,
  'another resort can use the same code');
select throws_ok($$select public.create_coupon('c1000000-0000-4000-8000-000000000001', 'SNEAKY', 'fixed', 100)$$,
  'P0020', null, 'another resort''s owner cannot create coupons here');

set local request.jwt.claims to '{"sub":"c0000000-0000-0000-0000-000000000002","role":"authenticated"}';
select lives_ok($$select public.update_coupon(
    (select id from public.coupons
      where property_id = 'c1000000-0000-4000-8000-000000000001' and code = 'SAVE10'),
    'save15', 'percent', 15)$$,
  'an admin edits a coupon');
select is((select code || '|' || value || '|' || coalesce(max_redemptions::text, 'none')
             from public.coupons
            where property_id = 'c1000000-0000-4000-8000-000000000001'
              and kind = 'percent' and value = 15),
  'SAVE15|15.00|none', 'the edit replaced the code and the value');
select throws_ok($$select public.update_coupon('c1000000-0000-4000-8000-000000000031', 'OLD5', 'fixed', 500,
    null, null, null, 2)$$,
  'P0033', 'usage_limit_below_used', 'the usage limit cannot drop below the 3 uses already taken');
select lives_ok($$select public.update_coupon('c1000000-0000-4000-8000-000000000031', 'OLD5', 'fixed', 500,
    null, null, null, 3)$$,
  'the usage limit can equal the uses already taken');
select lives_ok($$select public.update_coupon('c1000000-0000-4000-8000-000000000032', 'KIRANVIP', 'percent', 25,
    null, null, null, null, 'c0000000-0000-0000-0000-000000000009')$$,
  'a coupon keeps the guest it already had, even one who could not be chosen today');
select throws_ok($$select public.update_coupon('c1000000-0000-4000-8000-000000000032', 'KIRANVIP', 'percent', 25,
    null, null, null, null, 'c0000000-0000-0000-0000-000000000008')$$,
  'P0033', 'guest_not_eligible', 'switching to a guest who never booked here is refused');
select throws_ok($$select public.update_coupon('c1000000-0000-4000-8000-0000000000ff', 'NOPE', 'fixed', 1)$$,
  'P0002', null, 'editing an unknown coupon is P0002');
select throws_ok($$select public.update_coupon('c1000000-0000-4000-8000-000000000031', 'OWNER1', 'fixed', 500,
    null, null, null, 3)$$,
  'P0033', 'code_taken', 'renaming onto another coupon''s code is refused');
set local request.jwt.claims to '{"sub":"c0000000-0000-0000-0000-000000000003","role":"authenticated"}';
select throws_ok($$select public.update_coupon('c1000000-0000-4000-8000-000000000031', 'OLD5', 'fixed', 1)$$,
  'P0020', null, 'staff cannot edit coupons');
set local request.jwt.claims to '{"sub":"c0000000-0000-0000-0000-000000000005","role":"authenticated"}';
select throws_ok($$select public.update_coupon('c1000000-0000-4000-8000-000000000031', 'OLD5', 'fixed', 1)$$,
  'P0020', null, 'another resort''s owner cannot edit this resort''s coupons');

set local request.jwt.claims to '{"sub":"c0000000-0000-0000-0000-000000000002","role":"authenticated"}';
select lives_ok($$select public.set_coupon_active(
    (select id from public.coupons
      where property_id = 'c1000000-0000-4000-8000-000000000001' and code = 'SAVE15'), false)$$,
  'an admin deactivates a coupon');
select is((select is_active from public.coupons
            where property_id = 'c1000000-0000-4000-8000-000000000001' and code = 'SAVE15'),
  false, 'the coupon is now inactive');
set local request.jwt.claims to '{"sub":"c0000000-0000-0000-0000-000000000006","role":"authenticated"}';
select throws_ok($$select public.get_quote('c1000000-0000-4000-8000-000000000011',
    tstzrange(now() + interval '40 days', now() + interval '41 days', '[)'), 2, null, 'SAVE15')$$,
  'P0010', null, 'a guest cannot apply a deactivated coupon');
set local request.jwt.claims to '{"sub":"c0000000-0000-0000-0000-000000000002","role":"authenticated"}';
select lives_ok($$select public.set_coupon_active(
    (select id from public.coupons
      where property_id = 'c1000000-0000-4000-8000-000000000001' and code = 'SAVE15'), true)$$,
  'an admin reactivates it');
set local request.jwt.claims to '{"sub":"c0000000-0000-0000-0000-000000000006","role":"authenticated"}';
select is((public.get_quote('c1000000-0000-4000-8000-000000000011',
             tstzrange(now() + interval '40 days', now() + interval '41 days', '[)'), 2, null, 'SAVE15')
           -> 'coupon' ->> 'discount')::numeric,
  1500::numeric, 'a coupon made here applies through the unchanged get_quote: 15% of 10,000');
set local request.jwt.claims to '{"sub":"c0000000-0000-0000-0000-000000000003","role":"authenticated"}';
select throws_ok($$select public.set_coupon_active('c1000000-0000-4000-8000-000000000031', false)$$,
  'P0020', null, 'staff cannot deactivate coupons');
set local request.jwt.claims to '{"sub":"c0000000-0000-0000-0000-000000000002","role":"authenticated"}';
select throws_ok($$select public.set_coupon_active('c1000000-0000-4000-8000-0000000000ff', false)$$,
  'P0002', null, 'deactivating an unknown coupon is P0002');
select throws_ok($$select public.set_coupon_active('c1000000-0000-4000-8000-000000000031', null)$$,
  'P0005', null, 'set_coupon_active needs true or false');

reset role;
set local request.jwt.claims to '';
select is((select array_agg(a.action order by a.id)
             from public.audit_log a
             join public.coupons c on c.id = a.entity_id
            where a.entity = 'coupon'
              and c.property_id = 'c1000000-0000-4000-8000-000000000001'
              and c.code = 'SAVE15'),
  array['create','update','deactivate','activate'], 'every change to a coupon is audited');
select is((select count(*)::int from public.audit_log
            where entity = 'coupon'
              and property_id = 'c1000000-0000-4000-8000-000000000001'
              and actor_id is null),
  0, 'every coupon audit row names who made the change');

-- === Task 3: listing, guest lookup, suspended and archived resorts ===========

-- One coupon in each remaining state, written straight into the table.
-- (Still superuser with empty claims from the end of Task 2's section.)
insert into public.coupons (property_id, code, kind, value, valid_to) values
  ('c1000000-0000-4000-8000-000000000001', 'EXPIRED1', 'fixed', 100, now() - interval '1 day');
insert into public.coupons (property_id, code, kind, value, valid_from) values
  ('c1000000-0000-4000-8000-000000000001', 'LATER1', 'fixed', 100, now() + interval '5 days');
insert into public.coupons (property_id, code, kind, value, max_redemptions, redeemed_count) values
  ('c1000000-0000-4000-8000-000000000001', 'USEDUP', 'fixed', 100, 1, 1);
insert into public.coupons (property_id, code, kind, value, is_active) values
  ('c1000000-0000-4000-8000-000000000001', 'OFF1', 'fixed', 100, false);

set local role authenticated;
set local request.jwt.claims to '{"sub":"c0000000-0000-0000-0000-000000000002","role":"authenticated"}';
select is((select count(*)::int from public.list_coupons('c1000000-0000-4000-8000-000000000001')),
  10, 'an admin lists every coupon of the resort, inactive ones too');
select is((select array_agg(code || ':' || status order by code)
             from public.list_coupons('c1000000-0000-4000-8000-000000000001')
            where code in ('EXPIRED1','LATER1','OFF1','SAVE15','USEDUP')),
  array['EXPIRED1:expired','LATER1:scheduled','OFF1:inactive','SAVE15:active','USEDUP:used_up'],
  'each coupon''s status follows the rules booking applies');
select is((select valid_from || '|' || valid_until || '|' || redeemed_count || '|' ||
                  customer_email || '|' || customer_name
             from public.list_coupons('c1000000-0000-4000-8000-000000000001')
            where code = 'SUMMER'),
  '2026-10-01|2026-10-31|0|Gita.Guest@Example.com|Gita Guest',
  'dates come back as the days picked, with the guest''s email and name');
select is((select redeemed_count || '/' || max_redemptions
             from public.list_coupons('c1000000-0000-4000-8000-000000000001')
            where code = 'OLD5'),
  '3/3', 'the usage count comes back with the limit');
select is((select code from public.list_coupons('c1000000-0000-4000-8000-000000000001') offset 9),
  'OFF1', 'inactive coupons are listed last');

set local request.jwt.claims to '{"sub":"c0000000-0000-0000-0000-000000000001","role":"authenticated"}';
select is((select count(*)::int from public.list_coupons('c1000000-0000-4000-8000-000000000001')),
  10, 'the owner lists them too');
set local request.jwt.claims to '{"sub":"c0000000-0000-0000-0000-000000000003","role":"authenticated"}';
select throws_ok($$select * from public.list_coupons('c1000000-0000-4000-8000-000000000001')$$,
  'P0020', null, 'staff cannot list coupons');
set local request.jwt.claims to '{"sub":"c0000000-0000-0000-0000-000000000004","role":"authenticated"}';
select throws_ok($$select * from public.list_coupons('c1000000-0000-4000-8000-000000000001')$$,
  'P0020', null, 'an accountant cannot list coupons');
set local request.jwt.claims to '{"sub":"c0000000-0000-0000-0000-00000000000a","role":"authenticated"}';
select throws_ok($$select * from public.list_coupons('c1000000-0000-4000-8000-000000000001')$$,
  'P0020', null, 'the platform admin cannot list a resort''s coupons');

set local request.jwt.claims to '{"sub":"c0000000-0000-0000-0000-000000000005","role":"authenticated"}';
select is((select array_agg(code) from public.list_coupons('c1000000-0000-4000-8000-000000000002')),
  array['SAVE10'], 'another resort lists only its own coupons');
select throws_ok($$select * from public.list_coupons('c1000000-0000-4000-8000-000000000001')$$,
  'P0020', null, 'another resort''s owner cannot list this resort''s coupons');
select is((select count(*)::int
             from public.find_resort_guest('c1000000-0000-4000-8000-000000000002', 'gita.guest@example.com')),
  0, 'a guest who never booked at S is not found there');
select is((select count(*)::int
             from public.find_resort_guest('c1000000-0000-4000-8000-000000000002', 'cp-olu@example.com')),
  1, 'S finds its own guest');

set local request.jwt.claims to '{"sub":"c0000000-0000-0000-0000-000000000002","role":"authenticated"}';
select is((select user_id || '|' || email || '|' || full_name
             from public.find_resort_guest('c1000000-0000-4000-8000-000000000001', '  GITA.guest@example.COM ')),
  'c0000000-0000-0000-0000-000000000006|Gita.Guest@Example.com|Gita Guest',
  'finds a guest who booked here, whatever the case and spacing');
select is((select count(*)::int
             from public.find_resort_guest('c1000000-0000-4000-8000-000000000001', 'cp-olu@example.com')),
  0, 'a guest of another resort is not found');
select is((select count(*)::int
             from public.find_resort_guest('c1000000-0000-4000-8000-000000000001', 'cp-hana@example.com')),
  0, 'a guest with only a hold is not found');
select is((select count(*)::int
             from public.find_resort_guest('c1000000-0000-4000-8000-000000000001', 'cp-kiran@example.com')),
  0, 'a guest whose only booking was cancelled is not found');
select is((select count(*)::int
             from public.find_resort_guest('c1000000-0000-4000-8000-000000000001', 'nobody@example.com')),
  0, 'an unknown email finds nobody');
select is((select count(*)::int
             from public.find_resort_guest('c1000000-0000-4000-8000-000000000001', 'cp-r-staff@example.com')),
  0, 'a team member who never booked is not found');
set local request.jwt.claims to '{"sub":"c0000000-0000-0000-0000-000000000003","role":"authenticated"}';
select throws_ok($$select * from public.find_resort_guest('c1000000-0000-4000-8000-000000000001', 'cp-olu@example.com')$$,
  'P0020', null, 'staff cannot look up guests');

-- Suspended: reads work, writes P0022. `reset role` keeps the claims;
-- clear them so the status change runs with no authenticated caller.
reset role;
set local request.jwt.claims to '';
update public.properties set status = 'suspended'
 where id = 'c1000000-0000-4000-8000-000000000001';
set local role authenticated;
set local request.jwt.claims to '{"sub":"c0000000-0000-0000-0000-000000000002","role":"authenticated"}';
select is((select count(*)::int from public.list_coupons('c1000000-0000-4000-8000-000000000001')),
  10, 'a suspended resort''s admin still lists coupons');
select is((select count(*)::int
             from public.find_resort_guest('c1000000-0000-4000-8000-000000000001', 'gita.guest@example.com')),
  1, 'and still looks up guests');
select throws_ok($$select public.create_coupon('c1000000-0000-4000-8000-000000000001', 'PAUSED', 'fixed', 100)$$,
  'P0022', null, 'no new coupons at a suspended resort');
select throws_ok($$select public.update_coupon('c1000000-0000-4000-8000-000000000031', 'OLD5', 'fixed', 500,
    null, null, null, 3)$$,
  'P0022', null, 'no edits at a suspended resort');
select throws_ok($$select public.set_coupon_active('c1000000-0000-4000-8000-000000000031', false)$$,
  'P0022', null, 'no deactivating at a suspended resort');

-- Archived: closed.
reset role;
set local request.jwt.claims to '';
update public.properties set status = 'archived'
 where id = 'c1000000-0000-4000-8000-000000000001';
set local role authenticated;
set local request.jwt.claims to '{"sub":"c0000000-0000-0000-0000-000000000002","role":"authenticated"}';
select throws_ok($$select * from public.list_coupons('c1000000-0000-4000-8000-000000000001')$$,
  'P0020', null, 'an archived resort''s coupons are closed to its admin');
select throws_ok($$select * from public.find_resort_guest('c1000000-0000-4000-8000-000000000001', 'gita.guest@example.com')$$,
  'P0020', null, 'and so is its guest lookup');
reset role;
set local request.jwt.claims to '';

select * from finish();
rollback;
