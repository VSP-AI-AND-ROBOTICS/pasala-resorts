import { assertEquals } from "jsr:@std/assert@1";
import { createOrderHandler, type CreateOrderDeps } from "./handler.ts";
import { DbError, type RazorpayConfig } from "../_shared/payments_types.ts";
import { FakeRazorpay, FakeServiceDb, FakeUserDb, fixtureConfig, post, reservationId } from "../_shared/testing.ts";

function setup(config: RazorpayConfig | null = fixtureConfig) {
  const service = new FakeServiceDb();
  const user = new FakeUserDb();
  const razorpay = new FakeRazorpay();
  const authorizations: string[] = [];
  const deps: CreateOrderDeps = {
    config: () => config,
    service,
    userDb: (authorization) => {
      authorizations.push(authorization);
      return user;
    },
    razorpay: () => razorpay,
  };
  return { handler: createOrderHandler(deps), service, user, razorpay, authorizations };
}

const request = { reservation_id: reservationId, amount: 5000, purpose: "advance" };

Deno.test("OPTIONS answers the CORS preflight", async () => {
  const { handler } = setup();
  const res = await handler(new Request("http://localhost/fn", { method: "OPTIONS" }));
  assertEquals(res.status, 200);
  assertEquals(res.headers.get("Access-Control-Allow-Origin"), "*");
});

Deno.test("GET is refused", async () => {
  const { handler } = setup();
  const res = await handler(new Request("http://localhost/fn"));
  assertEquals(res.status, 405);
});

Deno.test("without keys it answers configured:false, switches live off and calls nobody", async () => {
  const { handler, service, user, razorpay } = setup(null);
  const res = await handler(post(request));
  assertEquals(res.status, 200);
  assertEquals(await res.json(), { configured: false });
  assertEquals(service.live, false);
  assertEquals(user.calls.length, 0);
  assertEquals(razorpay.orders.length, 0);
});

Deno.test("a probe reports the key id and switches live on, creating nothing", async () => {
  const { handler, service, razorpay } = setup();
  const res = await handler(post({ probe: true }));
  assertEquals(await res.json(), { configured: true, key_id: "rzp_test_fixture" });
  assertEquals(service.live, true);
  assertEquals(service.liveKeyId, "rzp_test_fixture");
  assertEquals(razorpay.orders.length, 0);
});

Deno.test("a probe without keys reports configured:false", async () => {
  const { handler } = setup(null);
  assertEquals(await (await handler(post({ probe: true }))).json(), { configured: false });
});

Deno.test("a paying request needs a bearer token", async () => {
  const { handler, razorpay } = setup();
  const res = await handler(post(request, {}));
  assertEquals(res.status, 401);
  assertEquals((await res.json()).error, "unauthorized");
  assertEquals(razorpay.orders.length, 0);
});

Deno.test("bad bodies are 400 and touch nothing", async () => {
  const { handler, service } = setup();
  for (
    const body of [
      "not json",
      [],
      { ...request, purpose: "tip" },
      { ...request, amount: -1 },
      { ...request, amount: "5000" },
      { ...request, reservation_id: "r1" },
    ]
  ) {
    const res = await handler(post(body));
    assertEquals(res.status, 400, JSON.stringify(body));
    assertEquals((await res.json()).error, "bad_request");
  }
  assertEquals(service.live, null);
});

Deno.test("an order is quoted as the guest, created at the quoted paise and recorded", async () => {
  const { handler, service, user, razorpay, authorizations } = setup();

  const res = await handler(post(request));

  assertEquals(res.status, 200);
  assertEquals(authorizations, ["Bearer user-jwt"]);
  assertEquals(user.calls, [{ reservationId, kind: "advance", amount: 5000 }]);
  assertEquals(razorpay.orders, [{
    amountPaise: 500000,
    currency: "INR",
    receipt: reservationId,
    notes: { reservation_id: reservationId, property_id: "a6100000-0000-4000-8000-000000000001", kind: "advance" },
  }]);
  assertEquals(service.opened, [{
    reservationId,
    customerId: "a6000000-0000-0000-0000-000000000004",
    kind: "advance",
    amount: 5000,
    razorpayOrderId: "order_P6test0001",
  }]);
  assertEquals(await res.json(), {
    configured: true,
    key_id: "rzp_test_fixture",
    order_id: "order_P6test0001",
    amount: 500000,
    currency: "INR",
    name: "Online A",
    description: "Online A: booking advance",
    reservation_id: reservationId,
    prefill: { name: "Gita Guest", email: "p6-gita@example.com", contact: "+919800000001" },
  });
});

Deno.test("a refused quote is a 409 with the Postgres code, and no order is made", async () => {
  const { handler, user, razorpay } = setup();
  user.error = new DbError("P0009", "payment amount 1 is outside the accepted range 5000 to 10000");
  const res = await handler(post(request));
  assertEquals(res.status, 409);
  assertEquals(await res.json(), {
    error: "db",
    code: "P0009",
    message: "payment amount 1 is outside the accepted range 5000 to 10000",
  });
  assertEquals(razorpay.orders.length, 0);
});

Deno.test("a Razorpay failure is a 502 and nothing is recorded", async () => {
  const { handler, service, razorpay } = setup();
  razorpay.orderError = new Error("boom");
  const res = await handler(post(request));
  assertEquals(res.status, 502);
  assertEquals((await res.json()).error, "gateway");
  assertEquals(service.opened.length, 0);
});

Deno.test("a refused open is a 409", async () => {
  const { handler, service } = setup();
  service.openError = new DbError("P0008", "only the booking's guest can pay online");
  const res = await handler(post(request));
  assertEquals(res.status, 409);
  assertEquals((await res.json()).code, "P0008");
});

Deno.test("anything unexpected is a 500 with our own error body", async () => {
  const { handler, user } = setup();
  user.error = new TypeError("kaboom");
  const res = await handler(post(request));
  assertEquals(res.status, 500);
  assertEquals((await res.json()).error, "internal");
});

// Final review minor 3: without RAZORPAY_WEBHOOK_SECRET a guest who closes
// the tab after paying is never settled or refunded, so payments stay off.
Deno.test("keys without the webhook secret are not live: no order, live off", async () => {
  const { handler, service, user, razorpay } = setup({ ...fixtureConfig, webhookSecret: null });
  const res = await handler(post(request));
  assertEquals(await res.json(), { configured: false });
  assertEquals(service.live, false);
  assertEquals(service.liveKeyId, null);
  assertEquals(user.calls.length, 0);
  assertEquals(razorpay.orders.length, 0);
});

Deno.test("a probe with keys but no webhook secret says the secret is missing", async () => {
  const { handler, service } = setup({ ...fixtureConfig, webhookSecret: null });
  assertEquals(await (await handler(post({ probe: true }))).json(), {
    configured: false,
    missing: ["RAZORPAY_WEBHOOK_SECRET"],
  });
  assertEquals(service.live, false);
});
