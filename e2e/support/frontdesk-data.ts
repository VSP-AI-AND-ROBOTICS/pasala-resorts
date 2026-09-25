// Extra fixture data for tests/frontdesk.spec.ts only. Kept out of
// fixtures/sql.ts and fixtures/global-setup.ts (which other agents are
// editing in parallel) to keep this change isolated: the spec's own
// beforeAll/afterAll create and remove exactly these rows through
// fixtures/db.ts, the same psql-in-Docker path world.ts's own fixtures use.
//
// Persona: frontdesk. Do not reuse these ids elsewhere.
//
// Why a whole new guest + booking instead of reusing world.ts's
// `bookings.arrivingToday` / `bookings.checkedIn`: this spec checks a guest
// in, takes a desk payment, and checks them out again -- real, one-way
// state changes. Doing that to a booking other spec files also read (e.g.
// a dashboard "Next Arrival" card) would make this spec's result depend on
// run order across files. A dedicated guest at Tree House -- the one Resort
// A unit no shared fixture booking uses -- and arriving tomorrow rather
// than today (so it can never be sorted ahead of the shared
// `guests.arriving` booking as Resort A's next arrival) avoids that.
//
// This booking is also deliberately paid only 40% up front (world.ts's
// shared bookings are paid in full), so `current_charges` reports a real
// balance and the desk checkout screen's Cash-and-reference flow actually
// has something to do.

import { EMAIL_DOMAIN, PASSWORD, resortA, type FixtureUser } from '../fixtures/world.ts';
import { runSql } from '../fixtures/db.ts';

const lit = (value: string): string => `'${value.replace(/'/g, "''")}'`;

export const frontdeskGuest: FixtureUser = {
  id: 'e2e40000-0000-4000-8000-000000000001',
  email: `guest.frontdesk@${EMAIL_DOMAIN}`,
  fullName: 'Frank Frontdesk',
};

/** Tree House: the one Resort A unit no fixture in world.ts already books. */
export const frontdeskUnit = resortA.units[2];

export const frontdeskBookingId = 'e2e30000-0000-4000-8000-000000000099';

/**
 * Confirmed, Tree House, `frontdeskGuest`, arriving tomorrow -> +3 days,
 * paid 40% up front (a real balance is due at checkout).
 */
export function setupFrontdeskFixture(): void {
  runSql(`
begin;

insert into auth.users (id, instance_id, aud, role, email, encrypted_password,
                        email_confirmed_at, raw_app_meta_data,
                        raw_user_meta_data, created_at, updated_at,
                        confirmation_token, recovery_token,
                        email_change_token_new, email_change)
values (
  ${lit(frontdeskGuest.id)}, '00000000-0000-0000-0000-000000000000', 'authenticated',
  'authenticated', ${lit(frontdeskGuest.email)}, crypt(${lit(PASSWORD)}, gen_salt('bf')), now(),
  '{"provider":"email","providers":["email"]}'::jsonb,
  jsonb_build_object('full_name', ${lit(frontdeskGuest.fullName)}),
  now(), now(), '', '', '', ''
);

insert into auth.identities (id, provider_id, user_id, identity_data, provider,
                             last_sign_in_at, created_at, updated_at)
values (
  gen_random_uuid(), ${lit(frontdeskGuest.id)}, ${lit(frontdeskGuest.id)}::uuid,
  jsonb_build_object('sub', ${lit(frontdeskGuest.id)}, 'email', ${lit(frontdeskGuest.email)},
                     'email_verified', true),
  'email', now(), now(), now()
);

insert into public.reservations
  (id, unit_id, period, kind, status, customer_id, guests, quote, source, created_by)
values (
  ${lit(frontdeskBookingId)}, ${lit(frontdeskUnit.id)},
  public.build_period(${lit(frontdeskUnit.id)},
    (now() at time zone 'Asia/Kolkata')::date + 1,
    (now() at time zone 'Asia/Kolkata')::date + 3),
  'booking', 'confirmed', ${lit(frontdeskGuest.id)}, 2,
  public.get_quote(${lit(frontdeskUnit.id)},
    public.build_period(${lit(frontdeskUnit.id)},
      (now() at time zone 'Asia/Kolkata')::date + 1,
      (now() at time zone 'Asia/Kolkata')::date + 3),
    2),
  'app', ${lit(frontdeskGuest.id)}
);

-- Paid 40% up front, unlike world.ts's fully-paid fixture bookings, so a
-- real balance is due when this spec checks the guest out at the desk.
insert into public.payments (reservation_id, amount, kind, status, gateway, gateway_ref)
select id, round((quote ->> 'total')::numeric * 0.4, 2), 'advance', 'succeeded', 'mock',
       ${lit(`e2e-fd-${frontdeskBookingId}`)}
from public.reservations where id = ${lit(frontdeskBookingId)};

commit;
`);
}

/**
 * Removes exactly the rows setupFrontdeskFixture() created, and puts Tree
 * House's room status back the way the fixture world starts it (no row, so
 * Available): the spec's desk checkout marks the room dirty, which would
 * otherwise leak into later spec files' room-grid counts (staff.spec.ts).
 */
export function teardownFrontdeskFixture(): void {
  runSql(`
begin;
delete from public.unit_room_status where unit_id = ${lit(frontdeskUnit.id)};
delete from public.payments where reservation_id = ${lit(frontdeskBookingId)};
delete from public.reservations where id = ${lit(frontdeskBookingId)};
delete from auth.identities where user_id = ${lit(frontdeskGuest.id)}::uuid;
delete from auth.refresh_tokens where user_id = ${lit(frontdeskGuest.id)};
delete from auth.users where id = ${lit(frontdeskGuest.id)};
commit;
`);
}
