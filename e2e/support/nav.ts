// Moving around the app. Prefer goTo (router path) for getting somewhere and
// clickTab/getByRole for exercising the UI itself.

import { expect, type Page } from '@playwright/test';
import type { ResortRoleName } from '../fixtures/world.ts';
import { currentPath, waitForFlutter } from './flutter.ts';

/** Where each role lands after signing in (router.dart landingPathFor). */
export const landingPath = {
  platformAdmin: '/platform',
  owner: '/owner',
  admin: '/admin',
  staff: '/staff',
  accountant: '/finance',
  customer: '/',
} as const satisfies Record<ResortRoleName | 'platformAdmin' | 'customer', string>;

/**
 * Navigates to router [path] in place, by setting the URL hash: go_router
 * picks it up without a page reload, so the session and app state stay as
 * they are (and it is much faster than page.goto). The router's redirects
 * still apply, so pass [expectPath] (default [path]) for where it should end up.
 */
export async function goTo(page: Page, path: string, expectPath: string = path): Promise<void> {
  await page.evaluate((p) => {
    window.location.hash = p;
  }, path);
  await expectAt(page, expectPath);
}

/** Asserts the router has arrived at [path] (polls; the router is async). */
export async function expectAt(page: Page, path: string, timeout = 15_000): Promise<void> {
  await expect.poll(() => currentPath(page), { timeout, message: `router path should be ${path}` }).toBe(path);
  await waitForFlutter(page);
}

/**
 * Taps a bottom-navigation destination ("Browse", "Bookings", "Owner"...).
 * Only the narrow layout (< 840px wide) exposes these as role=tab: the wide
 * layout's NavigationRail does not appear in the semantics tree at all, so
 * this helper narrows the viewport first when needed.
 */
export async function clickTab(page: Page, label: string): Promise<void> {
  const size = page.viewportSize();
  if (size && size.width >= 840) {
    await page.setViewportSize({ width: 400, height: size.height });
  }
  await page.getByRole('tab', { name: label, exact: true }).click();
}
