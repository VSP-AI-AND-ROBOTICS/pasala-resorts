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
--     a duplicate), the same UID arriving with new non-overlapping dates
--     (`updated`, with the reservation's period actually moved -- Task 10
--     fix-round Finding 2), and a genuine double-booking caught as
--     `conflict` and applied nowhere.
--   - `ical_poll_feed`/the `pg_cron` schedule, exercised only on the
--     paths that need no live network I/O (pg_net IS available in this
--     local stack -- see the migration header and the task report for
--     why the actual HTTP fetch itself is deliberately left untested by
--     pgTAP) -- including, by faking a collected response directly in
--     `net._http_response`, that one feed's malformed event (a
--     zero-duration event or a blank UID) cannot wedge that feed or take
--     down another feed polled in the same batch, and that the wedged
--     feed recovers on its very next poll (Task 10 fix-round Finding 1).

begin;
select plan(68);

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

insert into public.resort_members (property_id, user_id, role) values
  ('e5000000-0000-0000-0000-000000000001','e5000000-0000-0000-0000-000000000011','admin'),
  ('e5000000-0000-0000-0000-000000000001','e5000000-0000-0000-0000-000000000012','staff');

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

-- ical_export is Admin+ of the unit's resort (0045).
set local role authenticated;
set local request.jwt.claims to
  '{"sub":"e5000000-0000-0000-0000-000000000011","role":"authenticated"}';

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
--
-- Revoke sweep: `ical_line_fold` is revoked from `anon`/`authenticated` at
-- the grant layer (0018_ical.sql) -- internal only, same convention as
-- `ical_build_document`/`render_template`. This file's own direct,
-- fold-implementation-level assertions below are exactly the kind of
-- in-database caller that convention still allows (no PostgREST layer, no
-- client role in front of it -- the same shape as `ical_build_document`
-- calling it internally), so the two calls below run as `postgres` (the
-- functions' owner) rather than under this file's `authenticated` test
-- role, then hand back to `authenticated` immediately after for the tests
-- that follow.
set local role postgres;
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
set local role authenticated;
set local request.jwt.claims to
  '{"sub":"e5000000-0000-0000-0000-000000000012","role":"authenticated"}';

-- Admin+ of the unit's resort only (0045): neither a customer nor the
-- resort's staff can pull a unit's export.
set local request.jwt.claims to
  '{"sub":"e5000000-0000-0000-0000-000000000010","role":"authenticated"}';
select throws_ok(
  $$select public.ical_export('e5000000-0000-0000-0000-000000000002')$$,
  'P0020', null,
  'a customer cannot call ical_export directly');

set local request.jwt.claims to
  '{"sub":"e5000000-0000-0000-0000-000000000011","role":"authenticated"}';
select lives_ok(
  $$select public.ical_export('e5000000-0000-0000-0000-000000000002')$$,
  'an admin can call ical_export');

-- === round trip: the parser can read back what the exporter wrote =========
--
-- Revoke sweep: `ical_parse_events` (and, transitively, `ical_parse_datetime`)
-- is revoked from `anon`/`authenticated` at the grant layer -- internal
-- only, reachable in production only through `ical_poll_feed`. This
-- round-trip proof, like the `ical_line_fold` one above, calls it directly
-- as `postgres` (the owner) rather than under the `authenticated` test
-- role, then hands back to `authenticated` immediately after. `ical_export`
-- inside each call is unaffected either way -- it stays granted to
-- `authenticated`, and its own `assert_resort_role` check reads the admin JWT
-- claims set above, not the postgres role, so switching role changes
-- nothing about what it does or doesn't allow.
set local role postgres;
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
set local role authenticated;
set local request.jwt.claims to
  '{"sub":"e5000000-0000-0000-0000-000000000011","role":"authenticated"}';

-- Revoke sweep: `ical_parse_events` is an internal parsing helper for
-- `ical_poll_feed` only (called above via `set local role postgres`, the
-- functions' owner, which bypasses grants same as any other internal
-- helper call in this file) -- revoked from `anon`/`authenticated` at the
-- grant layer in 0018_ical.sql, the same convention as
-- `ical_build_document`/`render_template`. Worth asserting directly: this
-- function walks caller-supplied text, so leaving it reachable by `anon`
-- would be a cheap CPU vector even though it touches no data.
set local role anon;
set local request.jwt.claims to '{"role":"anon"}';
select throws_ok(
  $$select * from public.ical_parse_events(
      'BEGIN:VCALENDAR' || E'\r\n' || 'END:VCALENDAR')$$,
  '42501', null,
  'anon cannot call ical_parse_events directly -- rejected at the grant '
  'layer, before the function body ever runs');
set local role authenticated;

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
  'P0020', null,
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

-- C1: reproduced live before this fix -- a plain `POST
-- /rest/v1/rpc/ical_import_event` carrying only the public anon key
-- returned 200 and created a 7-night `kind = 'ota'` reservation on a real
-- unit. The old guard (`auth.uid() is not null and not is_admin()`) let
-- `anon` straight through, since `auth.uid()` is null for `anon` too -- it
-- was indistinguishable, to that guard, from the trusted cron caller this
-- exemption exists for. The function also kept the PostgreSQL default
-- PUBLIC EXECUTE the whole time (`grant ... to authenticated` never
-- removes it), so `anon` did not even need the guard to fail in its
-- favour -- it never needed any grant at all. Both layers are fixed now:
-- the grant is explicitly revoked from `anon` (asserted here as 42501,
-- before the function body runs at all) and the guard itself now keys on
-- `current_setting('request.jwt.claims', true) is null` -- true only for
-- a genuine in-database caller (pg_cron/direct SQL, no PostgREST layer in
-- front of it) -- rather than on `auth.uid()`, which any client request,
-- anon included, can make come back null.
set local role anon;
set local request.jwt.claims to '{"role":"anon"}';
select throws_ok(
  $$select public.ical_import_event('e5000000-0000-0000-0000-000000000002',
      'anon-exploit-uid', '2028-01-10T14:00:00Z'::timestamptz,
      '2028-01-12T11:00:00Z'::timestamptz)$$,
  '42501', null,
  'C1: anon cannot call ical_import_event at all -- rejected at the grant '
  'layer (42501), the same live exploit the reviewer reproduced against '
  'the running stack before this fix');

set local role postgres;
select is(
  (select count(*)::int from public.reservations
    where external_uid = 'anon-exploit-uid'),
  0,
  'C1: out-of-band check -- the anon call above created no reservation '
  'at all, not even one that a later assertion might miss');

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"e5000000-0000-0000-0000-000000000010","role":"authenticated"}';
select throws_ok(
  $$select public.ical_import_event('e5000000-0000-0000-0000-000000000002',
      'airbnb-uid-1', '2028-01-10T14:00:00Z'::timestamptz,
      '2028-01-12T11:00:00Z'::timestamptz)$$,
  'P0020', null,
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

-- === same UID, different (non-overlapping) dates: `updated`, and the =====
-- === reservation's period actually moves (Task 10 fix-round Finding 2 -- =
-- === previously only `created`, identical re-import (`unchanged`), and a=
-- === different-UID overlap (`conflict`) were covered; the same-UID ======
-- === changed-dates path itself was never exercised) ========================

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"e5000000-0000-0000-0000-000000000011","role":"authenticated"}';

