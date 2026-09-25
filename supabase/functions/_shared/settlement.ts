// What payments-verify and payments-webhook both do after settling.
import type { RazorpayApi, ServicePaymentsDb, SettleResult } from "./payments_types.ts";

export type RefundState = "initiated" | "failed" | null;

/**
 * Refunds an unapplied payment in full (spec decision 10). Returns null
 * when no refund is due. A failed refund is logged and left for the next
 * settle call: payment_order_settle keeps `refund_needed` true until a
 * refund is recorded.
 */
export async function refundIfNeeded(
  settled: SettleResult,
  razorpay: RazorpayApi,
  service: ServicePaymentsDb,
): Promise<RefundState> {
  if (!settled.refund_needed) return null;
  try {
    const refund = await razorpay.refundPayment(settled.razorpay_payment_id, {
      notes: { reason: "unapplied", reservation_id: settled.reservation_id },
    });
    await service.recordRefund(settled.razorpay_payment_id, refund.id, refund.amount / 100);
    return "initiated";
  } catch (e) {
    console.error("refund failed", settled.razorpay_payment_id, e);
    return "failed";
  }
}
