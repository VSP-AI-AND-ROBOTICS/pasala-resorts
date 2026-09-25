# OTA Sync Reliability (P9) — Design

## Why

Each unit already syncs with Airbnb and Booking.com over plain iCal
(`0018_ical.sql`, made per-resort in `0045_resort_functions.sql`). An export
link goes into the OTA, the OTA's export link comes back as an import feed
(`ical_feeds`), and a `pg_cron` job (`ical-poll-feeds`, every 15 minutes)
runs `ical_poll_feed` for each active feed. The OTA screen
(`/admin/ota/:unitId`, `lib/features/ota/ical_screen.dart`) can also press
Sync.

None of this has run against a real OTA listing (`docs/STATUS.md`, item 5).
Reading the code against the formats Airbnb and Booking.com really publish
turned up these problems:

- **All-day events land at midnight UTC.** Both OTAs export stays as
  `DTSTART;VALUE=DATE:20271009` / `DTEND;VALUE=DATE:20271012`.
  `ical_parse_datetime` turns these into `00:00 UTC` (05:30 in India). A
  guest of ours who checks out at 11:00 on the day an Airbnb guest arrives
  then overlaps the Airbnb stay, so a normal back-to-back booking is reported
  as a conflict and the Airbnb stay is not imported.
- **The parser skips or misreads real-world events.** An event with a date
  but no `DTEND` (a one-day block) is dropped. `TZID="Europe/London"` (quoted)
  and a Windows zone name (`TZID=India Standard Time`) raise, which fails the
  whole feed. A date written without `VALUE=DATE` is misread. `STATUS:CANCELLED`
  events are imported. Properties inside a `VALARM` can overwrite the
  event's own `UID` or `DTSTART`. A line with trailing spaces, such as
  `BEGIN:VEVENT `, is not recognised.
- **Our own bookings come back as conflicts.** When an OTA reads our export,
  it closes those dates and then lists them in its own export ("Airbnb (Not
  available)", "CLOSED - Not available"). We then import them, they overlap
  our own booking, and every poll reports a conflict. Admins learn to ignore
  the warning.
- **A feed's health cannot be seen.** `ical_feeds` records only
  `last_synced_at` and `last_error`. A conflict note and a dead link both
  appear as the same red text. Nothing says how many events the feed holds,
  when it last worked, or that the 15-minute job has stopped. A URL that
  returns a web page instead of a calendar reads as a successful sync with
  zero events.
- **Sync shows old data.** The Sync button calls `ical_poll_feed` once. That
  call collects whatever the cron job fetched up to 15 minutes earlier, then
  starts a new fetch that nobody collects until the next tick. The screen
  asks the admin to "press Sync again in a moment".
- **The export link cannot work.** `IcalRepository.exportUrl` builds
  `/rest/v1/rpc/ical_export_public?token=…&apikey=…`. The function's parameter
  is `p_token`, so PostgREST finds no function for `token` and returns
  PGRST202. Even with the right name, PostgREST sends a `text` result as a
  JSON string (`"BEGIN:VCALENDAR\r\n…"`) with `Content-Type:
  application/json`, and no OTA can read that.
- **Nothing tells an owner how to link a real listing.** The README says the
  export URL "has never been verified" but gives no steps.

## Decisions (agreed 2026-09-25, product owner: auto-approved)

From the accepted P9 brief:

1. **Fixture tests** use the real Airbnb and Booking.com export formats:
   `VEVENT` with `DTSTART;VALUE=DATE`, the summaries `Reserved`, `Airbnb (Not
   available)` and `CLOSED - Not available`, folded lines, CRLF and bare-LF
   line endings, and timezone variants. They cover the parser and the import.
2. **`ical_feeds` gains** `last_status` (`ok` or `error`) and
   `last_event_count`. `ical_poll_feed` sets these together with the existing
   `last_synced_at` and `last_error`.
3. **The OTA screen** shows each feed as "Last sync 5 min ago · 3 events", or
   shows the error in red. Each feed has a "Sync now" button.
4. **A README section** explains how to link a real Airbnb or Booking.com
   listing. This is the one manual verification step left.

Judgment calls made while writing this spec, all within the brief:

5. **All-day OTA events use the resort's check-in and check-out times**, in
   the resort's time zone, through the same `build_period` that native
   bookings use. `20271009`–`20271012` becomes 9 Oct 14:00 to 12 Oct 11:00
   in Asia/Kolkata. Imports from before this change carry the same UID, so the
   next poll moves them automatically (reported as `updated`).
6. **Floating times and unknown `TZID`s use the resort's time zone**, not
   UTC. A quoted or slash-prefixed `TZID` is read.
