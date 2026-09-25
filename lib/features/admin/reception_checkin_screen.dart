import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/current_resort.dart';
import '../../core/errors.dart';
import '../../core/format.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/failure_view.dart';
import '../../data/models/room_status.dart';
import '../../data/models/verified_pass.dart';
import '../../data/repositories/room_status_repository.dart';
import '../../data/repositories/stay_pass_repository.dart';
import '../../data/repositories/stay_repository.dart';
import '../staff/providers.dart' show allBookingsProvider;
import 'admin_bookings_screen.dart' show bookingCode, bookingMatchesSearch;
import 'pass_check_in_sheet.dart';

/// The warning reception sees on a booking whose room is not ready. A
/// warning only: check-in is never blocked on room state (room status
/// spec, decision 10). Null when the room is ready or its state is
/// unknown.
String? roomWarningFor(RoomBoardEntry? room) => switch (room?.state) {
      RoomState.dirty => 'Room not cleaned yet',
      RoomState.outOfOrder => 'Maintenance: ${room?.reason ?? 'out of order'}',
      _ => null,
    };

/// `/admin/check-in` -- every `confirmed` booking, one-tap Check In.
/// Reception finds a guest by scrolling, by typing a booking code, name
/// or phone into the search (which filters the list), or by the guest's
/// signed check-in pass (P3): "Scan pass" opens the camera at
/// `/admin/check-in/scan`, and a pass typed or pasted into the search --
/// which is also what a keyboard-wedge barcode scanner does -- opens on
/// Enter. A verified pass opens [PassCheckInSheet] for that booking.
/// A booking whose room still needs cleaning or is in maintenance carries
/// a warning chip (see [roomWarningFor]).
class ReceptionCheckinScreen extends ConsumerStatefulWidget {
  const ReceptionCheckinScreen({super.key});

  @override
  ConsumerState<ReceptionCheckinScreen> createState() =>
      _ReceptionCheckinScreenState();
}

class _ReceptionCheckinScreenState
    extends ConsumerState<ReceptionCheckinScreen> {
  final _search = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _checkIn(String id, String propertyId) async {
    try {
      await ref.read(stayRepositoryProvider).checkIn(id);
      ref.invalidate(todaysArrivalsProvider(propertyId));
      ref.invalidate(checkedInProvider(propertyId));
      // The admin dashboard's Farmhouse Status / Today's Focus cards read
      // from this same list -- without invalidating it here, a fresh
      // check-in never shows as OCCUPIED until something else happens to
      // refetch it.
      ref.invalidate(allBookingsProvider);
      // The room is Occupied now.
      ref.invalidate(roomBoardProvider(propertyId));
      _toast('Checked in');
    } on BookingFailure catch (e) {
      _toast(FailureView.messageFor(e));
    }
  }

  Future<void> _scan() async {
    final code = await context.push<String>('/admin/check-in/scan');
    if (!mounted || code == null) return;
    await _openPass(code);
  }

  /// Verifies [raw] and, for a genuine pass at this resort, opens its
  /// check-in sheet.
  Future<void> _openPass(String raw) async {
    if (_busy) return;
    final propertyId = ref.read(currentResortProvider)!.propertyId;
    setState(() => _busy = true);
    try {
      final VerifiedPass pass;
      try {
        pass = await ref.read(stayPassSourceProvider).verify(raw.trim());
      } on BookingFailure catch (e) {
        _toast(FailureView.messageFor(e));
        return;
      } finally {
        // A pass in the search box has done its job either way.
        if (mounted && looksLikeStayPass(_search.text)) _search.clear();
      }
      // Someone who works at two resorts passes the server's check for
      // either; this desk checks guests in at the current resort only.
      if (pass.propertyId != propertyId) {
        _toast(const StayPassRejected.otherResort().message);
        return;
      }
      if (!mounted) return;
      final rooms = ref.read(roomBoardProvider(propertyId)).value ??
          const <RoomBoardEntry>[];
      final room = {for (final r in rooms) r.unitId: r}[pass.reservation.unitId];
      final checkIn = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) =>
            PassCheckInSheet(pass: pass, roomWarning: roomWarningFor(room)),
      );
      if (checkIn == true) await _checkIn(pass.reservation.id, propertyId);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final propertyId = ref.watch(currentResortProvider)!.propertyId;
    final arrivalsAsync = ref.watch(todaysArrivalsProvider(propertyId));
    // The board only adds warnings: while it loads, or if it fails, the
    // list shows without them and check-in works as before.
    final rooms = ref.watch(roomBoardProvider(propertyId)).value ??
        const <RoomBoardEntry>[];
    final roomByUnit = {for (final r in rooms) r.unitId: r};
    final query = _search.text;
    final typingPass = looksLikeStayPass(query);

    return Scaffold(
      appBar: AppBar(title: const Text('Check-In')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                Spacing.md, Spacing.md, Spacing.md, 0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('checkin-search'),
                    controller: _search,
                    textInputAction: TextInputAction.go,
                    decoration: InputDecoration(
                      labelText: 'Booking code, name or phone',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: typingPass
                          ? IconButton(
                              key: const Key('open-pass'),
                              tooltip: 'Open pass',
                              icon: const Icon(Icons.arrow_forward),
                              onPressed:
                                  _busy ? null : () => _openPass(_search.text),
                            )
                          : null,
                    ),
                    onSubmitted: (value) {
                      if (looksLikeStayPass(value)) _openPass(value);
                    },
                  ),
                ),
                const SizedBox(width: Spacing.sm),
                FilledButton.icon(
                  key: const Key('scan-pass-button'),
                  onPressed: _busy ? null : _scan,
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('Scan pass'),
                ),
              ],
            ),
          ),
          Expanded(
            child: AsyncView(
              value: arrivalsAsync,
              onRetry: () => ref.invalidate(todaysArrivalsProvider(propertyId)),
              empty: () => const EmptyState(
                icon: Icons.how_to_reg_outlined,
                title: 'No bookings waiting to check in',
              ),
              data: (bookings) {
                // A pass being typed is not a search term.
                final shown = typingPass
                    ? bookings
                    : bookings
                        .where((b) => bookingMatchesSearch(b, query))
                        .toList();
                if (shown.isEmpty) {
                  return EmptyState(
                    icon: Icons.search_off,
                    title: 'No booking matches "${query.trim()}"',
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.all(Spacing.md),
                  itemCount: shown.length,
                  itemBuilder: (context, i) {
                    final b = shown[i];
                    final warning = roomWarningFor(roomByUnit[b.unitId]);
                    return Card(
                      margin: const EdgeInsets.only(bottom: Spacing.sm),
                      child: ListTile(
                        title: Text(b.customerName ?? 'Guest'),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${formatDay(b.start.toLocal())} → ${formatDay(b.end.toLocal())} · '
                              '${b.guests ?? '—'} guests · Booking ${bookingCode(b.id)}',
                            ),
                            if (warning != null)
                              Padding(
                                padding:
                                    const EdgeInsets.only(top: Spacing.xs),
                                child: Chip(
                                  key: Key('room-warning-${b.id}'),
                                  visualDensity: VisualDensity.compact,
                                  avatar: Icon(Icons.warning_amber_outlined,
                                      size: 18,
                                      color: RoomStatus.cleaning.color),
                                  label: Text(warning),
                                ),
                              ),
                          ],
                        ),
                        trailing: FilledButton(
                          onPressed: () => _checkIn(b.id, propertyId),
                          child: const Text('Check In'),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
