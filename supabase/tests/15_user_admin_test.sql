-- public.list_profiles() and public.set_user_role(), added in
-- 0019_user_admin.sql to back the admin user-management screen. See that
-- migration's header for why there is no "create user" function here.
--
-- Fixture roles used throughout, all seeded by supabase/seed.sql (loaded on
-- every `db reset`, so present before this transaction even starts):
--   10000000-0000-0000-0000-000000000001  super@pasala.test    super_admin
--   10000000-0000-0000-0000-000000000002  admin@pasala.test    admin
-- This file's own fixtures (a fresh customer to promote, and a second
-- super_admin so "demote one of two" has something to prove) are inserted
-- below with a distinct '91.../92...' id prefix so they can't collide with
-- the seed data or with any other test file's fixtures.

begin;
select plan(24);

select has_function('public','list_profiles','list_profiles() exists');
select has_function('public','set_user_role','set_user_role() exists');

-- A fresh customer, signed up like anyone else -- the only path this app
-- has for a new account to exist at all (see the migration header).
insert into auth.users (id, email, raw_user_meta_data)
values ('91111111-1111-1111-1111-111111111111', 'newstaff@example.com',
        '{"full_name":"New Staff"}'::jsonb);

-- === list_profiles: admin-gated =============================================

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"91111111-1111-1111-1111-111111111111","role":"authenticated"}';

select throws_ok(
  $$select * from public.list_profiles()$$,
  'P0008', null, 'a customer calling list_profiles gets P0008');

set local request.jwt.claims to
  '{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}';

select lives_ok(
  $$select * from public.list_profiles()$$,
  'an admin can call list_profiles');

select is(
  (select count(*)::int from public.list_profiles()
    where id = '10000000-0000-0000-0000-000000000001'),
  1,
  'admin sees the super admin row via list_profiles');

select is(
  (select email from public.list_profiles()
    where id = '10000000-0000-0000-0000-000000000001'),
  'super@pasala.test',
  'list_profiles joins the email in from auth.users');

-- === set_user_role: super-admin-only, with the last-super-admin guard =====

-- A plain admin is refused, even for an ordinary promotion.
select throws_ok(
  $$select public.set_user_role(
      '91111111-1111-1111-1111-111111111111','staff')$$,
  'P0008', null, 'a plain admin calling set_user_role gets P0008');

set local request.jwt.claims to
  '{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}';

select lives_ok(
  $$select public.set_user_role(
      '91111111-1111-1111-1111-111111111111','staff')$$,
  'a super admin can promote a customer to staff');

reset role;

select is(
  (select role from public.profiles
    where id = '91111111-1111-1111-1111-111111111111'),
  'staff'::public.user_role,
  'the promotion is visible directly on profiles');

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}';

select is(
  (select role from public.list_profiles()
    where id = '91111111-1111-1111-1111-111111111111'),
  'staff'::public.user_role,
  'the promotion is visible via list_profiles too');

reset role;

select is(
  (select count(*)::int from public.audit_log
    where entity = 'profile'
      and entity_id = '91111111-1111-1111-1111-111111111111'
      and action = 'role:customer->staff'),
  1,
  'the role change wrote an audit_log row with the expected action string');

-- The seeded super@pasala.test is, at this point, the only super_admin in
-- the table -- demoting it (even by itself) must be refused.
set local role authenticated;
set local request.jwt.claims to
  '{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}';

select throws_ok(
  $$select public.set_user_role(
      '10000000-0000-0000-0000-000000000001','admin')$$,
  'P0014', null,
  'demoting the only super_admin raises P0014');

reset role;

select is(
  (select role from public.profiles
    where id = '10000000-0000-0000-0000-000000000001'),
  'super_admin'::public.user_role,
  'the sole super_admin''s row is unchanged after the refused demotion');

