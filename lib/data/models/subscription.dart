import '../../core/format.dart';

/// A resort's plan tier (`public.subscription_tier`,
/// 0049_subscriptions.sql). A label with a monthly price only: it gates
/// no feature yet (spec decision 2).
enum SubscriptionTier { starter, pro, enterprise }

/// Unknown text is rejected rather than defaulted -- a silent fallback
/// would hide a server/app mismatch.
SubscriptionTier subscriptionTierFromDb(String raw) => switch (raw) {
  'starter' => SubscriptionTier.starter,
  'pro' => SubscriptionTier.pro,
  'enterprise' => SubscriptionTier.enterprise,
  _ => throw ArgumentError('Unknown subscription tier: $raw'),
};

/// Inverse of [subscriptionTierFromDb] -- the Postgres enum label.
String subscriptionTierToDb(SubscriptionTier tier) => switch (tier) {
  SubscriptionTier.starter => 'starter',
  SubscriptionTier.pro => 'pro',
  SubscriptionTier.enterprise => 'enterprise',
};

extension SubscriptionTierLabel on SubscriptionTier {
  String get label => switch (this) {
    SubscriptionTier.starter => 'Starter',
    SubscriptionTier.pro => 'Pro',
    SubscriptionTier.enterprise => 'Enterprise',
  };
}

/// What the platform admin set (`public.subscription_status`). "Lapsed" is
/// never stored: the server works it out on every read
/// ([ResortPlan.lapsed]).
enum SubscriptionStatus { trial, active, cancelled }

SubscriptionStatus subscriptionStatusFromDb(String raw) => switch (raw) {
  'trial' => SubscriptionStatus.trial,
  'active' => SubscriptionStatus.active,
  'cancelled' => SubscriptionStatus.cancelled,
  _ => throw ArgumentError('Unknown subscription status: $raw'),
};

String subscriptionStatusToDb(SubscriptionStatus status) => switch (status) {
  SubscriptionStatus.trial => 'trial',
  SubscriptionStatus.active => 'active',
  SubscriptionStatus.cancelled => 'cancelled',
};

extension SubscriptionStatusLabel on SubscriptionStatus {
  String get label => switch (this) {
    SubscriptionStatus.trial => 'Trial',
    SubscriptionStatus.active => 'Active',
    SubscriptionStatus.cancelled => 'Cancelled',
  };
}

/// `yyyy-MM-dd` for a Postgres `date` parameter: only the calendar day of
/// [d] is sent, whatever its time or zone.
String dateToDb(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// A Postgres `date` as a local, time-less [DateTime].
DateTime? _dateFromDb(Object? raw) {
  if (raw == null) return null;
  final parsed = DateTime.parse(raw as String);
  return DateTime(parsed.year, parsed.month, parsed.day);
}

/// PostgREST sends `numeric` as a JSON number; accept text too, so a
/// change of serialisation never turns a price into a crash.
num? _numFromDb(Object? raw) => switch (raw) {
  null => null,
  num n => n,
  String s => num.parse(s),
  _ => throw ArgumentError('Not a number: $raw'),
};

/// One row of `subscription_plans`.
class SubscriptionPlan {
  const SubscriptionPlan({
    required this.tier,
    required this.name,
    required this.monthlyPriceInr,
    required this.sortOrder,
  });

  factory SubscriptionPlan.fromJson(Map<String, dynamic> json) =>
      SubscriptionPlan(
        tier: subscriptionTierFromDb(json['tier'] as String),
        name: json['name'] as String,
        monthlyPriceInr: _numFromDb(json['monthly_price_inr']) ?? 0,
        sortOrder: (json['sort_order'] as num).toInt(),
      );

  final SubscriptionTier tier;
  final String name;
  final num monthlyPriceInr;
  final int sortOrder;
}

/// The row `platform_summary()` returns: the console's three cards.
class PlatformTotals {
  const PlatformTotals({
    required this.subscribed,
    required this.active,
    required this.trials,
    required this.mrrInr,
  });

  factory PlatformTotals.fromJson(Map<String, dynamic> json) => PlatformTotals(
    subscribed: (json['subscribed_count'] as num).toInt(),
    active: (json['active_count'] as num).toInt(),
    trials: (json['trial_count'] as num).toInt(),
    mrrInr: _numFromDb(json['mrr_inr']) ?? 0,
  );

  static const zero = PlatformTotals(
    subscribed: 0,
    active: 0,
    trials: 0,
    mrrInr: 0,
  );

  /// Not archived, and not cancelled.
  final int subscribed;

  /// Subscribed, and paid up or in a trial, with no lapse.
  final int active;

  /// Live (not lapsed) trials, included in [active].
  final int trials;

  /// The monthly price of every paid-up subscription, trials excluded.
  final num mrrInr;
}

/// A resort's subscription: the plan columns of `platform_resorts()` and
/// `my_resort_subscription()`, which share their names.
class ResortPlan {
  const ResortPlan({
    required this.tier,
    required this.name,
    required this.status,
    this.trialEndsOn,
    this.paidThrough,
    this.lapsed = false,
    required this.monthlyPriceInr,
    this.notes,
  });

  /// Null when the row carries no plan (`plan_tier` is null): the resort
  /// has no subscription row, shown as "No plan".
  static ResortPlan? fromRow(Map<String, dynamic> json) {
    final rawTier = json['plan_tier'] as String?;
    if (rawTier == null) return null;
    final tier = subscriptionTierFromDb(rawTier);
    return ResortPlan(
      tier: tier,
      name: json['plan_name'] as String? ?? tier.label,
      status: subscriptionStatusFromDb(json['plan_status'] as String),
      trialEndsOn: _dateFromDb(json['trial_ends_on']),
      paidThrough: _dateFromDb(json['paid_through']),
      lapsed: json['lapsed'] as bool? ?? false,
      monthlyPriceInr: _numFromDb(json['monthly_price_inr']) ?? 0,
      notes: json['plan_notes'] as String?,
    );
  }

  final SubscriptionTier tier;
  final String name;
  final SubscriptionStatus status;

  /// Set for a trial: the last day it runs.
  final DateTime? trialEndsOn;

  /// The last day paid for; null means no end date.
  final DateTime? paidThrough;

  /// Worked out by the server (Asia/Kolkata "today"): a trial or a paid
  /// plan whose last day has passed.
  final bool lapsed;
  final num monthlyPriceInr;
  final String? notes;
}

/// One line describing [plan]'s state, shared by the platform console and
/// the owner's Settings. "Lapsed" is always spelled out, so the state never
/// depends on colour alone.
String planStatusLine(ResortPlan plan) {
  switch (plan.status) {
    case SubscriptionStatus.cancelled:
      return 'Cancelled';
    case SubscriptionStatus.trial:
      final end = plan.trialEndsOn;
      if (end == null) return 'Trial';
      return plan.lapsed
          ? 'Lapsed: trial ended ${formatDate(end)}'
          : 'Trial until ${formatDate(end)}';
    case SubscriptionStatus.active:
      final paid = plan.paidThrough;
      if (paid == null) return 'Paid, no end date';
      return plan.lapsed
          ? 'Lapsed: paid until ${formatDate(paid)}'
          : 'Paid until ${formatDate(paid)}';
  }
}
