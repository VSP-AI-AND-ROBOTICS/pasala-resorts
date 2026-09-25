# E2E results: Playwright suite on main

Date: 2026-09-25. Branch `main`, after merging `fix-e2e-guest`, `fix-e2e-ops`
and `fix-e2e-db`, plus follow-up commit 9719ee9. The suite drives the
release web build (`./build-app.sh`, `E2E=true`) through Flutter's semantics
DOM against the local Supabase stack. It runs one worker, in Chromium, at
1280x800.

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

The suite has 44 tests.

| Persona | Spec | Tests | What is exercised |
|---|---|---|---|
| Guest / customer | `guest.spec.ts` | 9 | Signs in with no sign-up step; browse shows only active resorts and greets the guest; theme toggle; amenity filter; resort page (photo counter, address, reviews); booking with the 35% advance option through the mock gateway, then My Bookings; cancelling shows the cancelled state; My Stay pass; unit picker at a resort with several units |
| Owner | `owner.spec.ts` | 7 | Lands on `/owner` with the day's figures; Team add/role change/remove; refuses to demote the only owner (readable error); plan line shows the subscription tier; Rooms tile opens the grid; Finance tile; tenancy (never sees a Resort B booking) |
| Front desk (admin) | `frontdesk.spec.ts` | 7 | Dashboard; bookings list; check-in marks the unit occupied; check-out with a desk Cash payment and reference, after which the room needs cleaning; units and rates screens; a Resort B URL gives not-found; the desk checkout survives a reload |
| Staff / incharge | `staff.spec.ts` | 6 | `/staff` Today with the staff bar; room grid tiles and counts; Maintenance needs a reason; a housekeeping dispatch reaches Assigned Work and clears the room on completion; `/owner` gives 404 (heading); admin deletes a task from `/admin/tasks` |
| Accountant | `accountant.spec.ts` | 6 | Lands on Finance with the accountant bar; Today online vs front-desk split; Collections and Ledger; Settlements (advance vs desk balance); CSV export download; read-only room grid |
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
  are not asserted. Screenshot comparison would be needed.
- **Maps redirect and service-worker caching:** not driven. Playwright
  could check the popup URL and the network cache headers.
- **Only the wide layout (1280x800) is covered**, apart from `clickTab`,
  which narrows the viewport to reach the bottom navigation bar. There is
  no phone-size pass.
- **Items left open from the fix reviews:**
  - The desk checkout ends on a guest invoice route (ops Minor 6).
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
