import {
  type CalendarLookup,
  type CalendarStore,
  ICS_CONTENT_TYPE,
  TOKEN_PATTERN,
} from "./types.ts";

/**
 * The token from `/ical-export/<token>.ics`, or from `?token=` when the
 * path ends at the function name. Null unless it looks like a real token,
 * so junk never reaches the database.
 */
export function tokenFrom(url: URL): string | null {
  const last = url.pathname.split("/").filter((s) => s !== "").pop() ?? "";
  const fromPath = last.replace(/\.ics$/i, "");
  const candidate = fromPath === "" || fromPath === "ical-export"
    ? url.searchParams.get("token") ?? ""
    : fromPath;
  return TOKEN_PATTERN.test(candidate) ? candidate : null;
}

function plain(status: number, body: string, head: boolean): Response {
  return new Response(head ? null : body, {
    status,
    headers: {
      "Content-Type": "text/plain; charset=utf-8",
      "Cache-Control": "no-store",
    },
  });
}

/** Serves one unit's calendar to an OTA. Never throws. */
export async function handle(
  req: Request,
  store: CalendarStore,
): Promise<Response> {
  const head = req.method === "HEAD";
  if (req.method !== "GET" && !head) {
    return new Response("Method not allowed", {
      status: 405,
      headers: {
        Allow: "GET, HEAD",
        "Content-Type": "text/plain; charset=utf-8",
      },
    });
  }

  const token = tokenFrom(new URL(req.url));
  if (token === null) return plain(404, "Calendar not found", head);

  let found: CalendarLookup;
  try {
    found = await store.lookup(token);
  } catch (e) {
    found = { kind: "unavailable", detail: String(e) };
  }

  switch (found.kind) {
    case "ok":
      return new Response(head ? null : found.ics, {
        status: 200,
        headers: {
          "Content-Type": ICS_CONTENT_TYPE,
          "Cache-Control": "no-cache, max-age=0",
        },
      });
    case "not_found":
      return plain(404, "Calendar not found", head);
    case "unavailable":
      console.error(`ical-export: ${found.detail}`);
      return plain(502, "Calendar temporarily unavailable", head);
  }
}

/**
 * Reads the calendar through PostgREST's `ical_export_public` (granted to
 * `anon`) with the project's anon key. PostgREST returns the text as a JSON
 * string, or `null` when the unit's resort is not active.
 */
export function restStore(
  supabaseUrl: string,
  anonKey: string,
  fetchFn: typeof fetch = fetch,
): CalendarStore {
  const base = supabaseUrl.replace(/\/+$/, "");
  const endpoint = `${base}/rest/v1/rpc/ical_export_public`;
  return {
    async lookup(token: string): Promise<CalendarLookup> {
      const res = await fetchFn(endpoint, {
        method: "POST",
        headers: {
          apikey: anonKey,
          Authorization: `Bearer ${anonKey}`,
          "Content-Type": "application/json",
          Accept: "application/json",
        },
        body: JSON.stringify({ p_token: token }),
      });
      const body = await res.json().catch(() => null);
      if (res.ok) {
        return typeof body === "string" && body !== ""
          ? { kind: "ok", ics: body }
          : { kind: "not_found" };
      }
      if (body?.code === "P0002") return { kind: "not_found" };
      return {
        kind: "unavailable",
        detail: `HTTP ${res.status} ${body?.code ?? ""} ${body?.message ?? ""}`
          .trim(),
      };
    },
  };
}
