// The fixture world every spec runs against: who exists, where they work,
// and which bookings are already on the books. global-setup.ts writes it
// into the local database; global-teardown.ts deletes it again.
//
// The local database holds real data, so everything here is namespaced:
// accounts end in @e2e.resorthub.test and resort slugs start with "e2e-".
// Teardown deletes by those two patterns (not only by the ids below), so a
// resort or account a test creates is cleaned up too, as long as it follows
// the same naming.
//
// Dates are not fixed here: "today" is the resort's today (Asia/Kolkata),
// worked out in SQL at setup time.

/** Test-only password shared by every fixture account. Never a real one. */
export const PASSWORD = 'e2e-Only-Passw0rd!';

export const EMAIL_DOMAIN = 'e2e.resorthub.test';
export const SLUG_PREFIX = 'e2e-';

/** Build a fixture email, e.g. `email('someone')` for a signup test. */
export const email = (local: string): string => `${local}@${EMAIL_DOMAIN}`;

export type ResortRoleName = 'owner' | 'admin' | 'staff' | 'accountant';
export type Tier = 'starter' | 'pro' | 'enterprise';

export interface FixtureUser {
  id: string;
  email: string;
  fullName: string;
}

export interface FixtureUnit {
  id: string;
  name: string;
  capacityBase: number;
  capacityMax: number;
  /** Base (weekday) nightly rate in INR; weekends are 1.4x. */
  nightlyRate: number;
  cleaningFee: number;
}

export interface FixtureResort<R extends ResortRoleName = ResortRoleName> {
  id: string;
  slug: string;
  name: string;
  status: 'active' | 'suspended';
  subscription: { tier: Tier; status: 'active' };
  units: FixtureUnit[];
  team: Record<R, FixtureUser>;
}

export interface FixtureBooking {
  id: string;
  resortId: string;
  unitId: string;
  guest: FixtureUser;
  guests: number;
  status: 'confirmed' | 'checked_in';
  /** Nights relative to the resort's today: 0 = today, -1 = yesterday. */
  fromDay: number;
  toDay: number;
}

const user = (n: number, local: string, fullName: string): FixtureUser => ({
  id: `e2e10000-0000-4000-8000-${n.toString().padStart(12, '0')}`,
  email: email(local),
  fullName,
});

const unit = (
  n: number,
  name: string,
  capacityBase: number,
  capacityMax: number,
  nightlyRate: number,
): FixtureUnit => ({
  id: `e2e20000-0000-4000-8000-${n.toString().padStart(12, '0')}`,
  name,
  capacityBase,
  capacityMax,
  nightlyRate,
  cleaningFee: 500,
});

export const platformAdmin: FixtureUser = user(1, 'platform', 'Pat Platform');

export const resortA: FixtureResort = {
  id: 'e2e0000a-0000-4000-8000-000000000000',
  slug: 'e2e-a',
  name: 'E2E Resort A',
  status: 'active',
  subscription: { tier: 'enterprise', status: 'active' },
  units: [
    unit(1, 'Garden Cottage', 2, 4, 5000),
    unit(2, 'Lake Villa', 4, 8, 12000),
    unit(3, 'Tree House', 2, 3, 7000),
  ],
  team: {
    owner: user(11, 'owner.a', 'Olivia OwnerA'),
    admin: user(12, 'admin.a', 'Adam AdminA'),
    staff: user(13, 'staff.a', 'Sam StaffA'),
    accountant: user(14, 'accountant.a', 'Alice AccountantA'),
  },
};

export const resortB: FixtureResort = {
  id: 'e2e0000b-0000-4000-8000-000000000000',
  slug: 'e2e-b',
  name: 'E2E Resort B',
  status: 'active',
  subscription: { tier: 'starter', status: 'active' },
  units: [
    unit(11, 'Beach Hut', 2, 4, 4000),
    unit(12, 'Sea View Suite', 2, 5, 9000),
  ],
  team: {
    owner: user(21, 'owner.b', 'Oscar OwnerB'),
    admin: user(22, 'admin.b', 'Anna AdminB'),
    staff: user(23, 'staff.b', 'Steve StaffB'),
    accountant: user(24, 'accountant.b', 'Arun AccountantB'),
  },
};

/** Suspended by the platform admin: hidden from guests, locked for staff. */
export const resortS: FixtureResort<'owner'> = {
  id: 'e2e0000c-0000-4000-8000-000000000000',
  slug: 'e2e-s',
  name: 'E2E Resort S',
  status: 'suspended',
  subscription: { tier: 'pro', status: 'active' },
  units: [unit(21, 'Hill Cabin', 2, 4, 6000)],
  team: {
    owner: user(31, 'owner.s', 'Sofia OwnerS'),
  },
};

export const resorts = { a: resortA, b: resortB, s: resortS } as const;

export const guests = {
  /** Has a confirmed booking at Resort A arriving today (not checked in). */
  arriving: user(41, 'guest.arriving', 'Gita Arriving'),
  /** Is checked in at Resort A (arrived yesterday, leaves tomorrow). */
  inHouse: user(42, 'guest.inhouse', 'Hari InHouse'),
  /** No bookings anywhere: use for booking-flow tests. */
  fresh: user(43, 'guest.fresh', 'Farah Fresh'),
} as const;

export const bookings = {
  /** Resort A, Garden Cottage, today -> today+2, confirmed, paid in full. */
  arrivingToday: {
    id: 'e2e30000-0000-4000-8000-000000000001',
    resortId: resortA.id,
    unitId: resortA.units[0].id,
    guest: guests.arriving,
    guests: 2,
    status: 'confirmed',
    fromDay: 0,
    toDay: 2,
  },
  /** Resort A, Lake Villa, yesterday -> tomorrow, checked in, paid in full. */
  checkedIn: {
    id: 'e2e30000-0000-4000-8000-000000000002',
    resortId: resortA.id,
    unitId: resortA.units[1].id,
    guest: guests.inHouse,
    guests: 4,
    status: 'checked_in',
    fromDay: -1,
    toDay: 1,
  },
} as const satisfies Record<string, FixtureBooking>;

/** Every fixture account, for setup. */
export const allUsers: FixtureUser[] = [
  platformAdmin,
  ...Object.values(resortA.team),
  ...Object.values(resortB.team),
  ...Object.values(resortS.team),
  ...Object.values(guests),
];

/** Every fixture resort, for setup (every one has at least an owner). */
export const allResorts: FixtureResort<'owner'>[] = [resortA, resortB, resortS];
