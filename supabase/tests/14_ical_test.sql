-- iCal export/import for OTA calendar sync (Airbnb/Booking.com), without a
-- paid channel manager. Covers, in order:
--   - `ical_export`: one VCALENDAR, exactly one VEVENT for a confirmed
--     booking, correct UTC DTSTART/DTEND, RFC 5545 line folding at 75
--     octets, no guest name/email anywhere, and a cancelled booking never
--     appears.
--   - a self-consistency round trip: the exported document, fed straight
--     back through `ical_parse_events`, yields the same UID/DTSTART/DTEND
--     -- proof the fold/escape logic and the parser agree with each other,
--     with no live network call needed.
--   - `ical_feeds` CRUD, admin-only.
--   - the token-gated public export endpoint (`rotate_ical_token` /
--     `ical_export_public`), reachable by `anon` -- the whole point, since
--     an OTA cannot authenticate -- and reachable ONLY with a valid token.
--   - `ical_import_event`: create, idempotent re-import (`unchanged`, not
--     a duplicate), and a genuine double-booking caught as `conflict` and
--     applied nowhere.
--   - `ical_poll_feed`/the `pg_cron` schedule, exercised only on the
--     paths that need no live network I/O (pg_net IS available in this
--     local stack -- see the migration header and the task report for
--     why the actual HTTP fetch itself is deliberately left untested by
--     pgTAP).

begin;
select plan(53);

select has_table('public', 'ical_feeds', 'ical_feeds table exists');
select has_column('public', 'ical_feeds', 'unit_id', 'ical_feeds has unit_id');
select has_column('public', 'ical_feeds', 'url', 'ical_feeds has url');
select has_column('public', 'ical_feeds', 'label', 'ical_feeds has label');
select has_column('public', 'ical_feeds', 'is_active', 'ical_feeds has is_active');
select has_column('public', 'ical_feeds', 'last_synced_at',
  'ical_feeds has last_synced_at');
select has_column('public', 'ical_feeds', 'last_error', 'ical_feeds has last_error');
select has_column('public', 'reservations', 'external_uid',
  'reservations gains external_uid for idempotent re-import');
select has_function('public', 'ical_export', 'ical_export() exists');
select has_function('public', 'ical_import_event', 'ical_import_event() exists');
select has_function('public', 'ical_export_public', 'ical_export_public() exists');
select has_function('public', 'rotate_ical_token', 'rotate_ical_token() exists');
select has_function('public', 'ical_poll_feed', 'ical_poll_feed() exists');

-- === fixtures ===============================================================

insert into public.properties (id, name, slug)
values ('e5000000-0000-0000-0000-000000000001', 'IcalProp', 'ical-prop');
insert into public.units (id, property_id, name, capacity_base, capacity_max)
values ('e5000000-0000-0000-0000-000000000002',
        'e5000000-0000-0000-0000-000000000001', 'IcalUnit', 2, 4);

insert into auth.users (id, email) values
  ('e5000000-0000-0000-0000-000000000010', 'icalcust@example.com'),
  ('e5000000-0000-0000-0000-000000000011', 'icaladmin@example.com'),
  ('e5000000-0000-0000-0000-000000000012', 'icalstaff@example.com');
update public.profiles set full_name = 'Priya Guestperson'
  where id = 'e5000000-0000-0000-0000-000000000010';
update public.profiles set role = 'admin'
  where id = 'e5000000-0000-0000-0000-000000000011';
update public.profiles set role = 'staff'
  where id = 'e5000000-0000-0000-0000-000000000012';

-- A confirmed booking with an identifiable guest name/email, expressed as
-- an explicit UTC tstzrange (bypassing build_period) so the expected
-- DTSTART/DTEND strings below are exact literals, not re-derived.
insert into public.reservations
  (id, unit_id, period, kind, status, customer_id, guests, quote, source)
values (
  'e5000000-0000-0000-0000-000000000020',
  'e5000000-0000-0000-0000-000000000002',
  tstzrange('2027-05-10 08:30:00+00', '2027-05-12 06:00:00+00', '[)'),
  'booking', 'confirmed', 'e5000000-0000-0000-0000-000000000010', 2,
  jsonb_build_object('total', 12000.00), 'app');

-- A cancelled booking on a different, non-overlapping range -- must never
-- appear in the export.
insert into public.reservations
  (id, unit_id, period, kind, status, customer_id, guests, quote, source)
