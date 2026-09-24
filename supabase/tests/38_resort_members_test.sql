-- Resort member management (list/add/set role/remove) and the platform
-- admin's functions (platform_resorts, set_resort_status, create_resort),
-- added in 0045_resort_functions.sql. They replace list_profiles() and
-- set_user_role() from 0019_user_admin.sql; the guarantees that file's
-- test (15_user_admin_test.sql) proved -- email joined from auth.users,
-- role changes audited, same-role no-op, last-owner guard safe under a
-- genuine two-connection race, anon unable to call -- are proved here for
-- the resort-scoped replacements.
begin;
select plan(54);

insert into auth.users (id, email) values
  ('d0000000-0000-0000-0000-000000000001','owner1@example.com'),
  ('d0000000-0000-0000-0000-000000000002','owner2@example.com'),
  ('d0000000-0000-0000-0000-000000000003','newhire@example.com'),
  ('d0000000-0000-0000-0000-000000000004','platform@example.com');
insert into public.properties (id, name, slug) values
  ('dddddddd-0000-4000-8000-000000000001','Resort D','resort-d');
insert into public.resort_members (property_id, user_id, role) values
  ('dddddddd-0000-4000-8000-000000000001','d0000000-0000-0000-0000-000000000001','owner');
update public.profiles set role = 'platform_admin'
  where id = 'd0000000-0000-0000-0000-000000000004';

-- Further fixtures for the sections after the brief's eleven assertions:
-- Resort F (owner1 owns it too, plus an admin and a staff member), a guest,
-- and Resort D bookings for platform_resorts' counts and sums.
insert into auth.users (id, email) values
  ('d0000000-0000-0000-0000-000000000005','fadmin@example.com'),
  ('d0000000-0000-0000-0000-000000000006','fstaff@example.com'),
  ('d0000000-0000-0000-0000-000000000007','guest@example.com');
update public.profiles set full_name = 'Fay Admin'
  where id = 'd0000000-0000-0000-0000-000000000005';
insert into public.properties (id, name, slug) values
  ('ffffffff-0000-4000-8000-000000000001','Resort F','resort-f');
insert into public.resort_members (property_id, user_id, role) values
  ('ffffffff-0000-4000-8000-000000000001','d0000000-0000-0000-0000-000000000001','owner'),
  ('ffffffff-0000-4000-8000-000000000001','d0000000-0000-0000-0000-000000000005','admin'),
  ('ffffffff-0000-4000-8000-000000000001','d0000000-0000-0000-0000-000000000006','staff');

insert into public.units (id, property_id, name, capacity_base, capacity_max) values
  ('dddddddd-0000-4000-8000-000000000011','dddddddd-0000-4000-8000-000000000001','UD',2,4);
-- Counted: confirmed today (1000) and 100 days ago (500). Not counted: a
-- cancellation today, and a booking older than 365 days.
insert into public.reservations (unit_id, period, kind, status, customer_id, guests, quote, created_at) values
  ('dddddddd-0000-4000-8000-000000000011',
   tstzrange('2027-03-01 14:00+05:30','2027-03-02 11:00+05:30','[)'),
   'booking','confirmed','d0000000-0000-0000-0000-000000000007',2,'{"total":1000}', now()),
  ('dddddddd-0000-4000-8000-000000000011',
   tstzrange('2027-03-05 14:00+05:30','2027-03-06 11:00+05:30','[)'),
   'booking','confirmed','d0000000-0000-0000-0000-000000000007',2,'{"total":500}', now() - interval '100 days'),
  ('dddddddd-0000-4000-8000-000000000011',
   tstzrange('2027-03-10 14:00+05:30','2027-03-11 11:00+05:30','[)'),
   'booking','cancelled','d0000000-0000-0000-0000-000000000007',2,'{"total":700}', now()),
  ('dddddddd-0000-4000-8000-000000000011',
   tstzrange('2027-03-15 14:00+05:30','2027-03-16 11:00+05:30','[)'),
   'booking','confirmed','d0000000-0000-0000-0000-000000000007',2,'{"total":300}', now() - interval '400 days');

set local role authenticated;
set local request.jwt.claims to '{"sub":"d0000000-0000-0000-0000-000000000001","role":"authenticated"}';

select lives_ok($$select public.add_resort_member('dddddddd-0000-4000-8000-000000000001','newhire@example.com','staff')$$,
  'owner adds an existing account as staff');
