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
select plan(62);

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

-- === Task 2: reading plans, counts and MRR =================================

select is(array[
    public.subscription_lapsed('trial', pg_temp.today(), null),
    public.subscription_lapsed('trial', pg_temp.today() - 1, null),
    public.subscription_lapsed('active', null, pg_temp.today()),
    public.subscription_lapsed('active', null, pg_temp.today() - 1),
    public.subscription_lapsed('active', null, null),
    public.subscription_lapsed('cancelled', pg_temp.today() - 100, pg_temp.today() - 100)],
  array[false, true, false, true, false, false],
  'a plan is good through its end date, never lapses without one, and cancelled never lapses');

set local role authenticated;
set local request.jwt.claims to '{"sub":"f0000000-0000-0000-0000-000000000001","role":"authenticated"}';

select is((select plan_tier::text || '|' || plan_name || '|' || plan_status::text || '|'
                  || lapsed::text || '|' || monthly_price_inr::int
             from public.platform_resorts()
            where property_id = 'f1000000-0000-4000-8000-000000000001'),
  'pro|Pro|active|false|7999',
  'a resort paid until today shows its plan and price, and is not lapsed');
select is((select array_agg(name || ':' || lapsed::text order by name collate "C")
             from public.platform_resorts()
            where name like 'Sub %'),
  array['Sub Archived:false','Sub Cancelled:false','Sub None:false','Sub Open:false',
        'Sub Paid:false','Sub Paid Lapsed:true','Sub Suspended:false','Sub Trial:false',
        'Sub Trial Lapsed:true'],
  'platform_resorts flags exactly the lapsed trial and the lapsed paid plan');
select is((select plan_status::text || '|' || (trial_ends_on - pg_temp.today())::text
             from public.platform_resorts()
            where property_id = 'f1000000-0000-4000-8000-000000000003'),
  'trial|5', 'a trial shows its end date');
select ok((select plan_tier is null and plan_name is null and plan_status is null
                  and monthly_price_inr is null and not lapsed
             from public.platform_resorts()
            where property_id = 'f1000000-0000-4000-8000-000000000009'),
  'a resort with no subscription row shows no plan');
select is((select array[subscribed_count, active_count, trial_count]
             from public.platform_summary()),
  array[6, 4, 1],
  'subscribed leaves out cancelled, archived and plan-less resorts; active also leaves out the two lapsed; one live trial');
select is((select mrr_inr from public.platform_summary()), 30997::numeric,
  'MRR is Pro 7999 + Enterprise 19999 + the suspended resort''s Starter 2999: no trials, lapsed, cancelled or archived');

-- The owner of P1.
set local request.jwt.claims to '{"sub":"f0000000-0000-0000-0000-000000000002","role":"authenticated"}';
select throws_ok($$select * from public.platform_summary()$$,
  'P0008', null, 'an owner cannot read the platform totals');
select is((select plan_tier::text || '|' || plan_status::text || '|' || lapsed::text || '|' || paid_through::text
             from public.my_resort_subscription('f1000000-0000-4000-8000-000000000001')),
  'pro|active|false|' || pg_temp.today()::text, 'an owner reads their own plan');
select throws_ok($$select * from public.my_resort_subscription('f1000000-0000-4000-8000-000000000002')$$,
  'P0020', null, 'an owner cannot read another resort''s plan');

-- P1's admin, staff member and accountant.
set local request.jwt.claims to '{"sub":"f0000000-0000-0000-0000-000000000003","role":"authenticated"}';
select is((select count(*)::int
             from public.my_resort_subscription('f1000000-0000-4000-8000-000000000001')),
  1, 'an admin reads their resort''s plan');
set local request.jwt.claims to '{"sub":"f0000000-0000-0000-0000-000000000004","role":"authenticated"}';
select throws_ok($$select * from public.my_resort_subscription('f1000000-0000-4000-8000-000000000001')$$,
  'P0020', null, 'staff cannot read the plan');
select throws_ok($$select * from public.platform_summary()$$,
  'P0008', null, 'staff cannot read the platform totals');
set local request.jwt.claims to '{"sub":"f0000000-0000-0000-0000-000000000005","role":"authenticated"}';
select throws_ok($$select * from public.my_resort_subscription('f1000000-0000-4000-8000-000000000001')$$,
  'P0020', null, 'an accountant cannot read the plan');

-- The owner of P2, P8 (suspended) and P9 (no plan).
set local request.jwt.claims to '{"sub":"f0000000-0000-0000-0000-000000000006","role":"authenticated"}';
select is((select plan_status::text
             from public.my_resort_subscription('f1000000-0000-4000-8000-000000000008')),
  'active', 'the owner of a suspended resort still reads their plan');
select is((select count(*)::int
             from public.my_resort_subscription('f1000000-0000-4000-8000-000000000009')),
  0, 'a resort with no plan returns no row');

-- The platform admin is nobody's member.
set local request.jwt.claims to '{"sub":"f0000000-0000-0000-0000-000000000001","role":"authenticated"}';
select throws_ok($$select * from public.my_resort_subscription('f1000000-0000-4000-8000-000000000001')$$,
  'P0020', null, 'the platform admin reads plans through platform_resorts, not as a member');
reset role;
set local request.jwt.claims to '';

-- === Task 3: creating resorts, changing plans and prices ===================

set local role authenticated;
set local request.jwt.claims to '{"sub":"f0000000-0000-0000-0000-000000000001","role":"authenticated"}';

