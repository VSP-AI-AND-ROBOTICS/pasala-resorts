import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors.dart';
import '../../core/supabase_client.dart';
import '../models/billing.dart';
import '../models/subscription.dart';

/// One row of `platform_resorts()` -- a resort summary for the platform
/// console. No guest data: owner emails, booking counts/revenue for the
/// last 30 and 365 days, and the resort's subscription (see the tenancy
/// and subscriptions design specs).
class ResortSummary {
  const ResortSummary({
    required this.propertyId,
    required this.name,
    required this.status,
    required this.ownerEmails,
    required this.createdAt,
    required this.bookings30d,
    required this.revenue30d,
    required this.bookings365d,
    required this.revenue365d,
    this.plan,
  });

  final String propertyId;
  final String name;

  /// `active`, `suspended` or `archived` -- `properties.status`, the only
  /// thing that locks a resort. The subscription never does.
  final String status;
  final List<String> ownerEmails;
  final DateTime createdAt;
  final int bookings30d;
  final num revenue30d;
  final int bookings365d;
  final num revenue365d;

  /// The resort's subscription, or null when it has none ("No plan").
  final ResortPlan? plan;

  factory ResortSummary.fromJson(Map<String, dynamic> json) => ResortSummary(
    propertyId: json['property_id'] as String,
    name: json['name'] as String,
    status: json['status'] as String,
    ownerEmails: (json['owner_emails'] as List<dynamic>? ?? []).cast<String>(),
    createdAt: DateTime.parse(json['created_at'] as String).toUtc(),
    bookings30d: (json['bookings_30d'] as num?)?.toInt() ?? 0,
    revenue30d: (json['revenue_30d'] as num?) ?? 0,
    bookings365d: (json['bookings_365d'] as num?)?.toInt() ?? 0,
    revenue365d: (json['revenue_365d'] as num?) ?? 0,
    plan: ResortPlan.fromRow(json),
  );

  ResortSummary copyWith({String? status, ResortPlan? plan}) => ResortSummary(
    propertyId: propertyId,
    name: name,
    status: status ?? this.status,
    ownerEmails: ownerEmails,
    createdAt: createdAt,
    bookings30d: bookings30d,
    revenue30d: revenue30d,
    bookings365d: bookings365d,
    revenue365d: revenue365d,
    plan: plan ?? this.plan,
  );
}

/// The slice of [PlatformRepository] the platform console needs. Extracted
/// as its own interface, mirroring [IcalSource]/`OutboxSource`, so tests
/// can override it with `FakePlatformSource`
/// (test/support/fake_platform_source.dart) instead of a real
/// [SupabaseClient].
abstract class PlatformSource {
  Future<List<ResortSummary>> resorts();

  /// The console's count cards: `platform_summary()`.
  Future<PlatformTotals> totals();

  /// The plans and their monthly prices, cheapest first.
  Future<List<SubscriptionPlan>> plans();

  Future<void> setStatus(String propertyId, String status);

  /// Creates the resort and its subscription: a trial of [trialDays] days
  /// on [tier], or active with no end date when [trialDays] is 0.
  Future<String> createResort(
    String name,
    String ownerEmail, {
    SubscriptionTier tier = SubscriptionTier.starter,
    int trialDays = 30,
  });

  /// Sets (or first creates) the resort's subscription. The server keeps
  /// only the date [status] needs: [trialEndsOn] for a trial,
  /// [paidThrough] otherwise.
  Future<void> setSubscription(
    String propertyId, {
    required SubscriptionTier tier,
    required SubscriptionStatus status,
    DateTime? trialEndsOn,
    DateTime? paidThrough,
    String? notes,
  });

  Future<void> setPlanPrice(SubscriptionTier tier, num monthlyPriceInr);

  /// Auto-pay state and last payment per resort (`platform_billing()`),
  /// only for resorts that ever had auto-pay or a payment (P8).
  Future<List<PlatformBilling>> billing();

  /// Sets or clears (null) the Razorpay plan behind [tier]
  /// (`set_plan_razorpay_id`).
  Future<void> setRazorpayPlanId(SubscriptionTier tier, String? planId);
}

