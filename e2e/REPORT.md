# E2E results: Playwright suite

Latest: 2026-09-26, branch `feat/gaps` (P1-P11 merged), release web build
(`./build-app.sh`, `E2E=true`) rebuilt from the branch head, local Supabase
stack at migration 0060. One worker, Chromium, two projects: `desktop`
(1280x800) and `phone` (Pixel 7: 412x839, touch, Android Chrome). The
section "Earlier: main" below is the 2026-09-25 report on `main`, kept for
its history.

## Gap round (feat/gaps): run results

| Check | Result |
|---|---|
| `npx tsc --noEmit` (e2e) | clean |
| Tests | 68 per project (was 50), 136 per full run |
| First full run with the new specs | 134 passed, 2 failed (both the same helper race, fixed below) |
| Final full run 1, both projects | **136 passed**, 0 failed, 0 flaky (17.5 min) |
| Final full run 2, both projects | **136 passed**, 0 failed, 0 flaky (17.7 min) |
| `test.fail` / `test.fixme` / `test.skip` / `test.only` in `e2e/tests` | none |
| After each final run | 0 `@e2e.resorthub.test` users, 0 `e2e-` resorts |
| Non-e2e row counts (every `public` table plus `auth.users`), before vs after | identical |
| App bugs found | none (no `lib/` or SQL change in this round) |

### The one flaky failure, and its fix

`login()` switching users on a page that already runs the app (the
coupon test's owner-then-guest, the listing test's guest-then-owner) went
to `/#/login`, which is only a hash change there: the signed-in app bounced
it to its landing page a moment after the helper had already seen
`/login`, so the email field vanished under `fillField`. `support/auth.ts`
now drops the session and reloads first when the app is already open. A
test-helper race, not an app bug.

### New specs

Each brings its own resort and accounts (`support/kit.ts`), created in
`beforeAll` and removed in `afterAll` by exact slug and email, so no shared
`world.ts` resort changes (Resort A's CSV header and tax rates stay as other
specs expect).

