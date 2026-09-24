-- Subscriptions and tiers (REQ-08), added in 0049_subscriptions.sql. See
-- docs/superpowers/specs/2026-09-25-subscriptions-design.md.
--
-- One file, built up by the plan's database tasks in order: each section
-- relies on the state the sections before it leave behind.
--
-- Fixtures: a platform admin; resort "Sub Paid" (P1) with an owner, an
-- admin, a staff member and an accountant; a second owner who owns "Sub
-- Open" (P2), "Sub Suspended" (P8) and "Sub None" (P9); and a guest with
-- no membership. P1-P9 cover every case the counts must handle:
--   P1 Pro, active, paid until today      -> active, in MRR
--   P2 Enterprise, active, no end date    -> active, in MRR
--   P3 Starter trial ending in 5 days     -> active, a live trial
--   P4 Starter trial that ended yesterday -> subscribed, lapsed
--   P5 Pro, active, paid until 3 days ago -> subscribed, lapsed
--   P6 Pro, cancelled                     -> not subscribed
--   P7 archived resort, Enterprise active -> counts for nothing
--   P8 suspended resort, Starter active   -> active, in MRR
--   P9 no subscription row                -> "No plan", counts for nothing
begin;
select plan(21);

-- "Today" as the subscription functions see it.
create function pg_temp.today() returns date
language sql stable as $f$ select (now() at time zone 'Asia/Kolkata')::date $f$;

-- platform_summary counts every resort in the database. Start from no
-- subscription rows so the seeded resort (and any other) counts for nothing.
delete from public.resort_subscriptions;

insert into auth.users (id, email) values
  ('f0000000-0000-0000-0000-000000000001','sub-platform@example.com'),
  ('f0000000-0000-0000-0000-000000000002','sub-owner@example.com'),
  ('f0000000-0000-0000-0000-000000000003','sub-admin@example.com'),
  ('f0000000-0000-0000-0000-000000000004','sub-staff@example.com'),
  ('f0000000-0000-0000-0000-000000000005','sub-accountant@example.com'),
  ('f0000000-0000-0000-0000-000000000006','sub-other-owner@example.com'),
  ('f0000000-0000-0000-0000-000000000007','sub-guest@example.com');
update public.profiles set role = 'platform_admin'
  where id = 'f0000000-0000-0000-0000-000000000001';

insert into public.properties (id, name, slug, status) values
  ('f1000000-0000-4000-8000-000000000001','Sub Paid','sub-paid','active'),
  ('f1000000-0000-4000-8000-000000000002','Sub Open','sub-open','active'),
  ('f1000000-0000-4000-8000-000000000003','Sub Trial','sub-trial','active'),
  ('f1000000-0000-4000-8000-000000000004','Sub Trial Lapsed','sub-trial-lapsed','active'),
  ('f1000000-0000-4000-8000-000000000005','Sub Paid Lapsed','sub-paid-lapsed','active'),
  ('f1000000-0000-4000-8000-000000000006','Sub Cancelled','sub-cancelled','active'),
  ('f1000000-0000-4000-8000-000000000007','Sub Archived','sub-archived','archived'),
  ('f1000000-0000-4000-8000-000000000008','Sub Suspended','sub-suspended','suspended'),
  ('f1000000-0000-4000-8000-000000000009','Sub None','sub-none','active');

insert into public.resort_members (property_id, user_id, role) values
  ('f1000000-0000-4000-8000-000000000001','f0000000-0000-0000-0000-000000000002','owner'),
  ('f1000000-0000-4000-8000-000000000001','f0000000-0000-0000-0000-000000000003','admin'),
  ('f1000000-0000-4000-8000-000000000001','f0000000-0000-0000-0000-000000000004','staff'),
  ('f1000000-0000-4000-8000-000000000001','f0000000-0000-0000-0000-000000000005','accountant'),
  ('f1000000-0000-4000-8000-000000000002','f0000000-0000-0000-0000-000000000006','owner'),
  ('f1000000-0000-4000-8000-000000000008','f0000000-0000-0000-0000-000000000006','owner'),
  ('f1000000-0000-4000-8000-000000000009','f0000000-0000-0000-0000-000000000006','owner');

insert into public.resort_subscriptions (property_id, tier, status, trial_ends_on, paid_through) values
  ('f1000000-0000-4000-8000-000000000001','pro','active',null,pg_temp.today()),
  ('f1000000-0000-4000-8000-000000000002','enterprise','active',null,null),
  ('f1000000-0000-4000-8000-000000000003','starter','trial',pg_temp.today() + 5,null),
  ('f1000000-0000-4000-8000-000000000004','starter','trial',pg_temp.today() - 1,null),
  ('f1000000-0000-4000-8000-000000000005','pro','active',null,pg_temp.today() - 3),
  ('f1000000-0000-4000-8000-000000000006','pro','cancelled',null,null),
  ('f1000000-0000-4000-8000-000000000007','enterprise','active',null,null),
  ('f1000000-0000-4000-8000-000000000008','starter','active',null,null);

-- === Task 1: the contract ===================================================

select has_table('public', 'subscription_plans', 'subscription_plans exists');
select has_table('public', 'resort_subscriptions', 'resort_subscriptions exists');
select enum_has_labels('public', 'subscription_tier', array['starter','pro','enterprise'],
  'the tiers are starter, pro and enterprise -- no free tier');
select enum_has_labels('public', 'subscription_status', array['trial','active','cancelled'],
  'lapsed is never stored');
