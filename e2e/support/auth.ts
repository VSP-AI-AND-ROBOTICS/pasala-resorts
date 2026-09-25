// Signing in and out through the real login form.

import { expect, type Page } from '@playwright/test';
import { PASSWORD, type FixtureUser } from '../fixtures/world.ts';
import { currentPath, fillField, openApp, waitForFlutter } from './flutter.ts';

/**
 * Signs in as [who] (a fixture user or an email) through the login form and
 * waits until the app has left `/login`. Returns the router path the user
 * landed on (see nav.ts landingPath). If a session is already open, it is
 * dropped first. Throws with the app's snackbar message if sign-in fails.
 */
export async function login(
  page: Page,
  who: FixtureUser | string,
  password: string = PASSWORD,
): Promise<string> {
  const emailAddress = typeof who === 'string' ? who : who.email;
  await openApp(page, '/login');
  if (currentPath(page) !== '/login') {
    // Already signed in: the router bounced /login to a landing page.
    await clearSession(page);
    await openApp(page, '/login');
  }

  await fillField(page.getByLabel('Email'), emailAddress);
  await fillField(page.getByLabel('Password'), password);
  await expect(page.getByLabel('Email')).toHaveValue(emailAddress);
  await expect(page.getByLabel('Password')).toHaveValue(password);
  await page.getByRole('button', { name: 'Sign in', exact: true }).click();

  try {
    await expect.poll(() => currentPath(page), { timeout: 20_000 }).not.toBe('/login');
  } catch {
    const snack = await page
      .locator('flt-semantics-host')
      .innerText()
      .catch(() => '');
    throw new Error(`login(${emailAddress}) stayed on /login. Screen text:\n${snack}`);
  }
  await waitForFlutter(page);
  return currentPath(page);
}

/**
 * Signs out through the UI: the app bar's "Sign out" button (owner, staff,
 * accountant, platform admin) or the "Account" sheet's "Sign out" (admin,
 * customer). Waits until the app shows a signed-out screen: signOut() goes
 * to /login, but the router then settles on /welcome, so either counts.
 */
export async function logout(page: Page): Promise<void> {
  const direct = page.getByRole('button', { name: 'Sign out', exact: true });
  // The guest browse screen has two "Account" buttons (app bar and hero).
  const account = page.getByRole('button', { name: 'Account', exact: true }).first();
  await expect(direct.or(account).first()).toBeVisible();
  if (await direct.isVisible()) {
    await direct.click();
  } else {
    await account.click();
    await page.getByRole('button', { name: 'Sign out', exact: true }).click();
  }
  await expect
    .poll(() => SIGNED_OUT_PATHS.includes(currentPath(page)), { timeout: 15_000 })
    .toBe(true);
}

/** Pre-auth screens a signed-out user can be left on. */
export const SIGNED_OUT_PATHS = ['/welcome', '/login'];

/**
 * Drops the Supabase session without the UI (clears browser storage and
 * reloads). For test setup; use logout() to test signing out.
 */
export async function clearSession(page: Page): Promise<void> {
  await page.evaluate(() => {
    window.localStorage.clear();
    window.sessionStorage.clear();
  });
  await page.reload();
  await waitForFlutter(page);
}
