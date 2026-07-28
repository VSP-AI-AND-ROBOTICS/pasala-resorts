import 'dart:async';

import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/reservation.dart';
import '../../data/repositories/booking_repository.dart';
import 'calendar_refresh_controller.dart';

/// How often the calendar force-refreshes from Postgrest as a fallback to
/// the realtime stream, in case that stream has silently stalled (see
/// [CalendarRefreshController]). 30 seconds keeps worst-case staleness low
/// without meaningfully loading Postgrest -- calendars are viewed by a
/// handful of staff/customers at a time, not polled at scale -- and a
/// manual reload already gives correct data immediately for anyone who
/// needs fresher data sooner.
const calendarRefreshInterval = Duration(seconds: 30);

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
  final repo = ref.watch(bookingRepositoryProvider);

  final resumeController = StreamController<void>.broadcast();
  final lifecycleListener = AppLifecycleListener(
    onResume: () => resumeController.add(null),
  );

  final refresher = CalendarRefreshController<List<Reservation>>(
    realtime: repo.watchUnit(unitId),
    fetch: () => repo.fetchUnit(unitId),
    resumeSignals: resumeController.stream,
    interval: calendarRefreshInterval,
  );

  ref.onDispose(() {
    lifecycleListener.dispose();
    unawaited(resumeController.close());
    unawaited(refresher.dispose());
  });

  return refresher.stream;
});
