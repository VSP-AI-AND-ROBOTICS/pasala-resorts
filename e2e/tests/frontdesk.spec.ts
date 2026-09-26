// Admin / front desk at Resort A: the daily dashboard, the bookings list,
// reception's check-in and desk check-out queues, the room status grid's
// reaction to both, and the units/rates screens (including the one guard
// that keeps a Resort A admin off a Resort B unit's rates page).
//
// Fixture data: everything here uses a dedicated guest + booking created in
// beforeAll/afterAll (support/frontdesk-data.ts), not world.ts's own
// `bookings.arrivingToday` / `bookings.checkedIn` -- see that file's header
// comment for why. The one exception is the very last test, which reads
// (but never completes checkout for) the shared `bookings.checkedIn`
// fixture to check the desk checkout survives a reload; it leaves that
// booking checked in, same as it found it.
//
// Tests 3 and 4 form one continuous, one-way workflow (confirmed -> checked
// in -> checked out) against the same `frontdeskBookingId` reservation, so
// they must run in this file's declared order -- guaranteed by
// playwright.config.ts (`fullyParallel: false`, `workers: 1`). Test 4 also
// checks the guest in itself if it isn't already (check_in_booking is
// idempotent), so it still passes standalone (e.g. `-g "desk Cash"`).

import { expect, test } from '@playwright/test';
import { bookings, resortA, resortB } from '../fixtures/world.ts';
import { expectAt, fillField, goTo, landingPath, login, reveal } from '../support/index.ts';
import {
  frontdeskBookingId,
  frontdeskGuest,
  frontdeskUnit,
  setupFrontdeskFixture,
  teardownFrontdeskFixture,
} from '../support/frontdesk-data.ts';

test.beforeAll(() => setupFrontdeskFixture());
test.afterAll(() => teardownFrontdeskFixture());

const admin = resortA.team.admin;

test('admin sees the Resort A dashboard', async ({ page }) => {
  expect(await login(page, admin)).toBe(landingPath.admin);

  const firstName = admin.fullName.split(' ')[0];
  await expect(
    page.getByText(new RegExp(`Good (Morning|Afternoon|Evening), ${firstName}`)),
  ).toBeVisible();
  for (const action of ['New Booking', 'Check-in', 'Check-out', 'Rooms']) {
    await reveal(page, page.getByRole('button', { name: action, exact: true }));
  }
});

test('admin bookings list shows the Resort A reservations', async ({ page }) => {
  await login(page, admin);
  await goTo(page, '/admin/bookings');

  await expect(page.getByRole('heading', { name: 'Bookings' })).toBeVisible();
  await expect(page.getByLabel('Search by Booking ID / Guest / Mobile')).toBeVisible();
  for (const label of ['All', 'Confirmed', 'Pending', 'Cancelled', 'Completed', 'Blocks']) {
    await expect(page.getByRole('checkbox', { name: label, exact: true })).toBeVisible();
  }
  // frontdeskGuest's booking is in the list, whatever its current status
  // (this test may run before or after the check-in/check-out tests below).
  await expect(
    page.getByRole('button', { name: new RegExp(frontdeskGuest.fullName) }),
  ).toBeVisible();
});

test('reception checks the guest in, and the room grid marks the unit occupied', async ({
  page,
}) => {
  await login(page, admin);
  await goTo(page, '/admin/check-in');

  const row = page.getByRole('group', { name: new RegExp(`^${frontdeskGuest.fullName}`) });
  await expect(row).toBeVisible();
  await row.getByRole('button', { name: 'Check In', exact: true }).click();

  // "Checked in" appears twice: the visible snackbar span and a
  // screen-reader-only live announcement -- .first() picks either happily.
  await expect(page.getByText('Checked in', { exact: true }).first()).toBeVisible();
  await expect(row).toBeHidden();

  await goTo(page, '/staff/rooms');
  const tile = page.getByRole('button', { name: new RegExp(`^${frontdeskUnit.name}`) });
  await expect(tile).toContainText('Occupied');
  await expect(tile).toContainText('Guest: Frank');
});

