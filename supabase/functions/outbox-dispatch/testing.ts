// Test-only helpers. Not a *_test.ts file and never imported by index.ts,
// so it is neither run as a test nor deployed.
import type { FetchFn } from "./types.ts";

export interface RecordedCall {
  url: string;
  method: string;
  /** Header names are lower-case (the Headers API normalises them). */
  headers: Record<string, string>;
  /** The JSON-parsed body, the raw text if it is not JSON, or null. */
  body: unknown;
}

/**
 * A fetch that answers from a queue and records every request. An empty
 * queue rejects, so an unexpected call fails the test instead of reaching
 * the network.
 */
export function stubFetch(
  answers: Array<Response | Error>,
): { fetch: FetchFn; calls: RecordedCall[] } {
  const calls: RecordedCall[] = [];
  const fetch: FetchFn = (input, init) => {
    const headers: Record<string, string> = {};
    new Headers(init?.headers).forEach((value, key) => {
      headers[key] = value;
    });
    const raw = init?.body;
    let body: unknown = raw ?? null;
    if (typeof raw === "string") {
      try {
        body = JSON.parse(raw);
      } catch {
        body = raw;
      }
    }
    calls.push({ url: input, method: init?.method ?? "GET", headers, body });
    const next = answers.shift();
    if (next === undefined) {
      return Promise.reject(new Error(`unexpected fetch to ${input}`));
    }
    return next instanceof Error ? Promise.reject(next) : Promise.resolve(next);
  };
  return { fetch, calls };
}

export function jsonResponse(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
