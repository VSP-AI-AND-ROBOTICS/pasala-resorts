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
  exportable as CSV or PDF (see "Invoices and PDF exports").
- Both screens are staff-or-above (not admin-only): the accountant role
  exists specifically to read financials.

**Coupons, refunds, and advance/balance (phase 2)**

- Coupons: percentage or fixed value, with expiry, usage limit, minimum
  booking value, and optional per-customer restriction. Applied inside
  `get_quote`, so a coupon can never produce a client-computed total, and
  redemption counting is race-safe (proven with two genuinely concurrent
  `create_hold` calls via `dblink`). Owners and admins manage them on the
  Coupons screen (owner hub → Coupons, or admin More → Coupons): create,
  edit, deactivate, and see each code's usage; a coupon can be limited to
  one guest who has booked at the resort.
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
- The `outbox-dispatch` Edge Function sends email (Resend) and SMS
  (MSG91), called every minute by pg_cron, with retries (1, 2, 4, 8
  minutes; failed after 5 attempts). Without provider keys it runs as a
  **dry run**: messages are marked `dry_run` and nothing is sent. WhatsApp
  is queued only. Setup: [docs/email-and-sms-delivery.md](docs/email-and-sms-delivery.md).
- `/admin/outbox` (staff-or-above) shows each channel's delivery mode and
  when the sender last ran, and lets owners/admins send a failed or
  dry-run message again.
- Clients still cannot write `outbox`: there is no INSERT/UPDATE/DELETE
  grant to `authenticated` or `anon` (proven in `13_outbox_test.sql`).
  Only `security definer` functions change rows, and only the service
  role (the Edge Function) marks one sent (`46_email_sms_delivery_test.sql`).

**OTA calendar sync — iCal (phase 2)**

`/admin/ota/:unitId` (Admin → Properties → Units → a unit's overflow menu →
"OTA sync") gives each unit two things, with no paid channel manager:

- **An export URL** to paste into Airbnb or Booking.com's "import calendar"
  setting: `<SUPABASE_URL>/functions/v1/ical-export/<token>.ics`, served as
  `text/calendar` by the `ical-export` Edge Function. It lists only busy
  date ranges as RFC 5545 `VEVENT`s — no guest name, email, or amount ever
  appears in it, by construction: the builder reads `unit_calendar_events`,
  the identity-free occupancy mirror, never `reservations` directly.
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
active import feed and applies it automatically. The admin "Sync now" button
drives the same function and waits for fresh data. Each feed shows
"Last sync 5 min ago · 3 events", or its error in red with a hint. All-day
OTA events are placed at the resort's own check-in and check-out times, and
an OTA listing our own booking back to us is not reported as a conflict.
The import is tested against fixtures in the real Airbnb and Booking.com
export formats (`supabase/tests/48_ota_sync_test.sql`).