select throws_ok($$select public.add_resort_member('dddddddd-0000-4000-8000-000000000001','nobody@example.com','staff')$$,
  'P0002', null, 'unknown email is not found');
select is((select count(*)::int from public.list_resort_members('dddddddd-0000-4000-8000-000000000001')), 2,
  'roster lists both members');
select throws_ok($$select public.set_member_role('dddddddd-0000-4000-8000-000000000001','d0000000-0000-0000-0000-000000000001','admin')$$,
  'P0023', null, 'sole owner cannot demote themself');
select throws_ok($$select public.remove_resort_member('dddddddd-0000-4000-8000-000000000001','d0000000-0000-0000-0000-000000000001')$$,
  'P0023', null, 'sole owner cannot remove themself');

set local request.jwt.claims to '{"sub":"d0000000-0000-0000-0000-000000000003","role":"authenticated"}';
select throws_ok($$select public.add_resort_member('dddddddd-0000-4000-8000-000000000001','owner2@example.com','owner')$$,
  'P0020', null, 'staff cannot add members');
select throws_ok($$select * from public.platform_resorts()$$,
  'P0008', null, 'staff cannot call platform functions');

set local request.jwt.claims to '{"sub":"d0000000-0000-0000-0000-000000000004","role":"authenticated"}';
select ok((select count(*) from public.platform_resorts() where property_id = 'dddddddd-0000-4000-8000-000000000001') = 1,
  'platform admin sees resort summary');
select lives_ok($$select public.set_resort_status('dddddddd-0000-4000-8000-000000000001','suspended')$$,
  'platform admin suspends a resort');
select isnt(public.create_resort('Resort E','owner2@example.com'), null,
  'platform admin creates a resort for an existing account');
select throws_ok($$select * from public.list_resort_members('dddddddd-0000-4000-8000-000000000001')$$,
  'P0020', null, 'platform admin cannot read a resort roster');

-- === platform_resorts: summaries only =======================================

select is((select owner_emails from public.platform_resorts()
            where property_id = 'dddddddd-0000-4000-8000-000000000001'),
  array['owner1@example.com'],
  'platform_resorts lists the owner emails');
select is((select array[bookings_30d, revenue_30d, bookings_365d, revenue_365d]::numeric[]
             from public.platform_resorts()
            where property_id = 'dddddddd-0000-4000-8000-000000000001'),
  array[1, 1000, 2, 1500]::numeric[],
  'platform_resorts counts and sums confirmed bookings made in the last 30 and 365 days');
select is(pg_get_function_result('public.platform_resorts()'::regprocedure),
  'TABLE(property_id uuid, name text, status text, owner_emails text[], created_at timestamp with time zone, '
  'bookings_30d integer, revenue_30d numeric, bookings_365d integer, revenue_365d numeric)',
  'platform_resorts returns summary columns only -- no guest data');
select is((select status from public.platform_resorts()
            where property_id = 'dddddddd-0000-4000-8000-000000000001'),
  'suspended', 'the suspension is visible in the summary');

-- === set_resort_status / create_resort: input errors ========================

select throws_ok($$select public.set_resort_status('dddddddd-0000-4000-8000-000000000001','closed')$$,
  'P0005', null, 'an unknown status is rejected');
select throws_ok($$select public.set_resort_status('00000000-0000-4000-8000-000000000000','active')$$,
  'P0002', null, 'set_resort_status on an unknown resort is not found');
select throws_ok($$select public.create_resort('Resort X','nobody@example.com')$$,
  'P0002', null, 'create_resort for an unknown account is not found');
select lives_ok($$select public.create_resort('Resort D','owner2@example.com')$$,
  'create_resort with a name whose slug is taken still succeeds');

-- `reset role` keeps the JWT claims; clear them so these checks run with no
-- authenticated caller.
reset role;
set local request.jwt.claims to '';

select is((select count(*)::int from public.audit_log
            where entity = 'property'
              and entity_id = 'dddddddd-0000-4000-8000-000000000001'
              and property_id = 'dddddddd-0000-4000-8000-000000000001'
              and action = 'status:active->suspended'),
  1, 'set_resort_status wrote an audit_log row for that resort');
