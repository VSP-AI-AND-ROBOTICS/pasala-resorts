-- Subscription auto-billing (P8), added in 0057_subscription_billing.sql.
-- See docs/superpowers/specs/2026-09-25-p8-subscription-auto-billing-design.md.
--
-- One file, built up by the plan's database tasks in order: each section
-- relies on the state the sections before it leave behind.
--
-- Fixtures: a platform admin (U1); an owner (U2) of R1, R3, R4 and R5; an
-- admin (U3) and a staff member (U4) of R1; a second owner (U5) of R2;
-- and a guest (U6) with no membership.
--   R1 Bill Trial      starter trial ending in 10 days
--   R2 Bill Paid       pro, active, paid until 5 days from now
--   R3 Bill Suspended  suspended resort, starter, active, no end date
--   R4 Bill Lapsed     pro, active, paid until 3 days ago
--   R5 Bill None       no subscription row
begin;
select plan(95);

-- "Today" as the subscription functions see it.
create function pg_temp.today() returns date
language sql stable as $f$ select (now() at time zone 'Asia/Kolkata')::date $f$;

-- Unix seconds of midnight Asia/Kolkata at the start of p_day.
create function pg_temp.ist(p_day date) returns bigint
language sql stable as $f$
  select extract(epoch from (p_day::timestamp at time zone 'Asia/Kolkata'))::bigint
$f$;

insert into auth.users (id, email) values
  ('b8000000-0000-0000-0000-000000000001','bill-platform@example.com'),
  ('b8000000-0000-0000-0000-000000000002','bill-owner@example.com'),
  ('b8000000-0000-0000-0000-000000000003','bill-admin@example.com'),
  ('b8000000-0000-0000-0000-000000000004','bill-staff@example.com'),
  ('b8000000-0000-0000-0000-000000000005','bill-other@example.com'),
  ('b8000000-0000-0000-0000-000000000006','bill-guest@example.com');
update public.profiles set role = 'platform_admin'
  where id = 'b8000000-0000-0000-0000-000000000001';

insert into public.properties (id, name, slug, status) values
  ('b8100000-0000-4000-8000-000000000001','Bill Trial','bill-trial','active'),
  ('b8100000-0000-4000-8000-000000000002','Bill Paid','bill-paid','active'),
  ('b8100000-0000-4000-8000-000000000003','Bill Suspended','bill-suspended','suspended'),
  ('b8100000-0000-4000-8000-000000000004','Bill Lapsed','bill-lapsed','active'),
  ('b8100000-0000-4000-8000-000000000005','Bill None','bill-none','active');

insert into public.resort_members (property_id, user_id, role) values
  ('b8100000-0000-4000-8000-000000000001','b8000000-0000-0000-0000-000000000002','owner'),
  ('b8100000-0000-4000-8000-000000000001','b8000000-0000-0000-0000-000000000003','admin'),
  ('b8100000-0000-4000-8000-000000000001','b8000000-0000-0000-0000-000000000004','staff'),
  ('b8100000-0000-4000-8000-000000000002','b8000000-0000-0000-0000-000000000005','owner'),
  ('b8100000-0000-4000-8000-000000000003','b8000000-0000-0000-0000-000000000002','owner'),
  ('b8100000-0000-4000-8000-000000000004','b8000000-0000-0000-0000-000000000002','owner'),
  ('b8100000-0000-4000-8000-000000000005','b8000000-0000-0000-0000-000000000002','owner');

insert into public.resort_subscriptions (property_id, tier, status, trial_ends_on, paid_through) values
  ('b8100000-0000-4000-8000-000000000001','starter','trial',pg_temp.today() + 10,null),
  ('b8100000-0000-4000-8000-000000000002','pro','active',null,pg_temp.today() + 5),
  ('b8100000-0000-4000-8000-000000000003','starter','active',null,null),
  ('b8100000-0000-4000-8000-000000000004','pro','active',null,pg_temp.today() - 3);

-- === Task 1: the contract ===================================================

select has_column('public', 'subscription_plans', 'razorpay_plan_id',
  'each tier can carry a Razorpay plan id');
select has_table('public', 'billing_subscriptions', 'billing_subscriptions exists');
select has_table('public', 'subscription_invoices', 'subscription_invoices exists');
select throws_ok($$update public.subscription_plans set razorpay_plan_id = 'pro-monthly' where tier = 'pro'$$,
  '23514', null, 'a plan id must look like plan_...');
