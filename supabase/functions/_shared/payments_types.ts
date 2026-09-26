// The contract of the payments-* Edge Functions (spec: "Edge Functions").
// The Flutter client mirrors these shapes in
// lib/data/models/payment_order.dart; the SQL functions they wrap are in
// supabase/migrations/0055_online_payments.sql.

/** Mirrors public.payment_kind. */
export type PaymentKind = "advance" | "balance";

export interface Prefill {
  name: string | null;
  email: string | null;
  contact: string | null;
}

/** POST payments-create-order. `amount` is in rupees, as the app shows it. */
export interface CreateOrderRequest {
  reservation_id: string;
  amount: number;
  purpose: PaymentKind;
}

export type CreateOrderResponse =
  | { configured: false }
  | {
    configured: true;
    key_id: string;
    order_id: string;
    /** Paise. */
    amount: number;
    currency: "INR";
    name: string;
    description: string;
    reservation_id: string;
    prefill: Prefill;
  };

/** POST payments-create-order with {"probe": true}. */
export type ProbeResponse = { configured: false } | { configured: true; key_id: string };

/** POST payments-verify: the three values Razorpay Checkout hands back. */
export interface VerifyRequest {
  razorpay_order_id: string;
  razorpay_payment_id: string;
  razorpay_signature: string;
}

export type VerifyResponse =
  | { configured: false }
  | {
    configured: true;
    outcome: "paid" | "unapplied";
    reservation_id: string;
    kind: PaymentKind;
    refund: "initiated" | "failed" | null;
  }
  | {
    // Razorpay has not captured the money (yet), so nothing was settled.
    // The payment.captured webhook settles it if it is captured later.
    configured: true;
    outcome: "pending";
    reservation_id: string;
    kind: PaymentKind | null;
    refund: null;
  };

/** Every non-2xx body the three functions send. */
export interface ErrorBody {
  error:
    | "bad_request"
    | "unauthorized"
    | "db"
    | "gateway"
    | "invalid_signature"
    | "internal"
    | "not_configured";
  /** The Postgres error code, for error "db". */
  code?: string;
  message: string;
}

/** public.payment_order_quote's jsonb. */
export interface OrderQuote {
  reservation_id: string;
  property_id: string;
  property_name: string;
  customer_id: string;
  kind: PaymentKind;
  amount: number;
  amount_paise: number;
  currency: "INR";
  receipt: string;
  description: string;
  prefill: Prefill;
}

/** public.payment_order_settle's jsonb (built by payment_order_json). */
export interface SettleResult {
  order_id: string;
  reservation_id: string;
  kind: PaymentKind;
  amount: number;
  status: "paid" | "unapplied" | "refunded";
  razorpay_payment_id: string;
  reason: string | null;
  refund_needed: boolean;
}

/** A Postgres error from an RPC, with its SQLSTATE (e.g. "P0009"). */
export class DbError extends Error {
  constructor(readonly code: string, message: string) {
    super(message);
    this.name = "DbError";
  }
}

/** Calls made as the signed-in guest (their JWT). */
export interface UserPaymentsDb {
  quoteOrder(args: { reservationId: string; kind: PaymentKind; amount: number }): Promise<OrderQuote>;
}

/** Calls made with the service role. */
export interface ServicePaymentsDb {
  setLive(live: boolean, keyId: string | null): Promise<void>;
  openOrder(args: {
    reservationId: string;
    customerId: string;
    kind: PaymentKind;
    amount: number;
    razorpayOrderId: string;
  }): Promise<void>;
  /** null when the order id is not one of ours (P0002). */
  settleOrder(razorpayOrderId: string, razorpayPaymentId: string): Promise<SettleResult | null>;
  failOrder(razorpayOrderId: string, reason: string): Promise<void>;
  /** `amount` in rupees. */
  recordRefund(razorpayPaymentId: string, refundId: string, amount: number): Promise<void>;
  /** true while the event still needs processing. */
  beginWebhook(eventId: string, event: string, payload: unknown): Promise<boolean>;
  finishWebhook(eventId: string, outcome: string): Promise<void>;
}

export interface RazorpayOrderCreated {
  id: string;
  /** Paise. */
  amount: number;
  currency: string;
}

/** GET /v1/payments/:id (the fields we read). */
export interface RazorpayPayment {
  id: string;
  order_id: string | null;
  /** Paise. */
  amount: number;
  currency: string;
  /** created | authorized | captured | refunded | failed */
  status: string;
}

/** GET /v1/orders/:id (the fields we read). Empty notes come back as []. */
export interface RazorpayOrder {
  id: string;
  /** Paise. */
  amount: number;
  currency: string;
  notes: Record<string, string> | unknown[];
}

export interface RazorpayRefundCreated {
  id: string;
  /** Paise. */
  amount: number;
}

/** The Razorpay REST calls the functions make. */
export interface RazorpayApi {
  fetchPayment(paymentId: string): Promise<RazorpayPayment>;
  fetchOrder(orderId: string): Promise<RazorpayOrder>;
  /** POST /v1/payments/:id/capture: an authorized payment becomes captured. */
  capturePayment(paymentId: string, args: { amountPaise: number; currency: string }): Promise<RazorpayPayment>;
  createOrder(args: {
    amountPaise: number;
    currency: "INR";
    receipt: string;
    notes: Record<string, string>;
  }): Promise<RazorpayOrderCreated>;
  refundPayment(
    paymentId: string,
    args?: { amountPaise?: number; notes?: Record<string, string> },
  ): Promise<RazorpayRefundCreated>;
}

/** From the Edge Function secrets; null when the keys are not set. */
export interface RazorpayConfig {
  keyId: string;
  keySecret: string;
  webhookSecret: string | null;
}
