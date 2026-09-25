// SQL that builds and removes the fixture world (world.ts). Run through
// db.ts as the `postgres` role, which bypasses RLS, so rows are written
// straight into the tables, the way supabase/seed.sql writes them.
//
// Safety: every delete here is scoped to resorts whose slug starts with
// "e2e-" and accounts whose email ends in "@e2e.resorthub.test". Nothing
// else in the (real, local) database is touched.

import {
  EMAIL_DOMAIN,
  PASSWORD,
  SLUG_PREFIX,
  allResorts,
  allUsers,
  bookings,
  platformAdmin,
  type FixtureBooking,
} from './world.ts';

/** A SQL string literal. */
const lit = (value: string): string => `'${value.replace(/'/g, "''")}'`;

const RESORT_SLUGS = lit(`${SLUG_PREFIX}%`);
const USER_EMAILS = lit(`%@${EMAIL_DOMAIN}`);

/**
 * Deletes every fixture resort and account, and everything hanging off
 * them. Idempotent: safe on an empty database and after a half-finished run.
 *
 * Resort-scoped tables are found by their `property_id` column, and the
 * foreign keys pointing at fixture accounts are read from the catalog, so a
 * table added by a later migration is covered without editing this file.
 * Foreign-key order between those tables is resolved by retrying.
 */
export function teardownSql(): string {
  return `
do $e2e$
declare
  v_props  uuid[] := array(select id from public.properties where slug like ${RESORT_SLUGS});
  v_users  uuid[] := array(select id from auth.users where email like ${USER_EMAILS});
  v_tables text[];
  v_refs   text[];
  v_left   int;
  v_pass   int;
  t        text;
begin
  -- 1. Every row at a fixture resort, then the resorts. Tasks included:
  --    with no auth.uid() here, tasks_enforce_write lets this session
  --    delete them and unlink them from a deleted unit (0050).
  select coalesce(array_agg(format('public.%I', c.table_name)), '{}')
    into v_tables
    from information_schema.columns c
    join information_schema.tables tb
      on tb.table_schema = c.table_schema and tb.table_name = c.table_name
   where c.table_schema = 'public'
     and c.column_name = 'property_id'
     and tb.table_type = 'BASE TABLE';

  v_pass := 0;
  loop
    v_pass := v_pass + 1;
    v_left := 0;
    foreach t in array v_tables loop
      begin
        execute format('delete from %s where property_id = any($1)', t) using v_props;
      exception when foreign_key_violation then
        v_left := v_left + 1;
      end;
    end loop;
    exit when v_left = 0;
    if v_pass >= 20 then
      raise exception 'e2e teardown: resort rows still referenced after % passes', v_pass;
    end if;
  end loop;

  delete from public.audit_log
   where entity_id = any(v_props) or entity_id = any(v_users) or actor_id = any(v_users);
  delete from public.properties where id = any(v_props);

  -- 2. Anything a fixture account left at a non-fixture resort (a test
  --    guest booking a real resort, say), via every single-column foreign
  --    key to profiles or auth.users that would otherwise block the delete.
  select coalesce(array_agg(format('delete from %s where %I = any($1)',
                                   con.conrelid::regclass, a.attname)), '{}')
    into v_refs
    from pg_constraint con
    join pg_attribute a
      on a.attrelid = con.conrelid and a.attnum = con.conkey[1]
   where con.contype = 'f'
     and array_length(con.conkey, 1) = 1
     and con.confrelid in ('public.profiles'::regclass, 'auth.users'::regclass)
     and con.confdeltype in ('a', 'r')
     and con.connamespace = 'public'::regnamespace;

  v_pass := 0;
  loop
    v_pass := v_pass + 1;
    v_left := 0;
    foreach t in array v_refs loop
      begin
        execute t using v_users;
      exception when foreign_key_violation then
        v_left := v_left + 1;
      end;
    end loop;
    exit when v_left = 0;
    if v_pass >= 20 then
      raise exception 'e2e teardown: account rows still referenced after % passes', v_pass;
    end if;
  end loop;

  -- 3. The accounts. Cascades to profiles, identities, sessions and
  --    resort memberships.
  delete from auth.refresh_tokens where user_id = any(v_users::text[]);
  delete from auth.users where id = any(v_users);
end
$e2e$;
`;
}

