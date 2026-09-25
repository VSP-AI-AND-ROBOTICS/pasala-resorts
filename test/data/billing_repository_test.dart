import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:pasala/core/errors.dart';
import 'package:pasala/data/models/billing.dart';
import 'package:pasala/data/models/subscription.dart';
import 'package:pasala/data/repositories/billing_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A repository whose Edge Function calls go to [invoke]. The client is
/// never used by these tests: only the function path is exercised.
BillingRepository _repo(BillingFunctionInvoker invoke) => BillingRepository(
  SupabaseClient(
    'http://localhost:54321',
    'test-anon-key',
    authOptions: const AuthClientOptions(autoRefreshToken: false),
  ),
  invoke: invoke,
);

FunctionException _fx(int status, Object? details) =>
    FunctionException(status: status, details: details);

void main() {
  group('availability (the probe)', () {
    test('configured with plans', () async {
      final calls = <(String, Map<String, dynamic>)>[];
      final repo = _repo((name, body) async {
        calls.add((name, body));
        return {
          'configured': true,
          'plans': [
            {'tier': 'pro', 'name': 'Pro', 'monthly_price_inr': 7999},
          ],
        };
      });
      final a = await repo.availability('p1');
      expect(a.canPay, isTrue);
      expect(a.plans.single.tier, SubscriptionTier.pro);
      expect(calls.single.$1, 'billing-subscribe');
      expect(calls.single.$2, {'action': 'probe', 'property_id': 'p1'});
    });

    test('not configured stays manual', () async {
      final repo = _repo((_, _) async => {'configured': false});
      expect((await repo.availability('p1')).canPay, isFalse);
    });

    test('a function that is not deployed means not configured', () async {
      final repo = _repo((_, _) async => throw _fx(404, 'Not Found'));
      expect(await repo.availability('p1'), same(BillingAvailability.off));
    });

    test('a network failure means not configured, never an error', () async {
      final repo = _repo((_, _) async => throw http.ClientException('offline'));
      expect(await repo.availability('p1'), same(BillingAvailability.off));
    });
  });

  group('subscribe', () {
    test('sends the tier and reads the answer', () async {
      Map<String, dynamic>? sent;
      final repo = _repo((_, body) async {
        sent = body;
        return {
          'configured': true,
          'action': 'created',
          'subscription_id': 'sub_NewSub0000001',
          'short_url': 'https://rzp.io/i/new',
          'status': 'created',
        };
      });
      final r = await repo.subscribe('p1', SubscriptionTier.pro);
      expect(sent, {'action': 'subscribe', 'property_id': 'p1', 'tier': 'pro'});
      expect(r.action, SubscribeAction.created);
      expect(r.shortUrl, 'https://rzp.io/i/new');
    });

    test('P0038 from the database is BillingUnavailable', () async {
      final repo = _repo(
        (_, _) async => throw _fx(409, {
          'error': 'db',
          'code': 'P0038',
          'message': 'billing_unavailable',
        }),
      );
      await expectLater(
        repo.subscribe('p1', SubscriptionTier.enterprise),
        throwsA(isA<BillingUnavailable>()),
      );
    });

    test('P0020 from the database is NotAMember', () async {
      final repo = _repo(
        (_, _) async => throw _fx(409, {
          'error': 'db',
          'code': 'P0020',
          'message': 'not_a_member',
        }),
      );
      await expectLater(
        repo.subscribe('p1', SubscriptionTier.pro),
        throwsA(isA<NotAMember>()),
      );
    });

    test('Razorpay trouble is a readable InvalidState', () async {
      final repo = _repo(
        (_, _) async => throw _fx(502, {
          'error': 'gateway',
          'message': 'The plan id provided does not exist',
        }),
      );
      await expectLater(
        repo.subscribe('p1', SubscriptionTier.pro),
        throwsA(
          isA<InvalidState>().having(
            (e) => e.message,
            'message',
            'Razorpay did not respond. Try again in a minute.',
          ),
        ),
      );
    });

    test('401 is NotPermitted', () async {
      final repo = _repo(
        (_, _) async => throw _fx(401, {
          'error': 'unauthorized',
          'message': 'Sign in first.',
        }),
      );
      await expectLater(
        repo.subscribe('p1', SubscriptionTier.pro),
        throwsA(isA<NotPermitted>()),
      );
    });

    test('keys removed since the probe: BillingUnavailable', () async {
      final repo = _repo((_, _) async => {'configured': false});
      await expectLater(
        repo.subscribe('p1', SubscriptionTier.pro),
        throwsA(isA<BillingUnavailable>()),
      );
    });

    test('offline is a NetworkFailure', () async {
      final repo = _repo((_, _) async => throw http.ClientException('offline'));
      await expectLater(
        repo.subscribe('p1', SubscriptionTier.pro),
        throwsA(isA<NetworkFailure>()),
      );
    });
  });

  test('cancel reads the action', () async {
    Map<String, dynamic>? sent;
    final repo = _repo((_, body) async {
      sent = body;
      return {
        'configured': true,
        'action': 'cancel_scheduled',
        'subscription_id': 'sub_Current000001',
        'status': 'active',
      };
    });
    expect(await repo.cancel('p1'), CancelAction.cancelScheduled);
    expect(sent, {'action': 'cancel', 'property_id': 'p1'});
  });
}
