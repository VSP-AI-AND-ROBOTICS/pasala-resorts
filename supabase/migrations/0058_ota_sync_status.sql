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
begin
  raise exception 'ical_parse_when is not implemented yet' using errcode = '0A000';
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
begin
  raise exception 'ical_parse_feed is not implemented yet' using errcode = '0A000';
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
