# Single-Property Onboarding & Occasion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the two placeholder seeded properties with the real Pasala Farm House, add a free-text "occasion" note to the booking flow, and add a branded splash → sign-in/sign-up chooser sequence ahead of login, with a customer landing directly on the one property instead of a list.

**Architecture:** Backend-first ordering (seed data and the `occasion` column/RPC parameter land before anything in Dart depends on them), then a self-contained Dart data-model change (occasion plumbing through `BookingActions`), then two new standalone screens, then the router wiring that connects them, then per-screen UI additions (booking field, confirmation/detail display, browse auto-redirect).

**Tech Stack:** Flutter/Riverpod/go_router (frontend), Postgres/pgTAP via Supabase CLI (backend). Reuses `HeroBackdrop`, `BrandMark`, `PasalaTokens` from the prior farmhouse UI redesign — no new shared widgets, no new pub.dev dependencies.

**Spec:** `docs/superpowers/specs/2026-08-13-single-property-onboarding-design.md`

## Global Constraints

- No new pub.dev dependencies — vanilla Flutter APIs only.
- `create_hold`'s new `p_occasion` parameter must be appended AFTER the existing `p_coupon_code` parameter (last position) so every existing positional call site across the pgTAP suite keeps compiling unmodified.
- `occasion` is metadata only — it must never be read by `get_quote`, never affect pricing, and never appear in any advance/balance calculation.
- Every implementer of the `BookingActions` interface (the real `BookingRepository` and three test fakes: `_FakeBookingActions`, `_ThrowingCancelActions` in `hold_lifecycle_test.dart`, `_FakeCancelActions` in `booking_detail_screen_test.dart`) must be updated together in one task — Dart requires every `implements BookingActions` class to accept any named parameter the interface declares, so this is not divisible across tasks.
- Admin/staff/accountant screens, the payment gateway seam, coupon/refund/advance-balance logic, iCal sync, and the outbox are out of scope — do not touch `lib/features/admin/`, `lib/features/reports/`, `lib/features/staff/`, `lib/features/outbox/`, `lib/features/ota/`, `lib/features/booking/payment_gateway.dart`, `lib/features/booking/razorpay_gateway.dart`.
- Run `flutter analyze` with zero new issues after every Dart task before committing. Run `supabase test db` after every SQL task before committing.
- The three pre-existing `hold_lifecycle_test.dart` failures (a `pay-button` key finder issue, noted in the prior redesign round) are unrelated to this work — do not attempt to fix them as part of this plan, and re-confirm at final verification that they are still the same three, not more.

---

### Task 1: `occasion` column, `create_hold` parameter, and its pgTAP test

**Files:**
- Create: `supabase/migrations/0020_reservation_occasion.sql`
- Create: `supabase/tests/16_reservation_occasion_test.sql`

**Interfaces:**
- Consumes: nothing new.
- Produces: `public.reservations.occasion` (nullable `text` column); `public.create_hold`'s signature gains `p_occasion text default null` as its 8th (last) parameter. Task 2's Dart plumbing calls this RPC with a named `p_occasion` argument.

- [ ] **Step 1: Write the failing test**

```sql
-- supabase/tests/16_reservation_occasion_test.sql

-- create_hold's new optional p_occasion parameter: a free-text note
-- captured at hold time, never read by get_quote or any pricing path,
-- stored as-is on the reservation row. See
-- docs/superpowers/specs/2026-08-13-single-property-onboarding-design.md
-- section 3.2.

begin;
select plan(3);

select has_column('public', 'reservations', 'occasion',
  'reservations gains an occasion column');

insert into auth.users (id, email)
values ('d1111111-1111-1111-1111-111111111111','occasioncust@example.com');

insert into public.properties (id, name, slug)
values ('cccccccc-0000-0000-0000-000000000001',
        'Occasion Test Property','occasion-test');
insert into public.units (id, property_id, name, capacity_base, capacity_max)
values ('dddddddd-0000-0000-0000-000000000001',
        'cccccccc-0000-0000-0000-000000000001','Occasion Test Unit',4,6);
insert into public.rate_rules
  (unit_id, kind, price, extra_guest_price, cleaning_fee, priority)
values ('dddddddd-0000-0000-0000-000000000001','base',10000,1500,1500,0);

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"d1111111-1111-1111-1111-111111111111","role":"authenticated"}';

-- occasion is stored verbatim when supplied
select is(
  (select occasion from public.create_hold(
     'dddddddd-0000-0000-0000-000000000001',
     '2026-08-03','2026-08-04', 4, null, null, null,
     'Anniversary weekend')),
  'Anniversary weekend',
  'create_hold stores the supplied occasion');

-- omitting occasion defaults to null, matching every existing caller that
-- doesn't know this parameter exists
select is(
  (select occasion from public.create_hold(
     'dddddddd-0000-0000-0000-000000000001',
     '2026-09-03','2026-09-04', 4)),
  null,
  'create_hold defaults occasion to null when omitted');

reset role;

select * from finish();
rollback;
```

- [ ] **Step 2: Run test to verify it fails**

Run: `supabase test db`
Expected: FAIL — `has_column` reports `occasion` missing, and both `create_hold` calls with 8 arguments fail with a Postgres "function does not exist" error (no 8-argument overload of `create_hold` yet).

- [ ] **Step 3: Write the implementation**

```sql
-- supabase/migrations/0020_reservation_occasion.sql

-- A free-text note captured at hold time (create_hold), purely
-- informational -- never read by get_quote or any pricing path. See
-- docs/superpowers/specs/2026-08-13-single-property-onboarding-design.md
-- section 3.2.

alter table public.reservations add column occasion text;

create or replace function public.create_hold(
  p_unit_id        uuid,
  p_from           date,
  p_to             date,
  p_guests         int,
  p_slot_type_id   uuid default null,
  p_expected_total numeric default null,
  p_coupon_code    text default null,
  p_occasion       text default null
) returns public.reservations
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid       uuid := auth.uid();
  v_mode      public.booking_mode;
  v_period    tstzrange;
  v_quote     jsonb;
  v_row       public.reservations;
  v_coupon_id uuid;
  v_discount  numeric(12,2);
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode = 'P0008';
  end if;

  -- I3: `booking_mode` was enforced nowhere -- a slot-only unit could be
  -- held for three nights, and a nightly-only unit could be held with a
  -- slot (occupying just 09:00-18:00 instead of 14:00->11:00, leaving the
  -- very same physical room bookable overnight -- a real double
  -- -allocation `reservations_no_overlap` cannot see, since the two
  -- periods never overlap). Enforced here in SQL, not just in the client,
  -- so a buggy or malicious caller invoking this RPC directly is held to
  -- the same rule. If the unit doesn't exist `v_mode` stays NULL, matching
  -- neither branch below, so `build_period`'s own "unit not found" raise
  -- still fires -- this doesn't duplicate that check.
  select booking_mode into v_mode from public.units where id = p_unit_id;
  if v_mode = 'nightly' and p_slot_type_id is not null then
    raise exception 'this unit does not support slot bookings'
      using errcode = 'P0003';
  end if;
  if v_mode = 'slot' and p_slot_type_id is null then
    raise exception 'this unit requires a slot type' using errcode = 'P0003';
  end if;

  v_period := public.build_period(p_unit_id, p_from, p_to, p_slot_type_id);
  v_quote  := public.get_quote(p_unit_id, v_period, p_guests, p_slot_type_id,
                                p_coupon_code);

  -- The client displayed a total; refuse to hold at a price it never saw.
  if p_expected_total is not null
     and (v_quote ->> 'total')::numeric <> p_expected_total then
    raise exception 'price changed to %', (v_quote ->> 'total')
      using errcode = 'P0007';
  end if;

  insert into public.reservations
    (unit_id, slot_type_id, period, kind, status, customer_id, guests,
     quote, hold_expires_at, created_by, occasion)
  values
    (p_unit_id, p_slot_type_id, v_period, 'booking', 'hold', v_uid, p_guests,
     v_quote, now() + interval '15 minutes', v_uid, p_occasion)
  returning * into v_row;

  if p_coupon_code is not null then
    -- Race-safe redemption: the max_redemptions check and the increment
    -- are the SAME statement. Two concurrent holds racing for the last
    -- slot both run this UPDATE; Postgres's row-level lock on the coupon
    -- row serializes them -- whichever commits first moves
    -- redeemed_count to the limit, and the second's WHERE clause is
    -- re-evaluated against that committed value once its lock is granted,
    -- so it affects zero rows and this raises P0012. There is no separate
    -- SELECT anywhere in this path for a second transaction to read stale
    -- data from -- that gap is exactly what a naive
    -- "SELECT count(*) < max_redemptions, THEN INSERT" implementation
    -- would leave open.
    update public.coupons
       set redeemed_count = redeemed_count + 1
     where code = p_coupon_code
       and is_active
       and (max_redemptions is null or redeemed_count < max_redemptions)
    returning id into v_coupon_id;

    if v_coupon_id is null then
      raise exception 'coupon % has reached its usage limit', p_coupon_code
        using errcode = 'P0012';
    end if;

    v_discount := coalesce(((v_quote -> 'coupon') ->> 'discount')::numeric, 0);

    insert into public.coupon_redemptions
      (coupon_id, reservation_id, customer_id, amount)
    values (v_coupon_id, v_row.id, v_uid, v_discount);
  end if;

  return v_row;
end;
$$;

grant execute on function public.create_hold to authenticated;
```

