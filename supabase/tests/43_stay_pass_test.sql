-- QR scanning at the front desk (P3), added in 0052_stay_pass.sql. See
-- docs/superpowers/specs/2026-09-25-p3-qr-scanning-at-the-front-desk-design.md.
--
-- One file, built up by the plan's tasks in order (contract, issue,
-- verify): each section relies on the fixtures and the `test.*` settings
-- the sections before it leave behind.
--
-- Fixtures: resort R (owner, admin, staff, accountant), resort S (one
-- staff member), guest Gita with five bookings at R, guest Hari with one
-- at S, and an outsider with no membership.
--   ...021 R Cottage 1  confirmed    tomorrow -> +3 days   (Gita)
--   ...022 R Cottage 2  checked_in   yesterday -> tomorrow (Gita)
--   ...023 R Cottage 1  cancelled    +10 -> +12 days       (Gita)
--   ...024 R Cottage 1  checked_out  -10 -> -8 days        (Gita)
--   ...025 R Cottage 2  confirmed    -5 -> -3 days, a no-show whose stay has ended (Gita)
--   ...026 S Villa      confirmed    tomorrow -> +3 days   (Hari)
begin;
select plan(68);

insert into auth.users (id, email) values
  ('f3000000-0000-0000-0000-000000000001','pass-r-owner@example.com'),
  ('f3000000-0000-0000-0000-000000000002','pass-r-admin@example.com'),
  ('f3000000-0000-0000-0000-000000000003','pass-r-staff@example.com'),
  ('f3000000-0000-0000-0000-000000000004','pass-r-accountant@example.com'),
  ('f3000000-0000-0000-0000-000000000005','pass-s-staff@example.com'),
  ('f3000000-0000-0000-0000-000000000006','pass-gita@example.com'),
  ('f3000000-0000-0000-0000-000000000007','pass-hari@example.com'),
  ('f3000000-0000-0000-0000-000000000008','pass-outsider@example.com');
update public.profiles set full_name = 'Gita Guest', phone = '9000000001'
  where id = 'f3000000-0000-0000-0000-000000000006';
update public.profiles set full_name = 'Hari Guest'
  where id = 'f3000000-0000-0000-0000-000000000007';

insert into public.properties (id, name, slug) values
  ('f3f3f3f3-0000-4000-8000-000000000001','Pass Resort R','pass-r'),
  ('f3f3f3f3-0000-4000-8000-000000000002','Pass Resort S','pass-s');

insert into public.resort_members (property_id, user_id, role) values
  ('f3f3f3f3-0000-4000-8000-000000000001','f3000000-0000-0000-0000-000000000001','owner'),
  ('f3f3f3f3-0000-4000-8000-000000000001','f3000000-0000-0000-0000-000000000002','admin'),
  ('f3f3f3f3-0000-4000-8000-000000000001','f3000000-0000-0000-0000-000000000003','staff'),
  ('f3f3f3f3-0000-4000-8000-000000000001','f3000000-0000-0000-0000-000000000004','accountant'),
  ('f3f3f3f3-0000-4000-8000-000000000002','f3000000-0000-0000-0000-000000000005','staff');

insert into public.units (id, property_id, name, capacity_base, capacity_max) values
  ('f3f3f3f3-0000-4000-8000-000000000011','f3f3f3f3-0000-4000-8000-000000000001','Cottage 1',2,4),
  ('f3f3f3f3-0000-4000-8000-000000000012','f3f3f3f3-0000-4000-8000-000000000001','Cottage 2',2,4),
  ('f3f3f3f3-0000-4000-8000-000000000013','f3f3f3f3-0000-4000-8000-000000000002','S Villa',2,4);

insert into public.reservations
  (id, unit_id, period, kind, status, customer_id, guests, checked_in_at, checked_out_at)
