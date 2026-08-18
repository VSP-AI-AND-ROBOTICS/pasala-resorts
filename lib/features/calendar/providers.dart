import 'dart:async';

import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/reservation.dart';
import '../../data/repositories/booking_repository.dart';
import 'calendar_refresh_controller.dart';

/// How often the calendar force-refreshes from Postgrest as a fallback to
/// the realtime stream, in case that stream has silently stalled (see
/// [CalendarRefreshController]).
///
/// This calendar is customer-facing (embedded in the booking flow on the
/// property page, reached from every
/// property's booking flow), not a low-traffic staff tool -- so the
/// interval has to be judged against what it actually gates: the window
/// during which a customer can see a date as free after someone else has
/// already taken it. Concretely, up to [calendarRefreshInterval] can pass
/// between a competing hold/booking landing and this calendar reflecting
/// it, during which a customer could pick that date, only to have
/// `create_hold` reject it with a `23P01` exclusion-constraint violation.
/// That failure path has been verified end-to-end: `mapPostgrestError`
/// turns `23P01` into [UnitUnavailable], and `BookingScreen._handleFailure`
/// shows its message and calls `ref.invalidate(unitReservationsProvider)`
/// to force an immediate re-fetch, so the customer sees a clear "someone
/// else took this" message and a corrected calendar rather than a confusing
/// error or a silently-stale grid. Given that backstop, this interval only
/// has to bound *how often* that (already-handled) collision happens, not
/// prevent it -- the database's exclusion constraint is what actually
/// prevents a double-booking.
///
/// 30 seconds is chosen over the alternatives as follows:
///  * 10s would cut the collision window three-fold, but triples the
///    steady-state Postgrest polling load of every open calendar for a
///    fallback path that, per the realtime pipeline proof in
///    `realtime-debug-report.md`, fires rarely -- realtime alone already
///    delivers changes in under two seconds in every measured run, so the
///    fallback's job is to bound the *rare tail* (a stalled/backgrounded
///    websocket), not to be the primary latency budget. Shrinking it mainly
///    buys margin on an already-rare case, at a 3x cost in baseline load.
///  * 60s would halve that load again, but doubles how long a customer can
///    be shown a date as available after it was actually taken -- pushing
///    the failed-hold recovery path (correct, but still an interruption)
///    from "occasionally seen if you click at the wrong moment" towards
///    "routinely seen by anyone slow to act on a stale screen."
///  * 30s is the point where the collision window stays short relative to
///    typical human deliberation time on a date picker (seconds, not under
///    one), while the polling cost stays low enough to add for every open
///    calendar without a second thought. When the collision does happen,
///    it is fully recoverable in one round trip (see above) -- and a manual
///    reload always gives correct data immediately for anyone who wants it
///    sooner than that.
const calendarRefreshInterval = Duration(seconds: 30);

/// [UnitCalendarSource] is a thin seam around [bookingRepositoryProvider]:
/// [unitReservationsProvider] only ever calls `watchUnit`/`fetchUnit`, so
/// tests can override just this provider with a fake that never touches
/// Supabase, instead of needing a real `SupabaseClient` to construct a fake
/// [BookingRepository]. See `test/features/calendar/providers_test.dart`.
final unitCalendarSourceProvider = Provider<UnitCalendarSource>(
  (ref) => ref.watch(bookingRepositoryProvider),
);

/// Riverpod seam around [calendarRefreshInterval]: production code always
/// resolves this to the real 30-second constant, but it lets
/// `test/features/calendar/providers_test.dart` shrink the fallback
/// interval to a few milliseconds so lifecycle tests over
/// [unitReservationsProvider] don't have to wait out 30 real seconds per
/// assertion.
final calendarRefreshIntervalProvider = Provider<Duration>(
  (ref) => calendarRefreshInterval,
);

/// Live reservations for one unit. An admin block or a competing booking
/// updates every open calendar without a refresh via realtime, backed by a
/// periodic poll and a refresh-on-foreground so the calendar cannot stay
/// stale indefinitely even if the realtime websocket drops silently (e.g.
/// while the tab is backgrounded) and never reconnects on its own.
///
/// `autoDispose` matters here: it is what guarantees the fallback timer
/// and the app-lifecycle listener are torn down when the calendar is no
/// longer on screen, instead of polling forever in the background.
final unitReservationsProvider = StreamProvider.autoDispose
    .family<List<Reservation>, String>((ref, unitId) {
  final repo = ref.watch(unitCalendarSourceProvider);

  final resumeController = StreamController<void>.broadcast();
  final lifecycleListener = AppLifecycleListener(
    onResume: () => resumeController.add(null),
  );

  final refresher = CalendarRefreshController<List<Reservation>>(
    realtime: repo.watchUnit(unitId),
    fetch: () => repo.fetchUnit(unitId),
    resumeSignals: resumeController.stream,
    interval: ref.watch(calendarRefreshIntervalProvider),
  );

  ref.onDispose(() {
    lifecycleListener.dispose();
    unawaited(resumeController.close());
    unawaited(refresher.dispose());
  });

  return refresher.stream;
});
