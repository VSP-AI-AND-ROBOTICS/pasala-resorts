-- OTA sync reliability (P9), added in 0058_ota_sync_status.sql. See
-- docs/superpowers/specs/2026-09-25-p9-ota-sync-reliability-design.md.
--
-- One file, built up by the plan's database tasks in order: each section
-- relies on the state the sections before it leave behind.
--
-- Fixtures: resort R (Asia/Kolkata, check-in 14:00, check-out 11:00 -- the
-- column defaults) with an admin (Asha) and a staff member (Sunil); units
-- Cottage A and Cottage B; an inactive contract feed on Cottage B.
begin;
select plan(12);

insert into auth.users (id, email) values
  ('f9000000-0000-4000-8000-000000000001','ota-admin@example.com'),
  ('f9000000-0000-4000-8000-000000000002','ota-staff@example.com');

insert into public.properties (id, name, slug) values
  ('f9000000-0000-4000-8000-000000000010','Resort R','ota-r');

insert into public.resort_members (property_id, user_id, role) values
  ('f9000000-0000-4000-8000-000000000010','f9000000-0000-4000-8000-000000000001','admin'),
  ('f9000000-0000-4000-8000-000000000010','f9000000-0000-4000-8000-000000000002','staff');

insert into public.units (id, property_id, name, capacity_base, capacity_max) values
  ('f9000000-0000-4000-8000-000000000011','f9000000-0000-4000-8000-000000000010','Cottage A',2,4),
  ('f9000000-0000-4000-8000-000000000012','f9000000-0000-4000-8000-000000000010','Cottage B',2,4);

insert into public.ical_feeds (id, unit_id, url, label, is_active) values
  ('f9000000-0000-4000-8000-000000000030','f9000000-0000-4000-8000-000000000012',
   'https://example.invalid/contract.ics','Contract',false);

-- === Task 1: the contract ===================================================

select has_column('public', 'ical_feeds', 'last_status', 'ical_feeds has last_status');
select has_column('public', 'ical_feeds', 'last_event_count',
  'ical_feeds has last_event_count');
select has_column('public', 'ical_feeds', 'last_ok_at', 'ical_feeds has last_ok_at');
select throws_ok($$update public.ical_feeds set last_status = 'maybe'
  where id = 'f9000000-0000-4000-8000-000000000030'$$,
  '23514', null, 'last_status is ok, error or null');
select throws_ok($$update public.ical_feeds set last_event_count = -1
  where id = 'f9000000-0000-4000-8000-000000000030'$$,
  '23514', null, 'last_event_count is never negative');
select is((select count(*)::int from unnest(array[
    to_regprocedure('public.ical_parse_when(text, text, text)'),
    to_regprocedure('public.ical_parse_feed(text, text)'),
    to_regprocedure('public.ical_event_period(uuid, timestamptz, timestamptz, date, date)'),
    to_regprocedure('public.ical_event_is_echo(uuid, date, date)')]) f
   where f is not null),
  4, 'the four parser helpers exist with these signatures');
select is((select array_agg(p.parameter_name::text order by p.ordinal_position)
             from information_schema.parameters p
             join information_schema.routines r
               on r.specific_schema = p.specific_schema and r.specific_name = p.specific_name
            where r.routine_schema = 'public' and r.routine_name = 'ical_parse_feed'
              and p.parameter_mode = 'OUT'),
  array['uid','dtstart','dtend','start_date','end_date','summary','error'],
  'ical_parse_feed returns the columns ical_poll_feed reads');
select is((select array_agg(p.parameter_name::text order by p.ordinal_position)
             from information_schema.parameters p
             join information_schema.routines r
               on r.specific_schema = p.specific_schema and r.specific_name = p.specific_name
            where r.routine_schema = 'public' and r.routine_name = 'ical_parse_when'
              and p.parameter_mode = 'OUT'),
  array['at_ts','on_date'], 'ical_parse_when returns at_ts and on_date');
select is((select count(*)::int from pg_proc
            where oid in ('public.ical_parse_when(text, text, text)'::regprocedure,
                          'public.ical_parse_feed(text, text)'::regprocedure,
                          'public.ical_event_period(uuid, timestamptz, timestamptz, date, date)'::regprocedure,
                          'public.ical_event_is_echo(uuid, date, date)'::regprocedure)
              and prosecdef),
  0, 'none of them is security definer, so the definer allow-list does not change');
select is((select array_agg(f::text order by f::text)
             from unnest(array[
               'public.ical_parse_when(text, text, text)',
               'public.ical_parse_feed(text, text)',
               'public.ical_event_period(uuid, timestamptz, timestamptz, date, date)',
               'public.ical_event_is_echo(uuid, date, date)']::regprocedure[]) f
            where has_function_privilege('anon', f, 'execute')),
  null, 'anon can execute none of the parser helpers');
select is((select array_agg(f::text order by f::text)
             from unnest(array[
               'public.ical_parse_when(text, text, text)',
               'public.ical_parse_feed(text, text)',
               'public.ical_event_period(uuid, timestamptz, timestamptz, date, date)',
               'public.ical_event_is_echo(uuid, date, date)']::regprocedure[]) f
            where has_function_privilege('authenticated', f, 'execute')),
  null, 'authenticated cannot either -- they run only inside ical_poll_feed');
select ok(to_regprocedure('public.ical_poll_feed(uuid)') is not null
      and to_regprocedure('public.ical_parse_events(text)') is not null,
  'ical_poll_feed and ical_parse_events keep their signatures');

select * from finish();
rollback;
