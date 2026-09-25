// Contract for the `ical-export` Edge Function (P9). See
// docs/superpowers/specs/2026-09-25-p9-ota-sync-reliability-design.md.
//
// Request:  GET or HEAD /functions/v1/ical-export/<token>.ics
//           (also accepted: /functions/v1/ical-export?token=<token>)
// Response: 200 text/calendar; charset=utf-8 -- the unit's busy dates
//           404 text/plain -- unknown token, or the resort is not active
//           405 text/plain -- any other method (Allow: GET, HEAD)
//           502 text/plain -- the database could not be read

/** What looking a token up in the database can give. */
export type CalendarLookup =
  | { kind: "ok"; ics: string }
  | { kind: "not_found" }
  | { kind: "unavailable"; detail: string };

/** Where the handler reads a calendar from; faked in tests. */
export interface CalendarStore {
  lookup(token: string): Promise<CalendarLookup>;
}

export const ICS_CONTENT_TYPE = "text/calendar; charset=utf-8";

/** `encode(gen_random_bytes(24), 'hex')` -- see 0018_ical.sql. */
export const TOKEN_PATTERN = /^[0-9a-f]{48}$/;
