// Reading what a screen says. Flutter merges a card's texts into one
// semantics node, and a node that also holds a button (or is tappable)
// carries its text as an aria-label rather than as inner text, so neither
// getByText nor innerText alone sees everything. screenLines() reads both.

import { expect, type Page } from '@playwright/test';

/**
 * Every line of text on screen: the semantics tree's inner text, one entry
 * per line, plus every aria-label (whitespace collapsed), in document order.
 */
export async function screenLines(page: Page): Promise<string[]> {
  const host = page.locator('flt-semantics-host');
  const text = await host.innerText().catch(() => '');
  const labels = await host
    .locator('[aria-label]')
    .evaluateAll((els) => els.map((e) => e.getAttribute('aria-label') ?? ''))
    .catch(() => [] as string[]);
  return [
    ...text.split('\n').map((l) => l.trim()),
    ...labels.map((l) => l.replace(/\s+/g, ' ').trim()),
  ].filter(Boolean);
}

/**
 * Waits until some screen line matches [pattern] (a substring or a
 * RegExp) and returns that line.
 */
export async function expectLine(page: Page, pattern: string | RegExp, timeout = 15_000): Promise<string> {
  const matches = (l: string) => (typeof pattern === 'string' ? l.includes(pattern) : pattern.test(l));
  let found: string | undefined;
  let last: string[] = [];
  try {
    await expect
      .poll(
        async () => {
          last = await screenLines(page);
          found = last.find(matches);
          return found !== undefined;
        },
        { timeout },
      )
      .toBe(true);
  } catch {
    throw new Error(`no screen line matches ${pattern}; the screen says:\n${last.join('\n')}`);
  }
  return found!;
}

/** Waits until no screen line matches [pattern]. */
export async function expectNoLine(page: Page, pattern: string | RegExp, timeout = 15_000): Promise<void> {
  const matches = (l: string) => (typeof pattern === 'string' ? l.includes(pattern) : pattern.test(l));
  await expect
    .poll(async () => (await screenLines(page)).some(matches), { timeout, message: `a line still matches ${pattern}` })
    .toBe(false);
}
