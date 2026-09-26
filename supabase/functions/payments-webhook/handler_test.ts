import { assertEquals } from "jsr:@std/assert@1";
import { webhookHandler } from "./handler.ts";
import { DbError, type RazorpayConfig } from "../_shared/payments_types.ts";
import { sha256Hex } from "../_shared/razorpay.ts";
import {
  capturedEvent,
  failedEvent,
  FakeRazorpay,
  FakeServiceDb,
  fixtureConfig,
  refundEvent,
  settleResult,
  signedWebhook,
} from "../_shared/testing.ts";

function setup(config: RazorpayConfig | null = fixtureConfig) {
  const service = new FakeServiceDb();
  const razorpay = new FakeRazorpay();
  const handler = webhookHandler({ config: () => config, service, razorpay: () => razorpay });
  return { handler, service, razorpay };
}

Deno.test("without the keys or the webhook secret it is 503", async () => {
  assertEquals((await setup(null).handler(await signedWebhook(capturedEvent(), "evt_1"))).status, 503);
  const noSecret = setup({ ...fixtureConfig, webhookSecret: null });
  assertEquals((await noSecret.handler(await signedWebhook(capturedEvent(), "evt_1"))).status, 503);
});

Deno.test("a bad signature is 401 and nothing is recorded", async () => {
  const { handler, service } = setup();
  const req = new Request("http://localhost/fn", {
    method: "POST",
    headers: { "X-Razorpay-Signature": "00", "X-Razorpay-Event-Id": "evt_1" },
    body: JSON.stringify(capturedEvent()),
  });
  assertEquals((await handler(req)).status, 401);
  assertEquals(service.events.size, 0);
  assertEquals(service.settles.length, 0);
});

Deno.test("payment.captured settles an order no verify call has seen", async () => {
  const { handler, service } = setup();
  const res = await handler(await signedWebhook(capturedEvent(), "evt_1"));
  assertEquals(res.status, 200);
  assertEquals(await res.json(), { status: "processed", outcome: "settled:paid" });
  assertEquals(service.settles, [["order_P6test0001", "pay_P6test0001"]]);
  assertEquals(service.events.get("evt_1")?.outcome, "settled:paid");
});

Deno.test("the same event delivered again is a duplicate and settles nothing more", async () => {
  const { handler, service } = setup();
  await handler(await signedWebhook(capturedEvent(), "evt_1"));
  const res = await handler(await signedWebhook(capturedEvent(), "evt_1"));
  assertEquals(await res.json(), { status: "duplicate" });
  assertEquals(service.settles.length, 1);
});

Deno.test("a captured payment for an order that is not ours is ignored with 200", async () => {
  const { handler, service } = setup();
  service.settleResult = null;
  const res = await handler(await signedWebhook(capturedEvent("order_subscription"), "evt_2"));
  assertEquals(res.status, 200);
  assertEquals((await res.json()).outcome, "ignored:unknown_order");
});

Deno.test("an unapplied captured payment is refunded", async () => {
  const { handler, service, razorpay } = setup();
  service.settleResult = settleResult({ status: "unapplied", refund_needed: true });
  const body = await (await handler(await signedWebhook(capturedEvent(), "evt_3"))).json();
  assertEquals(body.outcome, "settled:unapplied:refund_initiated");
  assertEquals(razorpay.refunds.length, 1);
  assertEquals(service.refunds, [["pay_P6test0001", "rfnd_P6test0001", 5000]]);
});

Deno.test("payment.failed marks the order failed with Razorpay's reason", async () => {
  const { handler, service } = setup();
  const body = await (await handler(await signedWebhook(failedEvent(), "evt_4"))).json();
  assertEquals(body.outcome, "failed");
  assertEquals(service.failed, [["order_P6test0001", "Card declined by bank"]]);
});