values
  ('f3f3f3f3-0000-4000-8000-000000000021','f3f3f3f3-0000-4000-8000-000000000011',
   tstzrange(now() + interval '1 day', now() + interval '3 days', '[)'),
   'booking','confirmed','f3000000-0000-0000-0000-000000000006',2,null,null),
  ('f3f3f3f3-0000-4000-8000-000000000022','f3f3f3f3-0000-4000-8000-000000000012',
   tstzrange(now() - interval '1 day', now() + interval '1 day', '[)'),
   'booking','checked_in','f3000000-0000-0000-0000-000000000006',2,now() - interval '1 day',null),
  ('f3f3f3f3-0000-4000-8000-000000000023','f3f3f3f3-0000-4000-8000-000000000011',
   tstzrange(now() + interval '10 days', now() + interval '12 days', '[)'),
   'booking','cancelled','f3000000-0000-0000-0000-000000000006',2,null,null),
  ('f3f3f3f3-0000-4000-8000-000000000024','f3f3f3f3-0000-4000-8000-000000000011',
   tstzrange(now() - interval '10 days', now() - interval '8 days', '[)'),
   'booking','checked_out','f3000000-0000-0000-0000-000000000006',2,
   now() - interval '10 days', now() - interval '8 days'),
  ('f3f3f3f3-0000-4000-8000-000000000025','f3f3f3f3-0000-4000-8000-000000000012',
   tstzrange(now() - interval '5 days', now() - interval '3 days', '[)'),
   'booking','confirmed','f3000000-0000-0000-0000-000000000006',2,null,null),
  ('f3f3f3f3-0000-4000-8000-000000000026','f3f3f3f3-0000-4000-8000-000000000013',
   tstzrange(now() + interval '1 day', now() + interval '3 days', '[)'),
   'booking','confirmed','f3000000-0000-0000-0000-000000000007',2,null,null);

-- ---------------------------------------------------------------------
-- Section 1: contract (Task 1)

select has_function('public', 'issue_stay_pass', array['uuid'], 'issue_stay_pass(uuid) exists');
select has_function('public', 'verify_stay_pass', array['text'], 'verify_stay_pass(text) exists');
select is(pg_get_function_result('public.issue_stay_pass(uuid)'::regprocedure), 'text',
  'issue_stay_pass returns text');
select is(pg_get_function_result('public.verify_stay_pass(text)'::regprocedure), 'jsonb',
  'verify_stay_pass returns jsonb');
select is(
  (select array_agg(p.proname::text order by p.proname)
     from pg_proc p
    where p.pronamespace = 'public'::regnamespace
      and p.proname in ('issue_stay_pass', 'verify_stay_pass')
      and p.prosecdef
      and p.provolatile = 's'
      and exists (select 1 from unnest(p.proconfig) c
                   where c like 'search_path=%public%pg_temp%')),
  array['issue_stay_pass', 'verify_stay_pass'],
  'both pass functions are stable security definer with a pinned search_path');
select ok(not has_function_privilege('anon', 'public.issue_stay_pass(uuid)', 'execute'),
  'anon cannot execute issue_stay_pass');
select ok(not has_function_privilege('anon', 'public.verify_stay_pass(text)', 'execute'),
  'anon cannot execute verify_stay_pass');
select ok(has_function_privilege('authenticated', 'public.issue_stay_pass(uuid)', 'execute'),
  'authenticated can execute issue_stay_pass');
select ok(has_function_privilege('authenticated', 'public.verify_stay_pass(text)', 'execute'),
  'authenticated can execute verify_stay_pass');
select has_table('private', 'stay_pass_secret', 'private.stay_pass_secret exists');
select is((select count(*)::int from private.stay_pass_secret where length(secret) = 32), 1,
  'one 32-byte secret is seeded');
select ok(not has_schema_privilege('authenticated', 'private', 'usage'),
  'authenticated cannot use the private schema');
select ok(not has_schema_privilege('anon', 'private', 'usage'),
  'anon cannot use the private schema');
select ok(not has_table_privilege('authenticated', 'private.stay_pass_secret', 'select'),
  'authenticated has no select on the secret');