-- === set_user_role: the last-super-admin guard must be race-safe ===========
--
-- With exactly two super admins, each demoting the OTHER "at the same
-- instant" must not both succeed -- `for update` on just the row being
-- changed doesn't conflict with a concurrent demotion of a DIFFERENT
-- super_admin, so a naive "select count(*), then check" implementation
-- lets both concurrent calls read count = 2, both pass, and both commit,
-- leaving zero super admins. Reproduced live against a throwaway revert of
-- the fix in 0019_user_admin.sql before writing this test: both calls
-- returned success and the final super_admin count was 0.
--
-- Same dblink technique as the coupon redemption race in
-- 11_coupons_test.sql: two genuine connections, both `set_user_role` calls
-- dispatched before either result is awaited, so they are genuinely in
-- flight at the database level at the same time, not just run one after
-- another. The race's own fixture -- TWO fresh super admins, not the
-- seeded super@pasala.test -- must be COMMITTED, not staged in this
-- file's outer transaction, or the two dblink sessions would not see it,
-- so it is created (and afterwards torn down) via dblink itself,
-- independent of this file's closing `rollback`.
--
-- Placed here -- before "with two super_admins, demoting one succeeds"
-- below -- deliberately: that test's `set_user_role` call SUCCEEDS, and a
-- successful call's `for update` lock on every super_admin row that
-- existed at the time (not just the one it actually changes) is held for
-- the rest of this file's still-open outer transaction, since only a
-- caught exception (like the P0014 one just above) releases its lock via
-- an implicit savepoint rollback. A race running after that point would
-- have its own lock attempts on the seeded super@pasala.test block
-- forever on this transaction's own prior work -- not a race at all, just
-- a hang. Two brand-new fixtures below sidestep needing that row at all.
--
-- The guard's own count is GLOBAL (`where role = 'super_admin'`, no id
-- filter -- see 0019_user_admin.sql), not scoped to whatever fixtures a
-- caller has in mind, and the seeded super@pasala.test is still
-- super_admin at this point in the file. Left alone, it sits alongside
-- the two race fixtures as a THIRD super_admin, so the guard's count is
-- always >= 3 no matter how the race interleaves -- comfortably above the
-- "<= 1" threshold in every case, meaning both concurrent demotions
-- succeed regardless of whether the locking fix is present, proving
-- nothing. (Verified live: this was tried first, and passed identically
-- against both the fixed migration and a reverted, deliberately-racy
-- one.) So the seed is temporarily neutralised -- demoted to 'admin' via
-- a direct dblink UPDATE, bypassing set_user_role entirely, exactly like
-- the fixture creation below -- for the span of the race, then restored
-- to super_admin immediately after the race's results (including the
-- super_admin count) are captured, before the two fixtures are deleted.
-- That restore runs unconditionally right after result capture, not
-- inside any exception handler, since neither dblink_get_result call
-- above can raise past its own local exception block.
set local role postgres;
create extension if not exists dblink;

