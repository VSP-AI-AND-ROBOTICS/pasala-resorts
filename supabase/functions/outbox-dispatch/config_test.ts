import { assertEquals, assertThrows } from "jsr:@std/assert@^1.0.13";
import { ConfigError, loadConfig, parseBatchSize } from "./config.ts";

function envOf(values: Record<string, string>): (name: string) => string | undefined {
  return (name) => values[name];
}

const base = {
  SUPABASE_URL: "http://127.0.0.1:54321/",
  SUPABASE_SERVICE_ROLE_KEY: "service-key",
};

Deno.test("with no provider keys both channels are a dry run with a reason", () => {
  const config = loadConfig(envOf(base));
  assertEquals(config.supabaseUrl, "http://127.0.0.1:54321");
  assertEquals(config.serviceKey, "service-key");
  assertEquals(config.batchSize, 50);
  assertEquals(config.email, { mode: "dry_run", provider: "resend", detail: "RESEND_API_KEY is not set" });
  assertEquals(config.sms, { mode: "dry_run", provider: "msg91", detail: "MSG91_AUTH_KEY is not set" });
});

Deno.test("email needs a key and a bare sender address", () => {
  assertEquals(
    loadConfig(envOf({ ...base, RESEND_API_KEY: "re_k" })).email,
    { mode: "dry_run", provider: "resend", detail: "RESEND_FROM is not set" },
  );
  assertEquals(
    loadConfig(envOf({ ...base, RESEND_API_KEY: "re_k", RESEND_FROM: "Bookings <b@x.com>" })).email,
    { mode: "dry_run", provider: "resend", detail: "RESEND_FROM is not an email address" },
  );
  assertEquals(
    loadConfig(envOf({ ...base, RESEND_API_KEY: " re_k ", RESEND_FROM: "bookings@mail.example.com" })).email,
    { mode: "live", provider: "resend", config: { apiKey: "re_k", from: "bookings@mail.example.com" } },
  );
});

Deno.test("a blank key counts as unset", () => {
  assertEquals(
    loadConfig(envOf({ ...base, RESEND_API_KEY: "   ", MSG91_AUTH_KEY: "" })).email.mode,
    "dry_run",
  );
});

Deno.test("SMS needs a key and a JSON object of template ids", () => {
  const withKey = { ...base, MSG91_AUTH_KEY: "auth" };
  assertEquals(
    loadConfig(envOf(withKey)).sms,
    { mode: "dry_run", provider: "msg91", detail: "MSG91_TEMPLATES is not set" },
  );
  assertEquals(
    loadConfig(envOf({ ...withKey, MSG91_TEMPLATES: "{oops" })).sms,
    { mode: "dry_run", provider: "msg91", detail: "MSG91_TEMPLATES is not valid JSON" },
  );
  assertEquals(
    loadConfig(envOf({ ...withKey, MSG91_TEMPLATES: '["a"]' })).sms,
    { mode: "dry_run", provider: "msg91", detail: "MSG91_TEMPLATES must be a JSON object" },
  );
  assertEquals(
    loadConfig(envOf({
      ...withKey,
      MSG91_SENDER_ID: "RSTHUB",
      MSG91_TEMPLATES: '{"booking_confirmation_sms":" t1 ","cancellation_sms":"","x":5}',
    })).sms,
    {
      mode: "live",
      provider: "msg91",
      config: { authKey: "auth", senderId: "RSTHUB", templates: { booking_confirmation_sms: "t1" } },
    },
  );
  assertEquals(
    loadConfig(envOf({ ...withKey, MSG91_TEMPLATES: "{}" })).sms,
    { mode: "live", provider: "msg91", config: { authKey: "auth", senderId: null, templates: {} } },
  );
});

Deno.test("OUTBOX_BATCH_SIZE is clamped to 1..200 and defaults to 50", () => {
  assertEquals(parseBatchSize(undefined), 50);
  assertEquals(parseBatchSize("abc"), 50);
  assertEquals(parseBatchSize("2.5"), 50);
  assertEquals(parseBatchSize("0"), 1);
  assertEquals(parseBatchSize("500"), 200);
  assertEquals(parseBatchSize("25"), 25);
  assertEquals(loadConfig(envOf({ ...base, OUTBOX_BATCH_SIZE: "10" })).batchSize, 10);
});

Deno.test("the Supabase URL and service key are required", () => {
  assertThrows(() => loadConfig(envOf({ SUPABASE_SERVICE_ROLE_KEY: "k" })), ConfigError, "SUPABASE_URL is not set");
  assertThrows(() => loadConfig(envOf({ SUPABASE_URL: "http://x" })), ConfigError, "SUPABASE_SERVICE_ROLE_KEY is not set");
});
