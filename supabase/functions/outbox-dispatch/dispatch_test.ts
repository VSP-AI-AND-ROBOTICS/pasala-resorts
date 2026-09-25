import { assertEquals } from "jsr:@std/assert@^1.0.13";
import { channelModes, deliver, type DispatchDeps, dispatchOnce } from "./dispatch.ts";
import { dryConfig, emailRow, FakeEmailSender, FakeSmsSender, FakeStore, liveConfig, smsRow } from "./fakes.ts";
import type { DispatchConfig } from "./types.ts";

function depsFor(
  config: DispatchConfig,
  store: FakeStore = new FakeStore(),
  email: FakeEmailSender | null = null,
  sms: FakeSmsSender | null = null,
) {
  const logs: Record<string, unknown>[] = [];
  const deps: DispatchDeps = { config, store, email, sms, log: (entry) => logs.push(entry) };
  return { deps, store, logs };
}

Deno.test("without keys every row is a dry run with its reason, and nothing is sent", async () => {
  const store = new FakeStore();
  store.rows = [emailRow(), smsRow()];
  const { deps } = depsFor(dryConfig, store);

  const summary = await dispatchOnce(deps);

  assertEquals(store.completed, [
    { id: emailRow().id, outcome: { kind: "dry_run", reason: "Dry run: RESEND_API_KEY is not set" } },
    { id: smsRow().id, outcome: { kind: "dry_run", reason: "Dry run: MSG91_AUTH_KEY is not set" } },
  ]);
  assertEquals(summary, {
    claimed: 2, sent: 0, dry_run: 2, retry: 0, failed: 0, errors: 0,
    modes: { email: "dry_run", sms: "dry_run" },
  });
  assertEquals(store.runs, [channelModes(dryConfig)]);
  assertEquals(store.claimLimits, [50]);
});

Deno.test("channelModes reports each channel's mode, provider and reason", () => {
  assertEquals(channelModes(dryConfig), [
    { channel: "email", mode: "dry_run", provider: "resend", detail: "RESEND_API_KEY is not set" },
    { channel: "sms", mode: "dry_run", provider: "msg91", detail: "MSG91_AUTH_KEY is not set" },
  ]);
  assertEquals(channelModes(liveConfig), [
    { channel: "email", mode: "live", provider: "resend", detail: null },
    { channel: "sms", mode: "live", provider: "msg91", detail: null },
  ]);
});

Deno.test("a live email goes out with the resort name and the row id as idempotency key", async () => {
  const email = new FakeEmailSender();
  email.results = [{ ok: true, providerId: "re_123" }];
  const { deps } = depsFor(liveConfig, undefined, email, new FakeSmsSender());

  assertEquals(await deliver(emailRow(), deps), { kind: "sent", providerId: "re_123" });
  assertEquals(email.sent, [{
    to: "asha@example.com",
    fromName: "Pasala Farm House",
    subject: emailRow().subject!,
    text: emailRow().body!,
    idempotencyKey: emailRow().id,
  }]);
});

Deno.test("a listing email (P10) has no reservation and no variables, and still goes out", async () => {
  const email = new FakeEmailSender();
  email.results = [{ ok: true, providerId: "re_456" }];
  const { deps } = depsFor(liveConfig, undefined, email, new FakeSmsSender());
  const row = emailRow({
    reservation_id: null,
    template: "listing_submitted",
    recipient: "lina@example.com",
    subject: "We have your listing for Lina's Lakeside",
    body: "Thanks, Lina. We will review it soon.",
    vars: {},
  });

  assertEquals(await deliver(row, deps), { kind: "sent", providerId: "re_456" });
  assertEquals(email.sent[0].fromName, "");
  assertEquals(email.sent[0].to, "lina@example.com");
});

Deno.test("provider failures become retry or failed", async () => {
  const email = new FakeEmailSender();
  email.results = [
    { ok: false, retryable: true, error: "resend 503: busy" },
    { ok: false, retryable: false, error: "resend 422: bad to" },
  ];
  const { deps } = depsFor(liveConfig, undefined, email, new FakeSmsSender());

  assertEquals(await deliver(emailRow(), deps), { kind: "retry", error: "resend 503: busy" });
  assertEquals(await deliver(emailRow(), deps), { kind: "failed", error: "resend 422: bad to" });
});

