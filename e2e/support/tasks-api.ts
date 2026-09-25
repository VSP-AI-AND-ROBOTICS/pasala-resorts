// Staff tasks through the app's own REST API (PostgREST), signed in as a
// fixture account -- the same authenticated path the app itself uses.
//
// Why not SQL (fixtures/db.ts): these run mid-suite as a real user, the
// way the app writes tasks; the SQL teardown (fixtures/sql.ts) removes any
// task still left at a fixture resort afterwards.
//
// Why not the UI: cleanup must not depend on the screens under test (the
// /admin/tasks delete flow is itself covered in tests/staff.spec.ts).

import { PASSWORD, type FixtureUser } from '../fixtures/world.ts';

/** The local stack, as build-app.sh points the app at it. */
const SUPABASE_URL = process.env.SUPABASE_URL ?? 'http://127.0.0.1:54321';
const SUPABASE_ANON_KEY =
  process.env.SUPABASE_ANON_KEY ??
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0';

async function accessToken(who: FixtureUser): Promise<string> {
  const res = await fetch(`${SUPABASE_URL}/auth/v1/token?grant_type=password`, {
    method: 'POST',
    headers: { apikey: SUPABASE_ANON_KEY, 'Content-Type': 'application/json' },
    body: JSON.stringify({ email: who.email, password: PASSWORD }),
  });
  if (!res.ok) throw new Error(`sign-in as ${who.email} failed: ${res.status} ${await res.text()}`);
  return ((await res.json()) as { access_token: string }).access_token;
}

async function rest(who: FixtureUser, method: string, path: string, body?: unknown): Promise<unknown[]> {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/${path}`, {
    method,
    headers: {
      apikey: SUPABASE_ANON_KEY,
      Authorization: `Bearer ${await accessToken(who)}`,
      'Content-Type': 'application/json',
      Prefer: 'return=representation',
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  if (!res.ok) throw new Error(`${method} ${path} as ${who.email} failed: ${res.status} ${await res.text()}`);
  return (await res.json()) as unknown[];
}

/** Creates a general task at [resortId], as [admin] (an owner/admin there). */
export async function createTask(
  admin: FixtureUser,
  resortId: string,
  assignee: FixtureUser,
  title: string,
): Promise<string> {
  const [row] = (await rest(admin, 'POST', 'tasks', {
    property_id: resortId,
    assignee_id: assignee.id,
    title,
  })) as { id: string }[];
  return row.id;
}

/** Deletes every task at [resortId], as [admin]. Returns how many it deleted. */
export async function deleteAllTasks(admin: FixtureUser, resortId: string): Promise<number> {
  return (await rest(admin, 'DELETE', `tasks?property_id=eq.${resortId}`)).length;
}
