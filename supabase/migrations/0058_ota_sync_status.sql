-- OTA sync reliability (P9): per-feed sync status, a parser that reads
-- real Airbnb and Booking.com exports, all-day events placed at the
-- resort's check-in/check-out times, echoes told apart from conflicts,
-- and rules for feed URLs.
-- See docs/superpowers/specs/2026-09-25-p9-ota-sync-reliability-design.md.
--
-- Error code: P0039 -- `invalid_feed_url` / `duplicate_feed` (the
-- ical_feeds URL rules, section 4). Also raised: P0005 (an unreadable
-- event; ical_poll_feed catches it per event and counts it as failed).
--
-- No security definer function is added: the helpers below are internal
-- and run inside the existing ical_poll_feed.

-- ---------------------------------------------------------------------
-- 1. Sync status on each feed. last_synced_at and last_error exist (0018):
--    last_synced_at is when the collected data was fetched; last_error is
--    the feed-level error when last_status = 'error', otherwise a note
--    about skipped events (or null).

alter table public.ical_feeds
  add column last_status text
    constraint ical_feeds_last_status_check
      check (last_status in ('ok', 'error')),
  add column last_event_count int
    constraint ical_feeds_last_event_count_check
      check (last_event_count >= 0),
  add column last_ok_at timestamptz;

-- Feeds that synced before this migration: a recorded error reads as an
-- error until the next poll (at most 15 minutes) rewrites it.
update public.ical_feeds
   set last_status = case when last_error is null then 'ok' else 'error' end,
       last_ok_at  = case when last_error is null then last_synced_at end
 where last_synced_at is not null;

-- ---------------------------------------------------------------------
-- 2. Parsing a feed. Internal: reached only through ical_poll_feed (and,
--    for ical_parse_feed, the ical_parse_events wrapper). Task 2 of the
--    plan replaces these stub bodies.

create function public.ical_parse_when(
  p_value  text,
  p_params text,
  p_tz     text,
  out at_ts   timestamptz,
  out on_date date
)
language plpgsql
stable
set search_path = public, pg_temp
as $$
declare
  v    text := btrim(coalesce(p_value, ''));
  v_tz text;
  v_ts timestamp;
begin
  -- A date, with or without VALUE=DATE: 20271009.
  if v ~ '^[0-9]{8}$' then
    on_date := make_date(substr(v, 1, 4)::int, substr(v, 5, 2)::int,
                         substr(v, 7, 2)::int);
    at_ts := on_date::timestamp at time zone p_tz;
    return;
  end if;

  if v !~ '^[0-9]{8}T[0-9]{6}Z?$' then
    raise exception using errcode = 'P0005',
      message = 'unreadable date "' || v || '"';
  end if;

  v_ts := make_timestamp(substr(v, 1, 4)::int, substr(v, 5, 2)::int,
                         substr(v, 7, 2)::int, substr(v, 10, 2)::int,
                         substr(v, 12, 2)::int, substr(v, 14, 2)::int);

  if right(v, 1) = 'Z' then
    at_ts := v_ts at time zone 'UTC';
    return;
  end if;

  -- TZID=Asia/Kolkata, TZID="Europe/London" or TZID=/Europe/London. A zone
  -- Postgres does not know (a Windows name such as "India Standard Time")
  -- and floating time both mean the resort's own zone.
  v_tz := btrim(substring(coalesce(p_params, '')
                          from '(?i);TZID=("[^"]*"|[^;]*)'), '"/ ');
  if v_tz is not null and v_tz <> '' then
    begin
      at_ts := v_ts at time zone v_tz;
      return;
    exception when invalid_parameter_value then
      null;
    end;
  end if;

  at_ts := v_ts at time zone p_tz;
end;
$$;

create function public.ical_parse_feed(p_ics text, p_tz text default 'UTC')
returns table (
  uid        text,
  dtstart    timestamptz,
  dtend      timestamptz,
  start_date date,
  end_date   date,
  summary    text,
  error      text
)
language plpgsql
stable
set search_path = public, pg_temp
as $$
declare
  v_text      text;
  v_line      text;
  v_upper     text;
  v_match     text[];
  v_depth     int := 0;   -- 0 outside, 1 in a VEVENT, >1 in a component inside it
  v_uid       text;
  v_start_val text;
  v_start_par text;
  v_end_val   text;
  v_end_par   text;
  v_duration  text;
  v_summary   text;
  v_status    text;
  v_s         record;
  v_e         record;
