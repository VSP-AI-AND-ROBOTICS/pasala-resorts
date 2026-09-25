import { assertEquals } from "jsr:@std/assert@^1.0.13";
import { ConfigError } from "./config.ts";
import type { DispatchDeps } from "./dispatch.ts";
import { dryConfig, emailRow, FakeStore } from "./fakes.ts";
import { bearerMatches, handleRequest, timingSafeEqual } from "./handler.ts";

function depsWith(store: FakeStore): () => DispatchDeps {
  return () => ({ config: dryConfig, store, email: null, sms: null, log: () => {} });
}

function post(authorization?: string): Request {
  const headers: Record<string, string> = {};
  if (authorization !== undefined) headers["Authorization"] = authorization;
  return new Request("http://localhost/functions/v1/outbox-dispatch", { method: "POST", headers });
}

Deno.test("only POST is accepted", async () => {
  const store = new FakeStore();
  const res = await handleRequest(
    new Request("http://localhost/functions/v1/outbox-dispatch", { method: "GET" }),
    depsWith(store),
  );
  assertEquals(res.status, 405);
  assertEquals(await res.json(), { error: "method_not_allowed" });
  assertEquals(store.claimLimits.length, 0);
});

Deno.test("a missing or wrong bearer is refused before anything is claimed", async () => {
  for (const auth of [undefined, "Bearer nope", "service-key", "Basic service-key", "Bearer service-key-x"]) {
    const store = new FakeStore();
    const res = await handleRequest(post(auth), depsWith(store));
    assertEquals(res.status, 401, String(auth));
    assertEquals(await res.json(), { error: "unauthorized" });
    assertEquals(store.claimLimits.length, 0, String(auth));
  }
});

Deno.test("the service key runs one dispatch and returns the summary", async () => {
  const store = new FakeStore();
  store.rows = [emailRow()];
  const res = await handleRequest(post("Bearer service-key"), depsWith(store));

  assertEquals(res.status, 200);
  assertEquals(await res.json(), {
    claimed: 1, sent: 0, dry_run: 1, retry: 0, failed: 0, errors: 0,
    modes: { email: "dry_run", sms: "dry_run" },
  });
});

Deno.test("missing configuration is a 500 naming the missing variable", async () => {
  const res = await handleRequest(post("Bearer service-key"), () => {
    throw new ConfigError("SUPABASE_URL is not set");
  });
  assertEquals(res.status, 500);
  assertEquals(await res.json(), { error: "not_configured", detail: "SUPABASE_URL is not set" });
});

Deno.test("a store failure is a 502", async () => {
  const store = new FakeStore();
  store.claimError = new Error("connection refused");
  const res = await handleRequest(post("Bearer service-key"), depsWith(store));
  assertEquals(res.status, 502);
  assertEquals(await res.json(), { error: "store_unavailable" });
});

Deno.test("bearerMatches is exact, with a case-insensitive scheme", () => {
  assertEquals(bearerMatches("Bearer service-key", "service-key"), true);
  assertEquals(bearerMatches("bearer service-key", "service-key"), true);
  assertEquals(bearerMatches("  Bearer   service-key  ", "service-key"), true);
  assertEquals(bearerMatches("Bearer service-ke", "service-key"), false);
  assertEquals(bearerMatches(null, "service-key"), false);
  assertEquals(bearerMatches("Bearer ", "service-key"), false);
});

Deno.test("timingSafeEqual compares whole strings", () => {
  assertEquals(timingSafeEqual("abc", "abc"), true);
  assertEquals(timingSafeEqual("abc", "abd"), false);
  assertEquals(timingSafeEqual("abc", "abcd"), false);
  assertEquals(timingSafeEqual("", ""), true);
});
