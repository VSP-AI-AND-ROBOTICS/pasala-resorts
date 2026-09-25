// Extra fixture data for tests/accountant.spec.ts only.
//
// world.ts's two fixture bookings are both still open (confirmed / checked
// in), so Settlements -- which lists bookings checked out in the report
// range -- would otherwise be empty, and nothing in the fixture world uses
// a front-desk payment method, so there is no online-vs-desk split to see
// anywhere. This adds exactly one more booking to cover both: Resort A,
// Tree House (the one fixture unit nothing else books), already checked
// out today, paid 60% online (advance, as every fixture payment already
// is) and 40% at the desk in cash (balance) -- both payments dated today,
// so they show up in the Today tab's own split as well as this month's
// Collections, Ledger and Settlements.
//
// Kept out of fixtures/global-setup.ts and fixtures/sql.ts (per the task
// brief, other agents are editing blocks there in parallel) and instead
// created in this spec's own beforeAll/afterAll, through the same runSql
// helper global-setup.ts uses. Everything here is still namespaced the
// same way as world.ts (an @e2e.resorthub.test account, and rows hanging
// off an "e2e-" resort), so even if the afterAll here were ever skipped,
// the suite's own global teardown (fixtures/sql.ts) would still remove it.

import { runSql } from '../fixtures/db.ts';
import { PASSWORD, email, resortA, type FixtureUser } from '../fixtures/world.ts';

/** The guest on the desk-paid settlement below. Nothing else uses this account. */
export const deskGuest: FixtureUser = {
  id: 'e2eacc00-0000-4000-8000-000000000001',
  email: email('guest.deskpay'),
  fullName: 'Priya DeskPay',
};

/** Resort A, Tree House: yesterday -> today, already checked out. */
export const DESK_RESERVATION_ID = 'e2eacc00-0000-4000-8000-000000000002';
const RESERVATION_ID = DESK_RESERVATION_ID;
const UNIT_ID = resortA.units[2].id;

const lit = (value: string): string => `'${value.replace(/'/g, "''")}'`;

/** Inserts the desk guest, the booking, and its two payments. */
export function setupAccountantFixtures(): void {
  runSql(`
begin;

insert into auth.users (id, instance_id, aud, role, email, encrypted_password,
                        email_confirmed_at, raw_app_meta_data,
                        raw_user_meta_data, created_at, updated_at,
                        confirmation_token, recovery_token,
                        email_change_token_new, email_change)
values (
  ${lit(deskGuest.id)}::uuid, '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', ${lit(deskGuest.email)},
  crypt(${lit(PASSWORD)}, gen_salt('bf')), now(),
  '{"provider":"email","providers":["email"]}'::jsonb,
  jsonb_build_object('full_name', ${lit(deskGuest.fullName)}),
  now(), now(), '', '', '', ''
);

insert into auth.identities (id, provider_id, user_id, identity_data, provider,
                             last_sign_in_at, created_at, updated_at)
values (
  gen_random_uuid(), ${lit(deskGuest.id)}, ${lit(deskGuest.id)}::uuid,
  jsonb_build_object('sub', ${lit(deskGuest.id)}, 'email', ${lit(deskGuest.email)},
                     'email_verified', true),
  'email', now(), now(), now()
);

with period as (
  select public.build_period(
    ${lit(UNIT_ID)}::uuid,
    ((now() at time zone 'Asia/Kolkata')::date) - 1,
    ((now() at time zone 'Asia/Kolkata')::date)
  ) as p
),
quoted as (
  select p, public.get_quote(${lit(UNIT_ID)}::uuid, p, 2) as q from period
)
insert into public.reservations
  (id, unit_id, period, kind, status, customer_id, guests, quote, source,
   created_by, checked_in_at, checked_out_at)
select
  ${lit(RESERVATION_ID)}::uuid, ${lit(UNIT_ID)}::uuid, p, 'booking', 'checked_out',
  ${lit(deskGuest.id)}::uuid, 2, q, 'app', ${lit(deskGuest.id)}::uuid,
  lower(p), now()
from quoted;

-- 60% online, as an advance -- the same shape every fixture booking's own
-- payment already has.
insert into public.payments
  (reservation_id, amount, kind, status, gateway, gateway_ref, method, recorded_by)
select
  ${lit(RESERVATION_ID)}::uuid, round((quote ->> 'total')::numeric * 0.6, 2),
  'advance', 'succeeded', 'mock', ${lit(`e2e-acc-adv-${RESERVATION_ID}`)}, 'gateway',
  ${lit(deskGuest.id)}::uuid
from public.reservations where id = ${lit(RESERVATION_ID)}::uuid;

-- The remaining 40%, taken at the desk in cash by the resort's own
-- accountant -- exactly the split checkout_booking (0048) would record.
insert into public.payments
  (reservation_id, amount, kind, status, gateway, gateway_ref, method, reference, recorded_by)
select
  ${lit(RESERVATION_ID)}::uuid,
  round((quote ->> 'total')::numeric, 2) - round((quote ->> 'total')::numeric * 0.6, 2),
  'balance', 'succeeded', 'desk', ${lit(`desk-${RESERVATION_ID}`)}, 'cash', 'E2E-RCPT-1',
  ${lit(resortA.team.accountant.id)}::uuid
from public.reservations where id = ${lit(RESERVATION_ID)}::uuid;

commit;
`);
}

/** Removes exactly what setupAccountantFixtures() added. */
export function teardownAccountantFixtures(): void {
  runSql(`
begin;
delete from public.payments where reservation_id = ${lit(RESERVATION_ID)}::uuid;
delete from public.reservations where id = ${lit(RESERVATION_ID)}::uuid;
delete from auth.refresh_tokens where user_id = ${lit(deskGuest.id)};
delete from auth.identities where user_id = ${lit(deskGuest.id)}::uuid;
delete from auth.users where id = ${lit(deskGuest.id)}::uuid;
commit;
`);
}