- [ ] **Step 4: Run test to verify it passes**

Run: `supabase db reset && supabase test db`
Expected: PASS — all 3 assertions in `16_reservation_occasion_test.sql`, and the full suite (every other test file) still passes, since `p_occasion` is appended last with a default and every existing call keeps its original argument count.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/0020_reservation_occasion.sql supabase/tests/16_reservation_occasion_test.sql
git commit -m "feat(booking): add a free-text occasion note to create_hold"
```

---

### Task 2: Replace seed data with the real Pasala Farm House property

**Files:**
- Modify: `supabase/seed.sql:51-125`

**Interfaces:**
- Consumes: nothing new (this only changes seed data, not schema).
- Produces: one seeded property (`Pasala Farm House`) with six units (Dallas, Las Vegas, New York, Boston, Detroit, Miami). Task 4 (Browse single-property redirect) and Task 11's manual walkthrough both rely on there being exactly one active property after `supabase db reset`.

- [ ] **Step 1: Write the failing check**

This task has no Dart/pgTAP test of its own — seed data has no automated
assertion in this codebase (confirmed: no existing test queries `seed.sql`
data by name). The "failing" state to verify first is simply: query the
current seed data and see the placeholder rows.

Run: `supabase db reset && psql "$(supabase status -o env | grep DB_URL | cut -d= -f2 | tr -d '\"')" -c "select name from public.properties order by name;"`
Expected output before this task: `Pasala Hilltop` and `Pasala Riverside`
(the two rows this task removes).

- [ ] **Step 2: Replace the seed data**

```sql
-- supabase/seed.sql:51-125 — replace the properties/slot_types/units/
-- rate_rules/reservations block with:

insert into public.properties
  (id, name, slug, description, address, check_in_time, check_out_time, amenities)
values
  ('a0000000-0000-0000-0000-000000000001','Pasala Farm House','pasala-farm-house',
   'A boutique farmhouse resort with a private pool and themed cottages.',
   'Shamirpet, Hyderabad',
   '14:00','11:00', array['Pool','Wi-Fi','Barbecue','Parking','Garden']);

insert into public.slot_types (id, property_id, code, start_time, end_time)
values
  ('50000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001',
   'day','09:00','18:00'),
  ('50000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000001',
   'night','18:00','09:00');

insert into public.units
  (id, property_id, name, capacity_base, capacity_max, booking_mode)
values
  ('b0000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001',
   'Dallas', 2, 4, 'nightly'),
  ('b0000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000001',
   'Las Vegas', 2, 4, 'nightly'),
  ('b0000000-0000-0000-0000-000000000003','a0000000-0000-0000-0000-000000000001',
   'New York', 2, 4, 'nightly'),
  ('b0000000-0000-0000-0000-000000000004','a0000000-0000-0000-0000-000000000001',
   'Boston', 2, 4, 'nightly'),
  ('b0000000-0000-0000-0000-000000000005','a0000000-0000-0000-0000-000000000001',
   'Detroit', 2, 4, 'nightly'),
  ('b0000000-0000-0000-0000-000000000006','a0000000-0000-0000-0000-000000000001',
   'Miami', 20, 40, 'slot');

-- base rates for every unit
insert into public.rate_rules
  (unit_id, kind, label, price, extra_guest_price, cleaning_fee, priority)
values
  ('b0000000-0000-0000-0000-000000000001','base','Weekday', 6000, 800, 800,0),
  ('b0000000-0000-0000-0000-000000000002','base','Weekday', 6000, 800, 800,0),
  ('b0000000-0000-0000-0000-000000000003','base','Weekday', 6500, 900, 800,0),
  ('b0000000-0000-0000-0000-000000000004','base','Weekday', 6000, 800, 800,0),
  ('b0000000-0000-0000-0000-000000000005','base','Weekday', 6000, 800, 800,0),
  ('b0000000-0000-0000-0000-000000000006','base','Weekday',12000, 400,1500,0);

-- weekend uplift, Saturday and Sunday (ISO dow 6 and 7)
insert into public.rate_rules
  (unit_id, kind, label, price, extra_guest_price, cleaning_fee, priority, weekdays)
select unit_id, 'weekend', 'Weekend', price * 1.4, extra_guest_price,
       cleaning_fee, 10, array[6,7]
from public.rate_rules where kind = 'base';

-- Diwali season override, outranks weekend
insert into public.rate_rules
  (unit_id, kind, label, price, extra_guest_price, cleaning_fee, priority,
   valid_from, valid_to)
select unit_id, 'override', 'Diwali season', price * 1.8, extra_guest_price,
       cleaning_fee, 50, date '2026-11-06', date '2026-11-12'
from public.rate_rules where kind = 'base';

-- one confirmed booking and one admin block, so the calendar is not empty
insert into public.reservations
  (unit_id, period, kind, status, customer_id, guests, source)
values
  ('b0000000-0000-0000-0000-000000000001',
   public.build_period('b0000000-0000-0000-0000-000000000001',
                       current_date + 7, current_date + 9),
   'booking','confirmed','10000000-0000-0000-0000-000000000005',2,'app');

insert into public.reservations
  (unit_id, period, kind, status, block_reason, source)
values
  ('b0000000-0000-0000-0000-000000000002',
   public.build_period('b0000000-0000-0000-0000-000000000002',
                       current_date + 14, current_date + 16),
   'block','confirmed','Deep cleaning','admin');