7. **Parser rules.** A date without `VALUE=DATE` is still a date. An all-day
   event with no `DTEND` lasts one night, or its `DURATION` if it has one. An
   all-day event whose `DTEND` equals its `DTSTART` also lasts one night.
   `STATUS:CANCELLED` events are skipped and do not count. Properties inside
   nested components (`VALARM`) are ignored. Property names are
   case-insensitive and trailing whitespace is ignored. An event that cannot
   be read (no UID, no start, an impossible date, an end before its start) is
   returned with an error and counted as a failed event. It never fails the
   feed.
8. **Echoes are not conflicts.** When an all-day event conflicts and every
   night it covers is already taken by one of our own reservations on that
   unit, it is counted as an `echo`. It adds no warning.
9. **Only feed-level failures are errors.** An HTTP error, a timeout, a failed
   fetch, or a 200 response that is not a calendar (no `BEGIN:VCALENDAR`)
   sets `last_status = 'error'`. Conflicts and unreadable events keep
   `last_status = 'ok'`, with their note in `last_error`, and the screen
   shows them as a warning.
10. **`last_ok_at`** (new) records the last successful sync, so a failing
    feed can say "Last good sync 2 days ago".
11. **`last_synced_at` is the time the data was fetched** (`pending_since` of
    the collected request), not the time it was processed. A feed that has
    not synced for over an hour shows a stale warning.
12. **`last_event_count`** is the number of events read from the feed,
    including unreadable ones and excluding cancelled ones. A failed sync
    leaves the previous count.
13. **"Sync now" waits for fresh data.** The app calls `ical_poll_feed` every
    2 seconds, up to 8 times, and uses the first finished result from any
    call after the first. The first call's result was fetched before the
    press. If nothing arrives in time, the app says the sync is still running.
14. **Feed URL rules** (error **P0039**). The URL is trimmed. `webcal://`
    becomes `https://`. It must be an `http(s)` link with a host, at most
    2048 characters (`invalid_feed_url`). The same URL cannot be added twice
    to one unit (`duplicate_feed`). A trigger enforces both, and the app
    checks the form first.
15. **The export link is served by an Edge Function**, `ical-export`, at
    `<SUPABASE_URL>/functions/v1/ical-export/<token>.ics`. It serves
    `text/calendar` with no key in the URL (`verify_jwt = false`). It reads
    the calendar through the existing `ical_export_public`, so the token,
    the rotation and the "resort not active publishes nothing" rule do not
    change. This fixes the broken link above. Without this, the README's
    manual verification would fail at step one.
16. **No new security definer function.** The new SQL helpers are internal
    (revoked from `public`, `anon` and `authenticated`) and run inside the
    existing `ical_poll_feed`. The definer allow-list does not change.
17. **Existing rows** that synced before this change get `last_status`
    `ok` when `last_error` is null and `error` otherwise, and their
    `last_ok_at` is copied from `last_synced_at` when they are `ok`. The next
    poll (within 15 minutes) replaces both.

## Data model — `supabase/migrations/0058_ota_sync_status.sql`

- `ical_feeds` gains:
  - `last_status text check (last_status in ('ok','error'))`. Null means
    never synced.
  - `last_event_count int check (last_event_count >= 0)`
  - `last_ok_at timestamptz`
  - `last_synced_at` and `last_error` (from 0018) keep their names. Their
    meaning is refined by decisions 9 and 11.
- Backfill as in decision 17. Existing URLs are trimmed and `webcal://` is
  rewritten to `https://`. Both happen before the trigger below exists.
- Trigger `ical_feeds_normalize_url` (before insert, or update of `url` or
  `unit_id`), an invoker function that applies decision 14 and raises
  **P0039** `invalid_feed_url` or `duplicate_feed`.
