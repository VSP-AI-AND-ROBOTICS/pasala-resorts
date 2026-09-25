import { assertEquals } from "jsr:@std/assert@1";
import { makeSubscribeHandler, TOTAL_COUNT } from "./handler.ts";
import { FakeBillingDb, FakeRazorpay, rzpSubscription, subscribeState } from "../_shared/billing/testing.ts";
import { RazorpayError } from "../_shared/billing/razorpay_subscriptions.ts";
import { type CurrentSubscription, DbError } from "../_shared/billing/types.ts";

const PROPERTY = "11111111-1111-4111-8111-111111111111";
const CALLER = "22222222-2222-4222-8222-222222222222";
const keys = { keyId: "rzp_test_key", keySecret: "rzp_test_secret" };

function setup(withKeys = true) {
  const db = new FakeBillingDb();
  const rp = new FakeRazorpay();
  const jwts: string[] = [];
  const handler = makeSubscribeHandler({
    keys: withKeys ? keys : null,
    razorpay: () => rp,
    db: (jwt) => {
      jwts.push(jwt);
      return db;
    },
  });
  return { db, rp, jwts, handler };
}

function post(body: unknown, auth: string | null = "Bearer user-jwt"): Request {
  const headers = new Headers({ "Content-Type": "application/json" });
  if (auth) headers.set("Authorization", auth);
  return new Request("http://localhost/billing-subscribe", {
    method: "POST",
    headers,
    body: typeof body === "string" ? body : JSON.stringify(body),
  });
}

function current(overrides: Partial<CurrentSubscription> = {}): CurrentSubscription {
  return {
    razorpay_subscription_id: "sub_Current000001",
    tier: "pro",
    status: "active",
    short_url: "https://rzp.io/i/cur",
    cancel_at_cycle_end: false,
    ...overrides,
  };
}

Deno.test("answers the CORS preflight", async () => {
  const res = await setup().handler(new Request("http://localhost/billing-subscribe", { method: "OPTIONS" }));
  assertEquals(res.status, 200);
  assertEquals(res.headers.get("Access-Control-Allow-Origin"), "*");
  await res.body?.cancel();
});

Deno.test("only POST", async () => {
  const res = await setup().handler(new Request("http://localhost/billing-subscribe"));
  assertEquals(res.status, 405);
  assertEquals((await res.json()).error, "method_not_allowed");
});

Deno.test("needs a bearer token", async () => {
  const res = await setup().handler(post({ property_id: PROPERTY, action: "probe" }, null));
  assertEquals(res.status, 401);
  assertEquals((await res.json()).error, "unauthorized");
});

Deno.test("rejects a bad body", async () => {
  const { handler } = setup();
  for (
    const body of [
      "not json",
      { property_id: "p1", action: "probe" },
      { property_id: PROPERTY, action: "refund" },
      { property_id: PROPERTY, action: "subscribe" },
      { property_id: PROPERTY, action: "subscribe", tier: "free" },
    ]
  ) {
    const res = await handler(post(body));
    assertEquals(res.status, 400, JSON.stringify(body));
    assertEquals((await res.json()).error, "bad_request");
  }
});

Deno.test("without keys every action says not configured and touches nothing", async () => {
  const { handler, db, jwts, rp } = setup(false);
  for (const action of ["probe", "subscribe", "cancel"]) {
    const res = await handler(post({ property_id: PROPERTY, action, tier: "pro" }));
    assertEquals(res.status, 200);
    assertEquals(await res.json(), { configured: false });
  }
  assertEquals(jwts, []);
  assertEquals(db.calls, []);
  assertEquals(rp.created, []);
});

Deno.test("probe lists the billable plans, reading as the caller", async () => {
  const { handler, db, jwts } = setup();
  db.plans = [{ tier: "pro", name: "Pro", monthly_price_inr: 7999 }];
  const res = await handler(post({ property_id: PROPERTY, action: "probe" }));
  assertEquals(await res.json(), { configured: true, plans: [{ tier: "pro", name: "Pro", monthly_price_inr: 7999 }] });
  assertEquals(jwts, ["user-jwt"]);
});

