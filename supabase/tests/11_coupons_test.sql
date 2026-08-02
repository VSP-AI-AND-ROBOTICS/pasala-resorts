-- Coupons, applied server-side inside the quote. Every discount figure
-- asserted below was verified against the ACTUAL get_quote implementation
-- (not derived independently) before this file was written: base
-- 10000/night + 1500 cleaning = 11500 pre-discount, so a 10% coupon
-- discounts 1150 for a total of 10350 -- matching the task brief's worked
-- example exactly -- and a flat 2000 coupon discounts 2000 for 9500.

begin;
select plan(53);

select has_table('public', 'coupons', 'coupons table exists');
select has_table('public', 'coupon_redemptions',
  'coupon_redemptions table exists');

insert into public.properties (id, name, slug)
values ('aaaaaaaa-0000-0000-0000-000000000001', 'P1', 'p1');
insert into public.units (id, property_id, name, capacity_base, capacity_max)
values ('bbbbbbbb-0000-0000-0000-000000000001',
        'aaaaaaaa-0000-0000-0000-000000000001', 'U1', 4, 6);
-- base 10000/night, +1500 per extra guest, 1500 cleaning -- identical
-- fixture to 03_quote_test.sql, so the pre-discount total for one weekday
-- night is the same well-established 11500.
insert into public.rate_rules
  (unit_id, kind, price, extra_guest_price, cleaning_fee, priority)
values ('bbbbbbbb-0000-0000-0000-000000000001', 'base', 10000, 1500, 1500, 0);

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'cust1@example.com'),
  ('22222222-2222-2222-2222-222222222222', 'cust2@example.com'),
  ('44444444-4444-4444-4444-444444444444', 'couponadmin@example.com');
update public.profiles set role = 'admin'
  where id = '44444444-4444-4444-4444-444444444444';

insert into public.coupons (code, kind, value) values
  ('SAVE10', 'percent', 10),
  ('FLAT2000', 'fixed', 2000),
  ('HUGE', 'fixed', 999999);
insert into public.coupons (code, kind, value, valid_to) values
  ('EXPIRED10', 'percent', 10, now() - interval '1 day');
insert into public.coupons
  (code, kind, value, max_redemptions, redeemed_count) values
  ('MAXED', 'percent', 10, 1, 1);
insert into public.coupons (code, kind, value, min_booking_value) values
  ('BIGONLY', 'percent', 10, 50000);
insert into public.coupons (code, kind, value, is_active) values
  ('INACTIVE', 'percent', 10, false);
insert into public.coupons (code, kind, value, customer_id) values
  ('MINE', 'percent', 10, '22222222-2222-2222-2222-222222222222');
insert into public.coupons
  (code, kind, value, max_redemptions) values
  ('LASTONE', 'percent', 10, 1);

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

-- === worked arithmetic, verified against the real get_quote =============

select is(
  (public.get_quote('bbbbbbbb-0000-0000-0000-000000000001',
     tstzrange('2026-08-03 14:00+05:30','2026-08-04 11:00+05:30','[)'),
     4, null, 'SAVE10') -> 'coupon' ->> 'discount')::numeric,
  1150.00::numeric,
  'a 10% coupon on 11500 (10000 + 1500 cleaning) discounts 1150');

select is(
  (public.get_quote('bbbbbbbb-0000-0000-0000-000000000001',
     tstzrange('2026-08-03 14:00+05:30','2026-08-04 11:00+05:30','[)'),
     4, null, 'SAVE10') ->> 'total')::numeric,
  10350.00::numeric,
  'percent coupon: total is 11500 - 1150 = 10350');

select is(
  (public.get_quote('bbbbbbbb-0000-0000-0000-000000000001',
     tstzrange('2026-08-03 14:00+05:30','2026-08-04 11:00+05:30','[)'),
     4, null, 'FLAT2000') -> 'coupon' ->> 'discount')::numeric,
  2000.00::numeric,
  'a fixed 2000 coupon discounts exactly 2000');

select is(
  (public.get_quote('bbbbbbbb-0000-0000-0000-000000000001',
     tstzrange('2026-08-03 14:00+05:30','2026-08-04 11:00+05:30','[)'),
     4, null, 'FLAT2000') ->> 'total')::numeric,
  9500.00::numeric,
  'fixed coupon: total is 11500 - 2000 = 9500');