select is(
  (public.ical_import_event('e5000000-0000-0000-0000-000000000002',
     'airbnb-uid-1', '2028-03-01T14:00:00Z'::timestamptz,
     '2028-03-03T11:00:00Z'::timestamptz) ->> 'status'),
  'updated',
  'the same UID arriving with new, non-overlapping dates is reported as '
  'updated');

set local role postgres;
select is(
  (select period from public.reservations
    where external_uid = 'airbnb-uid-1'
      and unit_id = 'e5000000-0000-0000-0000-000000000002'),
  tstzrange('2028-03-01T14:00:00Z'::timestamptz,
            '2028-03-03T11:00:00Z'::timestamptz, '[)'),
  'checked out-of-band: the reservation''s period actually moved to the '
  'new dates, not just the status label');

-- === ical_poll_feed / pg_cron: proven on the paths that need no live ======
-- === network I/O -- see the migration header and task report for why the =
-- === actual HTTP fetch itself is out of scope for pgTAP ===================

select is(
  (select count(*)::int from cron.job where jobname = 'ical-poll-feeds'),
  1, 'the automatic-poll job is scheduled with pg_cron');

-- C1: same vulnerability, same fix, as ical_import_event above -- `anon`
-- held implicit PUBLIC EXECUTE and the old `auth.uid()`-based guard did
-- not stop it either. Left unfixed, `anon` could make the server issue
-- arbitrary outbound HTTP fetches against admin-configured feed URLs on
-- demand, with no authentication at all.
set local role anon;
set local request.jwt.claims to '{"role":"anon"}';
select throws_ok(
  $$select public.ical_poll_feed('00000000-0000-0000-0000-000000000000')$$,
  '42501', null,
  'C1: anon cannot call ical_poll_feed at all -- rejected at the grant '
  'layer (42501), before the function body (and any outbound HTTP fetch, '
  'or even the "feed not found" check) ever runs -- the nonexistent feed '
  'id proves the grant is what stops this, not a lookup failure');

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"e5000000-0000-0000-0000-000000000011","role":"authenticated"}';
select throws_ok(
  $$select public.ical_poll_feed('00000000-0000-0000-0000-000000000000')$$,
  'P0002', null,
  'polling a feed id that does not exist (or is inactive) fails cleanly, '
  'never silently doing nothing');

