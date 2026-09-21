import 'package:flutter/foundation.dart';
import 'resort.dart';

enum SubscriptionStatus {
  pendingPayment,
  active,
  trial,
  expired,
  cancelled,
  suspended;

  String get dbValue {
    switch (this) {
      case SubscriptionStatus.pendingPayment:
        return 'pending_payment';
      case SubscriptionStatus.active:
        return 'active';
      case SubscriptionStatus.trial:
        return 'trial';
      case SubscriptionStatus.expired:
        return 'expired';
      case SubscriptionStatus.cancelled:
        return 'cancelled';
      case SubscriptionStatus.suspended:
        return 'suspended';
    }
  }

  static SubscriptionStatus fromString(String str) {
    switch (str.toLowerCase()) {
      case 'pending_payment':
        return SubscriptionStatus.pendingPayment;
      case 'active':
        return SubscriptionStatus.active;
      case 'trial':
        return SubscriptionStatus.trial;
      case 'expired':
        return SubscriptionStatus.expired;
      case 'cancelled':
        return SubscriptionStatus.cancelled;
      case 'suspended':
        return SubscriptionStatus.suspended;
      default:
        return SubscriptionStatus.active;
    }
  }

  String get displayName {
    switch (this) {
      case SubscriptionStatus.pendingPayment:
        return 'Pending Payment';
      case SubscriptionStatus.active:
        return 'Active';
      case SubscriptionStatus.trial:
        return 'Trial';
      case SubscriptionStatus.expired:
        return 'Expired';
      case SubscriptionStatus.cancelled:
        return 'Cancelled';
      case SubscriptionStatus.suspended:
        return 'Suspended';
    }
  }
}

@immutable
class SubscriptionPlan {
  final String id;
  final SubscriptionTier tier;
  final String name;
  final double priceMonthly;
  final List<String> features;

  const SubscriptionPlan({
    required this.id,
    required this.tier,
    required this.name,
    required this.priceMonthly,
    required this.features,
  });

  factory SubscriptionPlan.fromJson(Map<String, dynamic> json) {
    return SubscriptionPlan(
      id: json['id'] as String,
      tier: SubscriptionTier.fromString(json['tier'] as String),
      name: json['name'] as String,
      priceMonthly: (json['price_monthly'] as num).toDouble(),
      features: (json['features'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'tier': tier.dbValue,
      'name': name,
      'price_monthly': priceMonthly,
      'features': features,
    };
  }
}

@immutable
class ResortSubscription {
  final String id;
  final String resortId;
  final String planId;
  final SubscriptionTier tier;
  final SubscriptionStatus status;
  final DateTime currentPeriodStart;
  final DateTime currentPeriodEnd;
  final bool cancelAtPeriodEnd;

  const ResortSubscription({
    required this.id,
    required this.resortId,
    required this.planId,
    required this.tier,
    required this.status,
    required this.currentPeriodStart,
    required this.currentPeriodEnd,
    required this.cancelAtPeriodEnd,
  });

  factory ResortSubscription.fromJson(Map<String, dynamic> json) {
    return ResortSubscription(
      id: json['id'] as String,
      resortId: json['resort_id'] as String,
      planId: json['plan_id'] as String,
      tier: SubscriptionTier.fromString(json['tier'] as String),
      status: SubscriptionStatus.fromString(json['status'] as String),
      currentPeriodStart: DateTime.parse(json['current_period_start'] as String),
      currentPeriodEnd: DateTime.parse(json['current_period_end'] as String),
      cancelAtPeriodEnd: json['cancel_at_period_end'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'resort_id': resortId,
      'plan_id': planId,
      'tier': tier.dbValue,
      'status': status.dbValue,
      'current_period_start': currentPeriodStart.toIso8601String(),
      'current_period_end': currentPeriodEnd.toIso8601String(),
      'cancel_at_period_end': cancelAtPeriodEnd,
    };
  }
}
