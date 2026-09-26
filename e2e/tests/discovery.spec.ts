// Guest search and discovery (P11): the search box, the sort options and
// the distance on each card. Distance needs the guest's position, so the
// browser context is granted geolocation at a fixed point (Bengaluru,
// 12.97 N 77.59 E); the location badge's reverse lookup (OpenStreetMap
// Nominatim) is answered locally, so no request leaves the machine.
// Without a position, Distance is not offered at all.
//
// Own fixture (support/kit.ts): three resorts whose names share
// "E2E Disco", at known distances from that point, with known lowest
// nightly prices and ratings, so every sort has one right order:
//   Near  ~2 km,   from ₹9,000, no reviews
//   Mid   ~48 km,  from ₹3,000, rated 3
//   Far   ~227 km, from ₹6,000, rated 5
// Every sort gives a different order from the one before it, so a list
// still showing the previous sort can never pass for the new one.

import { expect, test, type Page } from '@playwright/test';
import { runSql } from '../fixtures/db.ts';
import { expectAt, fillField, login, reveal } from '../support/index.ts';
import { TODAY, createFixtures, kitUser, lit, removeFixtures, type KitResort } from '../support/kit.ts';
import { expectLine } from '../support/screen.ts';

const HERE = { latitude: 12.97, longitude: 77.59 };

const guest = kitUser(0xf0, 1, 'guest.discovery', 'Dina Discovery');
const reviewer = kitUser(0xf0, 2, 'reviewer.discovery', 'Ravi Reviewer');

const resort = (n: number, name: string, lat: number, lng: number, price: number): KitResort => ({
  id: `e2e5f000-0000-4000-8000-00000000000${n}`,
  slug: `e2e-disco-${name.toLowerCase()}`,
  name: `E2E Disco ${name}`,
  city: 'Testville',
  amenities: ['Pool'],
  lat,
  lng,
  units: [{ id: `e2e5f000-0000-4000-8000-00000000001${n}`, name: `${name} Room`, nightlyRate: price }],
  team: {},
});

const near = resort(1, 'Near', 12.99, 77.59, 9000);
const mid = resort(2, 'Mid', 13.4, 77.59, 3000);
const far = resort(3, 'Far', 11.02, 76.96, 6000);
const all = [near, mid, far];

/** A checked-out stay at [r] with one review of [stars]. */
function reviewSql(r: KitResort, n: number, stars: number): string {
  const unitId = r.units[0].id;
  const resId = `e2e5f000-0000-4000-8000-00000000002${n}`;
  const period = `public.build_period(${lit(unitId)}, ${TODAY} - 6, ${TODAY} - 4)`;
  return `
insert into public.reservations (id, unit_id, period, kind, status, customer_id, guests, quote, source, created_by)
values (${lit(resId)}, ${lit(unitId)}, ${period}, 'booking', 'checked_out', ${lit(reviewer.id)}, 2,
        public.get_quote(${lit(unitId)}, ${period}, 2), 'app', ${lit(reviewer.id)});
insert into public.reviews (reservation_id, customer_id, farmhouse_rating, cleanliness_rating, food_rating,
                            service_rating, activities_rating, overall_rating, feedback)
values (${lit(resId)}, ${lit(reviewer.id)}, ${stars}, ${stars}, ${stars}, ${stars}, ${stars}, ${stars},
        'e2e discovery.spec.ts fixture review, ignore.');
`;
}

/** The distance search_resorts gives: haversine, R = 6371 km, from the rounded position. */
function kmLabel(r: KitResort): string {
  const rad = (d: number) => (d * Math.PI) / 180;
  const [lat1, lng1, lat2, lng2] = [HERE.latitude, HERE.longitude, r.lat!, r.lng!].map(rad);
  const a = Math.sin((lat2 - lat1) / 2) ** 2 + Math.cos(lat1) * Math.cos(lat2) * Math.sin((lng2 - lng1) / 2) ** 2;
  const km = Math.round(2 * 6371 * Math.asin(Math.min(1, Math.sqrt(a))) * 10) / 10;
  return km < 1 ? '< 1 km' : `${Math.round(km)} km`;
}

test.beforeAll(() => {
  removeFixtures(
    all.map((r) => r.slug),
    [guest, reviewer],
  );
  createFixtures([guest, reviewer], all);
  runSql(`begin;\n${reviewSql(mid, 2, 3)}\n${reviewSql(far, 3, 5)}\ncommit;`);
});
test.afterAll(() =>
  removeFixtures(
    all.map((r) => r.slug),
    [guest, reviewer],
  ),
);

/** A resort's browse card: a group named by its whole text. */
const card = (page: Page, r: KitResort) => page.getByRole('group', { name: new RegExp(r.name) });

/**
 * The fixture resorts' names in the order the list shows them. The list
 * builds cards lazily near the viewport, so this scrolls down from the
 * search box and records each name the first time it is built.
 */