set local role authenticated;
set local request.jwt.claims to '{"sub":"f3000000-0000-0000-0000-000000000003","role":"authenticated"}';
select throws_ok($$select secret from private.stay_pass_secret$$, '42501', null,
  'resort staff cannot read the secret');
reset role;

-- ---------------------------------------------------------------------
-- Section 2: issue_stay_pass and the pass format (Task 2)

-- base64url helpers, as the superuser (private is unreachable otherwise).
-- \xfbff is '+/8=' in plain base64.
select is(private.b64url_encode('\xfbff'::bytea), '-_8',
  'b64url uses - and _ and drops the padding');
select is(private.b64url_decode(private.b64url_encode('\x00ff10abcdef'::bytea)),
  '\x00ff10abcdef'::bytea, 'b64url round-trips');

-- Gita, the guest.
set local role authenticated;
set local request.jwt.claims to '{"sub":"f3000000-0000-0000-0000-000000000006","role":"authenticated"}';
select ok(set_config('test.tok_r1',
  public.issue_stay_pass('f3f3f3f3-0000-4000-8000-000000000021'), true)
  ~ '^rh1\.[A-Za-z0-9_-]{75}$',
  'the guest gets a well-formed pass for a confirmed booking');
select is(public.issue_stay_pass('f3f3f3f3-0000-4000-8000-000000000021'),
  current_setting('test.tok_r1'), 'issuing again gives the same pass');
select ok(set_config('test.tok_in',
  public.issue_stay_pass('f3f3f3f3-0000-4000-8000-000000000022'), true) ~ '^rh1\.',
  'a checked-in booking has a pass too');
select ok(set_config('test.tok_past',
  public.issue_stay_pass('f3f3f3f3-0000-4000-8000-000000000025'), true) ~ '^rh1\.',
  'a confirmed booking whose stay has ended still gets its (expired) pass');
select throws_ok($$select public.issue_stay_pass('f3f3f3f3-0000-4000-8000-000000000023')$$,
  'P0009', 'reservation is cancelled', 'no pass for a cancelled booking');
select throws_ok($$select public.issue_stay_pass('f3f3f3f3-0000-4000-8000-000000000024')$$,
  'P0009', 'reservation is checked_out', 'no pass after checkout');
select throws_ok($$select public.issue_stay_pass('f3f3f3f3-0000-4000-8000-000000000026')$$,
  'P0002', 'reservation not found', 'no pass for another guest''s booking');
select throws_ok($$select public.issue_stay_pass('f3f3f3f3-0000-4000-8000-0000000000ff')$$,
  'P0002', 'reservation not found', 'no pass for an unknown booking');

-- Hari, the other guest: his pass is used by Section 3.
set local request.jwt.claims to '{"sub":"f3000000-0000-0000-0000-000000000007","role":"authenticated"}';
select ok(set_config('test.tok_s1',
  public.issue_stay_pass('f3f3f3f3-0000-4000-8000-000000000026'), true) ~ '^rh1\.',
  'the other guest gets a pass for their own booking');

-- Staff do not mint passes, and cannot reach the helpers.
set local request.jwt.claims to '{"sub":"f3000000-0000-0000-0000-000000000003","role":"authenticated"}';
select throws_ok($$select public.issue_stay_pass('f3f3f3f3-0000-4000-8000-000000000021')$$,
  'P0002', 'reservation not found', 'resort staff cannot mint a guest''s pass');
select throws_ok($$select private.stay_pass_token('f3f3f3f3-0000-4000-8000-000000000021',
  'f3f3f3f3-0000-4000-8000-000000000001', 4102444800)$$,
  '42501', null, 'authenticated cannot call the private helpers');

set local request.jwt.claims to '{"role":"authenticated"}';
select throws_ok($$select public.issue_stay_pass('f3f3f3f3-0000-4000-8000-000000000021')$$,
  'P0008', 'authentication required', 'a caller with no user id is refused');