/// Drives the platform-admin-only functions of 0045_resort_functions.sql
/// and 0049_subscriptions.sql. The platform admin gets no row access to
/// any resort-owned table, so every call here goes through a `security
/// definer` function; the one direct read is `subscription_plans`, which
/// every signed-in user may read.
class PlatformRepository implements PlatformSource {
  PlatformRepository(this._db);
  final SupabaseClient _db;

  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } catch (e) {
      throw mapPostgrestError(e);
    }
  }

  @override
  Future<List<ResortSummary>> resorts() => _guard(() async {
    final rows = await _db.rpc('platform_resorts') as List<dynamic>;
    return rows
        .map((e) => ResortSummary.fromJson(e as Map<String, dynamic>))
        .toList();
  });

  @override
  Future<PlatformTotals> totals() => _guard(() async {
    final rows = await _db.rpc('platform_summary') as List<dynamic>;
    return rows.isEmpty
        ? PlatformTotals.zero
        : PlatformTotals.fromJson(rows.first as Map<String, dynamic>);
  });

  @override
  Future<List<SubscriptionPlan>> plans() => _guard(() async {
    final rows = await _db
        .from('subscription_plans')
        .select('tier, name, monthly_price_inr, sort_order, razorpay_plan_id')
        .order('sort_order');
    return rows.map(SubscriptionPlan.fromJson).toList();
  });

  @override
  Future<void> setStatus(String propertyId, String status) => _guard(() async {
    await _db.rpc(
      'set_resort_status',
      params: {'p_property': propertyId, 'p_status': status},
    );
  });

  @override
  Future<String> createResort(
    String name,
    String ownerEmail, {
    SubscriptionTier tier = SubscriptionTier.starter,
    int trialDays = 30,
  }) => _guard(() async {
    final id = await _db.rpc(
      'create_resort',
      params: {
        'p_name': name,
        'p_owner_email': ownerEmail,
        'p_tier': subscriptionTierToDb(tier),
        'p_trial_days': trialDays,
      },
    );
    return id as String;
  });

  @override
  Future<void> setSubscription(
    String propertyId, {
    required SubscriptionTier tier,
    required SubscriptionStatus status,
    DateTime? trialEndsOn,
    DateTime? paidThrough,
    String? notes,
  }) => _guard(() async {
    await _db.rpc(
      'set_resort_subscription',
      params: {
        'p_property': propertyId,
        'p_tier': subscriptionTierToDb(tier),
        'p_status': subscriptionStatusToDb(status),
        'p_trial_ends_on': trialEndsOn == null ? null : dateToDb(trialEndsOn),
        'p_paid_through': paidThrough == null ? null : dateToDb(paidThrough),
        'p_notes': notes,
      },
    );
  });

  @override
  Future<void> setPlanPrice(SubscriptionTier tier, num monthlyPriceInr) =>
      _guard(() async {
        await _db.rpc(
          'set_plan_price',
          params: {
            'p_tier': subscriptionTierToDb(tier),
            'p_monthly_price_inr': monthlyPriceInr,
          },
        );
      });

  @override
  Future<List<PlatformBilling>> billing() => _guard(() async {
    final rows = await _db.rpc('platform_billing') as List<dynamic>;
    return rows
        .map((e) => PlatformBilling.fromRow(e as Map<String, dynamic>))
        .toList();
  });

  @override
  Future<void> setRazorpayPlanId(SubscriptionTier tier, String? planId) =>
      _guard(() async {
        await _db.rpc(
          'set_plan_razorpay_id',
          params: {
            'p_tier': subscriptionTierToDb(tier),
            'p_plan_id': planId ?? '',
          },
        );
      });
}

final platformRepositoryProvider = Provider<PlatformRepository>(
  (ref) => PlatformRepository(ref.watch(supabaseProvider)),
);

/// [PlatformSource] seam around [platformRepositoryProvider], mirroring
/// `icalSourceProvider`: the console only ever calls this, so tests can
/// override just this provider with a fake.
final platformSourceProvider = Provider<PlatformSource>(
  (ref) => ref.watch(platformRepositoryProvider),
);

final platformResortsProvider = FutureProvider<List<ResortSummary>>(
  (ref) => ref.watch(platformSourceProvider).resorts(),
  // Screens show their own Retry button; don't also auto-retry (Riverpod 3
  // retries non-Error throws by default).
  retry: (retryCount, error) => null,
);

/// Platform-wide: the cards do not follow the console's search or filter.
final platformTotalsProvider = FutureProvider<PlatformTotals>(
  (ref) => ref.watch(platformSourceProvider).totals(),
  // Screens show their own Retry button; don't also auto-retry (Riverpod 3
  // retries non-Error throws by default).
  retry: (retryCount, error) => null,
);

final subscriptionPlansProvider = FutureProvider<List<SubscriptionPlan>>(
  (ref) => ref.watch(platformSourceProvider).plans(),
);

/// Billing per resort, keyed by property id. A resort without an entry
/// never had auto-pay.
final platformBillingProvider = FutureProvider<Map<String, PlatformBilling>>(
  (ref) async => {
    for (final b in await ref.watch(platformSourceProvider).billing())
      b.propertyId: b,
  },
  // Screens show their own Retry button; don't also auto-retry (Riverpod 3
  // retries non-Error throws by default).
  retry: (retryCount, error) => null,
);
