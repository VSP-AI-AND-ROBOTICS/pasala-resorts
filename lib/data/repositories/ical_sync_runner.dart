import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ical_repository.dart';

/// How [IcalSyncRunner] waits between calls; tests pass one that returns
/// at once.
typedef SyncWait = Future<void> Function(Duration delay);

/// Drives the OTA screen's "Sync now" (spec decision 13).
///
/// `ical_poll_feed` is a two-call state machine (0018): one call fires a
/// fetch, a later call collects it. A response collected by the FIRST call
/// was fetched before the press (by the 15-minute job), so the runner keeps
/// calling every [interval] and returns the first finished result
/// ([IcalSyncResult.isFinal]) from any later call. After [maxCalls] calls
/// without one it returns `IcalSyncResult(status: 'pending')`.
class IcalSyncRunner {
  IcalSyncRunner(
    this.source, {
    SyncWait? wait,
    this.maxCalls = 8,
    this.interval = const Duration(seconds: 2),
  }) : wait = wait ?? ((delay) => Future<void>.delayed(delay));

  final IcalSource source;
  final SyncWait wait;
  final int maxCalls;
  final Duration interval;

  Future<IcalSyncResult> syncNow(String feedId) async {
    // The first call only starts a fresh fetch (and may collect a stale one).
    await source.syncFeed(feedId);
    for (var call = 2; call <= maxCalls; call++) {
      await wait(interval);
      final result = await source.syncFeed(feedId);
      if (result.isFinal) return result;
    }
    return const IcalSyncResult(status: 'pending');
  }
}

final icalSyncRunnerProvider = Provider<IcalSyncRunner>(
  (ref) => IcalSyncRunner(ref.watch(icalSourceProvider)),
);
