// Test-only doubles. Not a *_test.ts file and never imported by index.ts.
import type {
  ChannelMode,
  ClaimedMessage,
  DispatchConfig,
  EmailMessage,
  EmailSender,
  Outcome,
  OutboxStore,
  SendResult,
  SmsMessage,
  SmsSender,
} from "./types.ts";

export const liveConfig: DispatchConfig = {
  supabaseUrl: "http://127.0.0.1:54321",
  serviceKey: "service-key",
  batchSize: 50,
  email: { mode: "live", provider: "resend", config: { apiKey: "re_k", from: "bookings@mail.example.com" } },
  sms: {
    mode: "live",
    provider: "msg91",
    config: { authKey: "auth", senderId: null, templates: { booking_confirmation_sms: "tmpl-confirm" } },
  },
};

export const dryConfig: DispatchConfig = {
  ...liveConfig,
  email: { mode: "dry_run", provider: "resend", detail: "RESEND_API_KEY is not set" },
  sms: { mode: "dry_run", provider: "msg91", detail: "MSG91_AUTH_KEY is not set" },
};

export function emailRow(overrides: Partial<ClaimedMessage> = {}): ClaimedMessage {
  return {
    id: "0b7f5c1e-0000-4000-8000-000000000001",
    property_id: "p1",
    reservation_id: "r1",
    channel: "email",
    recipient: "asha@example.com",
    template: "booking_confirmation",
    subject: "Your stay at Pasala Farm House is confirmed",
    body: "Hi Asha Rao, your booking for Mango Cottage is confirmed.",
    attempts: 1,
    vars: { guest_name: "Asha Rao", unit_name: "Mango Cottage", property_name: "Pasala Farm House" },
    ...overrides,
  };
}

export function smsRow(overrides: Partial<ClaimedMessage> = {}): ClaimedMessage {
  return {
    id: "0b7f5c1e-0000-4000-8000-000000000002",
    property_id: "p1",
    reservation_id: "r1",
    channel: "sms",
    recipient: "+91 98765 43210",
    template: "booking_confirmation_sms",
    subject: null,
    body: "Pasala Resorts: Hi Asha Rao, your stay at Mango Cottage is confirmed.",
    attempts: 1,
    vars: { guest_name: "Asha Rao", unit_name: "Mango Cottage", property_name: "Pasala Farm House" },
    ...overrides,
  };
}

export class FakeStore implements OutboxStore {
  rows: ClaimedMessage[] = [];
  claimError: Error | null = null;
  recordError: Error | null = null;
  readonly failCompleteFor = new Set<string>();
  readonly claimLimits: number[] = [];
  readonly completed: Array<{ id: string; outcome: Outcome }> = [];
  readonly runs: ChannelMode[][] = [];

  claim(limit: number): Promise<ClaimedMessage[]> {
    this.claimLimits.push(limit);
    return this.claimError ? Promise.reject(this.claimError) : Promise.resolve(this.rows);
  }

  complete(id: string, outcome: Outcome): Promise<string> {
    if (this.failCompleteFor.has(id)) return Promise.reject(new Error(`complete failed for ${id}`));
    this.completed.push({ id, outcome });
    return Promise.resolve(outcome.kind === "retry" ? "pending" : outcome.kind);
  }

  recordRun(modes: ChannelMode[]): Promise<void> {
    if (this.recordError) return Promise.reject(this.recordError);
    this.runs.push(modes);
    return Promise.resolve();
  }
}

export class FakeEmailSender implements EmailSender {
  readonly sent: EmailMessage[] = [];
  results: Array<SendResult | Error> = [];

  send(message: EmailMessage): Promise<SendResult> {
    this.sent.push(message);
    const fallback: SendResult = { ok: true, providerId: "re_default" };
    const next = this.results.shift() ?? fallback;
    return next instanceof Error ? Promise.reject(next) : Promise.resolve(next);
  }
}

export class FakeSmsSender implements SmsSender {
  readonly sent: SmsMessage[] = [];
  results: Array<SendResult | Error> = [];

  send(message: SmsMessage): Promise<SendResult> {
    this.sent.push(message);
    const fallback: SendResult = { ok: true, providerId: "msg91_default" };
    const next = this.results.shift() ?? fallback;
    return next instanceof Error ? Promise.reject(next) : Promise.resolve(next);
  }
}
