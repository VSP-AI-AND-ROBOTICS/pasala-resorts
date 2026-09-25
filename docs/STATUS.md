# Status — read this first

This is a single honest page. No optimism, no hedging, no "coming soon." If
something is not done, it says so below, plainly.

Last updated: 2026-08-02, after the final whole-branch review's fix wave
(branch `feat/booking-core`). Verified numbers as of this update: pgTAP
352/352 assertions (14 files), `flutter test` 277/277, `flutter analyze`
clean, `flutter build web` and `flutter build apk --debug` both succeed.
Everything below was checked against those runs, not assumed. (The 336/336
and 270/270 figures quoted by an earlier revision of this page were already
one commit stale when written; these are the actual final counts, including
the security/money fixes and the new tests that came with them — see
`.superpowers/sdd/2026-07-30-pasala-phase2/final-fixes-report.md`.)

## What works today

Everything below runs against the local Supabase stack right now, with real
server-side logic (Postgres RPC, RLS, triggers) behind it — not mocked
business logic, only a mocked payment and unsent notifications (see below).

- **Browsing and booking.** Multi-property, multi-unit catalog; server-only
  pricing (base + weekend + seasonal override rate rules); a real-time
  availability calendar; a race-proof booking flow (search → quote → timed
  hold → pay → confirm) with a Postgres exclusion constraint that makes two
  overlapping reservations on the same unit structurally impossible, not
  just application-checked.
- **Coupons.** Percentage/fixed, expiry, usage limits, minimum booking
  value, per-customer restriction, applied inside the server-side quote.
  Redemption counting is proven race-safe under genuine concurrency
  (`dblink`-based test, two simultaneous requests for the last redemption
  slot). Cancelling a couponed booking — whether it was a hold, an expired
  hold, or a fully confirmed booking — always releases the redemption.
- **Refund policy.** Days-before-check-in tiers, stored in `refund_rules`.
  Seeded default: full refund beyond 7 days, 50% within 7 days, 0% within
  48 hours. Every cancellation computes and stores a real refund figure.
  "Admin-configurable" means the RLS grants (staff/accountant read,
  admin-only write) and the table itself, not an in-app screen — there is
  no admin UI for editing tiers; changing them means writing to
  `refund_rules` directly (Supabase Studio or `psql`).
- **Advance/balance split.** A property can require less than 100% up
  front to confirm a hold, via `properties.advance_pct`. The split is
  computed and recorded correctly. Same caveat as the refund policy above:
  no admin UI exists for setting `advance_pct` per property, only a direct
  table edit. Collecting the remaining balance afterward is not built —
  see "What is stubbed" below.
- **Admin dashboard and reports.** Revenue, occupancy, upcoming arrivals,
  cancellations, and active holds — every number computed in SQL, exported
  as CSV. Staff and accountant roles can read these, not just admin,
  because the RLS grants were written that way on purpose. (No coupon-usage
  figure exists anywhere on this page or in `dashboard_summary()` — it
  returns exactly six keys, none of them coupon-related; a coupon-usage
  figure was mentioned in an earlier revision of this page but was never
  actually built.)
- **iCal export and import.** Any unit can be subscribed to from Airbnb or
  Booking.com via a per-unit, revocable export URL (busy dates only, no
  guest identity). This app can also import an OTA's own feed and block
  those dates here, with conflicts surfaced rather than silently dropped.
  Polling is real: a `pg_cron` job runs every 15 minutes, verified
  end-to-end against a live local HTTP server. What has NOT been verified:
  a real Airbnb or Booking.com account actually consuming this app's feed
  or being consumed by it — there is no owner-provided listing to test
  against, so the RFC 5545 shape has only been checked against the spec
  and against this app's own import path, never a live OTA.
- **A real UI**, not a prototype shell: a proper design system, WCAG AA
  contrast, deliberate empty/loading/error states everywhere, and no screen
  that renders a raw server error string.

## What is stubbed, and why

- **Payment is a mock.** `MockGateway` is the only payment path any build
  from this repo can take. No money has ever moved through this app, in any
  environment, at any point in either phase. A `RazorpayGateway` class
  exists (`lib/features/booking/razorpay_gateway.dart`), written against
  Razorpay's real Orders API, but it is inert by construction: there is no
  Razorpay merchant account to authenticate against, and no native checkout
  SDK wired into the app to actually collect a card/UPI/netbanking payment
  even if there were. Calling it today creates a real Razorpay order (if
  given real keys) and then deliberately throws rather than pretending that
  order is a captured charge. Nothing in this repo's build configuration
  ever supplies the keys that would select it.
