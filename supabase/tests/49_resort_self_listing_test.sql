-- Resort self-listing (P10), added in 0059_resort_self_listing.sql. See
-- docs/superpowers/specs/2026-09-25-p10-resort-self-listing-design.md.
--
-- One file, built up by the plan's database tasks in order: each section
-- relies on the state the sections before it leave behind.
--
-- Fixtures:
--   P  platform admin                       49000000-...-0001
--   A  applicant, no membership             49000000-...-0002 (Asha Applicant)
--   B  applicant, no membership             49000000-...-0003
--   G  guest, no membership                 49000000-...-0004
--   O  owner of C and D                     49000000-...-0005 (Chetan Owner)
--   M  admin of C                           49000000-...-0006
--   C  "Listing C", pending, set up by hand: an unsubmitted Pro application
--      by O, a Pro trial ending in 10 days, one active unit (Cottage 1)
--   D  "Listing D", active, Starter, paid with no end date
begin;
select plan(17);

-- "Today" as the listing functions see it.
create function pg_temp.today() returns date
language sql stable as $f$ select (now() at time zone 'Asia/Kolkata')::date $f$;

-- Rows a statement changed, run as the current role (0 when RLS filters it).
create function pg_temp.rows_affected(p_sql text) returns int
language plpgsql as $f$
declare n int;
begin
  execute p_sql;
  get diagnostics n = row_count;
  return n;
end;
$f$;

-- platform_summary counts every resort in the database. Start from no
-- subscription rows so only this file's resorts count.
delete from public.resort_subscriptions;

insert into auth.users (id, email) values
  ('49000000-0000-0000-0000-000000000001','list-platform@example.com'),
  ('49000000-0000-0000-0000-000000000002','list-applicant-a@example.com'),
  ('49000000-0000-0000-0000-000000000003','list-applicant-b@example.com'),
  ('49000000-0000-0000-0000-000000000004','list-guest@example.com'),
  ('49000000-0000-0000-0000-000000000005','list-owner-c@example.com'),
  ('49000000-0000-0000-0000-000000000006','list-admin-c@example.com');
update public.profiles set role = 'platform_admin'
  where id = '49000000-0000-0000-0000-000000000001';
update public.profiles set full_name = 'Asha Applicant'
  where id = '49000000-0000-0000-0000-000000000002';
update public.profiles set full_name = 'Chetan Owner'
  where id = '49000000-0000-0000-0000-000000000005';

insert into public.properties (id, name, slug, status, city, address, contact_phone, description) values
  ('49100000-0000-4000-8000-00000000000c','Listing C','listing-c','pending','Pune',
   '1 Hill Road, Pune','+919876543210','A quiet farm stay near the hills.'),
  ('49100000-0000-4000-8000-00000000000d','Listing D','listing-d','active',null,null,null,null);

insert into public.resort_members (property_id, user_id, role) values
  ('49100000-0000-4000-8000-00000000000c','49000000-0000-0000-0000-000000000005','owner'),
  ('49100000-0000-4000-8000-00000000000c','49000000-0000-0000-0000-000000000006','admin'),
  ('49100000-0000-4000-8000-00000000000d','49000000-0000-0000-0000-000000000005','owner');

insert into public.units (id, property_id, name, capacity_base, capacity_max) values
  ('49100000-0000-4000-8000-0000000000c1','49100000-0000-4000-8000-00000000000c','Cottage 1',2,4);

insert into public.resort_subscriptions (property_id, tier, status, trial_ends_on) values
  ('49100000-0000-4000-8000-00000000000c','pro','trial',pg_temp.today() + 10),
  ('49100000-0000-4000-8000-00000000000d','starter','active',null);

insert into public.listing_applications (property_id, applicant_id, tier) values
  ('49100000-0000-4000-8000-00000000000c','49000000-0000-0000-0000-000000000005','pro');

-- === Task 1: the contract ===================================================

select has_table('public', 'listing_applications', 'listing_applications exists');
select has_column('public', 'properties', 'city', 'properties.city exists');
select has_column('public', 'properties', 'contact_phone', 'properties.contact_phone exists');
select throws_ok($$insert into public.properties (name, slug, status) values ('Bad', 'bad-status', 'review')$$,
  '23514', null, 'status is still limited to the four known values');
select col_is_null('public', 'outbox', 'reservation_id',
  'an outbox row may have no reservation (listing messages)');
