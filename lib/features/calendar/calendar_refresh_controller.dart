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
/// That means there is never a partial-update to merge or reconcile: every
/// value that reaches [stream] is a complete, self-consistent snapshot, and
/// the two paths can never leave the UI showing a spliced-together mix of
/// old and new data.
///
/// What this does NOT guarantee for free is *temporal* ordering. A poll and
/// a realtime event can both be in flight at once, and network/DB timing
/// gives no promise that the one dispatched first resolves first: a poll
/// that was already in flight when a newer realtime event arrives can
/// resolve afterwards, carrying a snapshot taken before that event. Applying
/// it naively would revert the UI to stale data until the next event or
/// poll. To prevent that, every value (from either path) is stamped with a
/// monotonically increasing sequence number *at dispatch time* (when a poll
/// starts, or when a realtime event arrives), and a value is only applied if
/// its sequence number is the newest one dispatched so far. A poll that
/// resolves late is simply dropped once something newer has already been
/// applied -- the UI only ever moves forward.
class CalendarRefreshController<T> {
  CalendarRefreshController({
    required Stream<T> realtime,
    required Future<T> Function() fetch,
    Stream<void>? resumeSignals,
    required Duration interval,
  }) : _fetch = fetch {
    _realtimeSub = realtime.listen(_onRealtimeEvent, onError: _onRealtimeError);
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

  /// Monotonic counter: every dispatched value (poll or realtime event)
  /// claims the next number, in dispatch order.
  int _dispatchSeq = 0;

  /// The sequence number of the most recently *applied* value. A dispatched
  /// value whose sequence number is older than this has been superseded by
  /// something that already reached [stream] and must be dropped.
  int _appliedSeq = 0;

  Stream<T> get stream => _controller.stream;

  void _onRealtimeEvent(T value) {
    // Realtime events are already-resolved snapshots -- there is no gap
    // between "dispatch" and "arrival" to race against, so this always wins
    // over anything dispatched (but not yet applied) before it.
    final seq = ++_dispatchSeq;
    _apply(seq, value);
  }

  void _onRealtimeError(Object error, StackTrace st) {
    final seq = ++_dispatchSeq;
    _applyError(seq, error, st);
  }

  Future<void> _poll() async {
    if (_disposed) return;
    pollCount++;
    // Claimed before the await, so a realtime event that arrives while this
    // poll is in flight claims a higher sequence number and this poll's
    // eventual result -- however late -- can never overwrite it.
    final seq = ++_dispatchSeq;
    try {
      final value = await _fetch();
      _apply(seq, value);
    } catch (e, st) {
      _applyError(seq, e, st);
    }
  }

  void _apply(int seq, T value) {
    if (_disposed || _controller.isClosed) return;
    if (seq < _appliedSeq) return; // superseded by a newer value; drop it
    _appliedSeq = seq;
    _controller.add(value);
  }

  void _applyError(int seq, Object error, StackTrace st) {
    if (_disposed || _controller.isClosed) return;
    if (seq < _appliedSeq) return; // stale error; a newer value already won
    _appliedSeq = seq;
    _controller.addError(error, st);
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
