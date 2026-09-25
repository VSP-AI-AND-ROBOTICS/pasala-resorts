import '../../core/format.dart';
import 'subscription.dart';

/// Razorpay's subscription states, as stored in
/// `billing_subscriptions.status` (0057_subscription_billing.sql).
enum GatewayStatus {
  created,
  authenticated,
  active,
  pending,
  halted,
  cancelled,
  completed,
  expired,
  paused,
}

/// Unknown text is rejected rather than defaulted, as in subscription.dart.
GatewayStatus gatewayStatusFromDb(String raw) => switch (raw) {
  'created' => GatewayStatus.created,
  'authenticated' => GatewayStatus.authenticated,
  'active' => GatewayStatus.active,
  'pending' => GatewayStatus.pending,
  'halted' => GatewayStatus.halted,
  'cancelled' => GatewayStatus.cancelled,
  'completed' => GatewayStatus.completed,
  'expired' => GatewayStatus.expired,
  'paused' => GatewayStatus.paused,
  _ => throw ArgumentError('Unknown billing status: $raw'),
};

extension GatewayStatusLabel on GatewayStatus {
  /// The short state the platform console shows after "Auto-pay: ".
  String get label => switch (this) {
    GatewayStatus.created => 'Waiting for authorisation',
    GatewayStatus.authenticated => 'Authorised',
    GatewayStatus.active => 'On',
    GatewayStatus.pending => 'Retrying a failed payment',
    GatewayStatus.halted => 'Stopped after failed payments',
    GatewayStatus.cancelled => 'Cancelled',
    GatewayStatus.completed => 'Finished',
    GatewayStatus.expired => 'Expired',
    GatewayStatus.paused => 'Paused',
  };
}

const _liveStatuses = {
  GatewayStatus.created,
  GatewayStatus.authenticated,
  GatewayStatus.active,
  GatewayStatus.pending,
  GatewayStatus.paused,
};

DateTime? _timeFromDb(Object? raw) =>
    raw == null ? null : DateTime.parse(raw as String).toLocal();

DateTime? _dateFromDb(Object? raw) {
  if (raw == null) return null;
  final parsed = DateTime.parse(raw as String);
  return DateTime(parsed.year, parsed.month, parsed.day);
}

num? _numFromDb(Object? raw) => switch (raw) {
  null => null,
  num n => n,
  String s => num.parse(s),
  _ => throw ArgumentError('Not a number: $raw'),
};

SubscriptionTier? _tierOrNull(Object? raw) =>
    raw == null ? null : subscriptionTierFromDb(raw as String);

GatewayStatus? _statusOrNull(Object? raw) =>
    raw == null ? null : gatewayStatusFromDb(raw as String);

/// The row `my_resort_billing(p_property)` returns: the resort's current
/// Razorpay subscription and its latest payment.
class ResortBilling {
  const ResortBilling({
    this.status,
    this.tier,
    this.shortUrl,
    this.cancelAtCycleEnd = false,
    this.currentEnd,
    this.lastPaymentAt,
    this.lastPaymentInr,
  });

  factory ResortBilling.fromRow(Map<String, dynamic> json) => ResortBilling(
    status: _statusOrNull(json['billing_status']),
    tier: _tierOrNull(json['billing_tier']),
    shortUrl: json['short_url'] as String?,
    cancelAtCycleEnd: json['cancel_at_cycle_end'] as bool? ?? false,
    currentEnd: _timeFromDb(json['current_end']),
    lastPaymentAt: _timeFromDb(json['last_payment_at']),
    lastPaymentInr: _numFromDb(json['last_payment_inr']),
  );

  /// Null when there is no current subscription (only past payments).
  final GatewayStatus? status;
  final SubscriptionTier? tier;
  final String? shortUrl;
  final bool cancelAtCycleEnd;

  /// The end of the cycle Razorpay last reported: the next charge.
  final DateTime? currentEnd;
  final DateTime? lastPaymentAt;
  final num? lastPaymentInr;

  /// A live subscription that is not already ending.
  bool get canCancel =>
      status != null && _liveStatuses.contains(status) && !cancelAtCycleEnd;
}

/// One row of `platform_billing()`, for the console.
class PlatformBilling {
  const PlatformBilling({
    required this.propertyId,
    this.status,
    this.tier,
    this.lastPaymentAt,
    this.lastPaymentInr,
  });

  factory PlatformBilling.fromRow(Map<String, dynamic> json) => PlatformBilling(
    propertyId: json['property_id'] as String,
    status: _statusOrNull(json['billing_status']),
    tier: _tierOrNull(json['billing_tier']),
    lastPaymentAt: _timeFromDb(json['last_payment_at']),
    lastPaymentInr: _numFromDb(json['last_payment_inr']),
  );

  final String propertyId;
  final GatewayStatus? status;
  final SubscriptionTier? tier;
  final DateTime? lastPaymentAt;
  final num? lastPaymentInr;
}

