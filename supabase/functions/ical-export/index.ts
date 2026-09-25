// Wiring only: the logic, and everything the tests cover, is in handler.ts.
// SUPABASE_URL and SUPABASE_ANON_KEY are provided by the edge runtime.
import { handle, restStore } from "./handler.ts";

const store = restStore(
  Deno.env.get("SUPABASE_URL") ?? "",
  Deno.env.get("SUPABASE_ANON_KEY") ?? "",
);

Deno.serve((req) => handle(req, store));