```

Note: this drops the `Whole Villa`/`Pool Deck`/`Main House`/`Lawn` units
and their `'both'`-mode unit (`Whole Villa`), so nothing in the seed data
exercises `booking_mode = 'both'` or a unit with `capacity_base = 10`
anymore — this is fine, since `booking_mode`'s branches are already
covered by `06_booking_flow_test.sql`'s own fixtures, not by seed data.

- [ ] **Step 3: Run the check again**

Run: `supabase db reset && psql "$(supabase status -o env | grep DB_URL | cut -d= -f2 | tr -d '\"')" -c "select name from public.properties order by name;"`
Expected: exactly one row, `Pasala Farm House`.

Also run: `supabase test db`
Expected: every test file EXCEPT `10_reports_test.sql` still passes (Task 3
fixes that one — it is expected to fail until then, since it currently
references the now-removed Riverside/Hilltop UUIDs).

- [ ] **Step 4: Commit**

```bash
git add supabase/seed.sql
git commit -m "feat: replace placeholder seed properties with Pasala Farm House"
```

---

### Task 3: Rewrite `10_reports_test.sql` with self-contained fixtures

**Files:**
- Modify: `supabase/tests/10_reports_test.sql`

**Interfaces:**
- Consumes: nothing from Task 2 — this task explicitly stops depending on
  the real seeded properties.
- Produces: nothing consumed by later tasks.

- [ ] **Step 1: Confirm the current failure**

Run: `supabase test db`
Expected (after Task 2, before this task): `10_reports_test.sql` fails —
it inserts fixture units under `'a0000000-0000-0000-0000-000000000001'`
and `'a0000000-0000-0000-0000-000000000002'`, and the second of those
property IDs no longer exists after Task 2 removed `Pasala Hilltop`.

- [ ] **Step 2: Read the current file and replace its property references**

Read `supabase/tests/10_reports_test.sql` in full first — this step
requires seeing its exact current fixture-insertion block and comments
before editing, since the file's own header comment ("Fixture units under
the real seeded properties (Riverside/Hilltop)") and every reference to
those two UUIDs must be replaced together, consistently, or the file's
assertions (which compare revenue scoped to one property against the
other) will silently compare the wrong things.

Replace the file's own two hardcoded seeded-property UUIDs
(`'a0000000-0000-0000-0000-000000000001'`, previously Riverside, and
`'a0000000-0000-0000-0000-000000000002'`, previously Hilltop) with two
new properties this test inserts itself at the top of its fixture section,
before any unit/reservation inserts that reference them:

```sql
-- This test no longer depends on the app's real seeded properties (see
-- docs/superpowers/specs/2026-08-13-single-property-onboarding-design.md
-- section 3.3) -- it proves report_revenue/report_occupancy don't leak
-- one property's figures into another's using two properties it owns
-- entirely, so it stays correct regardless of what the real seed data
-- looks like.
insert into public.properties (id, name, slug)
values
  ('e0000000-0000-0000-0000-000000000001','Report Test Property A','report-test-a'),
  ('e0000000-0000-0000-0000-000000000002','Report Test Property B','report-test-b');
```

Then update every remaining reference in the file: replace
`'a0000000-0000-0000-0000-000000000001'` with
`'e0000000-0000-0000-0000-000000000001'` and
`'a0000000-0000-0000-0000-000000000002'` with
`'e0000000-0000-0000-0000-000000000002'` throughout the rest of the file
(the unit inserts, the reservation inserts, and any comment that names
"Riverside"/"Hilltop" — rename those comments to "Property A"/"Property B"
so they describe what the test actually does now, not stale product
names). Every other assertion, amount, and date in the file is unchanged —
only the property identity fixtures move from "borrowed from seed data" to
"owned by this test".

- [ ] **Step 3: Run test to verify it passes**

Run: `supabase db reset && supabase test db`
Expected: PASS — every test file, including `10_reports_test.sql` with its
own fixtures, and every file from Task 1/2.

- [ ] **Step 4: Commit**

```bash
git add supabase/tests/10_reports_test.sql
git commit -m "test(reports): decouple property-scoping test from real seed data"
```

---

### Task 4: Thread `occasion` through `BookingActions`, `BookingRepository`, and `Reservation`

**Files:**
- Modify: `lib/data/models/reservation.dart`
- Modify: `lib/data/repositories/booking_repository.dart`
- Modify: `test/features/booking/hold_lifecycle_test.dart`
- Modify: `test/features/account/booking_detail_screen_test.dart`

**Interfaces:**
- Consumes: `p_occasion` RPC parameter (Task 1).
- Produces: `Reservation.occasion` (`String?`, new field). `BookingActions.createHold`'s signature gains `String? occasion` (optional, no `required`). Task 8 (booking screen) calls `createHold(..., occasion: ...)`; Tasks 9/10 (confirmation/detail screens) read `reservation.occasion`.

- [ ] **Step 1: Write the failing test**

Add this test to `test/features/booking/hold_lifecycle_test.dart`, inside
`main()` alongside the existing tests (do not remove or alter any existing
test in this file):

```dart
  testWidgets('createHold passes the occasion through to the fake', (
    tester,
  ) async {
    final actions = _FakeBookingActions()
      ..quoteToReturn = _quote();
    final reservation = await actions.createHold(
      unitId: 'u1',
      from: DateTime.utc(2026, 8, 3),
      to: DateTime.utc(2026, 8, 5),
      guests: 2,
      occasion: 'Birthday celebration',
    );
    expect(reservation.occasion, 'Birthday celebration');
  });
