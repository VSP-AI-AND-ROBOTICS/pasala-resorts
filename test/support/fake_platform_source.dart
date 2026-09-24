import 'package:pasala/data/models/subscription.dart';
import 'package:pasala/data/repositories/platform_repository.dart';

/// The arguments of one [PlatformSource.setSubscription] call.
typedef SubscriptionCall = ({
  String propertyId,
  SubscriptionTier tier,
  SubscriptionStatus status,
  DateTime? trialEndsOn,
  DateTime? paidThrough,
  String? notes,
});

/// The three plans at the spec's placeholder prices.
const defaultPlans = [
  SubscriptionPlan(
    tier: SubscriptionTier.starter,
    name: 'Starter',
    monthlyPriceInr: 2999,
    sortOrder: 1,
  ),
  SubscriptionPlan(
    tier: SubscriptionTier.pro,
    name: 'Pro',
    monthlyPriceInr: 7999,
    sortOrder: 2,
  ),
  SubscriptionPlan(
    tier: SubscriptionTier.enterprise,
    name: 'Enterprise',
    monthlyPriceInr: 19999,
    sortOrder: 3,
  ),
];

/// A plan for tests; the price defaults to [defaultPlans]' price for [tier].
ResortPlan resortPlan({
  SubscriptionTier tier = SubscriptionTier.pro,
  SubscriptionStatus status = SubscriptionStatus.active,
  DateTime? trialEndsOn,
  DateTime? paidThrough,
  bool lapsed = false,
  num? monthlyPriceInr,
  String? notes,
}) => ResortPlan(
  tier: tier,
  name: tier.label,
  status: status,
  trialEndsOn: trialEndsOn,
  paidThrough: paidThrough,
  lapsed: lapsed,
  monthlyPriceInr:
      monthlyPriceInr ??
      defaultPlans.firstWhere((p) => p.tier == tier).monthlyPriceInr,
  notes: notes,
);

/// A resort summary for tests.
ResortSummary resortSummary({
  String propertyId = 'p1',
  String name = 'Resort A',
  String status = 'active',
  List<String> ownerEmails = const ['ownera@x.com'],
  ResortPlan? plan,
  int bookings30d = 0,
  num revenue30d = 0,
}) => ResortSummary(
  propertyId: propertyId,
  name: name,
  status: status,
  ownerEmails: ownerEmails,
  createdAt: DateTime.utc(2024, 1, 1),
  bookings30d: bookings30d,
  revenue30d: revenue30d,
  bookings365d: bookings30d,
  revenue365d: revenue30d,
  plan: plan,
);

/// In-memory [PlatformSource]. Set [store], [totalsValue] and [planList]
/// for what the server would return, an `...Error` to make that call
/// throw, and read the call logs to assert what a screen asked for. Writes
/// also update [store]/[planList], so a refetch shows them.
class FakePlatformSource implements PlatformSource {
  List<ResortSummary> store = [];
  PlatformTotals totalsValue = PlatformTotals.zero;
  List<SubscriptionPlan> planList = defaultPlans;

  Object? resortsError;
  Object? totalsError;
  Object? plansError;
  Object? setStatusError;
  Object? createError;
  Object? subscriptionError;
  Object? priceError;

  int resortsCalls = 0;
  int totalsCalls = 0;
  int plansCalls = 0;
  final List<(String, String)> statusCalls = [];
  final List<(String, String, SubscriptionTier, int)> createCalls = [];
  final List<SubscriptionCall> subscriptionCalls = [];
  final List<(SubscriptionTier, num)> priceCalls = [];
  int _idCounter = 0;

  @override
  Future<List<ResortSummary>> resorts() async {
    resortsCalls++;
    if (resortsError != null) throw resortsError!;
    return List.of(store);
  }

  @override
  Future<PlatformTotals> totals() async {
    totalsCalls++;
    if (totalsError != null) throw totalsError!;
    return totalsValue;
  }

  @override
  Future<List<SubscriptionPlan>> plans() async {
    plansCalls++;
    if (plansError != null) throw plansError!;
    return List.of(planList);
  }

  @override
  Future<void> setStatus(String propertyId, String status) async {
    statusCalls.add((propertyId, status));
    if (setStatusError != null) throw setStatusError!;
    store = [
      for (final r in store)
        r.propertyId == propertyId ? r.copyWith(status: status) : r,
    ];
  }

  @override
  Future<String> createResort(
    String name,
    String ownerEmail, {
    SubscriptionTier tier = SubscriptionTier.starter,
    int trialDays = 30,
  }) async {
    createCalls.add((name, ownerEmail, tier, trialDays));
    if (createError != null) throw createError!;
    final id = 'resort-${_idCounter++}';
    store = [
      ...store,
      resortSummary(
        propertyId: id,
        name: name,
        ownerEmails: [ownerEmail],
        plan: resortPlan(
          tier: tier,
          status: trialDays > 0
              ? SubscriptionStatus.trial
              : SubscriptionStatus.active,
          trialEndsOn: trialDays > 0 ? DateTime(2026, 9, 25 + trialDays) : null,
        ),
      ),
    ];
    return id;
  }

  @override
  Future<void> setSubscription(
    String propertyId, {
    required SubscriptionTier tier,
    required SubscriptionStatus status,
    DateTime? trialEndsOn,
    DateTime? paidThrough,
    String? notes,
  }) async {
    subscriptionCalls.add((
      propertyId: propertyId,
      tier: tier,
      status: status,
      trialEndsOn: trialEndsOn,
      paidThrough: paidThrough,
      notes: notes,
    ));
    if (subscriptionError != null) throw subscriptionError!;
    store = [
      for (final r in store)
        r.propertyId == propertyId
            ? r.copyWith(
                plan: resortPlan(
                  tier: tier,
                  status: status,
                  trialEndsOn: trialEndsOn,
                  paidThrough: paidThrough,
                  notes: notes,
                ),
              )
            : r,
    ];
  }

  @override
  Future<void> setPlanPrice(SubscriptionTier tier, num monthlyPriceInr) async {
    priceCalls.add((tier, monthlyPriceInr));
    if (priceError != null) throw priceError!;
    planList = [
      for (final p in planList)
        p.tier == tier
            ? SubscriptionPlan(
                tier: p.tier,
                name: p.name,
                monthlyPriceInr: monthlyPriceInr,
                sortOrder: p.sortOrder,
              )
            : p,
    ];
  }
}
