// The contract of the billing Edge Functions (P8). Names match the SQL
// functions in supabase/migrations/0057_subscription_billing.sql and the
// Flutter side in lib/data/repositories/billing_repository.dart.

export type Tier = "starter" | "pro" | "enterprise";
export const TIERS: readonly Tier[] = ["starter", "pro", "enterprise"];

/** Razorpay's subscription states (billing_subscriptions.status). */
export type RazorpaySubscriptionStatus =
  | "created"
  | "authenticated"
  | "active"
  | "pending"
  | "halted"
  | "cancelled"
  | "completed"
  | "expired"
  | "paused";

/** States in which a subscription can still be authorised or charge. */
export const LIVE_STATUSES: readonly RazorpaySubscriptionStatus[] = [
  "created",
  "authenticated",
  "active",
  "pending",
  "paused",
];

// --- billing-subscribe ----------------------------------------------------

export type BillingAction = "probe" | "subscribe" | "cancel";

export interface SubscribeRequest {
  property_id: string;
  action: BillingAction;
  /** Required for "subscribe". */
  tier?: Tier;
}

export interface BillablePlan {
  tier: Tier;
  name: string;
  monthly_price_inr: number;
}

/** Every action's answer while RAZORPAY_KEY_ID / _SECRET are unset. */
export interface NotConfigured {
  configured: false;
}

export interface ProbeResponse {
  configured: true;
  /** Only the tiers with a Razorpay plan id, cheapest first. */
  plans: BillablePlan[];
}

export interface SubscribeResponse {
  configured: true;
  action: "created" | "reused" | "unchanged";
  subscription_id: string;
  short_url: string | null;
  status: RazorpaySubscriptionStatus;
  /** A replaced subscription could not be cancelled; it will be retried. */
  warning?: "previous_not_cancelled";
}

export interface CancelResponse {
  configured: true;
  action: "cancel_scheduled" | "cancelled" | "none";
  subscription_id: string | null;
  status: RazorpaySubscriptionStatus | null;
}

export type ErrorKind =
  | "bad_request"
  | "unauthorized"
  | "method_not_allowed"
  | "db"
  | "gateway"
  | "invalid_signature"
  | "not_configured"
  | "internal";

export interface ErrorBody {
  error: ErrorKind;
  /** The Postgres error code, for "db". */
  code?: string;
  message: string;
}

// --- billing-webhook -------------------------------------------------------

export type ApplyOutcome =
  | "ignored"
  | "updated"
  | "stale"
  | "charged"
  | "duplicate"
  | "lapsed"
  | "cancelled";

export interface WebhookResponse {
  status: "processed" | "ignored";
  outcome?: ApplyOutcome;
}

// --- the database (0057) ---------------------------------------------------

export interface CurrentSubscription {
  razorpay_subscription_id: string;
  tier: Tier;
  status: RazorpaySubscriptionStatus;
  short_url: string | null;
  cancel_at_cycle_end: boolean;
}

/** What billing_subscribe_state(p_property, p_tier) returns. */
export interface SubscribeState {
  property_id: string;
  property_name: string;
  caller_id: string;
  notify_email: string | null;
  tier: Tier | null;
  plan_id: string | null;
  /** Unix seconds; null = start now. */
  start_at: number | null;
  current: CurrentSubscription | null;
  /** Replaced subscriptions still live: cancel them. */
  stale: string[];
}

export interface OpenedArgs {
  property_id: string;
  tier: Tier;
  razorpay_plan_id: string;
  razorpay_subscription_id: string;
  status: RazorpaySubscriptionStatus;
  short_url: string | null;
  start_at: number | null;
  created_by: string;
}

export interface OpenedResult {
  id: string;
  stale: string[];
}

export interface ApplyResult {
  outcome: ApplyOutcome;
  property_id: string | null;
  cancel_subscription_id: string | null;
}

/** A Postgres error, with its SQLSTATE (e.g. P0020, P0038). */
export class DbError extends Error {
  constructor(readonly code: string, message: string) {
    super(message);
    this.name = "DbError";
  }
}

/**
 * Every database call the two functions make. billablePlans and
 * subscribeState run as the signed-in caller; the rest as the service role.
 */
export interface BillingDb {
  billablePlans(): Promise<BillablePlan[]>;
  subscribeState(propertyId: string, tier: Tier | null): Promise<SubscribeState>;
  opened(args: OpenedArgs): Promise<OpenedResult>;
  cancelRequested(
    subscriptionId: string,
    atCycleEnd: boolean,
    status: RazorpaySubscriptionStatus | null,
    actor: string | null,
  ): Promise<void>;
  applyWebhook(
    event: string,
    eventAt: string | null,
    subscription: Record<string, unknown>,
    payment: Record<string, unknown> | null,
  ): Promise<ApplyResult>;
}