select throws_ok($$insert into public.billing_subscriptions
    (property_id, tier, razorpay_plan_id, razorpay_subscription_id)
  values ('b8100000-0000-4000-8000-000000000001', 'pro', 'plan_ContractPro01', 'subscription-1')$$,
  '23514', null, 'a subscription id must look like sub_...');
select is((select array_agg(p.parameter_name::text order by p.ordinal_position)
             from information_schema.parameters p
             join information_schema.routines r
               on r.specific_schema = p.specific_schema and r.specific_name = p.specific_name
            where r.routine_schema = 'public' and r.routine_name = 'my_resort_billing'
              and p.parameter_mode = 'OUT'),
  array['billing_status','billing_tier','short_url','cancel_at_cycle_end','current_end',
        'last_payment_at','last_payment_inr'],
  'my_resort_billing returns the columns ResortBilling.fromRow reads');
select is((select array_agg(p.parameter_name::text order by p.ordinal_position)
             from information_schema.parameters p
             join information_schema.routines r
               on r.specific_schema = p.specific_schema and r.specific_name = p.specific_name
            where r.routine_schema = 'public' and r.routine_name = 'platform_billing'
              and p.parameter_mode = 'OUT'),
  array['property_id','billing_status','billing_tier','last_payment_at','last_payment_inr'],
  'platform_billing returns the columns PlatformBilling.fromRow reads');
select is((select array_agg(f::text order by f::text)
             from unnest(array[
               'public.set_plan_razorpay_id(public.subscription_tier, text)',
               'public.my_resort_billing(uuid)',
               'public.platform_billing()',
               'public.billing_subscribe_state(uuid, public.subscription_tier)',
               'public.billing_subscription_opened(uuid, public.subscription_tier, text, text, text, text, timestamptz, uuid)',
               'public.billing_subscription_cancel_requested(text, boolean, text, uuid)',
               'public.billing_webhook_apply(text, timestamptz, jsonb, jsonb)']::regprocedure[]) f
            where has_function_privilege('anon', f, 'execute')),
  null, 'anon can execute none of the billing functions');
select is((select array_agg(p.proname::text order by p.proname::text)
             from unnest(array[
               'public.set_plan_razorpay_id(public.subscription_tier, text)',
               'public.my_resort_billing(uuid)',
               'public.platform_billing()',
               'public.billing_subscribe_state(uuid, public.subscription_tier)',
               'public.billing_subscription_opened(uuid, public.subscription_tier, text, text, text, text, timestamptz, uuid)',
               'public.billing_subscription_cancel_requested(text, boolean, text, uuid)',
               'public.billing_webhook_apply(text, timestamptz, jsonb, jsonb)']::regprocedure[]) f
             join pg_proc p on p.oid = f
            where has_function_privilege('authenticated', f, 'execute')),
  array['billing_subscribe_state','my_resort_billing','platform_billing','set_plan_razorpay_id'],
  'signed-in users execute only the reads and the plan id, never the billing writes');
select is((select count(*)::int
             from unnest(array[
               'public.billing_subscription_opened(uuid, public.subscription_tier, text, text, text, text, timestamptz, uuid)',
               'public.billing_subscription_cancel_requested(text, boolean, text, uuid)',
               'public.billing_webhook_apply(text, timestamptz, jsonb, jsonb)']::regprocedure[]) f
            where has_function_privilege('service_role', f, 'execute')),
  3, 'the Edge Functions (service role) execute the three billing writes');

-- A contract fixture: a current subscription with one invoice at R1.
insert into public.billing_subscriptions
  (id, property_id, tier, razorpay_plan_id, razorpay_subscription_id, status)
values ('b8200000-0000-4000-8000-000000000001', 'b8100000-0000-4000-8000-000000000001',
        'pro', 'plan_ContractPro01', 'sub_Contract000001', 'active');
insert into public.subscription_invoices
  (billing_subscription_id, tier, razorpay_payment_id, amount_inr, paid_at)
values ('b8200000-0000-4000-8000-000000000001', 'pro', 'pay_Contract000001', 7999, now());

select throws_ok($$insert into public.subscription_invoices
    (property_id, billing_subscription_id, tier, razorpay_payment_id, amount_inr, paid_at)
  values ('b8100000-0000-4000-8000-000000000002', 'b8200000-0000-4000-8000-000000000001',
          'pro', 'pay_Contract000002', 7999, now())$$,
  'P0021', null, 'an invoice always belongs to its subscription''s resort');
select throws_ok($$insert into public.billing_subscriptions
    (property_id, tier, razorpay_plan_id, razorpay_subscription_id)
  values ('b8100000-0000-4000-8000-000000000001', 'pro', 'plan_ContractPro01', 'sub_Contract000002')$$,
  '23505', null, 'a resort has one current subscription at a time');

