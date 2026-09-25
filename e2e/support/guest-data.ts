// Extra fixture data for guest.spec.ts, on top of fixtures/world.ts.
//
// world.ts's shared resorts (A/B/S) are shared with other specs, so the
// live booking tests use their own resort instead (PropertyScreen handles
// multi-unit resorts too now -- see guest.spec.ts's unit-picker test --
// but a single unit keeps the flow free of a picker step and of contention
// with other specs' bookings). This file adds one resort with a
// single unit -- with a 35% advance policy, so the split-payment option in
// QuoteSheet actually renders -- plus one already-checked-out stay with a
// review, so the property page's "reviews" section has something to show.
//
// Persona: guest. Keep this isolated from world.ts and sql.ts (other agents
// edit those in parallel) -- this file owns its own slug/email namespace
// (still under the shared "e2e-"/"@e2e.resorthub.test" prefixes, so the
// global teardown in fixtures/global-teardown.ts sweeps it up as a backstop
// even if setupGuestData/teardownGuestData below is never reached).

import { runSql } from '../fixtures/db.ts';
import { EMAIL_DOMAIN, PASSWORD, SLUG_PREFIX, guests, type FixtureUser } from '../fixtures/world.ts';

const lit = (value: string): string => `'${value.replace(/'/g, "''")}'`;

export const guestResort = {
  id: 'e2ed0001-0000-4000-8000-000000000000',
  slug: `${SLUG_PREFIX}guest-book`,
  name: 'E2E Guest Booking Resort',
  advancePct: 35,
  unit: {
    id: 'e2ed0001-0000-4000-8000-000000000001',
    name: 'Meadow Suite',
    capacityBase: 2,
    capacityMax: 4,
    nightlyRate: 6000,
    cleaningFee: 500,
  },
  /** Distinct from every world.ts resort's amenities (['Pool','Wi-Fi','Parking']) so the browse
   * screen's amenity filter can be exercised deterministically. */
  amenity: 'Spa',
} as const;

/** Already checked out, with a review -- exists only so the resort's page has one. */
const reviewedReservationId = 'e2ed0001-0000-4000-8000-000000000002';

const reviewer: FixtureUser = {
  id: 'e2ed0001-0000-4000-8000-000000000003',
  email: `guest.reviewer@${EMAIL_DOMAIN}`,
  fullName: 'Rita Reviewer',
};