select is((select array_agg(u.email || ':' || m.role || ':' || p.status)
             from public.properties p
             join public.resort_members m on m.property_id = p.id
             join auth.users u on u.id = m.user_id
            where p.slug = 'resort-e'),
  array['owner2@example.com:owner:active'],
  'create_resort made an active resort, slug from the name, with the account as its only owner');
select is((select count(*)::int from public.properties p
             join public.resort_members m on m.property_id = p.id
            where p.slug = 'resort-d-2' and p.name = 'Resort D'
              and m.user_id = 'd0000000-0000-0000-0000-000000000002' and m.role = 'owner'),
  1, 'a taken slug gets a numeric suffix');

-- === Owners at a suspended resort; non-platform callers =====================

set local role authenticated;
set local request.jwt.claims to '{"sub":"d0000000-0000-0000-0000-000000000001","role":"authenticated"}';

select throws_ok($$select public.add_resort_member('dddddddd-0000-4000-8000-000000000001','owner2@example.com','staff')$$,
  'P0022', null, 'owner cannot change members of a suspended resort');
select is((select count(*)::int from public.list_resort_members('dddddddd-0000-4000-8000-000000000001')), 2,
  'owner can still read the roster of a suspended resort');
select throws_ok($$select public.set_resort_status('dddddddd-0000-4000-8000-000000000001','active')$$,
  'P0008', null, 'owner cannot change resort status');
select throws_ok($$select public.create_resort('Resort Y','owner1@example.com')$$,
  'P0008', null, 'owner cannot create resorts');

-- === Resort F: roster, roles, removal ======================================

select is((select email || '|' || full_name
             from public.list_resort_members('ffffffff-0000-4000-8000-000000000001')
            where user_id = 'd0000000-0000-0000-0000-000000000005'),
  'fadmin@example.com|Fay Admin', 'roster joins email from auth.users and name from profiles');
select throws_ok($$select public.add_resort_member('ffffffff-0000-4000-8000-000000000001','fstaff@example.com','admin')$$,
  'P0005', null, 'adding an existing member is rejected (use set_member_role)');
select throws_ok($$select public.set_member_role('ffffffff-0000-4000-8000-000000000001','d0000000-0000-0000-0000-000000000006',null)$$,
  'P0005', null, 'role is required');
select throws_ok($$select public.set_member_role('ffffffff-0000-4000-8000-000000000001','d0000000-0000-0000-0000-000000000003','admin')$$,
  'P0002', null, 'set_member_role on a non-member is not found');
select throws_ok($$select public.remove_resort_member('ffffffff-0000-4000-8000-000000000001','d0000000-0000-0000-0000-000000000003')$$,
  'P0002', null, 'remove_resort_member on a non-member is not found');
select lives_ok($$select public.set_member_role('ffffffff-0000-4000-8000-000000000001','d0000000-0000-0000-0000-000000000006','admin')$$,
  'owner promotes staff to admin');
select lives_ok($$select public.set_member_role('ffffffff-0000-4000-8000-000000000001','d0000000-0000-0000-0000-000000000006','admin')$$,
  'setting a role to its current value succeeds');

set local request.jwt.claims to '{"sub":"d0000000-0000-0000-0000-000000000005","role":"authenticated"}';
select is((select count(*)::int from public.list_resort_members('ffffffff-0000-4000-8000-000000000001')), 3,
  'admin can read the roster');
select throws_ok($$select public.add_resort_member('ffffffff-0000-4000-8000-000000000001','newhire@example.com','staff')$$,
  'P0020', null, 'admin cannot add members');
select throws_ok($$select public.set_member_role('ffffffff-0000-4000-8000-000000000001','d0000000-0000-0000-0000-000000000006','staff')$$,
  'P0020', null, 'admin cannot change roles');
select throws_ok($$select public.remove_resort_member('ffffffff-0000-4000-8000-000000000001','d0000000-0000-0000-0000-000000000006')$$,
  'P0020', null, 'admin cannot remove members');

set local request.jwt.claims to '{"sub":"d0000000-0000-0000-0000-000000000003","role":"authenticated"}';
select throws_ok($$select * from public.list_resort_members('dddddddd-0000-4000-8000-000000000001')$$,
  'P0020', null, 'staff cannot read the roster');