| Spec | Personas | What it does |
|---|---|---|
| `coupons.spec.ts` (P1) | owner, guest | Owner opens Coupons from the owner hub, creates `E2ESAVE10` (10%); the card reads Active, 10% off, No date limits, Used 0 · Everyone. Guest books, types the code in lower case in the quote sheet, sees `Coupon (E2ESAVE10)` -₹850 and total ₹7,650, pays; the booking's quote carries the code and one redemption exists. Owner sees Used 1, deactivates it (Inactive, Activate offered); the guest's next Apply is refused with "coupon not found or inactive". |
| `finance-tax.spec.ts` (P4) | owner | Owner sets Food & drink 5% and Spa & activities 18% on Settings > Taxes; logs a ₹1,050 food sale and a ₹1,180 activity sale on Food & activity sales; the rows keep 5%/₹50.00 and 18%/₹180.00; Finance > Ledger shows `F&B tax ₹50.00`, `Spa/Activities tax ₹180.00` and both rates. Raising the food rate to 12% changes the rate line, not the recorded ₹50.00. |
| `ota-sync.spec.ts` (P9) | admin | Units > unit menu > OTA sync. A feed added in the app reads "Never synced"; Sync now makes the database fetch (pg_net) an Airbnb-style export (CRLF, folded UID, `VALUE=DATE`, "Reserved" / "Airbnb (Not available)") from a loopback server the spec runs: "Synced -- 2 events", "Last sync just now · 2 events", two imported blocks. A second feed whose link returns 404 shows "Sync failed just now: HTTP 404", the relink hint and "No successful sync yet"; the first keeps its good status. |
| `outbox.spec.ts` (P7) | staff, owner | A fixture booking queues its messages through the real trigger; the dispatcher's no-key outcome is applied to this resort's due emails with the dispatcher's own `complete_outbox_message(..., 'dry_run', ...)` (running `outbox-dispatch` itself would claim the real resort's queue too). Staff see "Dry run (2)", "Skipped (2)", each row with its reason, and no Send again; the owner sends one again: "Queued to send again.", Pending (1), Dry run (1), the row back to attempts 0. |
| `listing.spec.ts` (P10) | new owner, guest, platform admin | Welcome > List your resort > sign-up form (a real new account) > back on List your resort; apply; lands on `/owner` with "0 of 6 done"; the GSTIN step through its Taxes screen ("1 of 6"), the other five as that owner through RLS; Refresh checklist "6 of 6"; Submit for review (the `listing_submitted` email is queued). Guests cannot find it. Platform: "Waiting for review N" matches the database, Pending review filter, search, Approve > confirm, resort active, `listing_approved` queued. Guests then find it; the owner gets the normal hub (no checklist) and the application reads Approved. |
| `discovery.spec.ts` (P11) | guest | Three resorts with known distance, price and rating, chosen so every sort order differs from the previous one. No location: Distance is not in the sort menu and cards show no distance; Recommended (Far, Near, Mid by 0060's weighted score), Price low to high (Mid, Far, Near), Rating (Far, Mid, Near; unrated last). Geolocation granted at 12.97 N 77.59 E (Nominatim answered locally): the badge reads "Bengaluru, India", each card shows the haversine distance the server computes (2 / 48 / 227 km), Distance sorts Near, Mid, Far, and a narrower search keeps the sort. |

Changed specs:
- `owner.spec.ts`: "without Razorpay the plan stays manual" (P8). The
  suite runs the real `billing-subscribe` entry point under Deno with no
  Razorpay keys (`support/functions.ts`) and routes the app's call to it:
  the probe answers `{configured:false}`, the plan tile reads "Plan:
  Enterprise / Paid, no end date", and there is no Auto-pay card and no
  "Pay / manage subscription".
- `stay-pass.spec.ts`: the check-in test now goes through Scan pass (P3):
  the scanner screen, its no-camera message, "Enter code instead", then the
  signed pass typed into the check-in field.
- `guest.spec.ts`: `pickStayDates` moved to `support/booking.ts` (shared with
  the coupon booking). No behaviour change.

## Coverage per gap (P1-P11)

| Gap | Covered by | Not covered |
|---|---|---|
| P1 Coupons | coupons: create, list with usage, apply at booking, discount and total, redemption, deactivate, refused after | Editing a coupon, one-guest coupons, date and usage limits (widget and pgTAP tests cover them) |
| P2 PDF invoices | accountant: settlement row invoice and the guest's invoice (`invoice-E2E-A-E2EACC00.pdf`, `%PDF-`), Collections Export PDF; frontdesk: Download invoice after the desk checkout (`.pdf`) | PDF contents beyond the header bytes |
| P3 QR passes | stay-pass: tampered pass refused; Scan pass screen, Enter code instead, the signed pass checks the guest in | The camera itself (a headless browser has none) |
| P4 Food & spa tax | finance-tax: rates on the Taxes screen, tax stored per sale, Ledger per category and rates, history kept after a rate change | Food orders and activity bookings made by guests (same triggers, pgTAP-covered) |
| P5 Leftovers | frontdesk: desk checkout lands on the check-out list with the banner and invoice; owner: readable last-owner error; every spec at phone size | P0021 message is not triggered in the UI |
| P6 Razorpay | guest and coupons bookings fall back to the mock gateway | The configured path (needs Razorpay test keys); `payments-create-order` is not served to the suite because even its no-key answer writes the global live switch |
| P7 Email and SMS | outbox: Dry run section with reasons, staff read-only, owner Send again | Running `outbox-dispatch` end to end (it claims every resort's queue); the delivery panel's channel lines |
| P8 Subscription billing | owner: real `billing-subscribe` without keys, plan stays manual | The configured card (needs Razorpay plan ids and keys) |
| P9 OTA sync | ota-sync: never synced, real fetch and import, event count, HTTP 404 error with hint | Stale-sync warning (needs a sync over an hour old) |
| P10 Self-listing | listing: welcome entry, sign-up, apply, checklist, submit, pending hidden, platform count, filter, approve, visible to guests | Reject with reason (pgTAP and widget tests) |
| P11 Search and discovery | discovery (above); guest: search box, empty state, Clear filters, amenity chips | Owner's "Use my current location" on Map location |

## Coverage per persona

The suite has 68 tests, and each runs in both projects.

| Persona | Specs | Tests |
|---|---|---|
| Guest / customer | guest (10), discovery (3), coupons (guest parts), listing (guest parts) | 13 own + shared |
| Owner | owner (8), coupons, finance-tax (3), outbox (owner part), listing (applicant) | 11 own + shared |
| Front desk (admin) | frontdesk (7), stay-pass (2), ota-sync (2) | 11 |
| Staff / incharge | staff (6), outbox (staff part) | 6 + shared |
| Accountant | accountant (9) | 9 |
| Platform admin | platform (7), listing (approval) | 7 + shared |
| Smoke | smoke (2) | 2 |

Cross-persona specs: coupons (3: owner, guest, owner+guest), outbox (2:
staff, owner), listing (4: new owner, guest, platform, guest+owner).

## Coverage per requirement (REQ-01 to REQ-09), gap round additions

- REQ-01 Guest discovery UI: the location badge ("Bengaluru, India") is now
  asserted, with a fixed position; search and sort (discovery).
- REQ-03 Details and maps: distance on each card (discovery).
- REQ-04 Split payment: coupon discount in the quote sheet (coupons).
- REQ-05 QR pass: the Scan pass path at the desk, and a signed pass checks
  the guest in (stay-pass).
- REQ-06 Front desk: OTA calendar sync status (ota-sync).
- REQ-07 Ledger: F&B and Spa/Activities tax values and rates, checked
  value by value (finance-tax); PDF exports (accountant).
- REQ-08 SaaS portal: the Pending review queue and approval (listing); the
  plan stays manual without Razorpay (owner).
- REQ-02 and REQ-09: unchanged from the table below.

---

# Earlier: main (2026-09-25)

## Run results

| Check | Result |
|---|---|
| `supabase migration up --local` | 0047-0050 applied (see "DB incident" below) |
| `supabase test db` (pgTAP) | 40 files, 989 tests, PASS |
| `flutter analyze` | 2 issues: the baseline infos in `service_request_screen.dart` |
| `flutter test` | 917 passed, 0 failed |
| `npx tsc --noEmit` (e2e) | clean |
| Playwright, first run after the merge | 42 passed, 2 failed (both fixed in 9719ee9, see below) |
| Playwright, final run 1 | **44 passed**, 0 failed, 0 flaky, 0 skipped (4.1 min) |
| Playwright, final run 2 | **44 passed**, 0 failed, 0 flaky, 0 skipped (4.1 min) |
| Playwright on `feat/gaps` (P1-P11 merged), desktop project | **50 passed**, 0 failed |
| Playwright on `feat/gaps`, phone project | **50 passed**, 0 failed |
| Playwright on `feat/gaps`, both projects, final runs 1 and 2 | **100 passed** each, 0 flaky (10.6 and 10.9 min) |
| `test.fail` / `test.fixme` / `test.skip` left in `e2e/tests` | **none** |
| Teardown after each final run | 0 `@e2e.resorthub.test` users, 0 `e2e-` resorts |
| Non-e2e row counts (every `public` table plus `auth.users`) | same as before the runs |

### Failures on the first merged run, and how they were fixed

1. **`frontdesk.spec.ts`: "the desk checkout page survives a page reload".**
   A reload still ended on `/admin`. When the session loads, the user
   changes and then the resort changes, so the router refreshes twice while
   the app is still on `/splash`. Each refresh re-reads the location the
   Router last reported, and that lags until the end of the frame. The
   first redirect returned the held location and then forgot it. The second
   redirect, still on `/splash`, sent the user to their landing page.
   - The branch's router test missed this because it stubbed the resort
     as a constant, so only one refresh fired.
   - Fix (`lib/core/router.dart`): the held location is forgotten only
     after a frame that shows a page beyond the pre-auth screens, or when
     the session turns out to be signed out.
   - New test in `test/core/router_test.dart` uses the real
     `CurrentResort`, so both refreshes fire.
2. **`guest.spec.ts`: "cancelling a confirmed booking shows the cancelled state".**
   - (a) The spec found the calendar's forward arrow by taking the second
     `role=button` with no name. The test books 10 days ahead, which crosses
     into the next month, and there were 9 unnamed buttons on the page, so
     it failed. Fix: the date sheet's arrows now have tooltips, "Previous
     month" and "Next month", which screen readers also use. A widget test
     covers them, and the spec clicks "Next month" by name.
   - (b) This was predicted in the review. The "Booking cancelled"
     snackbar text also appears in Flutter web's aria-live announcer
     (`flt-announcement-polite`), so the locator matched 2 elements.
     Fix: the locator is scoped to `flt-semantics-host`.

### DB incident during this session

Partway through, the shared local stack's DB container was restarted from
outside this session (started 04:48:36Z). It came back with migrations only
up to 0046 and no seed data, probably from the `feat/resorthub-tenancy`
worktree. Recovery:
- `supabase migration up --local` applied 0047-0050.
- `supabase/seed.sql` was re-applied through psql. There was no
  `db reset`.
- The row counts then matched the baseline taken before any E2E run
  exactly. pgTAP was re-run afterwards and passed.
- Both final runs and the teardown checks ran after this recovery.

## Bugs the suite found, all fixed

Each bug was marked with `test.fail` in the first version of the suite. All
of those markers are now ordinary tests.

| Bug | Spec | Fixed in |
|---|---|---|
| Cancelling a booking reached by a direct link threw "nothing to pop" and kept showing the confirmed state | guest | `fix-e2e-guest` (booking_detail_screen) |
| A resort with more than one unit crashed its booking section (`list.single`) | guest | `fix-e2e-guest` (property_screen unit picker) |
| The desk checkout did not survive a page reload | frontdesk | `fix-e2e-ops` (single router, held location) + 9719ee9 |
| Deleting a task on `/admin/tasks` blanked the page and did not delete the task (dialog popped the shell navigator) | staff | `fix-e2e-ops` (tasks_screen) |
| NotFoundScreen had no semantics heading, so screen readers and the suite could not see it | staff | `fix-e2e-ops` (not_found_screen) |
| Demoting the only owner showed the raw code word `last_owner` | owner | `fix-e2e-ops` (errors.dart P0023; P0021 also mapped) |
| `tasks_enforce_write` blocked the FK set-null and deletes by psql with no JWT, which broke the fixture teardown | staff / teardown | `fix-e2e-db` (migration 0050 + pgTAP) |

## Coverage per persona

The suite has 50 tests, and each runs in both projects.

| Persona | Spec | Tests | What is exercised |
|---|---|---|---|
| Guest / customer | `guest.spec.ts` | 10 | Signs in with no sign-up step; browse shows only active resorts and greets the guest; theme toggle; amenity filter; search box and Clear filters; resort page (photo counter, address, reviews); booking with the 35% advance option through the mock gateway, then My Bookings; cancelling shows the cancelled state; My Stay pass; unit picker at a resort with several units |
| Owner | `owner.spec.ts` | 7 | Lands on `/owner` with the day's figures; Team add/role change/remove; refuses to demote the only owner (readable error); plan line shows the subscription tier; Rooms tile opens the grid; Finance tile; tenancy (never sees a Resort B booking) |
| Front desk (admin) | `frontdesk.spec.ts` | 7 | Dashboard; bookings list; check-in marks the unit occupied; check-out with a desk Cash payment and reference, back on the check-out list with a success banner and a PDF invoice download, after which the room needs cleaning; units and rates screens; a Resort B URL gives not-found; the desk checkout survives a reload |
| Staff / incharge | `staff.spec.ts` | 6 | `/staff` Today with the staff bar; room grid tiles and counts; Maintenance needs a reason; a housekeeping dispatch reaches Assigned Work and clears the room on completion; `/owner` gives 404 (heading); admin deletes a task from `/admin/tasks` |
| Accountant | `accountant.spec.ts` | 9 | Lands on Finance with the accountant bar; Today online vs front-desk split; Collections and Ledger; Settlements (advance vs desk balance); CSV export download; Collections PDF export; a settlement row's invoice PDF; the guest's invoice PDF from booking detail; read-only room grid |
| Front desk (passes) | `stay-pass.spec.ts` | 2 | A tampered check-in pass is refused with a readable message; a guest's signed pass opens their check-in and checks them in |
| Platform admin | `platform.spec.ts` | 7 | Totals cards; tier filter; search; tier and paid-through edit; suspend/reactivate; "+ Add resort"; sees no guest PII |
| Smoke | `smoke.spec.ts` | 2 | Welcome page; owner sign-in |

## Coverage per requirement (REQ-01 to REQ-09)

| REQ | Covered by | Not covered |
|---|---|---|
| REQ-01 Guest discovery UI | guest: greeting, "Discover your stay", resort cards, theme toggle, profile access via sign-in | Colour palette (mint/emerald, no blue) and the "Bengaluru, India" location badge are visual and not asserted |
| REQ-02 Amenities filter | guest: the Spa chip filters the list; All restores it | Horizontal scroll, the highlight badge style and count displays are not asserted |
| REQ-03 Details, gallery counter, maps | guest: "1 / N" photo counter, address text, reviews link | Opening Google Maps in a new tab with GPS coordinates; the counter advancing as you swipe |
| REQ-04 35% split payment | guest: booking offers "Pay 35% advance now" and full payment, then confirms through the mock gateway; accountant: Settlements shows advance vs desk balance; frontdesk: balance taken at the desk on checkout | The itemised 65% balance line in the modal; a real payment gateway |
| REQ-05 QR pass | guest: My Stay pass card for the checked-in guest (reached through the semantics tree) | Scanning the QR or checking its contents (it is canvas pixels); scanning it at the front desk |
| REQ-06 Front desk and housekeeping | frontdesk: check-in and check-out change room status; staff: room grid, Maintenance reason, housekeeping dispatch through to completion, task delete | Scanning a pass to check in; guest service tabs; cleaning SLA tracking |
| REQ-07 Ledger and settlement | accountant: Today split, Collections, Ledger, Settlements, CSV export; owner: Finance tile | Checking each ledger category (Room/F&B/Spa/Ancillary) value by value; the tax summary figures |
| REQ-08 SaaS portal | platform: totals cards, tier filter, search, tier and paid-through edit, suspend/reactivate, "+ Add resort", no PII; owner: plan line | The exact "21 subscribed" figures, which depend on the fixtures |
| REQ-09 Light/dark and cache | guest: theme toggle both ways | Toggling on admin and staff screens; the service-worker / PWA cache bypass is not tested |

## Remaining gaps and follow-ups

- **Visual checks:** colours, dark mode on every screen, and the QR image
  are not asserted. Screenshot comparison would be needed. Both sizes are
  covered by behaviour (bottom navigation, `reveal()` for below-the-fold
  content), not by screenshots.
- **Maps redirect and service-worker caching:** not driven. Playwright
  could check the popup URL and the network cache headers.
- **Items left open from the fix reviews:**
  - The same dialog-context pop bug exists in five other screens
    (ops Minor 7).
  - A staff-picker active-unit filter and a hold-orphaning edge case in
    the guest unit picker.
  - Migration 0050 comment wording (service_role never reaches the
    trigger).
  - An optional pgTAP assertion for the no-JWT UPDATE bypass.
- **Shared test DB:** the suite shares one local database with the other
  worktrees. A reset or restart from another checkout during a run breaks
  it. That happened in this session, and the run was repeated after
  recovery.

## Phone project (P5) and the gap-round checks

Specs added with the gap projects: `stay-pass.spec.ts` (P3: a tampered
pass is refused; a guest's pass checks them in), the accountant's PDF
checks (P2: Collections Export PDF, a settlement row's invoice, the
guest's invoice from booking detail), the desk checkout landing with its
invoice download (P5) and the guest search box (P11).

Fixes the phone project and the merged branch needed:
- The desk checkout's Reference field could not be focused on a phone:
  the payment Card merged its semantics, so the field's node covered the
  whole card, over the method chips. Fixed in the app
  (`Card(semanticContainer: false)`), not in the helper.
- A card that gains a button (the Settlements row's "Invoice PDF", the
  check-out banner's "Download invoice") becomes a group whose text is
  its `aria-label`; `bodyLines` and the banner check read that too.
- The CSV export test polls for its SnackBar instead of reading once.

