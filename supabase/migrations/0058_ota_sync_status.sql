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
  raise exception 'ical_event_period is not implemented yet' using errcode = '0A000';
end;
$$;

create function public.ical_event_is_echo(
  p_unit_id    uuid,
  p_start_date date,
  p_end_date   date
) returns boolean
language plpgsql
stable
set search_path = public, pg_temp
as $$
begin
  raise exception 'ical_event_is_echo is not implemented yet' using errcode = '0A000';
end;
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
