import { defineConfig, devices } from '@playwright/test';

const PORT = 8790;

/**
 * Playwright drives the prebuilt Flutter web app (`./build-app.sh` writes
 * ../build/web) through Flutter's semantics DOM. Every spec shares one local
 * database and one fixture world (fixtures/world.ts), so tests run one at a
 * time by default; raise --workers only for specs that are read-only.
 * Two projects run every spec: `desktop` (1280x800, the wide layout with
 * the NavigationRail) and `phone` (a full Pixel 7: 412x839, touch, Android
 * Chrome -- the bottom navigation bar and Flutter web's mobile paths).
 * `npx playwright test --project=phone` runs one.
 */
export default defineConfig({
  testDir: './tests',
  globalSetup: './fixtures/global-setup.ts',
  globalTeardown: './fixtures/global-teardown.ts',
  fullyParallel: false,
  workers: 1,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 1 : 0,
  // Flutter's first frame (engine + main.dart.js + CanvasKit) takes a few
  // seconds on a cold cache.
  timeout: 60_000,
  expect: { timeout: 15_000 },
  reporter: [['list'], ['html', { open: 'never' }]],
  use: {
    baseURL: `http://localhost:${PORT}`,
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
  },
  projects: [
    { name: 'desktop', use: { ...devices['Desktop Chrome'], viewport: { width: 1280, height: 800 } } },
    { name: 'phone', use: { ...devices['Pixel 7'] } },
  ],
  webServer: {
    // -s: silent; -c-1: no caching, so a rebuilt app is always picked up.
    command: `npx http-server ../build/web -p ${PORT} -s -c-1`,
    url: `http://localhost:${PORT}`,
    reuseExistingServer: true,
    timeout: 30_000,
  },
});
