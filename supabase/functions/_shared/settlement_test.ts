import { assertEquals } from "jsr:@std/assert@1";
import { refundIfNeeded } from "./settlement.ts";
import { FakeRazorpay, FakeServiceDb, settleResult } from "./testing.ts";

Deno.test("a paid order needs no refund", async () => {
  const razorpay = new FakeRazorpay();
  const service = new FakeServiceDb();
  assertEquals(await refundIfNeeded(settleResult(), razorpay, service), null);
  assertEquals(razorpay.refunds.length, 0);
});

Deno.test("an unapplied order is refunded in full and the refund recorded in rupees", async () => {
  const razorpay = new FakeRazorpay();
  const service = new FakeServiceDb();
  const state = await refundIfNeeded(
    settleResult({ status: "unapplied", refund_needed: true, reason: "reservation is cancelled" }),
    razorpay,
    service,
  );
  assertEquals(state, "initiated");
  assertEquals(razorpay.refunds, [[
    "pay_P6test0001",
    { notes: { reason: "unapplied", reservation_id: "a6100000-0000-4000-8000-000000000031" } },
  ]]);
  assertEquals(service.refunds, [["pay_P6test0001", "rfnd_P6test0001", 5000]]);
});

Deno.test("a refund Razorpay refuses is reported and not recorded", async () => {
  const razorpay = new FakeRazorpay();
  razorpay.refundError = new Error("payment not captured yet");
  const service = new FakeServiceDb();
  const state = await refundIfNeeded(settleResult({ status: "unapplied", refund_needed: true }), razorpay, service);
  assertEquals(state, "failed");
  assertEquals(service.refunds.length, 0);
});