set local role authenticated;
set local request.jwt.claims to '{"sub":"b8000000-0000-0000-0000-000000000002","role":"authenticated"}';
select is((select count(*)::int from public.billing_subscriptions), 1,
  'the owner reads their resort''s subscription');
select is((select count(*)::int from public.subscription_invoices), 1,
  'the owner reads their resort''s invoices');
select throws_ok($$insert into public.billing_subscriptions
    (property_id, tier, razorpay_plan_id, razorpay_subscription_id)
  values ('b8100000-0000-4000-8000-000000000005', 'pro', 'plan_ContractPro01', 'sub_Contract000003')$$,
  '42501', null, 'the owner cannot write a subscription directly');
select throws_ok($$update public.subscription_invoices set amount_inr = 0$$,
  '42501', null, 'the owner cannot change an invoice');
set local request.jwt.claims to '{"sub":"b8000000-0000-0000-0000-000000000003","role":"authenticated"}';
select is((select count(*)::int from public.billing_subscriptions), 0,
  'an admin reads no billing subscription (owner only)');
set local request.jwt.claims to '{"sub":"b8000000-0000-0000-0000-000000000004","role":"authenticated"}';
select is((select count(*)::int from public.subscription_invoices), 0, 'staff read no invoices');
set local request.jwt.claims to '{"sub":"b8000000-0000-0000-0000-000000000005","role":"authenticated"}';
select is((select count(*)::int from public.billing_subscriptions)
          + (select count(*)::int from public.subscription_invoices), 0,
  'another resort''s owner reads nothing');
set local request.jwt.claims to '{"sub":"b8000000-0000-0000-0000-000000000001","role":"authenticated"}';
select is((select count(*)::int from public.billing_subscriptions)
          + (select count(*)::int from public.subscription_invoices), 0,
  'the platform admin has no direct row access');
reset role;
set local request.jwt.claims to '';
delete from public.billing_subscriptions;

-- === Task 2: plan ids and the reads ========================================

set local role authenticated;
set local request.jwt.claims to '{"sub":"b8000000-0000-0000-0000-000000000002","role":"authenticated"}';
select throws_ok($$select public.set_plan_razorpay_id('pro', 'plan_ProMonthly0001')$$,
  'P0008', null, 'only the platform admin sets a plan id');
set local request.jwt.claims to '{"sub":"b8000000-0000-0000-0000-000000000001","role":"authenticated"}';
select throws_ok($$select public.set_plan_razorpay_id('pro', 'pro-monthly')$$,
  'P0005', null, 'a malformed plan id is refused with a message for the admin');
select lives_ok($$select public.set_plan_razorpay_id('pro', ' plan_ProMonthly0001 ')$$,
  'the platform admin sets Pro''s plan id (trimmed)');
select lives_ok($$select public.set_plan_razorpay_id('pro', 'plan_ProMonthly0001')$$,
  'setting the same id again is a no-op');
select throws_ok($$select public.set_plan_razorpay_id('starter', 'plan_ProMonthly0001')$$,
  'P0005', null, 'one Razorpay plan cannot back two tiers');
select lives_ok($$select public.set_plan_razorpay_id('starter', 'plan_StarterMon001')$$,
  'Starter gets its own plan id');
select lives_ok($$select public.set_plan_razorpay_id('enterprise', '')$$,
  'a blank id leaves Enterprise billed by hand');
reset role;
set local request.jwt.claims to '';
select is((select array_agg(tier::text || ':' || coalesce(razorpay_plan_id, '-') order by sort_order)
             from public.subscription_plans),
  array['starter:plan_StarterMon001','pro:plan_ProMonthly0001','enterprise:-'],
  'the plan ids are stored');
select is((select count(*)::int from public.audit_log
            where entity = 'subscription_plan' and action like 'razorpay_plan:%'),
  2, 'each real change is audited once; the no-ops are not');

-- billing_subscribe_state, as the owner.
set local role authenticated;
set local request.jwt.claims to '{"sub":"b8000000-0000-0000-0000-000000000002","role":"authenticated"}';
select throws_ok($$select public.billing_subscribe_state('b8100000-0000-4000-8000-000000000001', 'enterprise')$$,
  'P0038', null, 'a tier without a Razorpay plan cannot be paid online');
select is(public.billing_subscribe_state('b8100000-0000-4000-8000-000000000001', 'pro') ->> 'plan_id',
  'plan_ProMonthly0001', 'the state carries the tier''s plan id');