values (
  'e5000000-0000-0000-0000-000000000021',
  'e5000000-0000-0000-0000-000000000002',
  tstzrange('2027-06-01 08:30:00+00', '2027-06-03 06:00:00+00', '[)'),
  'booking', 'cancelled', 'e5000000-0000-0000-0000-000000000010', 2,
  jsonb_build_object('total', 12000.00), 'app');

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"e5000000-0000-0000-0000-000000000012","role":"authenticated"}';

-- === ical_export: shape, contents, identity, RFC 5545 folding =============

select ok(
  (select public.ical_export('e5000000-0000-0000-0000-000000000002')
    like '%BEGIN:VCALENDAR%'),
  'export document contains BEGIN:VCALENDAR');

select ok(
  (select public.ical_export('e5000000-0000-0000-0000-000000000002')
    like '%VERSION:2.0%'),
  'export document declares VERSION:2.0');

select ok(
  (select public.ical_export('e5000000-0000-0000-0000-000000000002')
    like '%CALSCALE:GREGORIAN%'),
  'export document declares CALSCALE:GREGORIAN');

select is(
  (select count(*)::int
   from regexp_matches(
     public.ical_export('e5000000-0000-0000-0000-000000000002'),
     'BEGIN:VEVENT', 'g')),
  1,
  'exactly one BEGIN:VEVENT -- the cancelled booking does not appear');

select ok(
  (select public.ical_export('e5000000-0000-0000-0000-000000000002')
    like '%DTSTART:20270510T083000Z%'),
  'DTSTART is the confirmed booking''s check-in, in UTC yyyymmddThhmmssZ form');

select ok(
  (select public.ical_export('e5000000-0000-0000-0000-000000000002')
    like '%DTEND:20270512T060000Z%'),
  'DTEND is the confirmed booking''s check-out, in UTC yyyymmddThhmmssZ form '
  '-- exclusive, matching the half-open tstzrange it came from');

select ok(
  (select public.ical_export('e5000000-0000-0000-0000-000000000002')
    not ilike '%Priya%'),
  'export contains no guest name, anywhere');

select ok(
  (select public.ical_export('e5000000-0000-0000-0000-000000000002')
    not ilike '%icalcust@example.com%'),
  'export contains no guest email, anywhere');

select ok(
  (select public.ical_export('e5000000-0000-0000-0000-000000000002')
    not like '%20270601%'),
  'the cancelled booking''s dates do not appear in the export at all');

-- RFC 5545 line folding: no physical (CRLF-separated) line may exceed 75
-- octets. Nothing in THIS fixture's small document actually reaches 75
-- octets on any one line (every value here is short), so this only proves
-- the trivial "already under threshold" case -- `ical_line_fold` itself is
-- exercised directly, below, against content well past 75 octets, which is
-- the assertion that would actually catch a broken fold implementation.
select ok(
  (select bool_and(octet_length(line) <= 75)
   from regexp_split_to_table(
     rtrim(public.ical_export('e5000000-0000-0000-0000-000000000002'), E'\r\n'),
     E'\r\n') as line),
  'every physical line of the export is <= 75 octets, per RFC 5545 folding');

-- `ical_line_fold` against 200 octets of content -- well past the 75-octet
-- threshold, so this actually exercises the fold, not just the pass-through
-- case above.
select ok(
  (select bool_and(octet_length(line) <= 75)
   from regexp_split_to_table(public.ical_line_fold(repeat('x', 200)), E'\r\n') as line),
  'ical_line_fold keeps every physical line <= 75 octets for content well '
  'past the fold threshold');

select is(
  (select regexp_replace(public.ical_line_fold(repeat('x', 200)), E'\r\n ', '', 'g')),
  repeat('x', 200),
  'unfolding ical_line_fold''s output (deleting each CRLF + its single '
  'leading space) reconstructs the original 200-octet content exactly -- '
  'the fold adds no content and drops none');

-- staff-or-above only: a customer cannot pull any unit's export.
set local request.jwt.claims to
  '{"sub":"e5000000-0000-0000-0000-000000000010","role":"authenticated"}';
select throws_ok(
  $$select public.ical_export('e5000000-0000-0000-0000-000000000002')$$,
  'P0008', null,
  'a customer cannot call ical_export directly');

set local request.jwt.claims to
  '{"sub":"e5000000-0000-0000-0000-000000000011","role":"authenticated"}';
select lives_ok(
  $$select public.ical_export('e5000000-0000-0000-0000-000000000002')$$,
  'an admin can call ical_export');

-- === round trip: the parser can read back what the exporter wrote =========

select is(
  (select count(*)::int from public.ical_parse_events(
    public.ical_export('e5000000-0000-0000-0000-000000000002'))),
  1,
  'parsing the exported document back yields exactly one event');