select is((select array_agg(p.parameter_name::text order by p.ordinal_position)
             from information_schema.parameters p
             join information_schema.routines r
               on r.specific_schema = p.specific_schema and r.specific_name = p.specific_name
            where r.routine_schema = 'public' and r.routine_name = 'my_listing_applications'
              and p.parameter_mode = 'OUT'),
  array['property_id','name','city','tier','property_status','created_at',
        'submitted_at','decision','decided_at','rejection_reason'],
  'my_listing_applications returns the columns ListingApplication.fromJson reads');
select is((select array_agg(p.parameter_name::text order by p.ordinal_position)
             from information_schema.parameters p
             join information_schema.routines r
               on r.specific_schema = p.specific_schema and r.specific_name = p.specific_name
            where r.routine_schema = 'public' and r.routine_name = 'listing_setup_status'
              and p.parameter_mode = 'OUT'),
  array['property_status','submitted_at','has_photos','has_unit','has_rates',
        'has_payment_settings','has_cancellation_policy','has_tax_details'],
  'listing_setup_status returns the columns ListingSetup.fromJson reads');
select is((select array_agg(p.parameter_name::text order by p.ordinal_position)
             from information_schema.parameters p
             join information_schema.routines r
               on r.specific_schema = p.specific_schema and r.specific_name = p.specific_name
            where r.routine_schema = 'public' and r.routine_name = 'platform_listing_applications'
              and p.parameter_mode = 'OUT'),
  array['property_id','name','city','address','contact_phone','description',
        'applicant_email','applicant_name','tier','created_at','submitted_at',
        'has_photos','has_unit','has_rates','has_payment_settings',
        'has_cancellation_policy','has_tax_details'],
  'platform_listing_applications returns the columns PendingListing.fromJson reads');
select ok(to_regprocedure('public.apply_for_listing(text, text, text, text, text, public.subscription_tier)') is not null,
  'apply_for_listing takes the five fields and a tier');
select is((select array_agg(f::text order by f::text)
             from unnest(array[
               'public.apply_for_listing(text, text, text, text, text, public.subscription_tier)',
               'public.my_listing_applications()',
               'public.listing_setup_status(uuid)',
               'public.submit_listing_for_review(uuid)',
               'public.platform_listing_applications()',
               'public.approve_listing(uuid)',
               'public.reject_listing(uuid, text)']::regprocedure[]) f
            where has_function_privilege('anon', f, 'execute')),
  null, 'anon can execute none of the listing functions');
select is((select count(*)::int
             from unnest(array[
               'public.apply_for_listing(text, text, text, text, text, public.subscription_tier)',
               'public.my_listing_applications()',
               'public.listing_setup_status(uuid)',
               'public.submit_listing_for_review(uuid)',
               'public.platform_listing_applications()',
               'public.approve_listing(uuid)',
               'public.reject_listing(uuid, text)']::regprocedure[]) f
            where has_function_privilege('authenticated', f, 'execute')),
  7, 'authenticated can execute all seven');
select throws_ok($$insert into public.listing_applications (property_id, applicant_id, tier)
  values ('49100000-0000-4000-8000-00000000000d', '49000000-0000-0000-0000-000000000005', 'starter')$$,
  '23505', null, 'one undecided application per user, enforced by the table');

-- Direct reads and writes: the applicant reads their own row; nobody
-- writes directly. (The resort's admin reading it needs pending access,
-- which arrives in Task 2 and is tested there.)
set local role authenticated;
set local request.jwt.claims to '{"sub":"49000000-0000-0000-0000-000000000005","role":"authenticated"}';
select is((select array_agg(property_id::text) from public.listing_applications),
  array['49100000-0000-4000-8000-00000000000c'],
  'the owner reads their resort''s application');
select throws_ok($$update public.listing_applications set submitted_at = now()$$,
  '42501', null, 'the owner cannot mark their own application submitted');
set local request.jwt.claims to '{"sub":"49000000-0000-0000-0000-000000000004","role":"authenticated"}';
select is((select count(*)::int from public.listing_applications), 0, 'a guest reads none');
set local request.jwt.claims to '{"sub":"49000000-0000-0000-0000-000000000001","role":"authenticated"}';
select is((select count(*)::int from public.listing_applications), 0,
  'the platform admin has no direct row access');
set local request.jwt.claims to '{"sub":"49000000-0000-0000-0000-000000000002","role":"authenticated"}';
select throws_ok($$insert into public.listing_applications (property_id, applicant_id, tier)
  values ('49100000-0000-4000-8000-00000000000d', '49000000-0000-0000-0000-000000000002', 'starter')$$,
  '42501', null, 'nobody inserts an application directly');
reset role;
set local request.jwt.claims to '';

select * from finish();
rollback;
