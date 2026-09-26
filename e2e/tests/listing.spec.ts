// Resort self-listing (P10), end to end across three personas:
// - a new owner taps "List your resort" on the welcome screen, signs up,
//   applies, works the setup checklist (the GSTIN step through the app,
//   the rest as that owner through the API) and submits for review;
// - guests cannot find the pending resort;
// - the platform admin sees it waiting, filters to Pending review and
//   approves it;
// - guests now find it, and its owner has a live resort (no checklist,
//   the application reads Approved).
//
// The applicant's account is created by the sign-up form, so it has no
// fixed id; it is looked up by email. Resort and accounts are removed in
// afterAll (support/kit.ts), and the slug the app derives from the name
// ("e2e-listed-resort") keeps the global teardown's e2e- sweep as a
// backstop. Tests run in order.

import { expect, test, type Page } from '@playwright/test';
import { platformAdmin, type FixtureUser } from '../fixtures/world.ts';
import { expectAt, fillField, goTo, login, openApp, reveal, revealAndClick } from '../support/index.ts';
import {
  PASSWORD,
  createFixtures,
  kitUser,
  removeFixtures,
  runSqlAs,
  sqlValue,
} from '../support/kit.ts';
import { expectLine, expectNoLine } from '../support/screen.ts';

const NAME = 'E2E Listed Resort';
const SLUG = 'e2e-listed-resort';
const GSTIN = '29ABCDE1234F1Z5';

/** Signs up through the app; its id is only known afterwards. */
const applicant: FixtureUser = {
  id: '',
  email: 'applicant.listing@e2e.resorthub.test',
  fullName: 'Lena Lister',
};
const guest = kitUser(0xe0, 1, 'guest.listing', 'Leo ListingGuest');

test.describe.configure({ mode: 'serial' });

test.beforeAll(() => {
  removeFixtures([SLUG], [applicant, guest]);
  createFixtures([guest], []);
});
test.afterAll(() => removeFixtures([SLUG], [applicant, guest]));

const propertyId = () => sqlValue(`select id from public.properties where slug = '${SLUG}'`);

/**
 * The browse card for the listed resort. A card with amenity chips is a
 * group labelled with its text; this one has no amenities, so the whole
 * card is one button named by its text.
 */
const listedCard = (page: Page) =>
  page.getByRole('group', { name: new RegExp(NAME) }).or(page.getByRole('button', { name: new RegExp(NAME) }));

test('a new owner lists a resort: welcome, sign up, apply, checklist, submit', async ({ page }) => {
  await openApp(page, '/');
  await expectAt(page, '/welcome');
  await page.getByRole('button', { name: 'List your resort', exact: true }).click();
  await expectAt(page, '/signup');

  await fillField(page.getByLabel('Full name'), applicant.fullName);
  await fillField(page.getByLabel('Email'), applicant.email);
  await fillField(page.getByLabel('Password'), PASSWORD);
  await revealAndClick(page, page.getByRole('button', { name: 'Create account', exact: true }));
  await expectAt(page, '/list-your-resort', 30_000);
  applicant.id = sqlValue(`select id from auth.users where email = '${applicant.email}'`);
  expect(applicant.id).toMatch(/^[0-9a-f-]{36}$/);

  await fillField(page.getByLabel('Resort name'), NAME);
  await fillField(page.getByLabel('City'), 'Testville');
  await fillField(page.getByLabel('Address'), '12 E2E Listing Road, Testville');
  await fillField(page.getByLabel('Contact phone'), '+919876543210');
  await fillField(page.getByLabel('Short description'), 'A quiet fixture resort for the listing test.');
  await revealAndClick(page, page.getByRole('button', { name: 'Apply', exact: true }));

  // The new resort is pending, on a 30-day trial, and the owner is on
  // /owner with its setup checklist.
  await expectAt(page, '/owner', 30_000);
  await expectLine(page, `Finish setting up ${NAME}`);
  await expectLine(page, '0 of 6 done');
  expect(sqlValue(`select status from public.properties where slug = '${SLUG}'`)).toBe('pending');
  expect(sqlValue(`select status || ':' || tier from public.resort_subscriptions where property_id = '${propertyId()}'`)).toBe(
    'trial:starter',
  );

  // The GSTIN step, through the app: its Taxes screen.
  await revealAndClick(page, page.getByRole('button', { name: /^Not done GSTIN and tax|^GSTIN and tax/ }));
  await expect(page.getByRole('heading', { name: 'Taxes' })).toBeVisible();
  await fillField(page.getByLabel('GSTIN'), GSTIN);
  await revealAndClick(page, page.getByRole('button', { name: 'Save', exact: true }));
  await expectAt(page, '/owner');
  await expectLine(page, '1 of 6 done');

  // The other five steps, as this owner through the API (RLS applies):
  // a photo, a unit with rates, payment methods, a cancellation rule.
  const id = propertyId();
  runSqlAs(
    applicant,
    `
update public.properties
   set images = array['/icons/Icon-512.png'], payment_display_methods = array['UPI','Card']
 where id = '${id}';
insert into public.units (id, property_id, name, capacity_base, capacity_max, booking_mode)
values ('e2e5e000-0000-4000-8000-000000000011', '${id}', 'Listing Lodge', 2, 4, 'nightly');
insert into public.rate_rules (unit_id, kind, label, price, extra_guest_price, cleaning_fee, priority, weekdays)
values ('e2e5e000-0000-4000-8000-000000000011', 'base', 'Weekday', 4500, 500, 500, 0, null);
insert into public.refund_rules (property_id, min_days_before, refund_pct) values ('${id}', 7, 100);
`,
  );
  await page.getByRole('button', { name: 'Refresh checklist' }).click();
  await expectLine(page, '6 of 6 done');

  await revealAndClick(page, page.getByRole('button', { name: 'Submit for review', exact: true }));
  await expectLine(page, 'Submitted for review.');
  await expectLine(page, /Submitted for review on .* We will email you when it is decided\./);
  expect(
    sqlValue(`select template || ':' || recipient from public.outbox where property_id = '${id}' order by created_at limit 1`),
  ).toBe(`listing_submitted:${applicant.email}`);
});

