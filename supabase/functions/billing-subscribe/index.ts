// Deployed entry point. Secrets come from `supabase secrets set`; without
// the Razorpay keys every action answers {configured:false}.
import { makeBillingDb } from "../_shared/billing/db.ts";
import { RazorpaySubscriptionsClient } from "../_shared/billing/razorpay_subscriptions.ts";
import { makeSubscribeHandler } from "./handler.ts";

const keyId = Deno.env.get("RAZORPAY_KEY_ID") ?? "";
const keySecret = Deno.env.get("RAZORPAY_KEY_SECRET") ?? "";
const config = {
  url: Deno.env.get("SUPABASE_URL") ?? "",
  anonKey: Deno.env.get("SUPABASE_ANON_KEY") ?? "",
  serviceRoleKey: Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
};

Deno.serve(makeSubscribeHandler({
  keys: keyId && keySecret ? { keyId, keySecret } : null,
  razorpay: (keys) => new RazorpaySubscriptionsClient(keys),
  db: (jwt) => makeBillingDb(config, jwt),
}));
