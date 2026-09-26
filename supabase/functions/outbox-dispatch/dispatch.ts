// One dispatcher run: claim a batch, send each row (or record a dry run),
// report each result, then record the run. State changes (backoff, the
// attempt limit, statuses) are decided in SQL by complete_outbox_message.
import { normalizeIndianMobile } from "./msg91.ts";
import type {
  ChannelMode,
  ClaimedMessage,
  DispatchConfig,
  DispatchSummary,
  EmailSender,
  Outcome,
  OutboxStore,
  SendResult,
  SmsSender,
} from "./types.ts";
import { clip, errorText } from "./util.ts";

export interface DispatchDeps {
  config: DispatchConfig;
  store: OutboxStore;
  /** Null when email is a dry run. */
  email: EmailSender | null;
  /** Null when SMS is a dry run. */
  sms: SmsSender | null;
  /** One structured line per event. Never given a recipient, subject or body. */
  log: (entry: Record<string, unknown>) => void;
}

export function channelModes(config: DispatchConfig): ChannelMode[] {
  return [
    {
      channel: "email",
      mode: config.email.mode,
      provider: config.email.provider,
      detail: config.email.mode === "dry_run" ? config.email.detail : null,
    },
    {
      channel: "sms",
      mode: config.sms.mode,
      provider: config.sms.provider,
      detail: config.sms.mode === "dry_run" ? config.sms.detail : null,
    },
  ];
}

function fromSendResult(result: SendResult): Outcome {
  if (result.ok) return { kind: "sent", providerId: result.providerId };
  return result.retryable ? { kind: "retry", error: result.error } : { kind: "failed", error: result.error };
}

export async function deliver(row: ClaimedMessage, deps: DispatchDeps): Promise<Outcome> {
  if (row.channel === "email") {
    const setup = deps.config.email;
    if (setup.mode === "dry_run" || deps.email === null) {
      return { kind: "dry_run", reason: `Dry run: ${setup.mode === "dry_run" ? setup.detail : "no email sender"}` };
    }
    if (!row.subject || !row.body) {
      return { kind: "failed", error: "nothing to send: the message has no subject or body" };
    }
    return fromSendResult(
      await deps.email.send({
        to: row.recipient,
        fromName: row.vars?.property_name ?? "",
        subject: row.subject,
        text: row.body,
        idempotencyKey: row.id,
      }),
    );
  }

  if (row.channel === "sms") {
    const setup = deps.config.sms;
    if (setup.mode === "dry_run" || deps.sms === null) {
      return { kind: "dry_run", reason: `Dry run: ${setup.mode === "dry_run" ? setup.detail : "no SMS sender"}` };
    }
    const templateId = setup.config.templates[row.template];
    if (!templateId) {
      return { kind: "failed", error: `no MSG91 template id for ${row.template} in MSG91_TEMPLATES` };
    }
    const mobile = normalizeIndianMobile(row.recipient);
    if (mobile === null) {
      return { kind: "failed", error: "the phone number on file is not a valid Indian mobile number" };
    }
    return fromSendResult(await deps.sms.send({ mobile, templateId, vars: row.vars ?? {} }));
  }

  // claim_outbox_batch never returns WhatsApp rows; this is a backstop.
  return { kind: "failed", error: `no sender for the ${row.channel} channel` };
}

export async function dispatchOnce(deps: DispatchDeps): Promise<DispatchSummary> {
  const summary: DispatchSummary = {
    claimed: 0,
    sent: 0,
    dry_run: 0,
    retry: 0,
    failed: 0,
    errors: 0,
    modes: { email: deps.config.email.mode, sms: deps.config.sms.mode },
  };

  const rows = await deps.store.claim(deps.config.batchSize);
  summary.claimed = rows.length;

  for (const row of rows) {
    let outcome: Outcome;
    try {
      outcome = await deliver(row, deps);
    } catch (e) {
      outcome = { kind: "retry", error: clip(`unexpected error: ${errorText(e)}`) };
    }
    try {
      await deps.store.complete(row.id, outcome);
      summary[outcome.kind] += 1;
      deps.log({ event: "outbox_message", id: row.id, channel: row.channel, template: row.template, outcome: outcome.kind });
    } catch (e) {
      // The row's lease runs out and a later run claims it again.
      summary.errors += 1;
      deps.log({ event: "outbox_complete_failed", id: row.id, outcome: outcome.kind, error: errorText(e) });
    }
  }

  try {
    await deps.store.recordRun(channelModes(deps.config));
  } catch (e) {
    summary.errors += 1;
    deps.log({ event: "outbox_record_run_failed", error: errorText(e) });
  }

  deps.log({ event: "outbox_dispatch_run", ...summary });
  return summary;
}
