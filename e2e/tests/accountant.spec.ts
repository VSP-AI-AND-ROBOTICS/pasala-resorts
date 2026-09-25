import { readFileSync } from 'node:fs';
import { expect, test, type Locator, type Page } from '@playwright/test';
import { resortA } from '../fixtures/world.ts';
import { goTo, landingPath, login, revealAndClick, useBottomNav } from '../support/index.ts';
import {
  DESK_RESERVATION_ID,
  deskGuest,
  setupAccountantFixtures,
  teardownAccountantFixtures,
} from '../support/accountant-data.ts';

// The accountant of Resort A: lands on Finance, keeps a read-only Rooms
// grid, and works the four Finance tabs -- Today, Collections, Ledger and
// Settlements. world.ts's own two bookings are both still open, so this
// spec's own beforeAll/afterAll (accountant-data.ts) adds one settled,
// desk-paid booking too: without it Settlements would be empty and there
// would be no online-vs-desk split anywhere to see.
//
// Flutter merges a whole Card's Text children into one semantics node, so
// e.g. the Today tab's desk-collected figure reads, as one accessible
// string, "Desk collected ₹3,000.00 Cash ₹3,000.00 Card ₹0.00 …" -- label
// and value are never separate DOM nodes. That merged string is also the
// most reliable thing to assert on (getByText locators risk matching an
// ancestor and a descendant at once and failing Playwright's strict mode),
// so every check here reads the whole semantics tree as an array of lines
// and matches within one line, rather than chaining locators.
//
// Every test calls useBottomNav first (a no-op on the phone project): the accountant's bottom
// navigation bar (Finance/Rooms/Dashboard/Reports) and the Card layout of
// Collections/Ledger/Settlements (as opposed to their wide-screen
// DataTable, whose cells really are separate nodes) only render below the
// 840px breakpoint -- see nav.ts's useBottomNav.

const accountant = resortA.team.accountant;

/**
 * The semantics tree's whole visible text, one entry per merged node, in
 * document order -- Flutter has no other DOM for a screen reader (or this)
 * to read. `line.startsWith(x)` / `line.includes(x)` is how to find a
 * given figure; a figure's label and its value are almost always in the
 * same entry, not adjacent ones.
 */
async function bodyLines(page: Page): Promise<string[]> {
  const text = await page.locator('flt-semantics-host').innerText();
  // A card that also holds a button (the Settlements row's "Invoice PDF")
  // is a group whose merged text is its aria-label, not its inner text.
  const groups = await page
    .locator('flt-semantics-host [role="group"][aria-label]')
    .evaluateAll((els) => els.map((e) => e.getAttribute('aria-label') ?? ''));
  return [
    ...text.split('\n').map((l) => l.trim()),
    ...groups.map((l) => l.replace(/\s+/g, ' ').trim()),
  ].filter(Boolean);
}

/** Clicks [button], returns the download's file name and first five bytes. */
async function downloadVia(page: Page, button: Locator): Promise<{ name: string; head: string }> {
  const [download] = await Promise.all([page.waitForEvent('download'), revealAndClick(page, button)]);
  const path = await download.path();
  expect(path).toBeTruthy();
  return {
    name: download.suggestedFilename(),
    head: readFileSync(path!).subarray(0, 5).toString('latin1'),
  };
}

/**
 * Clicks one of the Finance tabs and waits until `isReady` finds a line of
 * its own content (or its own empty-state line). `.click()` resolves as
 * soon as the event is dispatched, well before the TabBarView's switch
 * animation finishes and the new tab's semantics commit, so reading
 * bodyLines() right after a bare click can still see the tab it just left
 * -- this is what made these tabs' own tests flaky. Returns the settled
 * lines so the caller need not read them again.
 */
async function switchFinanceTab(
  page: Page,
  name: string,
  isReady: (lines: string[]) => boolean,
): Promise<string[]> {
  await page.getByRole('tab', { name, exact: true }).click();
  let lines: string[] = [];
  await expect
    .poll(
      async () => {
        lines = await bodyLines(page);
        return isReady(lines);
      },
      { message: `waiting for the ${name} tab's own content` },
    )
    .toBe(true);
  return lines;
}

