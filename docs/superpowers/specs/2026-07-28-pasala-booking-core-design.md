# Pasala Resorts — Booking Core (Phase 1) Design

Date: 2026-07-28
Source: `Pasala_Resorts_SRS_v1.docx` (SRS v1.0)
Status: approved for planning

## 1. Context and Decomposition

The SRS describes eight subsystems. Three of them depend on external accounts,
approvals, or paid third-party services that no amount of local work can
substitute:

- **OTA synchronization.** Airbnb, Booking.com, Agoda, MakeMyTrip, and Goibibo
  do not offer open two-way inventory APIs. The realistic options are iCal
  import/export (roughly hourly, no rate or inventory push, so genuine
  double-booking windows remain) or a paid channel manager such as Beds24,
  Hostaway, or Cloudbeds. The SRS success criterion "zero double bookings"
  cannot be met across channels with iCal alone. This is a commercial decision
  and is out of scope here.
- **Payments.** Requires a live gateway account (Razorpay or PhonePe for India)
  and a server-side webhook endpoint.
- **WhatsApp notifications.** Requires Meta Business API approval, which has a
  lead time measured in weeks.

The work is therefore split into five phases, each with its own spec, plan, and
implementation cycle:

1. **Booking core** — this document.
2. Payments, coupons, refund policy engine.
3. Notifications: email, then SMS, then WhatsApp.
4. OTA synchronization.
5. Reporting, dashboard metrics, staff housekeeping operations.

Phases 2 through 5 attach to seams this phase deliberately leaves in place. They
are named in this document only where they constrain a phase 1 decision.

## 2. Phase 1 Scope

In scope:

- Email and password authentication with five roles.
- Property and unit CRUD for admins.
- Rate rules and a server-side quote engine.
- Availability calendar, customer and admin views.
- Booking workflow with a timed hold and a mock payment gateway.
- Admin date blocking: single date, multiple dates, date range, with a reason.
- Booking cancellation.

Out of scope, deferred to the phases named in section 1: real payment gateway,
coupons, refund policy engine, email/SMS/WhatsApp delivery, OTA sync, reports
and exports, housekeeping status updates, dashboard metrics.

## 3. Decisions

| Decision | Choice |
|---|---|
| App shape | One Flutter codebase, role-gated, serving customer, staff, and admin |
| Platforms | Android, iOS, and web from the start |
| Properties | Multi-property from day one |
| Booking granularity | Units within properties; each unit is nightly, slot-based, or both |
| Auth | Email and password in phase 1; phone OTP added in a later phase |
| Staff accounts | Created by a super admin; no self-signup for non-customer roles |
| Pricing | Rate rules table: base, weekend, and priority-ordered date-range overrides |
| Payment in phase 1 | `PaymentGateway` interface with a mock implementation |
| Logic placement | Postgres RPC functions plus RLS; Flutter is a thin client |

### Why logic lives in Postgres

Two alternatives were considered.

**Edge Functions as an API layer** puts business logic in TypeScript, which is
easier to unit test, but adds a second runtime, language, and deploy target —
and race safety still requires the database constraint, so that work happens
either way.

**Logic in Flutter with RLS only** is fastest to a first screen but places the
availability check and the insert in separate round trips, which opens a real
oversell window, and forces every client platform to reimplement pricing. It
contradicts the SRS success criterion directly and was rejected.

The Postgres-centric approach makes overlapping reservations impossible at the
storage layer, so a buggy client, a malicious client, an admin tool, and a
future OTA sync worker are all held to the same rule without re-implementing it.
The cost is that business logic is written in `plpgsql` and tested with pgTAP
and integration tests rather than plain unit tests. That trade is worth taking
for a system whose primary success criterion is the absence of a race
condition.

Edge Functions are reserved for phase 2 and later, where HTTP endpoints and
server-held secrets are genuinely required: payment webhooks and OTA sync.

## 4. Data Model

```
profiles(id -> auth.users, full_name, phone, role)
    role: customer | staff | admin | accountant | super_admin

properties(id, name, slug, description, address, geo, images[], amenities[],
           check_in_time, check_out_time, timezone, is_active)

units(id, property_id, name, capacity_base, capacity_max,
      booking_mode: nightly | slot | both, is_active)

slot_types(id, property_id, code: day | night | full_day, start_time, end_time)

rate_rules(id, unit_id, kind: base | weekend | override,
           slot_type_id NULL, valid_from, valid_to, weekdays[],
           price, extra_guest_price, cleaning_fee, priority)

reservations(id, unit_id, period tstzrange, kind: booking | block | ota,
             status: hold | pending_payment | confirmed | cancelled,
             customer_id NULL, guests, quote jsonb, hold_expires_at,
             block_reason NULL, source)

payments(id, reservation_id, amount, kind: advance | balance,
         status, gateway, gateway_ref, raw jsonb)

audit_log(id, actor_id, entity, entity_id, action, before jsonb, after jsonb, at)
```

