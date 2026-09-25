// The dispatcher's three RPCs (0056_email_sms_delivery.sql), called
// through PostgREST with the service role key -- the only role they are
// granted to.
import type { ChannelMode, ClaimedMessage, FetchFn, Outcome, OutboxStore } from "./types.ts";
import { clip } from "./util.ts";

export class StoreError extends Error {
  constructor(readonly status: number, message: string) {
    super(message);
    this.name = "StoreError";
  }
}

/** `complete_outbox_message`'s arguments for one outcome. */
export function outcomeArgs(id: string, outcome: Outcome): Record<string, string | null> {
  switch (outcome.kind) {
    case "sent":
      return { p_id: id, p_outcome: "sent", p_error: null, p_provider_id: outcome.providerId };
    case "dry_run":
      return { p_id: id, p_outcome: "dry_run", p_error: outcome.reason, p_provider_id: null };
    case "retry":
      return { p_id: id, p_outcome: "retry", p_error: outcome.error, p_provider_id: null };
    case "failed":
      return { p_id: id, p_outcome: "failed", p_error: outcome.error, p_provider_id: null };
  }
}

export class RestOutboxStore implements OutboxStore {
  constructor(
    private readonly supabaseUrl: string,
    private readonly serviceKey: string,
    private readonly fetchFn: FetchFn = fetch,
  ) {}

  private async rpc(name: string, args: Record<string, unknown>): Promise<unknown> {
    const response = await this.fetchFn(`${this.supabaseUrl}/rest/v1/rpc/${name}`, {
      method: "POST",
      headers: {
        "apikey": this.serviceKey,
        "Authorization": `Bearer ${this.serviceKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(args),
    });
    const text = await response.text();
    if (!response.ok) {
      throw new StoreError(response.status, clip(`${name} ${response.status}: ${text}`));
    }
    return text.trim() === "" ? null : JSON.parse(text);
  }

  async claim(limit: number): Promise<ClaimedMessage[]> {
    const rows = await this.rpc("claim_outbox_batch", { p_limit: limit });
    return Array.isArray(rows) ? rows as ClaimedMessage[] : [];
  }

  async complete(id: string, outcome: Outcome): Promise<string> {
    return String(await this.rpc("complete_outbox_message", outcomeArgs(id, outcome)));
  }

  async recordRun(modes: ChannelMode[]): Promise<void> {
    await this.rpc("record_outbox_dispatch_run", { p_channels: modes });
  }
}
