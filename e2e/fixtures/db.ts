// Runs SQL against the local Supabase database through psql inside its
// Docker container, as the `postgres` role (bypasses RLS). Only the fixture
// SQL in sql.ts goes through here.

import { execFileSync } from 'node:child_process';

/** The local stack's Postgres container (`supabase start` names it). */
export const DB_CONTAINER = process.env.E2E_DB_CONTAINER ?? 'supabase_db_pasala_farm';

/** Runs [sql] in one psql session; throws with psql's stderr on any error. */
export function runSql(sql: string): string {
  try {
    return execFileSync(
      'docker',
      ['exec', '-i', DB_CONTAINER, 'psql', '-U', 'postgres', '-X', '-q', '-v', 'ON_ERROR_STOP=1'],
      { input: sql, encoding: 'utf8', stdio: ['pipe', 'pipe', 'pipe'], timeout: 120_000 },
    );
  } catch (error) {
    const stderr = (error as { stderr?: string }).stderr ?? '';
    throw new Error(`psql in ${DB_CONTAINER} failed:\n${stderr || String(error)}`);
  }
}
