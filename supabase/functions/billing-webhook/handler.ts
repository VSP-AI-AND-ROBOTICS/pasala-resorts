// billing-webhook (P8): Razorpay's subscription.* events. Called by
// Razorpay without a Supabase JWT (verify_jwt = false), so the signature
// over the raw body is the only authentication. The plan rules live in
// billing_webhook_apply (0057).
import { fail, json } from "../_shared/billing/http.ts";
import type { RazorpayKeys, RazorpaySubscriptions } from "../_shared/billing/razorpay_subscriptions.ts";
import { verifyWebhookSignature } from "../_shared/billing/signature.ts";
import { type ApplyResult, type BillingDb, DbError, type WebhookResponse } from "../_shared/billing/types.ts";

export interface WebhookDeps {
  /** RAZORPAY_BILLING_WEBHOOK_SECRET, else RAZORPAY_WEBHOOK_SECRET; null = 503. */
  webhookSecret: string | null;
  /** Needed only to cancel a replaced subscription that is still live. */
  keys: RazorpayKeys | null;
  razorpay: (keys: RazorpayKeys) => RazorpaySubscriptions;
  db: () => BillingDb;
}

interface RazorpayEvent {
  event?: unknown;
  created_at?: unknown;
  payload?: {
    subscription?: { entity?: Record<string, unknown> };
    payment?: { entity?: Record<string, unknown> };
  };
}

export function makeWebhookHandler(deps: WebhookDeps): (req: Request) => Promise<Response> {
  return async (req) => {
    if (req.method !== "POST") return fail(405, "method_not_allowed", "Use POST.", undefined, false);
    if (!deps.webhookSecret) {
      return fail(503, "not_configured", "The billing webhook secret is not set.", undefined, false);
    }

    const raw = await req.text();
    const valid = await verifyWebhookSignature(raw, req.headers.get("X-Razorpay-Signature"), deps.webhookSecret);
    if (!valid) return fail(401, "invalid_signature", "The signature does not match.", undefined, false);

    let body: RazorpayEvent;
    try {
      body = JSON.parse(raw);
    } catch {
      return fail(400, "bad_request", "The body must be JSON.", undefined, false);
    }

    const event = typeof body?.event === "string" ? body.event : "";
    if (!event.startsWith("subscription.")) {
      return json(200, { status: "ignored" } satisfies WebhookResponse, false);
    }
    const subscription = body.payload?.subscription?.entity;
    if (!subscription || typeof subscription.id !== "string") {
      return fail(400, "bad_request", "A subscription event needs its subscription.", undefined, false);
    }
    const payment = body.payload?.payment?.entity ?? null;
    const eventAt = typeof body.created_at === "number" ? new Date(body.created_at * 1000).toISOString() : null;

    const db = deps.db();
    let result: ApplyResult;
    try {
      result = await db.applyWebhook(event, eventAt, subscription, payment);
    } catch (e) {
      console.error("billing-webhook", event, e);
      return e instanceof DbError
        ? fail(500, "db", "Could not record the event.", e.code, false)
        : fail(500, "internal", "Could not record the event.", undefined, false);
    }

    if (result.cancel_subscription_id && deps.keys) {
      try {
        const res = await deps.razorpay(deps.keys).cancel(result.cancel_subscription_id, false);
        await db.cancelRequested(result.cancel_subscription_id, false, res.status, null);
      } catch (e) {
        // The next event for it, or the owner's next subscribe, retries.
        console.error("billing-webhook: could not cancel", result.cancel_subscription_id, e);
      }
    }

    return json(200, { status: "processed", outcome: result.outcome } satisfies WebhookResponse, false);
  };
}
