/// Online payments (P6): what the app sends to and reads back from the
/// payments-* Edge Functions. The shapes mirror
/// supabase/functions/_shared/payments_types.ts.
library;

/// What an online payment is for. Mirrors `public.payment_kind`: an
/// advance confirms a hold, a balance checks the guest out.
enum PaymentPurpose {
  advance('advance'),
  balance('balance');

  const PaymentPurpose(this.wire);

  /// The value `payments-create-order` and `public.payment_kind` use.
  final String wire;
}

/// What `payments-create-order` answered.
sealed class CreateOrderResult {
  const CreateOrderResult();

  factory CreateOrderResult.fromJson(Map<String, dynamic> json) =>
      json['configured'] == true
      ? RazorpayOrder.fromJson(json)
      : const PaymentsNotConfigured();
}

/// The deployment has no Razorpay keys: pay through the mock, exactly as
/// before P6 (spec decision 3).
final class PaymentsNotConfigured extends CreateOrderResult {
  const PaymentsNotConfigured();
}

/// A Razorpay order the server created for this exact amount.
final class RazorpayOrder extends CreateOrderResult {
  const RazorpayOrder({
    required this.keyId,
    required this.orderId,
    required this.amountPaise,
    required this.currency,
    required this.name,
    required this.description,
    required this.reservationId,
    this.prefillName,
    this.prefillEmail,
    this.prefillContact,
  });

  factory RazorpayOrder.fromJson(Map<String, dynamic> json) {
    final prefill =
        (json['prefill'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    return RazorpayOrder(
      keyId: json['key_id'] as String,
      orderId: json['order_id'] as String,
      amountPaise: (json['amount'] as num).toInt(),
      currency: json['currency'] as String? ?? 'INR',
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      reservationId: json['reservation_id'] as String,
      prefillName: prefill['name'] as String?,
      prefillEmail: prefill['email'] as String?,
      prefillContact: prefill['contact'] as String?,
    );
  }

  /// The public Razorpay key id (never the secret).
  final String keyId;
  final String orderId;
  final int amountPaise;
  final String currency;

  /// The resort's name, shown in the payment window.
  final String name;
  final String description;
  final String reservationId;
  final String? prefillName;
  final String? prefillEmail;
  final String? prefillContact;
}

enum VerifyOutcome { paid, unapplied }

enum RefundState { initiated, failed }

/// What `payments-verify` answered once the server settled the payment.
class VerifyResult {
  const VerifyResult({
    required this.outcome,
    required this.reservationId,
    this.refund,
  });

  /// Anything but `paid` is treated as unapplied: the app must never claim
  /// a booking is paid on an answer it does not understand.
  factory VerifyResult.fromJson(Map<String, dynamic> json) => VerifyResult(
    outcome: json['outcome'] == 'paid'
        ? VerifyOutcome.paid
        : VerifyOutcome.unapplied,
    reservationId: json['reservation_id'] as String,
    refund: switch (json['refund']) {
      'initiated' => RefundState.initiated,
      'failed' => RefundState.failed,
      _ => null,
    },
  );

  final VerifyOutcome outcome;
  final String reservationId;
  final RefundState? refund;
}
