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
select plan(102);

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

-- === Task 2: parsing real OTA exports ======================================
--
-- Shapes copied from real exports: Airbnb (CRLF, folded lines, all-day
-- VALUE=DATE events named "Reserved" and "Airbnb (Not available)");
-- Booking.com (bare LF, "CLOSED - Not available"); timezone variants; and
-- edge cases. The helpers are revoked from every API role, so this section
-- runs as the owner. 'Asia/Kolkata' stands in for the resort zone that
-- ical_poll_feed passes.
--
-- The fixtures are written with LF inside $ics$ quotes; replace(..., E'\n',
-- E'\r\n') makes the CRLF ones. A line starting with one space is a fold.

create temp table ics (name text primary key, body text not null);

insert into ics values ('airbnb', replace($ics$BEGIN:VCALENDAR
PRODID;X-RICAL-TZSOURCE=TZINFO:-//Airbnb Inc//Hosting Calendar 1.0//EN
CALSCALE:GREGORIAN
VERSION:2.0
BEGIN:VEVENT
DTEND;VALUE=DATE:20271012
DTSTART;VALUE=DATE:20271009
UID:1418fb94e984-0a1b2c3d4e5f6071
 8293a4b5c6d7e8f9@airbnb.com
DESCRIPTION:Reservation URL: https://www.airbnb.com/hosting/reservations/d
 etails/HMABCD1234\nPhone Number (Last 4 Digits): 4321
SUMMARY:Reserved
END:VEVENT
BEGIN:VEVENT
DTEND;VALUE=DATE:20271101
DTSTART;VALUE=DATE:20271025
UID:7f3e8a1c9d2b-11223344556677889900aabbccddeeff@airbnb.com
SUMMARY:Airbnb (Not available)
END:VEVENT
END:VCALENDAR
$ics$, E'\n', E'\r\n'));

insert into ics values ('booking', $ics$BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//admin.booking.com//EN
CALSCALE:GREGORIAN
METHOD:PUBLISH
BEGIN:VEVENT
UID:9d3c5e0f2a7b4c18a0e1@booking.com
DTSTAMP:20270901T060000Z
DTSTART;VALUE=DATE:20271115
DTEND;VALUE=DATE:20271118
SUMMARY:CLOSED - Not available
END:VEVENT
BEGIN:VEVENT
UID:5b7a1c3e9f0d2468b1c3@booking.com
DTSTAMP:20270901T060000Z
DTSTART;VALUE=DATE:20271201
DTEND;VALUE=DATE:20271202
SUMMARY:CLOSED - Not available
END:VEVENT
END:VCALENDAR
$ics$);
insert into ics
  select 'booking_crlf', replace(body, E'\n', E'\r\n') from ics where name = 'booking';

insert into ics values ('timezones', replace($ics$BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VEVENT
UID:tz-kolkata
DTSTART;TZID=Asia/Kolkata:20271205T140000
DTEND;TZID=Asia/Kolkata:20271207T110000
END:VEVENT
BEGIN:VEVENT
UID:tz-quoted
DTSTART;TZID="Europe/London":20271210T150000
DTEND;TZID="Europe/London":20271211T100000
END:VEVENT
BEGIN:VEVENT
UID:tz-windows
DTSTART;TZID=India Standard Time:20271212T140000
DTEND;TZID=India Standard Time:20271213T110000
END:VEVENT
BEGIN:VEVENT
UID:tz-floating
DTSTART:20271215T140000
DTEND:20271216T110000
END:VEVENT
BEGIN:VEVENT
UID:tz-utc
DTSTART:20271220T083000Z
DTEND:20271222T053000Z
END:VEVENT
END:VCALENDAR
$ics$, E'\n', E'\r\n'));