reset role;
set local role anon;
set local request.jwt.claims to '{"role":"anon"}';
select throws_ok($$select public.issue_stay_pass('f3f3f3f3-0000-4000-8000-000000000021')$$,
  '42501', null, 'anon cannot call issue_stay_pass');

-- What the pass carries, decoded as the superuser.
reset role;
select is(encode(substring(private.b64url_decode(substr(current_setting('test.tok_r1'), 5))
                           from 1 for 16), 'hex')::uuid,
  'f3f3f3f3-0000-4000-8000-000000000021'::uuid, 'the pass carries the reservation id');
select is(encode(substring(private.b64url_decode(substr(current_setting('test.tok_r1'), 5))
                           from 17 for 16), 'hex')::uuid,
  'f3f3f3f3-0000-4000-8000-000000000001'::uuid, 'the pass carries the resort id');
select is(('x' || encode(substring(private.b64url_decode(substr(current_setting('test.tok_r1'), 5))
                                   from 33 for 8), 'hex'))::bit(64)::bigint,
  (select extract(epoch from upper(period))::bigint from public.reservations
    where id = 'f3f3f3f3-0000-4000-8000-000000000021'),
  'the pass expires when the stay ends');
select is(substring(private.b64url_decode(substr(current_setting('test.tok_r1'), 5)) from 41 for 16),
  private.stay_pass_mac(substring(private.b64url_decode(substr(current_setting('test.tok_r1'), 5))
                                  from 1 for 40)),
  'the tag is the HMAC of the body');
select is(current_setting('test.tok_r1'),
  private.stay_pass_token('f3f3f3f3-0000-4000-8000-000000000021',
    'f3f3f3f3-0000-4000-8000-000000000001',
    (select extract(epoch from upper(period))::bigint from public.reservations
      where id = 'f3f3f3f3-0000-4000-8000-000000000021')),
  'stay_pass_token builds the same pass');

-- ---------------------------------------------------------------------
-- Section 3: verify_stay_pass (Task 3)

-- Passes minted as the superuser: expired, swapped to resort S (correctly
-- signed, so only the resort check can catch it), and for the cancelled
-- booking.
reset role;
select set_config('test.tok_expired', private.stay_pass_token(
  'f3f3f3f3-0000-4000-8000-000000000021', 'f3f3f3f3-0000-4000-8000-000000000001',
  extract(epoch from now())::bigint - 1), true);
select set_config('test.tok_swap', private.stay_pass_token(
  'f3f3f3f3-0000-4000-8000-000000000021', 'f3f3f3f3-0000-4000-8000-000000000002',
  extract(epoch from now())::bigint + 86400), true);
select set_config('test.tok_cancel', private.stay_pass_token(
  'f3f3f3f3-0000-4000-8000-000000000023', 'f3f3f3f3-0000-4000-8000-000000000001',
  extract(epoch from now())::bigint + 86400), true);

-- R's staff member at the desk.
set local role authenticated;
set local request.jwt.claims to '{"sub":"f3000000-0000-0000-0000-000000000003","role":"authenticated"}';
select is(public.verify_stay_pass(current_setting('test.tok_r1')) ->> 'id',
  'f3f3f3f3-0000-4000-8000-000000000021', 'R staff: the pass opens its booking');
select is(public.verify_stay_pass(current_setting('test.tok_r1')) ->> 'property_id',
  'f3f3f3f3-0000-4000-8000-000000000001', 'the booking''s resort is returned');
select is(public.verify_stay_pass(current_setting('test.tok_r1')) ->> 'unit_name',
  'Cottage 1', 'the unit name is returned');
select is(public.verify_stay_pass(current_setting('test.tok_r1')) -> 'profiles' ->> 'full_name',
  'Gita Guest', 'the guest''s name is returned');
select is(public.verify_stay_pass(current_setting('test.tok_r1')) ->> 'status',
  'confirmed', 'the booking''s status is returned');
select is(public.verify_stay_pass(current_setting('test.tok_in')) ->> 'status',
  'checked_in', 'a checked-in booking verifies, with its status');