select is((public.billing_subscribe_state('b8100000-0000-4000-8000-000000000001', 'pro') ->> 'start_at')::bigint,
  pg_temp.ist(pg_temp.today() + 11),
  'a trial resort''s auto-pay starts the day after the trial ends (midnight IST)');
select is(public.billing_subscribe_state('b8100000-0000-4000-8000-000000000001', 'pro')
            - array['property_id','property_name','caller_id','notify_email','tier','plan_id','start_at'],
  '{"current": null, "stale": []}'::jsonb, 'no current subscription and nothing stale yet');
select is((select jsonb_build_object('email', s -> 'notify_email', 'caller', s -> 'caller_id',
                                     'name', s -> 'property_name')
             from public.billing_subscribe_state('b8100000-0000-4000-8000-000000000001', 'pro') s),
  '{"email": "bill-owner@example.com", "caller": "b8000000-0000-0000-0000-000000000002", "name": "Bill Trial"}'::jsonb,
  'the state names the owner to notify and the resort');
select is(public.billing_subscribe_state('b8100000-0000-4000-8000-000000000003', 'starter') -> 'start_at',
  'null'::jsonb,
  'a suspended resort''s owner can still set up auto-pay; no end date means it starts now');
select is(public.billing_subscribe_state('b8100000-0000-4000-8000-000000000004', 'pro') -> 'start_at',
  'null'::jsonb, 'a lapsed plan starts auto-pay straight away');
select is(public.billing_subscribe_state('b8100000-0000-4000-8000-000000000001') -> 'plan_id',
  'null'::jsonb, 'without a tier (a cancel) no plan id is needed');
set local request.jwt.claims to '{"sub":"b8000000-0000-0000-0000-000000000003","role":"authenticated"}';
select throws_ok($$select public.billing_subscribe_state('b8100000-0000-4000-8000-000000000001', 'pro')$$,
  'P0020', null, 'an admin cannot start auto-pay (owner only)');
set local request.jwt.claims to '{"sub":"b8000000-0000-0000-0000-000000000004","role":"authenticated"}';
select throws_ok($$select public.billing_subscribe_state('b8100000-0000-4000-8000-000000000001', 'pro')$$,
  'P0020', null, 'staff cannot start auto-pay');
set local request.jwt.claims to '{"sub":"b8000000-0000-0000-0000-000000000006","role":"authenticated"}';
select throws_ok($$select public.billing_subscribe_state('b8100000-0000-4000-8000-000000000001', 'pro')$$,
  'P0020', null, 'a guest cannot start auto-pay');
set local request.jwt.claims to '{"sub":"b8000000-0000-0000-0000-000000000001","role":"authenticated"}';
select throws_ok($$select public.billing_subscribe_state('b8100000-0000-4000-8000-000000000001', 'pro')$$,
  'P0020', null, 'the platform admin cannot start a resort''s auto-pay');
set local request.jwt.claims to '{"sub":"b8000000-0000-0000-0000-000000000005","role":"authenticated"}';
select throws_ok($$select public.billing_subscribe_state('b8100000-0000-4000-8000-000000000001', 'pro')$$,
  'P0020', null, 'another resort''s owner cannot start it');
select is((public.billing_subscribe_state('b8100000-0000-4000-8000-000000000002', 'pro') ->> 'start_at')::bigint,
  pg_temp.ist(pg_temp.today() + 6),
  'a paid resort''s auto-pay starts the day after its paid period');

-- The reads, over a current subscription, a replaced one still live, and
-- two payments.
reset role;
set local request.jwt.claims to '';
insert into public.billing_subscriptions
  (id, property_id, tier, razorpay_plan_id, razorpay_subscription_id, status, superseded_at)
values ('b8200000-0000-4000-8000-000000000011', 'b8100000-0000-4000-8000-000000000001',
        'starter', 'plan_StarterMon001', 'sub_ReadOld000001', 'active', now());
insert into public.billing_subscriptions
  (id, property_id, tier, razorpay_plan_id, razorpay_subscription_id, status, short_url, current_end)
values ('b8200000-0000-4000-8000-000000000012', 'b8100000-0000-4000-8000-000000000001',
        'pro', 'plan_ProMonthly0001', 'sub_ReadCheck00001', 'active', 'https://rzp.io/i/read',
        now() + interval '20 days');
insert into public.subscription_invoices
  (billing_subscription_id, tier, razorpay_payment_id, amount_inr, paid_at)