insert into ics values ('edge', chr(65279) || replace($ics$BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VEVENT
UID:one-day
DTSTART;VALUE=DATE:20280105
SUMMARY:Blocked
END:VEVENT
BEGIN:VEVENT
UID:plain-date
DTSTART:20280110
DTEND:20280112
END:VEVENT
BEGIN:VEVENT
UID:same-day-end
DTSTART;VALUE=DATE:20280115
DTEND;VALUE=DATE:20280115
END:VEVENT
BEGIN:VEVENT
UID:two-days
DTSTART;VALUE=DATE:20280120
DURATION:P2D
END:VEVENT
begin:vevent
uid:lower-case
dtstart;value=date:20280125
dtend;value=date:20280127
end:vevent
BEGIN:VEVENT
UID:with-alarm
DTSTART;VALUE=DATE:20280201
DTEND;VALUE=DATE:20280203
BEGIN:VALARM
ACTION:DISPLAY
UID:alarm-uid-must-not-win
DTSTART:20280101T000000Z
END:VALARM
END:VEVENT
BEGIN:VEVENT
UID:cancelled-one
STATUS:CANCELLED
DTSTART;VALUE=DATE:20280205
DTEND;VALUE=DATE:20280207
END:VEVENT
BEGIN:VEVENT
DTSTART;VALUE=DATE:20280210
DTEND;VALUE=DATE:20280212
SUMMARY:No uid here
END:VEVENT
BEGIN:VEVENT
UID:bad-date
DTSTART;VALUE=DATE:20281345
DTEND;VALUE=DATE:20281347
END:VEVENT
BEGIN:VEVENT
UID:backwards
DTSTART;VALUE=DATE:20280220
DTEND;VALUE=DATE:20280218
END:VEVENT
END:VCALENDAR
$ics$, E'\n', E'\r\n'));

-- Airbnb.
select is((select count(*)::int from public.ical_parse_feed(
    (select body from ics where name = 'airbnb'), 'Asia/Kolkata')),
  2, 'Airbnb: both events are read');
select is((select count(*)::int from public.ical_parse_feed(
    (select body from ics where name = 'airbnb'), 'Asia/Kolkata')
   where uid = '1418fb94e984-0a1b2c3d4e5f60718293a4b5c6d7e8f9@airbnb.com'),
  1, 'Airbnb: a UID folded over two lines is unfolded');
select is((select array[start_date, end_date] from public.ical_parse_feed(
    (select body from ics where name = 'airbnb'), 'Asia/Kolkata')
   where summary = 'Reserved'),
  array['2027-10-09','2027-10-12']::date[],
  'Airbnb: a reservation is all day, check-in date to check-out date');
select is((select array_agg(summary order by summary) from public.ical_parse_feed(
    (select body from ics where name = 'airbnb'), 'Asia/Kolkata')),
  array['Airbnb (Not available)','Reserved'],
  'Airbnb: both summaries are read, and a folded DESCRIPTION does not get in the way');
select is((select count(*)::int from public.ical_parse_feed(
    (select body from ics where name = 'airbnb'), 'Asia/Kolkata')
   where error is not null),
  0, 'Airbnb: nothing is unreadable');
select is((select dtstart from public.ical_parse_feed(
    (select body from ics where name = 'airbnb'), 'Asia/Kolkata')
   where summary = 'Reserved'),
  '2027-10-09 00:00:00+05:30'::timestamptz,
  'Airbnb: an all-day start is midnight in the zone passed in');

-- Booking.com.
select is((select array_agg(uid || ' ' || start_date || ' ' || end_date order by start_date)
             from public.ical_parse_feed((select body from ics where name = 'booking'),
                                         'Asia/Kolkata')),
  array['9d3c5e0f2a7b4c18a0e1@booking.com 2027-11-15 2027-11-18',
        '5b7a1c3e9f0d2468b1c3@booking.com 2027-12-01 2027-12-02'],
  'Booking.com (bare LF): both closed periods are read');
select is((select array_agg(f::text order by f.uid) from public.ical_parse_feed(
    (select body from ics where name = 'booking_crlf'), 'Asia/Kolkata') f),
  (select array_agg(f::text order by f.uid) from public.ical_parse_feed(
    (select body from ics where name = 'booking'), 'Asia/Kolkata') f),
  'Booking.com: the same file with CRLF line endings gives the same rows');
select is((select count(*)::int from public.ical_parse_feed(
    (select body from ics where name = 'booking'), 'Asia/Kolkata')
   where summary = 'CLOSED - Not available'),
  2, 'Booking.com: the "CLOSED - Not available" summary is read');

-- Time zones.
create temp table tz as
  select * from public.ical_parse_feed((select body from ics where name = 'timezones'),
                                       'Asia/Kolkata');
