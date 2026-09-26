import { assert, assertEquals, assertFalse } from "jsr:@std/assert@1";
import { hmacSha256Hex, timingSafeEqual, verifyWebhookSignature } from "./signature.ts";

Deno.test("hmacSha256Hex matches RFC 4231 test case 2", async () => {
  assertEquals(
    await hmacSha256Hex("Jefe", "what do ya want for nothing?"),
    "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843",
  );
});

Deno.test("timingSafeEqual compares whole strings", () => {
  assert(timingSafeEqual("abc", "abc"));
  assertFalse(timingSafeEqual("abc", "abd"));
  assertFalse(timingSafeEqual("abc", "abcd"));
});

Deno.test("a signature over the raw body verifies, in either case", async () => {
  const body = '{"event":"subscription.charged"}';
  const sig = await hmacSha256Hex("whsec_test", body);
  assert(await verifyWebhookSignature(body, sig, "whsec_test"));
  assert(await verifyWebhookSignature(body, sig.toUpperCase(), "whsec_test"));
});

Deno.test("a wrong secret, a missing signature or a re-serialised body fails", async () => {
  const body = '{"event":"subscription.charged"}';
  const sig = await hmacSha256Hex("whsec_test", body);
  assertFalse(await verifyWebhookSignature(body, sig, "another_secret"));
  assertFalse(await verifyWebhookSignature(body, null, "whsec_test"));
  assertFalse(await verifyWebhookSignature('{"event": "subscription.charged"}', sig, "whsec_test"));
});
