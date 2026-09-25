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
select plan(111);

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

-- === Task 2: pending resorts and applying ==================================

-- A pending resort is set up by its members exactly like an active one.
set local role authenticated;
set local request.jwt.claims to '{"sub":"49000000-0000-0000-0000-000000000005","role":"authenticated"}';
select ok(public.has_resort_role('49100000-0000-4000-8000-00000000000c', true, 'owner'),
  'an owner may write at their pending resort');
select lives_ok($$select public.assert_resort_role('49100000-0000-4000-8000-00000000000c', true, 'owner','admin')$$,
  'assert_resort_role lets the owner write at a pending resort');
select is(pg_temp.rows_affected($$update public.properties
    set description = 'A quiet farm stay near the hills, with a pool.'
  where id = '49100000-0000-4000-8000-00000000000c'$$), 1,
  'the owner edits their pending resort');
select lives_ok($$insert into public.units (id, property_id, name, capacity_base, capacity_max)
  values ('49100000-0000-4000-8000-0000000000c2','49100000-0000-4000-8000-00000000000c','Cottage 2',2,4)$$,
  'the owner adds a unit at a pending resort');
set local request.jwt.claims to '{"sub":"49000000-0000-0000-0000-000000000006","role":"authenticated"}';
select is((select count(*)::int from public.listing_applications), 1,
  'the resort''s admin reads the application of their pending resort');
select ok(public.has_resort_role('49100000-0000-4000-8000-00000000000c', true, 'admin'),
  'an admin may write there too');

-- Guests and anon see nothing and book nothing.
reset role;
set local request.jwt.claims to '';
set local role anon;
select is((select count(*)::int from public.properties
            where id = '49100000-0000-4000-8000-00000000000c'), 0,
  'anon cannot see a pending resort');
select is((select count(*)::int from public.units
            where property_id = '49100000-0000-4000-8000-00000000000c'), 0,
  'anon cannot see its units');
reset role;
set local role authenticated;
set local request.jwt.claims to '{"sub":"49000000-0000-0000-0000-000000000004","role":"authenticated"}';
select is((select count(*)::int from public.properties
            where id = '49100000-0000-4000-8000-00000000000c'), 0,
  'a signed-in guest cannot see it either');
select throws_ok($$select public.get_quote('49100000-0000-4000-8000-0000000000c1',
    tstzrange('2027-05-01 14:00+05:30','2027-05-02 11:00+05:30','[)'), 2)$$,
  'P0022', null, 'a pending resort gives no quote');
select throws_ok($$select public.create_hold('49100000-0000-4000-8000-0000000000c1',
    '2027-05-01', '2027-05-02', 2)$$,
  'P0022', null, 'a pending resort takes no booking');

-- Applying.
set local request.jwt.claims to '{"sub":"49000000-0000-0000-0000-000000000001","role":"authenticated"}';
select throws_ok($$select public.apply_for_listing('Platform Stay', 'Goa', '1 Beach Road, Goa',
    '+91 98765 43210', 'A platform admin should not be able to apply.', 'starter')$$,
  'P0008', null, 'the platform admin adds resorts from the console, not by applying');
set local request.jwt.claims to '{"sub":"49000000-0000-0000-0000-000000000002","role":"authenticated"}';
select throws_ok($$select public.apply_for_listing(' ', 'Nashik', '12 Vineyard Road, Nashik',
    '+91 98765 43210', 'Vineyard cottages with a pool and a view.', 'pro')$$,
  'P0005', 'Enter the resort name (2 to 80 characters).', 'a blank name is refused');
select throws_ok($$select public.apply_for_listing('Green Acres', 'Nashik', '12 Vineyard Road, Nashik',
    '12345', 'Vineyard cottages with a pool and a view.', 'pro')$$,
  'P0005', 'Enter a contact phone number, e.g. +91 98765 43210.', 'a short phone number is refused');
select throws_ok($$select public.apply_for_listing('Green Acres', 'Nashik', '12 Vineyard Road, Nashik',
    '+91 98765 43210', 'Nice place', 'pro')$$,
  'P0005', 'Describe the resort in 20 to 500 characters.', 'a too-short description is refused');
