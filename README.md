# ResortHub — Multi-Resort Booking Platform (Phase 1 + Phase 2 + Tenancy)

A Flutter app (Android, iOS, and web from one codebase) backed by Supabase
(Postgres + Auth + Realtime), implementing property browsing, a
server-priced booking flow with a timed hold, coupons, a refund policy
engine, an advance/balance split, an owner/admin dashboard and reports, a
notification outbox, and two-way iCal calendar sync with Airbnb/Booking.com.

The app was built and seeded around a single tenant, Pasala Farm House, but
the product itself is now ResortHub: any number of resorts ("properties")
can live in one deployment, each with its own team and its own data,
switchable from one account when that account belongs to more than one.
See "Platform admin" and "Memberships and roles" below for how a resort and
its team are set up; the rest of this README otherwise still describes the
booking/ops feature set as it was written for Pasala, which is one resort
among however many exist in a given deployment.

Read `docs/STATUS.md` first — it is the single honest page on what is real,
what is stubbed, and what is needed from the owner to go live.

Design rationale: `docs/superpowers/specs/2026-07-28-pasala-booking-core-design.md`
(phase 1) and `docs/superpowers/specs/2026-07-30-pasala-phase2-design.md`
(phase 2). Full task-by-task record, including every defect found and every
deferred item: `.superpowers/sdd/2026-07-28-pasala-booking-core/progress.md`
and `.superpowers/sdd/2026-07-30-pasala-phase2/progress.md`.

## What the app includes today

**Core booking (phase 1)**

- Email/password authentication, one codebase gated by role at the router.
  Roles are two-tier: a platform-level role on `profiles.role`
  (`customer` or `platform_admin`, see "Platform admin" below) and, per
  resort, a membership role in `resort_members` (`owner`, `admin`, `staff`,
  `accountant`, see "Memberships and roles" below). There is no more global
  `super_admin`/`admin`/`staff`/`accountant` — those are resort-scoped now.
- Multi-property, multi-unit catalog (nightly, slot, or both booking modes).
- Rate rules (base, weekend, priority-ordered date-range overrides) priced
  entirely server-side via a Postgres RPC — the client never computes a
  price.
- A realtime + polled availability calendar, customer and admin views.
- Booking workflow: search availability → quote → timed hold → payment →
  confirm, all guarded by a Postgres exclusion constraint so two overlapping
  reservations on the same unit can never both commit.
- My Bookings: list, detail, and cancellation (releases the dates and
  computes a refund — see below).
- Admin: properties, units, rate rules, date blocking (single/multiple/range,
  with a reason and removal), and a bookings list.
- Staff: a "Today" view of arrivals and departures.

**Design system and UI (phase 2)**

- A real design system (colour roles, type scale, spacing scale, elevation,
  radius) — `lib/core/theme/`, one source consumed everywhere.
- Deliberate empty, loading, and error states on every screen, plus a shared
  `FailureView` so no screen renders a raw server error string.
- Property and unit imagery as first-class content on the browse screen.
- A booking flow with a clear step structure (dates → guests → price → pay)
  and a non-colour cue per calendar state (outline / bold+fill / hatch /
  dashed / opacity) so the calendar reads correctly without colour vision.
- Verified WCAG AA contrast (onSurface/surface: 16.30:1 light, 14.32:1 dark).

**Reports and admin dashboard (phase 2)**

- `/admin/dashboard`: today's revenue, month revenue, occupancy rate,
  upcoming arrivals, cancellations, and active holds — every figure computed
  in SQL, never in Dart. (`dashboard_summary()` returns exactly these six
  keys — there is no coupon-usage figure anywhere on this page or in the
  underlying function; an earlier draft of this README claimed one that was
  never actually built.)
- `/admin/reports`: revenue and occupancy by date range and property,
  exportable as CSV. PDF export was explicitly deferred — see
  "Known limitations".
- Both screens are staff-or-above (not admin-only): the accountant role
  exists specifically to read financials.

