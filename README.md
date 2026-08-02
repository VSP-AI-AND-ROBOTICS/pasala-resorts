# Pasala Resorts — Booking Core (Phase 1)

A Flutter app (Android, iOS, and web from one codebase) backed by Supabase
(Postgres + Auth + Realtime), implementing property browsing, a server-priced
booking flow with a timed hold and mock payment, admin property/rate/blocking
management, and a staff "Today" view.

Full design rationale: `docs/superpowers/specs/2026-07-28-pasala-booking-core-design.md`.

## What phase 1 includes

- Email/password authentication, five roles (`customer`, `staff`, `admin`,
  `accountant`, `super_admin`), one codebase gated by role at the router.
- Multi-property, multi-unit catalog (nightly, slot, or both booking modes).
- Rate rules (base, weekend, priority-ordered date-range overrides) priced
  entirely server-side via a Postgres RPC — the client never computes a price.
- A realtime + polled availability calendar, customer and admin views.
- Booking workflow: search availability → quote → timed hold → mock payment →
  confirm, all guarded by a Postgres exclusion constraint so two overlapping
  reservations on the same unit can never both commit.
- My Bookings: list, detail, and cancellation (releases the dates; see
  "Known limitations" for what cancellation does *not* do).
- Admin: properties, units, rate rules, date blocking (single/multiple/range,
  with a reason), and a bookings list.
- Staff: a "Today" view of arrivals and departures.

## What phase 1 deliberately excludes

These are named seams for later phases, not oversights — see
`docs/superpowers/specs/2026-07-28-pasala-booking-core-design.md` §1 for the
full phase breakdown:

- **A real payment gateway.** Phase 1 ships a `PaymentGateway` interface with
  a mock implementation. No real money moves. Phase 2 swaps in Razorpay or
  PhonePe behind the same interface.
- **Coupons and a refund policy engine.** Also phase 2.
- **Notifications** (email, then SMS, then WhatsApp). Phase 3 — WhatsApp
  needs Meta Business API approval with a multi-week lead time.
- **OTA synchronization** (Airbnb, Booking.com, Agoda, MakeMyTrip, Goibibo).
  Phase 4 originally. iCal export/import (the two-way sync every major OTA
  actually supports without a commercial agreement) shipped in phase 2 --
  see "OTA calendar sync (iCal)" below. A real-time, guaranteed-zero-double-
  booking two-way API integration (Agoda/MakeMyTrip/Goibibo, none of which
  publish one) is still out of scope.
- **Reports, dashboard metrics, and housekeeping status updates.** Phase 5
  originally; reports and the dashboard shipped in phase 2.

## Prerequisites

- Flutter 3.38.9 (stable channel)
- Docker (for the local Supabase stack)
- Supabase CLI (`supabase --version` — developed against 2.110.0)
- Xcode, if building/running the iOS target
- Android SDK/emulator, if building/running the Android target

## First run

```bash
# 1. Start the local Supabase stack (Postgres, Auth, Realtime, Storage, Studio).
supabase start

# 2. Copy the anon key it prints (also retrievable any time with:
#    supabase status -o env | grep ANON_KEY
# The Makefile's ANON_KEY variable picks this up automatically — you only
# need the raw value if you're running `flutter run`/`flutter build` by hand.

# 3. Apply migrations and load seed data (properties, units, rate rules,
#    one confirmed booking, one admin block, and the accounts below).
supabase db reset

# 4. Run the app in a browser.
make run-web
```

Then sign in with any account from the table below (shared password
`password123`).

## Seeded accounts

All seeded accounts share the password `password123`.

| Email | Role |
|---|---|
| `super@pasala.test` | super_admin |
| `admin@pasala.test` | admin |
| `staff@pasala.test` | staff |
| `accounts@pasala.test` | accountant |
| `ravi@example.com` | customer |
| `meera@example.com` | customer |

## `make` targets

| Target | What it does |
|---|---|
| `make db-reset` | `supabase db reset` — reapply migrations and reload seed data |
| `make db-test` | `supabase test db` — run the pgTAP suite |
| `make test` | `flutter test` — run the Flutter test suite |
| `make run-web` | Run the app in Chrome against the local Supabase stack |
| `make run-android` | Run the app on a connected Android emulator |
| `make run-ios` | Run the app on a connected iOS simulator |

`ANON_KEY` is resolved automatically from `supabase status`, so these targets
work as-is once `supabase start` has run — no manual key copying needed for
`make`-driven runs.

## OTA calendar sync (iCal)

`/admin/ota/:unitId` (reachable from Admin → Properties → Units → a unit's
overflow menu → "OTA sync") gives each unit two things, with no paid
channel manager:

- **An export URL** to paste into Airbnb (Listing → Availability → Sync
  calendars → Add another calendar) or Booking.com's equivalent "Import
  calendar" field. It lists only busy date ranges as RFC 5545 `VEVENT`s --
  no guest name, email, or amount ever appears in it, by construction: the
  builder reads `unit_calendar_events`, the identity-free occupancy mirror,
  never `reservations` directly.