Deno.test("subscribe with nothing current creates, records and returns the link", async () => {
  const { handler, db, rp } = setup();
  db.state = subscribeState({ start_at: 1790000000 });
  const res = await handler(post({ property_id: PROPERTY, action: "subscribe", tier: "pro" }));
  assertEquals(res.status, 200);
  assertEquals(await res.json(), {
    configured: true,
    action: "created",
    subscription_id: "sub_NewSub0000001",
    short_url: "https://rzp.io/i/new",
    status: "created",
  });
  assertEquals(db.callsTo("subscribeState"), [[PROPERTY, "pro"]]);
  assertEquals(rp.created, [{
    planId: "plan_ProMonthly0001",
    totalCount: TOTAL_COUNT,
    startAt: 1790000000,
    notifyEmail: "owner@example.com",
    notes: { property_id: PROPERTY, tier: "pro" },
  }]);
  assertEquals(db.callsTo("opened"), [[{
    property_id: PROPERTY,
    tier: "pro",
    razorpay_plan_id: "plan_ProMonthly0001",
    razorpay_subscription_id: "sub_NewSub0000001",
    status: "created",
    short_url: "https://rzp.io/i/new",
    start_at: 1790000000,
    created_by: CALLER,
  }]]);
});

Deno.test("subscribe reuses an unauthorised link for the same tier", async () => {
  const { handler, db, rp } = setup();
  db.state = subscribeState({ current: current({ status: "created" }) });
  const body = await (await handler(post({ property_id: PROPERTY, action: "subscribe", tier: "pro" }))).json();
  assertEquals(body.action, "reused");
  assertEquals(body.short_url, "https://rzp.io/i/cur");
  assertEquals(rp.created, []);
  assertEquals(db.callsTo("opened"), []);
});

Deno.test("subscribe leaves live auto-pay on the same tier unchanged", async () => {
  const { handler, db, rp } = setup();
  db.state = subscribeState({ current: current() });
  const body = await (await handler(post({ property_id: PROPERTY, action: "subscribe", tier: "pro" }))).json();
  assertEquals(body.action, "unchanged");
  assertEquals(body.subscription_id, "sub_Current000001");
  assertEquals(rp.created, []);
});

Deno.test("changing tier creates the new one, then cancels the replaced one now", async () => {
  const { handler, db, rp } = setup();
  db.state = subscribeState({ tier: "enterprise", plan_id: "plan_EnterpriseM01", current: current() });
  db.openedResult = { id: "row-2", stale: ["sub_Current000001"] };
  rp.createResult = rzpSubscription({ id: "sub_Enterprise0001", plan_id: "plan_EnterpriseM01" });
  const body = await (await handler(post({ property_id: PROPERTY, action: "subscribe", tier: "enterprise" }))).json();
  assertEquals(body.action, "created");
  assertEquals(body.subscription_id, "sub_Enterprise0001");
  assertEquals(body.warning, undefined);
  assertEquals(rp.cancelled, [{ id: "sub_Current000001", atCycleEnd: false }]);
  assertEquals(db.callsTo("cancelRequested"), [["sub_Current000001", false, "cancelled", CALLER]]);
});

Deno.test("stale subscriptions are cleaned up first, and a failure is a warning", async () => {
  const { handler, db, rp } = setup();
  db.state = subscribeState({ current: current({ status: "created" }), stale: ["sub_Stale00000001"] });
  rp.failCancel = new RazorpayError(502, "Bad Gateway");
  const res = await handler(post({ property_id: PROPERTY, action: "subscribe", tier: "pro" }));
  assertEquals(res.status, 200);
  const body = await res.json();
  assertEquals(body.action, "reused");
  assertEquals(body.warning, "previous_not_cancelled");
  assertEquals(rp.cancelled, [{ id: "sub_Stale00000001", atCycleEnd: false }]);
  assertEquals(db.callsTo("cancelRequested"), []);
});

Deno.test("a database refusal is 409 db with the Postgres code", async () => {
  const { handler, db } = setup();
  db.error = new DbError("P0038", "billing_unavailable");
  const res = await handler(post({ property_id: PROPERTY, action: "subscribe", tier: "enterprise" }));
  assertEquals(res.status, 409);
  assertEquals(await res.json(), { error: "db", code: "P0038", message: "billing_unavailable" });
});

