// Wires the real store and senders from the environment. A channel whose
// keys are missing gets no sender and is a dry run.
import { loadConfig } from "./config.ts";
import type { DispatchDeps } from "./dispatch.ts";
import { Msg91SmsSender } from "./msg91.ts";
import { ResendEmailSender } from "./resend.ts";
import { RestOutboxStore } from "./store.ts";
import type { FetchFn } from "./types.ts";

export function buildDeps(
  env: (name: string) => string | undefined,
  fetchFn: FetchFn = fetch,
  log: (entry: Record<string, unknown>) => void = (entry) => console.log(JSON.stringify(entry)),
): DispatchDeps {
  const config = loadConfig(env);
  return {
    config,
    store: new RestOutboxStore(config.supabaseUrl, config.serviceKey, fetchFn),
    email: config.email.mode === "live"
      ? new ResendEmailSender(config.email.config.apiKey, config.email.config.from, fetchFn)
      : null,
    sms: config.sms.mode === "live"
      ? new Msg91SmsSender(config.sms.config.authKey, config.sms.config.senderId, fetchFn)
      : null,
    log,
  };
}
