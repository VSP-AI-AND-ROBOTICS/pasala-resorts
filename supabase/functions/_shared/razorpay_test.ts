import { assert, assertEquals, assertFalse, assertRejects } from "jsr:@std/assert@1";
import {
  hmacSha256Hex,
  paymentsLive,
  RazorpayClient,
  RazorpayHttpError,
  readConfig,
  sha256Hex,
  timingSafeEqual,
  verifyPaymentSignature,
  verifyWebhookSignature,
} from "./razorpay.ts";
import { fixtureConfig, fixtureSignature } from "./testing.ts";

Deno.test("hmacSha256Hex matches RFC 4231 test case 2", async () => {
  assertEquals(
    await hmacSha256Hex("Jefe", "what do ya want for nothing?"),
    "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843",
  );
});

Deno.test("sha256Hex of the empty string", async () => {
  assertEquals(await sha256Hex(""), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");
});

Deno.test("a checkout signature over order_id|payment_id verifies", async () => {
  assert(await verifyPaymentSignature("order_P6test0001", "pay_P6test0001", fixtureSignature, "rzp_secret_fixture"));
});

Deno.test("an upper-case signature verifies too", async () => {
  assert(await verifyPaymentSignature(
    "order_P6test0001",
    "pay_P6test0001",
    fixtureSignature.toUpperCase(),
    "rzp_secret_fixture",
  ));
});

Deno.test("a signature for another payment, another secret, or nothing fails", async () => {
  assertFalse(await verifyPaymentSignature("order_P6test0001", "pay_OTHER", fixtureSignature, "rzp_secret_fixture"));
  assertFalse(await verifyPaymentSignature("order_P6test0001", "pay_P6test0001", fixtureSignature, "another_secret"));
  assertFalse(await verifyPaymentSignature("order_P6test0001", "pay_P6test0001", "", "rzp_secret_fixture"));
  assertFalse(await verifyPaymentSignature("", "pay_P6test0001", fixtureSignature, "rzp_secret_fixture"));
});

Deno.test("a webhook signature over the raw body verifies", async () => {
  assert(await verifyWebhookSignature(
    '{"entity":"event","event":"payment.captured"}',
    "856760a7b485f76effd94942bd1d835432170da3171d7e11d72f08b0d4cc7669",
    "whsec_fixture",
  ));
});

Deno.test("a webhook signature fails when one byte of the body changes", async () => {
  assertFalse(await verifyWebhookSignature(
    '{"entity":"event", "event":"payment.captured"}',
    "856760a7b485f76effd94942bd1d835432170da3171d7e11d72f08b0d4cc7669",
    "whsec_fixture",
  ));
  assertFalse(await verifyWebhookSignature("{}", "", "whsec_fixture"));
});

Deno.test("timingSafeEqual compares whole strings", () => {
  assert(timingSafeEqual("abc", "abc"));
  assertFalse(timingSafeEqual("abc", "abd"));
  assertFalse(timingSafeEqual("abc", "abcd"));
});

Deno.test("readConfig needs both keys; the webhook secret is optional", () => {
  const env = (values: Record<string, string>) => (name: string) => values[name];
  assertEquals(readConfig(env({})), null);
  assertEquals(readConfig(env({ RAZORPAY_KEY_ID: "rzp_test_x" })), null);
  assertEquals(readConfig(env({ RAZORPAY_KEY_ID: "  ", RAZORPAY_KEY_SECRET: "s" })), null);
  assertEquals(
    readConfig(env({ RAZORPAY_KEY_ID: "rzp_test_x", RAZORPAY_KEY_SECRET: "s" })),
    { keyId: "rzp_test_x", keySecret: "s", webhookSecret: null },
  );
  assertEquals(
    readConfig(env({ RAZORPAY_KEY_ID: "rzp_test_x", RAZORPAY_KEY_SECRET: "s", RAZORPAY_WEBHOOK_SECRET: "w" })),
    { keyId: "rzp_test_x", keySecret: "s", webhookSecret: "w" },
  );
});

type Call = { url: string; init: RequestInit };

function fakeFetch(status: number, body: unknown, calls: Call[]) {
  return (url: string, init: RequestInit) => {
    calls.push({ url, init });
    return Promise.resolve(new Response(JSON.stringify(body), { status }));
  };
}

Deno.test("createOrder posts paise to /v1/orders with Basic auth", async () => {
  const calls: Call[] = [];
  const client = new RazorpayClient(
    fixtureConfig,
    fakeFetch(200, { id: "order_X", amount: 500000, currency: "INR", status: "created" }, calls),
  );

  const order = await client.createOrder({
    amountPaise: 500000,
    currency: "INR",
    receipt: "r1",
    notes: { reservation_id: "r1" },
  });

  assertEquals(order.id, "order_X");
  assertEquals(calls[0].url, "https://api.razorpay.com/v1/orders");
  assertEquals(calls[0].init.method, "POST");
  const headers = calls[0].init.headers as Record<string, string>;
  assertEquals(headers["Authorization"], `Basic ${btoa("rzp_test_fixture:rzp_secret_fixture")}`);
  assertEquals(JSON.parse(calls[0].init.body as string), {
    amount: 500000,
    currency: "INR",
    receipt: "r1",
    notes: { reservation_id: "r1" },
  });
});

Deno.test("a Razorpay error becomes RazorpayHttpError with the status", async () => {
  const client = new RazorpayClient(fixtureConfig, fakeFetch(400, { error: { code: "BAD_REQUEST_ERROR" } }, []));
  const error = await assertRejects(
    () => client.createOrder({ amountPaise: 1, currency: "INR", receipt: "r", notes: {} }),
    RazorpayHttpError,
  );
  assertEquals(error.status, 400);
});

Deno.test("refundPayment posts to /v1/payments/:id/refund, full amount by default", async () => {
  const calls: Call[] = [];
  const client = new RazorpayClient(fixtureConfig, fakeFetch(200, { id: "rfnd_X", amount: 500000 }, calls));

  const refund = await client.refundPayment("pay_P6test0001", { notes: { reason: "unapplied" } });

  assertEquals(refund.id, "rfnd_X");
  assertEquals(calls[0].url, "https://api.razorpay.com/v1/payments/pay_P6test0001/refund");
  assertEquals(JSON.parse(calls[0].init.body as string), { notes: { reason: "unapplied" } });
});

Deno.test("refundPayment sends the idempotency key as X-Refund-Idempotency and the receipt", async () => {
  const calls: Call[] = [];
  const client = new RazorpayClient(fixtureConfig, fakeFetch(200, { id: "rfnd_X", amount: 500000 }, calls));

  await client.refundPayment("pay_P6test0001", {
    notes: { reason: "unapplied" },
    receipt: "unapplied_pay_P6test0001",
    idempotencyKey: "unapplied_pay_P6test0001",
  });

  const headers = calls[0].init.headers as Record<string, string>;
  assertEquals(headers["X-Refund-Idempotency"], "unapplied_pay_P6test0001");
  assertEquals(JSON.parse(calls[0].init.body as string), {
    notes: { reason: "unapplied" },
    receipt: "unapplied_pay_P6test0001",
  });
});

Deno.test("refundPayment sends no idempotency header when none is given", async () => {
  const calls: Call[] = [];
  const client = new RazorpayClient(fixtureConfig, fakeFetch(200, { id: "rfnd_X", amount: 500000 }, calls));
  await client.refundPayment("pay_P6test0001");
  const headers = calls[0].init.headers as Record<string, string>;
  assertEquals("X-Refund-Idempotency" in headers, false);
});

// Final review minor 3: without the webhook secret a guest who closes the
// tab after paying is never settled, so payments are not live.
Deno.test("paymentsLive needs both keys and the webhook secret", () => {
  assertEquals(paymentsLive(null), false);
  assertEquals(paymentsLive({ ...fixtureConfig, webhookSecret: null }), false);
  assertEquals(paymentsLive(fixtureConfig), true);
});

Deno.test("fetchPayment and fetchOrder GET /v1/payments/:id and /v1/orders/:id with Basic auth", async () => {
  const calls: Call[] = [];
  const client = new RazorpayClient(
    fixtureConfig,
    fakeFetch(200, {
      id: "pay_P6test0001",
      order_id: "order_P6test0001",
      amount: 500000,
      currency: "INR",
      status: "authorized",
    }, calls),
  );

  const payment = await client.fetchPayment("pay_P6test0001");
  await client.fetchOrder("order_P6test0001");

  assertEquals(payment.status, "authorized");
  assertEquals(calls[0].url, "https://api.razorpay.com/v1/payments/pay_P6test0001");
  assertEquals(calls[0].init.method, "GET");
  assertEquals(calls[0].init.body, undefined);
  const headers = calls[0].init.headers as Record<string, string>;
  assertEquals(headers["Authorization"], `Basic ${btoa("rzp_test_fixture:rzp_secret_fixture")}`);
  assertEquals(calls[1].url, "https://api.razorpay.com/v1/orders/order_P6test0001");
  assertEquals(calls[1].init.method, "GET");
});

Deno.test("capturePayment posts the amount and currency to /v1/payments/:id/capture", async () => {
  const calls: Call[] = [];
  const client = new RazorpayClient(
    fixtureConfig,
    fakeFetch(200, {
      id: "pay_P6test0001",
      order_id: "order_P6test0001",
      amount: 500000,
      currency: "INR",
      status: "captured",
    }, calls),
  );

  const payment = await client.capturePayment("pay_P6test0001", { amountPaise: 500000, currency: "INR" });

  assertEquals(payment.status, "captured");
  assertEquals(calls[0].url, "https://api.razorpay.com/v1/payments/pay_P6test0001/capture");
  assertEquals(calls[0].init.method, "POST");
  assertEquals(JSON.parse(calls[0].init.body as string), { amount: 500000, currency: "INR" });
});
