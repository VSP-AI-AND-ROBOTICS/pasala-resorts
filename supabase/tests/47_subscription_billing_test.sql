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
select plan(20);

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

select * from finish();
rollback;