select ok(
  (select uid from public.ical_parse_events(
    public.ical_export('e5000000-0000-0000-0000-000000000002')) limit 1)
  like 'e5000000-0000-0000-0000-000000000020%',
  'the round-tripped UID is keyed on the reservation id');

select is(
  (select dtstart from public.ical_parse_events(
    public.ical_export('e5000000-0000-0000-0000-000000000002')) limit 1),
  '2027-05-10 08:30:00+00'::timestamptz,
  'the round-tripped DTSTART matches the original period''s lower bound');

select is(
  (select dtend from public.ical_parse_events(
    public.ical_export('e5000000-0000-0000-0000-000000000002')) limit 1),
  '2027-05-12 06:00:00+00'::timestamptz,
  'the round-tripped DTEND matches the original period''s upper bound');

-- === ical_feeds CRUD, admin-only ===========================================

set local request.jwt.claims to
  '{"sub":"e5000000-0000-0000-0000-000000000010","role":"authenticated"}';
select throws_ok(
  $$insert into public.ical_feeds (unit_id, url, label)
    values ('e5000000-0000-0000-0000-000000000002',
            'https://airbnb.com/calendar/ical/1.ics', 'Airbnb')$$,
  '42501', null, 'a customer cannot add an import feed');

set local request.jwt.claims to
  '{"sub":"e5000000-0000-0000-0000-000000000011","role":"authenticated"}';
insert into public.ical_feeds (id, unit_id, url, label)
values ('e5000000-0000-0000-0000-000000000030',
        'e5000000-0000-0000-0000-000000000002',
        'https://airbnb.com/calendar/ical/1.ics', 'Airbnb');

select is(
  (select label from public.ical_feeds
    where id = 'e5000000-0000-0000-0000-000000000030'),
  'Airbnb', 'an admin can add and read back an import feed');

update public.ical_feeds
  set last_synced_at = now(), last_error = 'HTTP 503'
  where id = 'e5000000-0000-0000-0000-000000000030';
select is(
  (select last_error from public.ical_feeds
    where id = 'e5000000-0000-0000-0000-000000000030'),
  'HTTP 503', 'an admin can record a sync error honestly, not silently');

delete from public.ical_feeds
where id = 'e5000000-0000-0000-0000-000000000030';
select is(
  (select count(*)::int from public.ical_feeds
    where id = 'e5000000-0000-0000-0000-000000000030'),
  0, 'an admin can remove an import feed');

-- === token-gated public export: the URL an OTA (which cannot ============
-- === authenticate) can actually fetch ======================================

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"e5000000-0000-0000-0000-000000000012","role":"authenticated"}';
select throws_ok(
  $$select public.rotate_ical_token('e5000000-0000-0000-0000-000000000002')$$,
  'P0008', null,
  'a staff member (not admin) cannot rotate the export token');

set local request.jwt.claims to
  '{"sub":"e5000000-0000-0000-0000-000000000011","role":"authenticated"}';

select lives_ok(
  $$select public.rotate_ical_token('e5000000-0000-0000-0000-000000000002')$$,
  'an admin can rotate the unit''s export token');

reset role;
set local role postgres;
select is(
  (select count(*)::int from public.ical_export_tokens
    where unit_id = 'e5000000-0000-0000-0000-000000000002'),
  1, 'exactly one export-token row exists for the unit');

-- `ical_export_tokens` is admin-only readable (see the migration header --
-- it is deliberately never exposed to `anon`), so the token itself is
-- captured here, as postgres, into a psql variable via \gset, and passed
-- to `ical_export_public` as a literal below -- an anon client in the real
-- world holds this same opaque string because an admin pasted the URL
-- into Airbnb, not because it queried the database for it.
select token as ical_token from public.ical_export_tokens
  where unit_id = 'e5000000-0000-0000-0000-000000000002' \gset

set local role anon;
set local request.jwt.claims to '{"role":"anon"}';

select ok(
  (select public.ical_export_public(:'ical_token') like '%BEGIN:VCALENDAR%'),
  'anon, holding the current token, can fetch the export -- this is the '
  'whole point: an OTA that cannot authenticate still gets the calendar');

select throws_ok(
  $$select public.ical_export_public('not-a-real-token')$$,
  'P0002', null,
  'anon with a wrong/unknown token gets a clean not-found, not the calendar');

reset role;

