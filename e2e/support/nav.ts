// Moving around the app. Prefer goTo (router path) for getting somewhere and
// clickTab/getByRole for exercising the UI itself.

import { expect, type Locator, type Page } from '@playwright/test';
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

/** Flutter's wide/narrow switch: PasalaTokens.wideBreakpoint (lib/core/theme/tokens.dart). */
export const WIDE_BREAKPOINT = 840;

/** Room the NavigationBar takes at the bottom of a narrow layout. */
const BOTTOM_BAR_PX = 80;

/** True when the app is laid out as a phone: bottom navigation bar, card lists. */
export function isNarrow(page: Page): boolean {
  const size = page.viewportSize();
  return !!size && size.width < WIDE_BREAKPOINT;
}

/**
 * Makes the narrow layout render: the bottom navigation bar (role=tab; the
 * wide layout's NavigationRail is not in the semantics tree at all) and the
 * card lists that replace wide DataTables. The `phone` project already is
 * narrow, so this does nothing there. On `desktop` it narrows the width to
 * 400 -- width only: widening the height too once left a full-height
 * semantics node covering the screen and intercepting every tap.
 */
export async function useBottomNav(page: Page): Promise<void> {
  const size = page.viewportSize();
  if (size && size.width >= WIDE_BREAKPOINT) {
    await page.setViewportSize({ width: 400, height: size.height });
  }
}

/** Taps a bottom-navigation destination ("Browse", "Bookings", "Owner"...). */
export async function clickTab(page: Page, label: string): Promise<void> {
  await useBottomNav(page);
  await page.getByRole('tab', { name: label, exact: true }).click();
}

type RevealOptions = {
  /** Scroll over this element (e.g. something inside a bottom sheet) instead of the screen's centre. */
  over?: Locator;
  /** Wheel steps to try downwards before searching upwards (default 15). */
  maxScrolls?: number;
};

/**
 * Scrolls until [target] is on screen, and throws if it never gets there,
 * so it is also a visibility assertion. On a phone, much of a screen sits
 * below the fold, and Flutter builds a lazy list's children only near the
 * viewport: until scrolled to, the node is not in the semantics DOM at all,
 * and Playwright's own scroll-into-view cannot find it. "On screen" means
 * visible, its top inside the viewport, and clear of the bottom navigation
 * bar on a narrow layout. The scroll direction follows the target's box
 * when it has one; an unbuilt target is searched for downwards, then
 * upwards. At desktop size most targets are already on screen, and this
 * returns at once.
 */
export async function reveal(page: Page, target: Locator, opts: RevealOptions = {}): Promise<void> {
  const { width, height } = page.viewportSize() ?? { width: 1280, height: 800 };
  const bottom = height - (isNarrow(page) ? BOTTOM_BAR_PX : 0);
  const maxScrolls = opts.maxScrolls ?? 15;
  let direction = 1; // 1 = down, -1 = up
  for (let i = 0; i < maxScrolls * 3; i++) {
    const box = (await target.isVisible()) ? await target.boundingBox() : null;
    if (box && box.y >= 0 && box.y + Math.min(box.height, 48) <= bottom) return;
    if (box) direction = box.y < 0 ? -1 : 1;
    else if (i === maxScrolls) direction = -1;
    const anchor = opts.over ? await opts.over.boundingBox({ timeout: 5_000 }).catch(() => null) : null;
    await page.mouse.move(
      anchor ? anchor.x + anchor.width / 2 : width / 2,
      anchor ? anchor.y + anchor.height / 2 : height / 2,
    );
    await page.mouse.wheel(0, direction * Math.round(height * 0.4));
    await page.waitForTimeout(250);
  }
  throw new Error(`reveal(): ${target} never came into view (${width}x${height})`);
}

/** [reveal]s [target], then clicks it. */
export async function revealAndClick(page: Page, target: Locator, opts: RevealOptions = {}): Promise<void> {
  await reveal(page, target, opts);
  await target.click();
}