select is(
  (public.get_quote('bbbbbbbb-0000-0000-0000-000000000001',
     tstzrange('2026-08-03 14:00+05:30','2026-08-04 11:00+05:30','[)'),
     4) -> 'coupon'),
  'null'::jsonb,
  'no coupon code means the quote coupon field is JSON null, not an '
  'empty object');

-- === a coupon can never drive the total below zero ========================

select is(
  (public.get_quote('bbbbbbbb-0000-0000-0000-000000000001',
     tstzrange('2026-08-03 14:00+05:30','2026-08-04 11:00+05:30','[)'),
     4, null, 'HUGE') ->> 'total')::numeric,
  0.00::numeric,
  'a fixed coupon far larger than the total is capped -- total never negative');

select is(
  (public.get_quote('bbbbbbbb-0000-0000-0000-000000000001',
     tstzrange('2026-08-03 14:00+05:30','2026-08-04 11:00+05:30','[)'),
     4, null, 'HUGE') -> 'coupon' ->> 'discount')::numeric,
  11500.00::numeric,
  'the capped discount equals the full pre-discount total, not the raw '
  'coupon value');

-- === error codes ===========================================================

select throws_ok(
  $$select public.get_quote('bbbbbbbb-0000-0000-0000-000000000001',
      tstzrange('2026-08-03 14:00+05:30','2026-08-04 11:00+05:30','[)'),
      4, null, 'EXPIRED10')$$,
  'P0011', null, 'an expired coupon raises P0011');

select throws_ok(
  $$select public.get_quote('bbbbbbbb-0000-0000-0000-000000000001',
      tstzrange('2026-08-03 14:00+05:30','2026-08-04 11:00+05:30','[)'),
      4, null, 'MAXED')$$,
  'P0012', null, 'a coupon past max_redemptions raises P0012');

select throws_ok(
  $$select public.get_quote('bbbbbbbb-0000-0000-0000-000000000001',
      tstzrange('2026-08-03 14:00+05:30','2026-08-04 11:00+05:30','[)'),
      4, null, 'BIGONLY')$$,
  'P0013', null, 'a booking under min_booking_value raises P0013');

select throws_ok(
  $$select public.get_quote('bbbbbbbb-0000-0000-0000-000000000001',
      tstzrange('2026-08-03 14:00+05:30','2026-08-04 11:00+05:30','[)'),
      4, null, 'NOSUCHCODE')$$,
  'P0010', null, 'an unknown coupon code raises P0010');

select throws_ok(
  $$select public.get_quote('bbbbbbbb-0000-0000-0000-000000000001',
      tstzrange('2026-08-03 14:00+05:30','2026-08-04 11:00+05:30','[)'),
      4, null, 'INACTIVE')$$,
  'P0010', null, 'an inactive coupon raises P0010, same as unknown');

-- Customer 1 (the session above) hitting a coupon restricted to customer 2
-- must see the same P0010 as an unknown code -- not a different error that
-- would confirm the code exists for someone else.
select throws_ok(
  $$select public.get_quote('bbbbbbbb-0000-0000-0000-000000000001',
      tstzrange('2026-08-03 14:00+05:30','2026-08-04 11:00+05:30','[)'),
      4, null, 'MINE')$$,
  'P0010', null,
  'a coupon restricted to another customer raises P0010 for this one');

-- === the correctness trap: create_hold must re-quote WITH the coupon =====

-- Happy path: the client quoted 10350 (WITH the coupon applied) and holds
-- at that same number.
select lives_ok(
  $$select public.create_hold('bbbbbbbb-0000-0000-0000-000000000001',
      '2026-09-01','2026-09-02', 4, null, 10350, 'SAVE10')$$,
  'a couponed hold succeeds end to end when expected_total matches the '
  'discounted total');

-- The trap itself: if create_hold's internal re-quote silently dropped the
-- coupon code, it would re-quote at 11500 (undiscounted) and this SAME
-- 10350 the customer was quoted would then look "stale" and raise P0007 --
-- exactly backwards from what should happen. This proves the coupon code
-- really did flow through to the internal get_quote call, not just that
-- SOME expected_total was accepted.
select throws_ok(
  $$select public.create_hold('bbbbbbbb-0000-0000-0000-000000000001',
      '2026-09-05','2026-09-06', 4, null, 11500, 'SAVE10')$$,
  'P0007', null,
  'create_hold rejects the UNDISCOUNTED total for a couponed hold -- proof '
  'the coupon code reached the internal re-quote, not just that some '
  'total was accepted');

