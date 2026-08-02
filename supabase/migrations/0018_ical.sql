-- iCal export and import for OTA calendar sync (Airbnb/Booking.com), with
-- no paid channel manager -- both OTAs publish and consume plain RFC 5545
-- iCal without a commercial agreement.
--
-- pg_net IS installed in this local stack (schema `extensions`, checked
-- directly against the running database before writing this migration --
-- see the task report), so the automatic-poll job below is real: a
-- `pg_cron` schedule fetches every active feed with `net.http_get` and
-- feeds the response through `ical_parse_events`/`ical_import_event`. The
-- admin UI's "Sync" button drives the exact same `ical_poll_feed` function
-- on demand, so the two paths cannot drift apart.
--
-- The export side must be reachable by an OTA that cannot authenticate.
-- The chosen shape is a per-unit opaque token (`ical_export_tokens`,
-- generated with 24 bytes -- 192 bits -- from pgcrypto's
-- `gen_random_bytes`), NOT a column on `units` itself: `units_read` is a
-- public policy (`grant select on units to anon, authenticated`, used by
-- the ordinary browse screens), so anything stored directly on `units`
-- would be handed to every anonymous browse-screen query and the token
-- would carry zero more security than the unit's own id. Kept in its own
-- admin-only-readable table instead, it is never returned by any query a
-- customer or the browse UI makes. `rotate_ical_token` (admin-only)
-- generates a fresh one, invalidating the previous URL instantly if it
-- ever leaks. The trade-off, spelled out because the brief asked for it
-- explicitly: if the token itself leaks, the finder can fetch ONE unit's
-- busy/free calendar -- no names, no emails, no amounts, nothing
-- `ical_build_document` ever touches -- and revoking it is one admin
-- click away. That is the trade-off the brief accepts ("an export feed
-- leaking occupancy is acceptable, one leaking guest identity is not"),
-- and it is structurally true here, not just a policy promise: the
-- builder function only ever reads `unit_calendar_events`, which has no
-- identity columns to begin with.

-- === idempotent re-import ===================================================

alter table public.reservations add column external_uid text;

-- One external UID per unit can map to at most one reservation -- this is
-- what makes `ical_import_event` idempotent: re-importing the same UID
-- looks this up and updates/no-ops instead of inserting a duplicate. Two
-- DIFFERENT units may coincidentally see the same UID from two different
-- feeds without collision (the underlying calendar providers only
-- guarantee UID uniqueness within their own feed).
create unique index reservations_unit_external_uid_idx
  on public.reservations(unit_id, external_uid)
  where external_uid is not null;

-- === import feeds (subscriptions FROM another calendar, e.g. Airbnb's) ====

create table public.ical_feeds (
  id              uuid primary key default gen_random_uuid(),
  unit_id         uuid not null references public.units(id) on delete cascade,
  url             text not null,
  label           text,
  is_active       boolean not null default true,
  last_synced_at  timestamptz,
  last_error      text,
  created_at      timestamptz not null default now(),
  -- Bookkeeping for `ical_poll_feed`'s two-call async state machine -- see
  -- that function's own header comment for why this exists instead of a
  -- single blocking call. `pending_request_id` is pg_net's own request id
  -- (`net.http_get`'s return value) for a fetch that has been fired but
  -- not yet collected; null whenever no fetch is in flight.
  pending_request_id bigint,
  pending_since       timestamptz
);

create index ical_feeds_unit_idx on public.ical_feeds(unit_id);
create index ical_feeds_active_idx on public.ical_feeds(is_active) where is_active;

grant select on public.ical_feeds to authenticated;
grant insert, update, delete on public.ical_feeds to authenticated;

alter table public.ical_feeds enable row level security;

create policy ical_feeds_admin on public.ical_feeds
  for all to authenticated
  using (public.is_admin())
  with check (public.is_admin());

-- === export tokens (capability to fetch ONE unit's export, held by ========
-- === whichever OTA the admin pasted the URL into) ==========================
--
-- Deliberately its own table, not a column on `units` -- see the migration
-- header. `rotated_at` exists purely for the admin screen to show "token
-- last rotated on <date>", never read by any function here.
create table public.ical_export_tokens (
  unit_id    uuid primary key references public.units(id) on delete cascade,
  token      text not null unique
               default encode(extensions.gen_random_bytes(24), 'hex'),
  rotated_at timestamptz not null default now()
);

-- Admin-only read/write. No `anon` grant at all -- the only anon-reachable
-- door onto this table is `ical_export_public` below, which looks up a
-- token but never returns one.
grant select on public.ical_export_tokens to authenticated;
grant insert, update, delete on public.ical_export_tokens to authenticated;

alter table public.ical_export_tokens enable row level security;

create policy ical_export_tokens_admin on public.ical_export_tokens
  for all to authenticated
  using (public.is_admin())
  with check (public.is_admin());

-- Every unit gets a token the moment it exists, so the admin OTA screen
-- never has to special-case "no token yet".
create function public.ical_provision_token()
returns trigger
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
begin
  insert into public.ical_export_tokens (unit_id)
  values (new.id)
  on conflict (unit_id) do nothing;
  return new;
end;
$$;

create trigger units_provision_ical_token
  after insert on public.units
  for each row execute function public.ical_provision_token();

-- Backfill every unit that already existed before this migration.
insert into public.ical_export_tokens (unit_id)
select id from public.units
on conflict (unit_id) do nothing;

create function public.rotate_ical_token(p_unit_id uuid)
returns text
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_token text;
begin
  if not public.is_admin() then
    raise exception 'not permitted' using errcode = 'P0008';
  end if;

  v_token := encode(extensions.gen_random_bytes(24), 'hex');

  insert into public.ical_export_tokens (unit_id, token, rotated_at)
  values (p_unit_id, v_token, now())
  on conflict (unit_id) do update
    set token = excluded.token, rotated_at = now();

  return v_token;
end;
$$;

grant execute on function public.rotate_ical_token(uuid) to authenticated;

-- === RFC 5545 helpers ========================================================

-- Folds `p_line` at 75 octets per RFC 5545 3.1: a continuation line is
-- CRLF followed by exactly one leading space, which is NOT part of the
-- content -- a compliant reader strips exactly one leading whitespace
-- character when unfolding, nothing more. The first physical line gets
-- the full 75 octets; every continuation line gets 74 (75 minus the
-- leading space it re-adds). Chunked by character count then shrunk until
-- it actually fits in 75/74 OCTETS, so this holds even if a value ever
-- contains multi-byte UTF-8 (none of this schema's text does today, but
-- the function does not assume that of its caller).
create function public.ical_line_fold(p_line text)
returns text
language plpgsql
immutable
set search_path = public, pg_temp
as $$
declare
  v_out       text := '';
  v_remaining text := p_line;
  v_chunk     text;
  v_limit     int  := 75;
begin
  if octet_length(v_remaining) <= 75 then
    return v_remaining;
  end if;

  loop
    v_chunk := left(v_remaining, v_limit);
    while octet_length(v_chunk) > v_limit loop
      v_chunk := left(v_chunk, length(v_chunk) - 1);
    end loop;

    v_out := case when v_out = '' then v_chunk
                  else v_out || E'\r\n ' || v_chunk end;
    v_remaining := substring(v_remaining from length(v_chunk) + 1);
    exit when v_remaining = '';
    v_limit := 74;
  end loop;

  return v_out;
end;
$$;

-- Escapes `,`, `;`, `\` and embedded newlines per RFC 5545 3.3.11. Order
-- matters: the backslash itself must be escaped FIRST, or the backslashes
-- this function inserts for `,`/`;`/newline would themselves get
-- re-escaped on a second pass.
create function public.ical_escape_text(p_text text)
returns text
language sql
immutable
set search_path = public, pg_temp
as $$
  select replace(replace(replace(replace(
    coalesce(p_text, ''),
    '\', '\\'), ';', '\;'), ',', '\,'), E'\n', '\n');
$$;

-- === the document builder ====================================================
--
-- Reads `unit_calendar_events`, the identity-free occupancy mirror (Task
-- 15), not `reservations` directly -- it already excludes cancelled rows
-- (the sync trigger deletes their mirror row) and carries no customer_id,
-- no quote, no block_reason, so "no guest name or email anywhere in the
-- output" is true structurally, not by this function remembering to leave
-- columns out.
--
-- Internal only -- not granted to anyone. `ical_export` (staff-or-above,
-- takes a raw unit_id) and `ical_export_public` (anon, takes a token) are
-- the two gated entry points that call this; see the revoke block below.
create function public.ical_build_document(p_unit_id uuid)
returns text
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_exists boolean;
  v_lines  text[] := array[]::text[];
  v_row    record;
  v_now    text := to_char(now() at time zone 'UTC', 'YYYYMMDD"T"HH24MISS"Z"');
begin
  select true into v_exists from public.units where id = p_unit_id;
  if not found then
    raise exception 'unit not found' using errcode = 'P0002';
  end if;

  v_lines := array_append(v_lines, public.ical_line_fold('BEGIN:VCALENDAR'));
  v_lines := array_append(v_lines, public.ical_line_fold('VERSION:2.0'));
  v_lines := array_append(v_lines, public.ical_line_fold(
    'PRODID:-//Pasala Resorts//iCal Export//EN'));
  v_lines := array_append(v_lines, public.ical_line_fold('CALSCALE:GREGORIAN'));

  for v_row in
    select reservation_id, period, kind
    from public.unit_calendar_events
    where unit_id = p_unit_id
    order by lower(period)
  loop
    v_lines := array_append(v_lines, public.ical_line_fold('BEGIN:VEVENT'));
    v_lines := array_append(v_lines, public.ical_line_fold(
      'UID:' || v_row.reservation_id::text || '@pasala-resorts'));
    v_lines := array_append(v_lines, public.ical_line_fold('DTSTAMP:' || v_now));
    v_lines := array_append(v_lines, public.ical_line_fold(
      'DTSTART:' || to_char(lower(v_row.period) at time zone 'UTC',
        'YYYYMMDD"T"HH24MISS"Z"')));
    -- DTEND in RFC 5545 is EXCLUSIVE -- "the date/time the event ends,
    -- not included" -- which is exactly what the upper bound of our
    -- half-open `[)` tstzrange already means. No semantic conversion
    -- happens here, only a format one; a future reader should not go
    -- looking for an off-by-one adjustment that was never needed.
    v_lines := array_append(v_lines, public.ical_line_fold(
      'DTEND:' || to_char(upper(v_row.period) at time zone 'UTC',
        'YYYYMMDD"T"HH24MISS"Z"')));
    v_lines := array_append(v_lines, public.ical_line_fold(
      'SUMMARY:' || public.ical_escape_text(
        case v_row.kind when 'block' then 'Unavailable' else 'Booked' end)));
    v_lines := array_append(v_lines, public.ical_line_fold('END:VEVENT'));
  end loop;

  v_lines := array_append(v_lines, public.ical_line_fold('END:VCALENDAR'));

  return array_to_string(v_lines, E'\r\n') || E'\r\n';
end;
$$;

-- Staff-or-above, raw unit_id -- the admin UI's own preview path (and
-- what pgTAP exercises directly).
create function public.ical_export(p_unit_id uuid)
returns text
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  perform public.assert_staff();
  return public.ical_build_document(p_unit_id);
end;
$$;

grant execute on function public.ical_export(uuid) to authenticated;

-- anon, token-gated -- the actual URL an OTA fetches. See the migration
-- header for the token/security trade-off.
create function public.ical_export_public(p_token text)
returns text
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_unit_id uuid;
begin
  select unit_id into v_unit_id
  from public.ical_export_tokens
  where token = p_token;

  if not found then
    raise exception 'invalid or unknown iCal token' using errcode = 'P0002';
  end if;

  return public.ical_build_document(v_unit_id);
end;
$$;

grant execute on function public.ical_export_public(text) to anon, authenticated;

-- Internal only, same convention as `render_template`/
-- `release_reservation_coupon` elsewhere in this schema: never callable
-- directly, only through the two gated wrappers above.
revoke execute on function public.ical_build_document(uuid) from public;
revoke execute on function public.ical_build_document(uuid) from anon, authenticated;

-- === import ==================================================================
--
-- Creates/updates an `ota`-kind, identity-free reservation that blocks
-- `[p_start, p_end)` on `p_unit_id`, keyed on `p_uid` so re-importing the
-- same UID is idempotent (`unchanged`, never a duplicate row -- enforced
-- structurally by `reservations_unit_external_uid_idx` above, not just by
-- this function's own lookup). A genuine overlap with an existing,
-- non-cancelled reservation is caught via `reservations_no_overlap`'s
-- `exclusion_violation` and reported as `conflict` -- never silently
-- resolved, never force-applied.
create function public.ical_import_event(
  p_unit_id uuid,
  p_uid     text,
  p_start   timestamptz,
  p_end     timestamptz
) returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_existing public.reservations;
  v_period   tstzrange;
  v_id       uuid;
begin
  -- `auth.uid()` is only ever non-null for a real client request that
  -- carried a JWT through PostgREST (this function is granted to
  -- `authenticated` only -- `anon` gets 42501 before the body even runs,
  -- with no grant at all). `ical_poll_feed` (called either by an admin's
  -- Sync press or by the pg_cron job below, which runs as `postgres` with
  -- no session JWT) calls this function directly with no client request
  -- in play at all, so `auth.uid()` is null there. Rejecting only "a real
  -- authenticated caller who isn't an admin" -- not "no client caller at
  -- all" -- is what lets the automatic poll actually import anything;
  -- gating on `is_admin()` alone made every cron-driven import fail with
  -- P0008, since a cron tick has no profile to look up in the first
  -- place (caught by hand-testing the poll end-to-end against a real
  -- local HTTP server -- see the task report).
  if auth.uid() is not null and not public.is_admin() then
    raise exception 'not permitted' using errcode = 'P0008';
  end if;

  if p_uid is null or btrim(p_uid) = '' then
    raise exception 'external UID is required' using errcode = 'P0005';
  end if;
  if p_start is null or p_end is null or p_end <= p_start then
    raise exception 'invalid event period' using errcode = 'P0005';
  end if;

  v_period := tstzrange(p_start, p_end, '[)');

  select * into v_existing
  from public.reservations
  where unit_id = p_unit_id and external_uid = p_uid;

  if found then
    if v_existing.status <> 'cancelled' and v_existing.period = v_period then
      return jsonb_build_object(
        'status', 'unchanged', 'reservation_id', v_existing.id, 'conflict', null);
    end if;

    begin
      update public.reservations
        set period = v_period, status = 'confirmed'
        where id = v_existing.id
        returning id into v_id;

      return jsonb_build_object(
        'status', 'updated', 'reservation_id', v_id, 'conflict', null);
    exception when exclusion_violation then
      return jsonb_build_object(
        'status', 'conflict', 'reservation_id', null,
        'conflict', jsonb_build_object(
          'unit_id', p_unit_id, 'start', p_start, '"end"', p_end));
    end;
  end if;

  begin
    insert into public.reservations
      (unit_id, period, kind, status, external_uid, source)
    values (p_unit_id, v_period, 'ota', 'confirmed', p_uid, 'ical')
    returning id into v_id;

    return jsonb_build_object(
      'status', 'created', 'reservation_id', v_id, 'conflict', null);
  exception when exclusion_violation then
    return jsonb_build_object(
      'status', 'conflict', 'reservation_id', null,
      'conflict', jsonb_build_object(
        'unit_id', p_unit_id, 'start', p_start, '"end"', p_end));
  end;
end;
$$;

grant execute on function
  public.ical_import_event(uuid, text, timestamptz, timestamptz)
  to authenticated;

-- === parsing a raw ICS document (used by the poller; also directly ========
-- === testable/round-trippable without any network I/O) =====================

-- Best-effort DTSTART/DTEND value parser: UTC (`...Z`), `VALUE=DATE`
-- (all-day, e.g. Airbnb's checkin/checkout dates -- midnight UTC), and
-- `TZID=<zone>` local wall-clock time. Floating time (neither Z nor TZID)
-- falls back to UTC -- RFC 5545 leaves that case to the consumer's own
-- convention, and this server has no other one to apply.
--
-- The double cast (`to_timestamp(...)::timestamp at time zone v_tz`) is
-- the same trick `build_period` uses elsewhere in this schema: casting a
-- `to_timestamp`-built timestamptz down to a plain `timestamp` renders it
-- in whatever the SESSION's timezone happens to be, and re-attaching
-- `at time zone v_tz` interprets those exact same field values as being
-- IN v_tz -- so the session's own timezone cancels out of the result
-- either way, and only v_tz (or UTC) ever determines the outcome.
create function public.ical_parse_datetime(p_value text, p_params text)
returns timestamptz
language plpgsql
stable
set search_path = public, pg_temp
as $$
declare
  v_tzid text;
begin
  if p_value is null or p_value = '' then
    return null;
  end if;

  if p_params ilike '%VALUE=DATE%' and p_value !~ 'T' then
    return to_timestamp(p_value, 'YYYYMMDD')::timestamp at time zone 'UTC';
  end if;

  -- The literal "T" separator must be double-quoted in the format string
  -- -- a bare, unquoted `T` is not a documented to_timestamp template code,
  -- and empirically causes HH24MISS to parse as all-zero rather than
  -- raising, which silently truncated every timed event to midnight
  -- before this was caught (see the round-trip assertions in
  -- 14_ical_test.sql that would have passed anyway had this only been
  -- exercised against a same-day-at-midnight fixture).
  if right(p_value, 1) = 'Z' then
    return to_timestamp(left(p_value, length(p_value) - 1),
      'YYYYMMDD"T"HH24MISS')::timestamp at time zone 'UTC';
  end if;

  if p_params ~* 'TZID=' then
    v_tzid := substring(p_params from 'TZID=([^;:]+)');
    return to_timestamp(p_value, 'YYYYMMDD"T"HH24MISS')::timestamp
      at time zone v_tzid;
  end if;

  return to_timestamp(p_value, 'YYYYMMDD"T"HH24MISS')::timestamp at time zone 'UTC';
end;
$$;

-- Unfolds RFC 5545 line folding, then walks VEVENT blocks extracting
-- UID/DTSTART/DTEND. Deliberately not a full RFC 5545 parser (no VALARM,
-- no RRULE, no multi-calendar files beyond the one VCALENDAR a feed
-- normally sends) -- real OTA feeds are simple, and this covers exactly
-- what `ical_import_event` needs: one UID and one period per event. An
-- event missing any of the three required fields is skipped, not
-- half-imported.
create function public.ical_parse_events(p_ics text)
returns table(uid text, dtstart timestamptz, dtend timestamptz)
language plpgsql
stable
set search_path = public, pg_temp
as $$
declare
  v_unfolded  text;
  v_line      text;
  v_in_event  boolean := false;
  v_uid       text;
  v_dtstart   timestamptz;
  v_dtend     timestamptz;
  v_name      text;
  v_params    text;
  v_value     text;
  v_colon_pos int;
begin
  -- Unfolding per RFC 5545 3.1: delete every CRLF (or bare LF, for feeds
  -- that are not strictly CRLF) immediately followed by a single space or
  -- tab -- that whitespace is not content, it only marked the fold.
  v_unfolded := regexp_replace(coalesce(p_ics, ''), E'\r?\n[ \t]', '', 'g');

  for v_line in
    select rtrim(t, E'\r') from regexp_split_to_table(v_unfolded, E'\r?\n') as t
  loop
    if v_line = '' then
      continue;
    end if;

    if upper(v_line) = 'BEGIN:VEVENT' then
      v_in_event := true;
      v_uid := null;
      v_dtstart := null;
      v_dtend := null;
      continue;
    end if;

    if upper(v_line) = 'END:VEVENT' then
      if v_in_event and v_uid is not null
         and v_dtstart is not null and v_dtend is not null then
        uid := v_uid;
        dtstart := v_dtstart;
        dtend := v_dtend;
        return next;
      end if;
      v_in_event := false;
      continue;
    end if;

    if not v_in_event then
      continue;
    end if;

    v_colon_pos := position(':' in v_line);
    if v_colon_pos = 0 then
      continue;
    end if;

    v_name   := split_part(left(v_line, v_colon_pos - 1), ';', 1);
    v_params := substring(left(v_line, v_colon_pos - 1) from length(v_name) + 2);
    v_value  := substring(v_line from v_colon_pos + 1);

    if upper(v_name) = 'UID' then
      v_uid := v_value;
    elsif upper(v_name) = 'DTSTART' then
      v_dtstart := public.ical_parse_datetime(v_value, v_params);
    elsif upper(v_name) = 'DTEND' then
      v_dtend := public.ical_parse_datetime(v_value, v_params);
    end if;
  end loop;

  return;
end;
$$;

-- === automatic polling (pg_net + pg_cron -- pg_net IS available here) =====
--
-- pg_net's own synchronous convenience wrapper, `net.http_collect_response
-- (request_id, async := false)` -- the pattern Supabase's docs show for a
-- `pg_cron` job body precisely to avoid a second job for collecting
-- responses -- was tried FIRST here and found broken in the version
-- actually installed in this local stack (pg_net 0.20.3): every call,
-- with either `async` value, raised "query has no destination for result
-- data ... CONTEXT: PL/pgSQL function net.http_collect_response(bigint,
-- boolean)" -- a bug inside pg_net's own function body, verified by
-- calling it directly against a real local HTTP server, not a mistake in
-- how this migration called it. The deprecation notice pg_net itself
-- prints on every call is a corroborating signal, not just this build's
-- own noise.
--
-- What DOES work, verified the same way: `net.http_get` fires the request
-- and returns immediately with a request id; the background worker later
-- writes exactly one row to `net._http_response` keyed by that id, success
-- or failure, once the request resolves (bounded by its own
-- `timeout_milliseconds`). So `ical_poll_feed` is a two-call, non-blocking
-- state machine instead of one blocking call: if `pending_request_id` is
-- null, it fires a request and stores the id; if a request is already in
-- flight, it checks `net._http_response` for that id -- processing it
-- (parsing + `ical_import_event` per event) and clearing the marker if
-- it's ready, or returning `pending` and doing nothing else if it is not.
-- After processing a ready response it immediately fires the NEXT
-- request too, so a steady cadence of one round-trip per cron tick holds
-- rather than one every two ticks. Called from the same function whether
-- the caller is `pg_cron` (below) or an admin pressing Sync -- both paths
-- behave identically, by construction, not by two implementations kept in
-- sync by hand.
create function public.ical_poll_feed(p_feed_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, net, pg_temp
as $$
declare
  v_feed      public.ical_feeds;
  v_resp      record;
  v_body      text;
  v_event     record;
  v_created   int := 0;
  v_updated   int := 0;
  v_unchanged int := 0;
  v_conflicts int := 0;
  v_import    jsonb;
  v_error     text;
  v_req_id    bigint;
  v_result    jsonb;
begin
  -- Same "no client context at all" exemption as `ical_import_event`
  -- (which this function calls) -- the pg_cron job below invokes this
  -- with no session JWT, so `auth.uid()` is null there; a real
  -- authenticated non-admin client must still be rejected, or any
  -- signed-in customer could make the server issue arbitrary outbound
  -- fetches against admin-configured feed URLs on demand.
  if auth.uid() is not null and not public.is_admin() then
    raise exception 'not permitted' using errcode = 'P0008';
  end if;

  -- `for update` so two concurrent callers for the same feed (a cron tick
  -- landing exactly when an admin presses Sync, say) don't both read
  -- `pending_request_id = null` and both fire an extra pg_net request --
  -- the second caller blocks until the first's transaction commits, then
  -- sees the request id the first one just stored.
  select * into v_feed
  from public.ical_feeds
  where id = p_feed_id and is_active
  for update;

  if not found then
    raise exception 'feed not found or inactive' using errcode = 'P0002';
  end if;

  -- A request stuck far longer than pg_net's own per-request timeout
  -- could ever explain (worker outage, database restart mid-flight) --
  -- treat it as abandoned rather than waiting forever.
  if v_feed.pending_request_id is not null
     and v_feed.pending_since < now() - interval '30 minutes' then
    v_feed.pending_request_id := null;
  end if;

  if v_feed.pending_request_id is not null then
    select status_code, content, error_msg, timed_out
      into v_resp
      from net._http_response
      where id = v_feed.pending_request_id;

    if not found then
      -- pg_net's worker has not resolved this request yet -- see the
      -- header above. Nothing else to do this call.
      return jsonb_build_object('status', 'pending');
    end if;

    if v_resp.timed_out or v_resp.error_msg is not null
       or v_resp.status_code is distinct from 200 then
      v_error := coalesce(
        v_resp.error_msg,
        case when v_resp.timed_out then 'request timed out'
             else 'HTTP ' || coalesce(v_resp.status_code::text, 'unknown') end);
      v_result := jsonb_build_object('status', 'error', 'error', v_error);
    else
      v_body := v_resp.content;

      for v_event in select * from public.ical_parse_events(v_body) loop
        v_import := public.ical_import_event(
          v_feed.unit_id, v_event.uid, v_event.dtstart, v_event.dtend);
        case v_import ->> 'status'
          when 'created'   then v_created   := v_created + 1;
          when 'updated'   then v_updated   := v_updated + 1;
          when 'unchanged' then v_unchanged := v_unchanged + 1;
          when 'conflict'  then v_conflicts := v_conflicts + 1;
          else null;
        end case;
      end loop;

      v_error := case when v_conflicts > 0 then
        v_conflicts || ' event(s) conflicted with an existing booking '
        'and were skipped'
      else null end;
      v_result := jsonb_build_object('status', 'ok', 'created', v_created,
        'updated', v_updated, 'unchanged', v_unchanged, 'conflicts', v_conflicts);
    end if;

    update public.ical_feeds
      set last_synced_at = now(), last_error = v_error,
          pending_request_id = null, pending_since = null
      where id = p_feed_id;
  end if;

  -- Fire the next request -- either the first one (no prior
  -- pending_request_id at all) or the follow-up to what was just
  -- collected above.
  begin
    v_req_id := net.http_get(url := v_feed.url, timeout_milliseconds := 15000);
  exception when others then
    update public.ical_feeds
      set last_error = 'fetch failed: ' || sqlerrm,
          pending_request_id = null, pending_since = null
      where id = p_feed_id;
    return coalesce(v_result, jsonb_build_object('status', 'error', 'error', sqlerrm));
  end;

  update public.ical_feeds
    set pending_request_id = v_req_id, pending_since = now()
    where id = p_feed_id;

  return coalesce(v_result, jsonb_build_object('status', 'requested'));
end;
$$;

grant execute on function public.ical_poll_feed(uuid) to authenticated;

-- Called only by the cron job below (runs as the scheduling role,
-- `postgres`, which bypasses grants entirely) -- never meant to be called
-- by a client directly, same convention as `ical_build_document` above.
create function public.ical_poll_all_feeds()
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_feed record;
begin
  for v_feed in select id from public.ical_feeds where is_active loop
    perform public.ical_poll_feed(v_feed.id);
  end loop;
end;
$$;

revoke execute on function public.ical_poll_all_feeds() from public;
revoke execute on function public.ical_poll_all_feeds() from anon, authenticated;

-- Every 15 minutes -- frequent enough that a same-day OTA cancellation
-- shows up well within a business day, infrequent enough not to hammer
-- Airbnb's/Booking.com's own rate limits across every unit's feed.
select cron.schedule(
  'ical-poll-feeds', '*/15 * * * *',
  $$select public.ical_poll_all_feeds()$$);
