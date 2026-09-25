import type { ErrorBody, ErrorKind } from "./types.ts";

export const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

/** A JSON response; browser-facing functions add the CORS headers. */
export function json(status: number, body: unknown, cors = true): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...(cors ? corsHeaders : {}), "Content-Type": "application/json" },
  });
}

/** The error body every billing function uses: {error, code?, message}. */
export function fail(
  status: number,
  error: ErrorKind,
  message: string,
  code?: string,
  cors = true,
): Response {
  const body: ErrorBody = code ? { error, code, message } : { error, message };
  return json(status, body, cors);
}

/** The answer to a browser's CORS preflight. */
export function preflight(): Response {
  return new Response("ok", { headers: corsHeaders });
}