-- An existing (inactive, so never fetched) feed: the role check runs
-- once the feed's resort is known.
reset role;
insert into public.ical_feeds (id, unit_id, url, label, is_active)
values ('e5000000-0000-0000-0000-000000000031',
        'e5000000-0000-0000-0000-000000000002',
        'https://example.invalid/idle.ics', 'IdleFeed', false);
set local role authenticated;
set local request.jwt.claims to
  '{"sub":"e5000000-0000-0000-0000-000000000010","role":"authenticated"}';
select throws_ok(
  $$select public.ical_poll_feed('e5000000-0000-0000-0000-000000000031')$$,
  'P0020', null,
  'a customer cannot trigger a feed poll -- Sync is admin-only, same as '
  'every other write path here');

-- === Task 10 fix-round Finding 1 (Critical): one malformed feed event ====
-- === must not permanently wedge sync for every unit ========================
--
-- Reproduced live by the reviewer against the running local stack: a
-- feed's fetched response containing a zero-duration event (DTSTART ==
-- DTEND, which `ical_import_event` rejects with a plain, uncaught P0005)
-- or a blank UID (also P0005) crashed `ical_poll_feed` with no exception
-- boundary around the per-event `ical_import_event` call. That aborted
-- the whole call before `pending_request_id` was ever cleared or
-- `last_error` recorded, so the bad feed re-read the same stale response
-- and crashed identically on every subsequent poll -- forever, including
-- via the admin Sync button, and (with no per-feed boundary in
-- `ical_poll_all_feeds` either) took every OTHER unit's already-processed
-- feed result down with it in the same cron tick.
--
-- No live network call is needed to prove this: `ical_poll_feed`'s own
-- two-call state machine already separates "fire the request" from
-- "collect the response" via `net._http_response`, keyed by
-- `pending_request_id` -- so a fetched response is faked the same way a
-- real one would eventually land, by writing directly into
-- `net._http_response` and pointing the feed's `pending_request_id` at
-- it, exactly as the reviewer did.
reset role;
set local role postgres;

insert into public.ical_feeds (id, unit_id, url, label, is_active)
values ('e5000000-0000-0000-0000-000000000040',
        'e5000000-0000-0000-0000-000000000002',
        'https://example.invalid/bad.ics', 'BadFeed', true);
insert into public.ical_feeds (id, unit_id, url, label, is_active)
values ('e5000000-0000-0000-0000-000000000041',
        'e5000000-0000-0000-0000-000000000002',
        'https://example.invalid/good.ics', 'GoodFeed', true);

-- Fake request ids -- chosen far outside pg_net's own low, monotonically
-- assigned range so they cannot collide with a request id pg_net itself
-- hands out later in this same test run.
update public.ical_feeds set pending_request_id = 987654321, pending_since = now()
  where id = 'e5000000-0000-0000-0000-000000000040';
update public.ical_feeds set pending_request_id = 987654322, pending_since = now()
  where id = 'e5000000-0000-0000-0000-000000000041';

-- The bad feed's response: one zero-duration event and one blank-UID
-- event -- both malformed, both real shapes a hostile or buggy OTA feed
-- can send, neither of which `ical_parse_events` filters out (it only
-- requires the three fields to be non-null; an empty-string UID and an
-- equal DTSTART/DTEND both pass that check and reach `ical_import_event`,
-- which is what actually rejects them).
insert into net._http_response (id, status_code, content, timed_out, error_msg)
values (987654321, 200, E'BEGIN:VCALENDAR\r\nVERSION:2.0\r\nBEGIN:VEVENT\r\n'
  'UID:zero-duration-uid\r\nDTSTART:20280301T100000Z\r\n'
  'DTEND:20280301T100000Z\r\nEND:VEVENT\r\nBEGIN:VEVENT\r\nUID:\r\n'
  'DTSTART:20280310T100000Z\r\nDTEND:20280312T100000Z\r\nEND:VEVENT\r\n'
  'END:VCALENDAR\r\n', false, null);

