// payments-webhook: Razorpay's server-to-server events. Settles captured
// payments the app never verified (the guest closed the tab), records
// failures and refunds. Each event is processed once (spec decision 12).
import { fail, json, preflight } from "../_shared/http.ts";
import type { RazorpayApi, RazorpayConfig, ServicePaymentsDb } from "../_shared/payments_types.ts";
import { sha256Hex, verifyWebhookSignature } from "../_shared/razorpay.ts";
import { refundIfNeeded } from "../_shared/settlement.ts";

export interface WebhookDeps {
  config(): RazorpayConfig | null;
  service: ServicePaymentsDb;
  razorpay(config: RazorpayConfig): RazorpayApi;
}

type Json = Record<string, unknown>;

function isObject(value: unknown): value is Json {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

/** payload.<kind>.entity, when present. */
function entity(event: Json, kind: "payment" | "refund"): Json | null {
  const payload = event.payload;
  if (!isObject(payload)) return null;
  const wrapper = payload[kind];
  if (!isObject(wrapper)) return null;
  return isObject(wrapper.entity) ? wrapper.entity : null;
}

/** Handles one verified event; returns the outcome stored in the ledger. */
export async function handleEvent(event: Json, config: RazorpayConfig, deps: WebhookDeps): Promise<string> {
  const name = typeof event.event === "string" ? event.event : "unknown";
  switch (name) {
    case "payment.captured": {
      const payment = entity(event, "payment");
      if (!payment || typeof payment.id !== "string" || typeof payment.order_id !== "string") {
        return "ignored:no_order";
      }
      const settled = await deps.service.settleOrder(payment.order_id, payment.id);
      // Not one of our orders (e.g. a P8 subscription charge).
      if (!settled) return "ignored:unknown_order";
      const refund = await refundIfNeeded(settled, deps.razorpay(config), deps.service);
      return `settled:${settled.status}${refund ? `:refund_${refund}` : ""}`;
    }
    case "payment.failed": {
      const payment = entity(event, "payment");
      if (!payment || typeof payment.order_id !== "string") return "ignored:no_order";
      const reason = typeof payment.error_description === "string" ? payment.error_description : "payment failed";
      await deps.service.failOrder(payment.order_id, reason);
      return "failed";
    }
    case "refund.processed": {
      const refund = entity(event, "refund");
      if (
        !refund || typeof refund.id !== "string" || typeof refund.payment_id !== "string" ||
        typeof refund.amount !== "number"
      ) {
        return "ignored:no_refund";
      }
      await deps.service.recordRefund(refund.payment_id, refund.id, refund.amount / 100);
      return "refund_recorded";
    }
    default:
      return `ignored:${name}`;
  }
}

export function webhookHandler(deps: WebhookDeps): (req: Request) => Promise<Response> {
  return async (req) => {
    if (req.method === "OPTIONS") return preflight();
    if (req.method !== "POST") return fail(405, "bad_request", "Use POST.");

    const config = deps.config();
    if (!config || !config.webhookSecret) {
      return fail(503, "not_configured", "Razorpay webhooks are not configured.");
    }

    try {
      const raw = await req.text();
      const signature = req.headers.get("X-Razorpay-Signature") ?? "";
      if (!(await verifyWebhookSignature(raw, signature, config.webhookSecret))) {
        return fail(401, "invalid_signature", "Bad signature.");
      }

      let event: Json;
      try {
        const parsed: unknown = JSON.parse(raw);
        if (!isObject(parsed)) return fail(400, "bad_request", "Body must be a JSON object.");
        event = parsed;
      } catch {
        return fail(400, "bad_request", "Body must be JSON.");
      }

      const eventId = req.headers.get("X-Razorpay-Event-Id")?.trim() || `sha256:${await sha256Hex(raw)}`;
      const name = typeof event.event === "string" ? event.event : "unknown";
      if (!(await deps.service.beginWebhook(eventId, name, event))) {
        return json(200, { status: "duplicate" });
      }

      const outcome = await handleEvent(event, config, deps);
      // Only after it was handled: a crash above leaves the event
      // unfinished, and Razorpay's retry processes it again.
      await deps.service.finishWebhook(eventId, outcome);
      return json(200, { status: "processed", outcome });
    } catch (e) {
      console.error("payments-webhook", e);
      return fail(500, "internal", "Processing failed; Razorpay will retry.");
    }
  };
}