Deno.test("an email row with no body fails without calling Resend", async () => {
  const email = new FakeEmailSender();
  const { deps } = depsFor(liveConfig, undefined, email, new FakeSmsSender());

  assertEquals(await deliver(emailRow({ body: null }), deps), {
    kind: "failed",
    error: "nothing to send: the message has no subject or body",
  });
  assertEquals(email.sent.length, 0);
});

Deno.test("SMS: normalised mobile, template id from the map, variables passed through", async () => {
  const sms = new FakeSmsSender();
  sms.results = [{ ok: true, providerId: "msg91-req-1" }];
  const { deps } = depsFor(liveConfig, undefined, new FakeEmailSender(), sms);

  assertEquals(await deliver(smsRow(), deps), { kind: "sent", providerId: "msg91-req-1" });
  assertEquals(sms.sent, [{ mobile: "919876543210", templateId: "tmpl-confirm", vars: smsRow().vars }]);
});

Deno.test("SMS with no template id, or to a non-Indian number, fails at once", async () => {
  const sms = new FakeSmsSender();
  const { deps } = depsFor(liveConfig, undefined, new FakeEmailSender(), sms);

  assertEquals(await deliver(smsRow({ template: "cancellation_sms" }), deps), {
    kind: "failed",
    error: "no MSG91 template id for cancellation_sms in MSG91_TEMPLATES",
  });
  assertEquals(await deliver(smsRow({ recipient: "+44 7700 900123" }), deps), {
    kind: "failed",
    error: "the phone number on file is not a valid Indian mobile number",
  });
  assertEquals(sms.sent.length, 0);
});

Deno.test("email can be live while SMS is a dry run", async () => {
  const config: DispatchConfig = { ...liveConfig, sms: dryConfig.sms };
  const store = new FakeStore();
  store.rows = [emailRow(), smsRow()];
  const { deps } = depsFor(config, store, new FakeEmailSender(), null);

  const summary = await dispatchOnce(deps);

  assertEquals(summary.sent, 1);
  assertEquals(summary.dry_run, 1);
  assertEquals(summary.modes, { email: "live", sms: "dry_run" });
});

Deno.test("a sender that throws is retried later", async () => {
  const email = new FakeEmailSender();
  email.results = [new Error("boom")];
  const store = new FakeStore();
  store.rows = [emailRow()];
  const { deps } = depsFor(liveConfig, store, email, new FakeSmsSender());

  const summary = await dispatchOnce(deps);

  assertEquals(store.completed, [{ id: emailRow().id, outcome: { kind: "retry", error: "unexpected error: boom" } }]);
  assertEquals(summary.retry, 1);
});

Deno.test("if recording one row fails the run carries on with the next", async () => {
  const store = new FakeStore();
  store.rows = [emailRow({ id: "m1" }), emailRow({ id: "m2" })];
  store.failCompleteFor.add("m1");
  const { deps, logs } = depsFor(liveConfig, store, new FakeEmailSender(), new FakeSmsSender());

  const summary = await dispatchOnce(deps);

  assertEquals(store.completed.map((c) => c.id), ["m2"]);
  assertEquals(summary.errors, 1);
  assertEquals(summary.sent, 1);
  assertEquals(logs.some((l) => l.event === "outbox_complete_failed" && l.id === "m1"), true);
});

Deno.test("a failed run record is counted, not fatal", async () => {
  const store = new FakeStore();
  store.rows = [emailRow()];
  store.recordError = new Error("db down");
  const { deps } = depsFor(dryConfig, store);

  const summary = await dispatchOnce(deps);

  assertEquals(summary.dry_run, 1);
  assertEquals(summary.errors, 1);
});

Deno.test("logs never carry a recipient, subject or body", async () => {
  const store = new FakeStore();
  store.rows = [emailRow(), smsRow()];
  const email = new FakeEmailSender();
  email.results = [{ ok: false, retryable: false, error: "resend 422: asha@example.com is invalid" }];
  const { deps, logs } = depsFor(liveConfig, store, email, new FakeSmsSender());

  await dispatchOnce(deps);

  const text = JSON.stringify(logs);
  for (const personal of ["asha@example.com", "98765", emailRow().subject!, emailRow().body!, smsRow().body!]) {
    assertEquals(text.includes(personal), false, personal);
  }
});
