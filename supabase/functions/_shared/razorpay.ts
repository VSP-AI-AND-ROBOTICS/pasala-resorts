// Razorpay for the Edge Functions: reading the secrets, the two HMAC
// signatures, and the Orders, Payments and Refunds REST calls. No Razorpay SDK:
// fetch and Web Crypto only, so tests inject `fetch`. P8 (subscription
// billing) reuses this module.
import type {
  RazorpayApi,
  RazorpayConfig,
  RazorpayOrder,
  RazorpayOrderCreated,
  RazorpayPayment,
  RazorpayRefundCreated,
  RefundArgs,
} from "./payments_types.ts";

export const RAZORPAY_API = "https://api.razorpay.com/v1";

/** null unless both RAZORPAY_KEY_ID and RAZORPAY_KEY_SECRET are set. */
export function readConfig(get: (name: string) => string | undefined): RazorpayConfig | null {
  const keyId = get("RAZORPAY_KEY_ID")?.trim() ?? "";
  const keySecret = get("RAZORPAY_KEY_SECRET")?.trim() ?? "";
  if (keyId === "" || keySecret === "") return null;
  const webhookSecret = get("RAZORPAY_WEBHOOK_SECRET")?.trim() ?? "";
  return { keyId, keySecret, webhookSecret: webhookSecret === "" ? null : webhookSecret };
}

/**
 * Whether online payments are on: both keys AND the webhook secret. Without
 * the webhook secret payments-webhook answers 503, so a guest who closes the
 * tab after paying would never be settled or refunded (final review minor 3).
 */
export function paymentsLive(config: RazorpayConfig | null): config is RazorpayConfig & { webhookSecret: string } {
  return config !== null && config.webhookSecret !== null;
}

const encoder = new TextEncoder();

function toHex(buffer: ArrayBuffer): string {
  return Array.from(new Uint8Array(buffer), (b) => b.toString(16).padStart(2, "0")).join("");
}

export async function hmacSha256Hex(secret: string, message: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  return toHex(await crypto.subtle.sign("HMAC", key, encoder.encode(message)));
}

export async function sha256Hex(message: string): Promise<string> {
  return toHex(await crypto.subtle.digest("SHA-256", encoder.encode(message)));
}

/** Compares in time that does not depend on where the strings differ. */
export function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

/** Checkout's razorpay_signature = HMAC_SHA256(order_id|payment_id, key_secret). */
export async function verifyPaymentSignature(
  orderId: string,
  paymentId: string,
  signature: string,
  keySecret: string,
): Promise<boolean> {
  if (!orderId || !paymentId || !signature) return false;
  const expected = await hmacSha256Hex(keySecret, `${orderId}|${paymentId}`);
  return timingSafeEqual(expected, signature.trim().toLowerCase());
}

/** X-Razorpay-Signature = HMAC_SHA256(raw request body, webhook secret). */
export async function verifyWebhookSignature(
  rawBody: string,
  signature: string,
  webhookSecret: string,
): Promise<boolean> {
  if (!signature) return false;
  const expected = await hmacSha256Hex(webhookSecret, rawBody);
  return timingSafeEqual(expected, signature.trim().toLowerCase());
}

/** A non-2xx answer from Razorpay. The body is logged, never shown. */
export class RazorpayHttpError extends Error {
  constructor(readonly status: number, readonly body: string) {
    super(`Razorpay answered HTTP ${status}`);
    this.name = "RazorpayHttpError";
  }
}

export type FetchFn = (input: string, init: RequestInit) => Promise<Response>;

export class RazorpayClient implements RazorpayApi {
  constructor(
    private readonly config: RazorpayConfig,
    private readonly fetchFn: FetchFn = (input, init) => fetch(input, init),
    private readonly baseUrl: string = RAZORPAY_API,
  ) {}

  private async request<T>(
    method: "GET" | "POST",
    path: string,
    body?: unknown,
    extraHeaders: Record<string, string> = {},
  ): Promise<T> {
    const headers: Record<string, string> = {
      ...extraHeaders,
      "Authorization": `Basic ${btoa(`${this.config.keyId}:${this.config.keySecret}`)}`,
    };
    if (body !== undefined) headers["Content-Type"] = "application/json";
    const response = await this.fetchFn(`${this.baseUrl}${path}`, {
      method,
      headers,
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    const text = await response.text();
    if (!response.ok) throw new RazorpayHttpError(response.status, text);
    return JSON.parse(text) as T;
  }

  private post<T>(path: string, body: unknown): Promise<T> {
    return this.request<T>("POST", path, body);
  }

  /** GET /v1/payments/:id. */
  fetchPayment(paymentId: string): Promise<RazorpayPayment> {
    return this.request<RazorpayPayment>("GET", `/payments/${encodeURIComponent(paymentId)}`);
  }

  /** GET /v1/orders/:id. */
  fetchOrder(orderId: string): Promise<RazorpayOrder> {
    return this.request<RazorpayOrder>("GET", `/orders/${encodeURIComponent(orderId)}`);
  }

  /** POST /v1/payments/:id/capture. The amount must equal the payment's. */
  capturePayment(paymentId: string, args: { amountPaise: number; currency: string }): Promise<RazorpayPayment> {
    return this.post<RazorpayPayment>(`/payments/${encodeURIComponent(paymentId)}/capture`, {
      amount: args.amountPaise,
      currency: args.currency,
    });
  }

  /** POST /v1/orders. Amounts are paise. */
  createOrder(args: {
    amountPaise: number;
    currency: "INR";
    receipt: string;
    notes: Record<string, string>;
  }): Promise<RazorpayOrderCreated> {
    return this.post<RazorpayOrderCreated>("/orders", {
      amount: args.amountPaise,
      currency: args.currency,
      receipt: args.receipt,
      notes: args.notes,
    });
  }

  /**
   * POST /v1/payments/:id/refund. No amount = the full payment. With an
   * idempotency key (X-Refund-Idempotency), a repeat of the same request
   * returns the first refund instead of making another.
   */
  refundPayment(
    paymentId: string,
    args: RefundArgs = {},
  ): Promise<RazorpayRefundCreated> {
    const body: Record<string, unknown> = {};
    if (args.amountPaise !== undefined) body.amount = args.amountPaise;
    body.notes = args.notes ?? {};
    if (args.receipt !== undefined) body.receipt = args.receipt;
    return this.request<RazorpayRefundCreated>(
      "POST",
      `/payments/${encodeURIComponent(paymentId)}/refund`,
      body,
      args.idempotencyKey === undefined ? {} : { "X-Refund-Idempotency": args.idempotencyKey },
    );
  }
}