- No new table, policy or grant. `ical_feeds_read` and `ical_feeds_write`
  (0044, owner and admin of the feed's resort) cover the new columns.

## Functions

New internal helpers. Each is `stable`, has `set search_path = public,
pg_temp`, is not security definer, and is revoked from `public`, `anon` and
`authenticated`:

- `ical_parse_when(p_value text, p_params text, p_tz text, out at_ts
  timestamptz, out on_date date)`. Reads one `DTSTART`/`DTEND` value. For an
  8-digit date, it sets `on_date` and sets `at_ts` to midnight in `p_tz`. For
  `…Z` it returns UTC. For a local time it uses the `TZID` (quotes and a
  leading `/` removed), or `p_tz` when the `TZID` is missing or unknown.
  Anything else raises P0005 `unreadable date "<value>"`.
- `ical_parse_feed(p_ics text, p_tz text default 'UTC') returns table (uid
  text, dtstart timestamptz, dtend timestamptz, start_date date, end_date
  date, summary text, error text)`. Strips a BOM, unfolds (CRLF or LF
  followed by a space or tab), and splits on CRLF or LF. It reads `VEVENT`s
  by decision 7 and returns one row per non-cancelled event. `start_date`
  and `end_date` are set only for all-day events. `error` is set, and the
  times are null, for an unreadable event. Errors: `missing UID`, `missing
  DTSTART`, `missing DTEND`, `DTEND is before DTSTART`, `DTEND is not after
  DTSTART`, `DTEND is a time but DTSTART is a date`, or the Postgres message
  for an impossible date.
- `ical_event_period(p_unit_id uuid, p_dtstart timestamptz, p_dtend
  timestamptz, p_start_date date, p_end_date date) returns tstzrange`.
  All-day events use `build_period(p_unit_id, p_start_date, p_end_date)`.
  Timed events use `[p_dtstart, p_dtend)`, and raise P0005 `invalid event
  period` when that range is empty.
- `ical_event_is_echo(p_unit_id uuid, p_start_date date, p_end_date date)
  returns boolean`. It is true when every night `d` in `[start, end)` has a
  non-cancelled reservation on the unit whose period contains the resort-local
  midnight that ends night `d`.

Changed (latest bodies copied, then extended):

- `ical_parse_events(p_ics text)` (0018) keeps its signature. It becomes a
  wrapper that returns the error-free rows of `ical_parse_feed(p_ics, 'UTC')`,
  so existing callers and `14_ical_test.sql` keep working.
- `ical_poll_feed(p_feed_id uuid)` (latest in 0045) keeps its signature,
  guard, lock and two-call state machine. Changes:
  - Parses with `ical_parse_feed(body, <resort timezone>)`. Each event goes
    through `ical_event_period` and then `ical_import_event`, and the per-event
    exception boundary is kept.
  - A conflicting all-day event that `ical_event_is_echo` accepts counts as
    `echoes`.
  - A 200 response without `BEGIN:VCALENDAR` is an error: `not a calendar:
    the link did not return iCal data`.
  - The result `jsonb` gains `events` and `echoes`: `{status:'ok', events,
    created, updated, unchanged, conflicts, echoes, failed}`. The other forms
    stay `{status:'error', error}`, `{status:'pending'}` and
    `{status:'requested'}`.
  - After collecting a response it writes `last_synced_at = pending_since`,
    `last_status`, `last_error`, and on `ok` also `last_event_count` and
    `last_ok_at`.
  - If a fetch cannot be started and nothing was collected in the same call,
    it records `last_status = 'error'`, `last_synced_at = now()` and
    `last_error = 'fetch failed: …'`.
- `ical_poll_all_feeds()` (0018): its per-feed exception handler also sets
  `last_status = 'error'` and `last_synced_at = now()`.

Edge Function `supabase/functions/ical-export/`: `index.ts` (wiring),
`handler.ts` (logic), `types.ts` (contract), `handler_test.ts`, `deno.json`.
It is registered as `[functions.ical-export] verify_jwt = false` in
`supabase/config.toml`.

- `GET` or `HEAD` `/functions/v1/ical-export/<token>.ics`. The query form
  `?token=<token>` is also accepted.
- A token must be 48 lowercase hex characters. Anything else gets 404 before
  the database is queried.
- It POSTs `{"p_token": token}` to `/rest/v1/rpc/ical_export_public` with the
  project's anon key (`SUPABASE_URL`, `SUPABASE_ANON_KEY`, which the edge
  runtime provides).
- 200: the document, `Content-Type: text/calendar; charset=utf-8`,
  `Cache-Control: no-cache, max-age=0`. The response to `HEAD` has no body.
- 404 `Calendar not found`: an unknown token (P0002), or a resort that is not
  active (`null`).
- 502 `Calendar temporarily unavailable`: any other database failure (logged).
- 405 for any other method, with `Allow: GET, HEAD`.

## App

- `lib/data/models/ical_feed.dart`: `enum FeedSyncStatus { ok, error }`,
  `feedSyncStatusFromDb`, and `IcalFeed` gains `lastStatus`, `lastEventCount`
  and `lastOkAt`.
- `lib/data/repositories/ical_repository.dart`: `IcalSyncResult` gains
  `events`, `created`, `updated`, `unchanged`, `echoes`, `failed` and
  `isFinal`. `exportUrl` returns `icalExportUrl(Env.supabaseUrl, token)`,
  which is `<url>/functions/v1/ical-export/<token>.ics`.
- `lib/data/repositories/ical_sync_runner.dart`: `IcalSyncRunner.syncNow`
  implements decision 13 over the `IcalSource` seam, with an injectable wait.
  Also `icalSyncRunnerProvider`.
- `lib/features/ota/feed_sync_status.dart` (pure functions): `syncAgo`
  (`just now`, `5 min ago`, `3 h ago`, `2 days ago`), `eventCount`,
  `feedErrorHint`, `feedStatusLines` and `syncOutcomeMessage`.
