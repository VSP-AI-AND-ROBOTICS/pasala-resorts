import { assertEquals, assertRejects } from "jsr:@std/assert@1";
import { RAZORPAY_API, RazorpayError, RazorpaySubscriptionsClient } from "./razorpay_subscriptions.ts";

interface Seen {
  url: string;
  method: string;
  headers: Headers;
  body: unknown;
}

function fakeFetch(status: number, body: unknown, seen: Seen[]): typeof fetch {
  return (async (input: RequestInfo | URL, init?: RequestInit) => {
    seen.push({
      url: String(input),
      method: init?.method ?? "GET",
      headers: new Headers(init?.headers),
      body: init?.body ? JSON.parse(String(init.body)) : null,
    });
    return new Response(typeof body === "string" ? body : JSON.stringify(body), {
      status,
      headers: { "Content-Type": "application/json" },
    });
  }) as typeof fetch;
}

const keys = { keyId: "rzp_test_key", keySecret: "rzp_test_secret" };
const entity = {
  id: "sub_NewSub0000001",
  plan_id: "plan_ProMonthly0001",
  status: "created",
  short_url: "https://rzp.io/i/abc",
  current_start: null,
  current_end: null,
};
const input = {
  planId: "plan_ProMonthly0001",
  totalCount: 60,
  startAt: 1790000000,
  notifyEmail: "owner@example.com",
  notes: { property_id: "p1", tier: "pro" },
};

Deno.test("create posts the subscription with Basic auth", async () => {
  const seen: Seen[] = [];
  const client = new RazorpaySubscriptionsClient(keys, fakeFetch(200, entity, seen));
  const sub = await client.create(input);
  assertEquals(sub.id, "sub_NewSub0000001");
  assertEquals(sub.short_url, "https://rzp.io/i/abc");
  assertEquals(seen[0].url, `${RAZORPAY_API}/subscriptions`);
  assertEquals(seen[0].method, "POST");
  assertEquals(seen[0].headers.get("Authorization"), `Basic ${btoa("rzp_test_key:rzp_test_secret")}`);
  assertEquals(seen[0].body, {
    plan_id: "plan_ProMonthly0001",
    total_count: 60,
    quantity: 1,
    customer_notify: 1,
    notes: { property_id: "p1", tier: "pro" },
    start_at: 1790000000,
    notify_info: { notify_email: "owner@example.com" },
  });
});

Deno.test("create leaves out start_at and notify_info when there are none", async () => {
  const seen: Seen[] = [];
  const client = new RazorpaySubscriptionsClient(keys, fakeFetch(200, entity, seen));
  await client.create({ ...input, startAt: null, notifyEmail: null });
  assertEquals(seen[0].body, {
    plan_id: "plan_ProMonthly0001",
    total_count: 60,
    quantity: 1,
    customer_notify: 1,
    notes: { property_id: "p1", tier: "pro" },
  });
});

Deno.test("cancel posts cancel_at_cycle_end as 1 or 0", async () => {
  const seen: Seen[] = [];
  const client = new RazorpaySubscriptionsClient(
    keys,
    fakeFetch(200, { ...entity, id: "sub_Old0000000001", status: "cancelled" }, seen),
  );
  await client.cancel("sub_Old0000000001", true);
  const res = await client.cancel("sub_Old0000000001", false);
  assertEquals(res.status, "cancelled");
  assertEquals(seen[0].url, `${RAZORPAY_API}/subscriptions/sub_Old0000000001/cancel`);
  assertEquals(seen[0].body, { cancel_at_cycle_end: 1 });
  assertEquals(seen[1].body, { cancel_at_cycle_end: 0 });
});

Deno.test("a Razorpay error becomes RazorpayError with its description", async () => {
  const client = new RazorpaySubscriptionsClient(
    keys,
    fakeFetch(400, { error: { code: "BAD_REQUEST_ERROR", description: "The id provided does not exist" } }, []),
  );
  const err = await assertRejects(() => client.create(input), RazorpayError);
  assertEquals(err.status, 400);
  assertEquals(err.description, "The id provided does not exist");
});

Deno.test("a network failure becomes RazorpayError with status 0", async () => {
  const failing = (() => Promise.reject(new TypeError("connection refused"))) as typeof fetch;
  const client = new RazorpaySubscriptionsClient(keys, failing);
  const err = await assertRejects(() => client.cancel("sub_Old0000000001", true), RazorpayError);
  assertEquals(err.status, 0);
  assertEquals(err.description, "connection refused");
});
