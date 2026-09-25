import 'dart:async';

import 'package:pasala/data/models/billing.dart';
import 'package:pasala/data/models/subscription.dart';
import 'package:pasala/data/repositories/billing_repository.dart';

import 'fake_platform_source.dart';

/// Auto-pay offered on Starter and Pro at the placeholder prices.
final billablePlans = BillingAvailability(
  configured: true,
  plans: [defaultPlans[0], defaultPlans[1]],
);

/// A billing row for tests: Pro auto-pay on, charged 1 Oct 2026, next
/// charge 1 Nov 2026.
ResortBilling resortBilling({
  GatewayStatus? status = GatewayStatus.active,
  SubscriptionTier? tier = SubscriptionTier.pro,
  bool cancelAtCycleEnd = false,
  DateTime? currentEnd,
  DateTime? lastPaymentAt,
  num? lastPaymentInr = 7999,
}) => ResortBilling(
  status: status,
  tier: tier,
  shortUrl: 'https://rzp.io/i/current',
  cancelAtCycleEnd: cancelAtCycleEnd,
  currentEnd: currentEnd ?? DateTime(2026, 11, 1),
  lastPaymentAt: lastPaymentAt ?? DateTime(2026, 10, 1),
  lastPaymentInr: lastPaymentInr,
);

SubscriptionInvoice subscriptionInvoice({
  String id = 'i1',
  SubscriptionTier tier = SubscriptionTier.pro,
  num amountInr = 7999,
  DateTime? paidAt,
}) => SubscriptionInvoice(
  id: id,
  tier: tier,
  amountInr: amountInr,
  paidAt: paidAt ?? DateTime(2026, 10, 1),
);

/// In-memory [BillingSource]. Set the `...Value`/`...Result` fields for what
/// the server would answer, an `...Error` to make that call throw, and
/// [hold] to keep `subscribe` in flight until it completes. The call logs
/// record every property id (and tier) asked for.
class FakeBillingSource implements BillingSource {
  BillingAvailability availabilityValue = BillingAvailability.off;
  ResortBilling? billingValue;
  List<SubscriptionInvoice> invoiceList = [];
  SubscribeResult subscribeResult = const SubscribeResult(
    action: SubscribeAction.created,
    subscriptionId: 'sub_TestSub000001',
    shortUrl: 'https://rzp.io/i/test',
    status: GatewayStatus.created,
  );
  CancelAction cancelResult = CancelAction.cancelScheduled;

  Object? billingError;
  Object? invoicesError;
  Object? subscribeError;
  Object? cancelError;
  Completer<void>? hold;

  final List<String> availabilityCalls = [];
  final List<String> billingCalls = [];
  final List<String> invoiceCalls = [];
  final List<(String, SubscriptionTier)> subscribeCalls = [];
  final List<String> cancelCalls = [];

  @override
  Future<BillingAvailability> availability(String propertyId) async {
    availabilityCalls.add(propertyId);
    return availabilityValue;
  }

  @override
  Future<ResortBilling?> billing(String propertyId) async {
    billingCalls.add(propertyId);
    if (billingError != null) throw billingError!;
    return billingValue;
  }

  @override
  Future<List<SubscriptionInvoice>> invoices(String propertyId) async {
    invoiceCalls.add(propertyId);
    if (invoicesError != null) throw invoicesError!;
    return List.of(invoiceList);
  }

  @override
  Future<SubscribeResult> subscribe(
    String propertyId,
    SubscriptionTier tier,
  ) async {
    subscribeCalls.add((propertyId, tier));
    await hold?.future;
    if (subscribeError != null) throw subscribeError!;
    return subscribeResult;
  }

  @override
  Future<CancelAction> cancel(String propertyId) async {
    cancelCalls.add(propertyId);
    if (cancelError != null) throw cancelError!;
    return cancelResult;
  }
}
