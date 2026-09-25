// billing-subscribe (P8): the resort owner's probe, subscribe and cancel.
// Reads run as the caller (billing_subscribe_state asserts the owner);
// the billing writes run as the service role. See the spec's
// "Edge Functions" section.
import { decideCancel, decideSubscribe } from "../_shared/billing/decide.ts";
import { fail, json, preflight } from "../_shared/billing/http.ts";
import {
  RazorpayError,
  type RazorpayKeys,
  type RazorpaySubscriptions,
} from "../_shared/billing/razorpay_subscriptions.ts";
import {
  type BillingDb,
  type CancelResponse,
  DbError,
  type NotConfigured,
  type ProbeResponse,
  type SubscribeRequest,
  type SubscribeResponse,
  type Tier,
  TIERS,
} from "../_shared/billing/types.ts";

/** Monthly cycles per subscription: 5 years (spec decision 15). */
export const TOTAL_COUNT = 60;

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export interface SubscribeDeps {
  /** Null while RAZORPAY_KEY_ID / RAZORPAY_KEY_SECRET are unset. */
  keys: RazorpayKeys | null;
  razorpay: (keys: RazorpayKeys) => RazorpaySubscriptions;
  db: (callerJwt: string) => BillingDb;
}

/** The request, or a message saying what is wrong with it. */
export function parseRequest(body: unknown): SubscribeRequest | string {
  if (typeof body !== "object" || body === null) return "The body must be a JSON object.";
  const b = body as Record<string, unknown>;
  if (typeof b.property_id !== "string" || !UUID.test(b.property_id)) {
    return "property_id must be a resort id.";
  }
  if (b.action !== "probe" && b.action !== "subscribe" && b.action !== "cancel") {
    return "action must be probe, subscribe or cancel.";
  }
  if (b.action === "subscribe" && !TIERS.includes(b.tier as Tier)) {
    return "tier must be starter, pro or enterprise.";
  }
  return {
    property_id: b.property_id,
    action: b.action,
    tier: b.action === "subscribe" ? b.tier as Tier : undefined,
  };
}

/** Cancels each id now; false when any of them could not be cancelled. */
async function cancelStale(
  db: BillingDb,
  razorpay: RazorpaySubscriptions,
  ids: string[],
  actor: string | null,
): Promise<boolean> {
  let all = true;
  for (const id of ids) {
    try {
      const res = await razorpay.cancel(id, false);
      await db.cancelRequested(id, false, res.status, actor);
    } catch (e) {
      console.error("billing-subscribe: could not cancel", id, e);
      all = false;
    }
  }
  return all;
}

async function subscribe(
  db: BillingDb,
  razorpay: RazorpaySubscriptions,
  propertyId: string,
  tier: Tier,
): Promise<SubscribeResponse> {
  const state = await db.subscribeState(propertyId, tier);
  if (!state.plan_id) throw new DbError("P0038", "billing_unavailable");
  let cleanedUp = await cancelStale(db, razorpay, state.stale, state.caller_id);
  const warning = () => cleanedUp ? {} : { warning: "previous_not_cancelled" as const };

  const decision = decideSubscribe(state.current, tier);
  if (decision.kind !== "create") {
    return {
      configured: true,
      action: decision.kind === "reuse" ? "reused" : "unchanged",
      subscription_id: decision.subscriptionId,
      short_url: decision.shortUrl,
      status: decision.status,
      ...warning(),
    };
  }

  const created = await razorpay.create({
    planId: state.plan_id,
    totalCount: TOTAL_COUNT,
    startAt: state.start_at,
    notifyEmail: state.notify_email,
    notes: { property_id: propertyId, tier },
  });
  let opened;
  try {
    opened = await db.opened({
      property_id: propertyId,
      tier,
      razorpay_plan_id: state.plan_id,
      razorpay_subscription_id: created.id,
      status: created.status,
      short_url: created.short_url,
      start_at: state.start_at,
      created_by: state.caller_id,
    });
  } catch (e) {
    // Unrecorded, the new subscription could be authorised from Razorpay's
    // email and charge every month with nothing here able to see or cancel
    // it, so cancel it now (best effort) before answering the failure.
    try {
      await razorpay.cancel(created.id, false);
    } catch (cancelError) {
      console.error("billing-subscribe: could not cancel unrecorded", created.id, cancelError);
    }
    throw e;
  }
  cleanedUp = (await cancelStale(db, razorpay, opened.stale, state.caller_id)) && cleanedUp;
  return {
    configured: true,
    action: "created",
    subscription_id: created.id,
    short_url: created.short_url,
    status: created.status,
    ...warning(),
  };
}

async function cancel(
  db: BillingDb,
  razorpay: RazorpaySubscriptions,
  propertyId: string,
): Promise<CancelResponse> {
  const state = await db.subscribeState(propertyId, null);
  await cancelStale(db, razorpay, state.stale, state.caller_id);
  const decision = decideCancel(state.current);
  if (decision.kind === "none") {
    return {
      configured: true,
      action: "none",
      subscription_id: state.current?.razorpay_subscription_id ?? null,
      status: state.current?.status ?? null,
    };
  }
  const res = await razorpay.cancel(decision.subscriptionId, decision.atCycleEnd);
  await db.cancelRequested(decision.subscriptionId, decision.atCycleEnd, res.status, state.caller_id);
  return {
    configured: true,
    action: decision.atCycleEnd ? "cancel_scheduled" : "cancelled",
    subscription_id: decision.subscriptionId,
    status: res.status,
  };
}

export function makeSubscribeHandler(deps: SubscribeDeps): (req: Request) => Promise<Response> {
  return async (req) => {
    if (req.method === "OPTIONS") return preflight();
    if (req.method !== "POST") return fail(405, "method_not_allowed", "Use POST.");

    const auth = req.headers.get("Authorization") ?? "";
    const jwt = auth.startsWith("Bearer ") ? auth.slice(7).trim() : "";
    if (!jwt) return fail(401, "unauthorized", "Sign in first.");

    let raw: unknown;
    try {
      raw = await req.json();
    } catch {
      return fail(400, "bad_request", "The body must be JSON.");
    }
    const request = parseRequest(raw);
    if (typeof request === "string") return fail(400, "bad_request", request);

    if (deps.keys === null) return json(200, { configured: false } satisfies NotConfigured);

    try {
      const db = deps.db(jwt);
      switch (request.action) {
        case "probe":
          return json(200, { configured: true, plans: await db.billablePlans() } satisfies ProbeResponse);
        case "subscribe":
          return json(200, await subscribe(db, deps.razorpay(deps.keys), request.property_id, request.tier!));
        case "cancel":
          return json(200, await cancel(db, deps.razorpay(deps.keys), request.property_id));
      }
    } catch (e) {
      if (e instanceof DbError) return fail(409, "db", e.message, e.code);
      if (e instanceof RazorpayError) return fail(502, "gateway", e.description);
      console.error("billing-subscribe", e);
      return fail(500, "internal", "Something went wrong.");
    }
  };
}
