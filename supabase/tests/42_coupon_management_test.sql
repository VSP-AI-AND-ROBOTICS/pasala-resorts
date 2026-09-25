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
select plan(17);

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

select * from finish();
rollback;
