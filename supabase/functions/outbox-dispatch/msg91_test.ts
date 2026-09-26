import { assertEquals } from "jsr:@std/assert@^1.0.13";
import { DLT_VAR_MAX, MSG91_FLOW_URL, Msg91SmsSender, normalizeIndianMobile, smsVars } from "./msg91.ts";
import { jsonResponse, stubFetch } from "./testing.ts";

const vars = {
  guest_name: "Asha Rao",
  unit_name: "Mango Cottage",
  property_name: "Pasala Farm House",
  check_in: "01 Mar 2027",
  check_out: "02 Mar 2027",
  total: "11500",
  currency: "INR",
  cancel_reason: "no reason given",
};

Deno.test("normalizeIndianMobile accepts the usual ways of writing an Indian mobile", () => {
  const cases: Array<[string, string | null]> = [
    ["9876543210", "919876543210"],
    ["+91 98765 43210", "919876543210"],
    ["+91-98765-43210", "919876543210"],
    ["098765 43210", "919876543210"],
    ["0091 98765 43210", "919876543210"],
    ["919876543210", "919876543210"],
    ["6000000000", "916000000000"],
    ["5876543210", null], // Indian mobiles start with 6-9
    ["98765 4321", null], // nine digits
    ["+44 7700 900123", null], // not Indian
    ["", null],
    ["no phone on file", null],
  ];
  for (const [raw, expected] of cases) {
    assertEquals(normalizeIndianMobile(raw), expected, raw);
  }
});

Deno.test("smsVars stringifies every variable and cuts it to the DLT limit", () => {
  assertEquals(DLT_VAR_MAX, 30);
  assertEquals(
    smsVars({ guest_name: "A".repeat(40), total: 11500, cancel_reason: null }),
    { guest_name: "A".repeat(30), total: "11500", cancel_reason: "" },
  );
});

Deno.test("sends the flow request with template id, sender, mobile and variables", async () => {
  const { fetch, calls } = stubFetch([
    jsonResponse(200, { type: "success", message: "3567686b6f78313233343536" }),
  ]);
  const result = await new Msg91SmsSender("auth-key", "RSTHUB", fetch).send({
    mobile: "919876543210",
    templateId: "tmpl-confirm",
    vars,
  });

  assertEquals(result, { ok: true, providerId: "3567686b6f78313233343536" });
  assertEquals(calls[0].url, MSG91_FLOW_URL);
  assertEquals(calls[0].method, "POST");
  assertEquals(calls[0].headers["authkey"], "auth-key");
  assertEquals(calls[0].body, {
    template_id: "tmpl-confirm",
    short_url: "0",
    sender: "RSTHUB",
    recipients: [{ ...vars, mobiles: "919876543210" }],
  });
});

Deno.test("no sender field when MSG91_SENDER_ID is not set", async () => {
  const { fetch, calls } = stubFetch([jsonResponse(200, { type: "success", message: "r1" })]);
  await new Msg91SmsSender("auth-key", null, fetch).send({ mobile: "919876543210", templateId: "t", vars });
  assertEquals("sender" in (calls[0].body as Record<string, unknown>), false);
});

Deno.test("a variable named mobiles cannot replace the recipient", async () => {
  const { fetch, calls } = stubFetch([jsonResponse(200, { type: "success", message: "r1" })]);
  await new Msg91SmsSender("k", null, fetch).send({
    mobile: "919876543210",
    templateId: "t",
    vars: { mobiles: "910000000000" },
  });
  const body = calls[0].body as { recipients: Array<Record<string, string>> };
  assertEquals(body.recipients[0].mobiles, "919876543210");
});

Deno.test("HTTP 200 with type error is a permanent failure, never sent", async () => {
  const { fetch } = stubFetch([jsonResponse(200, { type: "error", message: "Template ID is not valid" })]);
  const result = await new Msg91SmsSender("k", null, fetch).send({ mobile: "919876543210", templateId: "t", vars });
  assertEquals(result, { ok: false, retryable: false, error: "msg91: Template ID is not valid" });
});

Deno.test("401 is permanent; 5xx is retryable", async () => {
  const unauthorized = stubFetch([jsonResponse(401, { type: "error", message: "Authentication failure" })]);
  assertEquals(
    await new Msg91SmsSender("k", null, unauthorized.fetch).send({ mobile: "919876543210", templateId: "t", vars }),
    { ok: false, retryable: false, error: "msg91 401: Authentication failure" },
  );
  const down = stubFetch([new Response("Service Unavailable", { status: 503 })]);
  assertEquals(
    await new Msg91SmsSender("k", null, down.fetch).send({ mobile: "919876543210", templateId: "t", vars }),
    { ok: false, retryable: true, error: "msg91 503: Service Unavailable" },
  );
});

Deno.test("a network error is retryable", async () => {
  const { fetch } = stubFetch([new TypeError("dns failure")]);
  const result = await new Msg91SmsSender("k", null, fetch).send({ mobile: "919876543210", templateId: "t", vars });
  assertEquals(result, { ok: false, retryable: true, error: "msg91: network error: dns failure" });
});