values
  ('b8200000-0000-4000-8000-000000000011', 'starter', 'pay_ReadOld000001', 2999, now() - interval '40 days'),
  ('b8200000-0000-4000-8000-000000000012', 'pro', 'pay_ReadNew000001', 7999, now() - interval '10 days');

set local role authenticated;
set local request.jwt.claims to '{"sub":"b8000000-0000-0000-0000-000000000002","role":"authenticated"}';
select is((select jsonb_build_object('current', s -> 'current' -> 'razorpay_subscription_id',
                                     'stale', s -> 'stale')
             from public.billing_subscribe_state('b8100000-0000-4000-8000-000000000001', 'pro') s),
  '{"current": "sub_ReadCheck00001", "stale": ["sub_ReadOld000001"]}'::jsonb,
  'the state names the current subscription and the replaced one still live');
select is((select billing_status || '|' || billing_tier::text || '|' || cancel_at_cycle_end::text
                  || '|' || last_payment_inr::text
             from public.my_resort_billing('b8100000-0000-4000-8000-000000000001')),
  'active|pro|false|7999.00', 'the owner reads auto-pay state and the latest payment');
select is((select count(*)::int from public.my_resort_billing('b8100000-0000-4000-8000-000000000005')),
  0, 'a resort that never had auto-pay has no billing row');
set local request.jwt.claims to '{"sub":"b8000000-0000-0000-0000-000000000003","role":"authenticated"}';
select throws_ok($$select * from public.my_resort_billing('b8100000-0000-4000-8000-000000000001')$$,
  'P0020', null, 'an admin cannot read billing (owner only)');
set local request.jwt.claims to '{"sub":"b8000000-0000-0000-0000-000000000002","role":"authenticated"}';
select throws_ok($$select * from public.platform_billing()$$,
  'P0008', null, 'only the platform admin reads the console''s billing');
set local request.jwt.claims to '{"sub":"b8000000-0000-0000-0000-000000000001","role":"authenticated"}';
select is((select array_agg(property_id::text) from public.platform_billing()),
  array['b8100000-0000-4000-8000-000000000001'],
  'the console lists only resorts with auto-pay or payments');
select is((select billing_status || '|' || last_payment_inr::text from public.platform_billing()),
  'active|7999.00', 'the console sees the latest payment');
reset role;
set local request.jwt.claims to '';
delete from public.billing_subscriptions;

-- === Task 3: opening and cancelling subscriptions ==========================

set local role authenticated;
set local request.jwt.claims to '{"sub":"b8000000-0000-0000-0000-000000000002","role":"authenticated"}';
select throws_ok($$select public.billing_subscription_opened('b8100000-0000-4000-8000-000000000001',
    'starter', 'plan_StarterMon001', 'sub_FirstOpen00001', 'created', null, null,
    'b8000000-0000-0000-0000-000000000002')$$,
  '42501', null, 'a signed-in user cannot record a subscription');
select throws_ok($$select public.billing_subscription_cancel_requested('sub_FirstOpen00001', true, 'active')$$,
  '42501', null, 'a signed-in user cannot record a cancellation');
reset role;
set local request.jwt.claims to '';

set local role service_role;
select throws_ok($$select public.billing_subscription_opened('b8100000-0000-4000-8000-000000000001',
    null, 'plan_StarterMon001', 'sub_FirstOpen00001', 'created', null, null, null)$$,
  'P0005', null, 'a tier is required');
select throws_ok($$select public.billing_subscription_opened('b8100000-0000-4000-8000-0000000000ff',
    'starter', 'plan_StarterMon001', 'sub_FirstOpen00001', 'created', null, null, null)$$,
  'P0002', null, 'an unknown resort is refused');
select is(public.billing_subscription_opened('b8100000-0000-4000-8000-000000000001',
            'starter', 'plan_StarterMon001', 'sub_FirstOpen00001', 'created',
            'https://rzp.io/i/first', now() + interval '11 days',
            'b8000000-0000-0000-0000-000000000002') -> 'stale',
  '[]'::jsonb, 'the first subscription replaces nothing');
select is(public.billing_subscription_opened('b8100000-0000-4000-8000-000000000001',
            'starter', 'plan_StarterMon001', 'sub_FirstOpen00001', 'created',
            'https://rzp.io/i/first', null, null) ->> 'id',
          public.billing_subscription_opened('b8100000-0000-4000-8000-000000000001',
            'starter', 'plan_StarterMon001', 'sub_FirstOpen00001', 'created',
            'https://rzp.io/i/first', null, null) ->> 'id',
  'recording the same subscription again returns the same row');
