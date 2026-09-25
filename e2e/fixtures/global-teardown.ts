// Playwright globalTeardown: deletes every fixture resort and account (and
// everything hanging off them). Set E2E_KEEP_FIXTURES=1 to leave them in
// place for poking at by hand; `npm run fixtures:teardown` removes them later.

import { runSql } from './db.ts';
import { teardownSql } from './sql.ts';

export default function globalTeardown(): void {
  if (process.env.E2E_KEEP_FIXTURES) return;
  runSql(teardownSql());
}