select throws_ok($$select public.apply_for_listing('Green Acres', 'Nashik', '12 Vineyard Road, Nashik',
    '+91 98765 43210', 'Vineyard cottages with a pool and a view.', null)$$,
  'P0005', 'Choose a plan.', 'a missing plan is refused');
select ok(set_config('app.list_a',
    public.apply_for_listing('  Green Acres ', 'Nashik', ' 12 Vineyard Road, Nashik ',
      '+91 98765-43210', 'Vineyard cottages with a pool and a view.', 'pro')::text,
    true) is not null,
  'applicant A applies');
select throws_ok($$select public.apply_for_listing('Second Stay', 'Nashik', '14 Vineyard Road, Nashik',
    '+91 98765 43210', 'A second resort while the first one is pending.', 'starter')$$,
  'P0040', 'You already have a resort waiting for review.',
  'one open application per user');
select is((select concat_ws('|', name, city, tier::text, property_status,
                            (submitted_at is null)::text, coalesce(decision, 'none'))
             from public.my_listing_applications()),
  'Green Acres|Nashik|pro|pending|true|none', 'A sees their application');
select ok(public.has_resort_role(current_setting('app.list_a')::uuid, true, 'owner'),
  'A owns the new resort and can set it up');
set local request.jwt.claims to '{"sub":"49000000-0000-0000-0000-000000000003","role":"authenticated"}';
select ok(set_config('app.list_b',
    public.apply_for_listing('Green Acres', 'Lonavala', '5 Lake Road, Lonavala',
      '9876501234', 'Lakeside tents and a big lawn for events.')::text,
    true) is not null,
  'applicant B applies with the default plan');
select is((select count(*)::int from public.my_listing_applications()), 1,
  'B sees only their own application');
reset role;
set local request.jwt.claims to '';

select is((select concat_ws('|', status, slug, city, contact_phone, address)
             from public.properties where id = current_setting('app.list_a')::uuid),
  'pending|green-acres|Nashik|+919876543210|12 Vineyard Road, Nashik',
  'A''s resort is pending, trimmed, with the phone stored without spaces or dashes');
select is((select slug from public.properties where id = current_setting('app.list_b')::uuid),
  'green-acres-2', 'a taken name gets a numbered slug');
select is((select concat_ws('|', tier::text, status::text, trial_ends_on - pg_temp.today())
             from public.resort_subscriptions
            where property_id = current_setting('app.list_a')::uuid),
  'pro|trial|30', 'A starts a 30-day trial of the plan they chose');
select is((select tier::text from public.resort_subscriptions
            where property_id = current_setting('app.list_b')::uuid),
  'starter', 'the default plan is Starter');
select is((select array_agg(action order by action) from public.audit_log
            where property_id = current_setting('app.list_a')::uuid),
  array['listing:apply','subscription:create'], 'applying writes both audit rows');
select ok(not has_function_privilege('authenticated', 'public.resort_slug_for(text)', 'execute'),
  'resort_slug_for is internal');

-- Suspend / Reactivate cannot bypass review; pending counts for nothing.
set local role authenticated;
set local request.jwt.claims to '{"sub":"49000000-0000-0000-0000-000000000001","role":"authenticated"}';
select throws_ok($$select public.set_resort_status('49100000-0000-4000-8000-00000000000c', 'active')$$,
  'P0040', 'Approve or reject this resort instead.', 'a pending resort cannot be activated by hand');
select throws_ok($$select public.set_resort_status('49100000-0000-4000-8000-00000000000c', 'suspended')$$,
  'P0040', 'Approve or reject this resort instead.', 'nor suspended');
select is((select concat_ws('|', subscribed_count, active_count, trial_count, mrr_inr::int)
             from public.platform_summary()),
  '1|1|0|2999', 'pending resorts count for nothing: only D is subscribed');
reset role;
set local request.jwt.claims to '';

