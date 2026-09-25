// Deployed entry point (verify_jwt = false in supabase/config.toml).
import { makeBillingDb } from "../_shared/billing/db.ts";
import { RazorpaySubscriptionsClient } from "../_shared/billing/razorpay_subscriptions.ts";
import { makeWebhookHandler } from "./handler.ts";

const keyId = Deno.env.get("RAZORPAY_KEY_ID") ?? "";
const keySecret = Deno.env.get("RAZORPAY_KEY_SECRET") ?? "";
const webhookSecret = Deno.env.get("RAZORPAY_BILLING_WEBHOOK_SECRET") ||
  Deno.env.get("RAZORPAY_WEBHOOK_SECRET") || null;
const config = {
  url: Deno.env.get("SUPABASE_URL") ?? "",
  anonKey: Deno.env.get("SUPABASE_ANON_KEY") ?? "",
  serviceRoleKey: Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
};

Deno.serve(makeWebhookHandler({
  webhookSecret,
  keys: keyId && keySecret ? { keyId, keySecret } : null,
  razorpay: (keys) => new RazorpaySubscriptionsClient(keys),
  db: () => makeBillingDb(config, null),
}));