/** Creates the resort, its one unit/rates, a past checked-out stay, and its review. */
export function setupGuestData(): void {
  runSql(`
begin;

insert into public.properties
  (id, name, slug, description, address, status, amenities, check_in_time, check_out_time, advance_pct)
values
  (${lit(guestResort.id)}, ${lit(guestResort.name)}, ${lit(guestResort.slug)},
   'Fixture resort for guest.spec.ts. Deleted after every run.',
   'E2E Meadow Lane, Testville', 'active', array[${lit(guestResort.amenity)}],
   '14:00', '11:00', ${guestResort.advancePct});

insert into public.resort_subscriptions (property_id, tier, status)
values (${lit(guestResort.id)}, 'starter', 'active');

insert into public.units (id, property_id, name, capacity_base, capacity_max, booking_mode)
values (${lit(guestResort.unit.id)}, ${lit(guestResort.id)}, ${lit(guestResort.unit.name)},
        ${guestResort.unit.capacityBase}, ${guestResort.unit.capacityMax}, 'nightly');

insert into public.rate_rules (unit_id, kind, label, price, extra_guest_price, cleaning_fee, priority, weekdays)
values
  (${lit(guestResort.unit.id)}, 'base', 'Weekday', ${guestResort.unit.nightlyRate}, 500, ${guestResort.unit.cleaningFee}, 0, null),
  (${lit(guestResort.unit.id)}, 'weekend', 'Weekend', ${Math.round(guestResort.unit.nightlyRate * 1.4)}, 500, ${guestResort.unit.cleaningFee}, 10, array[6,7]);

-- The reviewer account (as supabase/seed.sql creates accounts).
insert into auth.users (id, instance_id, aud, role, email, encrypted_password,
                        email_confirmed_at, raw_app_meta_data,
                        raw_user_meta_data, created_at, updated_at,
                        confirmation_token, recovery_token,
                        email_change_token_new, email_change)
values (${lit(reviewer.id)}::uuid, '00000000-0000-0000-0000-000000000000', 'authenticated',
        'authenticated', ${lit(reviewer.email)}, crypt(${lit(PASSWORD)}, gen_salt('bf')), now(),
        '{"provider":"email","providers":["email"]}'::jsonb,
        jsonb_build_object('full_name', ${lit(reviewer.fullName)}),
        now(), now(), '', '', '', '');

insert into auth.identities (id, provider_id, user_id, identity_data, provider,
                             last_sign_in_at, created_at, updated_at)
values (gen_random_uuid(), ${lit(reviewer.id)}, ${lit(reviewer.id)}::uuid,
        jsonb_build_object('sub', ${lit(reviewer.id)}, 'email', ${lit(reviewer.email)},
                           'email_verified', true),
        'email', now(), now(), now());

-- A stay that finished 5 days ago, already checked out.
insert into public.reservations
  (id, unit_id, period, kind, status, customer_id, guests, quote, source, created_by)
values
  (${lit(reviewedReservationId)}, ${lit(guestResort.unit.id)},
   public.build_period(${lit(guestResort.unit.id)}, (now() at time zone 'Asia/Kolkata')::date - 5,
                        (now() at time zone 'Asia/Kolkata')::date - 3),
   'booking', 'checked_out', ${lit(reviewer.id)}, 2,
   public.get_quote(${lit(guestResort.unit.id)},
                     public.build_period(${lit(guestResort.unit.id)}, (now() at time zone 'Asia/Kolkata')::date - 5,
                                         (now() at time zone 'Asia/Kolkata')::date - 3),
                     2),
   'app', ${lit(reviewer.id)});

insert into public.payments (reservation_id, amount, kind, status, gateway, gateway_ref)
select id, (quote ->> 'total')::numeric, 'advance', 'succeeded', 'mock', ${lit(`e2e-${reviewedReservationId}`)}
from public.reservations where id = ${lit(reviewedReservationId)};

insert into public.reviews
  (reservation_id, customer_id, farmhouse_rating, cleanliness_rating, food_rating,
   service_rating, activities_rating, overall_rating, feedback)
values
  (${lit(reviewedReservationId)}, ${lit(reviewer.id)}, 5, 5, 4, 5, 4, 5,
   'Lovely, peaceful stay -- e2e fixture review, ignore.');

commit;
`);
}

/** Deletes everything setupGuestData created, plus anything guest.spec.ts's own tests left
 * behind at guestResort (the global teardown also sweeps this up by slug/email as a backstop,
 * but this keeps the world clean even for a lone `npx playwright test tests/guest.spec.ts` run). */
export function teardownGuestData(): void {
  runSql(`
begin;
delete from public.audit_log where property_id = ${lit(guestResort.id)};
delete from public.reviews where property_id = ${lit(guestResort.id)};
delete from public.payments where property_id = ${lit(guestResort.id)};
delete from public.reservations where unit_id = ${lit(guestResort.unit.id)};
delete from public.rate_rules where property_id = ${lit(guestResort.id)};
delete from public.units where property_id = ${lit(guestResort.id)};
delete from public.resort_subscriptions where property_id = ${lit(guestResort.id)};
delete from public.properties where id = ${lit(guestResort.id)};
delete from auth.refresh_tokens where user_id = ${lit(reviewer.id)};
delete from auth.users where id = ${lit(reviewer.id)}::uuid;
commit;
`);
}

/** The fixture guest with no bookings (world.ts's `guests.fresh`), re-exported here so
 * guest.spec.ts's booking-flow tests read as self-contained without a second import. */
export const bookingGuest: FixtureUser = guests.fresh;