- **Import feeds**: paste the OTA's own export URL back in, and this app
  imports its busy dates as `ota`-kind reservations that block those dates
  here too. A genuine overlap with an existing confirmed booking is caught
  and reported as a conflict -- never silently force-applied.

**The export URL is protected by a per-unit opaque token**, not the unit's
own id -- see migration `0018_ical.sql`'s header for the full reasoning.
If a URL leaks, the finder can read that one unit's occupancy and nothing
else (no identity, no other units); rotating the token from the OTA screen
invalidates the leaked URL immediately.

**Automatic polling is wired and real**: `pg_net` is available in this
local stack, so a `pg_cron` job (`ical-poll-feeds`, every 15 minutes)
fetches every active import feed and applies it automatically -- verified
end-to-end against a real local HTTP server, not just unit-tested. It is
genuinely asynchronous, not a single blocking call (pg_net's own
synchronous convenience wrapper, `net.http_collect_response`, was tried
first and found broken in the pg_net version installed here -- see the
migration header for the exact error and how this was diagnosed): a fetch
is fired on one call and collected on the next, so a feed can briefly show
`requested`/`pending` before its first real result lands. The admin
"Sync" button drives the identical function on demand, for whenever
waiting up to 15 minutes is not acceptable.

## Per-platform host

Local Supabase binds to `127.0.0.1`. Each platform reaches that differently:

| Platform | `SUPABASE_URL` host |
|---|---|
| Web | `127.0.0.1` |
| iOS simulator | `127.0.0.1` |
| Android emulator | `10.0.2.2` (the emulator's alias for the host machine) |
| Physical device (either OS) | your machine's LAN IP (e.g. `192.168.1.23`) — the device must be on the same network, and `supabase start` must be reachable from it |

`lib/core/env.dart` picks `10.0.2.2` automatically for Android when no
`--dart-define=SUPABASE_URL` is passed; every other case needs the value
supplied explicitly (the `make run-*` targets and `.env.example` already do
this for the emulator/simulator/web cases).

## Development-only cleartext exemptions — remove before shipping

Local Supabase serves plain HTTP. Both iOS and Android block cleartext
traffic by default, so two exemptions were added purely to make local
development possible:

- **iOS**: `ios/Runner/Info.plist` — an `NSAppTransportSecurity` exception
  allowing insecure HTTP loads to `localhost` and `127.0.0.1`.
- **Android**: `android/app/src/main/res/xml/network_security_config.xml`,
  wired in via `android:networkSecurityConfig` on the `<application>` tag in
  `android/app/src/main/AndroidManifest.xml` — permits cleartext traffic to
  `10.0.2.2` and `127.0.0.1`.

**These must be removed before any deployed build.** A deployed backend
should always be served over HTTPS, at which point neither exemption is
needed; shipping them to production would leave the app willing to accept
plaintext HTTP from those hosts.

## Known limitations

- **Payment is a mock gateway.** No real money moves in phase 1.
  `PaymentGateway` (see `lib/`) is the seam a real provider (Razorpay,
  PhonePe) swaps into in phase 2.
- **Refund handling is not automated.** Cancelling a booking releases its
  dates on the calendar; it does not process, calculate, or record a refund.
  That is phase 2's refund policy engine.
- **Realtime calendar updates require `REPLICA IDENTITY FULL`** on
  `unit_calendar_events` — without it, a filtered realtime subscription
  received no event at all for a row `DELETE` (e.g. a cancellation), which
  was the root cause of an earlier staleness bug. A 30-second poll plus a
  refresh-on-app-foreground bound how stale the calendar can get if the
  realtime socket ever stalls or drops a message.
- **The admin date-blocking screen shows selected days as a count only**
  (e.g. "3 days selected"), not as highlighted calendar cells.
- **Some UI interactions were verified through widget tests and direct
  API/RPC calls rather than live browser clicks.** The development sandbox's
  browser automation cannot reliably focus Flutter-web text fields, and
  click-based interaction was inconsistent against the CanvasKit/web-server
  build used here. Where this applied, the underlying behavior was instead
  proven against the same RPCs and REST/Realtime endpoints the app itself
  calls (e.g. `psql`/`curl` round trips), plus Flutter widget tests.
- **Two narrow, documented races remain, both non-corrupting:**
  - Booking date/guest/slot controls are not gated on an in-flight request
    flag, so rapid multi-tapping can interleave two selection-change calls.
    This degrades gracefully (a benign duplicate cancel or a lost selection
    update) and never leaks a hold or double-books a unit — the exclusion
    constraint still holds.
  - A same-priority rate rule for a specific slot type can be outranked by a
    same-priority seasonal override; only reachable if an admin assigns two
    rules equal priority.
- **`json_annotation` is pinned to `>=4.9.0 <4.10.0`** to satisfy a
  transitive dependency conflict; newer compatible versions exist upstream.

For the full task-by-task record (including everything ruled out or
deferred along the way), see
`.superpowers/sdd/2026-07-28-pasala-booking-core/progress.md`.