begin
  -- A byte-order mark, then RFC 5545 unfolding: a line break followed by
  -- one space or tab continues the previous line.
  v_text := ltrim(coalesce(p_ics, ''), chr(65279));
  v_text := regexp_replace(v_text, E'\r?\n[ \t]', '', 'g');

  for v_line in
    select rtrim(t, E' \t\r') from regexp_split_to_table(v_text, E'\r?\n') as t
  loop
    continue when v_line = '';
    v_upper := upper(v_line);

    if v_depth = 0 then
      if v_upper = 'BEGIN:VEVENT' then
        v_depth := 1;
        v_uid := null; v_start_val := null; v_start_par := null;
        v_end_val := null; v_end_par := null; v_duration := null;
        v_summary := null; v_status := null;
      end if;
      continue;
    end if;

    -- A component nested in the event (VALARM): skip everything inside it.
    if v_upper like 'BEGIN:%' then
      v_depth := v_depth + 1;
      continue;
    end if;
    if v_upper like 'END:%' and v_depth > 1 then
      v_depth := v_depth - 1;
      continue;
    end if;
    continue when v_depth > 1;

    if v_upper = 'END:VEVENT' then
      v_depth := 0;
      continue when upper(coalesce(v_status, '')) = 'CANCELLED';

      uid := v_uid;
      summary := v_summary;
      dtstart := null; dtend := null; start_date := null; end_date := null;
      error := null;
      begin
        if v_uid is null or v_uid = '' then
          raise exception using errcode = 'P0005', message = 'missing UID';
        end if;
        if v_start_val is null then
          raise exception using errcode = 'P0005', message = 'missing DTSTART';
        end if;
        v_s := public.ical_parse_when(v_start_val, v_start_par, p_tz);
        if v_end_val is not null then
          v_e := public.ical_parse_when(v_end_val, v_end_par, p_tz);
        end if;

        if v_s.on_date is not null then
          -- All day: nights from start_date up to (not including) end_date.
          start_date := v_s.on_date;
          if v_end_val is not null then
            if v_e.on_date is null then
              raise exception using errcode = 'P0005',
                message = 'DTEND is a time but DTSTART is a date';
            end if;
            end_date := v_e.on_date;
          elsif v_duration is not null then
            end_date := (v_s.on_date + v_duration::interval)::date;
          else
            end_date := v_s.on_date + 1;
          end if;
          if end_date = start_date then
            end_date := start_date + 1;
          elsif end_date < start_date then
            raise exception using errcode = 'P0005',
              message = 'DTEND is before DTSTART';
          end if;
          dtstart := start_date::timestamp at time zone p_tz;
          dtend   := end_date::timestamp at time zone p_tz;
        else
          dtstart := v_s.at_ts;
          if v_end_val is not null then
            dtend := v_e.at_ts;
          elsif v_duration is not null then
            dtend := dtstart + v_duration::interval;
          else
            raise exception using errcode = 'P0005', message = 'missing DTEND';
          end if;
          if dtend <= dtstart then
            raise exception using errcode = 'P0005',
              message = 'DTEND is not after DTSTART';
          end if;
        end if;
      exception when others then
        dtstart := null; dtend := null; start_date := null; end_date := null;
        error := sqlerrm;
      end;
      return next;
      continue;
    end if;

    -- NAME;PARAM=a;PARAM="b:c":value -- the value starts at the first colon
    -- outside double quotes.
    v_match := regexp_match(v_line,
      '^([A-Za-z0-9-]+)((?:;(?:[^";:]|"[^"]*")*)*):(.*)$');
    continue when v_match is null;

    case upper(v_match[1])
      when 'UID'      then v_uid := btrim(v_match[3]);
      when 'DTSTART'  then v_start_val := v_match[3]; v_start_par := v_match[2];
      when 'DTEND'    then v_end_val := v_match[3];   v_end_par := v_match[2];
      when 'DURATION' then v_duration := btrim(v_match[3]);
      when 'SUMMARY'  then v_summary := btrim(v_match[3]);
      when 'STATUS'   then v_status := btrim(v_match[3]);
      else null;
    end case;
  end loop;

  return;
end;
$$;

-- ---------------------------------------------------------------------
-- 3. Importing. Task 3 of the plan replaces these stub bodies and then
--    redefines ical_parse_events, ical_poll_feed and ical_poll_all_feeds
--    below the revoke block.

create function public.ical_event_period(
  p_unit_id    uuid,
  p_dtstart    timestamptz,
  p_dtend      timestamptz,
  p_start_date date,
  p_end_date   date
) returns tstzrange
language plpgsql
stable
set search_path = public, pg_temp
as $$
begin
  -- An all-day OTA event covers nights: arrive at the resort's check-in
  -- time on the first date, leave at its check-out time on the last --
  -- exactly how a native booking's period is built.
  if p_start_date is not null then
    return public.build_period(p_unit_id, p_start_date,
                               coalesce(p_end_date, p_start_date + 1));
  end if;
  if p_dtstart is null or p_dtend is null or p_dtend <= p_dtstart then
    raise exception using errcode = 'P0005', message = 'invalid event period';
  end if;
  return tstzrange(p_dtstart, p_dtend, '[)');
