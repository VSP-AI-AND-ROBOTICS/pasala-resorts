# QR Scanning at the Front Desk (P3) — Design

## Why

The guest already sees a "Check-in QR" in three places: the booking
confirmation (`lib/features/booking/confirmation_screen.dart`), the booking
detail (`lib/features/account/booking_detail_screen.dart`) and My Stay
(`lib/features/stay/my_stay_screen.dart`). Each one encodes the bare
reservation UUID with `qr_flutter`, and the confirmation screen's own comment
admits it is "decorative only": nothing in the app ever scans it back.
Reception's `/admin/check-in` (`lib/features/admin/reception_checkin_screen.dart`)
is a list of every `confirmed` booking with a Check In button and no way to
find a booking except by scrolling.

A bare UUID is also not proof of anything. Anyone who has seen a booking id
(a forwarded screenshot, a guest from another resort) can show it, and it
never expires.

This project makes the QR a signed, expiring check-in pass that reception
scans with the device camera to open that booking's check-in, and keeps a
typed fallback.

## Decisions (accepted 2026-09-25, gap-closing round P3; the ones marked *plan* were made while writing this spec)

1. **The QR payload is a compact signed token** carrying the reservation id,
   the property id and an expiry, signed with HMAC-SHA256 under a
   per-deployment secret held server-side.
2. **`issue_stay_pass(p_reservation)`** is a security definer function that
   returns the token for the caller's own booking only.
3. **`verify_stay_pass(p_token)`** is for Staff+ at the token's resort. It
   returns the reservation, or raises **P0034** with one of three code words:
   `pass_invalid`, `pass_expired`, `pass_other_resort`.
4. **The secret lives in a server-only table** that only the definer
   functions read. The migration seeds a random secret if none exists.
5. **Package `mobile_scanner`** (7.x; it supports the web camera).
6. **Reception check-in** gets a "Scan pass" button: camera → verify → that
   booking's check-in. Manual entry is kept.
7. **The guest's QR screens render the signed token.**
8. *plan* **Token format**: `rh1.` followed by 75 base64url characters
   (no padding) encoding 56 bytes: reservation id (16) ‖ property id (16) ‖
   expiry as epoch seconds (8, big-endian) ‖ the first 16 bytes of
   HMAC-SHA256(secret, `rh1.` ‖ those 40 bytes). The whole pass is 79
   characters, which fits a small QR (version 5 at level M). The `rh1.`
   prefix is the format version, so a later format can live alongside it.
9. *plan* **Expiry = the end of the stay** (`upper(period)`). The same booking
   always gets the same pass, so a screenshot taken at booking time still
   works on arrival day, and a pass cannot be used after the stay ends. A
   short rolling expiry was rejected because guests often arrive with poor
   signal.
10. *plan* **"Staff+" is `owner, admin, staff, accountant`**, the same set as
    `check_in_booking` (0045). Verifying is a read (`has_resort_role(…, false,
    …)`), so it works while the resort is suspended; the check-in itself
    still gets P0022 there.
11. *plan* **Order of checks in `verify_stay_pass`**: format and signature
    (`pass_invalid`) → the caller's role at the token's resort
    (`pass_other_resort`) → expiry (`pass_expired`) → the reservation still
    exists at that resort as a booking (`pass_invalid`). A staff member of
    another resort learns only "other resort", never whether the pass expired.
12. *plan* **Verify returns the booking in any status.** A cancelled,
    checked-out or already-checked-in booking is shown with its status and
    no Check In button. `check_in_booking` stays the only thing that changes
    status.
13. *plan* **Only the guest issues a pass.** Staff calling `issue_stay_pass`
    get P0002 like any non-owner of the booking; a front desk does not need to
    mint passes. Errors: no user → P0008; not the caller's booking, unknown,
    or not `kind = 'booking'` → P0002 `reservation not found` (it does not
    reveal whether the id exists); status other than `confirmed` /
    `checked_in` → P0009 `reservation is <status>`.
14. *plan* **Where the secret lives**: table `private.stay_pass_secret` in a
    new `private` schema that is not in the API's exposed schemas
    (`supabase/config.toml` exposes `public` and `graphql_public`). `usage`
    on the schema and every privilege on the table are revoked from `public`,
    `anon` and `authenticated`. The secret is 32 random bytes from
    `extensions.gen_random_bytes`. Vault was not used: the repo does not use
    `supabase_vault` anywhere, and the table needs nothing Vault adds. The
    helper functions live in `private` too.
15. *plan* **Rotation** is a manual `update private.stay_pass_secret set secret
    = extensions.gen_random_bytes(32)` in SQL. Every existing pass then fails
    as `pass_invalid`, and guests get a new one the next time they open their
    booking. There is no rotation UI.
