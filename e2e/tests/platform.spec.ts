import { expect, test, type Locator, type Page } from '@playwright/test';
import { guests, platformAdmin, resortA, resortB, resortS } from '../fixtures/world.ts';
import { fillField, landingPath, login, waitForFlutter } from '../support/index.ts';
import { deleteResortsBySlug, slugFor } from '../support/platform-data.ts';

// The platform console (REQ-08): the totals cards, the search and tier
// filter, changing a resort's plan, suspending/reactivating a resort,
// "+ Add resort", and that the console never shows a guest's name, email
// or booking details.
//
// Every test logs in as the platform admin fresh (a new browser context
// per test) and restores anything it changes in the shared fixture world
// (resort B's plan/status, or a resort it created) before it ends, so the
// suite is safe to run in any order or a subset, alongside the other spec
// files that share this database.
//
// Selector note: a resort card is a single semantics `group` whose
// accessible name joins its name, owner emails, plan line and booking
// summary -- none of that is separate visible text, so it's asserted on
// via the group's accessible name (getByRole's `name` filter, or
// toHaveAccessibleName), never toContainText.

const escapeRegExp = (s: string): string => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

/** The one resort card whose accessible name starts with [name]. */
const resortCard = (page: Page, name: string): Locator =>
  page.getByRole('group', { name: new RegExp(`^${escapeRegExp(name)}`) });

/** The tier filter and the plan dialog's tier field both show one of these. */
const TIER_TRIGGER_LABELS = /^(All Tiers|Starter|Pro|Enterprise)$/;

/** Opens a tier-style dropdown/menu trigger and picks [label] from it. */
async function chooseFromMenu(page: Page, trigger: Locator, label: string): Promise<void> {
  await trigger.click();
  const item = page.getByRole('menuitem', { name: label, exact: true });
  await expect(item).toBeVisible();
  await item.click();
}

/** Filters the console's resort list via the search box. */
async function searchFor(page: Page, query: string): Promise<void> {
  await fillField(page.getByLabel('Search resorts or owner emails'), query);
}

/**
 * Whether [locator] becomes visible within [timeout] -- a bounded,
 * non-throwing presence check for an optional element (e.g. a button that
 * only appears in one branch of a dialog's state). A plain one-shot
 * `isVisible()` is unsafe for this: it doesn't wait, so it can catch the
 * element mid-render and report "absent" when it is only rendering late.
 */
async function isPresent(locator: Locator, timeout = 3_000): Promise<boolean> {
  try {
    await expect(locator).toBeVisible({ timeout });
    return true;
  } catch {
    return false;
  }
}

/** Clears the plan dialog's "Paid until" date, if one is currently set. */
async function clearPaidThroughIfSet(page: Page): Promise<void> {
  const clearDate = page.getByRole('button', { name: 'No end date', exact: true });
  if (await isPresent(clearDate)) {
    await clearDate.click();
  }
}