end;
$$;

create function public.ical_event_is_echo(
  p_unit_id    uuid,
  p_start_date date,
  p_end_date   date
) returns boolean
language sql
stable
set search_path = public, pg_temp
as $$
  -- True when every night of the event is already taken here: a
  -- reservation on the unit contains the resort-local midnight that ends
  -- that night.
  select coalesce(p_end_date > p_start_date, false)
     and exists (select 1 from public.units where id = p_unit_id)
     and not exists (
       select 1
         from generate_series(p_start_date::timestamp,
                              (p_end_date - 1)::timestamp,
                              interval '1 day') as night(d)
         join public.units u on u.id = p_unit_id
         join public.properties p on p.id = u.property_id
        where not exists (
          select 1
            from public.reservations r
           where r.unit_id = p_unit_id
             and r.status <> 'cancelled'
             and r.period @> ((night.d::date + 1)::timestamp
                              at time zone p.timezone)));
$$;

-- Internal helpers, same convention as ical_build_document (0018): never
-- callable through PostgREST.
revoke execute on function public.ical_parse_when(text, text, text)
  from public, anon, authenticated;
revoke execute on function public.ical_parse_feed(text, text)
  from public, anon, authenticated;
revoke execute on function
  public.ical_event_period(uuid, timestamptz, timestamptz, date, date)
  from public, anon, authenticated;
revoke execute on function public.ical_event_is_echo(uuid, date, date)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- 3b. The poller on top of the helpers. ical_parse_events keeps its
--     signature for existing callers; ical_poll_feed is copied from 0045
--     and ical_poll_all_feeds from 0018, then extended. Grants and revokes
--     survive `create or replace`.

create or replace function public.ical_parse_events(p_ics text)
returns table(uid text, dtstart timestamptz, dtend timestamptz)
language sql
stable
set search_path = public, pg_temp
as $$
  select f.uid, f.dtstart, f.dtend
    from public.ical_parse_feed(p_ics, 'UTC') as f
   where f.error is null;
$$;