select is((select dtstart from tz where uid = 'tz-kolkata'),
  '2027-12-05 08:30:00+00'::timestamptz, 'TZID=Asia/Kolkata: 14:00 there is 08:30 UTC');
select is((select dtend from tz where uid = 'tz-kolkata'),
  '2027-12-07 05:30:00+00'::timestamptz, 'TZID=Asia/Kolkata: 11:00 there is 05:30 UTC');
select is((select dtstart from tz where uid = 'tz-quoted'),
  '2027-12-10 15:00:00+00'::timestamptz, 'a quoted TZID ("Europe/London") is read');
select is((select dtstart from tz where uid = 'tz-windows'),
  '2027-12-12 08:30:00+00'::timestamptz,
  'a zone Postgres does not know (Windows "India Standard Time") falls back to the resort zone');
select is((select dtstart from tz where uid = 'tz-floating'),
  '2027-12-15 08:30:00+00'::timestamptz, 'a floating time is resort-local, not UTC');
select is((select dtstart from tz where uid = 'tz-utc'),
  '2027-12-20 08:30:00+00'::timestamptz, 'a ...Z time is UTC');
select is((select count(*)::int from tz where start_date is not null),
  0, 'timed events are not all-day');

-- Edge cases.
create temp table edge as
  select * from public.ical_parse_feed((select body from ics where name = 'edge'),
                                       'Asia/Kolkata');
select is((select count(*)::int from edge), 9,
  'a byte-order mark is skipped and every non-cancelled event is returned, readable or not');
select is((select count(*)::int from edge where uid = 'cancelled-one'), 0,
  'a STATUS:CANCELLED event is skipped');
select is((select end_date from edge where uid = 'one-day'), '2028-01-06'::date,
  'an all-day event with no DTEND lasts one night');
select is((select array[start_date, end_date] from edge where uid = 'plain-date'),
  array['2028-01-10','2028-01-12']::date[],
  'a date without VALUE=DATE is still a date');
select is((select end_date from edge where uid = 'same-day-end'), '2028-01-16'::date,
  'an all-day event whose DTEND equals DTSTART lasts one night');
select is((select end_date from edge where uid = 'two-days'), '2028-01-22'::date,
  'DURATION:P2D on an all-day event is two nights');
select is((select array[start_date, end_date] from edge where uid = 'lower-case'),
  array['2028-01-25','2028-01-27']::date[], 'property names are case-insensitive');
select is((select start_date from edge where uid = 'with-alarm'), '2028-02-01'::date,
  'properties inside a VALARM do not overwrite the event''s own');
select is((select error from edge where summary = 'No uid here'), 'missing UID',
  'an event without a UID is returned with an error');
select ok((select error is not null and dtstart is null from edge where uid = 'bad-date'),
  'an impossible date is an error on that event, not on the feed');
select is((select error from edge where uid = 'backwards'), 'DTEND is before DTSTART',
  'an end before the start is an error');
select is((select uid || ' ' || start_date || ' ' || end_date from public.ical_parse_feed(
    E'BEGIN:VCALENDAR\r\nBEGIN:VEVENT \r\nUID:padded   \r\nDTSTART;VALUE=DATE:20280301\r\n'
    'END:VEVENT\t\r\nEND:VCALENDAR\r\n', 'Asia/Kolkata')),
  'padded 2028-03-01 2028-03-02', 'trailing spaces and tabs are ignored');
select is((select error from public.ical_parse_feed(
    E'BEGIN:VEVENT\r\nUID:no-end\r\nDTSTART:20280305T100000Z\r\nEND:VEVENT\r\n',
    'Asia/Kolkata')),
  'missing DTEND', 'a timed event with no DTEND or DURATION is an error');
select is((select error from public.ical_parse_feed(
    E'BEGIN:VEVENT\r\nUID:zero\r\nDTSTART:20280305T100000Z\r\n'
    'DTEND:20280305T100000Z\r\nEND:VEVENT\r\n', 'Asia/Kolkata')),
  'DTEND is not after DTSTART', 'a zero-length timed event is an error');
