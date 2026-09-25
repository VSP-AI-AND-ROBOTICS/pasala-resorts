import {
  type CurrentSubscription,
  LIVE_STATUSES,
  type RazorpaySubscriptionStatus,
  type Tier,
} from "./types.ts";

export type SubscribeDecision =
  | { kind: "create" }
  | {
    kind: "reuse" | "unchanged";
    subscriptionId: string;
    shortUrl: string | null;
    status: RazorpaySubscriptionStatus;
  };

export type CancelDecision =
  | { kind: "none" }
  | { kind: "cancel"; subscriptionId: string; atCycleEnd: boolean };

const isLive = (status: RazorpaySubscriptionStatus) => LIVE_STATUSES.includes(status);

/**
 * Spec decisions 7 and 8: reuse an unauthorised link for the same tier;
 * leave a live subscription on the same tier alone unless it is ending;
 * otherwise create a new one (billing_subscription_opened then names the
 * old one for cancelling).
 */
export function decideSubscribe(current: CurrentSubscription | null, tier: Tier): SubscribeDecision {
  if (current === null || !isLive(current.status) || current.tier !== tier) {
    return { kind: "create" };
  }
  const same = {
    subscriptionId: current.razorpay_subscription_id,
    shortUrl: current.short_url,
    status: current.status,
  };
  if (current.status === "created") {
    return current.short_url ? { kind: "reuse", ...same } : { kind: "create" };
  }
  if (current.cancel_at_cycle_end) return { kind: "create" };
  return { kind: "unchanged", ...same };
}

/** Spec decision 9: authorised ends with its cycle; unauthorised ends now. */
export function decideCancel(current: CurrentSubscription | null): CancelDecision {
  if (current === null || !isLive(current.status)) return { kind: "none" };
  if (current.status === "created") {
    return { kind: "cancel", subscriptionId: current.razorpay_subscription_id, atCycleEnd: false };
  }
  if (current.cancel_at_cycle_end) return { kind: "none" };
  return { kind: "cancel", subscriptionId: current.razorpay_subscription_id, atCycleEnd: true };
}