select is(public.billing_subscription_opened('b8100000-0000-4000-8000-000000000001',
            'pro', 'plan_ProMonthly0001', 'sub_SecondOpen0001', 'created',
            'https://rzp.io/i/second', null, 'b8000000-0000-0000-0000-000000000002') -> 'stale',
  '["sub_FirstOpen00001"]'::jsonb,
  'a new subscription supersedes the current one and names it for cancelling');
select throws_ok($$select public.billing_subscription_opened('b8100000-0000-4000-8000-000000000001',
    'pro', 'plan_ProMonthly0001', 'sub_ThirdOpen00001', 'weird', null, null, null)$$,
  '23514', null, 'only Razorpay''s states are stored');
select throws_ok($$select public.billing_subscription_opened('b8100000-0000-4000-8000-000000000002',
    'pro', 'plan_ProMonthly0001', 'sub_SecondOpen0001', 'created', null, null, null)$$,
  'P0021', null, 'a subscription id is never moved to another resort');
select throws_ok($$select public.billing_subscription_cancel_requested('sub_Unknown000001', true, 'active')$$,
  'P0002', null, 'cancelling an unknown subscription is refused');
select lives_ok($$select public.billing_subscription_cancel_requested('sub_FirstOpen00001', false,
    'cancelled', 'b8000000-0000-0000-0000-000000000002')$$,
  'a replaced subscription is recorded as cancelled');
select lives_ok($$select public.billing_subscription_cancel_requested('sub_SecondOpen0001', true,
    'active', 'b8000000-0000-0000-0000-000000000002')$$,
  'the current one is set to cancel at the end of its cycle');
select lives_ok($$select public.billing_subscription_cancel_requested('sub_SecondOpen0001', true, 'bogus')$$,
  'an unknown status from Razorpay keeps the stored one');
reset role;

select is((select array_agg(razorpay_subscription_id || ':' || status || ':' || cancel_at_cycle_end::text
                            || ':' || (superseded_at is not null)::text
                            order by razorpay_subscription_id)
             from public.billing_subscriptions),
  array['sub_FirstOpen00001:cancelled:false:true','sub_SecondOpen0001:active:true:false'],
  'one current subscription; the replaced one is cancelled');
select is((select array[count(*) filter (where action like 'billing:opened %'),
                        count(*) filter (where action like 'billing:cancel_requested %')]::int[]
             from public.audit_log
            where entity = 'subscription' and property_id = 'b8100000-0000-4000-8000-000000000001'),
  array[2, 3], 'each opening and each cancellation is audited');
select is((select created_by::text || '|' || (start_at is not null)::text
             from public.billing_subscriptions where razorpay_subscription_id = 'sub_FirstOpen00001'),
  'b8000000-0000-0000-0000-000000000002|true',
  'the first recording is kept: who opened it and when it starts');

set local role authenticated;
set local request.jwt.claims to '{"sub":"b8000000-0000-0000-0000-000000000002","role":"authenticated"}';
select is((select jsonb_build_object('cancel', s -> 'current' -> 'cancel_at_cycle_end', 'stale', s -> 'stale')
             from public.billing_subscribe_state('b8100000-0000-4000-8000-000000000001', 'pro') s),
  '{"cancel": true, "stale": []}'::jsonb,
  'the owner sees the pending cancel, and nothing is left to clean up');
reset role;
set local request.jwt.claims to '';
delete from public.billing_subscriptions;

-- === Task 4: webhook events ================================================

-- Razorpay's subscription entity, and a captured payment of p_paise.
create function pg_temp.sub(p_id text, p_status text, p_start bigint default null,
                            p_end bigint default null)
returns jsonb language sql immutable as $f$
  select jsonb_build_object('id', p_id, 'entity', 'subscription', 'status', p_status,
                            'current_start', p_start, 'current_end', p_end,
                            'short_url', 'https://rzp.io/i/' || p_id)
$f$;
create function pg_temp.pay(p_id text, p_paise int)
returns jsonb language sql immutable as $f$
  select jsonb_build_object('id', p_id, 'entity', 'payment', 'amount', p_paise,
                            'currency', 'INR', 'status', 'captured',
                            'invoice_id', 'inv_' || substr(p_id, 5), 'created_at', 1790000000)
$f$;

insert into public.billing_subscriptions
  (property_id, tier, razorpay_plan_id, razorpay_subscription_id, status, superseded_at)
