// CORS and JSON helpers for the payments-* Edge Functions. The Flutter
// web build calls them from another origin, so every response, errors
// included, carries the CORS headers.
import type { ErrorBody } from "./payments_types.ts";

export const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

export function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

/** An error body in the shape every payments function uses. */
export function fail(
  status: number,
  error: ErrorBody["error"],
  message: string,
  code?: string,
): Response {
  const body: ErrorBody = code === undefined ? { error, message } : { error, code, message };
  return json(status, body);
}

export function preflight(): Response {
  return new Response("ok", { headers: corsHeaders });
}
