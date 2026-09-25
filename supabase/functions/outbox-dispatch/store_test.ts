import { assertEquals, assertRejects } from "@std/assert";
import { outcomeArgs, RestOutboxStore, StoreError } from "./store.ts";
import { jsonResponse, stubFetch } from "./testing.ts";
import type { ChannelMode, ClaimedMessage } from "./types.ts";

const url = "http://127.0.0.1:54321";

const row: ClaimedMessage = {
  id: "m1",
  property_id: "p1",
  reservation_id: "r1",
  channel: "email",
  recipient: "asha@example.com",
  template: "booking_confirmation",
  subject: "s",
  body: "b",
  attempts: 1,
  vars: { property_name: "Pasala Farm House" },
};

Deno.test("claim posts p_limit to claim_outbox_batch with the service key", async () => {
  const { fetch, calls } = stubFetch([jsonResponse(200, [row])]);
  const rows = await new RestOutboxStore(url, "service-key", fetch).claim(50);

  assertEquals(rows, [row]);
  assertEquals(calls[0].url, `${url}/rest/v1/rpc/claim_outbox_batch`);
  assertEquals(calls[0].method, "POST");
  assertEquals(calls[0].headers["apikey"], "service-key");
  assertEquals(calls[0].headers["authorization"], "Bearer service-key");
  assertEquals(calls[0].headers["content-type"], "application/json");
  assertEquals(calls[0].body, { p_limit: 50 });
});

Deno.test("an empty or odd claim reply is no rows", async () => {
  const { fetch } = stubFetch([jsonResponse(200, []), jsonResponse(200, null)]);
  const store = new RestOutboxStore(url, "k", fetch);
  assertEquals(await store.claim(10), []);
  assertEquals(await store.claim(10), []);
});

Deno.test("complete sends each outcome's arguments and returns the new status", async () => {
  const { fetch, calls } = stubFetch([jsonResponse(200, "sent"), jsonResponse(200, "pending")]);
  const store = new RestOutboxStore(url, "k", fetch);

  assertEquals(await store.complete("m1", { kind: "sent", providerId: "re_1" }), "sent");
  assertEquals(await store.complete("m2", { kind: "retry", error: "resend 503: busy" }), "pending");
  assertEquals(calls[0].url, `${url}/rest/v1/rpc/complete_outbox_message`);
  assertEquals(calls[0].body, { p_id: "m1", p_outcome: "sent", p_error: null, p_provider_id: "re_1" });
  assertEquals(calls[1].body, { p_id: "m2", p_outcome: "retry", p_error: "resend 503: busy", p_provider_id: null });
});

Deno.test("outcomeArgs maps dry_run and failed", () => {
  assertEquals(
    outcomeArgs("m3", { kind: "dry_run", reason: "Dry run: RESEND_API_KEY is not set" }),
    { p_id: "m3", p_outcome: "dry_run", p_error: "Dry run: RESEND_API_KEY is not set", p_provider_id: null },
  );
  assertEquals(
    outcomeArgs("m4", { kind: "failed", error: "resend 422: bad to" }),
    { p_id: "m4", p_outcome: "failed", p_error: "resend 422: bad to", p_provider_id: null },
  );
});

Deno.test("recordRun sends p_channels and accepts an empty reply", async () => {
  const { fetch, calls } = stubFetch([new Response(null, { status: 204 })]);
  const modes: ChannelMode[] = [
    { channel: "email", mode: "dry_run", provider: "resend", detail: "RESEND_API_KEY is not set" },
    { channel: "sms", mode: "live", provider: "msg91", detail: null },
  ];
  await new RestOutboxStore(url, "k", fetch).recordRun(modes);
  assertEquals(calls[0].url, `${url}/rest/v1/rpc/record_outbox_dispatch_run`);
  assertEquals(calls[0].body, { p_channels: modes });
});

Deno.test("a PostgREST error becomes a StoreError with the status", async () => {
  const { fetch } = stubFetch([
    jsonResponse(403, { code: "42501", message: "permission denied for function claim_outbox_batch" }),
  ]);
  const error = await assertRejects(() => new RestOutboxStore(url, "k", fetch).claim(10), StoreError);
  assertEquals(error.status, 403);
  assertEquals(error.message.startsWith("claim_outbox_batch 403: "), true);
});
