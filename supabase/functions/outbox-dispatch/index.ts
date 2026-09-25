// outbox-dispatch: sends due outbox email/SMS rows. pg_cron calls it every
// minute (0056's outbox_dispatch_tick), and it can be run by hand; see
// docs/email-and-sms-delivery.md. The configuration is read on every
// request, so new secrets take effect without a redeploy.
import { buildDeps } from "./deps.ts";
import { handleRequest } from "./handler.ts";

Deno.serve((req) => handleRequest(req, () => buildDeps((name) => Deno.env.get(name))));