-- Listing photos: the resort's owners and admins upload into its folder.
select is((select public from storage.buckets where id = 'property-photos'), true,
  'the photo bucket is public');
set local role authenticated;
set local request.jwt.claims to '{"sub":"49000000-0000-0000-0000-000000000005","role":"authenticated"}';
select lives_ok($$insert into storage.objects (bucket_id, name)
  values ('property-photos', '49100000-0000-4000-8000-00000000000c/1.jpg')$$,
  'the owner uploads a photo for their pending resort');
set local request.jwt.claims to '{"sub":"49000000-0000-0000-0000-000000000006","role":"authenticated"}';
select lives_ok($$insert into storage.objects (bucket_id, name)
  values ('property-photos', '49100000-0000-4000-8000-00000000000c/2.jpg')$$,
  'the admin uploads too');
set local request.jwt.claims to '{"sub":"49000000-0000-0000-0000-000000000002","role":"authenticated"}';
select throws_ok($$insert into storage.objects (bucket_id, name)
  values ('property-photos', '49100000-0000-4000-8000-00000000000c/3.jpg')$$,
  '42501', null, 'someone else cannot upload into that resort''s folder');
select throws_ok($$insert into storage.objects (bucket_id, name)
  values ('property-photos', 'not-a-resort/1.jpg')$$,
  '42501', null, 'a path that names no resort is refused');
reset role;
set local request.jwt.claims to '';

-- === Task 3: the checklist and submitting ==================================

-- C so far: two active units (Cottage 1, Cottage 2), no rates, no photos,
-- no payment methods, no refund rules, no GSTIN.
set local role authenticated;
set local request.jwt.claims to '{"sub":"49000000-0000-0000-0000-000000000005","role":"authenticated"}';
select is((select concat_ws('|', property_status, has_photos::text, has_unit::text, has_rates::text,
                            has_payment_settings::text, has_cancellation_policy::text,
                            has_tax_details::text, (submitted_at is null)::text)
             from public.listing_setup_status('49100000-0000-4000-8000-00000000000c')),
  'pending|false|true|false|false|false|false|true',
  'a fresh pending resort has only its units done');
select throws_ok($$select public.submit_listing_for_review('49100000-0000-4000-8000-00000000000c')$$,
  'P0040', 'Finish the setup checklist before submitting.', 'an unfinished checklist cannot be submitted');

-- The owner works through the checklist with the ordinary writes.
select lives_ok($$update public.properties
    set images = array['https://example.com/c1.jpg'],
        payment_display_methods = array['UPI'],
        gstin = '29abcde1234f1z5'
  where id = '49100000-0000-4000-8000-00000000000c'$$,
  'the owner adds a photo, a payment method and a GSTIN (lower case)');
select lives_ok($$insert into public.refund_rules (property_id, min_days_before, refund_pct)
  values ('49100000-0000-4000-8000-00000000000c', 7, 100)$$,
  'the owner adds a cancellation rule');
select lives_ok($$insert into public.rate_rules (unit_id, kind, price)
  values ('49100000-0000-4000-8000-0000000000c1', 'base', 3000)$$,
  'the owner prices Cottage 1');
select is((select has_rates::text from public.listing_setup_status('49100000-0000-4000-8000-00000000000c')),
  'false', 'every active unit needs a rate: Cottage 2 has none');
select lives_ok($$insert into public.rate_rules (unit_id, kind, price, valid_from, valid_to)
  values ('49100000-0000-4000-8000-0000000000c2', 'override', 3500, '2027-12-24', '2027-12-26')$$,
  'the owner gives Cottage 2 a holiday override');
select is((select has_rates::text from public.listing_setup_status('49100000-0000-4000-8000-00000000000c')),
  'false', 'an override alone is a date range, not a standing price');
select lives_ok($$update public.units set is_active = false
  where id = '49100000-0000-4000-8000-0000000000c2'$$,
  'the owner switches Cottage 2 off');
select is((select has_rates::text from public.listing_setup_status('49100000-0000-4000-8000-00000000000c')),
  'true', 'an inactive unit does not need a rate');