values
  ('b8100000-0000-4000-8000-000000000001', 'pro', 'plan_ProMonthly0001', 'sub_WebhookOne0001', 'created', null),
  ('b8100000-0000-4000-8000-000000000002', 'pro', 'plan_ProMonthly0001', 'sub_WebhookTwo0001', 'active', null),
  ('b8100000-0000-4000-8000-000000000002', 'starter', 'plan_StarterMon001', 'sub_WebhookOld0001', 'active', now()),
  ('b8100000-0000-4000-8000-000000000003', 'starter', 'plan_StarterMon001', 'sub_WebhookThree01', 'authenticated', null),
  ('b8100000-0000-4000-8000-000000000004', 'pro', 'plan_ProMonthly0001', 'sub_WebhookFour001', 'active', null);

-- A: authorise and charge R1's trial, twice, then a late charge.
set local role service_role;
select is(public.billing_webhook_apply('subscription.activated', now(),
            pg_temp.sub('sub_Unknown000001', 'active'), null) ->> 'outcome',
  'ignored', 'an event for a subscription this app did not create is ignored');
select is(public.billing_webhook_apply('subscription.authenticated', now() - interval '1 hour',
            pg_temp.sub('sub_WebhookOne0001', 'authenticated'), null) ->> 'outcome',
  'updated', 'authorising only updates the stored state');
select is(public.billing_webhook_apply('subscription.charged', now(),
            pg_temp.sub('sub_WebhookOne0001', 'active',
                        pg_temp.ist(pg_temp.today() + 11), pg_temp.ist(pg_temp.today() + 41)),
            pg_temp.pay('pay_WebhookOne0001', 799900)) ->> 'outcome',
  'charged', 'a successful charge is applied');
select is(public.billing_webhook_apply('subscription.charged', now(),
            pg_temp.sub('sub_WebhookOne0001', 'active',
                        pg_temp.ist(pg_temp.today() + 11), pg_temp.ist(pg_temp.today() + 41)),
            pg_temp.pay('pay_WebhookOne0001', 799900)) ->> 'outcome',
  'duplicate', 'the same charge delivered twice is recorded once');
select is(public.billing_webhook_apply('subscription.charged', now() - interval '1 day',
            pg_temp.sub('sub_WebhookOne0001', 'active',
                        pg_temp.ist(pg_temp.today() - 19), pg_temp.ist(pg_temp.today() + 10)),
            pg_temp.pay('pay_WebhookLate001', 799900)) ->> 'outcome',
  'charged', 'a late charge is still recorded');
reset role;

select is((select tier::text || '|' || amount_inr::text || '|' || period_start::text || '|'
                  || period_end::text || '|' || property_id::text
             from public.subscription_invoices where razorpay_payment_id = 'pay_WebhookOne0001'),
  'pro|7999.00|' || (pg_temp.today() + 11)::text || '|' || (pg_temp.today() + 40)::text
    || '|b8100000-0000-4000-8000-000000000001',
  'the invoice holds the rupee amount, the paid period in IST, and the resort');
select is((select count(*)::int from public.subscription_invoices
            where razorpay_payment_id = 'pay_WebhookOne0001'),
  1, 'a repeated charge adds no second invoice');
select is((select tier::text || '|' || status::text || '|' || coalesce(trial_ends_on::text, '-')
                  || '|' || paid_through::text
             from public.resort_subscriptions where property_id = 'b8100000-0000-4000-8000-000000000001'),
  'pro|active|-|' || (pg_temp.today() + 40)::text,
  'the charge turned the Starter trial into Pro paid through the period; the late charge did not move it back');
select is((select count(*)::int from public.audit_log
            where entity = 'subscription' and action = 'billing:charged pay_WebhookOne0001'),
  1, 'the charge is audited');
select is((select status || '|' || (current_end = to_timestamp(pg_temp.ist(pg_temp.today() + 41)))::text
             from public.billing_subscriptions where razorpay_subscription_id = 'sub_WebhookOne0001'),
  'active|true', 'the stored state follows the newest event, not the late one');

-- B: halted, stale, cancelled, and a replaced subscription that still charges.
set local role service_role;
select is(public.billing_webhook_apply('subscription.charged', now(),
            pg_temp.sub('sub_WebhookFour001', 'active'),
            pg_temp.pay('pay_WebhookFour001', 799900)) ->> 'outcome',
  'charged', 'a charge without a period is applied');
select is(public.billing_webhook_apply('subscription.halted', now() + interval '1 minute',
            pg_temp.sub('sub_WebhookFour001', 'halted'), null) ->> 'outcome',
  'lapsed', 'Razorpay giving up makes the plan lapse');
