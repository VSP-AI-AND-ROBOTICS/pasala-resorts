import 'dart:async';

/// Merges a realtime stream of full snapshots with a periodic fallback poll
/// and an optional external "refresh now" signal (e.g. the app returning to
/// the foreground).
///
/// Realtime websockets are not guaranteed to notice every disconnect. A
/// backgrounded browser tab can throttle the JS timers a websocket client
/// relies on for heartbeats and reconnect backoff, so a dropped connection
/// can in principle go unnoticed for as long as the tab stays hidden. This
/// class keeps the realtime stream as the fast path but guarantees the
/// calendar is refreshed at least once every [interval] and immediately
/// whenever [resumeSignals] fires, so staleness is always bounded even if
/// realtime never recovers on its own.
///
/// Both the realtime stream and [fetch] are expected to produce the *full*
/// current snapshot (not a delta) -- which is exactly what
/// `BookingRepository.watchUnit`/`fetchUnit` do for `unit_calendar_events`.
/// That means whichever value arrives last is always safe to show as-is:
/// there is nothing to merge or reconcile, and the two paths cannot leave
/// the UI in a partially-updated state or fight over conflicting data.
class CalendarRefreshController<T> {
  CalendarRefreshController({
    required Stream<T> realtime,
    required Future<T> Function() fetch,
    Stream<void>? resumeSignals,
    required Duration interval,
  }) : _fetch = fetch {
    _realtimeSub = realtime.listen(_controller.add, onError: _controller.addError);
    _timer = Timer.periodic(interval, (_) => _poll());
    if (resumeSignals != null) {
      _resumeSub = resumeSignals.listen((_) => _poll());
    }
  }

  final Future<T> Function() _fetch;
  final StreamController<T> _controller = StreamController<T>.broadcast();
  late final StreamSubscription<T> _realtimeSub;
  late final Timer _timer;
  StreamSubscription<void>? _resumeSub;

  /// Number of fallback polls issued so far. Exposed for tests; not used by
  /// production code.
  int pollCount = 0;

  bool _disposed = false;

  Stream<T> get stream => _controller.stream;

  Future<void> _poll() async {
    if (_disposed) return;
    pollCount++;
    try {
      final value = await _fetch();
      if (!_disposed && !_controller.isClosed) _controller.add(value);
    } catch (e, st) {
      if (!_disposed && !_controller.isClosed) _controller.addError(e, st);
    }
  }

  /// Cancels the timer and every subscription, and closes the output
  /// stream. Safe to call once; the timer in particular must be cancelled
  /// here or it leaks and keeps polling Postgrest forever.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _timer.cancel();
    await _realtimeSub.cancel();
    await _resumeSub?.cancel();
    await _controller.close();
  }
}
