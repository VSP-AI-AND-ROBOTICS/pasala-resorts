// The guest's booking flow on a resort page: the dates sheet and the
// quote sheet. Shared by guest.spec.ts and the specs that book through
// the UI (coupons.spec.ts).

import type { Page } from '@playwright/test';
import { revealAndClick } from './nav.ts';

/** The date sheet's month-forward arrow ("Next month" tooltip). */
export async function clickNextMonth(page: Page): Promise<void> {
  await page.getByRole('button', { name: 'Next month', exact: true }).click();
}

/**
 * Opens the check-in/check-out sheet from the property page and picks a
 * [nights]-night stay starting [startOffsetDays] days from today, moving
 * the sheet's month forward as often as each date needs. A night already
 * booked shows as unavailable and cannot be tapped, so callers booking
 * the same unit twice must use stays that do not overlap.
 */
export async function pickStayDates(page: Page, startOffsetDays = 1, nights = 2): Promise<void> {
  await revealAndClick(page, page.getByRole('button', { name: /^Check-in/ }));

  const today = new Date();
  const checkIn = new Date(today);
  checkIn.setDate(checkIn.getDate() + startOffsetDays);
  const checkOut = new Date(checkIn);
  checkOut.setDate(checkOut.getDate() + nights);

  const monthsAhead = (d: Date) =>
    (d.getFullYear() - today.getFullYear()) * 12 + (d.getMonth() - today.getMonth());

  let shown = 0;
  for (const day of [checkIn, checkOut]) {
    const target = monthsAhead(day);
    for (; shown < target; shown++) await clickNextMonth(page);
    await page.getByRole('button', { name: String(day.getDate()), exact: true }).click();
  }
}
