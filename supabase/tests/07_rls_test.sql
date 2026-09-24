-- RLS matrix: every role (customer, staff, admin, accountant, super_admin,
-- anon) against every table (profiles, properties, units, slot_types,
-- rate_rules, reservations, payments, audit_log) plus the availability view.
--
-- Coverage already proven elsewhere is deliberately NOT repeated here:
--   01_profiles_test.sql  - role-escalation guard, admin/super_admin role-
--                            change authority, admin insert/delete on
--                            profiles, customer self-delete filtered by RLS.
--   02_properties_test.sql - anon can read active properties.
--   03_quote_test.sql      - anon can read rate_rules; anon cannot write
--                            rate_rules (throws 42501).
--   05_audit_test.sql      - a customer sees zero audit_log rows.
--   06_booking_flow_test.sql - admin block_dates happy path and its
--                            all-or-nothing guarantee; customer cannot
--                            cancel/block via the RPCs; release_expired_holds
--                            is not callable by a client.
-- This file's job is the coverage the brief and those files leave out:
-- accountant, super_admin, staff-against-write-surfaces, anon-against-every-
-- privileged table (including the grant-layer-only tables), and the
-- availability view's shape and reach.

begin;
select plan(34);

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111','cust1@example.com'),
  ('22222222-2222-2222-2222-222222222222','cust2@example.com'),
  ('33333333-3333-3333-3333-333333333333','staff@example.com'),
  ('44444444-4444-4444-4444-444444444444','admin@example.com'),
  ('55555555-5555-5555-5555-555555555555','acct@example.com');

update public.profiles set role = 'staff'
  where id = '33333333-3333-3333-3333-333333333333';
update public.profiles set role = 'admin'
  where id = '44444444-4444-4444-4444-444444444444';
update public.profiles set role = 'accountant'
  where id = '55555555-5555-5555-5555-555555555555';

insert into public.properties (id, name, slug)
values ('aaaaaaaa-0000-0000-0000-000000000001','P1','p1');
insert into public.units (id, property_id, name, capacity_base, capacity_max)
values ('bbbbbbbb-0000-0000-0000-000000000001',
        'aaaaaaaa-0000-0000-0000-000000000001','U1',4,6);
insert into public.reservations (id, unit_id, period, kind, status, customer_id, guests)
values ('cccccccc-0000-0000-0000-000000000001',
        'bbbbbbbb-0000-0000-0000-000000000001',
        tstzrange('2026-08-03 14:00+05:30','2026-08-04 11:00+05:30','[)'),
        'booking','confirmed','11111111-1111-1111-1111-111111111111',4);

insert into public.resort_members (property_id, user_id, role) values
  ('aaaaaaaa-0000-0000-0000-000000000001','33333333-3333-3333-3333-333333333333','staff'),
  ('aaaaaaaa-0000-0000-0000-000000000001','44444444-4444-4444-4444-444444444444','admin'),
  ('aaaaaaaa-0000-0000-0000-000000000001','55555555-5555-5555-5555-555555555555','accountant');

-- === customer: own data only, no write surface on units ===================

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';
select is((select count(*)::int from public.reservations), 1,
          'customer sees own reservation');

set local request.jwt.claims to
  '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}';
select is((select count(*)::int from public.reservations), 0,
          'customer cannot see another customer reservation');

select throws_ok(
  $$select public.cancel_booking(
      'cccccccc-0000-0000-0000-000000000001','nope')$$,
  'P0020', null, 'customer cannot cancel another customer booking');

select throws_ok(
  $$select public.block_dates('bbbbbbbb-0000-0000-0000-000000000001',
      array[daterange('2026-12-01','2026-12-03')], 'nope')$$,
  'P0020', null, 'customer cannot block dates');

select throws_ok(
  $$insert into public.units (property_id, name, capacity_base, capacity_max)
    values ('aaaaaaaa-0000-0000-0000-000000000001','X-cust',2,2)$$,
  '42501', null, 'customer cannot create units');

-- === staff: reads reservations, no write surface on properties/units/rates =

set local request.jwt.claims to
  '{"sub":"33333333-3333-3333-3333-333333333333","role":"authenticated"}';
