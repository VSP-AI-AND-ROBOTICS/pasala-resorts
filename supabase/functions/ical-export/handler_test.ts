import { assertEquals, assertStrictEquals } from "jsr:@std/assert@1";
import { handle, restStore, tokenFrom } from "./handler.ts";
import type { CalendarLookup, CalendarStore } from "./types.ts";

const TOKEN = "0123456789abcdef0123456789abcdef0123456789abcdef";
const BASE = "http://localhost:54321/functions/v1/ical-export";
const ICS = "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nEND:VCALENDAR\r\n";

class FakeStore implements CalendarStore {
  calls: string[] = [];
  constructor(private result: CalendarLookup | Error) {}
  lookup(token: string): Promise<CalendarLookup> {
    this.calls.push(token);
    return this.result instanceof Error
      ? Promise.reject(this.result)
      : Promise.resolve(this.result);
  }
}

Deno.test("tokenFrom reads <token>.ics from the path", () => {
  assertEquals(tokenFrom(new URL(`${BASE}/${TOKEN}.ics`)), TOKEN);
  assertEquals(tokenFrom(new URL(`${BASE}/${TOKEN}.ICS`)), TOKEN);
  assertEquals(tokenFrom(new URL(`http://x/ical-export/${TOKEN}`)), TOKEN);
});

Deno.test("tokenFrom falls back to ?token= at the function root", () => {
  assertEquals(tokenFrom(new URL(`${BASE}?token=${TOKEN}`)), TOKEN);
  assertEquals(
    tokenFrom(new URL(`http://x/ical-export/?token=${TOKEN}`)),
    TOKEN,
  );
});

Deno.test("tokenFrom refuses anything that is not a 48-hex token", () => {
  assertStrictEquals(tokenFrom(new URL(`${BASE}/abc.ics`)), null);
  assertStrictEquals(
    tokenFrom(new URL(`${BASE}/${TOKEN.toUpperCase()}.ics`)),
    null,
  );
  assertStrictEquals(tokenFrom(new URL(`${BASE}/${TOKEN}x.ics`)), null);
  assertStrictEquals(tokenFrom(new URL(BASE)), null);
});

Deno.test("GET serves the calendar as text/calendar", async () => {
  const store = new FakeStore({ kind: "ok", ics: ICS });
  const res = await handle(new Request(`${BASE}/${TOKEN}.ics`), store);
  assertEquals(res.status, 200);
  assertEquals(res.headers.get("content-type"), "text/calendar; charset=utf-8");
  assertEquals(res.headers.get("cache-control"), "no-cache, max-age=0");
  assertEquals(await res.text(), ICS);
  assertEquals(store.calls, [TOKEN]);
});

Deno.test("HEAD gives the same headers and no body", async () => {
  const store = new FakeStore({ kind: "ok", ics: ICS });
  const res = await handle(
    new Request(`${BASE}/${TOKEN}.ics`, { method: "HEAD" }),
    store,
  );
  assertEquals(res.status, 200);
  assertEquals(res.headers.get("content-type"), "text/calendar; charset=utf-8");
  assertEquals(await res.text(), "");
});

Deno.test("a malformed token is 404 without asking the database", async () => {
  const store = new FakeStore({ kind: "ok", ics: ICS });
  const res = await handle(new Request(`${BASE}/not-a-token.ics`), store);
  assertEquals(res.status, 404);
  assertEquals(await res.text(), "Calendar not found");
  assertEquals(store.calls, []);
});

Deno.test("an unknown token or inactive resort is 404", async () => {
  const res = await handle(
    new Request(`${BASE}/${TOKEN}.ics`),
    new FakeStore({ kind: "not_found" }),
  );
  assertEquals(res.status, 404);
  assertEquals(res.headers.get("content-type"), "text/plain; charset=utf-8");
  assertEquals(await res.text(), "Calendar not found");
});

Deno.test("a database failure is 502, and a throwing store is too", async () => {
  const quiet = console.error;
  console.error = () => {};
  try {
    const down = await handle(
      new Request(`${BASE}/${TOKEN}.ics`),
      new FakeStore({ kind: "unavailable", detail: "HTTP 500" }),
    );
    assertEquals(down.status, 502);
    assertEquals(await down.text(), "Calendar temporarily unavailable");
    const threw = await handle(
      new Request(`${BASE}/${TOKEN}.ics`),
      new FakeStore(new Error("connection refused")),
    );
    assertEquals(threw.status, 502);
    await threw.body?.cancel();
  } finally {
    console.error = quiet;
  }
});

Deno.test("any other method is 405 with Allow", async () => {
  const res = await handle(
    new Request(`${BASE}/${TOKEN}.ics`, { method: "POST", body: "x" }),
    new FakeStore({ kind: "ok", ics: ICS }),
  );
  assertEquals(res.status, 405);
  assertEquals(res.headers.get("allow"), "GET, HEAD");
  await res.body?.cancel();
});

function fakeFetch(
  status: number,
  body: unknown,
  seen: Request[],
): typeof fetch {
  return (input: RequestInfo | URL, init?: RequestInit) => {
    seen.push(new Request(input, init));
    return Promise.resolve(
      new Response(JSON.stringify(body), {
        status,
        headers: { "Content-Type": "application/json" },
      }),
    );
  };
}

Deno.test("restStore posts p_token with the anon key and unwraps the JSON string", async () => {
  const seen: Request[] = [];
  const store = restStore(
    "http://db.test/",
    "anon-key",
    fakeFetch(200, ICS, seen),
  );
  assertEquals(await store.lookup(TOKEN), { kind: "ok", ics: ICS });
  assertEquals(seen.length, 1);
  assertEquals(seen[0].method, "POST");
  assertEquals(seen[0].url, "http://db.test/rest/v1/rpc/ical_export_public");
  assertEquals(seen[0].headers.get("apikey"), "anon-key");
  assertEquals(seen[0].headers.get("authorization"), "Bearer anon-key");
  assertEquals(await seen[0].json(), { p_token: TOKEN });
});

Deno.test("restStore maps null (resort not active) and P0002 to not_found", async () => {
  assertEquals(
    await restStore("http://db.test", "k", fakeFetch(200, null, [])).lookup(
      TOKEN,
    ),
    { kind: "not_found" },
  );
  assertEquals(
    await restStore(
      "http://db.test",
      "k",
      fakeFetch(400, {
        code: "P0002",
        message: "invalid or unknown iCal token",
      }, []),
    ).lookup(TOKEN),
    { kind: "not_found" },
  );
});

Deno.test("restStore reports any other failure as unavailable", async () => {
  const result = await restStore(
    "http://db.test",
    "k",
    fakeFetch(500, { code: "XX000", message: "boom" }, []),
  ).lookup(TOKEN);
  assertEquals(result, { kind: "unavailable", detail: "HTTP 500 XX000 boom" });
});
