import { assertEquals } from "jsr:@std/assert@1";
import { decideCancel, decideSubscribe } from "./decide.ts";
import type { CurrentSubscription } from "./types.ts";

function current(overrides: Partial<CurrentSubscription> = {}): CurrentSubscription {
  return {
    razorpay_subscription_id: "sub_Current000001",
    tier: "pro",
    status: "active",
    short_url: "https://rzp.io/i/cur",
    cancel_at_cycle_end: false,
    ...overrides,
  };
}

Deno.test("subscribe: nothing current, or a finished one, creates", () => {
  assertEquals(decideSubscribe(null, "pro"), { kind: "create" });
  for (const status of ["halted", "cancelled", "completed", "expired"] as const) {
    assertEquals(decideSubscribe(current({ status }), "pro"), { kind: "create" }, status);
  }
});

Deno.test("subscribe: another tier creates (the old one is cancelled after)", () => {
  assertEquals(decideSubscribe(current(), "enterprise"), { kind: "create" });
  assertEquals(decideSubscribe(current({ status: "created" }), "starter"), { kind: "create" });
});

Deno.test("subscribe: an unauthorised link for the same tier is reused", () => {
  assertEquals(decideSubscribe(current({ status: "created" }), "pro"), {
    kind: "reuse",
    subscriptionId: "sub_Current000001",
    shortUrl: "https://rzp.io/i/cur",
    status: "created",
  });
  assertEquals(decideSubscribe(current({ status: "created", short_url: null }), "pro"), { kind: "create" });
});

Deno.test("subscribe: live on the same tier is unchanged, unless it is ending", () => {
  for (const status of ["authenticated", "active", "pending", "paused"] as const) {
    assertEquals(decideSubscribe(current({ status }), "pro").kind, "unchanged", status);
  }
  assertEquals(decideSubscribe(current({ cancel_at_cycle_end: true }), "pro"), { kind: "create" });
});

Deno.test("cancel: authorised ends with its cycle, unauthorised ends now", () => {
  assertEquals(decideCancel(current()), {
    kind: "cancel",
    subscriptionId: "sub_Current000001",
    atCycleEnd: true,
  });
  assertEquals(decideCancel(current({ status: "created" })), {
    kind: "cancel",
    subscriptionId: "sub_Current000001",
    atCycleEnd: false,
  });
});

Deno.test("cancel: nothing live, or already ending, is none", () => {
  assertEquals(decideCancel(null), { kind: "none" });
  assertEquals(decideCancel(current({ status: "cancelled" })), { kind: "none" });
  assertEquals(decideCancel(current({ status: "halted" })), { kind: "none" });
  assertEquals(decideCancel(current({ cancel_at_cycle_end: true })), { kind: "none" });
});
