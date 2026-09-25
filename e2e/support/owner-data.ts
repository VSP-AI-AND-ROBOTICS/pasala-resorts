// Extra fixture data for tests/owner.spec.ts's tenancy check: a booking at
// Resort B, so the spec can assert its guest's name never leaks into Resort
// A's admin bookings list.
//
// PERSONA: owner. This file is scoped to owner.spec.ts alone -- created in
// its beforeAll and deleted in its afterAll -- rather than added to
// fixtures/world.ts / global-setup.ts, so it never collides with another
// spec editing those shared files in parallel (see the task brief). It
// follows the same naming rules as world.ts (email under EMAIL_DOMAIN, a
// fresh id that doesn't collide with any id already in world.ts) purely as
// a defensive belt-and-braces measure: global teardown's %@e2e.resorthub.test
// pattern would also sweep this up if this file's own cleanup didn't run.
//
// Written the same way fixtures/sql.ts writes bookings (see its bookingSql),
// through the same runSql() helper (fixtures/db.ts), as the postgres role.

import { runSql } from '../fixtures/db.ts';
import { PASSWORD, email, resortB, type FixtureUser } from '../fixtures/world.ts';

const lit = (value: string): string => `'${value.replace(/'/g, "''")}'`;

/**
 * A guest with a booking at Resort B ONLY. Its name is distinctive
 * ("NeverInA") so a test can search Resort A's own screens for it and
 * assert it never shows up.
 */
export const tenancyGuestB: FixtureUser = {
  id: 'e2e1a000-0000-4000-8000-00000000000b',
  email: email('guest.tenancy-b'),
  fullName: 'Nadia NeverInA',
};

const BOOKING_ID = 'e2e3a000-0000-4000-8000-00000000000b';

/**
 * Creates [tenancyGuestB]'s account and a confirmed, paid booking at Resort
 * B's first unit, today -> tomorrow. Idempotent-ish: run [deleteOwnerTenancyFixture]
 * first if a previous run was interrupted before cleaning up.
 */
export function createOwnerTenancyFixture(): void {
  const unit = resortB.units[0];
  const today = `(now() at time zone 'Asia/Kolkata')::date`;
  const period = `public.build_period(${lit(unit.id)}, ${today}, ${today} + 1)`;
  runSql(`
begin;

insert into auth.users (id, instance_id, aud, role, email, encrypted_password,
                        email_confirmed_at, raw_app_meta_data,
                        raw_user_meta_data, created_at, updated_at,
                        confirmation_token, recovery_token,
                        email_change_token_new, email_change)
values (${lit(tenancyGuestB.id)}::uuid, '00000000-0000-0000-0000-000000000000',
        'authenticated', 'authenticated', ${lit(tenancyGuestB.email)},
        crypt(${lit(PASSWORD)}, gen_salt('bf')), now(),
        '{"provider":"email","providers":["email"]}'::jsonb,
        jsonb_build_object('full_name', ${lit(tenancyGuestB.fullName)}),
        now(), now(), '', '', '', '');

insert into auth.identities (id, provider_id, user_id, identity_data, provider,
                             last_sign_in_at, created_at, updated_at)
values (gen_random_uuid(), ${lit(tenancyGuestB.id)}, ${lit(tenancyGuestB.id)}::uuid,
        jsonb_build_object('sub', ${lit(tenancyGuestB.id)}, 'email', ${lit(tenancyGuestB.email)},
                           'email_verified', true),
        'email', now(), now(), now());

insert into public.reservations
  (id, unit_id, period, kind, status, customer_id, guests, quote, source, created_by)
values
  (${lit(BOOKING_ID)}, ${lit(unit.id)}, ${period}, 'booking', 'confirmed',
   ${lit(tenancyGuestB.id)}, 2,
   public.get_quote(${lit(unit.id)}, ${period}, 2),
   'app', ${lit(tenancyGuestB.id)});

insert into public.payments (reservation_id, amount, kind, status, gateway, gateway_ref)
select id, (quote ->> 'total')::numeric, 'advance', 'succeeded', 'mock', ${lit(`e2e-${BOOKING_ID}`)}
from public.reservations where id = ${lit(BOOKING_ID)};

commit;
`);
}

/** Deletes everything [createOwnerTenancyFixture] added, restoring the world as found. */
export function deleteOwnerTenancyFixture(): void {
  runSql(`
begin;
delete from public.payments where reservation_id = ${lit(BOOKING_ID)};
delete from public.reservations where id = ${lit(BOOKING_ID)};
delete from auth.refresh_tokens where user_id = ${lit(tenancyGuestB.id)}::text;
delete from auth.identities where user_id = ${lit(tenancyGuestB.id)}::uuid;
delete from auth.users where id = ${lit(tenancyGuestB.id)}::uuid;
commit;
`);
}