### One reservations table

Bookings, admin blocks, and future OTA holds share one table so that one
constraint protects all three:

```sql
EXCLUDE USING gist (unit_id WITH =, period WITH &&)
  WHERE (status <> 'cancelled')
```

Concurrent conflicting inserts resolve deterministically: one transaction
commits, the other receives SQLSTATE `23P01`. This is enforcement, not
convention.

A consequence worth stating explicitly: an admin cannot block a date range that
overlaps a confirmed booking. The insert fails with the same conflict error and
the UI reports which booking is in the way. Overriding a real booking is a
deliberate act — the admin cancels the booking first.

### Time as ranges

Every reservation is a `tstzrange`. A nightly booking is
`[Aug 3 14:00, Aug 5 11:00)`; a slot booking is `[Aug 3 09:00, Aug 3 18:00)`.
Units in `both` mode need no special casing, because mixed nightly and slot
reservations on one unit are just ranges. Half-open ranges also mean an 11:00
checkout and a 14:00 check-in on the same day do not falsely conflict.

Check-in and check-out times come from the unit's property configuration for
nightly bookings, and from `slot_types` for slot bookings. All values are stored
in UTC; the app renders in Asia/Kolkata.

### Pricing

The highest-priority matching `rate_rules` row wins for each night or slot.
Seasonal, holiday, and event pricing from the SRS are all `kind=override` rows
with different date ranges and priorities — one mechanism, no separate code
paths. `base` is the fallback when nothing else matches; a unit without a
`base` rule cannot be booked, and the admin UI surfaces that as a validation
error at unit creation.

`reservations.quote` stores the full per-night breakdown as it was computed at
booking time, so later rate changes never alter an existing booking's price or
its invoice.

### Row Level Security

- **Anonymous:** read active properties, units, and availability. Public browse
  before signup is required by the customer module.
- **Customer:** the above, plus read and write on own reservations only.
- **Staff:** read reservations for assigned properties, limited to arrivals and
  departures views.
- **Accountant:** read-only on reservations and payments.
- **Admin, super admin:** full access. Only a super admin may set a `profiles`
  row's role.

Availability is exposed to anonymous callers through a view that returns busy
ranges without customer identity, so browsing never leaks who booked what.

## 5. RPC Surface and Booking Workflow

Six functions. Flutter performs no writes outside them.

```
search_availability(property_id?, from, to, guests, slot_type?)
get_quote(unit_id, period, guests, slot_type?)
create_hold(unit_id, period, guests, slot_type?)
confirm_booking(reservation_id, payment_ref)
cancel_booking(reservation_id, reason)
release_expired_holds()
```

All are `SECURITY DEFINER` with a pinned `search_path`. Caller identity comes
from `auth.uid()` inside the function; a client-supplied user id is never
trusted. `release_expired_holds` runs every minute under `pg_cron`.

The SRS ten-step workflow maps as follows.

**Steps 1 and 2, date selection and availability.** `search_availability` is
read-only and may be slightly stale; it drives the calendar, not the booking
decision.

**Steps 3 and 4, pricing and coupons.** `get_quote` computes the price server
side and returns a breakdown. The client displays it and never computes money.
Coupon application enters here in phase 2 as an additional argument and an
additional line in the breakdown.

**Step 5, advance payment collection begins.** `create_hold` inserts a row with
`status=hold` and `hold_expires_at = now() + 15 minutes`. This is the point
where oversell is prevented: two customers racing for the last slot produce one
hold and one `UnitUnavailable` error. The function re-computes the quote
internally and rejects the call if the client's displayed total no longer
matches, so a stale price can never be paid.

**Step 6, booking confirmed.** The mock gateway returns a reference;
`confirm_booking` verifies the hold has not expired, writes a `payments` row,
and sets `status=confirmed` in a single transaction. An expired hold yields
`HoldExpired` and the customer restarts with dates prefilled. In phase 2 the
same function is called from a Razorpay webhook Edge Function instead of from
the client; its body does not change.

**Step 7, dates blocked automatically.** No action. The hold row is already the
block, so there is no second write and no way for "a booking exists" and "the
calendar shows busy" to disagree.

**Steps 8 through 10, notifications.** Phase 1 writes an `audit_log` row at
every status transition. Phase 3 attaches real senders to those transitions.
Balance payment reminders belong to phase 2, which owns the advance and balance
split.