set local request.jwt.claims to '{"sub":"d0000000-0000-0000-0000-000000000001","role":"authenticated"}';
select lives_ok($$select public.set_member_role('ffffffff-0000-4000-8000-000000000001','d0000000-0000-0000-0000-000000000006','owner')$$,
  'owner makes a second owner');
select lives_ok($$select public.set_member_role('ffffffff-0000-4000-8000-000000000001','d0000000-0000-0000-0000-000000000001','admin')$$,
  'with two owners, one can demote themself');

set local request.jwt.claims to '{"sub":"d0000000-0000-0000-0000-000000000006","role":"authenticated"}';
select lives_ok($$select public.remove_resort_member('ffffffff-0000-4000-8000-000000000001','d0000000-0000-0000-0000-000000000001')$$,
  'the new owner removes the former owner');

reset role;
set local request.jwt.claims to '';

select is((select array_agg(u.email || ':' || m.role order by u.email)
             from public.resort_members m join auth.users u on u.id = m.user_id
            where m.property_id = 'ffffffff-0000-4000-8000-000000000001'),
  array['fadmin@example.com:admin','fstaff@example.com:owner'],
  'Resort F roster after the changes');
select is((select array_agg(action order by id) from public.audit_log
            where entity = 'resort_member'
              and property_id = 'ffffffff-0000-4000-8000-000000000001'),
  array['role:staff->admin','role:admin->owner','role:owner->admin','remove:admin'],
  'each member change wrote one audit_log row at that resort; the no-op wrote none');
select is((select array_agg(action order by id) from public.audit_log
            where entity = 'resort_member'
              and property_id = 'dddddddd-0000-4000-8000-000000000001'),
  array['add:staff'], 'adding a member is audited too');

-- === Last-owner guard under a genuine two-connection race ===================
--
-- Two owners each demoting (or removing) themselves at the same instant
-- must not both succeed. Same dblink technique as the race in
-- 11_coupons_test.sql and the former 15_user_admin_test.sql: both calls are
-- sent before either result is awaited, so they are in flight at the same
-- time. The fixture resort and its two owners must be committed for the
-- dblink sessions to see them, so they are created and torn down via
-- dblink, independent of this file's rollback. They use their own ids,
-- emails and slug so no uncommitted row of this transaction can block them.
set local role postgres;
create extension if not exists dblink;

-- Runs one race: owner 1 and owner 2 of a fresh committed resort each call
-- `<p_fn>(resort, own id[, 'admin'])`. Returns who succeeded, the losers'
-- sqlstates, and the resort's owner count right after.
create function pg_temp.owner_race(p_fn text)
returns table(a_ok boolean, b_ok boolean, a_err text, b_err text, owners int)
language plpgsql as $f$
declare
  v_conn text := format(
    'host=%s port=%s dbname=postgres user=postgres password=postgres sslmode=disable',
    host(inet_server_addr()), inet_server_port());
  v_extra text := case when p_fn = 'set_member_role' then ', ''admin''' else '' end;
  v_row record;