test('reception checks the guest out with a desk Cash payment and reference, lands back on the list with the invoice, and the room needs cleaning', async ({
  page,
}) => {
  await login(page, admin);

  // Idempotent guard so this test also passes standalone: check in first if
  // the previous test hasn't already (check_in_booking no-ops if it has).
  await goTo(page, '/admin/check-in');
  const checkInRow = page.getByRole('group', { name: new RegExp(`^${frontdeskGuest.fullName}`) });
  if (await checkInRow.isVisible().catch(() => false)) {
    await checkInRow.getByRole('button', { name: 'Check In', exact: true }).click();
    await expect(checkInRow).toBeHidden();
  }

  await goTo(page, '/admin/check-out');
  const outRow = page.getByRole('group', { name: new RegExp(`^${frontdeskGuest.fullName}`) });
  await expect(outRow).toBeVisible();
  await outRow.getByRole('button', { name: 'Check Out', exact: true }).click();

  // Desk checkout: a real balance is due (frontdesk-data.ts pays only 40%
  // up front), so the payment-method chips and reference field show.
  await expect(page.getByRole('heading', { name: 'Checkout' })).toBeVisible();
  await expect(page.getByText('Balance to pay')).toBeVisible();
  const cash = page.getByRole('checkbox', { name: 'Cash', exact: true });
  await expect(cash).toHaveAttribute('aria-checked', 'true'); // Cash is the default
  await cash.click(); // exercise the selection explicitly
  await expect(cash).toHaveAttribute('aria-checked', 'true');

  const reference = page.locator('input[aria-label*="Reference"]');
  await fillField(reference, 'UTR-FRONTDESK-0001');

  await page.getByRole('button', { name: /^Record .* and check out$/ }).click();

  // checkout_booking succeeds and reception is back on its own check-out
  // list -- not the guest's /my-stay/invoice -- with a success banner (in
  // the URL, so a reload keeps it) and the booking's invoice PDF.
  await expectAt(page, '/admin/check-out');
  await expect
    .poll(() => page.evaluate(() => window.location.hash))
    .toBe(`#/admin/check-out?checkedOut=${frontdeskBookingId}`);
  await expect(page.getByRole('heading', { name: 'Check-Out' })).toBeVisible();
  // Scoped to the semantics host: the banner is a live region, so Flutter
  // also copies its text into the hidden aria-live announcer. With its
  // Download invoice button the banner is a group, and its text is that
  // group's aria-label rather than inner text.
  const host = page.locator('flt-semantics-host');
  await expect(
    host.getByText(/Guest checked out/).or(host.locator('[aria-label*="Guest checked out"]')).first(),
  ).toBeVisible();
  await expect(outRow).toBeHidden();

  const [download] = await Promise.all([
    page.waitForEvent('download'),
    page.getByRole('button', { name: 'Download invoice', exact: true }).click(),
  ]);
  expect(download.suggestedFilename()).toMatch(/\.pdf$/);

  // checkout_booking marks the room dirty -- the grid now shows Cleaning.
  await goTo(page, '/staff/rooms');
  const tile = page.getByRole('button', { name: new RegExp(`^${frontdeskUnit.name}`) });
  await expect(tile).toContainText('Cleaning');
});

test('units and rates screens open for Resort A', async ({ page }) => {
  await login(page, admin);

  await goTo(page, `/admin/units/${resortA.id}`);
  await expect(page.getByRole('heading', { name: 'Units' })).toBeVisible();
  for (const unit of resortA.units) {
    await reveal(page, page.getByRole('group', { name: new RegExp(`^${unit.name}`) }));
  }

  await goTo(page, `/admin/rates/${frontdeskUnit.id}`);
  await expect(page.getByRole('heading', { name: 'Rates' })).toBeVisible();
  await expect(page.getByText('Base', { exact: true })).toBeVisible();
});

test('a Resort B unit\'s rates URL shows not-found for a Resort A admin', async ({ page }) => {
  await login(page, admin);

  // ResortUnitGuard (lib/features/admin/resort_unit_guard.dart) renders
  // NotFoundScreen in place without changing the URL, so `goTo`'s default
  // expectPath (the same path) still matches.
  await goTo(page, `/admin/rates/${resortB.units[0].id}`);
  await expect(page.getByText('Page not found', { exact: true })).toBeVisible();
});

// Regression: the desk checkout must survive a page reload. It used to be
// opened with `context.push`, which never puts the reservation id in the
// address bar (go_router reflects only declarative locations), and on a
// reload the router bounced a signed-in user to their landing page -- it
// treated the not-yet-loaded session as signed out, and was rebuilt from
// `/splash` once the session arrived (lib/core/router.dart routerProvider).
//
// Uses world.ts's shared `bookings.checkedIn` (Lake Villa / Hari InHouse)
// read-only: it navigates to the desk checkout screen and reloads, but
// never submits a payment, so the booking is left checked in exactly as
// this spec found it.
test(
  'the desk checkout page survives a page reload',
  async ({ page }) => {
    await login(page, admin);
    await goTo(page, '/admin/check-out');

    const row = page.getByRole('group', {
      name: new RegExp(`^${bookings.checkedIn.guest.fullName}`),
    });
    await expect(row).toBeVisible();
    await row.getByRole('button', { name: 'Check Out', exact: true }).click();
    await expect(page.getByRole('heading', { name: 'Checkout' })).toBeVisible();

    // The reservation-specific URL, so a reload can rebuild the page.
    await expect
      .poll(() => page.evaluate(() => window.location.hash))
      .toBe(`#/admin/check-out/${bookings.checkedIn.id}`);

    await page.reload();
    await expect(page.getByRole('heading', { name: 'Checkout' })).toBeVisible();
    await expect
      .poll(() => page.evaluate(() => window.location.hash))
      .toBe(`#/admin/check-out/${bookings.checkedIn.id}`);
  },
);