-- === the discount is stored in the reservation''s quote ====================

select is(
  (select quote -> 'coupon' ->> 'code' from public.reservations
    where unit_id = 'bbbbbbbb-0000-0000-0000-000000000001'
      and lower(period) >= '2026-09-01' and lower(period) < '2026-09-02'),
  'SAVE10',
  'the reservation''s stored quote records the coupon code');

select is(
  (select (quote -> 'coupon' ->> 'discount')::numeric from public.reservations
    where unit_id = 'bbbbbbbb-0000-0000-0000-000000000001'
      and lower(period) >= '2026-09-01' and lower(period) < '2026-09-02'),
  1150.00::numeric,
  'the reservation''s stored quote records the discount amount');

select is(
  (select (quote ->> 'total')::numeric from public.reservations
    where unit_id = 'bbbbbbbb-0000-0000-0000-000000000001'
      and lower(period) >= '2026-09-01' and lower(period) < '2026-09-02'),
  10350.00::numeric,
  'the reservation''s stored quote total is net of the discount');

-- === redemption bookkeeping =================================================

select is(
  (select redeemed_count from public.coupons where code = 'SAVE10'),
  1,
  'redeeming a coupon through create_hold increments redeemed_count');

select is(
  (select count(*)::int from public.coupon_redemptions cr
    join public.coupons c on c.id = cr.coupon_id
    where c.code = 'SAVE10'),
  1,
  'exactly one coupon_redemptions row was created for the couponed hold');

select is(
  (select cr.amount from public.coupon_redemptions cr
    join public.coupons c on c.id = cr.coupon_id
    where c.code = 'SAVE10'),
  1150.00::numeric,
  'the redemption records the discount amount, not the coupon''s raw value');

select is(
  (select cr.reservation_id from public.coupon_redemptions cr
    join public.coupons c on c.id = cr.coupon_id
    where c.code = 'SAVE10'),
  (select id from public.reservations
    where unit_id = 'bbbbbbbb-0000-0000-0000-000000000001'
      and lower(period) >= '2026-09-01' and lower(period) < '2026-09-02'),
  'the redemption is tied to the exact reservation it was created with');

