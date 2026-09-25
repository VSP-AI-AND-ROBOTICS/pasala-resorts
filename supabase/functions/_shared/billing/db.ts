// The real BillingDb: supabase-js as the signed-in caller (the owner's
// reads, so assert_resort_role sees them) and as the service role (the
// billing writes, which no client role may execute). Not imported by any
// test; exercised by the plan's integration task.
import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";
import {
  type ApplyResult,
  type BillablePlan,
  type BillingDb,
  DbError,
  type OpenedResult,
  type SubscribeState,
} from "./types.ts";

export interface DbConfig {
  url: string;
  anonKey: string;
  serviceRoleKey: string;
}

export function makeBillingDb(config: DbConfig, callerJwt: string | null): BillingDb {
  const options = { auth: { persistSession: false, autoRefreshToken: false } };
  const service = createClient(config.url, config.serviceRoleKey, options);
  const caller = callerJwt === null ? null : createClient(config.url, config.anonKey, {
    ...options,
    global: { headers: { Authorization: `Bearer ${callerJwt}` } },
  });

  const asCaller = (): SupabaseClient => {
    if (caller === null) throw new DbError("P0008", "no signed-in caller");
    return caller;
  };

  async function rpc<T>(client: SupabaseClient, fn: string, args: Record<string, unknown>): Promise<T> {
    const { data, error } = await client.rpc(fn, args);
    if (error) throw new DbError(error.code ?? "", error.message);
    return data as T;
  }

  return {
    async billablePlans(): Promise<BillablePlan[]> {
      const { data, error } = await asCaller()
        .from("subscription_plans")
        .select("tier, name, monthly_price_inr")
        .not("razorpay_plan_id", "is", null)
        .order("sort_order");
      if (error) throw new DbError(error.code ?? "", error.message);
      return (data ?? []).map((r) => ({
        tier: r.tier,
        name: r.name,
        monthly_price_inr: Number(r.monthly_price_inr),
      }));
    },
    subscribeState: (propertyId, tier) =>
      rpc<SubscribeState>(asCaller(), "billing_subscribe_state", { p_property: propertyId, p_tier: tier }),
    opened: (a) =>
      rpc<OpenedResult>(service, "billing_subscription_opened", {
        p_property: a.property_id,
        p_tier: a.tier,
        p_razorpay_plan_id: a.razorpay_plan_id,
        p_razorpay_subscription_id: a.razorpay_subscription_id,
        p_status: a.status,
        p_short_url: a.short_url,
        p_start_at: a.start_at === null ? null : new Date(a.start_at * 1000).toISOString(),
        p_created_by: a.created_by,
      }),
    async cancelRequested(subscriptionId, atCycleEnd, status, actor) {
      await rpc<null>(service, "billing_subscription_cancel_requested", {
        p_razorpay_subscription_id: subscriptionId,
        p_at_cycle_end: atCycleEnd,
        p_status: status,
        p_actor: actor,
      });
    },
    applyWebhook: (event, eventAt, subscription, payment) =>
      rpc<ApplyResult>(service, "billing_webhook_apply", {
        p_event: event,
        p_event_at: eventAt,
        p_subscription: subscription,
        p_payment: payment,
      }),
  };
}
