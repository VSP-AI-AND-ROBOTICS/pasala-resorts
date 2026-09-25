import { expect, test } from '@playwright/test';
import { resortA } from '../fixtures/world.ts';
import { expectAt, landingPath, login, logout, openApp } from '../support/index.ts';

test('welcome page shows ResortHub and Sign In', async ({ page }) => {
  await openApp(page, '/');
  await expectAt(page, '/welcome');
  await expect(page.getByText('ResortHub', { exact: true })).toBeVisible();
  await expect(page.getByRole('button', { name: 'Sign In', exact: true })).toBeVisible();
  await expect(page.getByRole('button', { name: 'Sign Up', exact: true })).toBeVisible();
});

test('the owner of Resort A signs in to the owner console', async ({ page }) => {
  const owner = resortA.team.owner;
  expect(await login(page, owner)).toBe(landingPath.owner);

  await expect(page.getByRole('heading', { name: 'Owner' })).toBeVisible();
  const firstName = owner.fullName.split(' ')[0];
  await expect(page.getByText(new RegExp(`Good (Morning|Afternoon|Evening), ${firstName}`))).toBeVisible();
  await expect(page.getByRole('button', { name: /^Business dashboard/ })).toBeVisible();
  await expect(page.getByRole('button', { name: /^Team/ })).toBeVisible();

  await logout(page);
  await expect(
    page.getByRole('button', { name: 'Sign In', exact: true }).or(page.getByLabel('Email')),
  ).toBeVisible();
});