select lives_ok($$update public.properties set gstin = '29ABCDE1234F1Z'
  where id = '49100000-0000-4000-8000-00000000000c'$$,
  'the owner mistypes the GSTIN');
select is((select has_tax_details::text from public.listing_setup_status('49100000-0000-4000-8000-00000000000c')),
  'false', 'a malformed GSTIN does not count');
select lives_ok($$update public.properties set gstin = '29abcde1234f1z5'
  where id = '49100000-0000-4000-8000-00000000000c'$$,
  'the owner fixes it');
select is((select concat_ws('|', property_status, has_photos::text, has_unit::text, has_rates::text,
                            has_payment_settings::text, has_cancellation_policy::text,
                            has_tax_details::text, (submitted_at is null)::text)
             from public.listing_setup_status('49100000-0000-4000-8000-00000000000c')),
  'pending|true|true|true|true|true|true|true', 'the checklist is complete');

set local request.jwt.claims to '{"sub":"49000000-0000-0000-0000-000000000006","role":"authenticated"}';
select is((select has_photos::text from public.listing_setup_status('49100000-0000-4000-8000-00000000000c')),
  'true', 'the resort''s admin reads the checklist');
select throws_ok($$select public.submit_listing_for_review('49100000-0000-4000-8000-00000000000c')$$,
  'P0020', null, 'only the owner submits');
set local request.jwt.claims to '{"sub":"49000000-0000-0000-0000-000000000004","role":"authenticated"}';
select throws_ok($$select * from public.listing_setup_status('49100000-0000-4000-8000-00000000000c')$$,
  'P0020', null, 'a stranger cannot read the checklist');

set local request.jwt.claims to '{"sub":"49000000-0000-0000-0000-000000000005","role":"authenticated"}';
select lives_ok($$select public.submit_listing_for_review('49100000-0000-4000-8000-00000000000c')$$,
  'the owner submits a complete resort');
select lives_ok($$select public.submit_listing_for_review('49100000-0000-4000-8000-00000000000c')$$,
  'submitting twice is harmless');
select is((select submitted_at is not null
             from public.listing_setup_status('49100000-0000-4000-8000-00000000000c')),
  true, 'the checklist shows the submission');
select throws_ok($$select public.submit_listing_for_review('49100000-0000-4000-8000-00000000000d')$$,
  'P0040', 'This resort is not waiting for review.', 'an active resort cannot be submitted');
select is((select concat_ws('|', template, recipient, status::text, (reservation_id is null)::text)
             from public.outbox where property_id = '49100000-0000-4000-8000-00000000000c'),
  'listing_submitted|list-owner-c@example.com|pending|true',
  'one submission email to the owner, with no reservation, readable by the owner');
reset role;
set local request.jwt.claims to '';

select is((select count(*)::int from public.audit_log
            where property_id = '49100000-0000-4000-8000-00000000000c' and action = 'listing:submit'),
  1, 'one submit audit row');
select ok((select body from public.outbox
            where property_id = '49100000-0000-4000-8000-00000000000c'
              and template = 'listing_submitted')
          like 'Hi Chetan Owner, thank you for listing Listing C on ResortHub.%',
  'the email is rendered with the owner''s and the resort''s names');
select ok(not has_function_privilege('authenticated', 'public.listing_setup_flags(uuid)', 'execute'),
  'listing_setup_flags is internal');
select ok(not has_function_privilege('authenticated', 'public.enqueue_listing_message(uuid, text)', 'execute'),
  'enqueue_listing_message is internal');

-- P7's dispatcher claims listing emails too (not in the plan: 0056's
-- claim_outbox_batch assumed every row has a reservation). A listing
-- email has no reservation variables, and the resort's guest-notification
-- toggles do not hold it back (spec decision 16).
insert into public.notification_settings (property_id, email_enabled)
  values ('49100000-0000-4000-8000-00000000000c', false)
  on conflict (property_id) do update set email_enabled = false;
