// What payments-verify and payments-webhook both do after settling.
import type { RazorpayApi, RazorpayOrder, ServicePaymentsDb, SettleResult } from "./payments_types.ts";

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
