// Front-desk check-in passes (P3): a guest's signed pass, typed into
// reception's check-in search the way a keyboard-wedge barcode scanner
// types it, opens that booking's check-in sheet. The camera path is
// checked by hand (Step 6): a headless browser has no camera to point at
// a QR.
//
// Fixture: the front-desk guest and booking from support/frontdesk-data.ts
// (confirmed, arriving tomorrow). frontdesk.spec.ts uses the same rows;
// each file creates and removes them itself, and files run one at a time
// (playwright.config.ts: workers 1), so the two never overlap. The tests
// here run in order: the second checks the guest in.

import { expect, test } from '@playwright/test';
import { runSql } from '../fixtures/db.ts';
import { resortA } from '../fixtures/world.ts';
import { fillField, goTo, login } from '../support/index.ts';
import {
  frontdeskBookingId,
  frontdeskGuest,
  setupFrontdeskFixture,
  teardownFrontdeskFixture,
} from '../support/frontdesk-data.ts';

test.beforeAll(() => setupFrontdeskFixture());
test.afterAll(() => teardownFrontdeskFixture());

const admin = resortA.team.admin;

/** The pass issue_stay_pass gives the fixture guest, as their app gets it. */
function issuePass(): string {
  const out = runSql(`
begin;
set local role authenticated;
set local request.jwt.claims to '{"sub":"${frontdeskGuest.id}","role":"authenticated"}';
select 'PASS=' || public.issue_stay_pass('${frontdeskBookingId}');
commit;
`);
  const match = out.match(/PASS=(rh1\.[A-Za-z0-9_-]{75})/);
  if (!match) throw new Error(`issue_stay_pass returned no pass:\n${out}`);
  return match[1];
}

test('a tampered pass is refused with a readable message', async ({ page }) => {
  const pass = issuePass();
  const tampered = `rh1.${pass[4] === 'A' ? 'B' : 'A'}${pass.slice(5)}`;

  await login(page, admin);
  await goTo(page, '/admin/check-in');
  await fillField(page.getByLabel('Booking code, name or phone'), tampered);
  await page.getByRole('button', { name: 'Open pass' }).click();

  await expect(page.getByText('This is not a valid check-in pass.').first()).toBeVisible();
  await expect(page.getByText('Pass verified')).toBeHidden();
});

test("a guest's pass opens their check-in and checks them in", async ({ page }) => {
  const pass = issuePass();

  await login(page, admin);
  await goTo(page, '/admin/check-in');
  await fillField(page.getByLabel('Booking code, name or phone'), pass);
  await page.getByRole('button', { name: 'Open pass' }).click();

  await expect(page.getByText('Pass verified')).toBeVisible();
  await page.getByRole('button', { name: 'Check in guest', exact: true }).click();

  // The visible snackbar and a screen-reader live region: .first() takes either.
  await expect(page.getByText('Checked in', { exact: true }).first()).toBeVisible();
  await expect(
    page.getByRole('group', { name: new RegExp(`^${frontdeskGuest.fullName}`) }),
  ).toBeHidden();
});