select throws_ok($$select public.verify_stay_pass(current_setting('test.tok_past'))$$,
  'P0034', 'pass_expired', 'a pass whose stay has ended is expired');
select throws_ok($$select public.verify_stay_pass(current_setting('test.tok_expired'))$$,
  'P0034', 'pass_expired', 'a pass one second past its expiry is expired');
select is(public.verify_stay_pass(current_setting('test.tok_cancel')) ->> 'status',
  'cancelled', 'a cancelled booking verifies and shows as cancelled');
select throws_ok($$select public.verify_stay_pass(current_setting('test.tok_s1'))$$,
  'P0034', 'pass_other_resort', 'a pass for resort S is another resort''s');
select throws_ok($$select public.verify_stay_pass(current_setting('test.tok_swap'))$$,
  'P0034', 'pass_other_resort', 'a pass re-signed for resort S is another resort''s');
select throws_ok($$select public.verify_stay_pass(
    'rh1.' || case when substr(current_setting('test.tok_r1'), 5, 1) = 'A' then 'B' else 'A' end
           || substr(current_setting('test.tok_r1'), 6))$$,
  'P0034', 'pass_invalid', 'a pass with one character changed is invalid');
select throws_ok($$select public.verify_stay_pass('hello')$$,
  'P0034', 'pass_invalid', 'any other QR text is invalid');
select throws_ok($$select public.verify_stay_pass('f3f3f3f3-0000-4000-8000-000000000021')$$,
  'P0034', 'pass_invalid', 'an old bare-UUID QR is invalid');
select throws_ok($$select public.verify_stay_pass(null)$$,
  'P0034', 'pass_invalid', 'no pass is invalid');
select throws_ok($$select public.verify_stay_pass('rh1.' || repeat('A', 75))$$,
  'P0034', 'pass_invalid', 'a well-formed but unsigned pass is invalid');
select throws_ok($$select public.verify_stay_pass('rh1.' || repeat('!', 75))$$,
  'P0034', 'pass_invalid', 'a pass with characters outside base64url is invalid');

-- Every Staff+ role at R.
set local request.jwt.claims to '{"sub":"f3000000-0000-0000-0000-000000000001","role":"authenticated"}';
select is(public.verify_stay_pass(current_setting('test.tok_r1')) ->> 'id',
  'f3f3f3f3-0000-4000-8000-000000000021', 'R owner verifies');
set local request.jwt.claims to '{"sub":"f3000000-0000-0000-0000-000000000002","role":"authenticated"}';
select is(public.verify_stay_pass(current_setting('test.tok_r1')) ->> 'id',
  'f3f3f3f3-0000-4000-8000-000000000021', 'R admin verifies');
set local request.jwt.claims to '{"sub":"f3000000-0000-0000-0000-000000000004","role":"authenticated"}';
select is(public.verify_stay_pass(current_setting('test.tok_r1')) ->> 'id',
  'f3f3f3f3-0000-4000-8000-000000000021', 'R accountant verifies');

-- S's staff member.
set local request.jwt.claims to '{"sub":"f3000000-0000-0000-0000-000000000005","role":"authenticated"}';
select throws_ok($$select public.verify_stay_pass(current_setting('test.tok_r1'))$$,
  'P0034', 'pass_other_resort', 'S staff: an R pass is another resort''s');
select throws_ok($$select public.verify_stay_pass(current_setting('test.tok_expired'))$$,
  'P0034', 'pass_other_resort', 'S staff learn nothing about an R pass''s expiry');
select throws_ok($$select public.verify_stay_pass(current_setting('test.tok_swap'))$$,
  'P0034', 'pass_invalid', 'S staff: a pass naming S for an R booking is invalid');
select is(public.verify_stay_pass(current_setting('test.tok_s1')) ->> 'id',
  'f3f3f3f3-0000-4000-8000-000000000026', 'S staff verify their own guest''s pass');

