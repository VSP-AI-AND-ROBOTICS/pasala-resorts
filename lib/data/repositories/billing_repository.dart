import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors.dart';
import '../../core/supabase_client.dart';
import '../models/billing.dart';
import '../models/subscription.dart';

/// Calls an Edge Function with a JSON body and returns its decoded JSON
/// body. Throws [FunctionException] on a non-2xx answer, as
/// `SupabaseClient.functions.invoke` does.
typedef BillingFunctionInvoker =
    Future<Object?> Function(String name, Map<String, dynamic> body);

/// The Edge Function behind every billing action
/// (supabase/functions/billing-subscribe).
const billingFunctionName = 'billing-subscribe';

/// Auto-pay for one resort's ResortHub plan (P8), for its owner. Tests
/// override [billingSourceProvider] with `FakeBillingSource`
/// (test/support/fake_billing_source.dart).
abstract class BillingSource {
  /// Whether auto-pay can be offered. Never throws: any failure means "not
  /// configured", and the plan stays manual exactly as before.
  Future<BillingAvailability> availability(String propertyId);

  /// Null when the resort never had auto-pay or a payment.
  Future<ResortBilling?> billing(String propertyId);

  /// Newest first, at most 12.
  Future<List<SubscriptionInvoice>> invoices(String propertyId);

  Future<SubscribeResult> subscribe(String propertyId, SubscriptionTier tier);

  Future<CancelAction> cancel(String propertyId);
}

/// Maps a billing-subscribe error body (`{error, code?, message}`) or any
/// other error to a [BookingFailure].
BookingFailure billingFailureFor(Object error) {
  if (error is FunctionException) {
    final details = error.details;
    final body = details is Map ? details : const <String, dynamic>{};
    final code = body['code'];
    return switch (body['error']) {
      'db' when code is String => mapPostgrestError(
        PostgrestException(message: '${body['message'] ?? ''}', code: code),
      ),
      'gateway' => const InvalidState(
        'Razorpay did not respond. Try again in a minute.',
      ),
      _ when error.status == 401 => const NotPermitted(),
      _ => UnknownFailure('billing-subscribe answered ${error.status}'),
    };
  }
  return mapPostgrestError(error);
}

/// Reads `my_resort_billing` and `subscription_invoices`, and drives the
/// billing-subscribe Edge Function (0057_subscription_billing.sql).
class BillingRepository implements BillingSource {
  BillingRepository(this._db, {BillingFunctionInvoker? invoke})
    : _invoke = invoke;

  final SupabaseClient _db;
  final BillingFunctionInvoker? _invoke;

  Future<Object?> _call(Map<String, dynamic> body) async {
    final invoke = _invoke;
    if (invoke != null) return invoke(billingFunctionName, body);
    final response = await _db.functions.invoke(
      billingFunctionName,
      body: body,
    );
    return response.data;
  }

  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } catch (e) {
      throw billingFailureFor(e);
    }
  }

  @override
  Future<BillingAvailability> availability(String propertyId) async {
    try {
      final data = await _call({'action': 'probe', 'property_id': propertyId});
      return data is Map<String, dynamic>
          ? BillingAvailability.fromJson(data)
          : BillingAvailability.off;
    } catch (_) {
      return BillingAvailability.off;
    }
  }

  @override
  Future<ResortBilling?> billing(String propertyId) => _guard(() async {
    final rows =
        await _db.rpc('my_resort_billing', params: {'p_property': propertyId})
            as List<dynamic>;
    return rows.isEmpty
        ? null
        : ResortBilling.fromRow(rows.first as Map<String, dynamic>);
  });

  @override
  Future<List<SubscriptionInvoice>> invoices(String propertyId) =>
      _guard(() async {
        final rows = await _db
            .from('subscription_invoices')
            .select('id, tier, amount_inr, paid_at, period_start, period_end')
            .eq('property_id', propertyId)
            .order('paid_at', ascending: false)
            .limit(12);
        return rows.map(SubscriptionInvoice.fromJson).toList();
      });

  @override
  Future<SubscribeResult> subscribe(String propertyId, SubscriptionTier tier) =>
      _guard(() async {
        final json =
            await _call({
                  'action': 'subscribe',
                  'property_id': propertyId,
                  'tier': subscriptionTierToDb(tier),
                })
                as Map<String, dynamic>;
        if (json['configured'] != true) throw const BillingUnavailable();
        return SubscribeResult.fromJson(json);
      });

  @override
  Future<CancelAction> cancel(String propertyId) => _guard(() async {
    final json =
        await _call({'action': 'cancel', 'property_id': propertyId})
            as Map<String, dynamic>;
    if (json['configured'] != true) throw const BillingUnavailable();
    return cancelActionFromWire(json['action']);
  });
}

final billingRepositoryProvider = Provider<BillingRepository>(
  (ref) => BillingRepository(ref.watch(supabaseProvider)),
);

/// The [BillingSource] seam every screen calls through.
final billingSourceProvider = Provider<BillingSource>(
  (ref) => ref.watch(billingRepositoryProvider),
);

/// Keyed by property id; `autoDispose`, so Settings asks again every time
/// it opens (secrets may have been set since).
final billingAvailabilityProvider = FutureProvider.autoDispose
    .family<BillingAvailability, String>(
      (ref, propertyId) =>
          ref.watch(billingSourceProvider).availability(propertyId),
    );

final resortBillingProvider = FutureProvider.autoDispose
    .family<ResortBilling?, String>(
      (ref, propertyId) => ref.watch(billingSourceProvider).billing(propertyId),
      // Screens show their own Retry button; don't also auto-retry (Riverpod 3
      // retries non-Error throws by default).
      retry: (retryCount, error) => null,
    );

final subscriptionInvoicesProvider = FutureProvider.autoDispose
    .family<List<SubscriptionInvoice>, String>(
      (ref, propertyId) =>
          ref.watch(billingSourceProvider).invoices(propertyId),
      // Screens show their own Retry button; don't also auto-retry (Riverpod 3
      // retries non-Error throws by default).
      retry: (retryCount, error) => null,
    );
