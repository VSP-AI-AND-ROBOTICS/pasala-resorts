// SMS through the MSG91 Flow API (DLT-registered templates, India).
import type { FetchFn, SendResult, SmsMessage, SmsSender } from "./types.ts";
import { clip, errorText, isRetryableStatus, safeJson } from "./util.ts";

export const MSG91_FLOW_URL = "https://control.msg91.com/api/v5/flow";

/** DLT (TRAI) templates allow at most 30 characters per variable. */
export const DLT_VAR_MAX = 30;

/**
 * `91` + a 10-digit Indian mobile number (first digit 6-9), however the
 * guest typed it ("+91 98765 43210", "098765 43210", "0091 …"), or null
 * when it is not an Indian mobile number.
 */
export function normalizeIndianMobile(raw: string): string | null {
  let digits = raw.replace(/\D/g, "");
  if (digits.startsWith("00")) digits = digits.slice(2);
  let national: string;
  if (digits.length === 10) {
    national = digits;
  } else if (digits.length === 11 && digits.startsWith("0")) {
    national = digits.slice(1);
  } else if (digits.length === 12 && digits.startsWith("91")) {
    national = digits.slice(2);
  } else {
    return null;
  }
  return /^[6-9]\d{9}$/.test(national) ? `91${national}` : null;
}

/** Template variables as MSG91 wants them: strings, each cut to the DLT limit. */
export function smsVars(vars: Record<string, unknown>): Record<string, string> {
  const out: Record<string, string> = {};
  for (const [key, value] of Object.entries(vars)) {
    out[key] = String(value ?? "").slice(0, DLT_VAR_MAX);
  }
  return out;
}

export class Msg91SmsSender implements SmsSender {
  constructor(
    private readonly authKey: string,
    private readonly senderId: string | null,
    private readonly fetchFn: FetchFn = fetch,
  ) {}

  async send(message: SmsMessage): Promise<SendResult> {
    const payload: Record<string, unknown> = {
      template_id: message.templateId,
      short_url: "0",
      // mobiles last, so no template variable can replace the recipient.
      recipients: [{ ...smsVars(message.vars), mobiles: message.mobile }],
    };
    if (this.senderId) payload.sender = this.senderId;

    let response: Response;
    try {
      response = await this.fetchFn(MSG91_FLOW_URL, {
        method: "POST",
        headers: {
          "authkey": this.authKey,
          "Content-Type": "application/json",
          "Accept": "application/json",
        },
        body: JSON.stringify(payload),
      });
    } catch (e) {
      return { ok: false, retryable: true, error: clip(`msg91: network error: ${errorText(e)}`) };
    }

    const text = await response.text();
    const json = safeJson(text);
    const detail = typeof json?.message === "string" ? json.message : text;
    if (!response.ok) {
      return {
        ok: false,
        retryable: isRetryableStatus(response.status),
        error: clip(`msg91 ${response.status}: ${detail}`),
      };
    }
    if (json?.type === "success") {
      return { ok: true, providerId: typeof json.message === "string" ? json.message : null };
    }
    // MSG91 reports many refusals (bad template, DLT mismatch, no balance)
    // as HTTP 200 with type "error". Retrying will not fix them.
    return { ok: false, retryable: false, error: clip(`msg91: ${detail}`) };
  }
}