-- staff is not the owner of cccccccc-...0001 (that's customer 1); seeing it
-- proves staff has org-wide read access, not just their own rows.
select is(
  (select count(*)::int from public.reservations
    where id = 'cccccccc-0000-0000-0000-000000000001'),
  1,
  'staff sees reservations');

select throws_ok(
  $$insert into public.properties (name, slug) values ('Staff Prop','staff-p')$$,
  '42501', null, 'staff cannot create properties');

select throws_ok(
  $$insert into public.units (property_id, name, capacity_base, capacity_max)
    values ('aaaaaaaa-0000-0000-0000-000000000001','X-staff',2,2)$$,
  '42501', null, 'staff cannot create units');

select throws_ok(
  $$insert into public.rate_rules (unit_id, kind, price, priority)
    values ('bbbbbbbb-0000-0000-0000-000000000001','base',1,0)$$,
  '42501', null, 'staff cannot create rate rules');

-- === fixtures for accountant / super_admin / payments coverage =============
-- Seeded as postgres (bypasses RLS) so the fixtures themselves aren't
-- testing anything; the assertions below are.

set local role postgres;

insert into auth.users (id, email)
values ('66666666-6666-6666-6666-666666666666','superadmin@example.com');
update public.profiles set role = 'super_admin'
  where id = '66666666-6666-6666-6666-666666666666';

insert into public.resort_members (property_id, user_id, role) values
  ('aaaaaaaa-0000-0000-0000-000000000001','66666666-6666-6666-6666-666666666666','owner');

insert into public.slot_types (id, property_id, code, start_time, end_time)
values ('77777777-0000-0000-0000-000000000001',
        'aaaaaaaa-0000-0000-0000-000000000001','day','09:00','18:00');

insert into public.reservations (id, unit_id, period, kind, status, customer_id, guests)
values ('cccccccc-0000-0000-0000-000000000002',
        'bbbbbbbb-0000-0000-0000-000000000001',
        tstzrange('2026-09-03 14:00+05:30','2026-09-04 11:00+05:30','[)'),
        'booking','confirmed','22222222-2222-2222-2222-222222222222',2);

insert into public.payments (reservation_id, amount, kind, status, gateway, gateway_ref)
values ('cccccccc-0000-0000-0000-000000000001',5000,'advance','succeeded','mock','rls_pay_1'),
       ('cccccccc-0000-0000-0000-000000000002',6000,'advance','succeeded','mock','rls_pay_2');

-- The availability view is public.reservations minus customer identity.
-- Prove that structurally, not just by observation: the column must not
-- exist, so no future migration can reintroduce it unnoticed.
select hasnt_column('public','availability','customer_id',
  'availability view exposes no customer_id');

-- === accountant: read-only on reservations and payments, no admin surface ==

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"55555555-5555-5555-5555-555555555555","role":"authenticated"}';

-- neither fixture reservation belongs to the accountant (owned by customers
-- 1 and 2); seeing both proves org-wide read, not visibility of own rows.
select is(
  (select count(*)::int from public.reservations
    where id in ('cccccccc-0000-0000-0000-000000000001',
                 'cccccccc-0000-0000-0000-000000000002')),
  2,
  'accountant sees all reservations');

select throws_ok(
  $$insert into public.reservations
      (unit_id, period, kind, status, customer_id, guests)
    values ('bbbbbbbb-0000-0000-0000-000000000001',
      tstzrange('2026-10-10 14:00+05:30','2026-10-11 11:00+05:30','[)'),
      'booking','hold','55555555-5555-5555-5555-555555555555',2)$$,
  '42501', null, 'accountant cannot create reservations directly');

select is((select count(*)::int from public.payments), 2,
          'accountant sees all payments');

select throws_ok(
  $$insert into public.payments
      (reservation_id, amount, kind, status, gateway, gateway_ref)
    values ('cccccccc-0000-0000-0000-000000000001',100,'advance','succeeded',
            'mock','acct_attempt')$$,
  '42501', null, 'accountant cannot create payments');

select throws_ok(
  $$insert into public.properties (name, slug) values ('Acct Prop','acct-p')$$,
  '42501', null, 'accountant cannot reach the properties admin surface');

-- an admin-only UPDATE that matches no policy is filtered, not an error
select lives_ok(
  $$update public.profiles set role = 'admin'
      where id = '11111111-1111-1111-1111-111111111111'$$,
  'accountant role-change attempt raises no error (RLS-filtered)');

set local role postgres;
select is(
  (select role from public.profiles
    where id = '11111111-1111-1111-1111-111111111111'),
  'customer'::public.user_role,
  'accountant role-change attempt changed no rows');

-- === super_admin: full access where admin has it ===========================

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"66666666-6666-6666-6666-666666666666","role":"authenticated"}';

-- same reasoning as the accountant assertion above: both fixtures belong to
-- other customers, so seeing both proves org-wide read for super_admin too.
select is(
  (select count(*)::int from public.reservations
    where id in ('cccccccc-0000-0000-0000-000000000001',
                 'cccccccc-0000-0000-0000-000000000002')),
  2,
  'super_admin sees all reservations');

