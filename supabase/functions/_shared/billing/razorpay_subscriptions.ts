import type { RazorpaySubscriptionStatus } from "./types.ts";

export const RAZORPAY_API = "https://api.razorpay.com/v1";

export interface RazorpayKeys {
  keyId: string;
  keySecret: string;
}

/** The fields of Razorpay's subscription entity this app reads. */
export interface RazorpaySubscription {
  id: string;
  plan_id: string;
  status: RazorpaySubscriptionStatus;
  short_url: string | null;
  current_start: number | null;
  current_end: number | null;
}

export interface CreateSubscriptionInput {
  planId: string;
  totalCount: number;
  /** Unix seconds; null = start now. */
  startAt: number | null;
  notifyEmail: string | null;
  notes: Record<string, string>;
}

export interface RazorpaySubscriptions {
  create(input: CreateSubscriptionInput): Promise<RazorpaySubscription>;
  cancel(subscriptionId: string, atCycleEnd: boolean): Promise<RazorpaySubscription>;
}

/** Razorpay refused (status >= 400) or could not be reached (status 0). */
export class RazorpayError extends Error {
  constructor(readonly status: number, readonly description: string) {
    super(`Razorpay answered ${status}: ${description}`);
    this.name = "RazorpayError";
  }
}

/** The Subscriptions API with the platform's keys; fetch is injectable. */
export class RazorpaySubscriptionsClient implements RazorpaySubscriptions {
  constructor(
    private readonly keys: RazorpayKeys,
    private readonly fetchFn: typeof fetch = fetch,
  ) {}

  create(input: CreateSubscriptionInput): Promise<RazorpaySubscription> {
    const body: Record<string, unknown> = {
      plan_id: input.planId,
      total_count: input.totalCount,
      quantity: 1,
      customer_notify: 1,
      notes: input.notes,
    };
    if (input.startAt !== null) body.start_at = input.startAt;
    if (input.notifyEmail) body.notify_info = { notify_email: input.notifyEmail };
    return this.post("/subscriptions", body);
  }

  cancel(subscriptionId: string, atCycleEnd: boolean): Promise<RazorpaySubscription> {
    return this.post(`/subscriptions/${encodeURIComponent(subscriptionId)}/cancel`, {
      cancel_at_cycle_end: atCycleEnd ? 1 : 0,
    });
  }

  private async post(path: string, body: unknown): Promise<RazorpaySubscription> {
    let res: Response;
    try {
      res = await this.fetchFn(`${RAZORPAY_API}${path}`, {
        method: "POST",
        headers: {
          Authorization: `Basic ${btoa(`${this.keys.keyId}:${this.keys.keySecret}`)}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify(body),
      });
    } catch (e) {
      throw new RazorpayError(0, e instanceof Error ? e.message : String(e));
    }
    const text = await res.text();
    let parsed: unknown = null;
    try {
      parsed = JSON.parse(text);
    } catch {
      // Not JSON: the description falls back to the raw text below.
    }
    if (!res.ok) {
      const description = (parsed as { error?: { description?: string } } | null)?.error
        ?.description ?? text.slice(0, 200);
      throw new RazorpayError(res.status, description);
    }
    return parsed as RazorpaySubscription;
  }
}