Deno.test("refund.processed records the refund in rupees", async () => {
  const { handler, service } = setup();
  const body = await (await handler(await signedWebhook(refundEvent(), "evt_5"))).json();
  assertEquals(body.outcome, "refund_recorded");
  assertEquals(service.refunds, [["pay_P6test0001", "rfnd_P6test0002", 1000]]);
});

Deno.test("other events are acknowledged and ignored", async () => {
  const { handler, service } = setup();
  const body = await (await handler(await signedWebhook({ event: "order.paid", payload: {} }, "evt_6"))).json();
  assertEquals(body.outcome, "ignored:order.paid");
  assertEquals(service.settles.length, 0);
});

Deno.test("without X-Razorpay-Event-Id the event is keyed by the body's SHA-256", async () => {
  const { handler, service } = setup();
  const event = capturedEvent();
  await handler(await signedWebhook(event));
  assertEquals([...service.events.keys()], [`sha256:${await sha256Hex(JSON.stringify(event))}`]);
});

Deno.test("a database failure is 500 and leaves the event unfinished for the retry", async () => {
  const { handler, service } = setup();
  service.settleError = new DbError("08006", "connection failure");
  const res = await handler(await signedWebhook(capturedEvent(), "evt_7"));
  assertEquals(res.status, 500);
  assertEquals(service.events.get("evt_7")?.processed, false);
});

// Final review minor 2: a signed event proves the secrets are set, so the
// webhook switches live on too.
Deno.test("a signed event switches live on with the key id", async () => {
  const { handler, service } = setup();
  await handler(await signedWebhook(capturedEvent(), "evt_8"));
  assertEquals(service.live, true);
  assertEquals(service.liveKeyId, "rzp_test_fixture");
});

Deno.test("an unsigned request never touches the live switch", async () => {
  const noSecret = setup({ ...fixtureConfig, webhookSecret: null });
  await noSecret.handler(await signedWebhook(capturedEvent(), "evt_9"));
  assertEquals(noSecret.service.live, null);
  const { handler, service } = setup();
  await handler(new Request("http://localhost/fn", { method: "POST", body: "{}" }));
  assertEquals(service.live, null);
});

Deno.test("a failure to update the live switch never blocks the event", async () => {
  const { handler, service } = setup();
  service.setLiveError = new DbError("08006", "connection failure");
  const res = await handler(await signedWebhook(capturedEvent(), "evt_10"));
  assertEquals(res.status, 200);
  assertEquals(service.events.get("evt_10")?.outcome, "settled:paid");
});

// Final review minor 8: a permanent database error will fail the same way
// on every retry, so it is recorded with an error outcome and answered 200.
Deno.test("a permanent database error is finished with an error outcome and answered 200", async () => {
  for (const code of ["P0009", "23505", "22P02"]) {
    const { handler, service } = setup();
    service.settleError = new DbError(code, "refused");
    const res = await handler(await signedWebhook(capturedEvent(), "evt_11"));
    assertEquals(res.status, 200, code);
    assertEquals(await res.json(), { status: "processed", outcome: `error:${code}` }, code);
    assertEquals(service.events.get("evt_11")?.processed, true, code);
    assertEquals(service.events.get("evt_11")?.outcome, `error:${code}`, code);
  }
});

Deno.test("a transient database error is 500 and left for Razorpay's retry", async () => {
  for (const code of ["08006", "40001", "40P01", "53300", "57014", "PGRST000", "unknown"]) {
    const { handler, service } = setup();
    service.settleError = new DbError(code, "try again");
    const res = await handler(await signedWebhook(capturedEvent(), "evt_12"));
    assertEquals(res.status, 500, code);
    assertEquals(service.events.get("evt_12")?.processed, false, code);
  }
});

Deno.test("an error that is not from the database is still 500", async () => {
  const { handler, service } = setup();
  service.settleError = new Error("boom");
  assertEquals((await handler(await signedWebhook(capturedEvent(), "evt_13"))).status, 500);
  assertEquals(service.events.get("evt_13")?.processed, false);
});
