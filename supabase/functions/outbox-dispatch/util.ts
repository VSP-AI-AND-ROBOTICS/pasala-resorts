/** Parses a JSON object, or returns null for anything else. */
export function safeJson(text: string): Record<string, unknown> | null {
  try {
    const value: unknown = JSON.parse(text);
    return value !== null && typeof value === "object" && !Array.isArray(value)
      ? value as Record<string, unknown>
      : null;
  } catch {
    return null;
  }
}

/** Cuts text to what `outbox.last_error` keeps (1000 characters). */
export function clip(text: string, max = 1000): string {
  return text.length <= max ? text : text.slice(0, max - 1) + "…";
}

export function errorText(e: unknown): string {
  return e instanceof Error ? e.message : String(e);
}

/** HTTP statuses worth another attempt later. */
export function isRetryableStatus(status: number): boolean {
  return status === 408 || status === 429 || status >= 500;
}