**Coupons, refunds, and advance/balance (phase 2)**

- Coupons: percentage or fixed value, with expiry, usage limit, minimum
  booking value, and optional per-customer restriction. Applied inside
  `get_quote`, so a coupon can never produce a client-computed total, and
  redemption counting is race-safe (proven with two genuinely concurrent
  `create_hold` calls via `dblink`). There is no admin UI for creating
  coupons yet — create them directly in the `coupons` table (Supabase
  Studio or `psql`); the customer-facing "Have a coupon?" field in the
  booking screen and all quote/redemption logic are otherwise complete.
- Refund policy: rules by days-before-check-in, stored in `refund_rules` and
  editable directly in that table (Supabase Studio or `psql`) — "admin-
  configurable" describes the data model and RLS (staff/accountant can
  read, only an admin can write), not an admin UI screen; there is no
  in-app form for editing tiers, see "Known limitations". Seeded default:
  full refund beyond 7 days out, 50% within 7 days, 0% within 48 hours (the
  boundary itself — exactly 48 hours — keeps the 50% tier; see the
  controller ruling in the phase 2 ledger). Cancelling a booking now
  computes and records a real refund amount instead of only releasing the
  dates.
- Advance/balance: `properties.advance_pct` sets the minimum share of the
  quoted total needed to confirm a hold; `confirm_booking` accepts any
  amount from that minimum up to the full total (never more than quoted).
  Same caveat as the refund policy above: there is no admin UI for setting
  `advance_pct` per property, only a direct table edit. The balance itself
  is not collected anywhere yet — see "Known limitations".
- A cancelled coupon redemption (hold, expired hold, or a fully confirmed
  booking) always releases its `coupon_redemptions` row and restores
  `redeemed_count` — proven for all three paths.

**Notification outbox (phase 2)**

- An `outbox` table records every booking-confirmation, payment-success, and
  cancellation message, rendered from templates, per channel
  (email/sms/whatsapp), with per-customer skip-with-reason when no
  email/phone is on file.
- `/admin/outbox` (staff-or-above) shows the queue honestly, including a
  permanent, undismissable banner: **nothing has ever been sent — there is
  no email/SMS/WhatsApp provider configured.**
- This is enforced at the database privilege level, not just in the UI:
  `outbox` has no INSERT/UPDATE/DELETE grant to `authenticated` or `anon` at
  all. The only writer is a `SECURITY DEFINER` trigger function that never
  once sets `status = 'sent'`. A direct attempt to write `sent` fails with
  `42501` before RLS is even evaluated — proven in `13_outbox_test.sql`.

**OTA calendar sync — iCal (phase 2)**

`/admin/ota/:unitId` (Admin → Properties → Units → a unit's overflow menu →
"OTA sync") gives each unit two things, with no paid channel manager:

- **An export URL** to paste into Airbnb (Listing → Availability → Sync
  calendars → Add another calendar) or Booking.com's equivalent "Import
  calendar" field. It lists only busy date ranges as RFC 5545 `VEVENT`s —
  no guest name, email, or amount ever appears in it, by construction: the
  builder reads `unit_calendar_events`, the identity-free occupancy mirror,
  never `reservations` directly.
- **Import feeds**: paste the OTA's own export URL back in, and this app
  imports its busy dates as `ota`-kind reservations that block those dates
  here too. A genuine overlap with an existing confirmed booking is caught
  and reported as a conflict — never silently force-applied.

The export URL is protected by a per-unit opaque token, not the unit's own
id — see migration `0018_ical.sql`'s header. If a URL leaks, the finder can
read that one unit's occupancy and nothing else; rotating the token from the
OTA screen invalidates the leaked URL immediately.

**Automatic polling is wired and real**: `pg_net` is available in this local
stack, so a `pg_cron` job (`ical-poll-feeds`, every 15 minutes) fetches every
active import feed and applies it automatically — verified end-to-end
against a real local HTTP server. The admin "Sync" button drives the same
function on demand.

