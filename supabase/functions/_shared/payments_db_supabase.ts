// The real database adapters, over supabase-js. Imported only by the
// functions' index.ts, never by a test, so `deno test` needs neither
// supabase-js nor a database. Verified end to end in the integration task.
import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import {
  DbError,
  type OrderQuote,
  type ServicePaymentsDb,
  type SettleResult,
  type UserPaymentsDb,
} from "./payments_types.ts";

function env(name: string): string {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`${name} is not set`);
  return value;
}

async function rpc<T>(client: SupabaseClient, fn: string, args: Record<string, unknown>): Promise<T> {
  const { data, error } = await client.rpc(fn, args);
  if (error) throw new DbError(error.code ?? "unknown", error.message);
  return data as T;
}

/** Runs as the caller: their Authorization header is forwarded. */
export function userDb(authorization: string): UserPaymentsDb {
  const client = createClient(env("SUPABASE_URL"), env("SUPABASE_ANON_KEY"), {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  return {
    quoteOrder: ({ reservationId, kind, amount }) =>
      rpc<OrderQuote>(client, "payment_order_quote", {
        p_reservation: reservationId,
        p_kind: kind,
        p_amount: amount,
      }),
  };
}

/** Runs with the service role; created on first use. */
export function serviceDb(): ServicePaymentsDb {
  let client: SupabaseClient | null = null;
  const db = () =>
    client ??= createClient(env("SUPABASE_URL"), env("SUPABASE_SERVICE_ROLE_KEY"), {
      auth: { persistSession: false, autoRefreshToken: false },
    });
  return {
    async setLive(live, keyId) {
      await rpc(db(), "payments_set_live", { p_live: live, p_key_id: keyId });
    },
    async openOrder({ reservationId, customerId, kind, amount, razorpayOrderId }) {
      await rpc(db(), "payment_order_open", {
        p_reservation: reservationId,
        p_customer: customerId,
        p_kind: kind,
        p_amount: amount,
        p_razorpay_order_id: razorpayOrderId,
      });
    },
    async settleOrder(razorpayOrderId, razorpayPaymentId) {
      try {
        return await rpc<SettleResult>(db(), "payment_order_settle", {
          p_razorpay_order_id: razorpayOrderId,
          p_razorpay_payment_id: razorpayPaymentId,
        });
      } catch (e) {
        if (e instanceof DbError && e.code === "P0002") return null;
        throw e;
      }
    },
    async failOrder(razorpayOrderId, reason) {
      await rpc(db(), "payment_order_failed", { p_razorpay_order_id: razorpayOrderId, p_reason: reason });
    },
    async recordRefund(razorpayPaymentId, refundId, amount) {
      await rpc(db(), "payment_order_refunded", {
        p_razorpay_payment_id: razorpayPaymentId,
        p_refund_id: refundId,
        p_amount: amount,
      });
    },
    async releaseRefund(razorpayPaymentId) {
      await rpc(db(), "payment_order_refund_release", { p_razorpay_payment_id: razorpayPaymentId });
    },
    beginWebhook: (eventId, event, payload) =>
      rpc<boolean>(db(), "payment_webhook_begin", { p_event_id: eventId, p_event: event, p_payload: payload }),
    async finishWebhook(eventId, outcome) {
      await rpc(db(), "payment_webhook_done", { p_event_id: eventId, p_outcome: outcome });
    },
  };
}