begin
  a_ok := false;
  b_ok := false;

  perform dblink_exec(v_conn, $F$
    insert into auth.users (id, email) values
      ('e0000000-0000-0000-0000-000000000001','race38-1@example.com'),
      ('e0000000-0000-0000-0000-000000000002','race38-2@example.com')$F$);
  perform dblink_exec(v_conn, $F$
    insert into public.properties (id, name, slug) values
      ('eeeeeeee-0000-4000-8000-000000000001','Race Resort','race-38')$F$);
  perform dblink_exec(v_conn, $F$
    insert into public.resort_members (property_id, user_id, role) values
      ('eeeeeeee-0000-4000-8000-000000000001','e0000000-0000-0000-0000-000000000001','owner'),
      ('eeeeeeee-0000-4000-8000-000000000001','e0000000-0000-0000-0000-000000000002','owner')$F$);

  perform dblink_connect('race_a', v_conn);
  perform dblink_connect('race_b', v_conn);
  perform dblink_exec('race_a', 'set role authenticated');
  perform dblink_exec('race_a', $Q$set request.jwt.claims to
    '{"sub":"e0000000-0000-0000-0000-000000000001","role":"authenticated"}'$Q$);
  perform dblink_exec('race_b', 'set role authenticated');
  perform dblink_exec('race_b', $Q$set request.jwt.claims to
    '{"sub":"e0000000-0000-0000-0000-000000000002","role":"authenticated"}'$Q$);

  -- The void call is wrapped so dblink_get_result has a column to parse.
  perform dblink_send_query('race_a', format(
    $Q$select true as ok from (select public.%s('eeeeeeee-0000-4000-8000-000000000001',
       'e0000000-0000-0000-0000-000000000001'%s)) as _wrap$Q$, p_fn, v_extra));
  perform dblink_send_query('race_b', format(
    $Q$select true as ok from (select public.%s('eeeeeeee-0000-4000-8000-000000000001',
       'e0000000-0000-0000-0000-000000000002'%s)) as _wrap$Q$, p_fn, v_extra));

  begin
    select * into v_row from dblink_get_result('race_a') as t(ok boolean);
    a_ok := true;
  exception when others then
    a_err := sqlstate;
  end;
  begin perform dblink_get_result('race_a'); exception when others then null; end;

  begin
    select * into v_row from dblink_get_result('race_b') as t(ok boolean);
    b_ok := true;
  exception when others then
    b_err := sqlstate;
  end;
  begin perform dblink_get_result('race_b'); exception when others then null; end;

  perform dblink_disconnect('race_a');
  perform dblink_disconnect('race_b');

  select n into owners from dblink(v_conn, $Q$
    select count(*)::int from public.resort_members
     where property_id = 'eeeeeeee-0000-4000-8000-000000000001' and role = 'owner'$Q$)
    as t(n int);

  perform dblink_exec(v_conn, $F$
    delete from public.audit_log where property_id = 'eeeeeeee-0000-4000-8000-000000000001'$F$);
  perform dblink_exec(v_conn, $F$
    delete from public.properties where id = 'eeeeeeee-0000-4000-8000-000000000001'$F$);
  perform dblink_exec(v_conn, $F$
    delete from auth.users where id in
      ('e0000000-0000-0000-0000-000000000001','e0000000-0000-0000-0000-000000000002')$F$);

  return next;
end;
$f$;

create temp table race_results as
  select 'set_member_role' as fn, * from pg_temp.owner_race('set_member_role')
  union all
  select 'remove_resort_member', * from pg_temp.owner_race('remove_resort_member');

select ok((select a_ok <> b_ok from race_results where fn = 'set_member_role'),
  'concurrent self-demotions by two owners: exactly one succeeds');
select is((select case when a_ok then b_err else a_err end from race_results where fn = 'set_member_role'),
  'P0023', 'the losing demotion gets P0023, not a deadlock or other error');
select is((select owners from race_results where fn = 'set_member_role'),
  1, 'one owner remains after the demotion race');
select ok((select a_ok <> b_ok from race_results where fn = 'remove_resort_member'),
  'concurrent self-removals by two owners: exactly one succeeds');
select is((select case when a_ok then b_err else a_err end from race_results where fn = 'remove_resort_member'),
  'P0023', 'the losing removal gets P0023, not a deadlock or other error');
select is((select owners from race_results where fn = 'remove_resort_member'),
  1, 'one owner remains after the removal race');

reset role;

-- === Grants; the functions these replace are gone ===========================

select is((select array_agg(f::text order by f::text)
             from unnest(array[
               'public.list_resort_members(uuid)',
               'public.add_resort_member(uuid, text, public.resort_role)',
               'public.set_member_role(uuid, uuid, public.resort_role)',
               'public.remove_resort_member(uuid, uuid)',
               'public.platform_resorts()',
               'public.set_resort_status(uuid, text)',
               'public.create_resort(text, text)']::regprocedure[]) f
            where has_function_privilege('anon', f, 'execute')),
  null, 'anon can execute none of the new functions');
select is((select count(*)::int
             from unnest(array[
               'public.list_resort_members(uuid)',
               'public.add_resort_member(uuid, text, public.resort_role)',
               'public.set_member_role(uuid, uuid, public.resort_role)',
               'public.remove_resort_member(uuid, uuid)',
               'public.platform_resorts()',
               'public.set_resort_status(uuid, text)',
               'public.create_resort(text, text)']::regprocedure[]) f
            where has_function_privilege('authenticated', f, 'execute')),
  7, 'authenticated can execute all seven');
select hasnt_function('public', 'list_profiles', 'list_profiles() is dropped');
select hasnt_function('public', 'set_user_role', 'set_user_role() is dropped');

select * from finish();
rollback;