-- A redemption cannot exist without a reservation: the FK is real, not
-- just a convention. Run as postgres (bypassing RLS, same as every other
-- fixture-seeding statement in this file's peers) so this actually
-- exercises the FK constraint rather than being pre-empted by
-- coupon_redemptions_admin_write's RLS check, which a plain customer
-- would hit first regardless of the FK.
set local role postgres;
select throws_ok(
  $$insert into public.coupon_redemptions
      (coupon_id, reservation_id, customer_id, amount)
    values ((select id from public.coupons where code = 'SAVE10'),
            '00000000-0000-0000-0000-0000000000ff',
            '11111111-1111-1111-1111-111111111111', 100)$$,
  '23503', null,
  'a coupon_redemptions row cannot reference a nonexistent reservation');
set local role authenticated;
set local request.jwt.claims to
  '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

-- === max_redemptions, exercised sequentially through create_hold itself ===
-- (the atomic race-safety proof below additionally covers the case a
-- sequential test structurally cannot: two holds racing for the same
-- last slot at the same instant.)

select lives_ok(
  $$select public.create_hold('bbbbbbbb-0000-0000-0000-000000000001',
      '2026-09-10','2026-09-11', 4, null, 10350, 'LASTONE')$$,
  'the first redemption of a max_redemptions=1 coupon succeeds');

select throws_ok(
  $$select public.create_hold('bbbbbbbb-0000-0000-0000-000000000001',
      '2026-09-15','2026-09-16', 4, null, 10350, 'LASTONE')$$,
  'P0012', null,
  'a second redemption of the same coupon, once its limit is reached, '
  'raises P0012');

select is(
  (select count(*)::int from public.reservations
    where unit_id = 'bbbbbbbb-0000-0000-0000-000000000001'
      and lower(period) >= '2026-09-15' and lower(period) < '2026-09-16'),
  0,
  'the rejected second redemption left no orphaned hold behind -- '
  'create_hold is all-or-nothing');

-- === RLS: grants beside policies ===========================================

set local role anon;
select ok(
  (select count(*) from public.coupons where code = 'SAVE10') = 1,
  'anon can read an active, unrestricted coupon');
select ok(
  (select count(*) from public.coupons where code = 'INACTIVE') = 0,
  'anon cannot see an inactive coupon through RLS');
select throws_ok(
  $$insert into public.coupons (code, kind, value) values ('HACK','fixed',1)$$,
  '42501', null, 'anon cannot create coupons');
reset role;

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';
select throws_ok(
  $$insert into public.coupons (code, kind, value) values ('HACK2','fixed',1)$$,
  '42501', null, 'a customer cannot create coupons');
-- Customer 1 made both redemptions earlier in this file (SAVE10 and
-- LASTONE); customer 2 made none. Comparing customer 2's count against
-- zero -- rather than asserting customer 1's own evolving total -- is
-- what actually proves "own only," not just "some number came back."
set local request.jwt.claims to
  '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}';
select is(
  (select count(*)::int from public.coupon_redemptions),
  0,
  'a customer who redeemed nothing sees zero coupon redemptions, not '
  'someone else''s');

set local request.jwt.claims to
  '{"sub":"44444444-4444-4444-4444-444444444444","role":"authenticated"}';
select lives_ok(
  $$insert into public.coupons (code, kind, value) values ('ADMINMADE','percent',5)$$,
  'an admin can create a coupon');
reset role;

-- === redemption counting must be race-safe =================================
--
-- Two customers redeeming the last slot of a max_redemptions=1 coupon at
-- the same instant must not both succeed. `create_hold`'s redemption
-- consumption is a single atomic `UPDATE ... WHERE redeemed_count <
-- max_redemptions RETURNING id` -- the check and the increment are the
-- SAME statement, so Postgres's row-level lock on the coupon row
-- serializes any two concurrent attempts regardless of arrival order. A
-- naive "SELECT count(*) < max_redemptions, THEN INSERT" implementation
-- has a real gap between those two statements for a second session to
-- read the same stale count through -- proven live against a throwaway
-- copy of exactly that shape before writing this test: both concurrent
-- calls returned success and redeemed_count overshot to 2.
--
-- A single pgTAP session cannot produce genuine concurrency on its own, so
-- this test opens two more real connections via `dblink` and fires both
-- `create_hold` calls asynchronously (send both, THEN wait for either
-- result) so they are genuinely in flight at the database level at the
-- same time, not just run one after another.
--
-- The race's own fixture must be COMMITTED, not staged in this file's
-- outer transaction, or the two dblink sessions (genuinely separate
-- connections) would not see it -- so it is created and torn down via
-- dblink itself, independent of this file's closing `rollback`.
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
  v_row   record;
begin
  perform dblink_exec(v_conn, $F$
    insert into public.properties (id, name, slug, timezone)
    values ('a0000000-0000-0000-0000-0000000000f1','RaceProp','race-prop-11',
            'Asia/Kolkata')$F$);
  perform dblink_exec(v_conn, $F$
    insert into public.units (id, property_id, name, capacity_base, capacity_max)
    values
      ('b0000000-0000-0000-0000-0000000000f1',
       'a0000000-0000-0000-0000-0000000000f1','RaceU1',2,2),
      ('b0000000-0000-0000-0000-0000000000f2',
       'a0000000-0000-0000-0000-0000000000f1','RaceU2',2,2)$F$);
  perform dblink_exec(v_conn, $F$
    insert into public.rate_rules (unit_id, kind, price, cleaning_fee, priority)
    values
      ('b0000000-0000-0000-0000-0000000000f1','base',5000,500,0),
      ('b0000000-0000-0000-0000-0000000000f2','base',5000,500,0)$F$);
  perform dblink_exec(v_conn, $F$
    insert into auth.users (id, email) values
      ('c0000000-0000-0000-0000-0000000000f1','racecust1@example.com'),
      ('c0000000-0000-0000-0000-0000000000f2','racecust2@example.com')$F$);
  perform dblink_exec(v_conn, $F$
    insert into public.coupons (code, kind, value, max_redemptions)
    values ('RACE10','percent',10,1)$F$);

  perform dblink_connect('race_a', v_conn);
  perform dblink_connect('race_b', v_conn);
  perform dblink_exec('race_a', 'set role authenticated');
  perform dblink_exec('race_a', $Q$set request.jwt.claims to
    '{"sub":"c0000000-0000-0000-0000-0000000000f1","role":"authenticated"}'$Q$);
  perform dblink_exec('race_b', 'set role authenticated');
  perform dblink_exec('race_b', $Q$set request.jwt.claims to
    '{"sub":"c0000000-0000-0000-0000-0000000000f2","role":"authenticated"}'$Q$);

  -- Both sent before either is awaited -- this is what makes them
  -- genuinely concurrent rather than sequential.
  perform dblink_send_query('race_a', $Q$
    select id from public.create_hold(
      'b0000000-0000-0000-0000-0000000000f1','2029-01-10','2029-01-11',2,
      null, 4950, 'RACE10') as t(id)$Q$);
  perform dblink_send_query('race_b', $Q$
    select id from public.create_hold(
      'b0000000-0000-0000-0000-0000000000f2','2029-01-10','2029-01-11',2,
      null, 4950, 'RACE10') as t(id)$Q$);

  begin
    select * into v_row from dblink_get_result('race_a') as t(id uuid);
    v_a_ok := true;
  exception when others then
    v_a_err := sqlstate;
  end;
  begin perform dblink_get_result('race_a'); exception when others then null; end;

  begin
    select * into v_row from dblink_get_result('race_b') as t(id uuid);
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
  perform set_config('app.race_redeemed_count',
    (select redeemed_count::text from public.coupons where code = 'RACE10'), false);
  perform set_config('app.race_redemption_rows',
    (select count(*)::text from public.coupon_redemptions cr
      join public.coupons c on c.id = cr.coupon_id
      where c.code = 'RACE10'), false);

  -- Torn down via dblink, independent of this file's own rollback.
  perform dblink_exec(v_conn, $F$
    delete from public.coupon_redemptions where coupon_id in
      (select id from public.coupons where code = 'RACE10')$F$);
  perform dblink_exec(v_conn, $F$delete from public.coupons where code = 'RACE10'$F$);
  perform dblink_exec(v_conn, $F$
    delete from public.reservations where unit_id in
      ('b0000000-0000-0000-0000-0000000000f1',
       'b0000000-0000-0000-0000-0000000000f2')$F$);
  perform dblink_exec(v_conn, $F$
    delete from public.rate_rules where unit_id in
      ('b0000000-0000-0000-0000-0000000000f1',
       'b0000000-0000-0000-0000-0000000000f2')$F$);
  perform dblink_exec(v_conn, $F$
    delete from public.units where id in
      ('b0000000-0000-0000-0000-0000000000f1',
       'b0000000-0000-0000-0000-0000000000f2')$F$);
  perform dblink_exec(v_conn, $F$
    delete from public.properties where id = 'a0000000-0000-0000-0000-0000000000f1'$F$);
  perform dblink_exec(v_conn, $F$
    delete from auth.users where id in
      ('c0000000-0000-0000-0000-0000000000f1',
       'c0000000-0000-0000-0000-0000000000f2')$F$);
end $$;
reset role;

select ok(
  (current_setting('app.race_a_ok') = 'true') <> (current_setting('app.race_b_ok') = 'true'),
  'exactly one of the two concurrent create_hold calls succeeded, not '
  'both and not neither');

select is(
  (case when current_setting('app.race_a_ok') = 'false'
        then current_setting('app.race_a_err')
        else current_setting('app.race_b_err') end),
  'P0012',
  'the losing concurrent call was rejected with P0012, not a different error');

select is(
  current_setting('app.race_redeemed_count')::int,
  1,
  'redeemed_count is exactly 1 after the race -- never overshoots '
  'max_redemptions, and never gets left at 0 by two mutual failures');

select is(
  current_setting('app.race_redemption_rows')::int,
  1,
  'exactly one coupon_redemptions row exists after the race');

-- === carried-forward fix: an abandoned/expired hold must release its ======
-- === coupon redemption, not exhaust it forever =============================
--
-- Task 7's review found that `cancel_booking` and `release_expired_holds`
-- only ever flipped `reservations.status` -- neither touched
-- `coupons.redeemed_count` or `coupon_redemptions`, so a single abandoned
-- hold against a `max_redemptions = 1` coupon exhausted it permanently, for
-- every future customer. Proven here via `cancel_booking` directly and via
-- `release_expired_holds` (the unattended path an abandoned hold actually
-- takes), plus idempotency (a second cancel of an already-cancelled
-- reservation must not decrement a second time) and reuse (once released,
-- a DIFFERENT customer can redeem the same slot).

insert into public.coupons (code, kind, value, max_redemptions) values
  ('RELEASE1', 'percent', 10, 1),
  ('RELEASE2', 'percent', 10, 1);

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

-- --- cancel_booking releases the redemption -------------------------------

select lives_ok(
  $$select public.create_hold('bbbbbbbb-0000-0000-0000-000000000001',
      '2026-10-01','2026-10-02', 4, null, 10350, 'RELEASE1')$$,
  'a max_redemptions=1 coupon can be redeemed once');

select is(
  (select redeemed_count from public.coupons where code = 'RELEASE1'),
  1,
  'redeeming RELEASE1 brings its redeemed_count to 1');

select lives_ok(
  $$select public.cancel_booking(
      (select id from public.reservations
        where unit_id = 'bbbbbbbb-0000-0000-0000-000000000001'
          and lower(period) >= '2026-10-01' and lower(period) < '2026-10-02'),
      'changed plans')$$,
  'cancelling the redeemed hold succeeds');

select is(
  (select redeemed_count from public.coupons where code = 'RELEASE1'),
  0,
  'THE FIX: cancelling the hold restores redeemed_count to 0 -- before '
  'this fix it stayed permanently at 1');

select is(
  (select count(*)::int from public.coupon_redemptions cr
    join public.coupons c on c.id = cr.coupon_id
    where c.code = 'RELEASE1'),
  0,
  'THE FIX: cancelling the hold removes the coupon_redemptions row');

-- Idempotency: cancelling an already-cancelled reservation must not
-- decrement a second time. cancel_booking's own early return (status
-- already 'cancelled') means this exercises that guard directly.
select lives_ok(
  $$select public.cancel_booking(
      (select id from public.reservations
        where unit_id = 'bbbbbbbb-0000-0000-0000-000000000001'
          and lower(period) >= '2026-10-01' and lower(period) < '2026-10-02'),
      'changed plans again')$$,
  'a second cancel of the same reservation is a no-op, not an error');

