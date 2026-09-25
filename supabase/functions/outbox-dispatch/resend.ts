// Email through the Resend HTTP API (https://resend.com/docs/api-reference/emails/send-email).
import type { EmailMessage, EmailSender, FetchFn, SendResult } from "./types.ts";
import { clip, errorText, isRetryableStatus, safeJson } from "./util.ts";

export const RESEND_URL = "https://api.resend.com/emails";

/**
 * The sender's display name: the resort's name without the characters
 * that would break a `Name <address>` header; "ResortHub" when empty.
 */
export function displayName(raw: string | undefined | null): string {
  const cleaned = (raw ?? "").replace(/[<>",;\r\n]/g, " ").replace(/\s+/g, " ").trim();
  return cleaned === "" ? "ResortHub" : cleaned;
}

export class ResendEmailSender implements EmailSender {
  constructor(
    private readonly apiKey: string,
    private readonly from: string,
    private readonly fetchFn: FetchFn = fetch,
  ) {}

  async send(message: EmailMessage): Promise<SendResult> {
    let response: Response;
    try {
      response = await this.fetchFn(RESEND_URL, {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${this.apiKey}`,
          "Content-Type": "application/json",
          // The outbox row id: if a run dies after Resend accepted the
          // email, the retry of the same row is not delivered twice.
          "Idempotency-Key": message.idempotencyKey,
        },
        body: JSON.stringify({
          from: `${displayName(message.fromName)} <${this.from}>`,
          to: [message.to],
          subject: message.subject,
          text: message.text,
        }),
      });
    } catch (e) {
      return { ok: false, retryable: true, error: clip(`resend: network error: ${errorText(e)}`) };
    }

    const text = await response.text();
    const json = safeJson(text);
    if (response.ok) {
      return { ok: true, providerId: typeof json?.id === "string" ? json.id : null };
    }
    const detail = typeof json?.message === "string" ? json.message : text;
    return {
      ok: false,
      retryable: isRetryableStatus(response.status),
      error: clip(`resend ${response.status}: ${detail}`),
    };
  }
}
