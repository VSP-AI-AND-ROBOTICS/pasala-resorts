// HTTP entry: POST only, and only with the service role key (pg_cron's
// outbox_dispatch_tick sends it from Vault; a person running it by hand
// passes it too).
import { ConfigError } from "./config.ts";
import { type DispatchDeps, dispatchOnce } from "./dispatch.ts";
import { errorText } from "./util.ts";

/** Compares every byte, so the time taken does not reveal how much matched. */
export function timingSafeEqual(a: string, b: string): boolean {
  const left = new TextEncoder().encode(a);
  const right = new TextEncoder().encode(b);
  let diff = left.length ^ right.length;
  const length = Math.max(left.length, right.length);
  for (let i = 0; i < length; i++) {
    diff |= (left[i] ?? 0) ^ (right[i] ?? 0);
  }
  return diff === 0;
}

export function bearerMatches(header: string | null, key: string): boolean {
  if (header === null) return false;
  const match = /^Bearer\s+(\S+)$/i.exec(header.trim());
  return match !== null && timingSafeEqual(match[1], key);
}

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

export async function handleRequest(req: Request, makeDeps: () => DispatchDeps): Promise<Response> {
  if (req.method !== "POST") return json(405, { error: "method_not_allowed" });

  let deps: DispatchDeps;
  try {
    deps = makeDeps();
  } catch (e) {
    const detail = e instanceof ConfigError ? e.message : "configuration error";
    return json(500, { error: "not_configured", detail });
  }

  if (!bearerMatches(req.headers.get("Authorization"), deps.config.serviceKey)) {
    return json(401, { error: "unauthorized" });
  }

  try {
    return json(200, await dispatchOnce(deps));
  } catch (e) {
    deps.log({ event: "outbox_dispatch_failed", error: errorText(e) });
    return json(502, { error: "store_unavailable" });
  }
}