-- The good feed's response: one perfectly valid event, in the SAME
-- `ical_poll_all_feeds()` call as the bad feed above -- mirroring exactly
-- how the reviewer reproduced the cross-feed blast radius.
insert into net._http_response (id, status_code, content, timed_out, error_msg)
values (987654322, 200, E'BEGIN:VCALENDAR\r\nVERSION:2.0\r\nBEGIN:VEVENT\r\n'
  'UID:good-feed-uid\r\nDTSTART:20280401T100000Z\r\n'
  'DTEND:20280403T100000Z\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n', false, null);

-- No session JWT, same as the real pg_cron job -- see the header comments
-- on `ical_import_event` and `ical_poll_feed` for why that is the
-- exemption that lets an automatic poll import anything at all.
reset request.jwt.claims;

select lives_ok(
  $$select public.ical_poll_all_feeds()$$,
  'polling a feed with a malformed event alongside a feed with a valid '
  'event, in the same batch call, does not raise -- one bad feed no '
  'longer takes the whole batch down');

select is(
  (select status from public.reservations
    where external_uid = 'good-feed-uid'
      and unit_id = 'e5000000-0000-0000-0000-000000000002')::text,
  'confirmed',
  'the OTHER feed''s valid event was still imported -- its own processing '
  'was not rolled back by the bad feed''s failure in the same cron tick');

select is(
  (select count(*)::int from public.reservations
    where external_uid = 'zero-duration-uid'),
  0, 'the zero-duration event was never force-imported');

select ok(
  (select last_error from public.ical_feeds
    where id = 'e5000000-0000-0000-0000-000000000040')
    like '2 event(s) failed to import and were skipped%',
  'the bad feed records a last_error, and it accounts for BOTH malformed '
  'events -- the zero-duration one and the blank-UID one -- not just one '
  'of them');

select isnt(
  (select pending_request_id from public.ical_feeds
    where id = 'e5000000-0000-0000-0000-000000000040'),
  987654321::bigint,
  'the bad feed''s pending_request_id no longer points at the stale '
  'response that crashed it -- it advanced to a freshly fired request, '
  'proving the feed is not wedged re-reading the same response forever');

select is(
  (select last_error from public.ical_feeds
    where id = 'e5000000-0000-0000-0000-000000000041'),
  null,
  'the good feed''s own last_error is untouched by the bad feed''s '
  'failure -- the two feeds'' outcomes do not bleed into each other');

-- === recovery: a SUBSEQUENT poll of the previously-wedged feed proceeds ===
-- === rather than repeating the crash, with no direct DB access needed ====
select pending_request_id as bad_feed_next_request
  from public.ical_feeds where id = 'e5000000-0000-0000-0000-000000000040' \gset

insert into net._http_response (id, status_code, content, timed_out, error_msg)
values (:bad_feed_next_request, 200, E'BEGIN:VCALENDAR\r\nVERSION:2.0\r\n'
  'BEGIN:VEVENT\r\nUID:zero-duration-uid\r\nDTSTART:20280301T100000Z\r\n'
  'DTEND:20280301T100000Z\r\nEND:VEVENT\r\n'
  'END:VCALENDAR\r\n', false, null);

select lives_ok(
  $$select public.ical_poll_feed('e5000000-0000-0000-0000-000000000040')$$,
  'polling the previously-wedged feed again proceeds normally -- it does '
  'not repeat the same crash on the same shape of bad event, and needed '
  'no direct DB intervention to recover, only its next scheduled poll');

select ok(
  (select last_error from public.ical_feeds
    where id = 'e5000000-0000-0000-0000-000000000040') is not null,
  'the recovered feed still honestly records the new failure rather than '
  'going silent about it');

select is(
  (select count(*)::int from public.reservations
    where external_uid = 'zero-duration-uid'),
  0, 'the zero-duration event is still never force-imported, even after '
  'recovery');

reset role;

select * from finish();
rollback;
