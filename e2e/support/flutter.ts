// Waiting on the Flutter web app. Flutter paints to a canvas; the only DOM
// Playwright can query is the semantics tree (<flt-semantics> elements with
// ARIA roles and labels), which the E2E build turns on at startup
// (lib/core/e2e_semantics.dart).

import { expect, type Locator, type Page } from '@playwright/test';

/**
 * Resolves once Flutter has rendered a real screen: the semantics host has
 * at least one node with a role (a button, a text field, or a heading --
 * Flutter web renders a `header` node as a bare `<h1>`..`<h6>`, not an
 * `flt-semantics[role]`, which is all a screen like NotFoundScreen has) and
 * the router has left `/splash`.
 */
export async function waitForFlutter(page: Page, timeout = 30_000): Promise<void> {
  await page
    .locator(
      [
        'flt-semantics-host flt-semantics[role]',
        'flt-semantics-host input[aria-label]',
        'flt-semantics-host :is(h1, h2, h3, h4, h5, h6)',
      ].join(', '),
    )
    .first()
    .waitFor({ state: 'attached', timeout });
  await expect.poll(() => currentPath(page), { timeout }).not.toBe('/splash');
}

/** Loads the app at [path] (a router path such as `/login`) and waits for it. */
export async function openApp(page: Page, path = '/'): Promise<void> {
  await page.goto(`/#${path}`);
  await waitForFlutter(page);
}

/**
 * The router path the app is showing: the URL's hash (the app uses
 * Flutter's default hash URL strategy), without any query string.
 */
export function currentPath(page: Page): string {
  const hash = new URL(page.url()).hash.replace(/^#/, '');
  return (hash || '/').split('?')[0];
}

/**
 * Types [value] into a Flutter text field and makes sure the app, not just
 * the DOM, has it.
 *
 * A Flutter web text field is a semantics <input>, but Flutter only listens
 * to it once the framework has focused the field, which takes a round trip
 * after the click. A value filled before that shows in the DOM and then
 * silently vanishes when focus moves on (Flutter rewrites the <input> from
 * its own, empty, state). So this clicks, waits a beat, fills, blurs, and
 * checks the value survived the blur -- retrying until it does.
 */
export async function fillField(field: Locator, value: string, timeout = 20_000): Promise<void> {
  await expect(async () => {
    await field.click();
    await expect(field).toBeFocused({ timeout: 1_000 });
    await field.page().waitForTimeout(150);
    await field.fill(value);
    await field.blur();
    // Give Flutter time to rewrite the <input> if it never saw the value.
    await field.page().waitForTimeout(250);
    await expect(field).toHaveValue(value, { timeout: 500 });
  }).toPass({ timeout, intervals: [250, 500, 1_000] });
}
