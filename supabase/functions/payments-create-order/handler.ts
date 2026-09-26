// payments-create-order: checks the amount as the signed-in guest,
// creates the Razorpay order and records it. See the spec's "Edge
// Functions" section. index.ts wires the real dependencies.
import { fail, json, preflight } from "../_shared/http.ts";
import {
  type CreateOrderResponse,
  DbError,
  type PaymentKind,
  type ProbeResponse,
  type RazorpayApi,
  type RazorpayConfig,
  type RazorpayOrderCreated,
  type ServicePaymentsDb,
  type UserPaymentsDb,
} from "../_shared/payments_types.ts";
import { paymentsLive } from "../_shared/razorpay.ts";

export interface CreateOrderDeps {
  /** Read on every request, so `supabase secrets set` takes effect without a redeploy. */
  config(): RazorpayConfig | null;
  service: ServicePaymentsDb;
  userDb(authorization: string): UserPaymentsDb;
  razorpay(config: RazorpayConfig): RazorpayApi;
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export type ParsedCreateOrder =
  | { probe: true }
  | { probe: false; reservationId: string; amount: number; kind: PaymentKind };

/** A message for the 400 answer, or the parsed request. */
export function parseCreateOrder(body: unknown): ParsedCreateOrder | string {
  if (typeof body !== "object" || body === null || Array.isArray(body)) {
    return "Body must be a JSON object.";
  }
  const b = body as Record<string, unknown>;
  if (b.probe === true) return { probe: true };
  if (typeof b.reservation_id !== "string" || !UUID.test(b.reservation_id)) {
    return "reservation_id must be a uuid.";
  }
  if (typeof b.amount !== "number" || !Number.isFinite(b.amount) || b.amount <= 0) {
    return "amount must be a positive number of rupees.";
  }
  if (b.purpose !== "advance" && b.purpose !== "balance") {
    return "purpose must be advance or balance.";
  }
  return { probe: false, reservationId: b.reservation_id, amount: b.amount, kind: b.purpose };
}

export function createOrderHandler(deps: CreateOrderDeps): (req: Request) => Promise<Response> {
  return async (req) => {
    if (req.method === "OPTIONS") return preflight();
    if (req.method !== "POST") return fail(405, "bad_request", "Use POST.");
    try {
      let body: unknown;
      try {
        body = await req.json();
      } catch {
        return fail(400, "bad_request", "Body must be JSON.");
      }
      const parsed = parseCreateOrder(body);
      if (typeof parsed === "string") return fail(400, "bad_request", parsed);

      // Keep the database's live switch in step with the secrets (spec
      // decision 5): on while the keys and the webhook secret are set, off
      // once any is removed. Without the webhook secret a guest who closes
      // the tab after paying is never settled, so no order is made either
      // (final review minor 3). payments-verify and payments-webhook keep
      // the switch in step too.
      const config = deps.config();
      const live = paymentsLive(config);
      await deps.service.setLive(live, live ? config.keyId : null);

      if (parsed.probe) {
        const probe: ProbeResponse = live
          ? { configured: true, key_id: config.keyId }
          : config
          ? { configured: false, missing: ["RAZORPAY_WEBHOOK_SECRET"] }
          : { configured: false };
        return json(200, probe);
      }
      if (!live) return json(200, { configured: false } satisfies CreateOrderResponse);

      const authorization = req.headers.get("Authorization") ?? "";
      if (!authorization.startsWith("Bearer ")) return fail(401, "unauthorized", "Sign in to pay.");

      // As the guest: their booking, the right status, an accepted amount.
      const quote = await deps.userDb(authorization).quoteOrder({
        reservationId: parsed.reservationId,
        kind: parsed.kind,
        amount: parsed.amount,
      });

      let order: RazorpayOrderCreated;
      try {
        order = await deps.razorpay(config).createOrder({
          amountPaise: quote.amount_paise,
          currency: "INR",
          receipt: quote.receipt,
          notes: { reservation_id: quote.reservation_id, property_id: quote.property_id, kind: quote.kind },
        });
      } catch (e) {
        console.error("payments-create-order: Razorpay order failed", e);
        return fail(502, "gateway", "The payment provider did not respond. Try again.");
      }

      await deps.service.openOrder({
        reservationId: quote.reservation_id,
        customerId: quote.customer_id,
        kind: quote.kind,
        amount: quote.amount,
        razorpayOrderId: order.id,
      });

      const response: CreateOrderResponse = {
        configured: true,
        key_id: config.keyId,
        order_id: order.id,
        amount: order.amount,
        currency: "INR",
        name: quote.property_name,
        description: quote.description,
        reservation_id: quote.reservation_id,
        prefill: quote.prefill,
      };
      return json(200, response);
    } catch (e) {
      if (e instanceof DbError) return fail(409, "db", e.message, e.code);
      console.error("payments-create-order", e);
      return fail(500, "internal", "Something went wrong. Try again.");
    }
  };
}