test('guests cannot find a resort that is waiting for review', async ({ page }) => {
  await login(page, guest);
  await expectAt(page, '/');
  await fillField(page.getByLabel('Search resorts'), NAME);
  await reveal(page, page.getByText('No resorts match your search'));
  await expect(listedCard(page)).toHaveCount(0);
});

test('the platform admin sees it waiting, filters to Pending review, and approves it', async ({ page }) => {
  await login(page, platformAdmin);
  await expectAt(page, '/platform');

  const waiting = sqlValue(
    `select count(*) from public.listing_applications where decision is null and submitted_at is not null`,
  );
  await expectLine(page, new RegExp(`Waiting for review ${waiting}\\b`));

  await revealAndClick(page, page.getByRole('checkbox', { name: 'Pending review', exact: true }));
  await fillField(page.getByLabel('Search resorts or owner emails'), NAME);
  await expectLine(page, new RegExp(`${NAME}.*Testville`));
  await expectLine(page, applicant.email);

  await revealAndClick(page, page.getByRole('button', { name: 'Approve', exact: true }));
  const dialog = page.getByRole('alertdialog');
  await expect(dialog).toContainText(`Approve ${NAME}?`);
  await dialog.getByRole('button', { name: 'Approve', exact: true }).click();
  await expectLine(page, 'No resorts are waiting for review.');

  expect(sqlValue(`select status from public.properties where slug = '${SLUG}'`)).toBe('active');
  expect(
    sqlValue(`select count(*) from public.outbox where property_id = '${propertyId()}' and template = 'listing_approved'`),
  ).toBe('1');

  // Off the Pending filter, it is an active resort like any other.
  await page.getByRole('checkbox', { name: 'Pending review', exact: true }).click();
  await expect(page.getByRole('group', { name: new RegExp(`^${NAME}`) })).toBeVisible();
  await expectNoLine(page, 'No resorts are waiting for review.');
});

test('guests now find the resort, and its owner has a live resort', async ({ page }) => {
  await login(page, guest);
  await expectAt(page, '/');
  await fillField(page.getByLabel('Search resorts'), NAME);
  await reveal(page, listedCard(page));

  // A live resort's owner gets the normal hub, without the checklist, and
  // their application reads Approved.
  await login(page, applicant);
  await expectAt(page, '/owner');
  await expectLine(page, 'Revenue this month');
  await expectNoLine(page, `Finish setting up ${NAME}`);
  await goTo(page, '/list-your-resort');
  await expectLine(page, 'Earlier applications');
  await expectLine(page, new RegExp(`${NAME}.*Approved`));
});
