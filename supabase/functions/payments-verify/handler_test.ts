import { assertEquals } from "jsr:@std/assert@1";
import { verifyHandler } from "./handler.ts";
import { DbError, type RazorpayConfig } from "../_shared/payments_types.ts";
import {
  FakeRazorpay,
  FakeServiceDb,
  fixtureConfig,
  fixtureSignature,
  post,
  reservationId,
  settleResult,
} from "../_shared/testing.ts";

function setup(config: RazorpayConfig | null = fixtureConfig) {
  const service = new FakeServiceDb();
  const razorpay = new FakeRazorpay();
  const handler = verifyHandler({ config: () => config, service, razorpay: () => razorpay });
  return { handler, service, razorpay };
}

const good = {
  razorpay_order_id: "order_P6test0001",
  razorpay_payment_id: "pay_P6test0001",
  razorpay_signature: fixtureSignature,
};

Deno.test("without keys it answers configured:false and settles nothing", async () => {
  const { handler, service } = setup(null);
  const res = await handler(post(good));
  assertEquals(await res.json(), { configured: false });
  assertEquals(service.settles.length, 0);
});

Deno.test("verifying needs a bearer token", async () => {
  const { handler } = setup();
  assertEquals((await handler(post(good, {}))).status, 401);
});

Deno.test("a missing field is 400", async () => {
  const { handler } = setup();
  const res = await handler(post({ ...good, razorpay_signature: "" }));
  assertEquals(res.status, 400);
  assertEquals((await res.json()).error, "bad_request");
});

Deno.test("a wrong signature is refused and nothing is settled", async () => {
  const { handler, service } = setup();
  const res = await handler(post({ ...good, razorpay_payment_id: "pay_forged" }));
  assertEquals(res.status, 400);
  assertEquals((await res.json()).error, "invalid_signature");
  assertEquals(service.settles.length, 0);
});

Deno.test("a good signature settles the order and answers paid", async () => {
  const { handler, service, razorpay } = setup();
  const res = await handler(post(good));
  assertEquals(res.status, 200);
  assertEquals(service.settles, [["order_P6test0001", "pay_P6test0001"]]);
  assertEquals(await res.json(), {
    configured: true,
    outcome: "paid",
    reservation_id: reservationId,
    kind: "advance",
    refund: null,
  });
  assertEquals(razorpay.refunds.length, 0);
});

Deno.test("verifying twice answers paid twice (the database settles once)", async () => {
  const { handler, service } = setup();
  assertEquals((await (await handler(post(good))).json()).outcome, "paid");
  assertEquals((await (await handler(post(good))).json()).outcome, "paid");
  assertEquals(service.settles.length, 2);
});

Deno.test("an unapplied payment is refunded and reported", async () => {
  const { handler, service, razorpay } = setup();
  service.settleResult = settleResult({ status: "unapplied", refund_needed: true, reason: "reservation is cancelled" });
  const body = await (await handler(post(good))).json();
  assertEquals(body.outcome, "unapplied");
  assertEquals(body.refund, "initiated");
  assertEquals(razorpay.refunds.length, 1);
  assertEquals(service.refunds, [["pay_P6test0001", "rfnd_P6test0001", 5000]]);
});

Deno.test("a refund that fails is reported as failed", async () => {
  const { handler, service, razorpay } = setup();
  service.settleResult = settleResult({ status: "unapplied", refund_needed: true });
  razorpay.refundError = new Error("not captured yet");
  assertEquals((await (await handler(post(good))).json()).refund, "failed");
});

Deno.test("an already refunded order is unapplied with nothing more to refund", async () => {
  const { handler, service, razorpay } = setup();
  service.settleResult = settleResult({ status: "refunded", refund_needed: false });
  const body = await (await handler(post(good))).json();
  assertEquals(body.outcome, "unapplied");
  assertEquals(body.refund, null);
  assertEquals(razorpay.refunds.length, 0);
});

Deno.test("an unknown order is a 409 P0002", async () => {
  const { handler, service } = setup();
  service.settleResult = null;
  const res = await handler(post(good));
  assertEquals(res.status, 409);
  assertEquals(await res.json(), { error: "db", code: "P0002", message: "payment_order_not_found" });
});

Deno.test("a database error is a 409 with its code", async () => {
  const { handler, service } = setup();
  service.settleError = new DbError("P0009", "a Razorpay payment id is required");
  const res = await handler(post(good));
  assertEquals(res.status, 409);
  assertEquals((await res.json()).code, "P0009");
});