select is((select vars::text from public.claim_outbox_batch(200)
            where template = 'listing_submitted'),
  '{}', 'the dispatcher claims a listing email, with no reservation variables');
select is((select concat_ws('|', status::text, attempts) from public.outbox
            where property_id = '49100000-0000-4000-8000-00000000000c'
              and template = 'listing_submitted'),
  'pending|1', 'the resort''s guest-email toggle does not hold back a listing email');
delete from public.notification_settings
  where property_id = '49100000-0000-4000-8000-00000000000c';

-- === Task 4: review and decisions ==========================================

-- Undecided now: C (submitted, complete), A's Green Acres and B's Green
-- Acres (both still being set up).
set local role authenticated;
set local request.jwt.claims to '{"sub":"49000000-0000-0000-0000-000000000005","role":"authenticated"}';
select throws_ok($$select * from public.platform_listing_applications()$$,
  'P0008', null, 'an owner cannot list applications');
select throws_ok($$select public.approve_listing('49100000-0000-4000-8000-00000000000c')$$,
  'P0008', null, 'an owner cannot approve their own resort');

set local request.jwt.claims to '{"sub":"49000000-0000-0000-0000-000000000001","role":"authenticated"}';
select is((select count(*)::int from public.platform_listing_applications()), 3,
  'three undecided applications');
select is((select name from public.platform_listing_applications() limit 1), 'Listing C',
  'submitted applications come first');
select is((select concat_ws('|', applicant_email, coalesce(applicant_name, ''), tier::text, city,
                            contact_phone, has_photos::text, has_unit::text, has_rates::text,
                            has_payment_settings::text, has_cancellation_policy::text,
                            has_tax_details::text)
             from public.platform_listing_applications()
            where property_id = '49100000-0000-4000-8000-00000000000c'),
  'list-owner-c@example.com|Chetan Owner|pro|Pune|+919876543210|true|true|true|true|true|true',
  'the console sees the applicant, the contact details and the checklist');
select throws_ok(format('select public.approve_listing(%L)', current_setting('app.list_a')),
  'P0040', 'This resort has not been submitted for review yet.',
  'an application still being set up cannot be approved');
select throws_ok($$select public.approve_listing('49100000-0000-4000-8000-0000000000ff')$$,
  'P0002', null, 'an unknown application');

-- The owner removes the photo after submitting: approval re-checks.
reset role;
set local request.jwt.claims to '';
update public.properties set images = '{}' where id = '49100000-0000-4000-8000-00000000000c';
set local role authenticated;
set local request.jwt.claims to '{"sub":"49000000-0000-0000-0000-000000000001","role":"authenticated"}';
select throws_ok($$select public.approve_listing('49100000-0000-4000-8000-00000000000c')$$,
  'P0040', 'The setup checklist is no longer complete.',
  'a resort that lost a checklist item is not approved');
reset role;
set local request.jwt.claims to '';
update public.properties set images = array['https://example.com/c1.jpg']
  where id = '49100000-0000-4000-8000-00000000000c';
set local role authenticated;
set local request.jwt.claims to '{"sub":"49000000-0000-0000-0000-000000000001","role":"authenticated"}';
select lives_ok($$select public.approve_listing('49100000-0000-4000-8000-00000000000c')$$,
  'the platform admin approves Listing C');
select throws_ok($$select public.approve_listing('49100000-0000-4000-8000-00000000000c')$$,
  'P0040', 'This application has already been decided.', 'a decision is final');
reset role;
set local request.jwt.claims to '';

select is((select status from public.properties where id = '49100000-0000-4000-8000-00000000000c'),
  'active', 'Listing C is live');
select is((select concat_ws('|', decision, decided_by::text) from public.listing_applications
            where property_id = '49100000-0000-4000-8000-00000000000c'),
  'approved|49000000-0000-0000-0000-000000000001', 'the decision and who made it are stored');
select is((select trial_ends_on - pg_temp.today() from public.resort_subscriptions
            where property_id = '49100000-0000-4000-8000-00000000000c'),
  30, 'approval restarts the 30-day trial');
