// The contract between the outbox-dispatch Edge Function and
// supabase/migrations/0056_email_sms_delivery.sql, and between this
// function's modules. See
// docs/superpowers/specs/2026-09-25-p7-email-and-sms-delivery-design.md.

export type Channel = "email" | "sms" | "whatsapp";

/** One row returned by `claim_outbox_batch`. */
export interface ClaimedMessage {
  id: string;
  property_id: string;
  reservation_id: string;
  channel: Channel;
  recipient: string;
  template: string;
  subject: string | null;
  body: string | null;
  /** Attempts so far, including this one. */
  attempts: number;
  /** `outbox_template_context` without customer_email / customer_phone. */
  vars: Record<string, string>;
}

/** What `complete_outbox_message` is told about one claimed row. */
export type Outcome =
  | { kind: "sent"; providerId: string | null }
  | { kind: "dry_run"; reason: string }
  | { kind: "retry"; error: string }
  | { kind: "failed"; error: string };

/** A provider's answer for one message. */
export type SendResult =
  | { ok: true; providerId: string | null }
  | { ok: false; retryable: boolean; error: string };

export interface EmailMessage {
  to: string;
  /** The resort's name; shown as the sender's display name. */
  fromName: string;
  subject: string;
  text: string;
  /** The outbox row id, so a repeat of the same row is not delivered twice. */
  idempotencyKey: string;
}

export interface EmailSender {
  send(message: EmailMessage): Promise<SendResult>;
}

export interface SmsMessage {
  /** `91` followed by a 10-digit Indian mobile number. */
  mobile: string;
  templateId: string;
  vars: Record<string, string>;
}

export interface SmsSender {
  send(message: SmsMessage): Promise<SendResult>;
}

/** One element of `record_outbox_dispatch_run`'s p_channels. */
export interface ChannelMode {
  channel: "email" | "sms";
  mode: "live" | "dry_run";
  provider: string;
  detail: string | null;
}

/** The three RPCs this function calls, all granted to service_role only. */
export interface OutboxStore {
  claim(limit: number): Promise<ClaimedMessage[]>;
  /** Returns the row's new `outbox_status`. */
  complete(id: string, outcome: Outcome): Promise<string>;
  recordRun(modes: ChannelMode[]): Promise<void>;
}

export interface DispatchSummary {
  claimed: number;
  sent: number;
  dry_run: number;
  retry: number;
  failed: number;
  /** Rows whose result could not be recorded, plus a failed run record. */
  errors: number;
  modes: { email: "live" | "dry_run"; sms: "live" | "dry_run" };
}

export type FetchFn = (input: string, init?: RequestInit) => Promise<Response>;

export interface EmailConfig {
  apiKey: string;
  /** A bare address, e.g. bookings@mail.example.com. */
  from: string;
}

export interface SmsConfig {
  authKey: string;
  senderId: string | null;
  /** Outbox template name -> MSG91 template id. */
  templates: Record<string, string>;
}

/** A channel is either live with its config, or a dry run with a reason. */
export type Setup<T> =
  | { mode: "live"; provider: string; config: T }
  | { mode: "dry_run"; provider: string; detail: string };

export interface DispatchConfig {
  supabaseUrl: string;
  serviceKey: string;
  batchSize: number;
  email: Setup<EmailConfig>;
  sms: Setup<SmsConfig>;
}
