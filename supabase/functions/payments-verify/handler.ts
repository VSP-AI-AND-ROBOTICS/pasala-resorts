// payments-verify: checks Razorpay Checkout's signature and settles the
// payment in the database (spec decision 6).
import { fail, json, preflight } from "../_shared/http.ts";
import {
  DbError,
  type RazorpayApi,
  type RazorpayConfig,
  type ServicePaymentsDb,
  type VerifyResponse,
} from "../_shared/payments_types.ts";
import { verifyPaymentSignature } from "../_shared/razorpay.ts";
import { refundIfNeeded } from "../_shared/settlement.ts";

export interface VerifyDeps {
  config(): RazorpayConfig | null;
  service: ServicePaymentsDb;
  razorpay(config: RazorpayConfig): RazorpayApi;
}

export type ParsedVerify = { orderId: string; paymentId: string; signature: string };

export function parseVerify(body: unknown): ParsedVerify | string {
  if (typeof body !== "object" || body === null || Array.isArray(body)) {
    return "Body must be a JSON object.";
  }
  const b = body as Record<string, unknown>;
  const values: string[] = [];
  for (const field of ["razorpay_order_id", "razorpay_payment_id", "razorpay_signature"]) {
    const value = b[field];
    if (typeof value !== "string" || value.trim() === "" || value.length > 200) {
      return `${field} is required.`;
    }
    values.push(value.trim());
  }
  return { orderId: values[0], paymentId: values[1], signature: values[2] };
}

export function verifyHandler(deps: VerifyDeps): (req: Request) => Promise<Response> {
  return async (req) => {
    if (req.method === "OPTIONS") return preflight();
    if (req.method !== "POST") return fail(405, "bad_request", "Use POST.");
    try {
      const authorization = req.headers.get("Authorization") ?? "";
      if (!authorization.startsWith("Bearer ")) return fail(401, "unauthorized", "Sign in to pay.");

      let body: unknown;
      try {
        body = await req.json();
      } catch {
        return fail(400, "bad_request", "Body must be JSON.");
      }
      const parsed = parseVerify(body);
      if (typeof parsed === "string") return fail(400, "bad_request", parsed);

      const config = deps.config();
      if (!config) return json(200, { configured: false } satisfies VerifyResponse);

      const valid = await verifyPaymentSignature(
        parsed.orderId,
        parsed.paymentId,
        parsed.signature,
        config.keySecret,
      );
      if (!valid) return fail(400, "invalid_signature", "The payment could not be verified.");

      const settled = await deps.service.settleOrder(parsed.orderId, parsed.paymentId);
      if (!settled) return fail(409, "db", "payment_order_not_found", "P0002");

      const refund = await refundIfNeeded(settled, deps.razorpay(config), deps.service);
      const response: VerifyResponse = {
        configured: true,
        outcome: settled.status === "paid" ? "paid" : "unapplied",
        reservation_id: settled.reservation_id,
        kind: settled.kind,
        refund,
      };
      return json(200, response);
    } catch (e) {
      if (e instanceof DbError) return fail(409, "db", e.message, e.code);
      console.error("payments-verify", e);
      return fail(500, "internal", "Something went wrong. Try again.");
    }
  };
}