select is(
  (select redeemed_count from public.coupons where code = 'RELEASE1'),
  0,
  'a second cancel does not decrement redeemed_count again -- it never '
  'goes negative and never double-releases');

-- Reuse: the released slot is now available to a DIFFERENT customer, proof
-- the release is real and not just cosmetic bookkeeping.
set local request.jwt.claims to
  '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}';

select lives_ok(
  $$select public.create_hold('bbbbbbbb-0000-0000-0000-000000000001',
      '2026-10-05','2026-10-06', 4, null, 10350, 'RELEASE1')$$,
  'a released max_redemptions=1 coupon can be redeemed by a different '
  'customer');

select is(
  (select redeemed_count from public.coupons where code = 'RELEASE1'),
  1,
  'the reused coupon''s redeemed_count is 1, not 2 (no double count) and '
  'not 0 (the new redemption really was recorded)');

-- --- release_expired_holds releases the redemption too --------------------
-- This is the path an ABANDONED hold actually takes: nobody calls
-- cancel_booking at all, the 15-minute expiry just passes and the pg_cron
-- job (or a direct test call, here) sweeps it.

set local request.jwt.claims to
  '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

select lives_ok(
  $$select public.create_hold('bbbbbbbb-0000-0000-0000-000000000001',
      '2026-10-10','2026-10-11', 4, null, 10350, 'RELEASE2')$$,
  'RELEASE2 is redeemed for the expiry-path fixture');