- **Email and SMS are sent by the `outbox-dispatch` Edge Function** once
  a Resend key (email) and an MSG91 key and DLT templates (SMS) are set.
  Until then every message is recorded as a dry run and nothing is sent.
  The admin Outbox screen shows each channel's mode and when the sender
  last ran. WhatsApp messages are queued only. Setup:
  `docs/email-and-sms-delivery.md`.

## What is needed from the owner to go live

Each item below is a real external dependency this codebase cannot
substitute for. Until it exists, the stated consequence holds — not as a
risk, as the current fact.

1. **A Razorpay or PhonePe merchant account, with KYC completed.**
   Consequence while missing: **no booking can ever be paid for with real
   money.** Every booking made against a deployed build still runs through
   `MockGateway`, which fabricates a success reference and charges nothing.
   Anyone using the app is not paying, and the business is not getting
   paid, regardless of what the UI says.

2. **Supabase hosting (a paid project) and a domain.** Consequence while
   missing: **there is nothing to deploy to.** Everything described in this
   document, including every "works today" item above, only runs against a
   local Supabase instance on a developer's machine. There is no URL a
   guest or the owner can visit. This also blocks HTTPS, which in turn
   blocks removing the development-only cleartext exemptions documented in
   the README — those exemptions must not ship to a real deployment.

3. **A Resend account with a verified sending domain (email) and an MSG91
   account with DLT-registered templates (SMS).** Consequence while
   missing: **the sender runs as a dry run, so no guest receives a
   booking confirmation, payment receipt or cancellation notice.** The
   Outbox screen says so for each channel. Setup takes minutes once the
   accounts exist; see `docs/email-and-sms-delivery.md`.

4. **Meta Business verification for WhatsApp**, on top of item 3. This has
   its own multi-week approval lead time, independent of any other item on
   this list, and should be started early if WhatsApp delivery matters.
   Consequence while missing: **no WhatsApp message is ever delivered**,
   even after email/SMS providers are connected — WhatsApp is a separate
   channel with its own account requirement.

5. **For iCal: pasting this app's export URL into Airbnb (and/or
   Booking.com), and adding their export URL back into this app's OTA
   screen.** This is the one item on this list that is a configuration
   step, not a paid account — but it still has not happened, because there
   is no live Airbnb/Booking.com listing to point at. Consequence while
   missing: **the two-way calendar sync is built and tested against itself,
   but has never synced with a real OTA.** A double-booking between this
   app and an actual Airbnb calendar is possible until someone with a real
   listing performs this step and it is verified working both directions.

## Known limitations (full list)

Phase 1:

- Realtime calendar updates require `REPLICA IDENTITY FULL` on
  `unit_calendar_events`; a 30-second poll plus refresh-on-foreground bound
  the staleness if the realtime socket ever drops a message.
- Some phase-1 UI interactions were verified via widget tests and direct
  RPC/REST calls rather than live browser clicks — the sandbox's browser
  automation cannot reliably focus Flutter-web text fields.
- Booking date/guest/slot controls are not gated on an in-flight request
  flag; rapid multi-tapping can interleave two selection-change calls
  (degrades gracefully, never leaks a hold or double-books).
- A same-priority rate rule for a specific slot type can be outranked by a
  same-priority seasonal override (only reachable if an admin sets two
  rules to equal priority).
- `json_annotation` is pinned to `>=4.9.0 <4.10.0` for a transitive
  dependency conflict.

Phase 2:

- Payment is still a mock gateway (see above).
- Nothing in the notification outbox has ever been sent (see above).
- **The iCal export URL shape has never been verified against a real
  Airbnb or Booking.com account** (see item 5 above).
- No coupon management UI — coupons are created directly in the `coupons`
  table via Supabase Studio or `psql`.
- No refund-policy or advance-payment configuration UI — `refund_rules`
  tiers and `properties.advance_pct` are each editable only by a direct
  table write, the same gap as coupons above.
- The balance portion of an advance/balance booking is never collected;
  only the split itself is computed and stored.
- PDF report export was explicitly deferred; CSV only, with no
  disabled/greyed-out PDF button standing in for it.
- The admin dashboard's occupancy tab was not click-verified live in the
  development sandbox (canvas click flakiness); a widget test covers it
  instead.
- `report_occupancy`'s overlap filter builds its date range in session
  timezone rather than property-local midnight — up to 5.5 hours of skew
  near a day boundary. Numerically invisible for Asia/Kolkata, the only
  timezone any seeded property uses; verified by brute force and kept as a
  known limitation rather than fixed, since fixing it blind for a
  timezone nothing here exercises would be unverifiable.

For the complete task-by-task record behind every item on this page —
every defect found, every ruling made, every deferred item, with evidence —
see `.superpowers/sdd/2026-07-28-pasala-booking-core/progress.md` (phase 1)
and `.superpowers/sdd/2026-07-30-pasala-phase2/progress.md` (phase 2).