select is((select array_agg(action order by action) from public.audit_log
            where property_id = '49100000-0000-4000-8000-00000000000c'
              and action in ('status:pending->active','listing:approve','subscription:trial-restart')),
  array['listing:approve','status:pending->active','subscription:trial-restart'],
  'approval is audited');
select is((select concat_ws('|', recipient, status::text) from public.outbox
            where property_id = '49100000-0000-4000-8000-00000000000c'
              and template = 'listing_approved'),
  'list-owner-c@example.com|pending', 'the owner is told the resort is live');
select ok((select body from public.outbox
            where property_id = '49100000-0000-4000-8000-00000000000c'
              and template = 'listing_approved')
          like ('%runs until ' || to_char(pg_temp.today() + 30, 'DD Mon YYYY') || '.'),
  'the approval email carries the restarted trial''s end');
set local role anon;
select is((select count(*)::int from public.properties
            where id = '49100000-0000-4000-8000-00000000000c'), 1,
  'guests can now see Listing C');
reset role;

set local role authenticated;
set local request.jwt.claims to '{"sub":"49000000-0000-0000-0000-000000000001","role":"authenticated"}';
select is((select count(*)::int from public.platform_listing_applications()), 2,
  'Listing C has left the queue');
select throws_ok(format('select public.reject_listing(%L, %L)', current_setting('app.list_b'), '  no '),
  'P0005', 'Give the owner a reason (5 to 500 characters).', 'a rejection needs a reason');
set local request.jwt.claims to '{"sub":"49000000-0000-0000-0000-000000000005","role":"authenticated"}';
select throws_ok(format('select public.reject_listing(%L, %L)', current_setting('app.list_b'),
                        'Photos do not match.'),
  'P0008', null, 'only the platform admin rejects');
set local request.jwt.claims to '{"sub":"49000000-0000-0000-0000-000000000001","role":"authenticated"}';
select lives_ok(format('select public.reject_listing(%L, %L)', current_setting('app.list_b'),
                       'Photos do not match the address.'),
  'the platform admin rejects B''s resort');
select throws_ok($$select public.reject_listing('49100000-0000-4000-8000-00000000000c', 'Too late to change.')$$,
  'P0040', 'This application has already been decided.', 'an approved resort cannot be rejected');
select is((select concat_ws('|', subscribed_count, active_count, trial_count, mrr_inr::int)
             from public.platform_summary()),
  '2|2|1|2999', 'the approved trial now counts; the rejected and the pending ones do not');
reset role;
set local request.jwt.claims to '';

select is((select status from public.properties where id = current_setting('app.list_b')::uuid),
  'archived', 'a rejected resort is archived');
select is((select array_agg(action order by action) from public.audit_log
            where property_id = current_setting('app.list_b')::uuid
              and action in ('status:pending->archived','listing:reject')),
  array['listing:reject','status:pending->archived'], 'rejection is audited');
select ok((select body from public.outbox
            where property_id = current_setting('app.list_b')::uuid
              and template = 'listing_rejected')
          like '%Reason: Photos do not match the address.%',
  'the rejection email carries the reason');

set local role authenticated;
set local request.jwt.claims to '{"sub":"49000000-0000-0000-0000-000000000003","role":"authenticated"}';
select is((select concat_ws('|', property_status, decision, rejection_reason)
             from public.my_listing_applications()),
  'archived|rejected|Photos do not match the address.',
  'B still sees the decision and the reason');
select ok(not public.has_resort_role(current_setting('app.list_b')::uuid, false, 'owner'),
  'B keeps no access to the archived resort');
select ok(set_config('app.list_b2',
    public.apply_for_listing('Green Acres Lakeside', 'Lonavala', '5 Lake Road, Lonavala',
      '9876501234', 'Lakeside tents and a big lawn, now with photos.')::text,
    true) is not null,
  'B can apply again after a rejection');
select is((select count(*)::int from public.my_listing_applications()), 2,
  'B now has the old and the new application');
reset role;
set local request.jwt.claims to '';

select * from finish();
rollback;
