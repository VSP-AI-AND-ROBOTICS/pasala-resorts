import { assertEquals } from "jsr:@std/assert@1";
import { makeWebhookHandler } from "./handler.ts";
import { FakeBillingDb, FakeRazorpay } from "../_shared/billing/testing.ts";
import { hmacSha256Hex } from "../_shared/billing/signature.ts";
import { DbError } from "../_shared/billing/types.ts";

const SECRET = "whsec_fixture";
const keys = { keyId: "rzp_test_key", keySecret: "rzp_test_secret" };

const subscription = {
  id: "sub_WebhookOne0001",
  entity: "subscription",
  status: "active",
  current_start: 1790000000,
  current_end: 1792592000,
};
const payment = { id: "pay_WebhookOne0001", entity: "payment", amount: 799900, currency: "INR", created_at: 1790000100 };

function event(name: string, withPayment: boolean): string {
  return JSON.stringify({
    entity: "event",
    account_id: "acc_Fixture000001",
    event: name,
    contains: withPayment ? ["subscription", "payment"] : ["subscription"],
    payload: {
      subscription: { entity: subscription },
      ...(withPayment ? { payment: { entity: payment } } : {}),
    },
    created_at: 1790000200,
  });
}

function setup(opts: { secret?: string | null; withKeys?: boolean } = {}) {
  const db = new FakeBillingDb();
  const rp = new FakeRazorpay();
  const handler = makeWebhookHandler({
    webhookSecret: opts.secret === undefined ? SECRET : opts.secret,
    keys: opts.withKeys === false ? null : keys,
    razorpay: () => rp,
    db: () => db,
  });
  return { db, rp, handler };
}

async function signed(raw: string, secret = SECRET): Promise<Request> {
  return new Request("http://localhost/billing-webhook", {
    method: "POST",
    headers: { "Content-Type": "application/json", "X-Razorpay-Signature": await hmacSha256Hex(secret, raw) },
    body: raw,
  });
}

Deno.test("only POST", async () => {
  const res = await setup().handler(new Request("http://localhost/billing-webhook"));
  assertEquals(res.status, 405);
  await res.body?.cancel();
});

Deno.test("503 until a webhook secret is set", async () => {
  const { handler, db } = setup({ secret: null });
  const res = await handler(await signed(event("subscription.charged", true)));
  assertEquals(res.status, 503);
  assertEquals((await res.json()).error, "not_configured");
  assertEquals(db.calls, []);
});

Deno.test("a wrong or missing signature is 401 and records nothing", async () => {
  const { handler, db } = setup();
  const raw = event("subscription.charged", true);
  const wrong = await handler(await signed(raw, "another_secret"));
  assertEquals(wrong.status, 401);
  assertEquals((await wrong.json()).error, "invalid_signature");
  const missing = await handler(new Request("http://localhost/billing-webhook", { method: "POST", body: raw }));
  assertEquals(missing.status, 401);
  await missing.body?.cancel();
  assertEquals(db.calls, []);
});

Deno.test("a signed body that is not JSON is 400", async () => {
  const res = await setup().handler(await signed("not json"));
  assertEquals(res.status, 400);
  await res.body?.cancel();
});

Deno.test("events that are not subscription.* are acknowledged and ignored", async () => {
  const { handler, db } = setup();
  const res = await handler(await signed(JSON.stringify({ event: "payment.captured", payload: {} })));
  assertEquals(res.status, 200);
  assertEquals(await res.json(), { status: "ignored" });
  assertEquals(db.calls, []);
});

Deno.test("a subscription event without its subscription is 400", async () => {
  const res = await setup().handler(await signed(JSON.stringify({ event: "subscription.charged", payload: {} })));
  assertEquals(res.status, 400);
  await res.body?.cancel();
});

Deno.test("subscription.charged is applied with its payment and time", async () => {
  const { handler, db } = setup();
  db.applyResult = { outcome: "charged", property_id: "p1", cancel_subscription_id: null };
  const res = await handler(await signed(event("subscription.charged", true)));
  assertEquals(res.status, 200);
  assertEquals(await res.json(), { status: "processed", outcome: "charged" });
  assertEquals(db.callsTo("applyWebhook"), [[
    "subscription.charged",
    new Date(1790000200 * 1000).toISOString(),
    subscription,
    payment,
  ]]);
});

Deno.test("subscription.halted has no payment", async () => {
  const { handler, db } = setup();
  db.applyResult = { outcome: "lapsed", property_id: "p1", cancel_subscription_id: null };
  const res = await handler(await signed(event("subscription.halted", false)));
  assertEquals(await res.json(), { status: "processed", outcome: "lapsed" });
  assertEquals(db.callsTo("applyWebhook")[0][3], null);
});

Deno.test("a database failure is 500, so Razorpay retries", async () => {
  const { handler, db } = setup();
  db.error = new DbError("40001", "could not serialize access");
  const res = await handler(await signed(event("subscription.charged", true)));
  assertEquals(res.status, 500);
  assertEquals((await res.json()).error, "db");
});

Deno.test("a replaced subscription that is still live is cancelled now", async () => {
  const { handler, db, rp } = setup();
  db.applyResult = { outcome: "charged", property_id: "p1", cancel_subscription_id: "sub_WebhookOld0001" };
  const res = await handler(await signed(event("subscription.charged", true)));
  assertEquals(res.status, 200);
  await res.body?.cancel();
  assertEquals(rp.cancelled, [{ id: "sub_WebhookOld0001", atCycleEnd: false }]);
  assertEquals(db.callsTo("cancelRequested"), [["sub_WebhookOld0001", false, "cancelled", null]]);
});

Deno.test("without the API keys the replaced subscription is left for later", async () => {
  const { handler, db, rp } = setup({ withKeys: false });
  db.applyResult = { outcome: "charged", property_id: "p1", cancel_subscription_id: "sub_WebhookOld0001" };
  const res = await handler(await signed(event("subscription.charged", true)));
  assertEquals(res.status, 200);
  await res.body?.cancel();
  assertEquals(rp.cancelled, []);
});
