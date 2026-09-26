// OTA sync status (P9), admin: import feeds show when they last synced
// and what came of it. A feed added through the OTA screen is synced with
// "Sync now" for real: the database fetches it (pg_net) from a small HTTP
// server this spec runs, serving a calendar shaped like an Airbnb export
// (CRLF, folded lines, all-day "Reserved" / "Airbnb (Not available)"
// events). A second feed whose link the OTA no longer serves shows its
// error, with what to do about it.
//
// The server listens on the host's loopback only; the Supabase database
// container reaches it as host.docker.internal (Docker Desktop forwards
// that to the host's localhost). Own fixture
// (support/kit.ts): one resort, one unit, its admin. Tests run in order.

import { createServer, type Server } from 'node:http';
import type { AddressInfo } from 'node:net';
import { expect, test, type Page } from '@playwright/test';
import { fillField, goTo, login, reveal, revealAndClick } from '../support/index.ts';
import { createFixtures, kitUser, removeFixtures, sqlValue, type KitResort } from '../support/kit.ts';
import { expectLine } from '../support/screen.ts';

const admin = kitUser(0xb0, 1, 'admin.ota', 'Otto OtaAdmin');

const unitId = 'e2e5b000-0000-4000-8000-000000000011';
const resort: KitResort = {
  id: 'e2e5b000-0000-4000-8000-000000000001',
  slug: 'e2e-ota',
  name: 'E2E OTA Resort',
  units: [{ id: unitId, name: 'OTA Cabin', nightlyRate: 3500 }],
  team: { admin },
};

/** yyyymmdd, [days] from today (UTC is close enough for all-day events a month out). */
function icsDate(days: number): string {
  const d = new Date();
  d.setUTCDate(d.getUTCDate() + days);
  return d.toISOString().slice(0, 10).replace(/-/g, '');
}

/** An Airbnb-style export with two future events, one UID folded over two lines. */
function airbnbIcs(): string {
  return [
    'BEGIN:VCALENDAR',
    'PRODID;X-RICAL-TZSOURCE=TZINFO:-//Airbnb Inc//Hosting Calendar 1.0//EN',
    'CALSCALE:GREGORIAN',
    'VERSION:2.0',
    'BEGIN:VEVENT',
    `DTEND;VALUE=DATE:${icsDate(33)}`,
    `DTSTART;VALUE=DATE:${icsDate(30)}`,
    'UID:e2e0fb94e984-0a1b2c3d4e5f6071',
    ' 8293a4b5c6d7e8f9@airbnb.com',
    'DESCRIPTION:Reservation URL: https://www.airbnb.com/hosting/reservations/d',
    ' etails/HMABCD1234\\nPhone Number (Last 4 Digits): 4321',
    'SUMMARY:Reserved',
    'END:VEVENT',
    'BEGIN:VEVENT',
    `DTEND;VALUE=DATE:${icsDate(47)}`,
    `DTSTART;VALUE=DATE:${icsDate(40)}`,
    'UID:e2e3e8a1c9d2b-11223344556677889900aabbccddeeff@airbnb.com',
    'SUMMARY:Airbnb (Not available)',
    'END:VEVENT',
    'END:VCALENDAR',
    '',
  ].join('\r\n');
}

let server: Server;
let base = '';

test.describe.configure({ mode: 'serial' });

test.beforeAll(async () => {
  removeFixtures([resort.slug], [admin]);
  createFixtures([admin], [resort]);
  server = createServer((req, res) => {
    if (req.url === '/airbnb.ics') {
      res.writeHead(200, { 'content-type': 'text/calendar; charset=utf-8' });
      res.end(airbnbIcs());
    } else {
      res.writeHead(404, { 'content-type': 'text/plain' });
      res.end('not found');
    }
  });
  await new Promise<void>((resolve) => server.listen(0, '127.0.0.1', resolve));
  base = `http://host.docker.internal:${(server.address() as AddressInfo).port}`;
});

test.afterAll(async () => {
  await new Promise<void>((resolve) => server?.close(() => resolve()) ?? resolve());
  removeFixtures([resort.slug], [admin]);
});

/** Opens the unit's OTA screen the way an admin does: Units, the unit's menu, OTA sync. */
async function openOtaScreen(page: Page): Promise<void> {
  await login(page, admin);
  await goTo(page, `/admin/units/${resort.id}`);
  const unitRow = page.getByRole('group', { name: /^OTA Cabin/ });
  await expect(unitRow).toBeVisible();
  await unitRow.getByRole('button', { name: 'Show menu' }).click();
  await page.getByRole('menuitem', { name: 'OTA sync', exact: true }).click();
  await expect(page.getByRole('heading', { name: 'OTA calendar sync' })).toBeVisible();
}

async function addFeed(page: Page, url: string, label: string): Promise<void> {
  await reveal(page, page.getByLabel('Calendar URL'));
  await fillField(page.getByLabel('Calendar URL'), url);
  await fillField(page.getByLabel('Label (optional)'), label);
  await revealAndClick(page, page.getByRole('button', { name: 'Add feed', exact: true }));
  await expectLine(page, label);
}

test('a new feed has never synced; Sync now fetches it and shows the last sync with its event count', async ({
  page,
}) => {
  await openOtaScreen(page);
  await expectLine(page, 'No import feeds yet -- add one below.');

  await addFeed(page, `${base}/airbnb.ics`, 'Airbnb');
  await expectLine(page, 'Never synced');

  await revealAndClick(page, page.getByRole('button', { name: 'Sync now' }).first());
  await expectLine(page, 'Synced -- 2 events', 30_000);
  // The feed's card reads as one line: label, link, then its status.
  await expectLine(page, /Airbnb .*airbnb\.ics Last sync just now · 2 events/);

  // Both events are now blocks on the unit.
  expect(
    sqlValue(`select count(*) from public.reservations where unit_id = '${unitId}' and external_uid is not null`),
  ).toBe('2');
  expect(
    sqlValue(`select last_status || ':' || last_event_count from public.ical_feeds where unit_id = '${unitId}'`),
  ).toBe('ok:2');
});

test('a feed the OTA no longer serves shows the error and how to fix it', async ({ page }) => {
  await openOtaScreen(page);
  await expectLine(page, 'Last sync');

  await addFeed(page, `${base}/removed-listing.ics`, 'Booking.com');
  await revealAndClick(page, page.getByRole('button', { name: 'Sync now' }).nth(1));
  await expectLine(page, 'Sync failed: HTTP 404', 30_000);
  await expectLine(page, /Sync failed (just now|1 min ago): HTTP 404/);
  await expectLine(page, 'The OTA no longer serves this link.');
  await expectLine(page, 'No successful sync yet');
  // The first feed still reports its good sync.
  await expectLine(page, /Airbnb .* Last sync (just now|\d+ min ago) · 2 events/);
});