test.describe('platform console', () => {
  test.beforeEach(async ({ page }) => {
    const landing = await login(page, platformAdmin);
    expect(landing).toBe(landingPath.platformAdmin);
  });

  test('lands on /platform with the totals cards showing numbers', async ({ page }) => {
    await expect(page.getByRole('heading', { name: 'Platform', exact: true })).toBeVisible();
    await expect(page.getByText(/Subscribed resorts\s+\d+/)).toBeVisible();
    await expect(page.getByText(/Active subscriptions\s+\d+/)).toBeVisible();
    await expect(page.getByText(/MRR\s+₹[\d,]+/)).toBeVisible();
  });

  test('the tier filter narrows the resort list to the chosen tier', async ({ page }) => {
    // Narrow to just the three fixture resorts first, so this test's
    // assertions don't depend on how many other resorts the database
    // happens to hold (the real tenant, or another spec's fixtures).
    await searchFor(page, 'E2E Resort'); // matches only Resort A, B and S
    const cardA = resortCard(page, resortA.name); // Enterprise
    const cardB = resortCard(page, resortB.name); // Starter
    const cardS = resortCard(page, resortS.name); // Pro
    await expect(cardA).toBeVisible();
    await expect(cardB).toBeVisible();
    await expect(cardS).toBeVisible();

    const trigger = page.getByRole('button', { name: TIER_TRIGGER_LABELS });

    await chooseFromMenu(page, trigger, 'Enterprise');
    await expect(cardA).toBeVisible();
    await expect(cardB).toBeHidden();
    await expect(cardS).toBeHidden();

    await chooseFromMenu(page, trigger, 'Starter');
    await expect(cardB).toBeVisible();
    await expect(cardA).toBeHidden();
    await expect(cardS).toBeHidden();

    await chooseFromMenu(page, trigger, 'Pro');
    await expect(cardS).toBeVisible();
    await expect(cardA).toBeHidden();
    await expect(cardB).toBeHidden();

    await chooseFromMenu(page, trigger, 'All Tiers');
    await expect(cardA).toBeVisible();
    await expect(cardB).toBeVisible();
    await expect(cardS).toBeVisible();
  });

  test('the search box filters resorts by name', async ({ page }) => {
    const cardA = resortCard(page, resortA.name);
    const cardB = resortCard(page, resortB.name);

    await searchFor(page, resortA.name);
    await expect(cardA).toBeVisible();
    await expect(cardB).toBeHidden();

    await searchFor(page, 'zzz-no-such-resort-zzz');
    await expect(page.getByText('No resorts match your search.')).toBeVisible();

    await searchFor(page, '');
    await expect(cardA).toBeVisible();
    await expect(cardB).toBeVisible();
  });

  test("changing a resort's tier and paid-through date is reflected on its card", async ({
    page,
  }) => {
    await searchFor(page, resortB.name);
    const card = resortCard(page, resortB.name);
    await expect(card).toBeVisible();
    await expect(card.getByRole('checkbox', { name: 'Starter', exact: true })).toBeVisible();
    await expect(card).toHaveAccessibleName(/Paid, no end date/);

    try {
      await card.getByRole('button', { name: 'Change plan', exact: true }).click();
      const dialog = page.getByRole('alertdialog');
      await expect(dialog).toBeVisible();

      await chooseFromMenu(page, page.getByRole('button', { name: /^Tier/ }), 'Pro');

      // Resort B starts with no paid-through date, so this button reads
      // "No end date" (the clear icon only appears once a date is set).
      await page.getByRole('button', { name: 'No end date', exact: true }).click();
      await expect(page.getByText(/, Today$/)).toBeVisible();
      await page.getByText(/, Today$/).click();
      await page.getByRole('button', { name: 'OK', exact: true }).click();

      await page.getByRole('button', { name: 'Save', exact: true }).click();
      await expect(dialog).toBeHidden();

      await expect(card.getByRole('checkbox', { name: 'Pro', exact: true })).toBeVisible();
      await expect(card).toHaveAccessibleName(/Paid until/);
    } finally {
      // Restore resort B's original plan: Starter, no end date.
      await card.getByRole('button', { name: 'Change plan', exact: true }).click();
      const dialog = page.getByRole('alertdialog');
      await expect(dialog).toBeVisible();
      await chooseFromMenu(page, page.getByRole('button', { name: /^Tier/ }), 'Starter');
      await clearPaidThroughIfSet(page);
      await page.getByRole('button', { name: 'Save', exact: true }).click();
      await expect(dialog).toBeHidden();
    }

    await expect(card.getByRole('checkbox', { name: 'Starter', exact: true })).toBeVisible();
    await expect(card).toHaveAccessibleName(/Paid, no end date/);
  });

  test('suspending and reactivating a resort updates its status', async ({ page }) => {
    await searchFor(page, resortB.name);
    const card = resortCard(page, resortB.name);
    await expect(card.getByRole('checkbox', { name: 'Active', exact: true })).toBeVisible();

    try {
      await card.getByRole('button', { name: 'Suspend', exact: true }).click();
      const confirm = page.getByRole('alertdialog');
      await expect(confirm).toContainText(`Suspend ${resortB.name}?`);
      await confirm.getByRole('button', { name: 'Suspend', exact: true }).click();
      await expect(confirm).toBeHidden();

      await expect(card.getByRole('checkbox', { name: 'Suspended', exact: true })).toBeVisible();
      await expect(card.getByRole('button', { name: 'Reactivate', exact: true })).toBeVisible();
    } finally {
      const reactivateBtn = card.getByRole('button', { name: 'Reactivate', exact: true });
      if (await isPresent(reactivateBtn)) {
        await reactivateBtn.click();
        const confirm = page.getByRole('alertdialog');
        await expect(confirm).toBeVisible();
        await confirm.getByRole('button', { name: 'Reactivate', exact: true }).click();
        await expect(confirm).toBeHidden();
      }
    }

    await expect(card.getByRole('checkbox', { name: 'Active', exact: true })).toBeVisible();
    await expect(card.getByRole('button', { name: 'Suspend', exact: true })).toBeVisible();
  });

  test('"+ Add resort" creates a resort for an existing fixture account', async ({ page }) => {
    const name = `E2E Add Resort ${Date.now()}`;
    const slug = slugFor(name);

    try {
      await page.getByRole('button', { name: 'Add resort', exact: true }).click();
      const dialog = page.getByRole('alertdialog');
      await expect(dialog).toBeVisible();

      await fillField(page.getByLabel('Name'), name);
      // Must belong to an existing account: a fixture guest with no
      // bookings of their own, so this doesn't disturb any other test.
      await fillField(page.getByLabel('Owner email'), guests.fresh.email);
      await dialog.getByRole('button', { name: 'Create', exact: true }).click();
      await expect(dialog).toBeHidden();

      await searchFor(page, name);
      const card = resortCard(page, name);
      await expect(card).toBeVisible();
      await expect(card).toHaveAccessibleName(new RegExp(escapeRegExp(guests.fresh.email)));
      // Default plan per new_resort_dialog.dart: Starter, 30-day trial.
      await expect(card.getByRole('checkbox', { name: 'Starter', exact: true })).toBeVisible();
      await expect(card).toHaveAccessibleName(/Trial until/);
    } finally {
      deleteResortsBySlug([slug]);
    }

    // Confirm the cleanup actually took: reload (keeps the session) and
    // check the resort is gone from a fresh fetch, not just the old list.
    await page.reload();
    await waitForFlutter(page);
    await searchFor(page, name);
    await expect(resortCard(page, name)).toBeHidden();
  });

  test('the platform admin sees no guest name, email or booking detail', async ({ page }) => {
    await expect(resortCard(page, resortA.name)).toBeVisible();

    // Guest data could leak either as plain visible text or as an
    // accessible-name-only attribute (as a resort card's own details do),
    // so check both channels rather than just page.innerText().
    const visibleText = await page.locator('flt-semantics-host').innerText();
    const labelledText = await page
      .locator('flt-semantics-host [aria-label]')
      .evaluateAll((els) => els.map((e) => e.getAttribute('aria-label')).join('\n'));
    const everything = `${visibleText}\n${labelledText}`;

    for (const guest of [guests.arriving, guests.inHouse, guests.fresh]) {
      expect(everything).not.toContain(guest.email);
      expect(everything).not.toContain(guest.fullName);
    }
    for (const unit of resortA.units) {
      expect(everything).not.toContain(unit.name);
    }
  });
});