test.describe('Accountant (Resort A)', () => {
  test.beforeAll(() => setupAccountantFixtures());
  test.afterAll(() => teardownAccountantFixtures());

  test('lands on Finance, with the accountant bottom bar (no Today)', async ({ page }) => {
    expect(await login(page, accountant)).toBe(landingPath.accountant);
    await expect(page.getByRole('heading', { name: 'Finance' })).toBeVisible();

    await useBottomNav(page);
    for (const label of ['Finance', 'Rooms', 'Dashboard', 'Reports']) {
      await expect(page.getByRole('tab', { name: label, exact: true })).toBeVisible();
    }
    // The Finance screen's own top tab bar has its own "Today" tab
    // (Today / Collections / Ledger / Settlements) -- this asserts there
    // isn't a *second* one from the bottom nav, rather than that the word
    // never appears on screen at all.
    await expect(page.getByRole('tab', { name: 'Today', exact: true })).toHaveCount(1);
  });

  test('Today tab shows the online vs. front-desk collection split', async ({ page }) => {
    await login(page, accountant);
    await useBottomNav(page);

    // financeSummaryProvider fetches after the first frame, so the figures
    // can still say "Still loading" for a moment after landing.
    let lines: string[] = [];
    await expect
      .poll(
        async () => {
          lines = await bodyLines(page);
          return lines.some((l) => l.startsWith('Online collected'));
        },
        { message: 'waiting for the Today figures to load' },
      )
      .toBe(true);

    // Both channels have money today: the fixture bookings' own advance
    // payments (online) and accountant-data.ts's desk-paid booking (cash).
    const onlineLine = lines.find((l) => l.startsWith('Online collected'));
    const deskLine = lines.find((l) => l.startsWith('Desk collected'));
    expect(deskLine, `no "Desk collected" figure, got:\n${lines.join('\n')}`).toBeDefined();
    expect(onlineLine).toMatch(/^Online collected ₹[1-9]/);
    expect(deskLine).toMatch(/^Desk collected ₹[1-9]/);
    expect(deskLine).toMatch(/Cash ₹[1-9]/);
  });

  test('Collections and Ledger render real data for the month', async ({ page }) => {
    await login(page, accountant);
    await useBottomNav(page);

    let lines = await switchFinanceTab(
      page,
      'Collections',
      (ls) => ls.includes('No collections in this period') || ls.some((l) => l.startsWith('Total Online')),
    );
    expect(lines).not.toContain('No collections in this period');
    // The desk-paid booking's cash balance shows up in this month's
    // Collections alongside the online advances every fixture booking has.
    const collectionsTotal = lines.find((l) => l.startsWith('Total Online'));
    expect(collectionsTotal, `no Collections total row, got:\n${lines.join('\n')}`).toBeDefined();
    expect(collectionsTotal).toMatch(/Online ₹[1-9]/);
    expect(collectionsTotal).toMatch(/Cash ₹[1-9]/);

    lines = await switchFinanceTab(
      page,
      'Ledger',
      (ls) => ls.includes('No revenue in this period') || ls.some((l) => l.startsWith('Total Room')),
    );
    expect(lines).not.toContain('No revenue in this period');
    expect(lines.some((l) => l.startsWith('Taxable ₹'))).toBe(true);
    const ledgerTotal = lines.find((l) => l.startsWith('Total Room'));
    expect(ledgerTotal, `no Ledger total row, got:\n${lines.join('\n')}`).toBeDefined();
    expect(ledgerTotal).toMatch(/Room ₹[1-9]/);
    expect(ledgerTotal).toMatch(/Taxable ₹[1-9]/);
  });

  test('Settlements shows the checked-out booking, advance vs. desk balance', async ({ page }) => {
    await login(page, accountant);
    await useBottomNav(page);

    const lines = await switchFinanceTab(
      page,
      'Settlements',
      (ls) => ls.includes('No checkouts in this period') || ls.some((l) => l.includes(deskGuest.fullName)),
    );
    expect(lines).not.toContain('No checkouts in this period');

    const row = lines.find((l) => l.includes(deskGuest.fullName));
    expect(row, `no settlement row for ${deskGuest.fullName}, got:\n${lines.join('\n')}`).toBeDefined();
    expect(row).toMatch(/Advance ₹[1-9]/);
    expect(row).toMatch(/Balance at desk ₹[1-9][\d,]*\.\d{2} \(Cash · E2E-RCPT-1\)/);
    expect(row).toContain(`Recorded by ${accountant.fullName}`);
    expect(row).toMatch(/Settled$/);
  });

  test('CSV export downloads the Today report', async ({ page }) => {
    await login(page, accountant);

    const [download] = await Promise.all([
      page.waitForEvent('download'),
      page.getByRole('button', { name: 'Export CSV', exact: true }).click(),
    ]);

    expect(download.suggestedFilename()).toMatch(
      /^e2e-a-today-\d{4}-\d{2}-\d{2}-\d{4}-\d{2}-\d{2}\.csv$/,
    );
    const path = await download.path();
    expect(path).toBeTruthy();
    const firstLine = readFileSync(path!, 'utf8').split(/\r?\n/)[0];
    expect(firstLine).toBe('E2E Resort A,GSTIN not set');

    const lines = await bodyLines(page);
    expect(lines.some((l) => l.includes('CSV exported.'))).toBe(true);
  });

  test('Collections exports a PDF next to the CSV', async ({ page }) => {
    await login(page, accountant);
    await useBottomNav(page);
    await switchFinanceTab(
      page,
      'Collections',
      (ls) => ls.includes('No collections in this period') || ls.some((l) => l.startsWith('Total Online')),
    );

    const file = await downloadVia(page, page.getByRole('button', { name: 'Export PDF', exact: true }));

    expect(file.name).toMatch(/^e2e-a-collections-\d{4}-\d{2}-\d{2}-\d{4}-\d{2}-\d{2}\.pdf$/);
    expect(file.head).toBe('%PDF-');
    await expect
      .poll(async () => (await bodyLines(page)).some((l) => l.includes('PDF exported.')))
      .toBe(true);
  });

  test("a settlement row downloads that booking's invoice", async ({ page }) => {
    await login(page, accountant);
    await useBottomNav(page);
    await switchFinanceTab(
      page,
      'Settlements',
      (ls) => ls.includes('No checkouts in this period') || ls.some((l) => l.includes(deskGuest.fullName)),
    );

    const file = await downloadVia(page, page.getByRole('button', { name: 'Invoice PDF', exact: true }).first());

    expect(file.name).toBe('invoice-E2E-A-E2EACC00.pdf');
    expect(file.head).toBe('%PDF-');
  });

  test('the guest downloads the same invoice from their booking', async ({ page }) => {
    await login(page, deskGuest);
    await goTo(page, `/booking-detail/${DESK_RESERVATION_ID}`);

    const file = await downloadVia(
      page,
      page.getByRole('button', { name: 'Download invoice (PDF)', exact: true }),
    );

    expect(file.name).toBe('invoice-E2E-A-E2EACC00.pdf');
    expect(file.head).toBe('%PDF-');
  });

  test('the room status grid is read-only for an accountant', async ({ page }) => {
    await login(page, accountant);
    await useBottomNav(page);

    await goTo(page, '/staff/rooms');

    let lines: string[] = [];
    await expect
      .poll(
        async () => {
          lines = await bodyLines(page);
          return lines.some((l) => l.startsWith(resortA.units[0].name));
        },
        { message: 'waiting for the room board to load' },
      )
      .toBe(true);
    for (const unit of resortA.units) {
      expect(
        lines.some((l) => l.startsWith(unit.name)),
        `no tile for ${unit.name}, got:\n${lines.join('\n')}`,
      ).toBe(true);
    }

    // No per-room action controls anywhere on the (read-only) grid: these
    // only exist once the action sheet is open, and it never opens here.
    for (const label of ['Send housekeeping', 'Check-in', 'Check-out', 'Available']) {
      await expect(page.getByRole('button', { name: label, exact: true })).toHaveCount(0);
    }

    // Tapping a tile is a no-op: no action sheet opens, so the same
    // controls are still absent and the route hasn't changed. force:true
    // because the tile's own (non-interactive, since onTap is null)
    // hit-test semantics node sits on top of its text and would otherwise
    // make Playwright refuse the click as unactionable -- exactly the
    // read-only behaviour this asserts.
    await page.getByText(resortA.units[0].name).first().click({ force: true });
    await expect(page.getByRole('button', { name: 'Send housekeeping', exact: true })).toHaveCount(
      0,
    );
    expect(page.url()).toContain('/staff/rooms');
  });
});