**Admin blocking** is a `reservations` insert with `kind=block` and a reason.
Multi-select and range blocking expand to N rows inside one transaction, so a
partial block never lands.

**Cancellation** sets `status=cancelled`, which removes the row from the
exclusion constraint's `WHERE` clause and frees the dates immediately. The row
is retained for audit and for the phase 2 refund engine, which needs the
cancellation timestamp relative to check-in.

**Realtime.** Flutter subscribes to `reservations` filtered by property. An
admin block or a competing booking updates every open calendar without a
refresh and without polling, satisfying the SRS real-time calendar requirement.

## 6. Flutter Application

```
lib/
  core/          env.dart, supabase_client.dart, errors.dart, theme/, router.dart
  data/          models/ (freezed), repositories/
  features/
    auth/        login, signup, role gate
    browse/      property list, property detail with photos and video
    calendar/    availability calendar widget, shared by customer and admin
    booking/     date and slot picker, quote sheet, hold timer, mock pay,
                 confirmation
    account/     my bookings, booking detail, cancel
    admin/       properties CRUD, units CRUD, rate rules, block dates,
                 bookings list
    staff/       arrivals and departures, read-only in phase 1
  main.dart
```

Riverpod for state. `go_router` with a role-aware redirect: unauthenticated
users go to login, and a customer requesting an admin route gets a not-found
page rather than a hidden button. Route guarding is user experience only; RLS
is the enforcement.

A single responsive shell serves all roles — `NavigationBar` on mobile,
`NavigationRail` with wider layouts on web and tablet — so the admin portal is
usable on desktop web without a second application.

Repositories wrap the Supabase SDK. Widgets never import `supabase_flutter`,
which keeps the SDK swappable and makes widget tests trivial to fake.

## 7. Error Handling

Repositories translate Postgres errors into a sealed `BookingFailure`
hierarchy. Widgets never see a `PostgrestException`.

| Cause | SQLSTATE | Dart type | User-facing behaviour |
|---|---|---|---|
| Range overlap | `23P01` | `UnitUnavailable` | Report just-booked, refresh calendar |
| Hold expired | `P0001` | `HoldExpired` | Restart flow, dates prefilled |
| Quote changed | `P0001` | `QuoteStale` | Show new total, ask to accept |
| RLS denial | `42501` | `NotPermitted` | Generic denial, no detail disclosed |
| Transport | — | `NetworkFailure` | Retry affordance |

Application-raised errors carry a distinguishing `ERRCODE` hint so `HoldExpired`
and `QuoteStale` are told apart by code rather than by message text.

## 8. Testing

Test-driven throughout: write the failing test, watch it fail, then implement.

**Database tests (pgTAP), the load-bearing layer.**

- Two concurrent `create_hold` calls on the same range produce exactly one hold.
- Blocking over a confirmed booking is rejected.
- An 11:00 checkout and a 14:00 check-in on the same day do not conflict.
- Cancellation frees the range for immediate rebooking.
- Rate rule priority resolution, including a unit with no base rule.
- Quote totals for nightly, slot, extra guest, and cleaning fee combinations.
- The full RLS matrix: every role against every table, positive and negative.
- Expired holds are released and their dates become bookable.

**Dart unit tests.** Quote breakdown rendering, date and slot arithmetic, error
mapping, repository translation. Repositories faked.

**Widget tests.** Booking happy path, plus the unavailable, expired-hold, and
stale-quote paths.

## 9. Local Development

Supabase runs locally under Docker. Schema lives in `supabase/migrations/` and
is applied with `supabase db reset`, so every developer and every test run
starts from an identical database.

`supabase/seed.sql` provides two properties and roughly five units covering
nightly, slot, and both modes, a full set of rate rules including an override
season, and one account per role plus two customers.

Configuration is passed with `--dart-define` as `SUPABASE_URL` and
`SUPABASE_ANON_KEY`, resolved per platform in `core/env.dart`: `10.0.2.2` for
the Android emulator, `localhost` for iOS simulator and web, and a LAN address
for physical devices. No key is committed; `.env.example` documents the local
anon key only.

Two setup steps precede implementation: install the Supabase CLI
(`brew install supabase/tap/supabase`), and note that this repository was
initialised with `git init` for this spec.

## 10. Success Criteria for Phase 1

- Two concurrent bookings for the same unit and range produce exactly one
  confirmed booking, demonstrated by a passing pgTAP test.
- An admin block appears on an open customer calendar without a refresh.
- A quote is never computed on the client, verified by the absence of pricing
  arithmetic outside `get_quote`.
- Every role's access is covered by a passing positive and negative RLS test.
- The app builds and the booking flow completes on Android, iOS, and web.
