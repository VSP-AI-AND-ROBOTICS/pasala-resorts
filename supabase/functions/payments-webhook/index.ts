// payments-webhook (verify_jwt = false: Razorpay signs, it sends no JWT).
// Logic and tests: handler.ts / handler_test.ts.
import { webhookHandler } from "./handler.ts";
import { RazorpayClient, readConfig } from "../_shared/razorpay.ts";
import { serviceDb } from "../_shared/payments_db_supabase.ts";

Deno.serve(webhookHandler({
  config: () => readConfig((name) => Deno.env.get(name)),
  service: serviceDb(),
  razorpay: (config) => new RazorpayClient(config),
}));
