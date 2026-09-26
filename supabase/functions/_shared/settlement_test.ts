import { assertEquals } from "jsr:@std/assert@1";
import { ensureCaptured, refundIfNeeded } from "./settlement.ts";
import { FakeRazorpay, FakeServiceDb, razorpayOrder, razorpayPayment, settleResult } from "./testing.ts";

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
    {
      notes: { reason: "unapplied", reservation_id: "a6100000-0000-4000-8000-000000000031" },
      receipt: "unapplied_pay_P6test0001",
      idempotencyKey: "unapplied_pay_P6test0001",
    },
  ]]);
  assertEquals(service.refunds, [["pay_P6test0001", "rfnd_P6test0001", 5000]]);
  assertEquals(service.releases, []);
});

// Final review minor 1: verify and the webhook can both be told
// refund_needed for one payment. Both calls carry the same idempotency key,
// so Razorpay makes one refund however many callers ask.
Deno.test("every refund of one payment carries the same idempotency key and receipt", async () => {
  const razorpay = new FakeRazorpay();
  const service = new FakeServiceDb();
  const unapplied = settleResult({ status: "unapplied", refund_needed: true });
  await refundIfNeeded(unapplied, razorpay, service);
  await refundIfNeeded(unapplied, razorpay, service);
  assertEquals(razorpay.refunds.length, 2);
  assertEquals(razorpay.refunds[0], razorpay.refunds[1]);
});

Deno.test("a failed refund releases the refund claim for the next settle call", async () => {
  const razorpay = new FakeRazorpay();
  razorpay.refundError = new Error("gateway timeout");
  const service = new FakeServiceDb();
  const state = await refundIfNeeded(settleResult({ status: "unapplied", refund_needed: true }), razorpay, service);
  assertEquals(state, "failed");
  assertEquals(service.releases, ["pay_P6test0001"]);
});

Deno.test("a refund that cannot be recorded is failed and released too", async () => {
  const razorpay = new FakeRazorpay();
  const service = new FakeServiceDb();
  service.refundError = new Error("database down");
  const state = await refundIfNeeded(settleResult({ status: "unapplied", refund_needed: true }), razorpay, service);
  assertEquals(state, "failed");
  assertEquals(service.releases, ["pay_P6test0001"]);
});

Deno.test("a refund Razorpay refuses is reported and not recorded", async () => {
  const razorpay = new FakeRazorpay();
  razorpay.refundError = new Error("payment not captured yet");
  const service = new FakeServiceDb();
  const state = await refundIfNeeded(settleResult({ status: "unapplied", refund_needed: true }), razorpay, service);
  assertEquals(state, "failed");
  assertEquals(service.refunds.length, 0);
});

// A Checkout signature proves the payment was authorized, not captured
// (final review, Important 1). Only captured money may settle a booking.
Deno.test("a captured payment for this order and amount is captured; nothing else is called", async () => {
  const razorpay = new FakeRazorpay();
  assertEquals((await ensureCaptured(razorpay, "order_P6test0001", "pay_P6test0001")).state, "captured");
  assertEquals(razorpay.captures.length, 0);
});

Deno.test("an authorized payment is captured for the order's amount first", async () => {
  const razorpay = new FakeRazorpay();
  razorpay.payments.set("pay_P6test0001", razorpayPayment({ status: "authorized" }));
  assertEquals((await ensureCaptured(razorpay, "order_P6test0001", "pay_P6test0001")).state, "captured");
  assertEquals(razorpay.captures, [["pay_P6test0001", { amountPaise: 500000, currency: "INR" }]]);
});

Deno.test("a capture that fails because it was captured meanwhile still counts", async () => {
  const razorpay = new FakeRazorpay();
  razorpay.payments.set("pay_P6test0001", razorpayPayment({ status: "authorized" }));
  razorpay.captureError = new Error("This payment has already been captured");
  razorpay.captureAnyway = true;
  assertEquals((await ensureCaptured(razorpay, "order_P6test0001", "pay_P6test0001")).state, "captured");
});

Deno.test("an authorized payment that cannot be captured is pending", async () => {
  const razorpay = new FakeRazorpay();
  razorpay.payments.set("pay_P6test0001", razorpayPayment({ status: "authorized" }));
  razorpay.captureError = new Error("capture window closed");
  const check = await ensureCaptured(razorpay, "order_P6test0001", "pay_P6test0001");
  assertEquals(check.state, "pending");
});

Deno.test("a created, failed or refunded payment is pending and is not captured", async () => {
  for (const status of ["created", "failed", "refunded"]) {
    const razorpay = new FakeRazorpay();
    razorpay.payments.set("pay_P6test0001", razorpayPayment({ status }));
    assertEquals((await ensureCaptured(razorpay, "order_P6test0001", "pay_P6test0001")).state, "pending", status);
    assertEquals(razorpay.captures.length, 0);
  }
});

Deno.test("a payment for another order, amount or currency is a mismatch and is not captured", async () => {
  const cases = [
    razorpayPayment({ order_id: "order_OTHER", status: "authorized" }),
    razorpayPayment({ amount: 100, status: "authorized" }),
    razorpayPayment({ currency: "USD", status: "authorized" }),
  ];
  for (const payment of cases) {
    const razorpay = new FakeRazorpay();
    razorpay.payments.set("pay_P6test0001", payment);
    assertEquals((await ensureCaptured(razorpay, "order_P6test0001", "pay_P6test0001")).state, "mismatch");
    assertEquals(razorpay.captures.length, 0);
  }
  const razorpay = new FakeRazorpay();
  razorpay.orderLookups.set("order_P6test0001", razorpayOrder({ amount: 900000 }));
  assertEquals((await ensureCaptured(razorpay, "order_P6test0001", "pay_P6test0001")).state, "mismatch");
});

Deno.test("when Razorpay cannot be asked, the error reaches the caller", async () => {
  const razorpay = new FakeRazorpay();
  razorpay.fetchError = new Error("network down");
  let thrown = false;
  try {
    await ensureCaptured(razorpay, "order_P6test0001", "pay_P6test0001");
  } catch {
    thrown = true;
  }
  assertEquals(thrown, true);
});