select lives_ok($$select public.create_resort('Sub New Trial', 'sub-other-owner@example.com')$$,
  'create_resort with only a name and an owner still works');
select is((select plan_tier::text || '|' || plan_status::text || '|' || (trial_ends_on - pg_temp.today())::text
             from public.platform_resorts() where name = 'Sub New Trial'),
  'starter|trial|30', 'by default a new resort starts a 30-day Starter trial');
select lives_ok($$select public.create_resort('Sub New Paid', 'sub-other-owner@example.com', 'pro', 0)$$,
  'create_resort with no trial');
select is((select plan_tier::text || '|' || plan_status::text || '|' || coalesce(paid_through::text, 'none')
             from public.platform_resorts() where name = 'Sub New Paid'),
  'pro|active|none', 'with no trial a new resort starts active with no end date');
select throws_ok($$select public.create_resort('Sub Bad', 'sub-other-owner@example.com', 'pro', -1)$$,
  'P0005', null, 'negative trial days are refused');
select throws_ok($$select public.create_resort('Sub Bad', 'sub-other-owner@example.com', 'pro', 366)$$,
  'P0005', null, 'a trial longer than a year is refused');
select throws_ok($$select public.create_resort('Sub Bad', 'sub-other-owner@example.com', null, 30)$$,
  'P0005', null, 'a new resort needs a tier');

-- P9 has no plan yet: set_resort_subscription creates the row.
select lives_ok($$select public.set_resort_subscription('f1000000-0000-4000-8000-000000000009',
  'enterprise', 'trial', pg_temp.today() + 14, pg_temp.today() + 99, '   ')$$,
  'set_resort_subscription gives a plan-less resort a plan');
select is((select plan_tier::text || '|' || plan_status::text || '|' || (trial_ends_on - pg_temp.today())::text
                  || '|' || coalesce(paid_through::text, 'none') || '|' || coalesce(plan_notes, 'none')
             from public.platform_resorts()
            where property_id = 'f1000000-0000-4000-8000-000000000009'),
  'enterprise|trial|14|none|none', 'a trial keeps only its end date, and blank notes are dropped');
-- P4's trial lapsed yesterday: the admin records a payment.
select lives_ok($$select public.set_resort_subscription('f1000000-0000-4000-8000-000000000004',
  'pro', 'active', pg_temp.today() + 3, pg_temp.today() + 30, 'Paid by UPI')$$,
  'the platform admin converts a lapsed trial into a paid plan');
select is((select plan_tier::text || '|' || plan_status::text || '|' || lapsed::text || '|'
                  || coalesce(trial_ends_on::text, 'none') || '|'
                  || (paid_through - pg_temp.today())::text || '|' || plan_notes
             from public.platform_resorts()
            where property_id = 'f1000000-0000-4000-8000-000000000004'),
  'pro|active|false|none|30|Paid by UPI', 'the paid plan runs 30 days, drops the trial date and is no longer lapsed');
select throws_ok($$select public.set_resort_subscription('f1000000-0000-4000-8000-000000000003', 'pro', 'trial')$$,
  'P0005', null, 'a trial needs an end date');
select throws_ok($$select public.set_resort_subscription('f1000000-0000-4000-8000-000000000003', null, 'active')$$,
  'P0005', null, 'a plan needs a tier');
select throws_ok($$select public.set_resort_subscription('00000000-0000-4000-8000-000000000000', 'pro', 'active')$$,
  'P0002', null, 'an unknown resort is not found');

select lives_ok($$select public.set_plan_price('pro', 8999)$$, 'the platform admin changes the Pro price');
select is((select array[subscribed_count, active_count, trial_count] from public.platform_summary()),
  array[9, 8, 3], 'the two new resorts and the plans set above are counted');
select is((select mrr_inr from public.platform_summary()), 49995::numeric,
  'MRR follows the new Pro price: three Pro at 8999 + Enterprise 19999 + Starter 2999');
select throws_ok($$select public.set_plan_price('pro', -1)$$,
  'P0005', null, 'a negative price is refused');
select throws_ok($$update public.resort_subscriptions set status = 'cancelled'$$,
  '42501', null, 'the platform admin writes subscriptions only through the functions');

-- The owner of P1 cannot touch plans or prices.
set local request.jwt.claims to '{"sub":"f0000000-0000-0000-0000-000000000002","role":"authenticated"}';
select throws_ok($$select public.set_resort_subscription('f1000000-0000-4000-8000-000000000001', 'enterprise', 'active')$$,
  'P0008', null, 'an owner cannot change their own plan');
select throws_ok($$select public.set_plan_price('starter', 1)$$,
  'P0008', null, 'an owner cannot change prices');
reset role;
set local request.jwt.claims to '';

select is((select count(*)::int from public.audit_log
            where entity = 'subscription'
              and entity_id = 'f1000000-0000-4000-8000-000000000004'
              and property_id = 'f1000000-0000-4000-8000-000000000004'
              and before ->> 'status' = 'trial' and after ->> 'status' = 'active'),
  1, 'set_resort_subscription writes an audit row with before and after');
select is((select count(*)::int from public.audit_log a
             join public.properties p on p.id = a.entity_id
            where a.entity = 'subscription' and a.action = 'subscription:create'
              and p.name in ('Sub New Trial', 'Sub New Paid')),
  2, 'create_resort audits the subscription it starts');
select is((select count(*)::int from public.audit_log
            where entity = 'subscription_plan' and property_id is null
              and action = 'price:7999.00->8999.00'),
  1, 'set_plan_price writes a platform audit row');

select * from finish();
rollback;