function usersSql(): string {
  const users = allUsers
    .map((u) => `(${lit(u.id)}::uuid, ${lit(u.email)}, ${lit(u.fullName)})`)
    .join(',\n  ');
  return `
-- Accounts, as supabase/seed.sql creates them. Identities are added for
-- exactly these ids (not by email pattern), so an extra account a spec adds
-- under the same domain in its own beforeAll is never matched twice. on_auth_user_created adds
-- each profile (role customer).
insert into auth.users (id, instance_id, aud, role, email, encrypted_password,
                        email_confirmed_at, raw_app_meta_data,
                        raw_user_meta_data, created_at, updated_at,
                        confirmation_token, recovery_token,
                        email_change_token_new, email_change)
select u.id, '00000000-0000-0000-0000-000000000000', 'authenticated',
       'authenticated', u.email, crypt(${lit(PASSWORD)}, gen_salt('bf')), now(),
       '{"provider":"email","providers":["email"]}'::jsonb,
       jsonb_build_object('full_name', u.full_name),
       now(), now(), '', '', '', ''
from (values
  ${users}
) as u(id, email, full_name);

insert into auth.identities (id, provider_id, user_id, identity_data, provider,
                             last_sign_in_at, created_at, updated_at)
select gen_random_uuid(), u.id::text, u.id,
       jsonb_build_object('sub', u.id::text, 'email', u.email,
                          'email_verified', true),
       'email', now(), now(), now()
from auth.users u
where u.id in (${allUsers.map((u) => `${lit(u.id)}::uuid`).join(', ')});

update public.profiles set role = 'platform_admin' where id = ${lit(platformAdmin.id)};
`;
}

function resortsSql(): string {
  return allResorts
    .map((r) => {
      const members = Object.entries(r.team)
        .map(([role, u]) => `(${lit(r.id)}, ${lit(u.id)}, ${lit(role)})`)
        .join(',\n  ');
      const units = r.units
        .map(
          (u) =>
            `(${lit(u.id)}, ${lit(r.id)}, ${lit(u.name)}, ${u.capacityBase}, ${u.capacityMax}, 'nightly')`,
        )
        .join(',\n  ');
      const rates = r.units
        .map(
          (u) =>
            `(${lit(u.id)}, 'base', 'Weekday', ${u.nightlyRate}, 500, ${u.cleaningFee}, 0, null),\n  ` +
            `(${lit(u.id)}, 'weekend', 'Weekend', ${Math.round(u.nightlyRate * 1.4)}, 500, ${u.cleaningFee}, 10, array[6,7])`,
        )
        .join(',\n  ');
      return `
-- ${r.name}
insert into public.properties
  (id, name, slug, description, address, status, amenities, check_in_time, check_out_time)
values
  (${lit(r.id)}, ${lit(r.name)}, ${lit(r.slug)},
   'Fixture resort for the Playwright suite. Deleted after every run.',
   'E2E Lane, Testville', ${lit(r.status)}, array['Pool','Wi-Fi','Parking'],
   '14:00', '11:00');

insert into public.resort_subscriptions (property_id, tier, status)
values (${lit(r.id)}, ${lit(r.subscription.tier)}, ${lit(r.subscription.status)});

insert into public.resort_members (property_id, user_id, role) values
  ${members};

insert into public.units (id, property_id, name, capacity_base, capacity_max, booking_mode) values
  ${units};

insert into public.rate_rules
  (unit_id, kind, label, price, extra_guest_price, cleaning_fee, priority, weekdays)
values
  ${rates};
`;
    })
    .join('');
}

function bookingSql(b: FixtureBooking): string {
  // "Today" is the resort's today, as build_period and the app see it.
  const today = `(now() at time zone 'Asia/Kolkata')::date`;
  const period = `public.build_period(${lit(b.unitId)}, ${today} + ${b.fromDay}, ${today} + ${b.toDay})`;
  let sql = `
insert into public.reservations
  (id, unit_id, period, kind, status, customer_id, guests, quote, source, created_by)
values
  (${lit(b.id)}, ${lit(b.unitId)}, ${period}, 'booking', 'confirmed',
   ${lit(b.guest.id)}, ${b.guests},
   public.get_quote(${lit(b.unitId)}, ${period}, ${b.guests}),
   'app', ${lit(b.guest.id)});

-- Paid in full, as confirm_booking records it.
insert into public.payments (reservation_id, amount, kind, status, gateway, gateway_ref)
select id, (quote ->> 'total')::numeric, 'advance', 'succeeded', 'mock', ${lit(`e2e-${b.id}`)}
from public.reservations where id = ${lit(b.id)};
`;
  if (b.status === 'checked_in') {
    sql += `
-- Checked in at 15:00 on arrival day, as check_in_booking records it.
update public.reservations
   set status = 'checked_in',
       checked_in_at = ((${today} + ${b.fromDay}) + time '15:00') at time zone 'Asia/Kolkata'
 where id = ${lit(b.id)};
`;
  }
  return sql;
}

/** Tears down any previous fixture world, then builds a fresh one. */
export function setupSql(): string {
  return [
    'begin;',
    teardownSql(),
    usersSql(),
    resortsSql(),
    ...Object.values(bookings).map(bookingSql),
    'commit;',
  ].join('\n');
}
