// What payments-verify and payments-webhook both do after settling.
import type { RazorpayApi, RazorpayConfig, RazorpayOrder, ServicePaymentsDb, SettleResult } from "./payments_types.ts";
import { paymentsLive } from "./razorpay.ts";

export type CaptureCheck =
  | { state: "captured"; order: RazorpayOrder }
  | { state: "pending"; status: string; order: RazorpayOrder }
  | { state: "mismatch"; reason: string };

/**
 * Checkout's signature proves a payment was authorized, not that the money
 * was captured. With manual capture, or a payment authorized late (which
 * Razorpay does not auto-capture), an uncaptured payment is returned to
 * the guest after a few days -- so it must never confirm a booking.
 *
 * Asks Razorpay for the payment and its order and answers:
 *  - mismatch: the payment is not for this order, amount or currency;
 *  - captured: the money is ours (an authorized payment is captured here
 *    first, for the order's amount);
 *  - pending: not captured (still created, a capture that failed, failed,
 *    refunded). Nothing may be settled; the payment.captured webhook
 *    settles it if it is captured later.
 * Throws when Razorpay cannot be asked.
 */
export async function ensureCaptured(
  razorpay: RazorpayApi,
  orderId: string,
  paymentId: string,
): Promise<CaptureCheck> {
  const [payment, order] = await Promise.all([razorpay.fetchPayment(paymentId), razorpay.fetchOrder(orderId)]);
  if (payment.order_id !== orderId) return { state: "mismatch", reason: "payment is for another order" };
  if (payment.amount !== order.amount || payment.currency !== order.currency) {
    return { state: "mismatch", reason: "payment amount differs from the order" };
  }
  if (payment.status === "captured") return { state: "captured", order };
  if (payment.status !== "authorized") return { state: "pending", status: payment.status, order };

  try {
    const captured = await razorpay.capturePayment(paymentId, { amountPaise: order.amount, currency: order.currency });
    if (captured.status === "captured") return { state: "captured", order };
  } catch (e) {
    // Captured meanwhile (the other of verify and the webhook), or refused.
    console.error("capture failed", paymentId, e);
  }
  const again = await razorpay.fetchPayment(paymentId);
  return again.status === "captured" ? { state: "captured", order } : { state: "pending", status: again.status, order };
}

/** A string note payments-create-order put on the order, or null. */
export function orderNote(order: RazorpayOrder, name: string): string | null {
  const notes = order.notes;
  if (Array.isArray(notes) || typeof notes !== "object" || notes === null) return null;
  const value = (notes as Record<string, unknown>)[name];
  return typeof value === "string" ? value : null;
}

export type RefundState = "initiated" | "failed" | null;

/**
 * Refunds an unapplied payment in full (spec decision 10). Returns null
 * when no refund is due.
 *
 * payment_order_settle answers `refund_needed` to one caller only (it
 * claims the refund), so verify and the webhook settling the same payment
 * at once do not both refund it. The refund also carries an idempotency key
 * and receipt that are the same for every call for this payment, so even a
 * repeat after a lapsed claim returns Razorpay's first refund rather than
 * making a second (final review minor 1).
 *
 * A failed refund is logged and its claim given back, so the next settle
 * call tries again: payment_order_settle keeps offering the refund until
 * one is recorded.
 */
export async function refundIfNeeded(
  settled: SettleResult,
  razorpay: RazorpayApi,
  service: ServicePaymentsDb,
): Promise<RefundState> {
  if (!settled.refund_needed) return null;
  const key = `unapplied_${settled.razorpay_payment_id}`;
  try {
    const refund = await razorpay.refundPayment(settled.razorpay_payment_id, {
      notes: { reason: "unapplied", reservation_id: settled.reservation_id },
      receipt: key,
      idempotencyKey: key,
    });
    await service.recordRefund(settled.razorpay_payment_id, refund.id, refund.amount / 100);
    return "initiated";
  } catch (e) {
    console.error("refund failed", settled.razorpay_payment_id, e);
    try {
      await service.releaseRefund(settled.razorpay_payment_id);
    } catch (release) {
      // The claim lapses on its own after 10 minutes.
      console.error("refund claim release failed", settled.razorpay_payment_id, release);
    }
    return "failed";
  }
}

/**
 * Keeps the database's live switch (payments_set_live) in step with the
 * secrets from payments-verify and payments-webhook too, not only from
 * payments-create-order (final review minor 2). Never fails the caller: a
 * payment is settled even when the switch cannot be written.
 */
export async function syncLive(service: ServicePaymentsDb, config: RazorpayConfig | null): Promise<void> {
  const live = paymentsLive(config);
  try {
    await service.setLive(live, live ? config.keyId : null);
  } catch (e) {
    console.error("payments_set_live failed", e);
  }
}
