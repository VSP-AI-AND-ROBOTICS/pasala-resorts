# P5 Leftovers: desk checkout landing, P0021 message, phone-size E2E — Design

## Why

The Playwright report (`e2e/REPORT.md`, "Remaining gaps and follow-ups") and
the fix reviews left three small items open. The product owner accepted all
three in the gap-closing round (P5 in the round's decisions, 2026-09-25):

- **Desk checkout ends on a guest route.** Reception's desk checkout
  (`CheckoutScreen(desk: true)` at `/admin/check-out/:reservationId`,
  `lib/features/stay/checkout_screen.dart`) finishes with
  `context.go('/my-stay/invoice/<id>')`. That is the guest's own "Final
  Invoice" screen, with a guest "Leave a review" button. Reception has to
  find its way back to `/admin/check-out` for the next guest. The report
  lists this as "ops Minor 6".
- **P0021 `resort_mismatch` showed a bare code word.** The resort-consistency
  trigger (`0043_resort_tenancy.sql`) raises P0021 with the text
  `resort_mismatch`. It used to be passed through as `InvalidState(message)`,
  so the screen showed the code word.
- **Only the wide layout is tested.** `e2e/playwright.config.ts` has one
  project (Desktop Chrome, 1280x800). The only phone-size coverage is
  `clickTab` (`e2e/support/nav.ts`) and the accountant spec's own `narrow()`,
  which shrink the viewport's width to 400 to reach the bottom navigation
  bar. No spec runs as a phone.

## Decisions (agreed 2026-09-25, auto-approved)

From the round's accepted decisions:

1. After a desk checkout, reception returns to `/admin/check-out` (the
   reception list), with a success message and a **Download invoice**
   action. The action uses P2's booking invoice PDF. The guest's
   `/my-stay/invoice` route is no longer used for desk checkouts.
2. P0021 `resort_mismatch` gets a readable message in `lib/core/errors.dart`.
3. Playwright gets a phone-size project (Pixel 7). The persona specs pass
   at both sizes. Helpers are adjusted for the bottom navigation bar; there
   are no screenshot comparisons.

Judgment calls made while writing this spec (no questions asked):

4. **The success message lives in the URL**:
   `/admin/check-out?checkedOut=<reservationId>`. The desk checkout and the
   router already put everything in the URL so that a web reload or
   back/forward rebuilds the page (`frontdesk.spec.ts`'s reload regression).
   A route `extra` or in-memory state would lose the banner, and with it
   the Download invoice action, on a reload. `GoRouterState.matchedLocation`
   (which `redirectFor` checks) excludes the query, so the role matrix is
   unchanged.
5. **A banner, not a snackbar.** The banner is a card at the top of the
   check-out list. It says "Guest checked out" and "Booking `<first 8
   characters of the id>` is settled.", and has **Download invoice** and a
   **Dismiss** (X) button. A snackbar would disappear after 4 seconds and
   take the download action with it. The banner stays until it is
   dismissed, another guest is checked out (the URL changes), or reception
   leaves the list. It shows above the empty state too, because the last
   guest out leaves the list empty. It is a `Semantics(liveRegion: true)`
   container, so screen readers announce it.
6. **No guest name in the banner.** The desk screen knows only the
   reservation id, and `BookingRepository.reservation(id)` does not embed
   the profile. The short booking id matches `FinalInvoiceScreen`'s
   "Booking abcd1234" and the id part of P2's invoice number. Adding the
   name would mean a new query for one line of text.
7. **P5 owns a small seam for P2**, in
   `lib/features/admin/desk_invoice.dart`:
   `typedef DeskInvoiceDownload = Future<void> Function(BuildContext context, WidgetRef ref, String reservationId);`
   and `final deskInvoiceDownloadProvider = Provider<DeskInvoiceDownload?>(...)`.
   This follows the `csvDownloaderProvider` precedent in
   `lib/features/finance/providers.dart`. The banner passes its own context
   and ref, and the provider's own `Ref` is in scope where the binding is
   written. So the binding can call P2's entry point with whatever that
   needs: a `Ref`, a `WidgetRef`, a `BuildContext`, or plain data read
   through them. P2's plan is being written at the same time as this one,
   so its exact name is looked up when the provider is bound. Until P2 is merged the provider
   returns `null`, and the banner hides the button. So the P5 Flutter work
   ships and is tested on its own. The final integration task binds the
   provider to P2's "build this booking's invoice PDF and save it" entry
   point. On the web that must be a file **download** (a `.pdf`), not a
   print dialog, so the E2E suite can check it. P5 depends on P2.
8. **The P0021 copy has already landed.** Commit `8f46008` ("fix(errors):
   map P0021 resort_mismatch to readable copy") added `ResortMismatch`
   ("That belongs to a different resort.") and a unit test in
   `test/core/errors_test.dart`. P5 keeps that copy. It adds only a
   regression test that goes from the server's error through
   `mapPostgrestError` and `FailureView` to the screen, so the code word can
   never reach the screen again. The banner's error path is covered too: a
   failed invoice download that raises P0021 shows the same copy.
9. **The Playwright projects are named `desktop` and `phone`.** `desktop` is
   today's project, renamed from `chromium`: `devices['Desktop Chrome']`
   at 1280x800. `phone` is the full `devices['Pixel 7']` descriptor:
   412x839 viewport, deviceScaleFactor 2.625, `isMobile`, `hasTouch`, and an
   Android Chrome user agent, running in Chromium. A plain 412-wide window
   would not exercise Flutter web's mobile code paths (text input
   strategy, touch). Nothing in the repo refers to the old project name.
10. **Both projects run every spec, one after the other, in one run.**
    `workers: 1` stays. Each spec file's `beforeAll`/`afterAll` fixtures run
    once per project, and every mutating test already restores what it
    changes (the platform, owner and staff specs say so in their headers).
    So the second project finds the same fixture world. The global
    setup/teardown still runs once per `playwright test`.
11. **Helpers, not screenshots.** `e2e/support/nav.ts` gets:
    `WIDE_BREAKPOINT` (840, `PasalaTokens.wideBreakpoint`),
    `isNarrow(page)`, `useBottomNav(page)` (narrows only when wide; at phone
    size it does nothing), `clickTab` rebuilt on `useBottomNav`, and
    `reveal(page, locator)`. `reveal` scrolls the main scrollable with the
    mouse wheel until the target is in the semantics tree and visible. The
    accountant spec's private `narrow()` is replaced by `useBottomNav`.
    Specs call `reveal` before touching anything that sits below the fold
    on a phone. Flutter builds a lazy list's children only near the
    viewport, so an item further down is not in the DOM at all, and
    Playwright's own scroll-into-view cannot reach it. At desktop size
    `reveal` returns at once.
12. **No database work.** P5 has no migration, no SQL function, no pgTAP
    file and no new error code. Its pre-assigned 0054 slot is unused.

## Data model

None. No table, column, function, grant or policy changes.

## App

### Desk checkout landing

- `lib/features/admin/desk_invoice.dart` (new):
  `DeskInvoiceDownload` typedef
  (`Future<void> Function(BuildContext context, WidgetRef ref, String reservationId)`)
  and `deskInvoiceDownloadProvider` (`Provider<DeskInvoiceDownload?>`,
  `null` until the integration task binds it to P2).
- `lib/features/admin/desk_checkout_banner.dart` (new):
  `DeskCheckoutBanner({required String reservationId, required VoidCallback onDismiss})`,
  a `ConsumerStatefulWidget`:
  - a card keyed `desk-checkout-done`, in the primary container colour,
    with a check icon, the title "Guest checked out", and the line
    "Booking `<short id>` is settled."
  - **Download invoice** (`TextButton.icon`, download icon) only when
    `deskInvoiceDownloadProvider` is non-null. It calls the download with
    the reservation id. While the download runs the label is "Preparing
    invoice…" and the button is disabled, so a double tap downloads once.
    A failure shows a snackbar with
    `FailureView.messageFor(mapPostgrestError(e))`: readable copy for a
    `BookingFailure`, "Something went wrong." for anything else. The
    banner stays.
  - **Dismiss** (`IconButton`, tooltip "Dismiss") calls `onDismiss`.
  - wrapped in `Semantics(container: true, liveRegion: true)`.
- `lib/features/admin/reception_checkout_screen.dart`:
  - `const checkedOutParam = 'checkedOut';`
  - `String deskCheckoutDoneLocation(String reservationId)` builds
    `/admin/check-out?checkedOut=<id>`, URL-encoded through `Uri`.
  - `ReceptionCheckoutScreen({super.key, this.checkedOutId})`. A blank id is
    treated as none. The body is a `Column`: the banner (keyed by the id,
    so a new checkout resets its busy state) when there is an id, then
    `Expanded(AsyncView(...))` with today's list or empty state, unchanged.
    Dismiss does `context.go('/admin/check-out')`.
- `lib/core/router.dart`: the `/admin/check-out` route's builder passes
  `state.uri.queryParameters[checkedOutParam]` as `checkedOutId`. The role
  matrix and the `:reservationId` child route are unchanged.
- `lib/features/stay/checkout_screen.dart`: a successful **desk** checkout
  goes to `deskCheckoutDoneLocation(reservationId)` instead of
  `/my-stay/invoice/<id>`. Everything else stays as it is: the
  invalidations (current stay, charges, finance, check-out queue, bookings,
  room board), the guest's own checkout (still `/my-stay/invoice/<id>`) and
  the error snackbar.

### P0021 message

- `lib/core/errors.dart` is unchanged: `'P0021' => const ResortMismatch()`,
  copy "That belongs to a different resort.".
- A regression test in `test/core/widgets/failure_view_test.dart`: a
  `PostgrestException(code: 'P0021', message: 'resort_mismatch')` passed
  through `mapPostgrestError` renders the copy in `FailureView`, and never
  `resort_mismatch`.

## E2E (Playwright)

- `e2e/playwright.config.ts`: `projects` becomes `desktop` (Desktop Chrome,
  1280x800) and `phone` (`devices['Pixel 7']`). The top-level
  `use.viewport` is removed, because each project sets its own.
- `e2e/support/nav.ts`: `WIDE_BREAKPOINT`, `isNarrow`, `useBottomNav`,
  `clickTab` (through `useBottomNav`), `reveal`. `e2e/support/index.ts`
  re-exports them.
- Specs:
  - `accountant.spec.ts`: `narrow()` becomes `useBottomNav()`.
  - `reveal()` goes before assertions and clicks on content that can sit
    below the fold on a phone: the owner hub's MANAGE tiles (owner and smoke
    specs), the admin dashboard's quick actions, the guest resort page's
    address, reviews link, booking controls and quote sheet buttons, the
    booking detail's Cancel booking, My Stay's Checkout button, the
    platform console's resort cards, and the room grid's tiles.
  - `frontdesk.spec.ts`: the desk checkout test lands on `/admin/check-out`
    and sees the "Guest checked out" banner. **Download invoice** produces a
    download whose file name ends in `.pdf`. The room grid then shows
    Cleaning. (This change goes in with the integration task, after P2's
    binding.)
- `README.md` ("End-to-end tests"): the two projects, and how to run one:
  `npx playwright test --project=phone`.
- `e2e/REPORT.md`: run results per project. Drop the "Only the wide layout"
  gap and "The desk checkout ends on a guest invoice route (ops Minor 6)".

## Rules

- No route guard changes. `/admin/check-out` stays staff-or-above at the
  current resort, and the query parameter is not a permission.
  `checkout_booking` and P2's data reads keep enforcing access in Postgres.
- The banner never shows raw server text (`FailureView.messageFor`).
- The guest's self-checkout path is unchanged.
- No screenshot or pixel assertions in the E2E suite.

## Testing

- Flutter:
  - `test/features/admin/reception_checkout_screen_test.dart`:
    - no banner without the parameter, or with a blank one
    - the banner shows with the list, and above the empty state
    - Download invoice passes the id once and shows the busy label
    - no button while the provider is `null`
    - a P0021 failure shows "That belongs to a different resort."
    - any other failure shows "Something went wrong."
    - Dismiss clears the banner and the URL's query
  - `test/features/stay/checkout_screen_test.dart`:
    - a desk checkout lands on `/admin/check-out?checkedOut=r1`, never the
      guest invoice
    - the two existing desk tests follow it there
    - the guest checkout still ends on its invoice
  - `test/core/router_test.dart`: the real router builds the list with
    `checkedOutId` from `/admin/check-out?checkedOut=res-1` (URL alone, as a
    reload does)
  - `test/core/widgets/failure_view_test.dart`: the P0021 chain
- E2E: `npx tsc --noEmit`, and `npx playwright test --list` shows every test
  under both projects. The full suite passes under `--project=desktop` and
  `--project=phone` against the local stack with the E2E build.
- `flutter analyze`: only the two baseline infos in
  `service_request_screen.dart`. `flutter test`: all green.

## Out of scope

- A guest name in the banner.
- Screenshot or visual comparison.
- WebKit or Firefox projects, tablet sizes, landscape.
- Making absence assertions (`toHaveCount(0)`) on lazy lists scroll to the
  end first. The server-side isolation they back is covered by pgTAP.
- The other open items from the fix reviews (the dialog-context pop in
  other screens, the staff-picker active-unit filter, the 0050 comment
  wording).
- The invoice PDF itself (P2).
