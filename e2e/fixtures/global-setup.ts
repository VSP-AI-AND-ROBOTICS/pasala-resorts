// Playwright globalSetup: (re)creates the fixture world in world.ts. Any
// leftovers from an earlier, interrupted run are removed first, in the same
// transaction.

import { runSql } from './db.ts';
import { setupSql } from './sql.ts';

export default function globalSetup(): void {
  runSql(setupSql());
}