**The export URL shape has never been verified against a real Airbnb or
Booking.com account** — there is no owner-provided listing to test against.
See `docs/STATUS.md`.

**Payments (phase 2 seam, still stubbed)**

- `MockGateway` is, and remains, the default `PaymentGateway` in every build
  this repo produces — no real money moves anywhere in this app today.
- `RazorpayGateway` (`lib/features/booking/razorpay_gateway.dart`) exists as
  a written adapter against Razorpay's real Orders API shape, but it is
  inert: there is no merchant account to test it against, and no native
  checkout SDK integrated into the app, so `charge()` fails loudly
  (`UnimplementedError`) after creating an order rather than pretending a
  created order is a captured payment. `paymentGatewayProvider` only
  selects it when `RAZORPAY_KEY_ID`/`RAZORPAY_KEY_SECRET` are supplied via
  `--dart-define`; nothing in this repo's build configuration ever supplies
  them.

## What is still out of scope

- **SMS/WhatsApp/email actually being delivered.** The outbox renders and
  queues; nothing sends. WhatsApp additionally needs Meta Business API
  verification, which has a multi-week lead time.
- **A real-time, guaranteed-zero-double-booking two-way API integration**
  with Agoda/MakeMyTrip/Goibibo — none of them publish one; iCal (above) is
  the closest thing available without a commercial channel-manager
  agreement.
- **Collecting the balance payment** once a booking is confirmed on an
  advance. The split is computed and stored; nothing prompts or records the
  second payment yet.
- **Coupon management UI.** Coupons are created directly in the database;
  there is no admin screen for it yet.
- **PDF report export.** CSV only; see `lib/features/reports/reports_screen.dart`.
- **Production hosting.** Everything runs against local Supabase.

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

# 3. Apply all migrations and load seed data (one resort — Pasala Farm
#    House — its units, rate rules, refund policy, one confirmed booking,
#    one admin block, its resort_members team, and the accounts below).
#    No coupons are seeded.
supabase db reset

# 4. Run the pgTAP suite against the freshly seeded database (optional but
#    recommended — this is the suite CI/the owner should run before trusting
#    any change).
supabase test db

