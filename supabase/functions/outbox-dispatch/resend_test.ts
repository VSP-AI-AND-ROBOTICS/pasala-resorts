import { assertEquals } from "jsr:@std/assert@^1.0.13";
import { displayName, RESEND_URL, ResendEmailSender } from "./resend.ts";
import { jsonResponse, stubFetch } from "./testing.ts";
import type { EmailMessage } from "./types.ts";

const message: EmailMessage = {
  to: "asha@example.com",
  fromName: "Pasala Farm House",
  subject: "Your stay at Pasala Farm House is confirmed",
  text: "Hi Asha Rao, your booking is confirmed.",
  idempotencyKey: "0b7f5c1e-0000-4000-8000-000000000001",
};

Deno.test("sends one POST to Resend with the key, the idempotency key and a plain-text body", async () => {
  const { fetch, calls } = stubFetch([jsonResponse(200, { id: "re_123" })]);
  const sender = new ResendEmailSender("re_test_key", "bookings@mail.example.com", fetch);

  assertEquals(await sender.send(message), { ok: true, providerId: "re_123" });
  assertEquals(calls.length, 1);
  assertEquals(calls[0].url, RESEND_URL);
  assertEquals(calls[0].method, "POST");
  assertEquals(calls[0].headers["authorization"], "Bearer re_test_key");
  assertEquals(calls[0].headers["content-type"], "application/json");
  assertEquals(calls[0].headers["idempotency-key"], message.idempotencyKey);
  assertEquals(calls[0].body, {
    from: "Pasala Farm House <bookings@mail.example.com>",
    to: ["asha@example.com"],
    subject: message.subject,
    text: message.text,
  });
});

Deno.test("a 2xx without an id is still sent", async () => {
  const { fetch } = stubFetch([new Response("", { status: 200 })]);
  const result = await new ResendEmailSender("k", "b@example.com", fetch).send(message);
  assertEquals(result, { ok: true, providerId: null });
});

Deno.test("a 422 is a permanent failure carrying Resend's message", async () => {
  const { fetch } = stubFetch([
    jsonResponse(422, { statusCode: 422, name: "validation_error", message: "Invalid `to` field." }),
  ]);
  const result = await new ResendEmailSender("k", "b@example.com", fetch).send(message);
  assertEquals(result, { ok: false, retryable: false, error: "resend 422: Invalid `to` field." });
});

Deno.test("401 and 403 are permanent (a key or domain problem to fix, not to hammer)", async () => {
  for (const status of [401, 403]) {
    const { fetch } = stubFetch([jsonResponse(status, { message: "nope" })]);
    const result = await new ResendEmailSender("k", "b@example.com", fetch).send(message);
    assertEquals(result, { ok: false, retryable: false, error: `resend ${status}: nope` });
  }
});

Deno.test("429 and 5xx are retryable", async () => {
  for (const status of [429, 500, 503]) {
    const { fetch } = stubFetch([jsonResponse(status, { message: "try later" })]);
    const result = await new ResendEmailSender("k", "b@example.com", fetch).send(message);
    assertEquals(result, { ok: false, retryable: true, error: `resend ${status}: try later` });
  }
});

Deno.test("a network error is retryable", async () => {
  const { fetch } = stubFetch([new TypeError("connection reset")]);
  const result = await new ResendEmailSender("k", "b@example.com", fetch).send(message);
  assertEquals(result, { ok: false, retryable: true, error: "resend: network error: connection reset" });
});

Deno.test("a non-JSON error body is reported as text", async () => {
  const { fetch } = stubFetch([new Response("Bad Gateway", { status: 502 })]);
  const result = await new ResendEmailSender("k", "b@example.com", fetch).send(message);
  assertEquals(result, { ok: false, retryable: true, error: "resend 502: Bad Gateway" });
});

Deno.test("displayName strips header-breaking characters and falls back to ResortHub", () => {
  assertEquals(displayName('Sea "View", <Goa>;\r\nResort'), "Sea View Goa Resort");
  assertEquals(displayName("   "), "ResortHub");
  assertEquals(displayName(undefined), "ResortHub");
  assertEquals(displayName(null), "ResortHub");
});