select is((select array_agg(tier::text || ':' || name || ':' || monthly_price_inr::int order by sort_order)
             from public.subscription_plans),
  array['starter:Starter:2999','pro:Pro:7999','enterprise:Enterprise:19999'],
  'the three plans are seeded at the placeholder prices');
select is((select array_agg(p.parameter_name::text order by p.ordinal_position)
             from information_schema.parameters p
             join information_schema.routines r
               on r.specific_schema = p.specific_schema and r.specific_name = p.specific_name
            where r.routine_schema = 'public' and r.routine_name = 'platform_resorts'
              and p.parameter_mode = 'OUT'),
  array['property_id','name','status','owner_emails','created_at',
        'bookings_30d','revenue_30d','bookings_365d','revenue_365d',
        'plan_tier','plan_name','plan_status','trial_ends_on','paid_through',
        'lapsed','monthly_price_inr','plan_notes'],
  'platform_resorts returns the columns ResortSummary.fromJson reads');
select is((select array_agg(p.parameter_name::text order by p.ordinal_position)
             from information_schema.parameters p
             join information_schema.routines r
               on r.specific_schema = p.specific_schema and r.specific_name = p.specific_name
            where r.routine_schema = 'public' and r.routine_name = 'platform_summary'
              and p.parameter_mode = 'OUT'),
  array['subscribed_count','active_count','trial_count','mrr_inr'],
  'platform_summary returns the columns PlatformTotals.fromJson reads');
select is((select array_agg(p.parameter_name::text order by p.ordinal_position)
             from information_schema.parameters p
             join information_schema.routines r
               on r.specific_schema = p.specific_schema and r.specific_name = p.specific_name
            where r.routine_schema = 'public' and r.routine_name = 'my_resort_subscription'
              and p.parameter_mode = 'OUT'),
  array['plan_tier','plan_name','plan_status','trial_ends_on','paid_through',
        'lapsed','monthly_price_inr','plan_notes'],
  'my_resort_subscription returns the columns ResortPlan.fromRow reads');
select ok(to_regprocedure('public.create_resort(text, text, public.subscription_tier, integer)') is not null,
  'create_resort takes a tier and a number of trial days');
select ok(to_regprocedure('public.create_resort(text, text)') is null,
  'the two-argument create_resort is gone, so no call is ambiguous');
select is((select array_agg(f::text order by f::text)
             from unnest(array[
               'public.platform_resorts()',
               'public.platform_summary()',
               'public.my_resort_subscription(uuid)',
               'public.create_resort(text, text, public.subscription_tier, integer)',
               'public.set_resort_subscription(uuid, public.subscription_tier, public.subscription_status, date, date, text)',
               'public.set_plan_price(public.subscription_tier, numeric)']::regprocedure[]) f
            where has_function_privilege('anon', f, 'execute')),
  null, 'anon can execute none of the subscription functions');
select is((select count(*)::int
             from unnest(array[
               'public.platform_resorts()',
               'public.platform_summary()',
               'public.my_resort_subscription(uuid)',
               'public.create_resort(text, text, public.subscription_tier, integer)',
               'public.set_resort_subscription(uuid, public.subscription_tier, public.subscription_status, date, date, text)',
               'public.set_plan_price(public.subscription_tier, numeric)']::regprocedure[]) f
            where has_function_privilege('authenticated', f, 'execute')),
  6, 'authenticated can execute all six');
select throws_ok($$insert into public.resort_subscriptions (property_id, tier, status)
  values ('f1000000-0000-4000-8000-000000000009', 'starter', 'trial')$$,
  '23514', null, 'a trial without an end date is refused by the table itself');

-- Direct reads and writes. Owners and admins read their own resort's row;
-- nobody writes directly, not even the platform admin.
set local role authenticated;
set local request.jwt.claims to '{"sub":"f0000000-0000-0000-0000-000000000002","role":"authenticated"}';
select is((select array_agg(property_id::text) from public.resort_subscriptions),
  array['f1000000-0000-4000-8000-000000000001'],
  'an owner reads only their own resort''s subscription');
select is((select count(*)::int from public.subscription_plans), 3, 'an owner reads the plans');
select throws_ok($$insert into public.resort_subscriptions (property_id, tier, status)
  values ('f1000000-0000-4000-8000-000000000009', 'enterprise', 'active')$$,
  '42501', null, 'an owner cannot write a subscription directly');
select throws_ok($$update public.resort_subscriptions set tier = 'enterprise'$$,
  '42501', null, 'an owner cannot upgrade their own plan directly');
set local request.jwt.claims to '{"sub":"f0000000-0000-0000-0000-000000000003","role":"authenticated"}';
select is((select count(*)::int from public.resort_subscriptions), 1,
  'an admin reads their resort''s subscription');
set local request.jwt.claims to '{"sub":"f0000000-0000-0000-0000-000000000004","role":"authenticated"}';
select is((select count(*)::int from public.resort_subscriptions), 0, 'staff read no subscriptions');
set local request.jwt.claims to '{"sub":"f0000000-0000-0000-0000-000000000001","role":"authenticated"}';
select is((select count(*)::int from public.resort_subscriptions), 0,
  'the platform admin has no direct row access');
select throws_ok($$update public.subscription_plans set monthly_price_inr = 0$$,
  '42501', null, 'the platform admin changes prices only through set_plan_price');
reset role;
set local request.jwt.claims to '';

select * from finish();
rollback;