# 5. Run the app in a browser.
make run-web
```

Then sign in with any account from the table below (shared password
`password123`).

## Platform admin

Nobody is a platform admin by default. Being a platform admin is a
platform-wide capability (create/suspend resorts, `/platform`) — it is
separate from, and does not imply, membership in any particular resort.
After signing up, grant it once:

    docker exec supabase_db_pasala_farm psql -U postgres -c \
      "update public.profiles set role = 'platform_admin' where id = (select id from auth.users where email = 'you@example.com');"

`profiles.role` only ever holds `customer` or `platform_admin`; every other
role lives per-resort in `resort_members` (see below).

## Memberships and roles

Each resort's team lives in `resort_members`: a row per
`(property_id, user_id)` with a role of `owner`, `admin`, `staff`, or
`accountant`. A user can be a member of more than one resort, with a
different role in each — there is no single global role that follows them
everywhere. The signed-in account's memberships drive the resort switcher:
an account with exactly one resort goes straight to it, an account with
several gets a switcher, and an account with none (a plain customer) never
sees owner/admin screens at all.

- **owner** — full control of that resort, including its team: `/owner`
  and its sub-routes (`/owner/dashboard`, `/owner/reports`,
  `/owner/settings`, …) plus `/owner/team`, which lists, adds (by email —
  only `/signup` creates an `auth.users` row, so the owner adds an
  *existing* account here, never a brand-new one), changes the role of, and
  removes members for that resort. A resort must always keep at least one
  owner; `set_member_role`/removal both refuse to drop the last one.
- **admin** — day-to-day operations for that resort (`/admin` and its
  sub-routes: properties, units, rates, blocking, bookings, OTA sync,
  reviews) short of team management.
- **staff** — front-line operational screens for that resort (today's
  arrivals/departures, check-in/out, kitchen orders, etc.).
- **accountant** — read access to that resort's financials (dashboard,
  reports) without the operational screens.

A resort's own data (reservations, expenses, reports, …) is only ever
visible to that resort's members (by role, per the above) and, platform-
wide, to a `platform_admin` — never to a member of a *different* resort.
Create new resorts, and add their first owner, from `/platform`
(platform-admin only).

## Seeded accounts

All seeded accounts share the password `password123`. Pasala Farm House is
the only seeded resort; all four staff accounts are `resort_members` of it
(none is a platform admin by default — see "Platform admin" above).

| Email | Role (on Pasala Farm House) |
|---|---|
| `super@pasala.test` | owner |
| `admin@pasala.test` | admin |
| `staff@pasala.test` | staff |
| `accounts@pasala.test` | accountant |
| `ravi@example.com` | customer (no resort membership) |
| `meera@example.com` | customer (no resort membership) |

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
`make`-driven runs. Phase 2 added no new `make` targets.

## End-to-end tests (Playwright)

`e2e/` holds a Playwright suite (Chromium) that drives the real web build
against the local Supabase stack. Every spec runs twice: in the `desktop`
project (1280x800, navigation rail) and in the `phone` project (a Pixel 7:
412x839, touch, Android Chrome, bottom navigation bar). Specs call
`reveal()` (`e2e/support/nav.ts`) before touching anything that can sit
below a phone's fold, because Flutter builds lazy lists only near the
viewport. Flutter web paints to a canvas, so the
tests go through Flutter's semantics DOM (`flt-semantics` elements with
ARIA roles and labels). The E2E build turns semantics on at startup via
`--dart-define=E2E=true` (`lib/core/e2e_semantics.dart`); a normal build is
unaffected.

```bash
supabase start                       # the local stack must be running
cd e2e
npm install                          # first time only
npx playwright install chromium      # first time only
./build-app.sh                       # flutter build web (E2E) into ../build/web
npx playwright test                  # serves build/web on :8790 and runs every spec, desktop then phone
npx playwright test --project=desktop            # 1280x800 only
npx playwright test --project=phone              # Pixel 7 only
npx playwright test tests/smoke.spec.ts          # one spec
npx playwright test -g "owner of Resort A"       # one test by title
npx playwright show-report           # HTML report of the last run
```

Rebuild with `./build-app.sh` after any change under `lib/`: the suite
serves whatever is in `build/web`.

**Fixtures are self-cleaning and never reset the database.** The local
database holds real data, so the suite never runs `supabase db reset`.
Instead, a global setup writes its own fixture world through `psql` in the
`supabase_db_pasala_farm` container — a platform admin; "E2E Resort A"
(`e2e-a`, Enterprise) and "E2E Resort B" (`e2e-b`, Starter), each with
units, rates, and an owner, admin, staff and accountant; a suspended "E2E
Resort S" (`e2e-s`); and guests with a confirmed arrival today and a
checked-in stay at Resort A — and a global teardown deletes it again.
Every fixture account ends in `@e2e.resorthub.test` and every fixture
resort slug starts with `e2e-`; setup and teardown only ever touch rows
matching those patterns. `e2e/fixtures/world.ts` lists every id, email and
booking, and the shared test-only password.

- `E2E_KEEP_FIXTURES=1 npx playwright test` leaves the fixtures in place
  after the run, to poke at by hand.
- `npm run fixtures:setup` / `npm run fixtures:teardown` create or remove
  them without running any tests (e.g. after a killed run; the next run's
  setup also clears leftovers first).
- Tests run one at a time (`workers: 1`) because they share one database.

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

## Deploying the web build

Build with:

```
flutter build web
```

`--pwa-strategy` was removed from `flutter build web` as of this project's
Flutter version (3.44) — `flutter build web -h` no longer lists it, and
Flutter 3.44 no longer registers a caching service worker at all, so there
is nothing left for that flag to configure. `web/index.html` still carries a
small inline script (before `flutter_bootstrap.js`) that unregisters any
service worker a returning browser may have registered by an older build of
this app and clears any Cache Storage entries that build left behind, so
upgrading a previously-deployed install can't keep serving a stale bundle.

That inline cleanup only helps once a new `index.html` has actually reached
the browser, so the host must also be configured to send
`Cache-Control: no-cache` for `index.html` and `flutter_bootstrap.js` (both
change on every deploy and must always be revalidated); the hashed,
content-addressed assets under `build/web/` (e.g. `main.dart.js`,
`canvaskit/`) can still be cached aggressively/immutably as usual.

## Known limitations

Carried forward from phase 1, plus everything phase 2 found or deferred.
See `docs/STATUS.md` for what each of these means for going live, and the
two progress ledgers (linked at the top of this file) for the complete,
task-by-task record.

**From phase 1:**

- **Realtime calendar updates require `REPLICA IDENTITY FULL`** on
  `unit_calendar_events` — without it, a filtered realtime subscription
  received no event at all for a row `DELETE` (e.g. a cancellation), which
  was the root cause of an earlier staleness bug. A 30-second poll plus a
  refresh-on-app-foreground bound how stale the calendar can get if the
  realtime socket ever stalls or drops a message.
- **Some UI interactions were verified through widget tests and direct
  API/RPC calls rather than live browser clicks.** The development sandbox's
  browser automation cannot reliably focus Flutter-web text fields, so any
  verification requiring typed input used the same RPCs and REST/Realtime
  endpoints the app itself calls (`psql`/`curl` round trips) plus widget
  tests instead.
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

**From phase 2:**

- **Payment is still a mock gateway.** See "Payments" above — `MockGateway`
  is the default in every build this repo produces; `RazorpayGateway` exists
  but is inert without a merchant account and a checkout SDK this app does
  not integrate.
- **Nothing in the notification outbox has ever been sent.** There is no
  email/SMS/WhatsApp provider configured; the queue and the honest
  "not sent" banner are the whole deliverable here. See `docs/STATUS.md`
  for what's needed to change that.
- **The iCal export URL shape has never been verified against a real
  Airbnb or Booking.com account** — there is no owner-provided listing to
  test against. The RFC 5545 shape and the local end-to-end poll/apply
  cycle are verified; the specific way a real OTA parses this app's feed
  is not.
- **No coupon management UI.** Coupons are created directly in the
  `coupons` table.
- **No refund-policy or advance-payment configuration UI.** `refund_rules`
  tiers and `properties.advance_pct` are both editable only by writing to
  the table directly (Supabase Studio or `psql`) — "admin-configurable"
  elsewhere in this document describes the data model and RLS grants, not
  an in-app screen.
- **The balance portion of an advance/balance booking is never collected.**
  The split is computed and stored on confirmation; nothing prompts for or
  records the balance payment afterward.
- **PDF report export was explicitly deferred.** Reports export as CSV
  only — there is deliberately no disabled/greyed-out PDF button standing
  in for it.
- **The admin dashboard's occupancy tab was not click-verified live** in
  the development sandbox (canvas click flakiness); it is covered by a
  widget test instead.
- **`report_occupancy`'s overlap filter builds its date range in session
  timezone, not property-local midnight** — up to a 5.5-hour skew that can
  include/exclude a booking near a day boundary. Numerically invisible for
  Asia/Kolkata (the only timezone this app currently seeds), verified by
  brute force, and kept as a known limitation rather than blocking the
  phase on a westward-timezone edge case no seeded property has.
- **A same-priority rate rule for a specific slot type can be outranked by
  a same-priority seasonal override** (carried from phase 1, restated for
  completeness) — same root cause, same narrow trigger.

For the full task-by-task record (every defect found, every ruling made,
every deferred item), see:
- `.superpowers/sdd/2026-07-28-pasala-booking-core/progress.md` (phase 1)
- `.superpowers/sdd/2026-07-30-pasala-phase2/progress.md` (phase 2)
