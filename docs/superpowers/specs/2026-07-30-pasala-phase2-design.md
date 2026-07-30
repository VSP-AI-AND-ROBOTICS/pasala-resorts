# Pasala Resorts — Phase 2 Design: Product Surface and Revenue Features

Date: 2026-07-30
Builds on: `2026-07-28-pasala-booking-core-design.md` (phase 1, delivered)
Status: approved by standing autonomy grant; every decision below is reversible

## 1. What This Phase Is

Phase 1 delivered a correct booking engine: multi-property inventory, server-side
pricing, race-proof availability, holds, cancellation, admin management, and a
staff view. It is correct and ugly, and it cannot take money.

This phase makes the product presentable and adds the revenue and operations
features that do not depend on a third-party account. It deliberately stops
short of anything requiring credentials the owner has not yet obtained.

## 2. The Hard Boundary

Four capabilities are gated on accounts only the business owner can create.
They are designed for and stubbed behind interfaces, but they are NOT delivered
and must not be described as delivered:

| Capability | Blocked on | What this phase provides instead |
|---|---|---|
| Real card payment | Razorpay/PhonePe merchant account, KYC | `RazorpayGateway` written against the existing `PaymentGateway` seam, inert without keys; `MockGateway` remains the default |
| Email / SMS / WhatsApp delivery | Provider accounts; Meta business verification | Outbox with rendered messages and delivery state; a `LoggingSender` that records rather than sends |
| Two-way OTA sync | Paid channel manager | iCal import and export, which Airbnb and Booking.com both support without a commercial agreement |
| Production hosting | Supabase billing, domain | Everything runs against local Supabase, unchanged |

A message that was not sent must say so in the UI. A payment that did not
happen must not render as paid. This is the single most important constraint
in this phase: the product may be incomplete, but it may never lie about its
own state.

## 3. Workstreams

Five, in delivery order. Each is independently shippable and independently
testable, so a workstream that runs long can be cut without stranding another.

### A. UI/UX overhaul

The current app is stock Material with an 8-line theme. It works and looks
like a prototype. This workstream makes it look like something a resort would
put its name on, without inventing a new interaction model — the flows tested
in phase 1 stay as they are.

- A real design system: colour roles, type scale, spacing scale, elevation,
  radius, motion durations. One file, consumed everywhere, no ad-hoc values.
- Every screen gets deliberate empty, loading, and error states. Today several
  render a bare spinner or a one-line error.
- Property and unit imagery becomes first-class; the browse screen is currently
  text on cards.
- The booking flow gets a clear step structure: dates → guests → price → pay.
- Responsive layouts verified at phone, tablet and desktop widths, since the
  same codebase serves customers on phones and admins on desktops.
- Accessibility: contrast that passes WCAG AA, semantic labels on interactive
  elements, focus order, and a 48dp minimum touch target.

### B. Reports and admin dashboard

No external dependencies, so this workstream lands complete.

- Dashboard: today's revenue, month revenue, occupancy rate, upcoming arrivals,
  cancellations, coupon usage.
- Reports: revenue, bookings, occupancy, customers, coupons — each with a date
  range and a property filter.
- Export to CSV and PDF.
- Every figure is computed in SQL, consistent with the phase 1 rule that the
  client performs no arithmetic on money.

### C. Coupons, refunds, and the advance/balance split

- Coupons: percentage and fixed, with expiry, usage limit, minimum booking
  value, and per-customer restriction. Applied inside `get_quote` so a coupon
  can never produce a client-computed total.
- Refund policy: admin-configurable rules by days-before-check-in, producing a
  computed refund amount at cancellation time. Conservative default: full
  refund more than 7 days out, 50% within 7 days, none within 48 hours.
- Advance/balance: a booking may be confirmed on an advance payment, with the
  balance recorded as due. `confirm_booking`'s current exact-total check
  becomes a range check against the advance policy.

### D. Notification outbox

- An `outbox` table holding a rendered message, its channel, its recipient, its
  state, and its attempt history.
- Templates for the SRS triggers: booking confirmation, payment success,
  payment due, check-in reminder, cancellation, refund processed.
- A `NotificationSender` interface with a `LoggingSender` implementation.
  Real providers implement the same interface.
- The admin UI shows outbox state honestly, including "not sent — no provider
  configured".

### E. iCal import and export

- Export: a per-unit iCal feed URL that Airbnb and Booking.com can subscribe
  to, listing busy periods without guest identity.
- Import: admin-registered iCal URLs per unit, polled on a schedule, creating
  `kind='ota'` reservations that block the dates.
- Conflicts are surfaced, never silently resolved: if an imported event
  overlaps a confirmed booking, it is recorded as a conflict for an admin to
  handle rather than dropped or force-applied.

## 4. Architectural Continuity

Everything in this phase obeys the phase 1 rules, which held up well:

- Business logic in Postgres behind `SECURITY DEFINER` RPC; RLS on every table;
  an explicit grant beside every policy.
- No pricing arithmetic in Dart. Coupons and refunds are computed server-side.
- Widgets never import the Supabase SDK; repositories are the boundary.
- Errors surface as the sealed `BookingFailure` hierarchy.
- New DB error codes are added to the Dart mapping in the same change.
- pgTAP tests pair `set local role` with JWT claims; absence is asserted with
  out-of-band counts.

## 5. Testing

The phase 1 standard continues: a failing test first, then implementation, then
independent review of the diff.

- Coupon and refund arithmetic is tested in SQL against worked examples,
  because it is money.
- The outbox is tested for state transitions and retry behaviour, not for
  delivery, which cannot happen yet.
- iCal parsing is tested against real exported feeds, including the malformed
  cases feeds actually contain.
- UI work is tested with widget tests for state coverage, and golden tests are
  explicitly NOT used — they would lock in a design still in flux.

## 6. Success Criteria

- A customer can browse, book, and pay through a UI that reads as a finished
  product on a phone and on a desktop.
- An admin can see revenue and occupancy for a chosen period, and export it.
- A coupon reduces a quote server-side, and the reduction survives into the
  stored quote and the invoice.
- Cancelling produces a refund amount computed from policy, recorded against
  the booking.
- A booking confirmation message exists in the outbox, rendered, marked unsent,
  with the reason visible.
- An Airbnb iCal feed subscribed as an import blocks those dates in Pasala, and
  a Pasala booking appears in the exported feed.
- Every phase 1 test still passes, and the suites remain green.