```

(This references `_quote()` and `_FakeBookingActions`, both already
defined in this file — check the top of `hold_lifecycle_test.dart` for
the exact existing helper name if it differs from `_quote()`.)

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/booking/hold_lifecycle_test.dart --plain-name "createHold passes the occasion"`
Expected: FAIL — `Error: No named parameter with the name 'occasion'` (the
`createHold` interface and fake don't accept it yet).

- [ ] **Step 3: Write the implementation**

```dart
// lib/data/models/reservation.dart — add to the Reservation class:
// (constructor gains `this.occasion,`, fields gain `final String? occasion;`,
//  fromJson gains `occasion: json['occasion'] as String?,`)
```

Full replacement of `lib/data/models/reservation.dart`:

```dart
import 'quote.dart';

enum ReservationKind { booking, block, ota }

enum ReservationStatus { hold, pendingPayment, confirmed, cancelled }

ReservationStatus _status(String raw) => switch (raw) {
      'hold' => ReservationStatus.hold,
      'pending_payment' => ReservationStatus.pendingPayment,
      'confirmed' => ReservationStatus.confirmed,
      'cancelled' => ReservationStatus.cancelled,
      _ => throw ArgumentError('unknown status $raw'),
    };

/// Parses a Postgres tstzrange literal: ["2026-08-03 08:30:00+00","...")
({DateTime start, DateTime end}) parsePeriod(String raw) {
  final parts = raw
      .substring(1, raw.length - 1)
      .split(',')
      .map((s) => s.replaceAll('"', '').trim())
      .toList();
  return (
    start: DateTime.parse(parts[0].replaceFirst(' ', 'T')).toUtc(),
    end: DateTime.parse(parts[1].replaceFirst(' ', 'T')).toUtc(),
  );
}

class Reservation {
  const Reservation({
    required this.id,
    required this.unitId,
    required this.start,
    required this.end,
    required this.kind,
    required this.status,
    this.customerId,
    this.guests,
    this.quote,
    this.holdExpiresAt,
    this.blockReason,
    this.occasion,
  });

  final String id;
  final String unitId;
  final DateTime start;
  final DateTime end;
  final ReservationKind kind;
  final ReservationStatus status;
  final String? customerId;
  final int? guests;
  final Quote? quote;
  final DateTime? holdExpiresAt;
  final String? blockReason;

  /// A free-text note captured at hold time (e.g. "Anniversary weekend").
  /// Never read by pricing -- purely informational, shown on the
  /// confirmation and booking-detail screens when non-empty.
  final String? occasion;

  bool get isHold => status == ReservationStatus.hold;

  Duration? get holdRemaining {
    final expiry = holdExpiresAt;
    if (expiry == null) return null;
    final left = expiry.difference(DateTime.now().toUtc());
    return left.isNegative ? Duration.zero : left;
  }

  factory Reservation.fromJson(Map<String, dynamic> json) {
    final period = parsePeriod(json['period'] as String);
    return Reservation(
      id: json['id'] as String,
      unitId: json['unit_id'] as String,
      start: period.start,
      end: period.end,
      kind: ReservationKind.values.byName(json['kind'] as String),
      status: _status(json['status'] as String),
      customerId: json['customer_id'] as String?,
      guests: (json['guests'] as num?)?.toInt(),
      quote: json['quote'] == null
          ? null
          : Quote.fromJson(json['quote'] as Map<String, dynamic>),
      holdExpiresAt: json['hold_expires_at'] == null
          ? null
          : DateTime.parse(json['hold_expires_at'] as String).toUtc(),
      blockReason: json['block_reason'] as String?,
      occasion: json['occasion'] as String?,
    );
  }

  /// Built from `unit_calendar_events`, the identity-free occupancy mirror.
  /// customerId, guests and quote are intentionally absent -- this row exists
  /// so any viewer can see THAT a date is taken, never by whom.
  factory Reservation.fromCalendarEvent(Map<String, dynamic> json) {
    final period = parsePeriod(json['period'] as String);
    return Reservation(
      id: json['reservation_id'] as String,
      unitId: json['unit_id'] as String,
      start: period.start,
      end: period.end,
      kind: ReservationKind.values.byName(json['kind'] as String),
      status: _status(json['status'] as String),
    );
  }
}
```

Modify `lib/data/repositories/booking_repository.dart`'s `BookingActions`
abstract interface — `createHold`'s signature:

```dart
  Future<Reservation> createHold({
    required String unitId,
    required DateTime from,
    required DateTime to,
    required int guests,
    String? slotTypeId,
    num? expectedTotal,
    String? couponCode,
    String? occasion,
  });
```

And its `BookingRepository` implementation:

```dart
  @override
  Future<Reservation> createHold({
    required String unitId,
    required DateTime from,
    required DateTime to,
    required int guests,
    String? slotTypeId,
    num? expectedTotal,
    String? couponCode,
    String? occasion,
  }) =>
      _guard(() async {
        final row = await _db.rpc('create_hold', params: {
          'p_unit_id': unitId,
          'p_from': _d(from),
          'p_to': _d(to),
          'p_guests': guests,
          'p_slot_type_id': slotTypeId,
          'p_expected_total': expectedTotal,
          // The correctness trap: create_hold re-quotes internally to price
          // the hold. Omitting the coupon code here would make that
          // internal re-quote come back HIGHER than expectedTotal (which
          // the client computed WITH the discount applied), so every
          // couponed booking would fail with P0007 -- exactly backwards.
          'p_coupon_code': couponCode,
          'p_occasion': occasion,
        });
        return Reservation.fromJson(row as Map<String, dynamic>);
      });
```

Update the three test fakes so the project still compiles. In
`test/features/booking/hold_lifecycle_test.dart`, `_FakeBookingActions`:

```dart
  @override
  Future<Reservation> createHold({
    required String unitId,
    required DateTime from,
    required DateTime to,
    required int guests,
    String? slotTypeId,
    num? expectedTotal,
    String? couponCode,
    String? occasion,
  }) async {
    calls.add('createHold');
    couponCodesSeen.add(couponCode);
    for (final r in _live.values) {
      if (r.unitId == unitId && _overlaps(r, from, to)) {
        // The real 23P01 -> UnitUnavailable path. Reached only if a bug
        // let two live holds/bookings collide over the same range.
        throw const UnitUnavailable();
      }
    }
    final id = 'hold-${_nextId++}';
    final reservation = Reservation(
      id: id,
      unitId: unitId,
      start: from.toUtc(),
      end: to.toUtc(),
      kind: ReservationKind.booking,
      status: ReservationStatus.hold,
      holdExpiresAt: DateTime.now().toUtc().add(const Duration(minutes: 15)),
      occasion: occasion,
    );
    _live[id] = reservation;
    return reservation;
  }
```

(Only the parameter list and the `occasion: occasion` line in the
constructed `Reservation` are new — everything else in this method is
unchanged from what's already there.)

In the same file, `_ThrowingCancelActions`:

```dart
  @override
  Future<Reservation> createHold({
    required String unitId,
    required DateTime from,
    required DateTime to,
    required int guests,
    String? slotTypeId,
    num? expectedTotal,
    String? couponCode,
    String? occasion,
  }) =>
      throw UnimplementedError();
```

In `test/features/account/booking_detail_screen_test.dart`,
`_FakeCancelActions`:

```dart
  @override
  Future<Reservation> createHold({
    required String unitId,
    required DateTime from,
    required DateTime to,
    required int guests,
    String? slotTypeId,
    num? expectedTotal,
    String? couponCode,
    String? occasion,
  }) =>
      throw UnimplementedError();
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/booking/hold_lifecycle_test.dart test/features/account/booking_detail_screen_test.dart`
Expected: PASS — every test in both files, including the three
pre-existing `hold_lifecycle_test.dart` failures noted in Global
Constraints, which remain (still 3, not more, not fewer) since this task
doesn't touch the booking/payment state machine.

- [ ] **Step 5: Commit**

```bash
git add lib/data/models/reservation.dart lib/data/repositories/booking_repository.dart test/features/booking/hold_lifecycle_test.dart test/features/account/booking_detail_screen_test.dart
git commit -m "feat(booking): thread occasion through Reservation and BookingActions"
```

---

### Task 5: `SplashScreen` — branded first screen

**Files:**
- Create: `lib/features/splash/splash_screen.dart`
- Test: `test/features/splash/splash_screen_test.dart`

**Interfaces:**
- Consumes: `HeroBackdrop` (`imageAsset`, `child`), `BrandMark`/`BrandMarkSize`, `AppAssets.entranceGateNight`, `PasalaTokens.motionBase`.
- Produces: `SplashScreen` (no constructor parameters). Task 7 (router integration) wires this at the `/splash` route and navigates to it as `initialLocation`.

- [ ] **Step 1: Write the failing test**

```dart
// test/features/splash/splash_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pasala/core/widgets/brand_mark.dart';
import 'package:pasala/features/splash/splash_screen.dart';

void main() {
  Widget appFor() {
    final router = GoRouter(
      initialLocation: '/splash',
      routes: [
        GoRoute(path: '/splash', builder: (_, _) => const SplashScreen()),
        GoRoute(path: '/welcome', builder: (_, _) => const Text('Welcome')),
      ],
    );
    return MaterialApp.router(routerConfig: router);
  }

  testWidgets('shows the brand mark over the background', (tester) async {
    await tester.pumpWidget(appFor());

    expect(find.byType(BrandMark), findsOneWidget);
  });

  testWidgets('navigates to /welcome after its delay', (tester) async {
    await tester.pumpWidget(appFor());

    expect(find.text('Welcome'), findsNothing);

    await tester.pumpAndSettle(const Duration(seconds: 3));

    expect(find.text('Welcome'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/splash/splash_screen_test.dart`
Expected: FAIL — `Error: Couldn't resolve the package 'pasala/features/splash/splash_screen.dart'`.

- [ ] **Step 3: Write the implementation**

```dart
// lib/features/splash/splash_screen.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_assets.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/brand_mark.dart';
import '../../core/widgets/hero_backdrop.dart';

/// The app's very first screen. Reuses the entrance-gate night photo
/// (bundled but unused by the prior redesign round) so it reads as a
/// distinct moment from login/signup's own hero backdrop. Auto-advances to
/// `/welcome` after a brief delay -- a signed-out user never has to tap
/// anything to get past it, and a signed-in user never even sees it, since
/// `redirectFor` (see `core/router.dart`) sends them straight to their
/// landing path before this widget builds.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  static const _autoAdvanceDelay = Duration(milliseconds: 1500);

  @override
  void initState() {
    super.initState();
    Future.delayed(_autoAdvanceDelay, () {
      if (mounted) context.go('/welcome');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: HeroBackdrop(
        imageAsset: AppAssets.entranceGateNight,
        scrimOpacity: 0.6,
        child: const Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: PasalaTokens.motionBase,
            curve: Curves.easeOut,
            builder: _fadeIn,
            child: BrandMark(size: BrandMarkSize.splash, showWordmark: false),
          ),
        ),
      ),
    );
  }

  static Widget _fadeIn(BuildContext context, double value, Widget? child) =>
      Opacity(opacity: value, child: child);
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/splash/splash_screen_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/features/splash/splash_screen.dart test/features/splash/splash_screen_test.dart
git commit -m "feat: add branded splash screen"
```

---

### Task 6: `WelcomeScreen` — Sign In / Sign Up chooser

**Files:**
- Create: `lib/features/auth/welcome_screen.dart`
- Test: `test/features/auth/welcome_screen_test.dart`

**Interfaces:**
- Consumes: `HeroBackdrop`, `BrandMark`/`BrandMarkSize`, `AppAssets.entranceGateNight`.
- Produces: `WelcomeScreen` (no constructor parameters). Task 7 wires this at `/welcome`.

- [ ] **Step 1: Write the failing test**

```dart
// test/features/auth/welcome_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pasala/features/auth/welcome_screen.dart';

void main() {
  Widget appFor() {
    final router = GoRouter(
      initialLocation: '/welcome',
      routes: [
        GoRoute(path: '/welcome', builder: (_, _) => const WelcomeScreen()),
        GoRoute(path: '/login', builder: (_, _) => const Text('Login screen')),
        GoRoute(path: '/signup', builder: (_, _) => const Text('Signup screen')),
      ],
    );
    return MaterialApp.router(routerConfig: router);
  }

  testWidgets('Sign In navigates to /login', (tester) async {
    await tester.pumpWidget(appFor());

    await tester.tap(find.widgetWithText(FilledButton, 'Sign In'));
    await tester.pumpAndSettle();

    expect(find.text('Login screen'), findsOneWidget);
  });

  testWidgets('Sign Up navigates to /signup', (tester) async {
    await tester.pumpWidget(appFor());

    await tester.tap(find.widgetWithText(OutlinedButton, 'Sign Up'));
    await tester.pumpAndSettle();

    expect(find.text('Signup screen'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/auth/welcome_screen_test.dart`
Expected: FAIL — `Error: Couldn't resolve the package 'pasala/features/auth/welcome_screen.dart'`.

- [ ] **Step 3: Write the implementation**

```dart
// lib/features/auth/welcome_screen.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_assets.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/brand_mark.dart';
import '../../core/widgets/hero_backdrop.dart';

/// The Sign In / Sign Up chooser shown after the splash screen. Both
/// existing forms (`LoginScreen`/`SignupScreen`) are reached from here, and
/// both are still independently reachable by deep link -- this screen adds
/// a front door, it doesn't become the only way in.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: HeroBackdrop(
        imageAsset: AppAssets.entranceGateNight,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(Spacing.lg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const BrandMark(
                    size: BrandMarkSize.splash,
                    showWordmark: false,
                  ),
                  const SizedBox(height: Spacing.md),
                  Text(
                    'Pasala Resorts',
                    style: textTheme.headlineMedium
                        ?.copyWith(color: Colors.white),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: Spacing.xs),
                  Text(
                    'A boutique farmhouse getaway',
                    style: textTheme.bodyLarge?.copyWith(color: Colors.white70),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: Spacing.xl),
                  FilledButton(
                    onPressed: () => context.go('/login'),
                    child: const Text('Sign In'),
                  ),
                  const SizedBox(height: Spacing.sm),
                  OutlinedButton(
                    onPressed: () => context.go('/signup'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white),
                    ),
                    child: const Text('Sign Up'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/auth/welcome_screen_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/features/auth/welcome_screen.dart test/features/auth/welcome_screen_test.dart
git commit -m "feat: add Sign In / Sign Up chooser screen"
```

---

### Task 7: Router integration — `/splash`, `/welcome`, and the broadened pre-auth check

**Files:**
- Modify: `lib/core/router.dart`
- Modify: `test/core/router_test.dart`

**Interfaces:**
- Consumes: `SplashScreen` (Task 5), `WelcomeScreen` (Task 6).
- Produces: `redirectFor`'s third named parameter is renamed from `loggingIn` to `onPreAuthScreen` (broadened meaning: "this path is one of the four pre-authentication screens, not just login/signup"). Any future caller of `redirectFor` must use the new name.

- [ ] **Step 1: Write the failing test**

Add these tests to `test/core/router_test.dart`. First, update the file's
existing `_to` helper and the two explicit `loggingIn:` call sites to use
the new parameter name (this is the "red" step — the file won't compile
until Step 3 renames the actual parameter):

```dart
// test/core/router_test.dart — replace:
String? _to(AppUser? user, String path) =>
    redirectFor(user: user, path: path, loggingIn: false);
// with:
String? _to(AppUser? user, String path) =>
    redirectFor(user: user, path: path, onPreAuthScreen: false);
```

```dart
// replace:
    test('is left on /login and /signup', () {
      expect(redirectFor(user: null, path: '/login', loggingIn: true), null);
      expect(redirectFor(user: null, path: '/signup', loggingIn: true), null);
    });
// with:
    test('is left on /splash, /welcome, /login, and /signup', () {
      for (final path in ['/splash', '/welcome', '/login', '/signup']) {
        expect(
          redirectFor(user: null, path: path, onPreAuthScreen: true),
          null,
          reason: path,
        );
      }
    });
```

```dart
// replace:
  test('a signed-in customer hitting /login or /signup is sent home', () {
    expect(redirectFor(user: _customer, path: '/login', loggingIn: true), '/');
  });
// with:
  test(
    'a signed-in customer hitting any pre-auth screen is sent home',
    () {
      for (final path in ['/splash', '/welcome', '/login', '/signup']) {
        expect(
          redirectFor(user: _customer, path: path, onPreAuthScreen: true),
          '/',
          reason: path,
        );
      }
    },
  );
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/router_test.dart`
Expected: FAIL — `Error: No named parameter with the name 'onPreAuthScreen'` (compile error, since `redirectFor` still declares `loggingIn`).

- [ ] **Step 3: Write the implementation**

```dart
// lib/core/router.dart:44-71 — replace redirectFor's signature and its
// first two branches:
String? redirectFor({
  required AppUser? user,
  required String path,
  required bool onPreAuthScreen,
}) {
  if (user == null) return onPreAuthScreen ? null : '/login';
  if (onPreAuthScreen) return landingPathFor(user);

  if (path.startsWith('/admin')) {
    // ...unchanged from here down (the staffOrAboveOk block and the
    // /staff check) -- do not alter anything below this line in the
    // function.
```

(Everything from the `if (path.startsWith('/admin'))` line to the end of
the function's existing body is untouched — only the parameter name and
the two lines above it change.)

Also update the doc comment immediately above `redirectFor` — the second
sentence currently reads "and whether `path` is the login/signup screen";
change it to "and whether `path` is one of the four pre-authentication
screens (splash, welcome, login, signup)".

Add the two new imports and routes to `lib/core/router.dart`:

```dart
// add near the top, alongside the other feature imports:
import '../features/auth/welcome_screen.dart';
import '../features/splash/splash_screen.dart';
```

```dart
// lib/core/router.dart — inside routerProvider, replace:
  return GoRouter(
    initialLocation: '/',
    redirect: (context, state) => redirectFor(
      user: auth.value,
      path: state.matchedLocation,
      loggingIn: state.matchedLocation == '/login' ||
          state.matchedLocation == '/signup',
    ),
    routes: [
      GoRoute(
        path: '/login',
        pageBuilder: (_, state) => fadeSlidePage(const LoginScreen(), state),
      ),
      GoRoute(
        path: '/signup',
        pageBuilder: (_, state) => fadeSlidePage(const SignupScreen(), state),
      ),
      GoRoute(path: '/404', builder: (_, _) => const NotFoundScreen()),
// with:
  const preAuthPaths = {'/splash', '/welcome', '/login', '/signup'};
  return GoRouter(
    initialLocation: '/splash',
    redirect: (context, state) => redirectFor(
      user: auth.value,
      path: state.matchedLocation,
      onPreAuthScreen: preAuthPaths.contains(state.matchedLocation),
    ),
    routes: [
      GoRoute(
        path: '/splash',
        pageBuilder: (_, state) => fadeSlidePage(const SplashScreen(), state),
      ),
      GoRoute(
        path: '/welcome',
        pageBuilder: (_, state) => fadeSlidePage(const WelcomeScreen(), state),
      ),
      GoRoute(
        path: '/login',
        pageBuilder: (_, state) => fadeSlidePage(const LoginScreen(), state),
      ),
      GoRoute(
        path: '/signup',
        pageBuilder: (_, state) => fadeSlidePage(const SignupScreen(), state),
      ),
      GoRoute(path: '/404', builder: (_, _) => const NotFoundScreen()),
```

Note `preAuthPaths` is declared once, above the `GoRouter(...)`
construction, inside the `routerProvider` builder function body (not as a
top-level constant) — it needs to be in scope for the `redirect:` closure.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/core/router_test.dart`
Expected: PASS — all tests, including the renamed/added ones. Also run
`flutter analyze` to confirm no other file references `redirectFor`'s old
`loggingIn` parameter name (this codebase's only two call sites are
`routerProvider` itself and `router_test.dart`, both updated in this task).

- [ ] **Step 5: Commit**

```bash
git add lib/core/router.dart test/core/router_test.dart
git commit -m "feat: wire splash and welcome screens into the router"
```

---

### Task 8: Booking screen — the occasion field

**Files:**
- Modify: `lib/features/booking/booking_screen.dart`
- Modify: `test/features/booking/hold_lifecycle_test.dart`

**Interfaces:**
- Consumes: `HoldParams` (existing), `BookingActions.createHold`'s `occasion` parameter (Task 4).
- Produces: `HoldParams.occasion` (`String?`, new field, included in equality/hash). Nothing later depends on this beyond what Tasks 9/10 already read off `Reservation.occasion`.

- [ ] **Step 1: Write the failing test**

Add this test to `test/features/booking/hold_lifecycle_test.dart`, inside
`main()` alongside the existing tests:

```dart
  test('HoldParams equality includes occasion', () {
    HoldParams params(String? occasion) => HoldParams(
          unitId: 'u1',
          from: DateTime.utc(2026, 8, 3),
          to: DateTime.utc(2026, 8, 5),
          guests: 2,
          slotTypeId: null,
          couponCode: null,
          occasion: occasion,
        );

    expect(params('Birthday'), params('Birthday'));
    expect(params('Birthday') == params('Anniversary'), isFalse);
    expect(params('Birthday') == params(null), isFalse);
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/booking/hold_lifecycle_test.dart --plain-name "HoldParams equality includes occasion"`
Expected: FAIL — `Error: No named parameter with the name 'occasion'` (the
`HoldParams` constructor doesn't accept it yet).

- [ ] **Step 3: Write the implementation**

```dart
// lib/features/booking/booking_screen.dart — HoldParams class, replace:
@immutable
class HoldParams {
  const HoldParams({
    required this.unitId,
    required this.from,
    required this.to,
    required this.guests,
    required this.slotTypeId,
    required this.couponCode,
  });

  final String unitId;
  final DateTime from;
  final DateTime to;
  final int guests;
  final String? slotTypeId;
  final String? couponCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is HoldParams &&
          other.unitId == unitId &&
          other.from == from &&
          other.to == to &&
          other.guests == guests &&
          other.slotTypeId == slotTypeId &&
          other.couponCode == couponCode);

  @override
  int get hashCode =>
      Object.hash(unitId, from, to, guests, slotTypeId, couponCode);
}
// with:
@immutable
class HoldParams {
  const HoldParams({
    required this.unitId,
    required this.from,
    required this.to,
    required this.guests,
    required this.slotTypeId,
    required this.couponCode,
    required this.occasion,
  });

  final String unitId;
  final DateTime from;
  final DateTime to;
  final int guests;
  final String? slotTypeId;
  final String? couponCode;

  /// Unlike `couponCode`, an occasion change never affects the quote --
  /// `get_quote` never reads it -- but it's still part of a hold's
  /// identity so editing it while a hold is live flows through the same
  /// `_changeSelection`/`resolveSelectionChange` machinery every other
  /// selection field already uses, instead of a bespoke code path.
  final String? occasion;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is HoldParams &&
          other.unitId == unitId &&
          other.from == from &&
          other.to == to &&
          other.guests == guests &&
          other.slotTypeId == slotTypeId &&
          other.couponCode == couponCode &&
          other.occasion == occasion);

  @override
  int get hashCode => Object.hash(
        unitId,
        from,
        to,
        guests,
        slotTypeId,
        couponCode,
        occasion,
      );
}
```

```dart
// lib/features/booking/booking_screen.dart — resolveHoldForPayment,
// replace the actions.createHold(...) call:
  return actions.createHold(
    unitId: params.unitId,
    from: params.from,
    to: params.to,
    guests: params.guests,
    slotTypeId: params.slotTypeId,
    expectedTotal: expectedTotal,
    couponCode: params.couponCode,
    occasion: params.occasion,
  );
```

```dart
// lib/features/booking/booking_screen.dart — _BookingScreenState, add a
// new field alongside the existing `_couponCode`/`_couponError` fields:
  String? _occasion;
```

```dart
// lib/features/booking/booking_screen.dart — _changeSelection, replace
// the nextParams construction:
    final nextParams = (from != null && to != null)
        ? HoldParams(
            unitId: widget.unitId,
            from: from,
            to: to,
            guests: guests,
            slotTypeId: slotTypeId,
            // A dates/guests/slot change always drops any applied coupon
            // (see the field's own doc comment) -- it is re-validated
            // against the fresh quote `_maybeFetchQuote` is about to fetch,
            // never silently carried over.
            couponCode: null,
            // Unlike couponCode, occasion carries over unchanged -- it has
            // nothing to do with pricing, so a dates/guests change has no
            // reason to clear it.
            occasion: _occasion,
          )
        : null;
```

```dart
// lib/features/booking/booking_screen.dart — _applyCoupon, replace the
// nextParams construction:
      final nextParams = HoldParams(
        unitId: widget.unitId,
        from: from,
        to: to,
        guests: _guests,
        slotTypeId: _slotTypeId,
        couponCode: code,
        occasion: _occasion,
      );
```

```dart
// lib/features/booking/booking_screen.dart — _pay, replace the params
// construction:
      final params = HoldParams(
        unitId: widget.unitId,
        from: from,
        to: to,
        guests: _guests,
        slotTypeId: _slotTypeId,
        couponCode: _couponCode,
        occasion: _occasion,
      );
```

Add a new handler alongside `_onGuestsChanged`:

```dart
  void _onOccasionChanged(String occasion) {
    final trimmed = occasion.trim();
    unawaited(
      _changeSelection(
        from: _from,
        to: _to,
        guests: _guests,
        slotTypeId: _slotTypeId,
        applyLocalChange: () => _occasion = trimmed.isEmpty ? null : trimmed,
      ),
    );
  }
```

`_changeSelection`'s signature only takes `from`/`to`/`guests`/`slotTypeId`
today; it doesn't need a new `occasion` parameter, because
`nextParams.occasion` above already reads `_occasion` directly (the field
this handler's `applyLocalChange` callback is about to update) rather
than requiring the caller to thread it through — the same pattern
`_onGuestsChanged` already relies on for `_guests`.

Add the occasion field to the UI, in the "Guests" section:

```dart
// lib/features/booking/booking_screen.dart — replace:
          _NumberedSection(
            number: 2,
            title: 'Guests',
            subtitle: '$_guests guest${_guests == 1 ? '' : 's'}',
            active: true,
            child: Column(children: [slotSelector, _guestStepper(unit)]),
          ),
// with:
          _NumberedSection(
            number: 2,
            title: 'Guests',
            subtitle: '$_guests guest${_guests == 1 ? '' : 's'}',
            active: true,
            child: Column(
              children: [slotSelector, _guestStepper(unit), _occasionField()],
            ),
          ),
```

Add the field's widget builder, alongside `_guestStepper`:

```dart
  Widget _occasionField() => Padding(
    padding: const EdgeInsets.only(top: Spacing.sm),
    child: TextFormField(
      key: const Key('occasion-field'),
      initialValue: _occasion,
      decoration: const InputDecoration(
        labelText: 'Occasion (optional)',
        helperText: 'Tell us what you\'re celebrating',
      ),
      onChanged: _onOccasionChanged,
    ),
  );
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/booking/hold_lifecycle_test.dart`
Expected: PASS — every test in the file, including the new one and the
three pre-existing unrelated failures (still exactly 3, from Global
Constraints).

- [ ] **Step 5: Commit**

```bash
git add lib/features/booking/booking_screen.dart test/features/booking/hold_lifecycle_test.dart
git commit -m "feat(booking): add an occasion field to the booking flow"
```

---

### Task 9: Confirmation screen — show the occasion

**Files:**
- Modify: `lib/features/booking/confirmation_screen.dart`
- Modify: `test/features/booking/confirmation_screen_test.dart`

**Interfaces:**
- Consumes: `Reservation.occasion` (Task 4).
- Produces: nothing new for later tasks.

- [ ] **Step 1: Write the failing test**

This file already exists (from the prior farmhouse UI redesign) with a
module-level `_reservation` fixture, a `_unit` fixture, and an `_appFor()`
helper that hardcodes both. Parameterize `_appFor` to accept an optional
reservation override — the existing two tests keep calling `_appFor()`
with no arguments and keep passing unmodified, since the default still
resolves to the same `_reservation` fixture with the same id (`'r1'`):

```dart
// test/features/booking/confirmation_screen_test.dart — replace:
Widget _appFor() {
  final router = GoRouter(
    initialLocation: '/booking/r1',
    routes: [
      GoRoute(
        path: '/booking/:id',
        builder: (_, state) =>
            ConfirmationScreen(reservationId: state.pathParameters['id']!),
      ),
      GoRoute(path: '/bookings', builder: (_, _) => const SizedBox()),
      GoRoute(path: '/', builder: (_, _) => const SizedBox()),
    ],
  );

  return ProviderScope(
    overrides: [
      reservationProvider('r1').overrideWith((ref) => Future.value(_reservation)),
      unitByIdProvider('u1').overrideWith((ref) => Future.value(_unit)),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}
// with:
Widget _appFor({Reservation? reservation}) {
  final res = reservation ?? _reservation;
  final router = GoRouter(
    initialLocation: '/booking/${res.id}',
    routes: [
      GoRoute(
        path: '/booking/:id',
        builder: (_, state) =>
            ConfirmationScreen(reservationId: state.pathParameters['id']!),
      ),
      GoRoute(path: '/bookings', builder: (_, _) => const SizedBox()),
      GoRoute(path: '/', builder: (_, _) => const SizedBox()),
    ],
  );

  return ProviderScope(
    overrides: [
      reservationProvider(res.id).overrideWith((ref) => Future.value(res)),
      unitByIdProvider('u1').overrideWith((ref) => Future.value(_unit)),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}
```

Then add these two tests inside `main()`, alongside the existing two (do
not remove or alter `'shows the unit name and stay dates once confirmed'`
or `'animates the checkmark in with a scale transition'`):

```dart
  testWidgets('shows the occasion when one was given', (tester) async {
    final reservation = Reservation(
      id: 'r-occasion',
      unitId: 'u1',
      start: DateTime.utc(2026, 8, 20),
      end: DateTime.utc(2026, 8, 22),
      kind: ReservationKind.booking,
      status: ReservationStatus.confirmed,
      guests: 2,
      occasion: 'Anniversary weekend',
    );

    await tester.pumpWidget(_appFor(reservation: reservation));
    await tester.pumpAndSettle();

    expect(find.textContaining('Anniversary weekend'), findsOneWidget);
  });

  testWidgets('shows nothing extra when no occasion was given', (
    tester,
  ) async {
    await tester.pumpWidget(_appFor());
    await tester.pumpAndSettle();

    expect(find.textContaining('For:'), findsNothing);
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/booking/confirmation_screen_test.dart`
Expected: FAIL — the new `'shows the occasion when one was given'` test
fails with `findsNothing` (no occasion text rendered yet); the other three
tests (two pre-existing, one new "shows nothing extra") pass already.

- [ ] **Step 3: Write the implementation**

```dart
// lib/features/booking/confirmation_screen.dart — replace:
                    const SizedBox(height: Spacing.sm),
                    Text(
                      '${formatDay(reservation.start.toLocal())} – '
                      '${formatDay(reservation.end.toLocal())}',
                      style: textTheme.bodyLarge?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    if (quote != null) ...[
// with:
                    const SizedBox(height: Spacing.sm),
                    Text(
                      '${formatDay(reservation.start.toLocal())} – '
                      '${formatDay(reservation.end.toLocal())}',
                      style: textTheme.bodyLarge?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    if (reservation.occasion != null &&
                        reservation.occasion!.trim().isNotEmpty) ...[
                      const SizedBox(height: Spacing.sm),
                      Text(
                        'For: ${reservation.occasion}',
                        style: textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    if (quote != null) ...[
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/booking/confirmation_screen_test.dart`
Expected: PASS — all four tests in the file (the two pre-existing ones,
unmodified in behavior, plus the two new occasion cases).

- [ ] **Step 5: Commit**

```bash
git add lib/features/booking/confirmation_screen.dart test/features/booking/confirmation_screen_test.dart
git commit -m "feat(booking): show the occasion on the confirmation screen"
```

---

### Task 10: Booking detail screen — show the occasion

**Files:**
- Modify: `lib/features/account/booking_detail_screen.dart`
- Modify: `test/features/account/booking_detail_screen_test.dart`

**Interfaces:**
- Consumes: `Reservation.occasion` (Task 4).
- Produces: nothing new for later tasks.

- [ ] **Step 1: Write the failing test**

The file already has a `_reservation({required ReservationStatus status,
String id = 'r1'})` fixture helper and an `openDetail(tester, reservation,
actions, {refunds})` pump helper, both used by every existing test in
`main()` (e.g. `'shows the stored quote breakdown, not a recomputed one'`).
Add this test to `test/features/account/booking_detail_screen_test.dart`,
inside `main()` alongside the existing tests, reusing both:

```dart
  testWidgets('shows the occasion when one was given', (tester) async {
    final reservation = Reservation(
      id: 'r-occasion',
      unitId: 'unit-1',
      start: DateTime.utc(2026, 8, 3),
      end: DateTime.utc(2026, 8, 5),
      kind: ReservationKind.booking,
      status: ReservationStatus.confirmed,
      guests: 4,
      quote: _quote(),
      occasion: 'Family reunion',
    );
    await openDetail(tester, reservation, _FakeCancelActions());

    expect(find.textContaining('Family reunion'), findsOneWidget);
  });

  testWidgets('shows nothing extra when no occasion was given', (
    tester,
  ) async {
    final reservation = _reservation(status: ReservationStatus.confirmed);
    await openDetail(tester, reservation, _FakeCancelActions());

    expect(find.textContaining('Occasion:'), findsNothing);
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/account/booking_detail_screen_test.dart`
Expected: FAIL — the first new test's `findsOneWidget` assertion fails
with `findsNothing` (no occasion row rendered yet); the second new test
passes already (there's nothing to show either way), which is expected
and fine.

- [ ] **Step 3: Write the implementation**

```dart
// lib/features/account/booking_detail_screen.dart — replace:
              if (reservation.guests != null) ...[
                const SizedBox(height: Spacing.xs),
                Text(
                  '${reservation.guests} guests',
                  style: textTheme.bodyMedium
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
              if (isBlock && reservation.blockReason != null) ...[
// with:
              if (reservation.guests != null) ...[
                const SizedBox(height: Spacing.xs),
                Text(
                  '${reservation.guests} guests',
                  style: textTheme.bodyMedium
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
              if (!isBlock &&
                  reservation.occasion != null &&
                  reservation.occasion!.trim().isNotEmpty) ...[
                const SizedBox(height: Spacing.xs),
                Text(
                  'Occasion: ${reservation.occasion}',
                  style: textTheme.bodyMedium
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
              if (isBlock && reservation.blockReason != null) ...[
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/account/booking_detail_screen_test.dart`
Expected: PASS — every test in the file.

- [ ] **Step 5: Commit**

```bash
git add lib/features/account/booking_detail_screen.dart test/features/account/booking_detail_screen_test.dart
git commit -m "feat(booking): show the occasion on the booking detail screen"
```

---

### Task 11: Browse screen — single-property auto-redirect

**Files:**
- Modify: `lib/features/browse/browse_screen.dart`
- Modify: `test/features/browse/browse_screen_test.dart`

**Interfaces:**
- Consumes: `propertiesProvider` (existing).
- Produces: nothing new for later tasks.

- [ ] **Step 1: Write the failing test**

Add the import this test needs at the top of
`test/features/browse/browse_screen_test.dart` (the file doesn't use
`go_router` today, since its four existing tests never trigger navigation):

```dart
import 'package:go_router/go_router.dart';
```

Then add this test inside `main()` alongside the existing tests (do not
alter the existing multi-property tests — they remain valid regression
coverage for if a second property is ever added):

```dart
  testWidgets(
    'redirects straight to the property page when there is exactly one',
    (tester) async {
      const property = Property(
        id: 'solo-1',
        name: 'Pasala Farm House',
        slug: 'pasala-farm-house',
        description: null,
        address: null,
        images: [],
        amenities: [],
        checkInTime: '14:00',
        checkOutTime: '11:00',
        isActive: true,
      );

      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(path: '/', builder: (_, _) => const BrowseScreen()),
          GoRoute(
            path: '/property/:id',
            builder: (_, state) =>
                Text('Property page: ${state.pathParameters['id']}'),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            propertiesProvider.overrideWith((ref) => Future.value([property])),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Property page: solo-1'), findsOneWidget);
      expect(find.text('Pasala Farm House'), findsNothing);
    },
  );
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/browse/browse_screen_test.dart --plain-name "redirects straight to the property page"`
Expected: FAIL — `find.text('Property page: solo-1')` finds nothing (the
screen currently always renders the grid/list, even for one property).

- [ ] **Step 3: Write the implementation**

```dart
// lib/features/browse/browse_screen.dart — replace:
      data: (list) => RefreshIndicator(
        onRefresh: () async => ref.invalidate(propertiesProvider),
        child: CustomScrollView(
// with:
      data: (list) {
        // With exactly one active property, skip the list entirely and
        // land the customer straight on it -- self-correcting if a second
        // property is ever seeded (see
        // docs/superpowers/specs/2026-08-13-single-property-onboarding-design.md
        // section 4.4). Scheduled post-frame so this never navigates
        // mid-build.
        if (list.length == 1) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) context.go('/property/${list.single.id}');
          });
          return const LoadingState();
        }
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(propertiesProvider),
          child: CustomScrollView(
```

The closing braces of the original `data: (list) => RefreshIndicator(...)`
arrow function must become a block-bodied function with an explicit
`return` and matching closing `);\n      },` — read the file's full
current `data:` closure (lines 30-81 as of this plan's writing) before
editing, since converting an arrow function to a block body changes where
the trailing parentheses/braces close, and getting that wrong is a syntax
error, not a logic error a test will conveniently catch mid-edit.

Add the `LoadingState` import:

```dart
// lib/features/browse/browse_screen.dart — add to the import list:
import '../../core/widgets/loading_state.dart';
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/browse/browse_screen_test.dart`
Expected: PASS — all five tests in the file (the four pre-existing
multi-property/grid/list/overflow tests, unmodified, plus the new
single-property redirect test).

- [ ] **Step 5: Commit**

```bash
git add lib/features/browse/browse_screen.dart test/features/browse/browse_screen_test.dart
git commit -m "feat(browse): auto-redirect to the property page when only one exists"
```

---

### Task 12: Full-suite verification and manual walkthrough

**Files:** none (verification only)

**Interfaces:** none

- [ ] **Step 1: Backend verification**

Run: `supabase db reset && supabase test db`
Expected: every pgTAP test file passes, including the new
`16_reservation_occasion_test.sql` and the rewritten
`10_reports_test.sql`.

- [ ] **Step 2: Static analysis**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 3: Full automated Flutter test suite**

Run: `flutter test`
Expected: every test passes except the three pre-existing
`hold_lifecycle_test.dart` failures noted in Global Constraints — confirm
by name that it is still exactly those same three test descriptions
failing, not a different set and not more than three. Any other failure
is a regression introduced by this plan and must be fixed before this
task is considered done.

- [ ] **Step 4: Manual browser walkthrough**

Run: `make run-web`, then walk the full path end-to-end:

1. Cold start lands on `/splash` — the night entrance-gate photo and logo
   mark appear, and it auto-advances to `/welcome` within ~1.5 seconds.
2. `/welcome` shows "Sign In" and "Sign Up" buttons over the same photo.
3. Tap "Sign In", sign in as `ravi@example.com` / `password123`.
4. Confirm landing goes straight to the Pasala Farm House property page —
   no intermediate list screen.
5. Start a booking on any unit (e.g. Dallas), enter an occasion note (e.g.
   "Birthday celebration") in the new field alongside the guest stepper,
   complete payment.
6. Confirm the confirmation screen shows "For: Birthday celebration"
   under the stay dates.
7. Go to `/bookings`, open the booking's detail screen, confirm it shows
   "Occasion: Birthday celebration".
8. Sign out and sign back in as `admin@pasala.test` / `password123` —
   confirm the admin still lands on `/admin` (unaffected by any of this
   plan's changes) and can still see the full property/unit management
   screens.

- [ ] **Step 5: Commit (only if the walkthrough surfaced a formatting fix)**

If `dart format --output=none --set-exit-if-changed .` reports any file
needing formatting, run `dart format .` and commit:

```bash
git add -A
git commit -m "chore: format single-property onboarding files"
```

If nothing needed fixing, skip this step — there is nothing to commit.
