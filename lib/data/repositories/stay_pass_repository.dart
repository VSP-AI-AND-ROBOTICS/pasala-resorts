import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors.dart';
import '../../core/supabase_client.dart';
import '../models/verified_pass.dart';

/// The two calls behind signed check-in passes (0052_stay_pass.sql). The
/// guest screens and reception call through [stayPassSourceProvider];
/// tests override it with `FakeStayPassSource`
/// (test/support/fake_stay_pass_source.dart).
abstract class StayPassSource {
  /// The signed pass for the signed-in guest's own `confirmed` or
  /// `checked_in` booking (`issue_stay_pass`).
  Future<String> issue(String reservationId);

  /// Checks a scanned or typed pass (`verify_stay_pass`). Throws
  /// [StayPassRejected] for an invalid, expired or other-resort pass.
  Future<VerifiedPass> verify(String token);
}

/// Both functions check the caller server-side (the guest's own booking;
/// Staff+ at the pass's resort), so this repository checks nothing itself.
class StayPassRepository implements StayPassSource {
  StayPassRepository(this._db);
  final SupabaseClient _db;

  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } catch (e) {
      throw mapPostgrestError(e);
    }
  }

  @override
  Future<String> issue(String reservationId) => _guard(() async {
    final token = await _db.rpc(
      'issue_stay_pass',
      params: {'p_reservation': reservationId},
    );
    return token as String;
  });

  @override
  Future<VerifiedPass> verify(String token) => _guard(() async {
    final json = await _db.rpc(
      'verify_stay_pass',
      params: {'p_token': token.trim()},
    );
    return VerifiedPass.fromJson(json as Map<String, dynamic>);
  });
}

final stayPassRepositoryProvider = Provider<StayPassRepository>(
  (ref) => StayPassRepository(ref.watch(supabaseProvider)),
);

/// The [StayPassSource] seam every screen calls through.
final stayPassSourceProvider = Provider<StayPassSource>(
  (ref) => ref.watch(stayPassRepositoryProvider),
);

/// The guest's pass for one booking, keyed by reservation id. Not
/// `autoDispose`: a booking's pass never changes (it is signed over the
/// booking's ids and the end of the stay), so it is fetched once per app
/// session and survives the guest moving between screens.
final stayPassProvider = FutureProvider.family<String, String>(
  (ref, reservationId) =>
      ref.watch(stayPassSourceProvider).issue(reservationId),
  // Screens show their own Retry button; don't also auto-retry (Riverpod 3
  // retries non-Error throws by default).
  retry: (retryCount, error) => null,
);