**Linking a real listing is the one step left to verify by hand** — see
[Linking a real Airbnb or Booking.com listing](#linking-a-real-airbnb-or-bookingcom-listing).

**Online payments (Razorpay)**

- Guests pay the booking advance and their checkout balance through
  Razorpay: Checkout.js on the web, `razorpay_flutter` on Android and iOS.
  The app holds only the public key id. Three Edge Functions hold the
  secrets and do the work:
  - `payments-create-order` checks the amount (the advance rule or the
    balance due) as the signed-in guest and creates the Razorpay order;
  - `payments-verify` checks Checkout's signature, asks Razorpay whether
    the money was captured (capturing an authorized payment for the
    order's amount), and only then confirms the booking (or checks the
    guest out) on the server. A payment that is still not captured is
    reported as "not confirmed yet" and settles nothing; the
    `payment.captured` webhook settles it if it is captured later;
  - `payments-webhook` handles `payment.captured`, `payment.failed` and
    `refund.processed`, once each.

  A payment that cannot be applied (the hold was released, the booking
  was already paid, the balance changed) is refunded automatically.
- **Without secrets nothing changes.** The functions answer
  `{"configured": false}`, and the app pays through `MockGateway` as before.
  Online payments are live only when all three secrets are set, the webhook
  secret included: without it a guest who closes the tab after paying would
  never be settled or refunded. While live, the database refuses a guest's
  mock confirmation (P0036), so a live deployment cannot be booked for
  free.

To switch it on (test keys first), run all three steps; the probe is part
of the deploy, not optional:

```bash
supabase secrets set RAZORPAY_KEY_ID=rzp_test_xxx RAZORPAY_KEY_SECRET=xxx RAZORPAY_WEBHOOK_SECRET=xxx
supabase functions deploy payments-create-order payments-verify payments-webhook
# Deploy step: switch the database to live now. Until something does, a
# guest could still confirm with a mock payment by calling confirm_booking.
curl -X POST "https://<project-ref>.supabase.co/functions/v1/payments-create-order" \
  -H "Authorization: Bearer <anon key>" -H "Content-Type: application/json" \
  -d '{"probe": true}'     # → {"configured":true,"key_id":"rzp_test_xxx"}
```

Anything but `{"configured":true,...}` means payments are not live. The
answer `{"configured":false,"missing":["RAZORPAY_WEBHOOK_SECRET"]}` means
the keys are set but the webhook secret is not: set it and probe again.
`payments-verify` and every signed `payments-webhook` event also keep the
live switch in step with the secrets, but only the probe does so before the
first guest pays.

In the Razorpay Dashboard (Account & Settings → Webhooks), add the URL
`https://<project-ref>.supabase.co/functions/v1/payments-webhook`. Give it
the same secret as `RAZORPAY_WEBHOOK_SECRET`, and the events
`payment.captured`, `payment.failed` and `refund.processed`. Keep
**automatic capture** on (Account & Settings → Payment capture; the
default). A Checkout signature only proves a payment was authorized:
`payments-verify` captures an authorized payment itself, but when the guest
closes the tab before it runs, only automatic capture turns that payment
into money. An uncaptured payment is returned to the guest by Razorpay
after a few days and never confirms a booking.

To switch it off, run
`supabase secrets unset RAZORPAY_KEY_ID RAZORPAY_KEY_SECRET RAZORPAY_WEBHOOK_SECRET`
and then the probe again. Refunds for cancelled bookings are still made by
hand in the Razorpay Dashboard.

To run it locally, put the three variables in `supabase/functions/.env`
(gitignored) and run
`supabase functions serve --env-file supabase/functions/.env`. Razorpay can
reach a local webhook only through a tunnel. Never put the key secret in
`--dart-define`, the database or git.

**Not yet verified against a real Razorpay account.** The functions are
tested with signature fixtures and a mocked Razorpay API only. See
`docs/STATUS.md`.

## What is still out of scope

- **WhatsApp delivery.** Email and SMS are sent once their provider keys
  are set (see [docs/email-and-sms-delivery.md](docs/email-and-sms-delivery.md));
  WhatsApp needs Meta Business API verification, which has a multi-week
  lead time, and is queued only.
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
| `make functions-test` | `deno test supabase/functions/` — run the Edge Function tests |
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
- The gap-round specs (coupons, taxes, OTA sync, outbox, listing,
  discovery) bring their own resort and accounts (`e2e/support/kit.ts`),
  created in `beforeAll` and removed in `afterAll` by exact slug and email.
- `ota-sync.spec.ts` serves an Airbnb-style calendar on a loopback port;
  the database container fetches it as `host.docker.internal` (Docker
  Desktop). `owner.spec.ts` runs the real `billing-subscribe` function
  under Deno (`e2e/support/functions.ts`, no Razorpay keys), since the
  suite does not need the stack's edge runtime. `discovery.spec.ts`
  grants geolocation at a fixed point and answers the Nominatim lookup
  locally.

## Front-desk check-in passes

The QR a guest sees on their booking (confirmation, booking detail, My
Stay) is a signed check-in pass: `rh1.` plus the booking id, the resort id
and the end of the stay, signed with HMAC-SHA256 under a random
per-database secret (`supabase/migrations/0052_stay_pass.sql`). Reception
opens it from `/admin/check-in` with **Scan pass** (the device camera), or
by typing or pasting it into the search field. A USB or Bluetooth barcode
scanner that types and presses Enter works too. Guests can always read out
the booking code under the QR instead.

- The secret lives in `private.stay_pass_secret`, which the API cannot
  reach. `supabase db reset` (or the first migration run) creates it.
- To rotate it, which invalidates every pass issued so far (guests get a
  fresh one the next time they open their booking):
  `update private.stay_pass_secret set secret = extensions.gen_random_bytes(32);`
- The web camera needs HTTPS or `localhost`. On iOS the app asks with
  `NSCameraUsageDescription`; Android gets the camera permission from the
  `mobile_scanner` plugin.

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

## Linking a real Airbnb or Booking.com listing

This needs a live OTA listing, so it has to be done by someone who manages
one. Plan on about 30 minutes, plus however long the OTA takes to refresh
an imported calendar (often a few hours).

### Before you start

- The hosted project has every migration applied, and `pg_cron` and `pg_net`
  enabled (Database → Extensions).
- The export function is deployed: `supabase functions deploy ical-export`.
  `supabase/config.toml` sets `verify_jwt = false` for it, because an OTA
  cannot send a key. With an older CLI, add `--no-verify-jwt`.
- The app you use is built with the hosted `SUPABASE_URL`, because the
  export link is built from it.

### 1. Give the OTA our calendar

1. In the app, go to Admin → Properties → Units → the unit's menu → **OTA
   sync**, and copy the **Export URL**. It looks like
   `https://<project>.supabase.co/functions/v1/ical-export/<48 hex characters>.ics`.
2. Check the link before pasting it anywhere:

   ```bash
   curl -i 'https://<project>.supabase.co/functions/v1/ical-export/<token>.ics'
   ```

   Expect `200`, `content-type: text/calendar; charset=utf-8`, and a body
   starting with `BEGIN:VCALENDAR`. A `404 Calendar not found` means the
   token was rotated or mistyped, or the resort is not active.
3. Paste it into the OTA's import setting:
   - Airbnb: Listing → Availability → Connect calendars → Import.
   - Booking.com extranet: Rates & Availability → Sync calendars → Add
     calendar connection.
   - Menu names change; look for "import calendar". Name it "ResortHub".

### 2. Give our app the OTA's calendar

1. Copy the OTA's own export link. It is on the same page as the import,
   under "Export".
   - Airbnb: `https://www.airbnb.com/calendar/ical/<id>.ics?s=<secret>`.
   - Booking.com: a link to `admin.booking.com/…ical…`.
   - A `webcal://` link is fine: the app stores it as `https://`.
2. On the OTA sync screen, go to **Add import feed**. Paste the link, label
   it "Airbnb" or "Booking.com", and press **Add feed**.
3. Press **Sync now**. Within about 15 seconds the feed shows
   `Last sync just now · N events`. N should match the stays plus blocked
   periods on that OTA calendar, counting from today.

### 3. Prove both directions

1. **Ours to the OTA.** Block one night here (Admin → Block dates). After the
   OTA refreshes, that night shows as unavailable there. Check that it blocks
   **exactly** that night. Our export uses exact check-in/check-out times, so
   write down if an OTA also blocks the next night.
2. **The OTA to ours.** Block one night on the OTA, then press **Sync now**
   here. The count goes up by one, and the night is unavailable in this app's
   booking calendar.
3. Remove both test blocks. Removing the OTA block does **not** free the
   night here (see "Known gaps" below). Ask a developer to cancel the
   imported reservation.

### What the feed status means

| The feed shows | Meaning | What to do |
|---|---|---|
| `Last sync 5 min ago · 3 events` | Healthy. | Nothing. |
| Amber `N event(s) conflicted with an existing booking and were skipped` | The OTA has a stay on dates already booked here. | A double booking: contact the guest, then close the dates on the OTA. |
| Amber `N event(s) failed to import and were skipped (…)` | Some events could not be read. | Send the note and the OTA's link to a developer. |
| Red `Sync failed …: HTTP 404` (or 401, 403, 410) | The OTA no longer serves this link (it was reset, or the listing was unlisted). | Copy the export link from the OTA again, remove this feed and add the new link. |
| Red `Sync failed …: not a calendar: …` | The link opens a web page, not a calendar. | Use the calendar **export** link, not the listing page. |
| Red `request timed out` or `HTTP 5xx` | The OTA is down for a while. | Nothing; the next run is within 15 minutes. |
| Amber `Automatic sync has not run for over an hour` | The `pg_cron` job is not running. | In the SQL editor, run `select * from cron.job_run_details order by start_time desc limit 5;` and check that `ical-poll-feeds` is scheduled and succeeding. |

An OTA listing our own bookings back to us ("Airbnb (Not available)",
"CLOSED - Not available") is normal and is not counted as a conflict.

### Record the result

Update item 5 in `docs/STATUS.md` with the date, the OTA, and the listing.
Record whether each direction passed, and whether the OTA blocked any extra
night.

### Known gaps

- When an event disappears from an OTA feed (a cancellation there), the
  dates stay blocked here. Reservations do not yet record which feed they
  came from.
- Our export lists timed events (check-in to check-out). Step 3.1 is where
  you find out whether an OTA rounds them to one night too many.

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

- **Online payments are off until Razorpay secrets are set, and have not been
  run against a real Razorpay account.** See "Online payments (Razorpay)"
  above. Refunds for cancelled bookings are made by hand in the Razorpay
  Dashboard.
- **Email and SMS go out only once provider keys are set.** Until then the
  sender runs as a dry run and the Outbox screen says so per channel.
  WhatsApp is never sent. See `docs/email-and-sms-delivery.md`.
- **The iCal link has not yet been tried with a real Airbnb or Booking.com
  listing** — see "Linking a real Airbnb or Booking.com listing" above. The
  import is tested against fixtures in both OTAs' real formats and the export
  is served as `text/calendar`; how a live OTA reads our export is what is
  left to check. Events removed from an OTA feed are not removed here.
- **No refund-policy or advance-payment configuration UI.** `refund_rules`
  tiers and `properties.advance_pct` are both editable only by writing to
  the table directly (Supabase Studio or `psql`) — "admin-configurable"
  elsewhere in this document describes the data model and RLS grants, not
  an in-app screen.
- **The balance portion of an advance/balance booking is never collected.**
  The split is computed and stored on confirmation; nothing prompts for or
  records the balance payment afterward.
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

## Invoices and PDF exports

- **Booking invoice (PDF)** — on a checked-in or checked-out booking's detail
  screen (guests from My Bookings, owners/admins from Admin → Bookings), on the
  Final Invoice screen after checkout, per row in Finance → Settlements, and
  from reception's check-out list right after a desk checkout.
  Built client-side from the stored quote, the booking's food orders,
  activity bookings and payments, checked against `current_charges`; a
  checked-in stay gets a "Provisional bill". Invoice number:
  `<RESORT-SLUG>-<first 8 hex of the booking id>`.
- **Report PDFs** — Finance → Collections / Ledger / Settlements ("Export PDF"
  next to "Export CSV") and Owner → Reports.
- Web downloads the file; Android/iOS/desktop open the share sheet
  (`package:printing`). Fonts: Noto Sans (SIL OFL 1.1, `assets/fonts/`).