async function shownOrder(page: Page): Promise<string[]> {
  await reveal(page, page.getByLabel('Search resorts'));
  const names = all.map((r) => r.name);
  const seen: string[] = [];
  for (let i = 0; i < 20 && seen.length < names.length; i++) {
    const labels = await page
      .locator('flt-semantics-host [role="group"][aria-label]')
      .evaluateAll((els) => els.map((e) => e.getAttribute('aria-label') ?? ''));
    for (const label of labels) {
      for (const name of names) if (label.includes(name) && !seen.includes(name)) seen.push(name);
    }
    const { width, height } = page.viewportSize()!;
    await page.mouse.move(width / 2, height / 2);
    await page.mouse.wheel(0, Math.round(height * 0.4));
    await page.waitForTimeout(250);
  }
  return seen;
}

/** Picks [label] in the sort menu. */
async function sortBy(page: Page, current: string, label: string): Promise<void> {
  await reveal(page, page.getByLabel('Search resorts'));
  await page.getByRole('button', { name: current, exact: true }).click();
  await page.getByRole('menuitem', { name: label, exact: true }).click();
  await expect(page.getByRole('button', { name: label, exact: true })).toBeVisible();
}

async function searchDisco(page: Page, beforeSearch?: () => Promise<void>): Promise<void> {
  await login(page, guest);
  await expectAt(page, '/');
  await beforeSearch?.();
  await fillField(page.getByLabel('Search resorts'), 'E2E Disco');
  for (const r of all) await reveal(page, card(page, r));
}

test.describe('without a location', () => {
  test('Distance is not offered and cards show no distance', async ({ page }) => {
    await searchDisco(page);
    await expect(card(page, near)).not.toHaveAccessibleName(/ km away/);
    await reveal(page, page.getByLabel('Search resorts'));
    await page.getByRole('button', { name: 'Recommended', exact: true }).click();
    for (const label of ['Recommended', 'Price: low to high', 'Rating']) {
      await expect(page.getByRole('menuitem', { name: label, exact: true })).toBeVisible();
    }
    await expect(page.getByRole('menuitem', { name: 'Distance', exact: true })).toHaveCount(0);
    await page.keyboard.press('Escape');
  });

  test('Price and Rating sort the results', async ({ page }) => {
    await searchDisco(page);
    // Each card carries its lowest nightly price, and a rating once reviewed.
    await expect(card(page, mid)).toHaveAccessibleName(/from ₹3,000 per night/);
    await expect(card(page, mid)).toHaveAccessibleName(/Rated 3\.0 out of 5 from 1 review/);
    await expect(card(page, far)).toHaveAccessibleName(/Rated 5\.0 out of 5 from 1 review/);
    // Recommended: ratings pulled toward 4 stars by three phantom reviews
    // (0060's score): Far 4.25, Near (unrated) 4, Mid 3.75.
    await expect.poll(() => shownOrder(page)).toEqual([far.name, near.name, mid.name]);

    await sortBy(page, 'Recommended', 'Price: low to high');
    await expect.poll(() => shownOrder(page)).toEqual([mid.name, far.name, near.name]);

    await sortBy(page, 'Price: low to high', 'Rating');
    // Unrated resorts come last.
    await expect.poll(() => shownOrder(page)).toEqual([far.name, mid.name, near.name]);
  });
});

test.describe('with the guest at a fixed position', () => {
  test.use({ geolocation: HERE, permissions: ['geolocation'] });

  test.beforeEach(async ({ page }) => {
    await page.route('https://nominatim.openstreetmap.org/**', (route) =>
      route.fulfill({
        contentType: 'application/json',
        body: JSON.stringify({ address: { city: 'Bengaluru', country: 'India' } }),
      }),
    );
  });

  test('the badge names the place, cards show their distance, and Distance sorts nearest first', async ({
    page,
  }) => {
    // The hero's location badge, before the list scrolls it away.
    await searchDisco(page, () => expectLine(page, 'Bengaluru, India').then(() => undefined));
    for (const r of all) {
      await expect(card(page, r)).toHaveAccessibleName(new RegExp(`${kmLabel(r)} away`));
    }
    expect(kmLabel(near)).toBe('2 km');

    await sortBy(page, 'Recommended', 'Distance');
    await expect.poll(() => shownOrder(page)).toEqual([near.name, mid.name, far.name]);

    // Search and sort work together: a narrower search keeps the sort.
    await reveal(page, page.getByLabel('Search resorts'));
    await fillField(page.getByLabel('Search resorts'), 'E2E Disco Mid');
    await reveal(page, card(page, mid));
    await expect(card(page, near)).toHaveCount(0);
    await expect(page.getByRole('button', { name: 'Distance', exact: true })).toBeVisible();
  });
});
