// Food & spa tax (P4), owner: the Taxes screen sets the food & drink and
// spa & activities rates; walk-in sales logged afterwards carry the tax
// included in their price; the Finance Ledger shows that tax per category
// with the rates; and a later rate change does not rewrite those sales.
//
// Own fixture (support/kit.ts): one resort and its owner, so Resort A's
// rates (which other specs read) never change. Tests run in order.

import { expect, test, type Page } from '@playwright/test';
import { expectAt, fillField, goTo, login, revealAndClick } from '../support/index.ts';
import { createFixtures, kitUser, removeFixtures, runSqlAs, sqlValue, type KitResort } from '../support/kit.ts';
import { expectLine } from '../support/screen.ts';

const owner = kitUser(0xa0, 1, 'owner.tax', 'Tara TaxOwner');

const resort: KitResort = {
  id: 'e2e5a000-0000-4000-8000-000000000001',
  slug: 'e2e-tax',
  name: 'E2E Tax Resort',
  units: [{ id: 'e2e5a000-0000-4000-8000-000000000011', name: 'Tax Tent', nightlyRate: 3000 }],
  team: { owner },
};

test.describe.configure({ mode: 'serial' });

test.beforeAll(() => {
  removeFixtures([resort.slug], [owner]);
  createFixtures([owner], [resort]);
});
test.afterAll(() => removeFixtures([resort.slug], [owner]));

/** Logs one walk-in sale on /owner/food-sales through the New sale form. */
async function logSale(page: Page, category: 'Food' | 'Activity', item: string, price: string): Promise<void> {
  await goTo(page, '/owner/food-sales');
  await expect(page.getByRole('heading', { name: 'Food & activity sales' })).toBeVisible();
  await page.getByRole('button', { name: '', exact: true }).last().click(); // the + button
  await expect(page.getByRole('heading', { name: 'New sale' })).toBeVisible();
  if (category === 'Activity') {
    await page.getByRole('button', { name: /^Category/ }).click();
    await page.getByRole('menuitem', { name: 'Activity', exact: true }).click();
    await expect(page.getByRole('button', { name: /^Category/ })).toHaveAccessibleName(/Activity/);
  }
  await fillField(page.getByLabel('Item'), item);
  await fillField(page.getByLabel('Quantity'), '1');
  await fillField(page.getByLabel('Unit price'), price);
  await revealAndClick(page, page.getByRole('button', { name: 'Save', exact: true }));
  await expect(page.getByRole('heading', { name: 'Food & activity sales' })).toBeVisible();
  await expectLine(page, item);
}

test('the owner sets the food & drink and spa rates on the Taxes screen', async ({ page }) => {
  await login(page, owner);
  await goTo(page, '/owner/settings');
  await revealAndClick(page, page.getByRole('button', { name: /^Taxes/ }));
  await expect(page.getByRole('heading', { name: 'Taxes' })).toBeVisible();
  await expectLine(page, 'Changing a rate affects new sales only.');

  await fillField(page.getByLabel('Food & drink tax (%)'), '5');
  await fillField(page.getByLabel('Spa & activities tax (%)'), '18');
  await revealAndClick(page, page.getByRole('button', { name: 'Save', exact: true }));
  await expect(page.getByRole('heading', { name: 'Settings' })).toBeVisible();

  expect(sqlValue(`select fnb_tax_pct::float8 || '/' || spa_tax_pct::float8 from public.properties where id = '${resort.id}'`)).toBe(
    '5/18',
  );
});

test('sales logged afterwards show their included tax in the Finance Ledger', async ({ page }) => {
  await login(page, owner);
  await logSale(page, 'Food', 'E2E Thali', '1050');
  await logSale(page, 'Activity', 'E2E Massage', '1180');

  // Each sale keeps the rate it was made at, and the tax inside its price.
  expect(
    sqlValue(`select string_agg(category || ':' || tax_pct::float8 || ':' || tax_amount, ',' order by category::text)
                from public.food_activity_sales where property_id = '${resort.id}'`),
  ).toBe('activity:18:180.00,food:5:50.00');

  await goTo(page, '/finance');
  await page.getByRole('tab', { name: 'Ledger', exact: true }).click();
  // ₹1,050 at 5% holds ₹50; ₹1,180 at 18% holds ₹180.
  await expectLine(page, 'F&B tax ₹50.00');
  await expectLine(page, 'Spa/Activities tax ₹180.00');
  await expectLine(page, 'F&B rate 5%');
  await expectLine(page, 'Spa/Activities rate 18%');
});

test('a later rate change leaves the recorded tax as it was', async ({ page }) => {
  // The owner raises the food rate (through RLS, as the app would).
  runSqlAs(owner, `update public.properties set fnb_tax_pct = 12 where id = '${resort.id}';`);

  await login(page, owner);
  await expectAt(page, '/owner');
  await goTo(page, '/finance');
  await page.getByRole('tab', { name: 'Ledger', exact: true }).click();
  await expectLine(page, 'F&B rate 12%');
  await expectLine(page, 'F&B tax ₹50.00');
});