select is(public.billing_webhook_apply('subscription.halted', now() - interval '2 days',
            pg_temp.sub('sub_WebhookOne0001', 'halted'), null) ->> 'outcome',
  'stale', 'a halted event older than the last one applied changes nothing');
select is(public.billing_webhook_apply('subscription.cancelled', now(),
            pg_temp.sub('sub_WebhookThree01', 'cancelled'), null) ->> 'outcome',
  'updated', 'cancelling a subscription that never charged leaves the plan alone');
select is(public.billing_webhook_apply('subscription.cancelled', now() + interval '1 minute',
            pg_temp.sub('sub_WebhookOne0001', 'cancelled'), null) ->> 'outcome',
  'cancelled', 'cancelling a paid subscription cancels the plan');
select is(public.billing_webhook_apply('subscription.charged', now(),
            pg_temp.sub('sub_WebhookOld0001', 'active'),
            pg_temp.pay('pay_WebhookOld0001', 299900)) - 'property_id',
  '{"outcome": "charged", "cancel_subscription_id": "sub_WebhookOld0001"}'::jsonb,
  'a replaced subscription that still charges is recorded and handed back for cancelling');
select throws_ok($$select public.billing_webhook_apply('subscription.charged', now(),
    pg_temp.sub('sub_WebhookTwo0001', 'active'), null)$$,
  'P0005', null, 'a charged event without its payment is refused');
reset role;

select is((select period_end from public.subscription_invoices
            where razorpay_payment_id = 'pay_WebhookFour001'),
  ((pg_temp.today() - 1) + interval '1 month')::date,
  'without a period, a charge pays one month past yesterday for a lapsed plan');
select is((select paid_through::text || '|'
                  || public.subscription_lapsed(status, trial_ends_on, paid_through)::text
             from public.resort_subscriptions where property_id = 'b8100000-0000-4000-8000-000000000004'),
  (pg_temp.today() - 1)::text || '|true', 'halted forces the plan to lapse');
select is((select tier::text || '|' || status::text || '|' || coalesce(trial_ends_on::text, '-')
                  || '|' || paid_through::text
             from public.resort_subscriptions where property_id = 'b8100000-0000-4000-8000-000000000001'),
  'pro|cancelled|-|' || (pg_temp.today() + 40)::text,
  'the stale halted did nothing; the cancel kept the paid-through date');
select is((select status::text || '|' || coalesce(paid_through::text, '-')
             from public.resort_subscriptions where property_id = 'b8100000-0000-4000-8000-000000000003'),
  'active|-', 'an abandoned checkout never cancels the plan');
select is((select tier::text || '|' || status::text || '|' || paid_through::text
             from public.resort_subscriptions where property_id = 'b8100000-0000-4000-8000-000000000002'),
  'pro|active|' || (pg_temp.today() + 5)::text,
  'a charge on a replaced subscription does not change the plan');
select is((select count(*)::int from public.subscription_invoices
            where property_id = 'b8100000-0000-4000-8000-000000000002'),
  1, 'but its invoice is recorded at the right resort');
select is((select array[count(*) filter (where action = 'billing:halted sub_WebhookFour001'),
                        count(*) filter (where action = 'billing:cancelled sub_WebhookOne0001')]::int[]
             from public.audit_log where entity = 'subscription'),
  array[1, 1], 'the lapse and the cancel are audited');

-- Reads after the events.
set local role authenticated;
set local request.jwt.claims to '{"sub":"b8000000-0000-0000-0000-000000000002","role":"authenticated"}';
select is((select count(*)::int from public.subscription_invoices), 3,
  'the owner reads the invoices of their own resorts only');
set local request.jwt.claims to '{"sub":"b8000000-0000-0000-0000-000000000005","role":"authenticated"}';
select is((select count(*)::int from public.subscription_invoices), 1,
  'the other owner reads their one invoice');
set local request.jwt.claims to '{"sub":"b8000000-0000-0000-0000-000000000001","role":"authenticated"}';
select is((select billing_status || '|' || last_payment_inr::text from public.platform_billing()
            where property_id = 'b8100000-0000-4000-8000-000000000001'),
  'cancelled|7999.00', 'the console shows the cancelled auto-pay and its last payment');
select throws_ok($$select public.billing_webhook_apply('subscription.charged', now(),
    '{"id":"sub_WebhookTwo0001"}'::jsonb, '{"id":"pay_Forged000001","amount":1}'::jsonb)$$,
  '42501', null, 'a signed-in user cannot post webhook events');
reset role;
set local request.jwt.claims to '';

select * from finish();
rollback;
