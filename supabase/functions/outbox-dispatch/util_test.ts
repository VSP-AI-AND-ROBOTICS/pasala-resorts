import { assertEquals, assertRejects } from "@std/assert";
import { clip, errorText, isRetryableStatus, safeJson } from "./util.ts";
import { jsonResponse, stubFetch } from "./testing.ts";

Deno.test("safeJson returns objects and null for everything else", () => {
  assertEquals(safeJson('{"id":"x"}'), { id: "x" });
  assertEquals(safeJson("[1]"), null);
  assertEquals(safeJson('"text"'), null);
  assertEquals(safeJson("not json"), null);
  assertEquals(safeJson(""), null);
});

Deno.test("clip keeps short text and cuts long text to the limit", () => {
  assertEquals(clip("abc", 5), "abc");
  assertEquals(clip("abcdefgh", 5), "abcd…");
  assertEquals(clip("x".repeat(1200)).length, 1000);
});

Deno.test("errorText reads Error messages and stringifies the rest", () => {
  assertEquals(errorText(new Error("boom")), "boom");
  assertEquals(errorText(42), "42");
});

Deno.test("isRetryableStatus: timeouts, rate limits and server errors only", () => {
  for (const s of [408, 429, 500, 502, 503]) {
    assertEquals(isRetryableStatus(s), true, String(s));
  }
  for (const s of [400, 401, 403, 404, 422]) {
    assertEquals(isRetryableStatus(s), false, String(s));
  }
});

Deno.test("stubFetch answers in order, records requests and refuses surprises", async () => {
  const { fetch, calls } = stubFetch([jsonResponse(200, { ok: 1 })]);
  const res = await fetch("https://example.test/a", {
    method: "POST",
    headers: { "X-Key": "k" },
    body: JSON.stringify({ a: 1 }),
  });
  assertEquals(await res.json(), { ok: 1 });
  assertEquals(calls, [{
    url: "https://example.test/a",
    method: "POST",
    headers: { "x-key": "k" },
    body: { a: 1 },
  }]);
  await assertRejects(() => fetch("https://example.test/b"), Error, "unexpected fetch");
});
