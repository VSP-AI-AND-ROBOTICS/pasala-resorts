// Serving a real Edge Function to the app under test. The local stack's
// edge runtime is not part of this suite, so a spec that needs a function
// runs its deployed entry point (supabase/functions/<name>/index.ts) under
// Deno on a free loopback port, and routes the browser's calls to
// /functions/v1/<name> there. Only the public local URL and anon key are
// passed in: no Razorpay, Resend or MSG91 secret, so every function
// answers the way a deployment without those accounts does.

import { spawn, type ChildProcess } from 'node:child_process';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import type { Page } from '@playwright/test';

const FUNCTIONS_DIR = resolve(dirname(fileURLToPath(import.meta.url)), '../../supabase/functions');

/** The local stack's API URL and its public anon key (as build-app.sh). */
const LOCAL_ENV = {
  SUPABASE_URL: process.env.SUPABASE_URL ?? 'http://127.0.0.1:54321',
  SUPABASE_ANON_KEY:
    process.env.SUPABASE_ANON_KEY ??
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0',
};

export interface ServedFunction {
  name: string;
  base: string;
  stop(): Promise<void>;
}

/** Starts supabase/functions/[name]/index.ts under Deno; resolves once it listens. */
export async function serveFunction(name: string): Promise<ServedFunction> {
  const child: ChildProcess = spawn('deno', ['run', '--allow-net', '--allow-env', '--allow-read', 'index.ts'], {
    cwd: resolve(FUNCTIONS_DIR, name),
    env: {
      PATH: process.env.PATH ?? '',
      HOME: process.env.HOME ?? '',
      ...(process.env.DENO_DIR ? { DENO_DIR: process.env.DENO_DIR } : {}),
      DENO_SERVE_ADDRESS: 'tcp:127.0.0.1:0',
      NO_COLOR: '1',
      ...LOCAL_ENV,
    },
    stdio: ['ignore', 'pipe', 'pipe'],
  });

  let log = '';
  const base = await new Promise<string>((resolveBase, reject) => {
    const timer = setTimeout(() => reject(new Error(`${name} did not start:\n${log}`)), 60_000);
    const onData = (chunk: Buffer) => {
      log += chunk.toString();
      const match = log.match(/Listening on (http:\/\/127\.0\.0\.1:\d+)/);
      if (match) {
        clearTimeout(timer);
        resolveBase(match[1]);
      }
    };
    child.stdout!.on('data', onData);
    child.stderr!.on('data', onData);
    child.on('exit', (code) => {
      clearTimeout(timer);
      reject(new Error(`${name} exited (${code}):\n${log}`));
    });
  });

  return {
    name,
    base,
    stop: () =>
      new Promise<void>((done) => {
        if (child.exitCode !== null) return done();
        child.once('exit', () => done());
        child.kill();
      }),
  };
}

/** Sends [page]'s calls to /functions/v1/<name> to [fn] instead. */
export async function routeFunction(page: Page, fn: ServedFunction): Promise<void> {
  await page.route(`**/functions/v1/${fn.name}`, async (route) => {
    const response = await route.fetch({ url: `${fn.base}/` });
    await route.fulfill({ response });
  });
}
