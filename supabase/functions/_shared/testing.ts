// Fakes and fixtures for the payments-* handler tests. Never imported by
// a function's index.ts.
import { hmacSha256Hex, RazorpayHttpError } from "./razorpay.ts";
import type {
  OrderQuote,
  PaymentKind,
  RazorpayApi,
  RazorpayConfig,
  RazorpayOrder,
  RazorpayOrderCreated,
  RazorpayPayment,
  RazorpayRefundCreated,
  ServicePaymentsDb,
  SettleResult,
  UserPaymentsDb,
} from "./payments_types.ts";

export const fixtureConfig: RazorpayConfig = {
  keyId: "rzp_test_fixture",
  keySecret: "rzp_secret_fixture",
  webhookSecret: "whsec_fixture",
};

/** HMAC_SHA256("order_P6test0001|pay_P6test0001", "rzp_secret_fixture"). */
export const fixtureSignature = "2ae02360e84fd4e6929f7c8d0d9761625c989e7a088e20af8bc7ea63d2d9f08c";

export const reservationId = "a6100000-0000-4000-8000-000000000031";

export function orderQuote(overrides: Partial<OrderQuote> = {}): OrderQuote {
  return {
    reservation_id: reservationId,
    property_id: "a6100000-0000-4000-8000-000000000001",
    property_name: "Online A",
    customer_id: "a6000000-0000-0000-0000-000000000004",
    kind: "advance",
    amount: 5000,
    amount_paise: 500000,
    currency: "INR",
    receipt: reservationId,
    description: "Online A: booking advance",
    prefill: { name: "Gita Guest", email: "p6-gita@example.com", contact: "+919800000001" },
    ...overrides,
  };
}

export function settleResult(overrides: Partial<SettleResult> = {}): SettleResult {
  return {
    order_id: "po-1",
    reservation_id: reservationId,
    kind: "advance",
    amount: 5000,
    status: "paid",
    razorpay_payment_id: "pay_P6test0001",
    reason: null,
    refund_needed: false,
    ...overrides,
  };
}

/** GET /v1/payments/pay_P6test0001: captured, for order_P6test0001. */
export function razorpayPayment(overrides: Partial<RazorpayPayment> = {}): RazorpayPayment {
  return {
    id: "pay_P6test0001",
    order_id: "order_P6test0001",
    amount: 500000,
    currency: "INR",
    status: "captured",
    ...overrides,
  };
}

/** GET /v1/orders/order_P6test0001, with the notes payments-create-order sets. */
export function razorpayOrder(overrides: Partial<RazorpayOrder> = {}): RazorpayOrder {
  return {
    id: "order_P6test0001",
    amount: 500000,
    currency: "INR",
    notes: { reservation_id: reservationId, property_id: "a6100000-0000-4000-8000-000000000001", kind: "advance" },
    ...overrides,
  };
}

export class FakeUserDb implements UserPaymentsDb {
  calls: Array<{ reservationId: string; kind: PaymentKind; amount: number }> = [];
  quote: OrderQuote = orderQuote();
  error: Error | null = null;

  quoteOrder(args: { reservationId: string; kind: PaymentKind; amount: number }): Promise<OrderQuote> {
    this.calls.push(args);
    return this.error ? Promise.reject(this.error) : Promise.resolve(this.quote);
  }
}

export class FakeServiceDb implements ServicePaymentsDb {
  live: boolean | null = null;
  liveKeyId: string | null = null;
  opened: Array<Parameters<ServicePaymentsDb["openOrder"]>[0]> = [];
  openError: Error | null = null;
  settles: Array<[string, string]> = [];
  settleResult: SettleResult | null = settleResult();
  settleError: Error | null = null;
  failed: Array<[string, string]> = [];
  refunds: Array<[string, string, number]> = [];
  events = new Map<string, { event: string; processed: boolean; outcome?: string }>();

  setLive(live: boolean, keyId: string | null): Promise<void> {
    this.live = live;
    this.liveKeyId = keyId;
    return Promise.resolve();
  }

  openOrder(args: Parameters<ServicePaymentsDb["openOrder"]>[0]): Promise<void> {
    if (this.openError) return Promise.reject(this.openError);
    this.opened.push(args);
    return Promise.resolve();
  }

  settleOrder(razorpayOrderId: string, razorpayPaymentId: string): Promise<SettleResult | null> {
    this.settles.push([razorpayOrderId, razorpayPaymentId]);
    return this.settleError ? Promise.reject(this.settleError) : Promise.resolve(this.settleResult);
  }

  failOrder(razorpayOrderId: string, reason: string): Promise<void> {
    this.failed.push([razorpayOrderId, reason]);
    return Promise.resolve();
  }

  recordRefund(razorpayPaymentId: string, refundId: string, amount: number): Promise<void> {
    this.refunds.push([razorpayPaymentId, refundId, amount]);
    return Promise.resolve();
  }

  beginWebhook(eventId: string, event: string, _payload: unknown): Promise<boolean> {
    const known = this.events.get(eventId);
    if (!known) {
      this.events.set(eventId, { event, processed: false });
      return Promise.resolve(true);
    }
    return Promise.resolve(!known.processed);
  }

