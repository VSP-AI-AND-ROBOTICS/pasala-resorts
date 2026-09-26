// PERSONA: owner. Covers the Resort A owner console: the /owner landing
// page, the Team screen (list/add/re-role/remove, and the last-owner
// guard), the Settings screen's plan line (manual without Razorpay), the Rooms and Finance entry
// points, and tenant isolation on the admin bookings list.
//
// Extra fixture data (a Resort B booking, for the tenancy check) lives in
// support/owner-data.ts, created in beforeAll and deleted in afterAll --
// see that file's header for why it isn't in fixtures/world.ts.
//
// Every test signs in as the Resort A owner and leaves the team roster
// exactly as it found it, so tests can run in any order and repeatedly.

import { expect, test } from '@playwright/test';
import { guests, resortA } from '../fixtures/world.ts';
import { expectAt, fillField, goTo, landingPath, login, reveal, revealAndClick } from '../support/index.ts';
import { routeFunction, serveFunction } from '../support/functions.ts';
import { createOwnerTenancyFixture, deleteOwnerTenancyFixture, tenancyGuestB } from '../support/owner-data.ts';

const owner = resortA.team.owner;

test.beforeAll(() => {
  createOwnerTenancyFixture();
});

test.afterAll(() => {
  deleteOwnerTenancyFixture();
});

test('owner lands on /owner with the day\'s business figures', async ({ page }) => {
  expect(await login(page, owner)).toBe(landingPath.owner);

  await expect(page.getByRole('heading', { name: 'Owner' })).toBeVisible();
  const firstName = owner.fullName.split(' ')[0];
  await expect(page.getByText(new RegExp(`Good (Morning|Afternoon|Evening), ${firstName}`))).toBeVisible();
  // The two KPI cards: revenue and net profit this month, both real numbers
  // (not the "--" loading placeholder) once dashboard_summary() resolves.
  await expect(page.getByText('Revenue this month')).toBeVisible();
  await expect(page.getByText('Net profit this month')).toBeVisible();
  await expect(page.getByText(/₹[\d,]+/).first()).toBeVisible();

  // The MANAGE grid's destination tiles this spec exercises below.
  // On a phone the MANAGE grid is below the fold; reveal() scrolls to each.
  for (const tile of [/^Team/, /^Rooms/, /^Finance/, /^Settings/]) {
    await reveal(page, page.getByRole('button', { name: tile }));
  }
});

test('Team screen: lists members, adds a fixture account as staff, changes its role, removes it', async ({
  page,
}) => {
  await login(page, owner);
  await goTo(page, '/owner/team');

  // Every seeded member of Resort A is listed.
  await expect(page.getByRole('button', { name: /^Olivia OwnerA/ })).toBeVisible();
  await expect(page.getByRole('button', { name: /^Adam AdminA/ })).toBeVisible();
  await expect(page.getByRole('button', { name: /^Sam StaffA/ })).toBeVisible();
  await expect(page.getByRole('button', { name: /^Alice AccountantA/ })).toBeVisible();

  const newRow = page.getByRole('button', { name: new RegExp(`^${guests.fresh.fullName}`) });

  try {
    // Add an existing fixture account (a guest, so far a member of no
    // resort) by email. The dialog defaults its role to Staff / Incharge.
    await page.getByRole('button', { name: '', exact: true }).last().click(); // the FAB
    await fillField(page.getByLabel('Email'), guests.fresh.email);
    await page.getByRole('button', { name: 'Add', exact: true }).click();

    await expect(newRow).toBeVisible();
    await expect(newRow).toHaveAttribute('aria-label', new RegExp(`${guests.fresh.email}\\nStaff / Incharge$`));

    // Change her role: tap the row (its role value is merged into the same
    // tappable node as the name/email) to open the role popup menu, then
    // pick a different role.
    await newRow.click();
    await page.getByRole('menuitem', { name: 'Admin', exact: true }).click();
    await expect(newRow).toHaveAttribute('aria-label', new RegExp(`${guests.fresh.email}\\nAdmin$`));

    // Remove her: the row's own "Remove" icon button, then confirm the
    // dialog (its title has no separate heading role -- it's merged into
    // the same alertdialog text node as the body copy -- so match by text).
    await newRow.getByRole('button', { name: 'Remove', exact: true }).click();
    await expect(page.getByText(`Remove ${guests.fresh.fullName}?`)).toBeVisible();
    await page.getByRole('button', { name: 'Remove', exact: true }).last().click();
    await expect(newRow).toHaveCount(0);
  } finally {
    // Best-effort cleanup if an assertion above threw mid-flow: leave the
    // team exactly as this test found it either way.
    if ((await newRow.count()) > 0) {
      await newRow.getByRole('button', { name: 'Remove', exact: true }).click();
      await page.getByRole('button', { name: 'Remove', exact: true }).last().click();
      await expect(newRow).toHaveCount(0);
    }
  }
});

