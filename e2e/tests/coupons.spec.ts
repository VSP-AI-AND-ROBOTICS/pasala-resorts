// Coupons (P1), owner and guest: the owner creates a code on the Coupons
// screen, a guest applies it in the booking's quote sheet and pays the
// discounted total, and the owner then sees it used once and deactivates
// it -- after which the code is refused.
//
// Own fixture (support/kit.ts): one resort with one unit (no unit picker,
// full payment up front), its owner and one guest with no bookings. The
// tests run in order: each builds on the one before.

import { expect, test, type Page } from '@playwright/test';
import { pickStayDates } from '../support/booking.ts';
import { expectAt, fillField, goTo, login, reveal, revealAndClick, waitForFlutter } from '../support/index.ts';
import { createFixtures, kitUser, removeFixtures, sqlValue, type KitResort } from '../support/kit.ts';
import { expectLine } from '../support/screen.ts';

const owner = kitUser(0xc0, 1, 'owner.coupons', 'Cora CouponOwner');
const guest = kitUser(0xc0, 2, 'guest.coupons', 'Gus CouponGuest');

const resort: KitResort = {
  id: 'e2e5c000-0000-4000-8000-000000000001',
  slug: 'e2e-coupons',
  name: 'E2E Coupon Resort',
  units: [{ id: 'e2e5c000-0000-4000-8000-000000000011', name: 'Coupon Cottage', nightlyRate: 4000 }],
  team: { owner },
};

const CODE = 'E2ESAVE10';

test.describe.configure({ mode: 'serial' });

test.beforeAll(() => {
  removeFixtures([resort.slug], [owner, guest]);
  createFixtures([owner, guest], [resort]);
});
test.afterAll(() => removeFixtures([resort.slug], [owner, guest]));

/** The coupon's card on /admin/coupons: tappable, so its text is its label. */
const couponCard = (page: Page) => page.locator(`flt-semantics-host [aria-label^="${CODE}"]`).first();

test('the owner creates a 10% coupon from the owner hub', async ({ page }) => {
  await login(page, owner);
  await expectAt(page, '/owner');

  await revealAndClick(page, page.getByRole('button', { name: /^Coupons/ }));
  await expectAt(page, '/admin/coupons');
  await expectLine(page, 'No coupons yet');

  await page.getByRole('button', { name: 'New coupon', exact: true }).click();
  await fillField(page.getByLabel('Code'), CODE);
  await fillField(page.getByLabel('Discount (%)'), '10');
  await revealAndClick(page, page.getByRole('button', { name: 'Create coupon', exact: true }));

  await expectLine(page, 'Coupon created');
  await expect(couponCard(page)).toBeVisible();
  const card = (await couponCard(page).getAttribute('aria-label'))!.replace(/\s+/g, ' ');
  expect(card).toContain('Active');
  expect(card).toContain('10% off');
  expect(card).toContain('No date limits');
  expect(card).toContain('Used 0 · Everyone');
});

test('a guest applies the code in the quote sheet and pays the discounted total', async ({ page }) => {
  await login(page, guest);
  await goTo(page, `/property/${resort.id}`);
  await reveal(page, page.getByText(/Sleeps/));
  await pickStayDates(page, 4);

  const payButton = page.getByRole('button', { name: /^Pay ₹/ });
  await reveal(page, payButton);
  await expect(payButton).toBeEnabled({ timeout: 20_000 });
  await payButton.click();

  // The quote sheet: typed in lower case, sent upper case.
  const codeField = page.getByLabel('Coupon code');
  const inSheet = { over: codeField };
  await reveal(page, codeField, inSheet);
  await fillField(codeField, CODE.toLowerCase());
  await page.getByRole('button', { name: 'Apply', exact: true }).click();

  await expectLine(page, `Coupon (${CODE})`);
  // 10% of two nights at ₹4,000 plus the ₹500 cleaning fee.
  await expectLine(page, /^-₹850(\.00)?$/);
  await expectLine(page, /^₹7,650(\.00)?$/);

  await revealAndClick(page, page.getByRole('button', { name: 'Pay and confirm', exact: true }), inSheet);
  await expect.poll(() => page.url(), { timeout: 20_000 }).toMatch(/#\/booking\//);
  await waitForFlutter(page);
  await expect(page.getByRole('heading', { name: 'Booking confirmed' })).toBeVisible();

  // The booking carries the coupon, and it counts one redemption.
  expect(
    sqlValue(`select r.quote -> 'coupon' ->> 'code' from public.reservations r
               join public.units u on u.id = r.unit_id
              where u.property_id = '${resort.id}' and r.customer_id = '${guest.id}'`),
  ).toBe(CODE);
  expect(sqlValue(`select count(*) from public.coupon_redemptions where property_id = '${resort.id}'`)).toBe('1');
});

test('the owner sees the coupon used once, deactivates it, and the guest can no longer apply it', async ({
  page,
}) => {
  await login(page, owner);
  await goTo(page, '/admin/coupons');
  await expect(couponCard(page)).toHaveAttribute('aria-label', /Used 1 · Everyone/);

  await couponCard(page).getByRole('button', { name: 'Deactivate', exact: true }).click();
  await expect(page.getByRole('alertdialog')).toContainText(`Deactivate ${CODE}?`);
  await page.getByRole('alertdialog').getByRole('button', { name: 'Deactivate', exact: true }).click();
  await expectLine(page, `${CODE} deactivated`);
  await expect(couponCard(page)).toHaveAttribute('aria-label', /Inactive/);
  await expect(couponCard(page).getByRole('button', { name: 'Activate', exact: true })).toBeVisible();

  await login(page, guest);
  await goTo(page, `/property/${resort.id}`);
  await reveal(page, page.getByText(/Sleeps/));
  await pickStayDates(page, 9);
  const payButton = page.getByRole('button', { name: /^Pay ₹/ });
  await reveal(page, payButton);
  await expect(payButton).toBeEnabled({ timeout: 20_000 });
  await payButton.click();
  const codeField = page.getByLabel('Coupon code');
  await reveal(page, codeField, { over: codeField });
  await fillField(codeField, CODE);
  await page.getByRole('button', { name: 'Apply', exact: true }).click();
  // resolve_coupon's P0010, shown as written (errors.dart).
  await expectLine(page, 'coupon not found or inactive');
  await expect(page.getByText(`Coupon (${CODE})`)).toHaveCount(0);
});