do $$
declare
  v_conn text := format(
    'host=%s port=%s dbname=postgres user=postgres password=postgres sslmode=disable',
    host(inet_server_addr()), inet_server_port());
  v_a_ok  boolean := false;
  v_b_ok  boolean := false;
  v_a_err text;
  v_b_err text;
  -- dblink_get_result returns `setof record`, so a caller must give it a
  -- column list to parse a genuinely successful result against --
  -- `set_user_role` returns void, and void cannot appear in that column
  -- list (`as t(x void)` is itself a syntax error), so the dispatched
  -- query below wraps the void call in a FROM-subquery and projects a
  -- plain boolean instead, purely so this local variable has a type to
  -- receive. Found by running this block by hand: without the wrap, the
  -- winning side's dblink_get_result('race_a') raised a local 0A000
  -- ("function returning record called in context that cannot accept
  -- type record") on the SUCCESSFUL call -- caught by the `when others`
  -- below same as a real error would be, so both v_a_ok and v_b_ok came
  -- back false and neither v_..._err was ever 'P0014', even though the
  -- guard itself was already working correctly on the server side (the
  -- remote UPDATE had already committed by the time this local parse
  -- failed). That false negative would have shipped a race test that
  -- always reports "both failed" no matter what the migration does.
  v_row   record;
begin
  perform dblink_exec(v_conn, $F$
    update public.profiles set role = 'admin'
      where id = '10000000-0000-0000-0000-000000000001'$F$);

  perform dblink_exec(v_conn, $F$
    insert into auth.users (id, email) values
      ('93333333-3333-3333-3333-333333333331','racesuper1@example.com'),
      ('93333333-3333-3333-3333-333333333332','racesuper2@example.com')$F$);
  perform dblink_exec(v_conn, $F$
    update public.profiles set role = 'super_admin'
      where id in ('93333333-3333-3333-3333-333333333331',
                    '93333333-3333-3333-3333-333333333332')$F$);

  perform dblink_connect('race_a', v_conn);
  perform dblink_connect('race_b', v_conn);
  perform dblink_exec('race_a', 'set role authenticated');
  perform dblink_exec('race_a', $Q$set request.jwt.claims to
    '{"sub":"93333333-3333-3333-3333-333333333331","role":"authenticated"}'$Q$);
  perform dblink_exec('race_b', 'set role authenticated');
  perform dblink_exec('race_b', $Q$set request.jwt.claims to
    '{"sub":"93333333-3333-3333-3333-333333333332","role":"authenticated"}'$Q$);

  -- Both sent before either is awaited -- this is what makes them
  -- genuinely concurrent rather than sequential. Each super admin demotes
  -- itself, targeting the two DIFFERENT super admins that exist right now.
  perform dblink_send_query('race_a', $Q$
    select true as ok from (select public.set_user_role(
      '93333333-3333-3333-3333-333333333331','admin')) as _wrap$Q$);
  perform dblink_send_query('race_b', $Q$
    select true as ok from (select public.set_user_role(
      '93333333-3333-3333-3333-333333333332','admin')) as _wrap$Q$);

  begin
    select * into v_row from dblink_get_result('race_a') as t(ok boolean);
    v_a_ok := true;
  exception when others then
    v_a_err := sqlstate;
  end;
  begin perform dblink_get_result('race_a'); exception when others then null; end;

  begin
    select * into v_row from dblink_get_result('race_b') as t(ok boolean);
    v_b_ok := true;
  exception when others then
    v_b_err := sqlstate;
  end;
  begin perform dblink_get_result('race_b'); exception when others then null; end;

  perform dblink_disconnect('race_a');
  perform dblink_disconnect('race_b');

  perform set_config('app.race_a_ok', v_a_ok::text, false);
  perform set_config('app.race_b_ok', v_b_ok::text, false);
  perform set_config('app.race_a_err', coalesce(v_a_err, ''), false);
  perform set_config('app.race_b_err', coalesce(v_b_err, ''), false);
  -- Global, unfiltered count -- meaningful now that the seed was
  -- neutralised above, so these two fixtures are the only super_admins
  -- that exist anywhere while this is captured. This is the number the
  -- guard itself computes internally; asserting on it directly is what
  -- catches the "count is global, not fixture-scoped" bug an id-filtered
  -- count would silently paper over.
  perform set_config('app.race_super_admin_count',
    (select n::text from dblink(v_conn,
      $Q$select count(*) from public.profiles
         where role = 'super_admin'$Q$)
      as t(n int)), false);

  -- Restored unconditionally, before the fixtures are torn down, so every
  -- test after this one sees the same single-seeded-super_admin state it
  -- would have if this race test didn't exist.
  perform dblink_exec(v_conn, $F$
    update public.profiles set role = 'super_admin'
      where id = '10000000-0000-0000-0000-000000000001'$F$);

  -- Torn down via dblink, independent of this file's own rollback --
  -- both fixtures are throwaway, so no restoration is needed, just
  -- deletion (cascades to their profiles rows).
  perform dblink_exec(v_conn, $F$
    delete from auth.users where id in
      ('93333333-3333-3333-3333-333333333331',
       '93333333-3333-3333-3333-333333333332')$F$);
end $$;
reset role;

select ok(
  (current_setting('app.race_a_ok') = 'true') <> (current_setting('app.race_b_ok') = 'true'),
  'exactly one of the two concurrent self-demotions succeeded, not both '
  'and not neither');

select is(
  (case when current_setting('app.race_a_ok') = 'false'
        then current_setting('app.race_a_err')
        else current_setting('app.race_b_err') end),
  'P0014',
  'the losing concurrent demotion was rejected with P0014, not a '
  'different error (e.g. a raw deadlock)');

select is(
  current_setting('app.race_super_admin_count')::int,
  1,
  'exactly one super_admin exists anywhere immediately after the race -- '
  'never zero, which is the lockout this guard exists to prevent (the '
  'seed was neutralised for the span of the race, so this count reflects '
  'only the two race fixtures)');

select is(
  (select role from public.profiles
    where id = '10000000-0000-0000-0000-000000000001'),
  'super_admin'::public.user_role,
  'the seed, neutralised only for the span of the race, is restored to '
  'super_admin before any later test runs');

-- With a second super_admin in play, demoting one of the two succeeds.
insert into auth.users (id, email)
values ('92222222-2222-2222-2222-222222222222', 'secondsuper@example.com');
update public.profiles set role = 'super_admin'
  where id = '92222222-2222-2222-2222-222222222222';

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}';

select lives_ok(
  $$select public.set_user_role(
      '92222222-2222-2222-2222-222222222222','admin')$$,
  'with two super_admins, demoting one succeeds');

reset role;

select is(
  (select count(*)::int from public.profiles where role = 'super_admin'),
  1,
  'exactly one super_admin remains after that demotion');

-- Setting a role to its current value is a no-op that succeeds.
set local role authenticated;
set local request.jwt.claims to
  '{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}';

select lives_ok(
  $$select public.set_user_role(
      '91111111-1111-1111-1111-111111111111','staff')$$,
  'setting a role to its current value succeeds');

reset role;

select is(
  (select role from public.profiles
    where id = '91111111-1111-1111-1111-111111111111'),
  'staff'::public.user_role,
  'the no-op left the role unchanged');

select is(
  (select count(*)::int from public.audit_log
    where entity = 'profile'
      and entity_id = '91111111-1111-1111-1111-111111111111'
      and action = 'role:staff->staff'),
  0,
  'the no-op wrote no audit_log row');

-- === anon: neither function is even reachable ==============================

set local role anon;
set local request.jwt.claims to '{"role":"anon"}';

select throws_ok(
  $$select * from public.list_profiles()$$,
  '42501', null, 'anon cannot call list_profiles');

select throws_ok(
  $$select public.set_user_role(
      '91111111-1111-1111-1111-111111111111','staff')$$,
  '42501', null, 'anon cannot call set_user_role');

select * from finish();
rollback;