/// One row of `subscription_invoices`: a successful Razorpay charge.
class SubscriptionInvoice {
  const SubscriptionInvoice({
    required this.id,
    required this.tier,
    required this.amountInr,
    required this.paidAt,
    this.periodStart,
    this.periodEnd,
  });

  factory SubscriptionInvoice.fromJson(Map<String, dynamic> json) =>
      SubscriptionInvoice(
        id: json['id'] as String,
        tier: subscriptionTierFromDb(json['tier'] as String),
        amountInr: _numFromDb(json['amount_inr']) ?? 0,
        paidAt: _timeFromDb(json['paid_at'])!,
        periodStart: _dateFromDb(json['period_start']),
        periodEnd: _dateFromDb(json['period_end']),
      );

  final String id;
  final SubscriptionTier tier;
  final num amountInr;
  final DateTime paidAt;
  final DateTime? periodStart;
  final DateTime? periodEnd;
}

/// The probe's answer: whether auto-pay can be offered, and on which plans.
class BillingAvailability {
  const BillingAvailability({required this.configured, this.plans = const []});

  /// Not configured: the plan stays manual and no billing UI is shown.
  static const off = BillingAvailability(configured: false);

  factory BillingAvailability.fromJson(Map<String, dynamic> json) {
    if (json['configured'] != true) return off;
    final raw = (json['plans'] as List<dynamic>?) ?? const [];
    return BillingAvailability(
      configured: true,
      plans: [
        for (final (i, p) in raw.cast<Map<String, dynamic>>().indexed)
          SubscriptionPlan(
            tier: subscriptionTierFromDb(p['tier'] as String),
            name: p['name'] as String,
            monthlyPriceInr: _numFromDb(p['monthly_price_inr']) ?? 0,
            sortOrder: i + 1,
          ),
      ],
    );
  }

  final bool configured;

  /// Only the tiers that have a Razorpay plan id, cheapest first.
  final List<SubscriptionPlan> plans;

  bool get canPay => configured && plans.isNotEmpty;
}

enum SubscribeAction { created, reused, unchanged }

/// billing-subscribe's answer to "subscribe".
class SubscribeResult {
  const SubscribeResult({
    required this.action,
    required this.subscriptionId,
    this.shortUrl,
    required this.status,
    this.warning,
  });

  factory SubscribeResult.fromJson(Map<String, dynamic> json) =>
      SubscribeResult(
        action: switch (json['action']) {
          'created' => SubscribeAction.created,
          'reused' => SubscribeAction.reused,
          'unchanged' => SubscribeAction.unchanged,
          final other => throw ArgumentError(
            'Unknown subscribe action: $other',
          ),
        },
        subscriptionId: json['subscription_id'] as String,
        shortUrl: json['short_url'] as String?,
        status: gatewayStatusFromDb(json['status'] as String),
        warning: json['warning'] as String?,
      );

  final SubscribeAction action;
  final String subscriptionId;

  /// Razorpay's hosted page where the owner authorises auto-pay.
  final String? shortUrl;
  final GatewayStatus status;
  final String? warning;
}

enum CancelAction { cancelScheduled, cancelled, none }

CancelAction cancelActionFromWire(Object? raw) => switch (raw) {
  'cancel_scheduled' => CancelAction.cancelScheduled,
  'cancelled' => CancelAction.cancelled,
  'none' => CancelAction.none,
  _ => throw ArgumentError('Unknown cancel action: $raw'),
};

/// One line describing [billing]'s auto-pay state, always in words.
String billingStatusLine(ResortBilling billing) {
  final end = billing.currentEnd;
  return switch (billing.status) {
    null => 'No auto-pay set up',
    GatewayStatus.created => 'Waiting for you to authorise auto-pay',
    GatewayStatus.authenticated =>
      'Auto-pay authorised · first charge when your current period ends',
    GatewayStatus.active when billing.cancelAtCycleEnd =>
      end == null
          ? 'Auto-pay ends with this period'
          : 'Auto-pay ends on ${formatDate(end)}',
    GatewayStatus.active =>
      end == null
          ? 'Auto-pay on'
          : 'Auto-pay on · next charge ${formatDate(end)}',
    GatewayStatus.pending => 'A payment failed · Razorpay is retrying',
    GatewayStatus.halted => 'Auto-pay stopped after failed payments',
    GatewayStatus.cancelled => 'Auto-pay cancelled',
    GatewayStatus.completed => 'Auto-pay finished',
    GatewayStatus.expired => 'The auto-pay link expired',
    GatewayStatus.paused => 'Auto-pay paused',
  };
}

/// "Last payment ₹7,999 on 1 Oct 2026", or null without both parts.
String? lastPaymentLine(num? amountInr, DateTime? paidAt) =>
    amountInr == null || paidAt == null
    ? null
    : 'Last payment ${formatInr(amountInr)} on ${formatDate(paidAt)}';