select is(
  (select redeemed_count from public.coupons where code = 'RELEASE2'),
  1,
  'RELEASE2''s redeemed_count is 1 before it expires');

set local role postgres;
update public.reservations
   set hold_expires_at = now() - interval '1 minute'
 where unit_id = 'bbbbbbbb-0000-0000-0000-000000000001'
   and lower(period) >= '2026-10-10' and lower(period) < '2026-10-11';

select is(
  public.release_expired_holds(),
  1,
  'exactly the one forced-expired hold is released');

select is(
  (select status from public.reservations
    where unit_id = 'bbbbbbbb-0000-0000-0000-000000000001'
      and lower(period) >= '2026-10-10' and lower(period) < '2026-10-11'),
  'cancelled'::public.reservation_status,
  'the expired hold is cancelled');

select is(
  (select redeemed_count from public.coupons where code = 'RELEASE2'),
  0,
  'THE FIX: an expired (never explicitly cancelled) hold also releases '
  'its coupon redemption');

select is(
  (select count(*)::int from public.coupon_redemptions cr
    join public.coupons c on c.id = cr.coupon_id
    where c.code = 'RELEASE2'),
  0,
  'THE FIX: the expired hold''s coupon_redemptions row is removed too');

reset role;

select * from finish();
rollback;