- `lib/features/ota/ical_screen.dart`, per feed:
  - Never synced: `Never synced`.
  - OK: `Last sync 5 min ago · 3 events`. A note in `last_error` shows as an
    amber warning line with a warning icon.
  - Error: `Sync failed 5 min ago: <error>` in red with an error icon. A hint
    follows for HTTP 401/403/404/410 or a response that is not a calendar.
    The last line is `Last good sync 2 days ago` or `No successful sync yet`.
  - Stale (an active feed whose last sync is over an hour old): `Automatic
    sync has not run for over an hour. Press Sync now.` in amber.
  - Buttons `Sync now` and `Remove` sit below the text, which wraps at phone
    width. While syncing, a spinner and `Syncing…` replace the Sync now
    button. When it finishes, a snackbar shows the outcome and the list
    refreshes.
  - Status is never shown by colour alone: warnings and errors carry an icon.
  - The Add feed form accepts only `http://`, `https://` or `webcal://` links.
    Otherwise it shows `Paste the calendar link (starts with https:// or
    webcal://).` and disables Add.
  - `IcalScreen` takes an injectable `clock`.
- `lib/core/errors.dart`: P0039 maps to `FeedUrlRejected`, with messages for
  `invalid_feed_url` and `duplicate_feed`.
- Docs: a README section, "Linking a real Airbnb or Booking.com listing".
  It covers deploying `ical-export`, pasting the export link into each OTA,
  checking the link with `curl -i`, adding the OTA's link back as a feed,
  Sync now, a two-way test block, the table of errors and their fixes, and
  what to record in `docs/STATUS.md`. The README's OTA paragraph and
  `docs/STATUS.md` item 5 point to it.

## Rules

- The cron job and Sync now run the same function (`ical_poll_feed`). There
  is no second import path.
- No definer function is added. Every new SQL function is unreachable from
  PostgREST (revoked from `anon` and `authenticated`).
- No policy on `ical_feeds`, `ical_export_tokens` or `reservations` is
  widened. The Edge Function holds no secret beyond the anon key the runtime
  already provides, and reads only what `ical_export_public` already gives
  `anon`.
- One bad event never fails a feed, and one bad feed never fails the cron
  tick. These boundaries are kept from 0018/0045.
- Imported events never overwrite a native booking. A conflict is counted and
  skipped, never forced. Echoes are counted separately.

## Testing

- pgTAP `supabase/tests/48_ota_sync_test.sql`:
  - The contract: columns, checks, signatures, grants, not security definer.
  - Parser fixtures: Airbnb (CRLF, folded UID and DESCRIPTION, `Reserved`
    and `Airbnb (Not available)`); Booking.com (bare LF, the same file in
    CRLF gives the same rows, `CLOSED - Not available`); timezone variants
    (a named zone, quoted, a Windows name, floating, UTC); and edge cases
    (BOM, one-day, a date without `VALUE=DATE`, `DTEND` equal to `DTSTART`,
    `DURATION`, lower-case names, `VALARM`, cancelled, missing UID, an
    impossible date, backwards dates, trailing whitespace, and an HTML
    body).
  - Poll fixtures: `net._http_response` is faked. Checks cover the resort
    times, back-to-back with a native booking, a pre-P9 import moved,
    re-import unchanged, echo against conflict, every status column, HTML,
    404 keeping `last_ok_at` and the count, a timeout, pending, another
    resort's zone and times (Europe/London), a valid but empty calendar
    that cancels nothing, and the admin path against staff.
  - The URL rules (P0039).
  - `14_ical_test.sql` and `37_tenancy_isolation_test.sql` pass unchanged.
- Deno `supabase/functions/ical-export/handler_test.ts`: token parsing, the
  200/404/405/502/HEAD responses, and the REST store against a fake `fetch`
  (the body, a JSON-string result, `null`, P0002, a 500).
- Flutter:
  - `IcalFeed` and `IcalSyncResult` parsing.
  - `icalExportUrl`.
  - `IcalSyncRunner`: a stale first result, requested then pending then ok,
    a timeout, a failed fetch then ok, and an error that propagates.
  - `feed_sync_status` functions.
  - `IcalScreen` with `FakeIcalSource`: every status line and icon, Sync now
    (two calls, spinner, snackbars, refresh), the add-form validation, P0039,
    and no overflow at 360 px.

## Out of scope

- Freeing dates when an event disappears from an OTA feed (an OTA
  cancellation). Reservations do not record which feed they came from, and a
  unit can have several feeds. This is the next follow-up and the README
  says so.
- Changing what our export contains. It still uses timed UTC events. The
  README's verification step checks which nights the OTA blocks.
- Agoda, MakeMyTrip, Goibibo, or any paid channel manager.
- A per-resort sync interval, or realtime push from OTAs.
- Pausing and resuming feeds (`is_active` has no UI yet).