-- === ical_import_event =====================================================

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"e5000000-0000-0000-0000-000000000010","role":"authenticated"}';
select throws_ok(
  $$select public.ical_import_event('e5000000-0000-0000-0000-000000000002',
      'airbnb-uid-1', '2028-01-10T14:00:00Z'::timestamptz,
      '2028-01-12T11:00:00Z'::timestamptz)$$,
  'P0008', null,
  'a customer cannot import an OTA event');

set local request.jwt.claims to
  '{"sub":"e5000000-0000-0000-0000-000000000011","role":"authenticated"}';

select is(
  (public.ical_import_event('e5000000-0000-0000-0000-000000000002',
     'airbnb-uid-1', '2028-01-10T14:00:00Z'::timestamptz,
     '2028-01-12T11:00:00Z'::timestamptz) ->> 'status'),
  'created', 'importing a brand-new UID creates a reservation');

set local role postgres;
select is(
  (select kind from public.reservations
    where external_uid = 'airbnb-uid-1'
      and unit_id = 'e5000000-0000-0000-0000-000000000002')::text,
  'ota', 'the imported reservation carries kind = ota');
select is(
  (select status from public.reservations
    where external_uid = 'airbnb-uid-1'
      and unit_id = 'e5000000-0000-0000-0000-000000000002')::text,
  'confirmed', 'the imported reservation is confirmed -- it blocks the dates');
select is(
  (select customer_id from public.reservations
    where external_uid = 'airbnb-uid-1'
      and unit_id = 'e5000000-0000-0000-0000-000000000002'),
  null, 'the imported reservation carries no customer identity at all');

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"e5000000-0000-0000-0000-000000000011","role":"authenticated"}';

select is(
  (public.ical_import_event('e5000000-0000-0000-0000-000000000002',
     'airbnb-uid-1', '2028-01-10T14:00:00Z'::timestamptz,
     '2028-01-12T11:00:00Z'::timestamptz) ->> 'status'),
  'unchanged', 're-importing the identical UID/period is unchanged, not a duplicate');

set local role postgres;
select is(
  (select count(*)::int from public.reservations
    where external_uid = 'airbnb-uid-1'
      and unit_id = 'e5000000-0000-0000-0000-000000000002'),
  1, 're-importing the same UID never creates a second row');
set local role authenticated;
set local request.jwt.claims to
  '{"sub":"e5000000-0000-0000-0000-000000000011","role":"authenticated"}';

-- A second, DIFFERENT event that overlaps the confirmed booking fixture
-- above (2027-05-10 08:30Z to 2027-05-12 06:00Z) -- a genuine double-booking
-- the exclusion constraint must catch, reported as `conflict`, never
-- force-applied.
select is(
  (public.ical_import_event('e5000000-0000-0000-0000-000000000002',
     'airbnb-uid-conflict', '2027-05-11T00:00:00Z'::timestamptz,
     '2027-05-13T00:00:00Z'::timestamptz) ->> 'status'),
  'conflict',
  'an event overlapping an existing confirmed booking is reported as a conflict');

select isnt(
  (public.ical_import_event('e5000000-0000-0000-0000-000000000002',
     'airbnb-uid-conflict', '2027-05-11T00:00:00Z'::timestamptz,
     '2027-05-13T00:00:00Z'::timestamptz) ->> 'conflict'),
  null, 'the conflict payload is populated, not silently swallowed');

set local role postgres;
select is(
  (select count(*)::int from public.reservations
    where external_uid = 'airbnb-uid-conflict'),
  0, 'a conflicting import creates nothing at all');

-- === ical_poll_feed / pg_cron: proven on the paths that need no live ======
-- === network I/O -- see the migration header and task report for why the =
-- === actual HTTP fetch itself is out of scope for pgTAP ===================

select is(
  (select count(*)::int from cron.job where jobname = 'ical-poll-feeds'),
  1, 'the automatic-poll job is scheduled with pg_cron');

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"e5000000-0000-0000-0000-000000000011","role":"authenticated"}';
select throws_ok(
  $$select public.ical_poll_feed('00000000-0000-0000-0000-000000000000')$$,
  'P0002', null,
  'polling a feed id that does not exist (or is inactive) fails cleanly, '
  'never silently doing nothing');

set local request.jwt.claims to
  '{"sub":"e5000000-0000-0000-0000-000000000010","role":"authenticated"}';
select throws_ok(
  $$select public.ical_poll_feed('00000000-0000-0000-0000-000000000000')$$,
  'P0008', null,
  'a customer cannot trigger a feed poll -- Sync is admin-only, same as '
  'every other write path here');

reset role;

select * from finish();
rollback;
