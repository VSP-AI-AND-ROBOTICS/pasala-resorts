// payments-create-order. Logic and tests: handler.ts / handler_test.ts.
import { createOrderHandler } from "./handler.ts";
import { RazorpayClient, readConfig } from "../_shared/razorpay.ts";
import { serviceDb, userDb } from "../_shared/payments_db_supabase.ts";

Deno.serve(createOrderHandler({
  config: () => readConfig((name) => Deno.env.get(name)),
  service: serviceDb(),
  userDb,
  razorpay: (config) => new RazorpayClient(config),
}));
