// Fakes for the billing handlers' tests. Nothing here touches the network
// or a database.
import type {
  ApplyResult,
  BillablePlan,
  BillingDb,
  OpenedArgs,
  OpenedResult,
  RazorpaySubscriptionStatus,
  SubscribeState,
  Tier,
} from "./types.ts";
import {
  type CreateSubscriptionInput,
  RazorpayError,
  type RazorpaySubscription,
  type RazorpaySubscriptions,
} from "./razorpay_subscriptions.ts";

export function subscribeState(overrides: Partial<SubscribeState> = {}): SubscribeState {
  return {
    property_id: "11111111-1111-4111-8111-111111111111",
    property_name: "Resort A",
    caller_id: "22222222-2222-4222-8222-222222222222",
    notify_email: "owner@example.com",
    tier: "pro",
    plan_id: "plan_ProMonthly0001",
    start_at: null,
    current: null,
    stale: [],
    ...overrides,
  };
}

export function rzpSubscription(overrides: Partial<RazorpaySubscription> = {}): RazorpaySubscription {
  return {
    id: "sub_NewSub0000001",
    plan_id: "plan_ProMonthly0001",
    status: "created",
    short_url: "https://rzp.io/i/new",
    current_start: null,
    current_end: null,
    ...overrides,
  };
}

/**
 * Records every call in `calls`; `error`, when set, is thrown by every call,
 * and `failOn[method]`, when set, is thrown by that method only.
 */
export class FakeBillingDb implements BillingDb {
  plans: BillablePlan[] = [];
  state: SubscribeState = subscribeState();
  openedResult: OpenedResult = { id: "row-1", stale: [] };
  applyResult: ApplyResult = { outcome: "updated", property_id: null, cancel_subscription_id: null };
  error: Error | null = null;
  failOn: Partial<Record<keyof BillingDb, Error>> = {};
  calls: { method: string; args: unknown[] }[] = [];

  private record(method: string, args: unknown[]): void {
    this.calls.push({ method, args });
    if (this.error) throw this.error;
    const failure = this.failOn[method as keyof BillingDb];
    if (failure) throw failure;
  }

  callsTo(method: string): unknown[][] {
    return this.calls.filter((c) => c.method === method).map((c) => c.args);
  }

  async billablePlans(): Promise<BillablePlan[]> {
    this.record("billablePlans", []);
    return this.plans;
  }

  async subscribeState(propertyId: string, tier: Tier | null): Promise<SubscribeState> {
    this.record("subscribeState", [propertyId, tier]);
    return this.state;
  }

  async opened(args: OpenedArgs): Promise<OpenedResult> {
    this.record("opened", [args]);
    return this.openedResult;
  }

  async cancelRequested(
    subscriptionId: string,
    atCycleEnd: boolean,
    status: RazorpaySubscriptionStatus | null,
    actor: string | null,
  ): Promise<void> {
    this.record("cancelRequested", [subscriptionId, atCycleEnd, status, actor]);
  }

  async applyWebhook(
    event: string,
    eventAt: string | null,
    subscription: Record<string, unknown>,
    payment: Record<string, unknown> | null,
  ): Promise<ApplyResult> {
    this.record("applyWebhook", [event, eventAt, subscription, payment]);
    return this.applyResult;
  }
}

/** Records creates and cancels; `failCreate` / `failCancel` make them throw. */
export class FakeRazorpay implements RazorpaySubscriptions {
  created: CreateSubscriptionInput[] = [];
  cancelled: { id: string; atCycleEnd: boolean }[] = [];
  createResult: RazorpaySubscription = rzpSubscription();
  failCreate: RazorpayError | null = null;
  failCancel: RazorpayError | null = null;

  async create(input: CreateSubscriptionInput): Promise<RazorpaySubscription> {
    this.created.push(input);
    if (this.failCreate) throw this.failCreate;
    return this.createResult;
  }

  async cancel(subscriptionId: string, atCycleEnd: boolean): Promise<RazorpaySubscription> {
    this.cancelled.push({ id: subscriptionId, atCycleEnd });
    if (this.failCancel) throw this.failCancel;
    return rzpSubscription({ id: subscriptionId, status: atCycleEnd ? "active" : "cancelled" });
  }
}
