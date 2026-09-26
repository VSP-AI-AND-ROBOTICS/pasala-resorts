// Building blocks for a spec that brings its own resort and accounts
// (the gap-round specs: coupons, taxes, OTA sync, outbox, listing,
// discovery). Each spec creates what it needs in beforeAll and removes it
// in afterAll with removeFixtures(), so it never changes world.ts's shared
// resorts. Everything follows world.ts's naming (slug "e2e-...", email
// "...@e2e.resorthub.test"), so the global teardown sweeps it up too if a
// run is killed before afterAll.

import { runSql } from '../fixtures/db.ts';
import { createUsersSql, scopedTeardownSql } from '../fixtures/sql.ts';
import { PASSWORD, email, type FixtureUser, type ResortRoleName } from '../fixtures/world.ts';

export { PASSWORD };

/** A SQL string literal. */
export const lit = (value: string): string => `'${value.replace(/'/g, "''")}'`;

/** The resort's today (Asia/Kolkata), as build_period and the app see it. */
export const TODAY = `(now() at time zone 'Asia/Kolkata')::date`;

/** A fixture account in its own id block: `e2e5xxxx-...`. */
export const kitUser = (block: number, n: number, local: string, fullName: string): FixtureUser => ({
  id: `e2e5${block.toString(16).padStart(4, '0')}-0000-4000-8000-${n.toString().padStart(12, '0')}`,
  email: email(local),
  fullName,
});

export interface KitUnit {
  id: string;
  name: string;
  nightlyRate: number;
  cleaningFee?: number;
  capacityBase?: number;
  capacityMax?: number;
}

export interface KitResort {
  id: string;
  slug: string;
  name: string;
  description?: string;
  address?: string;
  city?: string;
  amenities?: string[];
  advancePct?: number;
  lat?: number;
  lng?: number;
  units: KitUnit[];
  team: Partial<Record<ResortRoleName, FixtureUser>>;
}

/** Inserts [resort] (active, starter plan), its team, units and rates. */
export function createResortSql(resort: KitResort): string {
  const members = Object.entries(resort.team)
    .map(([role, u]) => `(${lit(resort.id)}, ${lit(u!.id)}, ${lit(role)})`)
    .join(',\n  ');
  const units = resort.units
    .map(
      (u) =>
        `(${lit(u.id)}, ${lit(resort.id)}, ${lit(u.name)}, ${u.capacityBase ?? 2}, ${u.capacityMax ?? 4}, 'nightly')`,
    )
    .join(',\n  ');
  const rates = resort.units
    .map(
      (u) =>
        `(${lit(u.id)}, 'base', 'Weekday', ${u.nightlyRate}, 500, ${u.cleaningFee ?? 500}, 0, null),\n  ` +
        `(${lit(u.id)}, 'weekend', 'Weekend', ${u.nightlyRate}, 500, ${u.cleaningFee ?? 500}, 10, array[6,7])`,
    )
    .join(',\n  ');
  const num = (n: number | undefined) => (n === undefined ? 'null' : String(n));
  return `
insert into public.properties
  (id, name, slug, description, address, city, status, amenities, advance_pct, lat, lng)
values
  (${lit(resort.id)}, ${lit(resort.name)}, ${lit(resort.slug)},
   ${lit(resort.description ?? 'Fixture resort for the Playwright suite. Deleted after every run.')},
   ${lit(resort.address ?? 'E2E Lane, Testville')}, ${resort.city ? lit(resort.city) : 'null'}, 'active',
   array[${(resort.amenities ?? ['Pool']).map(lit).join(', ')}]::text[],
   ${resort.advancePct ?? 100}, ${num(resort.lat)}, ${num(resort.lng)});

insert into public.resort_subscriptions (property_id, tier, status)
values (${lit(resort.id)}, 'starter', 'active');
${members ? `\ninsert into public.resort_members (property_id, user_id, role) values\n  ${members};\n` : ''}
insert into public.units (id, property_id, name, capacity_base, capacity_max, booking_mode) values
  ${units};

insert into public.rate_rules
  (unit_id, kind, label, price, extra_guest_price, cleaning_fee, priority, weekdays)
values
  ${rates};
`;
}

/** Creates [users], then [resorts], in one transaction. */
export function createFixtures(users: FixtureUser[], resorts: KitResort[]): void {
  runSql(['begin;', users.length ? createUsersSql(users) : '', ...resorts.map(createResortSql), 'commit;'].join('\n'));
}

/**
 * Removes the resorts with [slugs] and the accounts [users] with
 * everything hanging off them (fixtures/sql.ts's teardown, scoped).
 * Idempotent.
 */
export function removeFixtures(slugs: string[], users: FixtureUser[]): void {
  runSql(scopedTeardownSql(slugs, users.map((u) => u.email)));
}

/**
 * Runs [sql] as [who] through PostgREST's roles: `authenticated` with
 * their JWT claims, so RLS and every security definer check apply exactly
 * as in the app. Returns psql's output.
 */
export function runSqlAs(who: FixtureUser, sql: string): string {
  return runSql(`
begin;
set local role authenticated;
set local request.jwt.claims to '{"sub":"${who.id}","role":"authenticated"}';
${sql}
commit;
`);
}

/** One value from a single-row, single-column query (psql -A -t style). */
export function sqlValue(sql: string): string {
  const out = runSql(`\\pset tuples_only on\n\\pset format unaligned\n${sql}`);
  return out.trim().split('\n').filter((l) => !l.startsWith('Tuples only') && !l.startsWith('Output format')).pop() ?? '';
}
