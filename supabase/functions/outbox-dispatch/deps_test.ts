import { assertEquals, assertInstanceOf } from "jsr:@std/assert@^1.0.13";
import { buildDeps } from "./deps.ts";
import { handleRequest } from "./handler.ts";
import { Msg91SmsSender } from "./msg91.ts";
import { RESEND_URL, ResendEmailSender } from "./resend.ts";
import { RestOutboxStore } from "./store.ts";
import { jsonResponse, stubFetch } from "./testing.ts";

function envOf(values: Record<string, string>): (name: string) => string | undefined {
  return (name) => values[name];
}

const base = { SUPABASE_URL: "http://127.0.0.1:54321", SUPABASE_SERVICE_ROLE_KEY: "service-key" };

Deno.test("without provider keys there are no senders", () => {
  const deps = buildDeps(envOf(base), stubFetch([]).fetch, () => {});
  assertEquals(deps.email, null);
  assertEquals(deps.sms, null);
  assertInstanceOf(deps.store, RestOutboxStore);
});

Deno.test("with keys both senders are wired to the given fetch", async () => {
  const { fetch, calls } = stubFetch([jsonResponse(200, { id: "re_1" })]);
  const deps = buildDeps(envOf({
    ...base,
    RESEND_API_KEY: "re_k",
    RESEND_FROM: "bookings@mail.example.com",
    MSG91_AUTH_KEY: "auth",
    MSG91_TEMPLATES: "{}",
  }), fetch, () => {});

  assertInstanceOf(deps.email, ResendEmailSender);
  assertInstanceOf(deps.sms, Msg91SmsSender);
  await deps.email!.send({ to: "a@example.com", fromName: "R", subject: "s", text: "t", idempotencyKey: "k" });
  assertEquals(calls[0].url, RESEND_URL);
});

Deno.test("a dry run end to end through the real store: claim, complete, record", async () => {
  const row = {
    id: "m1", property_id: "p1", reservation_id: "r1", channel: "email",
    recipient: "asha@example.com", template: "booking_confirmation",
    subject: "s", body: "b", attempts: 1, vars: { property_name: "P" },
  };
  const { fetch, calls } = stubFetch([
    jsonResponse(200, [row]),
    jsonResponse(200, "dry_run"),
    new Response(null, { status: 204 }),
  ]);
  const deps = buildDeps(envOf(base), fetch, () => {});

  const res = await handleRequest(
    new Request("http://localhost/functions/v1/outbox-dispatch", {
      method: "POST",
      headers: { Authorization: "Bearer service-key" },
    }),
    () => deps,
  );

  assertEquals(res.status, 200);
  assertEquals(calls.map((c) => c.url.split("/rpc/")[1]), [
    "claim_outbox_batch",
    "complete_outbox_message",
    "record_outbox_dispatch_run",
  ]);
  assertEquals(calls[1].body, {
    p_id: "m1", p_outcome: "dry_run", p_error: "Dry run: RESEND_API_KEY is not set", p_provider_id: null,
  });
});