test('Team screen: refuses to demote the resort\'s only owner', async ({ page }) => {
  await login(page, owner);
  await goTo(page, '/owner/team');

  const ownerRow = page.getByRole('button', { name: /^Olivia OwnerA/ });
  await ownerRow.click();
  await page.getByRole('menuitem', { name: 'Admin', exact: true }).click();

  // The server's set_role raises P0023 with the bare code word `last_owner`
  // (supabase/migrations/0046_drop_global_role_helpers.sql); errors.dart maps
  // it to LastOwner's readable copy, and the raw code must never show.
  // Scoped to the semantics host: Flutter also mirrors new text into a
  // hidden <flt-announcement-polite> live region for screen readers, which
  // would otherwise make this match two elements.
  const host = page.locator('flt-semantics-host');
  await expect(host.getByText('A resort must keep at least one owner.', { exact: true })).toBeVisible();
  await expect(host.getByText('last_owner')).toHaveCount(0);

  // The demotion did not go through: the row is still Owner.
  await expect(ownerRow).toHaveAttribute('aria-label', /\nOwner$/);
});

test('Settings: the plan line shows the resort\'s subscription tier', async ({ page }) => {
  await login(page, owner);
  await goTo(page, '/owner/settings');

  await expect(page.getByRole('heading', { name: 'Settings' })).toBeVisible();
  // resortA.subscription.tier is 'enterprise' (world.ts); the screen shows
  // the tier's display label, "Enterprise" (subscription.dart's SubscriptionTierLabel).
  await expect(page.getByText('Plan: Enterprise')).toBeVisible();
});

test('Settings: without Razorpay the plan stays manual (no auto-pay card)', async ({ page }) => {
  // The real billing-subscribe, with no Razorpay keys (support/functions.ts).
  const billing = await serveFunction('billing-subscribe');
  try {
    await routeFunction(page, billing);
    await login(page, owner);
    const probe = page.waitForResponse((r) => r.url().includes('/functions/v1/billing-subscribe'));
    await goTo(page, '/owner/settings');
    expect(await (await probe).json()).toEqual({ configured: false });

    // The plan tile as the platform admin set it, and nothing to pay with.
    await expect(page.getByText('Plan: Enterprise')).toBeVisible();
    await expect(page.getByText('Paid, no end date')).toBeVisible();
    await expect(page.getByText('Auto-pay', { exact: true })).toHaveCount(0);
    await expect(page.getByRole('button', { name: 'Pay / manage subscription' })).toHaveCount(0);
  } finally {
    await billing.stop();
  }
});

test('Rooms tile opens the room status grid', async ({ page }) => {
  await login(page, owner);
  await expectAt(page, '/owner');

  await revealAndClick(page, page.getByRole('button', { name: /^Rooms/ }));
  await expectAt(page, '/staff/rooms');
  await expect(page.getByRole('heading', { name: 'Rooms' })).toBeVisible();
  // Resort A's three units are on the grid, one tile each (a tile's
  // accessible name joins its name, status and detail line -- see the
  // support/flutter.ts "Quirks" notes -- so match by prefix).
  for (const unit of resortA.units) {
    await reveal(page, page.getByRole('button', { name: new RegExp(`^${unit.name}`) }));
  }
});

test('Finance tile opens the finance tabs', async ({ page }) => {
  await login(page, owner);
  await expectAt(page, '/owner');

  await revealAndClick(page, page.getByRole('button', { name: /^Finance/ }));
  await expectAt(page, '/finance');
  await expect(page.getByRole('heading', { name: 'Finance' })).toBeVisible();
  for (const label of ['Today', 'Collections', 'Ledger', 'Settlements']) {
    await expect(page.getByRole('tab', { name: label, exact: true })).toBeVisible();
  }
});

test('tenancy: the owner of Resort A never sees a Resort B booking', async ({ page }) => {
  await login(page, owner);
  await goTo(page, '/admin/bookings');

  // Resort A's own bookings are there (sanity check the list isn't just
  // empty). Each booking card is one merged semantics node (code, status,
  // guest name and more all joined together), so match by substring.
  await expect(page.getByText(guests.arriving.fullName)).toBeVisible();
  await expect(page.getByText(guests.inHouse.fullName)).toBeVisible();

  // A guest who only ever booked Resort B never appears here.
  await expect(page.getByText(tenancyGuestB.fullName)).toHaveCount(0);
});