select is((select dtend from public.ical_parse_feed(
    E'BEGIN:VEVENT\r\nUID:three-hours\r\nDTSTART:20280306T100000Z\r\n'
    'DURATION:PT3H\r\nEND:VEVENT\r\n', 'Asia/Kolkata')),
  '2028-03-06 13:00:00+00'::timestamptz, 'DURATION on a timed event sets its end');
select is((select error from public.ical_parse_feed(
    E'BEGIN:VEVENT\r\nUID:mixed\r\nDTSTART;VALUE=DATE:20280306\r\n'
    'DTEND:20280307T100000Z\r\nEND:VEVENT\r\n', 'Asia/Kolkata')),
  'DTEND is a time but DTSTART is a date', 'a date start with a timed end is an error');
select is((select count(*)::int from public.ical_parse_feed(
    '<!DOCTYPE html><html><body>Sign in</body></html>', 'Asia/Kolkata')),
  0, 'a web page has no events (ical_poll_feed reports it as not a calendar)');
select is((select count(*)::int from public.ical_parse_feed(null, 'Asia/Kolkata')),
  0, 'an empty body has no events');

-- One value.
select throws_ok($$select public.ical_parse_when('2027-12-05', '', 'Asia/Kolkata')$$,
  'P0005', 'unreadable date "2027-12-05"', 'a date with dashes is not an iCal date');
select is((select at_ts from public.ical_parse_when(
    '20271205T140000', ';TZID=Nowhere/Land', 'Asia/Kolkata')),
  '2027-12-05 08:30:00+00'::timestamptz, 'an unknown TZID falls back to the resort zone');
select is((select at_ts from public.ical_parse_when(
    '20271205T140000', ';TZID=/Asia/Kolkata', 'UTC')),
  '2027-12-05 08:30:00+00'::timestamptz, 'a TZID with a leading slash is read');

