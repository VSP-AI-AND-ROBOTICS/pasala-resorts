// Reads the function's configuration from its environment (Supabase Edge
// Function secrets). Each channel is live only when its provider's keys
// are set; otherwise it is a dry run with the reason, and nothing is sent.
import type { DispatchConfig, EmailConfig, Setup, SmsConfig } from "./types.ts";

export class ConfigError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "ConfigError";
  }
}

type Get = (name: string) => string | undefined;

// A bare address only: the display name is the resort's name.
const EMAIL_RE = /^[^\s@<>"]+@[^\s@<>"]+\.[^\s@<>"]+$/;

export function parseBatchSize(raw?: string): number {
  const n = raw === undefined ? NaN : Number(raw);
  if (!Number.isInteger(n)) return 50;
  return Math.min(Math.max(n, 1), 200);
}

function emailSetup(get: Get): Setup<EmailConfig> {
  const dry = (detail: string): Setup<EmailConfig> => ({ mode: "dry_run", provider: "resend", detail });
  const apiKey = get("RESEND_API_KEY");
  if (!apiKey) return dry("RESEND_API_KEY is not set");
  const from = get("RESEND_FROM");
  if (!from) return dry("RESEND_FROM is not set");
  if (!EMAIL_RE.test(from)) return dry("RESEND_FROM is not an email address");
  return { mode: "live", provider: "resend", config: { apiKey, from } };
}

function smsSetup(get: Get): Setup<SmsConfig> {
  const dry = (detail: string): Setup<SmsConfig> => ({ mode: "dry_run", provider: "msg91", detail });
  const authKey = get("MSG91_AUTH_KEY");
  if (!authKey) return dry("MSG91_AUTH_KEY is not set");
  const raw = get("MSG91_TEMPLATES");
  if (!raw) return dry("MSG91_TEMPLATES is not set");
  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch {
    return dry("MSG91_TEMPLATES is not valid JSON");
  }
  if (parsed === null || typeof parsed !== "object" || Array.isArray(parsed)) {
    return dry("MSG91_TEMPLATES must be a JSON object");
  }
  const templates: Record<string, string> = {};
  for (const [name, id] of Object.entries(parsed as Record<string, unknown>)) {
    if (typeof id === "string" && id.trim() !== "") templates[name] = id.trim();
  }
  return {
    mode: "live",
    provider: "msg91",
    config: { authKey, senderId: get("MSG91_SENDER_ID") ?? null, templates },
  };
}

export function loadConfig(env: (name: string) => string | undefined): DispatchConfig {
  const get: Get = (name) => {
    const value = env(name)?.trim();
    return value ? value : undefined;
  };
  const supabaseUrl = get("SUPABASE_URL");
  if (!supabaseUrl) throw new ConfigError("SUPABASE_URL is not set");
  const serviceKey = get("SUPABASE_SERVICE_ROLE_KEY");
  if (!serviceKey) throw new ConfigError("SUPABASE_SERVICE_ROLE_KEY is not set");
  return {
    supabaseUrl: supabaseUrl.replace(/\/+$/, ""),
    serviceKey,
    batchSize: parseBatchSize(get("OUTBOX_BATCH_SIZE")),
    email: emailSetup(get),
    sms: smsSetup(get),
  };
}