-- Not staff at all.
set local request.jwt.claims to '{"sub":"f3000000-0000-0000-0000-000000000006","role":"authenticated"}';
select throws_ok($$select public.verify_stay_pass(current_setting('test.tok_r1'))$$,
  'P0034', 'pass_other_resort', 'the guest cannot verify their own pass');
set local request.jwt.claims to '{"sub":"f3000000-0000-0000-0000-000000000008","role":"authenticated"}';
select throws_ok($$select public.verify_stay_pass(current_setting('test.tok_r1'))$$,
  'P0034', 'pass_other_resort', 'an outsider cannot verify a pass');
reset role;
set local role anon;
set local request.jwt.claims to '{"role":"anon"}';
select throws_ok($$select public.verify_stay_pass('rh1.x')$$,
  '42501', null, 'anon cannot call verify_stay_pass');

-- Suspended resort: verifying is a read and still works.
reset role;
set local request.jwt.claims to '';
update public.properties set status = 'suspended'
 where id = 'f3f3f3f3-0000-4000-8000-000000000001';
set local role authenticated;
set local request.jwt.claims to '{"sub":"f3000000-0000-0000-0000-000000000003","role":"authenticated"}';
select is(public.verify_stay_pass(current_setting('test.tok_r1')) ->> 'id',
  'f3f3f3f3-0000-4000-8000-000000000021', 'a suspended resort''s staff can still verify');

-- Archived resort: no access at all.
reset role;
set local request.jwt.claims to '';
update public.properties set status = 'archived'
 where id = 'f3f3f3f3-0000-4000-8000-000000000001';
set local role authenticated;
set local request.jwt.claims to '{"sub":"f3000000-0000-0000-0000-000000000003","role":"authenticated"}';
select throws_ok($$select public.verify_stay_pass(current_setting('test.tok_r1'))$$,
  'P0034', 'pass_other_resort', 'an archived resort''s staff cannot verify');
reset role;
set local request.jwt.claims to '';
update public.properties set status = 'active'
 where id = 'f3f3f3f3-0000-4000-8000-000000000001';

-- Rotating the secret invalidates every earlier pass.
update private.stay_pass_secret set secret = extensions.gen_random_bytes(32);
set local role authenticated;
set local request.jwt.claims to '{"sub":"f3000000-0000-0000-0000-000000000003","role":"authenticated"}';
select throws_ok($$select public.verify_stay_pass(current_setting('test.tok_r1'))$$,
  'P0034', 'pass_invalid', 'after a rotation the old pass is invalid');
reset role;

-- A missing secret fails closed (review fix). Without the row the tag
-- cannot be computed, so no pass verifies -- not even one with a zeroed
-- tag naming a real booking at R -- and none is issued.
delete from private.stay_pass_secret;
select set_config('test.tok_forged', 'rh1.' || private.b64url_encode(
     decode(replace('f3f3f3f3-0000-4000-8000-000000000021', '-', ''), 'hex')
  || decode(replace('f3f3f3f3-0000-4000-8000-000000000001', '-', ''), 'hex')
  || int8send(extract(epoch from now())::bigint + 86400)
  || '\x00000000000000000000000000000000'::bytea), true);
set local role authenticated;
set local request.jwt.claims to '{"sub":"f3000000-0000-0000-0000-000000000003","role":"authenticated"}';
select throws_ok($$select public.verify_stay_pass(current_setting('test.tok_forged'))$$,
  'P0034', 'pass_invalid', 'with no secret a forged pass for an R booking is invalid');
select throws_ok($$select public.verify_stay_pass(current_setting('test.tok_r1'))$$,
  'P0034', 'pass_invalid', 'with no secret an issued pass is invalid');
set local request.jwt.claims to '{"sub":"f3000000-0000-0000-0000-000000000006","role":"authenticated"}';
select throws_ok($$select public.issue_stay_pass('f3f3f3f3-0000-4000-8000-000000000021')$$,
  'XX000', 'stay pass secret is not set', 'with no secret no pass is issued');
reset role;

select * from finish();
rollback;