-- Resorts are created through create_resort, never by a direct insert, so
-- the owner's direct write access is shown on a resort-owned table.
select lives_ok(
  $$insert into public.units (property_id, name, capacity_base, capacity_max)
    values ('aaaaaaaa-0000-0000-0000-000000000001','SA-unit',2,2)$$,
  'super_admin (resort owner) has the same direct write access as admin');

-- === C1: no direct profile deletes ==========================================
-- `profiles_admin_delete` once let a plain admin delete a super_admin's row
-- and re-insert it as a customer. 0044 drops every admin policy on profiles
-- (profiles are global; resort roles live in resort_members), so no direct
-- DELETE on profiles is permitted for anyone.

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"44444444-4444-4444-4444-444444444444","role":"authenticated"}';

select lives_ok(
  $$delete from public.profiles
      where id = '66666666-6666-6666-6666-666666666666'$$,
  'a plain admin''s DELETE of a super_admin profile raises no error '
  '(RLS filters it, same as any USING-clause mismatch)');

set local role postgres;
select is(
  (select count(*)::int from public.profiles
    where id = '66666666-6666-6666-6666-666666666666'),
  1,
  'C1: the super_admin profile survives a plain admin''s delete attempt');

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"66666666-6666-6666-6666-666666666666","role":"authenticated"}';

select lives_ok(
  $$delete from public.profiles
      where id = '44444444-4444-4444-4444-444444444444'$$,
  'a super_admin''s DELETE of another profile raises no error (RLS-filtered)');

set local role postgres;
select is(
  (select count(*)::int from public.profiles
    where id = '44444444-4444-4444-4444-444444444444'),
  1,
  'C1: a super_admin''s delete of another profile removed nothing');

-- === payments: a customer sees only their own ==============================

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

select is((select count(*)::int from public.payments), 1,
          'customer sees only their own payment');

select throws_ok(
  $$insert into public.payments
      (reservation_id, amount, kind, status, gateway, gateway_ref)
    values ('cccccccc-0000-0000-0000-000000000001',100,'advance','succeeded',
            'mock','cust_attempt')$$,
  '42501', null, 'customer cannot create a payment directly, even for their own reservation');

-- === anon: public read surface, nothing else ================================

set local role anon;
set local request.jwt.claims to '{"role":"anon"}';

select ok(
  (select count(*) from public.units
    where id = 'bbbbbbbb-0000-0000-0000-000000000001') = 1,
  'anon can read units');

select ok(
  (select count(*) from public.slot_types
    where id = '77777777-0000-0000-0000-000000000001') = 1,
  'anon can read slot types');

select throws_ok(
  $$insert into public.properties (name, slug) values ('Anon Prop','anon-p')$$,
  '42501', null, 'anon cannot create properties');

select throws_ok(
  $$insert into public.units (property_id, name, capacity_base, capacity_max)
    values ('aaaaaaaa-0000-0000-0000-000000000001','X-anon',2,2)$$,
  '42501', null, 'anon cannot create units');

-- These four tables grant nothing to anon at all (grant ... to authenticated
-- only), so the denial happens at the grant layer, before RLS is evaluated.
-- Per this project's own convention, that surfaces as 42501 from the query
-- itself, not as a filtered zero-row result -- so it is asserted with
-- throws_ok, not is(count, 0). (The brief's literal draft asserted
-- is(count,0) for reservations here; run against this schema it raises
-- "permission denied for table reservations" instead, which is this same
-- fact caught the way the task said it would be: a false expectation in a
-- test, not a policy hole. Fixed here, not by adding a grant -- anon has no
-- business reading these tables at all, and the availability view exists
-- precisely so it doesn't need to.)
select throws_ok(
  $$select count(*) from public.reservations$$,
  '42501', null, 'anon cannot read reservations');

select throws_ok(
  $$select count(*) from public.payments$$,
  '42501', null, 'anon cannot read payments');

select throws_ok(
  $$select count(*) from public.profiles$$,
  '42501', null, 'anon cannot read profiles');

select throws_ok(
  $$select count(*) from public.audit_log$$,
  '42501', null, 'anon cannot read audit_log');

-- availability has no id column (by design -- see hasnt_column check above);
-- scope by the fixture unit instead. Both fixture reservations sit on it, so
-- this still proves anon can see busy periods it doesn't own, not just that
-- the view exists.
select is(
  (select count(*)::int from public.availability
    where unit_id = 'bbbbbbbb-0000-0000-0000-000000000001'),
  2,
  'anon can read the availability view');

select * from finish();
rollback;