Deno.test("Razorpay refusing the create is 502 gateway, and nothing is recorded", async () => {
  const { handler, db, rp } = setup();
  rp.failCreate = new RazorpayError(400, "The id provided does not exist");
  const res = await handler(post({ property_id: PROPERTY, action: "subscribe", tier: "pro" }));
  assertEquals(res.status, 502);
  assertEquals(await res.json(), { error: "gateway", message: "The id provided does not exist" });
  assertEquals(db.callsTo("opened"), []);
});

Deno.test("recording the new subscription failing cancels it on Razorpay, then answers the failure", async () => {
  const { handler, db, rp } = setup();
  db.failOn.opened = new DbError("P0021", "resort_mismatch");
  const res = await handler(post({ property_id: PROPERTY, action: "subscribe", tier: "pro" }));
  assertEquals(res.status, 409);
  assertEquals(await res.json(), { error: "db", code: "P0021", message: "resort_mismatch" });
  assertEquals(db.callsTo("opened").length, 1);
  assertEquals(rp.cancelled, [{ id: "sub_NewSub0000001", atCycleEnd: false }]);
});

Deno.test("an unexpected recording failure also cancels the new subscription, and is 500", async () => {
  const { handler, db, rp } = setup();
  db.failOn.opened = new Error("network blip");
  const res = await handler(post({ property_id: PROPERTY, action: "subscribe", tier: "pro" }));
  assertEquals(res.status, 500);
  assertEquals((await res.json()).error, "internal");
  assertEquals(rp.cancelled, [{ id: "sub_NewSub0000001", atCycleEnd: false }]);
});

Deno.test("when the compensating cancel fails too, the recording failure is still what is answered", async () => {
  const { handler, db, rp } = setup();
  db.failOn.opened = new DbError("P0005", "not_allowed");
  rp.failCancel = new RazorpayError(502, "Bad Gateway");
  const res = await handler(post({ property_id: PROPERTY, action: "subscribe", tier: "pro" }));
  assertEquals(res.status, 409);
  assertEquals(await res.json(), { error: "db", code: "P0005", message: "not_allowed" });
  assertEquals(rp.cancelled, [{ id: "sub_NewSub0000001", atCycleEnd: false }]);
});

Deno.test("cancel: authorised auto-pay ends with its cycle", async () => {
  const { handler, db, rp } = setup();
  db.state = subscribeState({ tier: null, plan_id: null, current: current() });
  const body = await (await handler(post({ property_id: PROPERTY, action: "cancel" }))).json();
  assertEquals(body, {
    configured: true,
    action: "cancel_scheduled",
    subscription_id: "sub_Current000001",
    status: "active",
  });
  assertEquals(db.callsTo("subscribeState"), [[PROPERTY, null]]);
  assertEquals(rp.cancelled, [{ id: "sub_Current000001", atCycleEnd: true }]);
  assertEquals(db.callsTo("cancelRequested"), [["sub_Current000001", true, "active", CALLER]]);
});

Deno.test("cancel: an unauthorised link is cancelled now", async () => {
  const { handler, db } = setup();
  db.state = subscribeState({ current: current({ status: "created" }) });
  const body = await (await handler(post({ property_id: PROPERTY, action: "cancel" }))).json();
  assertEquals(body.action, "cancelled");
  assertEquals(body.status, "cancelled");
});

Deno.test("cancel: nothing to cancel is none", async () => {
  const { handler, db, rp } = setup();
  db.state = subscribeState({ current: null });
  const body = await (await handler(post({ property_id: PROPERTY, action: "cancel" }))).json();
  assertEquals(body, { configured: true, action: "none", subscription_id: null, status: null });
  assertEquals(rp.cancelled, []);
});

Deno.test("anything unexpected is 500 internal", async () => {
  const { handler, db } = setup();
  db.error = new Error("boom");
  const res = await handler(post({ property_id: PROPERTY, action: "probe" }));
  assertEquals(res.status, 500);
  assertEquals((await res.json()).error, "internal");
});