16. *plan* **Old bare-UUID QR codes are refused** as `pass_invalid` ("This is
    not a valid check-in pass."). They are not accepted as a lookup: that would
    make the signature pointless. Reception finds those guests by typing.
17. *plan* **Manual entry** is one search field above the list: "Booking code,
    name or phone". Typing filters the list with the existing
    `bookingMatchesSearch` and `bookingCode` helpers
    (`lib/features/admin/admin_bookings_screen.dart`). Text that starts with
    `rh1.` is treated as a pass: Enter, or the field's "Open pass" button,
    verifies it. A USB or Bluetooth keyboard-wedge barcode scanner types the
    pass and presses Enter, so it works with no extra code. The list rows
    show `Booking PR3F2A` (the same `bookingCode`) in place of the raw UUID
    prefix, and the guest sees the same code under their QR.
18. *plan* **Current resort check in the app**: a user who belongs to two
    resorts passes the server check for either. The check-in screen refuses
    a verified pass whose `property_id` is not the current resort, with the
    same "different resort" message.
19. *plan* **"Opens that booking's check-in"** is a bottom sheet over the
    check-in list: "Pass verified", guest name and phone, unit, dates, guests,
    booking code, the existing room warning (`roomWarningFor`), and a "Check
    in guest" button for a `confirmed` booking. The label differs from the
    list's "Check In" buttons, so a screen reader or test can tell the sheet's
    button from the rows under it. The button runs the same code as the
    list's button.
20. *plan* **The scanner is its own route**, `/admin/check-in/scan`, a child of
    `/admin/check-in` with the same staff-or-above guard. It pops with the
    first QR text it reads, or with nothing when reception taps "Enter code
    instead". Only the first read leaves the screen.
21. *plan* **My Stay's 64-px QR is too small to scan**, so tapping it opens a
    "Check-in pass" dialog with a 200-px QR and the booking code.
22. *plan* **If a pass cannot be loaded** (offline, or the booking is not
    confirmed yet), the guest's QR box shows a retry button and "Couldn't load
    your pass. Show the booking code at the desk." The booking code is always
    shown under the full-size QR. The pass is cached in memory for the app
    session (it never changes for a booking); keeping it across restarts is
    out of scope.

## Data model — `supabase/migrations/0052_stay_pass.sql`

- `create schema if not exists private`, with every privilege revoked from
  `public`, `anon` and `authenticated`.
- Table `private.stay_pass_secret`:
  - `id boolean primary key default true check (id)`, so there is one row
  - `secret bytea not null check (length(secret) >= 32)`
  - `created_at timestamptz not null default now()`
  - seeded with `extensions.gen_random_bytes(32)` `on conflict (id) do nothing`
- No change to any `public` table, and no new column on `reservations`.

## Functions

Private helpers (no `security definer`, `search_path = pg_catalog, pg_temp`,
execute revoked from `public`). They run with the privileges of the definer
functions that call them:

- `private.b64url_encode(bytea) returns text` and
  `private.b64url_decode(text) returns bytea`: base64url without padding.
- `private.stay_pass_mac(p_body bytea) returns bytea`: the first 16 bytes of
  `extensions.hmac('rh1.' ‖ p_body, secret, 'sha256')`.
- `private.stay_pass_token(p_reservation uuid, p_property uuid, p_expires bigint) returns text`:
  builds a pass. Tests use it to mint expired and forged passes.

Public functions (security definer, `stable`, `search_path = public, pg_temp`,
revoked from `public` and `anon`, granted to `authenticated`, added to the
definer allow-list in `supabase/tests/37_tenancy_isolation_test.sql`):

- `issue_stay_pass(p_reservation uuid) returns text`: as in decision 13, then
  `private.stay_pass_token(id, property_id, extract(epoch from upper(period)))`.
- `verify_stay_pass(p_token text) returns jsonb`: as in decision 11. It
  returns `to_jsonb(reservation)` plus `profiles: {full_name, phone}` and
  `unit_name`, which is the shape `Reservation.fromJson` already reads. The
  resort is derived from the token and checked against the reservation row,
  never taken from the client.
- Error code **P0034** with the message `pass_invalid`, `pass_expired` or
  `pass_other_resort`.

## App

- `lib/core/errors.dart`: `enum PassRejection { invalid, expired, otherResort }`
  and `StayPassRejected` (a `BookingFailure`), mapped from P0034 by code word.
  An unknown code word reads as invalid. Copy:
  - invalid: "This is not a valid check-in pass."
  - expired: "This pass has expired. Ask the guest to reopen their booking,
    or find them in the list."
  - other resort: "This pass is for a booking at a different resort."
- `lib/data/models/verified_pass.dart`: `VerifiedPass {reservation, propertyId,
  unitName}` with `fromJson`, and `looksLikeStayPass(String)`.
- `lib/data/repositories/stay_pass_repository.dart`: the `StayPassSource` seam
  (`issue(reservationId)`, `verify(token)`), `StayPassRepository` over the two
  RPCs (errors through `_guard` / `mapPostgrestError`, and the token trimmed
  before it is sent), `stayPassSourceProvider`, and
  `stayPassProvider` (`FutureProvider.family<String, String>` keyed by
  reservation id, not auto-disposed).
- Guest: `lib/features/stay/stay_pass_qr.dart` holds `StayPassQr` (the QR, the
  retry state, and "Booking code PR3F2A"), `StayPassThumbnail` and
  `showStayPassDialog`. The confirmation screen and booking detail use
  `StayPassQr`; My Stay uses `StayPassThumbnail`. `qr_flutter` stays the QR
  renderer.
- Reception:
  - `lib/features/admin/scan_pass_screen.dart` at `/admin/check-in/scan`.
    `ScanPassScreen` shows the camera with a frame, the hint "Point the
    camera at the guest's check-in QR.", and "Enter code instead". The camera
    view comes from `passScannerProvider`, so tests replace it.
    `CameraPassScanner` wraps `MobileScanner`, reading QR codes only with
    `DetectionSpeed.noDuplicates`. `cameraErrorMessage` gives readable copy
    for a denied permission, a device with no camera, and any other error.
  - `lib/features/admin/pass_check_in_sheet.dart`: `PassCheckInSheet` and
    `passStatusLine`.
  - `reception_checkin_screen.dart`: the search field, the "Scan pass" button,
    the verify flow, the current-resort check, and the list filtered by the
    search.
- Platform: `ios/Runner/Info.plist` gains `NSCameraUsageDescription`. Android
  gets `CAMERA` from the plugin's manifest. On the web the camera needs HTTPS
  or localhost, and mobile_scanner loads its decoder itself (the browser's
  `BarcodeDetector`, or zxing-wasm from a CDN in browsers without it).
- Router: the `scan` child route, and `/admin/check-in/` sub-paths added to
  the staff-or-above list in `redirectFor`.
- `README.md` gets a short "Front-desk check-in passes" section covering how
  passes work, how to rotate the secret, and that the web camera needs HTTPS.

## Rules

- The HMAC secret never leaves Postgres: it is not in the app, not in a
  commit, and not readable through the API.
- `verify_stay_pass` derives the resort from the signed token, requires the
  reservation to belong to that resort, and asserts the caller's role there.
- No existing policy, table or function is changed. Check-in still goes
  through `check_in_booking`.
- The platform admin gets no pass access (no resort membership).

## Testing

- pgTAP `supabase/tests/43_stay_pass_test.sql` (65 assertions):
  - Contract: signatures, return types, definer and `search_path`, grants,
    the private schema locked, the secret seeded.
  - base64url round trip.
  - Issue: well-formed and deterministic; confirmed, checked-in and a past
    confirmed booking; cancelled and checked-out give P0009; another guest's
    booking, an unknown id and a staff caller give P0002; no user gives
    P0008; anon gets 42501; the decoded body carries the ids, the expiry and
    a valid tag; `authenticated` cannot call the private helpers.
  - Verify:
    - Returned shape.
    - Every Staff+ role.
    - Other resort, the guest themself and an outsider all get
      `pass_other_resort`.
    - Tampered, garbage, bare UUID, null, well-formed-but-unsigned and bad
      characters all get `pass_invalid`.
    - Expired (minted and issued) gets `pass_expired`.
    - The resort check comes before expiry.
    - A body swapped to another resort's id is refused both ways.
    - A cancelled booking is returned with its status.
    - Suspended: allowed. Archived: other resort.
    - Rotating the secret invalidates old passes.
    - Anon gets 42501.
- Flutter:
  - `StayPassRejected` mapping.
  - `VerifiedPass.fromJson`, `looksLikeStayPass`, and the `stayPassProvider`
    cache.
  - `StayPassQr`: loaded, error with retry, compact, and the thumbnail
    dialog.
  - The guest screens render the pass.
  - `ScanPassScreen`: the first read pops once, "Enter code instead", the
    camera error copy.
  - The router matrix for `/admin/check-in/scan`.
  - Reception:
    - Search filtering and the empty result.
    - The scan → sheet → Check In flow, and a scan cancelled with no code.
    - A rejected pass.
    - The other-resort refusal.
    - A keyboard-wedge Enter, trimmed.
    - The Open pass button.
    - The status line for a booking already checked in.
    - The room warning in the sheet.
    - The booking code in each row.
- Playwright `e2e/tests/stay-pass.spec.ts`: a pass issued for the front-desk
  fixture guest, pasted into the field, opens the sheet and checks the guest
  in. A tampered pass shows the invalid message. The camera itself is
  verified by hand.

## Out of scope

- Keeping the pass across app restarts (offline wallet).
- A rotation UI, or rotating the secret on a schedule.
- Staff-issued or printed passes.
- Scanning for check-out, food orders or activities.
- Apple/Google Wallet passes.
- Deriving the expiry from the resort's check-out time rather than the stored
  period.