  finishWebhook(eventId: string, outcome: string): Promise<void> {
    const known = this.events.get(eventId);
    if (known) {
      known.processed = true;
      known.outcome = outcome;
    }
    return Promise.resolve();
  }
}

export class FakeRazorpay implements RazorpayApi {
  orders: Array<Parameters<RazorpayApi["createOrder"]>[0]> = [];
  refunds: Array<[string, Parameters<RazorpayApi["refundPayment"]>[1]]> = [];
  orderError: Error | null = null;
  refundError: Error | null = null;
  payments = new Map<string, RazorpayPayment>([["pay_P6test0001", razorpayPayment()]]);
  orderLookups = new Map<string, RazorpayOrder>([["order_P6test0001", razorpayOrder()]]);
  captures: Array<[string, { amountPaise: number; currency: string }]> = [];
  /** Fails fetchPayment and fetchOrder (Razorpay unreachable). */
  fetchError: Error | null = null;
  captureError: Error | null = null;
  /** With captureError: the payment is captured all the same (a race). */
  captureAnyway = false;

  createOrder(args: Parameters<RazorpayApi["createOrder"]>[0]): Promise<RazorpayOrderCreated> {
    this.orders.push(args);
    if (this.orderError) return Promise.reject(this.orderError);
    return Promise.resolve({ id: "order_P6test0001", amount: args.amountPaise, currency: args.currency });
  }

  fetchPayment(paymentId: string): Promise<RazorpayPayment> {
    if (this.fetchError) return Promise.reject(this.fetchError);
    const payment = this.payments.get(paymentId);
    return payment ? Promise.resolve({ ...payment }) : Promise.reject(new RazorpayHttpError(400, "no such payment"));
  }

  fetchOrder(orderId: string): Promise<RazorpayOrder> {
    if (this.fetchError) return Promise.reject(this.fetchError);
    const order = this.orderLookups.get(orderId);
    return order ? Promise.resolve({ ...order }) : Promise.reject(new RazorpayHttpError(400, "no such order"));
  }

  capturePayment(paymentId: string, args: { amountPaise: number; currency: string }): Promise<RazorpayPayment> {
    this.captures.push([paymentId, args]);
    const payment = this.payments.get(paymentId);
    if (payment && (!this.captureError || this.captureAnyway)) payment.status = "captured";
    if (this.captureError) return Promise.reject(this.captureError);
    return payment ? Promise.resolve({ ...payment }) : Promise.reject(new RazorpayHttpError(400, "no such payment"));
  }

  refundPayment(
    paymentId: string,
    args?: Parameters<RazorpayApi["refundPayment"]>[1],
  ): Promise<RazorpayRefundCreated> {
    this.refunds.push([paymentId, args]);
    if (this.refundError) return Promise.reject(this.refundError);
    return Promise.resolve({ id: "rfnd_P6test0001", amount: 500000 });
  }
}

export function post(body: unknown, headers: Record<string, string> = { Authorization: "Bearer user-jwt" }): Request {
  return new Request("http://localhost/functions/v1/fn", {
    method: "POST",
    headers: { "Content-Type": "application/json", ...headers },
    body: typeof body === "string" ? body : JSON.stringify(body),
  });
}

/** A webhook request signed with fixtureConfig.webhookSecret. */
export async function signedWebhook(event: unknown, eventId?: string): Promise<Request> {
  const raw = JSON.stringify(event);
  const signature = await hmacSha256Hex(fixtureConfig.webhookSecret!, raw);
  return new Request("http://localhost/functions/v1/payments-webhook", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-Razorpay-Signature": signature,
      ...(eventId === undefined ? {} : { "X-Razorpay-Event-Id": eventId }),
    },
    body: raw,
  });
}

export function capturedEvent(orderId = "order_P6test0001", paymentId = "pay_P6test0001") {
  return {
    entity: "event",
    account_id: "acc_fixture",
    event: "payment.captured",
    contains: ["payment"],
    payload: {
      payment: {
        entity: {
          id: paymentId,
          entity: "payment",
          amount: 500000,
          currency: "INR",
          status: "captured",
          order_id: orderId,
        },
      },
    },
    created_at: 1790000000,
  };
}

export function failedEvent(orderId = "order_P6test0001", paymentId = "pay_P6test0001") {
  return {
    entity: "event",
    account_id: "acc_fixture",
    event: "payment.failed",
    contains: ["payment"],
    payload: {
      payment: {
        entity: {
          id: paymentId,
          entity: "payment",
          amount: 500000,
          currency: "INR",
          status: "failed",
          order_id: orderId,
          error_description: "Card declined by bank",
        },
      },
    },
    created_at: 1790000000,
  };
}

export function refundEvent(paymentId = "pay_P6test0001", refundId = "rfnd_P6test0002", amountPaise = 100000) {
  return {
    entity: "event",
    account_id: "acc_fixture",
    event: "refund.processed",
    contains: ["refund", "payment"],
    payload: {
      refund: {
        entity: {
          id: refundId,
          entity: "refund",
          amount: amountPaise,
          currency: "INR",
          payment_id: paymentId,
          status: "processed",
        },
      },
    },
    created_at: 1790000000,
  };
}