-- === Task 3: polling -- status columns, resort times, echoes ===============
--
-- ical_poll_feed collects a fetched response from net._http_response
-- (0018's two-call state machine), so a response is faked the way a real
-- one lands: point the feed's pending_request_id at a row written there.
-- Request ids are far above pg_net's own so they never collide. Polls run
-- with no JWT, like the pg_cron job, unless a test says otherwise.

set local request.jwt.claims to '';

insert into ics values ('booking_echo', $ics$BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//admin.booking.com//EN
BEGIN:VEVENT
UID:9d3c5e0f2a7b4c18a0e1@booking.com
DTSTART;VALUE=DATE:20271115
DTEND;VALUE=DATE:20271118
SUMMARY:CLOSED - Not available
END:VEVENT
BEGIN:VEVENT
UID:5b7a1c3e9f0d2468b1c3@booking.com
DTSTART;VALUE=DATE:20271201
DTEND;VALUE=DATE:20271202
SUMMARY:CLOSED - Not available
END:VEVENT
BEGIN:VEVENT
UID:echo-of-our-block@booking.com
DTSTART;VALUE=DATE:20271120
DTEND;VALUE=DATE:20271123
SUMMARY:CLOSED - Not available
END:VEVENT
BEGIN:VEVENT
UID:overlaps-our-block@booking.com
DTSTART;VALUE=DATE:20271122
DTEND;VALUE=DATE:20271125
SUMMARY:CLOSED - Not available
END:VEVENT
END:VCALENDAR
$ics$);

-- On Cottage A: our own block ending 25 Oct 11:00 (the Airbnb block starts
-- that day), our own block 20-23 Nov (Booking.com echoes it back), and an
-- Airbnb stay imported before P9, at midnight UTC.
insert into public.reservations
  (unit_id, period, kind, status, block_reason, external_uid, source) values
  ('f9000000-0000-4000-8000-000000000011',
   tstzrange('2027-10-22 08:30+00','2027-10-25 05:30+00','[)'),
   'block','confirmed','Owner stay', null, 'app'),
  ('f9000000-0000-4000-8000-000000000011',
   tstzrange('2027-11-20 08:30+00','2027-11-23 05:30+00','[)'),
   'block','confirmed','Owner stay', null, 'app'),
  ('f9000000-0000-4000-8000-000000000011',
   tstzrange('2027-10-09 00:00+00','2027-10-12 00:00+00','[)'),
   'ota','confirmed', null,
   '1418fb94e984-0a1b2c3d4e5f60718293a4b5c6d7e8f9@airbnb.com', 'ical');

insert into public.ical_feeds (id, unit_id, url, label) values
  ('f9000000-0000-4000-8000-000000000021','f9000000-0000-4000-8000-000000000011',
   'https://example.invalid/airbnb.ics','Airbnb'),
  ('f9000000-0000-4000-8000-000000000022','f9000000-0000-4000-8000-000000000011',
   'https://example.invalid/booking.ics','Booking.com'),
  ('f9000000-0000-4000-8000-000000000023','f9000000-0000-4000-8000-000000000012',
   'https://example.invalid/broken.ics','Broken');

-- Resort L, in London with its own check-in/check-out times.
insert into public.properties (id, name, slug, timezone, check_in_time, check_out_time)
values ('f9000000-0000-4000-8000-000000000050','Resort L','ota-l',
        'Europe/London','15:00','10:00');
insert into public.units (id, property_id, name, capacity_base, capacity_max) values
  ('f9000000-0000-4000-8000-000000000051','f9000000-0000-4000-8000-000000000050','Loft',2,4);
insert into public.ical_feeds (id, unit_id, url, label) values
  ('f9000000-0000-4000-8000-000000000052','f9000000-0000-4000-8000-000000000051',
   'https://example.invalid/london.ics','Airbnb');

-- Point a feed at a faked response fetched p_age ago.
create function pg_temp.deliver(p_feed uuid, p_req bigint, p_status int, p_body text,
                                p_age interval default '0',
                                p_timed_out boolean default false)
returns void language plpgsql as $f$
begin
  update public.ical_feeds
     set pending_request_id = p_req, pending_since = now() - p_age
   where id = p_feed;
  insert into net._http_response (id, status_code, content, timed_out, error_msg)
  values (p_req, p_status, p_body, p_timed_out, null);
end;
$f$;

-- Airbnb, fetched 10 minutes ago.
select pg_temp.deliver('f9000000-0000-4000-8000-000000000021', 948000001, 200,
  (select body from ics where name = 'airbnb'), '10 minutes');
select public.ical_poll_feed('f9000000-0000-4000-8000-000000000021')::text as r1 \gset

select is(:'r1'::jsonb ->> 'status', 'ok', 'a collected Airbnb export syncs ok');
select is((:'r1'::jsonb ->> 'events')::int, 2, 'events counts what the feed lists');
select is((:'r1'::jsonb ->> 'created')::int, 1, 'the Not available block is created');
select is((:'r1'::jsonb ->> 'updated')::int, 1,
  'the stay imported before P9 at midnight UTC is moved, not duplicated');
select is((:'r1'::jsonb ->> 'conflicts')::int, 0,
  'back to back with our own block is not a conflict');
select is((select period from public.reservations
            where external_uid = '1418fb94e984-0a1b2c3d4e5f60718293a4b5c6d7e8f9@airbnb.com'),
  tstzrange('2027-10-09 08:30+00','2027-10-12 05:30+00','[)'),
  'an all-day stay runs from check-in 14:00 to check-out 11:00, Asia/Kolkata');
select is((select period from public.reservations
            where external_uid = '7f3e8a1c9d2b-11223344556677889900aabbccddeeff@airbnb.com'),
  tstzrange('2027-10-25 08:30+00','2027-11-01 05:30+00','[)'),
  'the Not available block starts at check-in on the day our block ends');
select is((select array[last_status, last_event_count::text, coalesce(last_error, '-')]
             from public.ical_feeds where id = 'f9000000-0000-4000-8000-000000000021'),
  array['ok','2','-'], 'the feed records ok, 2 events and no note');
select is((select last_synced_at from public.ical_feeds
            where id = 'f9000000-0000-4000-8000-000000000021'),
  now() - interval '10 minutes',
  'last_synced_at is when the data was fetched, not when it was processed');
select is((select last_ok_at from public.ical_feeds
            where id = 'f9000000-0000-4000-8000-000000000021'),
  now() - interval '10 minutes', 'last_ok_at moves with a successful sync');
select isnt((select pending_request_id from public.ical_feeds
              where id = 'f9000000-0000-4000-8000-000000000021'),
  948000001::bigint, 'a fresh fetch was fired after collecting');

-- The same export again.
select pending_request_id as fa_next from public.ical_feeds
 where id = 'f9000000-0000-4000-8000-000000000021' \gset
select pg_temp.deliver('f9000000-0000-4000-8000-000000000021', :fa_next, 200,
  (select body from ics where name = 'airbnb'));
select public.ical_poll_feed('f9000000-0000-4000-8000-000000000021')::text as r2 \gset
select is((:'r2'::jsonb ->> 'unchanged')::int, 2, 'a re-import changes nothing');
select is((:'r2'::jsonb ->> 'created')::int, 0, 'and creates nothing');

-- Booking.com echoing our block back, plus one real overlap.
select pg_temp.deliver('f9000000-0000-4000-8000-000000000022', 948000002, 200,
  (select body from ics where name = 'booking_echo'), '5 minutes');
select public.ical_poll_feed('f9000000-0000-4000-8000-000000000022')::text as r3 \gset
select is((:'r3'::jsonb ->> 'events')::int, 4, 'Booking.com: four events read');
select is((:'r3'::jsonb ->> 'created')::int, 2, 'the two closed periods are created');
select is((:'r3'::jsonb ->> 'echoes')::int, 1,
  'Booking.com listing our own block back is an echo');
select is((:'r3'::jsonb ->> 'conflicts')::int, 1,
  'a closed period that overlaps our block for only some nights is a conflict');
select is((select count(*)::int from public.reservations
            where external_uid in ('echo-of-our-block@booking.com',
                                   'overlaps-our-block@booking.com')),
  0, 'neither is imported');
select is((select array[last_status, last_error] from public.ical_feeds
            where id = 'f9000000-0000-4000-8000-000000000022'),
  array['ok','1 event(s) conflicted with an existing booking and were skipped'],
  'a conflict is a note on an ok sync, and the echo adds nothing');

-- A web page instead of a calendar.
select pg_temp.deliver('f9000000-0000-4000-8000-000000000023', 948000003, 200,
  '<!DOCTYPE html><html><body>Log in</body></html>');
select public.ical_poll_feed('f9000000-0000-4000-8000-000000000023')::text as r4 \gset
select is(:'r4'::jsonb ->> 'status', 'error', 'a 200 that is not a calendar is an error');
select is((select array[last_status, last_error] from public.ical_feeds
            where id = 'f9000000-0000-4000-8000-000000000023'),
  array['error','not a calendar: the link did not return iCal data'],
  'and says so');
select ok((select last_ok_at is null and last_event_count is null from public.ical_feeds
            where id = 'f9000000-0000-4000-8000-000000000023'),
  'a feed that never worked has no last good sync and no count');

-- It works once (fetched 20 minutes ago), then the link dies.
select pg_temp.deliver('f9000000-0000-4000-8000-000000000023', 948000004, 200,
  (select body from ics where name = 'booking'), '20 minutes');
select public.ical_poll_feed('f9000000-0000-4000-8000-000000000023')::text as r5 \gset
select is(:'r5'::jsonb ->> 'status', 'ok', 'the feed recovers');
select pg_temp.deliver('f9000000-0000-4000-8000-000000000023', 948000005, 404, 'Not Found');
select public.ical_poll_feed('f9000000-0000-4000-8000-000000000023');
select is((select array[last_status, last_error] from public.ical_feeds
            where id = 'f9000000-0000-4000-8000-000000000023'),
  array['error','HTTP 404'], 'an HTTP error is an error');
select ok((select last_ok_at = now() - interval '20 minutes' and last_event_count = 2
             from public.ical_feeds where id = 'f9000000-0000-4000-8000-000000000023'),
  'a failure keeps the last good sync and its count');
select is((select last_synced_at from public.ical_feeds
            where id = 'f9000000-0000-4000-8000-000000000023'),
  now(), 'last_synced_at records the failed attempt');

-- A timeout, then a poll that finds nothing yet.
select pg_temp.deliver('f9000000-0000-4000-8000-000000000023', 948000006, null, null,
  '0', true);
select public.ical_poll_feed('f9000000-0000-4000-8000-000000000023')::text as r7 \gset
select is(:'r7'::jsonb ->> 'error', 'request timed out', 'a timeout is an error');
update public.ical_feeds set pending_request_id = 948999999, pending_since = now()
 where id = 'f9000000-0000-4000-8000-000000000023';
select public.ical_poll_feed('f9000000-0000-4000-8000-000000000023')::text as r8 \gset
select is(:'r8'::jsonb ->> 'status', 'pending', 'a response not there yet is pending');
select is((select last_error from public.ical_feeds
            where id = 'f9000000-0000-4000-8000-000000000023'),
  'request timed out', 'and a pending poll changes nothing');

-- Another resort's zone and times.
select pg_temp.deliver('f9000000-0000-4000-8000-000000000052', 948000007, 200,
  E'BEGIN:VCALENDAR\r\nVERSION:2.0\r\nBEGIN:VEVENT\r\nUID:london-stay@airbnb.com\r\n'
  'DTSTART;VALUE=DATE:20270705\r\nDTEND;VALUE=DATE:20270707\r\nSUMMARY:Reserved\r\n'
  'END:VEVENT\r\nEND:VCALENDAR\r\n');
select public.ical_poll_feed('f9000000-0000-4000-8000-000000000052');
select is((select period from public.reservations where external_uid = 'london-stay@airbnb.com'),
  tstzrange('2027-07-05 14:00+00','2027-07-07 09:00+00','[)'),
  'another resort''s zone and times are used (Europe/London, 15:00/10:00, summer time)');

-- A valid but empty calendar (an OTA glitch) cancels nothing.
select pending_request_id as fa_next from public.ical_feeds
 where id = 'f9000000-0000-4000-8000-000000000021' \gset
select pg_temp.deliver('f9000000-0000-4000-8000-000000000021', :fa_next, 200,
  E'BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//Airbnb Inc//Hosting Calendar 1.0//EN\r\n'
  'END:VCALENDAR\r\n');
select public.ical_poll_feed('f9000000-0000-4000-8000-000000000021')::text as r9 \gset
select is((:'r9'::jsonb ->> 'events')::int, 0, 'an empty calendar has 0 events');
select is((select array[last_status, last_event_count::text] from public.ical_feeds
            where id = 'f9000000-0000-4000-8000-000000000021'),
  array['ok','0'], 'and is an ok sync');
select is((select count(*)::int from public.reservations
            where external_uid like '%@airbnb.com' and unit_id = 'f9000000-0000-4000-8000-000000000011'
              and status = 'confirmed'),
  2, 'nothing imported earlier is cancelled');

-- Sync now: an admin of the resort may; a staff member may not.
select pending_request_id as fa_next from public.ical_feeds
 where id = 'f9000000-0000-4000-8000-000000000021' \gset
select pg_temp.deliver('f9000000-0000-4000-8000-000000000021', :fa_next, 200,
  (select body from ics where name = 'airbnb'));
set local role authenticated;
set local request.jwt.claims to '{"sub":"f9000000-0000-4000-8000-000000000001","role":"authenticated"}';
select is((select public.ical_poll_feed('f9000000-0000-4000-8000-000000000021') ->> 'status'),
  'ok', 'an admin''s Sync now collects and imports');
set local request.jwt.claims to '{"sub":"f9000000-0000-4000-8000-000000000002","role":"authenticated"}';
select throws_ok($$select public.ical_poll_feed('f9000000-0000-4000-8000-000000000021')$$,
  'P0020', null, 'a staff member cannot trigger a sync');
reset role;
set local request.jwt.claims to '';

-- The wrapper and the helpers.
select is((select count(*)::int from public.ical_parse_events(
    (select body from ics where name = 'edge'))),
  6, 'ical_parse_events returns only the readable events');
select is((select dtstart from public.ical_parse_events(
    (select body from ics where name = 'airbnb')) order by dtstart limit 1),
  '2027-10-09 00:00:00+00'::timestamptz,
  'ical_parse_events keeps its UTC-midnight reading of all-day events');
select is(public.ical_event_period('f9000000-0000-4000-8000-000000000011',
    null, null, '2027-10-09', '2027-10-12'),
  tstzrange('2027-10-09 08:30+00','2027-10-12 05:30+00','[)'),
  'ical_event_period places all-day dates at the resort''s times');
select throws_ok($$select public.ical_event_period('f9000000-0000-4000-8000-000000000011',
    '2028-01-01 10:00+00', '2028-01-01 10:00+00', null, null)$$,
  'P0005', 'invalid event period', 'an empty timed period is refused');
select ok(public.ical_event_is_echo('f9000000-0000-4000-8000-000000000011',
    '2027-11-20', '2027-11-23'),
  'every night taken by our own block: an echo');
select ok(not public.ical_event_is_echo('f9000000-0000-4000-8000-000000000011',
    '2027-11-22', '2027-11-25'),
  'some nights free: not an echo');
select ok(not public.ical_event_is_echo('f9000000-0000-4000-8000-000000000011',
    '2027-11-23', '2027-11-23'),
  'no nights at all: not an echo');

-- === Task 4: feed URL rules (P0039) =========================================

reset role;
set local request.jwt.claims to '';

insert into public.ical_feeds (id, unit_id, url, label) values
  ('f9000000-0000-4000-8000-000000000060','f9000000-0000-4000-8000-000000000012',
   E'  WEBCAL://www.airbnb.com/calendar/ical/77.ics?s=abc \n','Pasted');
select is((select url from public.ical_feeds where id = 'f9000000-0000-4000-8000-000000000060'),
  'https://www.airbnb.com/calendar/ical/77.ics?s=abc',
  'a pasted link is trimmed and webcal:// becomes https://');
select throws_ok($$insert into public.ical_feeds (unit_id, url)
  values ('f9000000-0000-4000-8000-000000000012', 'ftp://example.com/a.ics')$$,
  'P0039', 'invalid_feed_url', 'only http(s) and webcal links are feeds');
select throws_ok($$insert into public.ical_feeds (unit_id, url)
  values ('f9000000-0000-4000-8000-000000000012', 'airbnb.com/calendar/ical/1.ics')$$,
  'P0039', 'invalid_feed_url', 'a link without a scheme is refused');
select throws_ok($$insert into public.ical_feeds (unit_id, url)
  values ('f9000000-0000-4000-8000-000000000012', 'https://')$$,
  'P0039', 'invalid_feed_url', 'a link without a host is refused');
select throws_ok($$insert into public.ical_feeds (unit_id, url)
  values ('f9000000-0000-4000-8000-000000000012', 'https://example.com/my cal.ics')$$,
  'P0039', 'invalid_feed_url', 'a link with a space inside is refused');
select throws_ok($$insert into public.ical_feeds (unit_id, url)
  values ('f9000000-0000-4000-8000-000000000012',
          'webcal://www.airbnb.com/calendar/ical/77.ics?s=abc')$$,
  'P0039', 'duplicate_feed',
  'the webcal:// form of a stored https:// link is the same calendar');
select lives_ok($$insert into public.ical_feeds (unit_id, url)
  values ('f9000000-0000-4000-8000-000000000011',
          'https://www.airbnb.com/calendar/ical/77.ics?s=abc')$$,
  'the same link on another unit is fine');
select throws_ok($$update public.ical_feeds set url = 'not a url'
  where id = 'f9000000-0000-4000-8000-000000000060'$$,
  'P0039', 'invalid_feed_url', 'editing a link checks it too');
select lives_ok($$update public.ical_feeds set label = 'Airbnb'
  where id = 'f9000000-0000-4000-8000-000000000060'$$,
  'editing only the label is not checked');

set local role authenticated;
set local request.jwt.claims to '{"sub":"f9000000-0000-4000-8000-000000000001","role":"authenticated"}';
select throws_ok($$insert into public.ical_feeds (unit_id, url)
  values ('f9000000-0000-4000-8000-000000000012',
          'https://www.airbnb.com/calendar/ical/77.ics?s=abc')$$,
  'P0039', 'duplicate_feed', 'an admin adding a calendar twice gets duplicate_feed');
insert into public.ical_feeds (id, unit_id, url) values
  ('f9000000-0000-4000-8000-000000000061','f9000000-0000-4000-8000-000000000012',
   'webcal://www.booking.com/ical/88.ics');
select is((select url from public.ical_feeds where id = 'f9000000-0000-4000-8000-000000000061'),
  'https://www.booking.com/ical/88.ics', 'an admin''s webcal:// link is stored as https://');
reset role;
set local request.jwt.claims to '';

select * from finish();
rollback;