-- Admin+ of the feed's resort for a PostgREST caller (Sync now); the cron
-- job (no JWT) is not checked. See 0018 for the state machine.
create or replace function public.ical_poll_feed(p_feed_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_property    uuid;
  v_feed        public.ical_feeds;
  v_tz          text;
  v_resp        record;
  v_event       record;
  v_period      tstzrange;
  v_fetched_at  timestamptz;
  v_events      int := 0;
  v_created     int := 0;
  v_updated     int := 0;
  v_unchanged   int := 0;
  v_conflicts   int := 0;
  v_echoes      int := 0;
  v_failed      int := 0;
  v_failed_note text;
  v_import      jsonb;
  v_error       text;
  v_req_id      bigint;
  v_result      jsonb;
begin
  if nullif(current_setting('request.jwt.claims', true), '') is not null then
    select property_id into v_property from public.ical_feeds where id = p_feed_id;
    if v_property is null then
      raise exception 'feed not found or inactive' using errcode = 'P0002';
    end if;
    perform public.assert_resort_role(v_property, true, 'owner','admin');
  end if;

  -- `for update`: a cron tick and a Sync press for the same feed must not
  -- both fire a request.
  select * into v_feed
  from public.ical_feeds
  where id = p_feed_id and is_active
  for update;

  if not found then
    raise exception 'feed not found or inactive' using errcode = 'P0002';
  end if;

  -- A request stuck far longer than pg_net's own timeout is abandoned.
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
      return jsonb_build_object('status', 'pending');
    end if;

    -- The data is as old as the request that fetched it.
    v_fetched_at := coalesce(v_feed.pending_since, now());
    select p.timezone into v_tz
      from public.units u join public.properties p on p.id = u.property_id
     where u.id = v_feed.unit_id;

    -- Every path must reach the `update ical_feeds` below, so an
    -- unexpected error cannot wedge the feed.
    begin
      if v_resp.timed_out or v_resp.error_msg is not null
         or v_resp.status_code is distinct from 200 then
        v_error := coalesce(
          v_resp.error_msg,
          case when v_resp.timed_out then 'request timed out'
               else 'HTTP ' || coalesce(v_resp.status_code::text, 'unknown') end);
        v_result := jsonb_build_object('status', 'error', 'error', v_error);
      elsif coalesce(v_resp.content, '') !~* 'BEGIN:VCALENDAR' then
        -- A login page or a listing page, not a calendar: zero events would
        -- otherwise read as a healthy, empty feed.
        v_error := 'not a calendar: the link did not return iCal data';
        v_result := jsonb_build_object('status', 'error', 'error', v_error);
      else
        for v_event in
          select * from public.ical_parse_feed(v_resp.content, coalesce(v_tz, 'UTC'))
        loop
          v_events := v_events + 1;
          -- One unreadable or refused event skips itself; the rest import.
          begin
            if v_event.error is not null then
              raise exception using errcode = 'P0005', message = v_event.error;
            end if;
            v_period := public.ical_event_period(v_feed.unit_id,
              v_event.dtstart, v_event.dtend, v_event.start_date, v_event.end_date);
            v_import := public.ical_import_event(
              v_feed.unit_id, v_event.uid, lower(v_period), upper(v_period));
            case v_import ->> 'status'
              when 'created'   then v_created   := v_created + 1;
              when 'updated'   then v_updated   := v_updated + 1;
              when 'unchanged' then v_unchanged := v_unchanged + 1;
              when 'conflict'  then
                -- The OTA listing our own booking back to us (it closed
                -- those dates because of our export) is not a conflict.
                if v_event.start_date is not null
                   and public.ical_event_is_echo(v_feed.unit_id,
                         v_event.start_date, v_event.end_date) then
                  v_echoes := v_echoes + 1;
                else
                  v_conflicts := v_conflicts + 1;
                end if;
              else null;
            end case;
          exception when others then
            v_failed := v_failed + 1;
            v_failed_note := coalesce(nullif(btrim(v_event.uid), ''), '(blank uid)')
              || ': ' || sqlerrm;
          end;
        end loop;

        v_error := nullif(trim(both ', ' from concat_ws(', ',
          case when v_conflicts > 0 then
            v_conflicts || ' event(s) conflicted with an existing booking '
            'and were skipped'
          end,
          case when v_failed > 0 then
            v_failed || ' event(s) failed to import and were skipped '
            '(last error: ' || v_failed_note || ')'
          end
        )), '');
        v_result := jsonb_build_object('status', 'ok', 'events', v_events,
          'created', v_created, 'updated', v_updated, 'unchanged', v_unchanged,
          'conflicts', v_conflicts, 'echoes', v_echoes, 'failed', v_failed);
      end if;
    exception when others then
      v_error := 'poll failed while processing response: ' || sqlerrm;
      v_result := jsonb_build_object('status', 'error', 'error', v_error);
    end;

    update public.ical_feeds
       set last_synced_at   = v_fetched_at,
           last_status      = v_result ->> 'status',
           last_error       = v_error,
           last_event_count = case when v_result ->> 'status' = 'ok'
                                   then v_events else last_event_count end,
           last_ok_at       = case when v_result ->> 'status' = 'ok'
                                   then v_fetched_at else last_ok_at end,
           pending_request_id = null,
           pending_since      = null
     where id = p_feed_id;
  end if;

  -- Fire the next request (the first, or the follow-up to the one just
  -- collected).
  begin
    v_req_id := net.http_get(url := v_feed.url, timeout_milliseconds := 15000);
  exception when others then
    if v_result is null then
      -- Nothing was collected in this call: the failed fetch is the news.
      update public.ical_feeds
         set last_synced_at = now(), last_status = 'error',
             last_error = 'fetch failed: ' || sqlerrm,
             pending_request_id = null, pending_since = null
       where id = p_feed_id;
      return jsonb_build_object('status', 'error', 'error', 'fetch failed: ' || sqlerrm);
    end if;
    update public.ical_feeds
       set pending_request_id = null, pending_since = null
     where id = p_feed_id;
    return v_result;
  end;

  update public.ical_feeds
    set pending_request_id = v_req_id, pending_since = now()
    where id = p_feed_id;

  return coalesce(v_result, jsonb_build_object('status', 'requested'));
end;
$$;

-- Cron only (revoked from every API role in 0018; the revoke survives).
create or replace function public.ical_poll_all_feeds()
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_feed record;
begin
  for v_feed in select id from public.ical_feeds where is_active loop
    -- One feed's failure must not roll back the other feeds' results.
    begin
      perform public.ical_poll_feed(v_feed.id);
    exception when others then
      update public.ical_feeds
         set last_synced_at = now(), last_status = 'error',
             last_error = 'poll failed: ' || sqlerrm,
             pending_request_id = null, pending_since = null
       where id = v_feed.id;
    end;
  end loop;
end;
$$;
