import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/errors.dart';
import '../../core/widgets/failure_view.dart';
import '../../data/models/quote.dart';
import '../../data/models/reservation.dart';
import '../../data/models/slot_type.dart';
import '../../data/models/unit.dart';
import '../../data/repositories/booking_repository.dart';
import '../browse/providers.dart' show slotTypesProvider;
import '../calendar/availability_calendar.dart';
import '../calendar/providers.dart' show unitReservationsProvider;
import 'payment_gateway.dart';
import 'providers.dart';
import 'quote_sheet.dart';

/// The dates/hold/quote slice of [BookingScreen]'s state that a failure can
/// touch. Kept as its own value type -- rather than four loose fields -- so
/// [recoverSelection] can be a pure function tested without a widget.
@immutable
class HoldSelection {
  const HoldSelection({this.hold, this.quote, this.from, this.to});

  final Reservation? hold;
  final Quote? quote;
  final DateTime? from;
  final DateTime? to;
}

/// Maps a caught [BookingFailure] to the selection that should follow it.
/// This is the part of the recovery flow most likely to be wrong -- getting
/// it backwards means either re-showing a taken date as available, or
/// forcing a customer to re-pick dates that were never actually invalidated
/// -- so it is a standalone pure function instead of a switch buried in a
/// `setState` closure.
///
///  * [UnitUnavailable] — someone else took the range: the hold never
///    existed (or is worthless) and the end date must go, so the customer
///    is forced to pick a new, non-conflicting range.
///  * [HoldExpired] — the 15-minute hold lapsed: the hold and quote are
///    dead, but the dates themselves are still perfectly bookable, so they
///    are kept for an immediate retry.
///  * [QuoteStale] — the price moved between quote and hold: nothing was
///    ever created server-side, so only the quote needs clearing to force
///    a re-fetch; dates are kept.
///  * anything else (permission, not-found, network, unknown...) — none of
///    these mean the hold/quote/dates are actually invalid, so the
///    selection is left untouched and the caller just shows the message.
HoldSelection recoverSelection(BookingFailure failure, HoldSelection current) =>
    switch (failure) {
      UnitUnavailable() => HoldSelection(from: current.from, to: null),
      HoldExpired() => HoldSelection(from: current.from, to: current.to),
      QuoteStale() => HoldSelection(from: current.from, to: current.to),
      _ => current,
    };

/// Identifies what a hold was created for: everything `create_hold` takes
/// except `expectedTotal` (price isn't part of a hold's *identity* -- two
/// requests for the same unit/dates/guests/slot are "the same hold" even if
/// the quoted total moved between them).
///
/// This is what makes a retry after a declined payment safe: comparing
/// [HoldParams] tells [decideHoldAction] whether the customer's new
/// selection is really new, or just a re-pick of the exact dates their still
/// -live hold already covers.
@immutable
class HoldParams {
  const HoldParams({
    required this.unitId,
    required this.from,
    required this.to,
    required this.guests,
    required this.slotTypeId,
  });

  final String unitId;
  final DateTime from;
  final DateTime to;
  final int guests;
  final String? slotTypeId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is HoldParams &&
          other.unitId == unitId &&
          other.from == from &&
          other.to == to &&
          other.guests == guests &&
          other.slotTypeId == slotTypeId);

  @override
  int get hashCode => Object.hash(unitId, from, to, guests, slotTypeId);
}

/// What should happen to a live hold when the selection is about to become
/// [nextParams].
enum HoldAction {
  /// No hold is live -- nothing to release, nothing to reuse.
  none,

  /// A hold is live and the incoming selection is byte-for-byte what it was
  /// created for. This is the retry-after-decline path: creating a second
  /// hold for the same range would collide with the still-live first one --
  /// `reservations_no_overlap` has no same-customer exemption, so that
  /// collision surfaces to the customer as "someone else took your own
  /// dates."
  reuseExisting,

  /// A hold is live and the incoming selection differs in any field. The old
  /// hold no longer matches what the customer wants and must be released
  /// immediately -- left alone, it would sit on the range for up to 15
  /// minutes (until it expires on its own) and could collide with the
  /// customer's own next hold for a different-but-overlapping range.
  releaseAndClear,
}

/// The Critical-defect fix: decides what to do with [hold] given the
/// selection is about to become [nextParams] (`null` means the selection
/// isn't a complete from/to pair yet, e.g. only the start date has been
/// tapped). Pure so this -- the exact logic that let a declined payment's
/// orphaned hold lock a customer out of their own dates -- is unit-testable
/// without a widget or a `Timer`. See `test/features/booking/hold_lifecycle_test.dart`.
HoldAction decideHoldAction({
  required Reservation? hold,
  required HoldParams? heldParams,
  required HoldParams? nextParams,
}) {
  if (hold == null) return HoldAction.none;
  if (heldParams != null && heldParams == nextParams) {
    return HoldAction.reuseExisting;
  }
  return HoldAction.releaseAndClear;
}

/// What [resolveSelectionChange] resolved the hold/heldParams pair to.
/// [releaseFailure] is set only when a release attempt itself failed -- the
/// caller must still apply [hold]/[heldParams] (both null in that case) and
/// let the customer keep going rather than get stuck, because a stale hold
/// expires on its own in 15 minutes regardless.
@immutable
class SelectionChangeResult {
  const SelectionChangeResult({
    required this.action,
    this.hold,
    this.heldParams,
    this.releaseFailure,
  });

  final HoldAction action;
  final Reservation? hold;
  final HoldParams? heldParams;
  final BookingFailure? releaseFailure;
}

/// Orchestrates [decideHoldAction] against [actions]: releases a hold that no
/// longer matches the selection (cancelling BEFORE the caller is free to
/// create a new one for the new selection), or leaves a still-matching hold
/// alone so it can be reused. Never throws -- a failed release is reported
/// via [SelectionChangeResult.releaseFailure] instead, so a flaky network
/// call here can never wedge the UI.
Future<SelectionChangeResult> resolveSelectionChange({
  required BookingActions actions,
  required Reservation? currentHold,
  required HoldParams? currentHeldParams,
  required HoldParams? nextParams,
}) async {
  final action = decideHoldAction(
    hold: currentHold,
    heldParams: currentHeldParams,
    nextParams: nextParams,
  );
  switch (action) {
    case HoldAction.none:
      return SelectionChangeResult(action: action);
    case HoldAction.reuseExisting:
      return SelectionChangeResult(
        action: action,
        hold: currentHold,
        heldParams: currentHeldParams,
      );
    case HoldAction.releaseAndClear:
      try {
        await actions.cancel(
          reservationId: currentHold!.id,
          reason: 'selection changed',
        );
      } on BookingFailure catch (e) {
        return SelectionChangeResult(action: action, releaseFailure: e);
      }
      return SelectionChangeResult(action: action);
  }
}

/// Resolves the hold to charge against for [params]: reuses [currentHold]
/// when [decideHoldAction] says it still matches (the retry-after-decline
/// path), otherwise creates a fresh one. Pure orchestration wrapper so
/// `_pay`'s "never double-create a hold for a live selection" rule is
/// testable without a widget.
Future<Reservation> resolveHoldForPayment({
  required BookingActions actions,
  required Reservation? currentHold,
  required HoldParams? currentHeldParams,
  required HoldParams params,
  required num expectedTotal,
}) {
  final action = decideHoldAction(
    hold: currentHold,
    heldParams: currentHeldParams,
    nextParams: params,
  );
  if (action == HoldAction.reuseExisting) {
    return Future.value(currentHold);
  }
  return actions.createHold(
    unitId: params.unitId,
    from: params.from,
    to: params.to,
    guests: params.guests,
    slotTypeId: params.slotTypeId,
    expectedTotal: expectedTotal,
  );
}

/// Formats a hold's remaining time for the "Holding your dates — mm:ss
/// left" banner. Pure so the countdown text is testable without a running
/// [Timer].
String formatHoldRemaining(Duration remaining) {
  final clamped = remaining.isNegative ? Duration.zero : remaining;
  final minutes = clamped.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = clamped.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds left';
}

/// The dead-end fix: whether the hold banner should show a "Resume
/// payment"/"Cancel hold" affordance. A hold survives a declined charge by
/// design (Finding 1's whole point is that the retry reuses it), but the
/// calendar renders a held range as occupied to every OTHER viewer -- the
/// mirror is identity-free on purpose, so it cannot tell the holder apart
/// from anyone else -- and disables tapping occupied days. Without this
/// control, a customer whose card was declined has no way back to `Pay and
/// confirm` for the dates they are still holding: the sheet already closed,
/// and their own dates now look untappable to them too. Pure so the exact
/// condition is testable without a widget or a running [Timer] -- see
/// `test/features/booking/resume_hold_test.dart`.
///
/// [remaining] is passed in rather than read off [hold] here so a test can
/// simulate "the ticker hasn't fired yet but the clock has moved on" without
/// a real [DateTime.now] dependency; production code always passes
/// `hold?.holdRemaining`.
bool shouldShowResumeHold({
  required Reservation? hold,
  required Duration? remaining,
}) {
  if (hold == null) return false;
  // A hold that has already been confirmed or cancelled is not live, even if
  // stale state elsewhere still thinks it has time left -- defends against
  // exactly the kind of local/server-state drift the confirm path leaves for
  // one frame before navigating away.
  if (hold.status != ReservationStatus.hold) return false;
  if (remaining == null || remaining <= Duration.zero) return false;
  return true;
}

class BookingScreen extends ConsumerStatefulWidget {
  const BookingScreen({super.key, required this.unitId});

  final String unitId;

  @override
  ConsumerState<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends ConsumerState<BookingScreen> {
  DateTime? _from;
  DateTime? _to;
  int _guests = 2;
  String? _slotTypeId;
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  Quote? _quote;
  Reservation? _hold;
  // The params `_hold` was created for -- `null` exactly when `_hold` is
  // `null`. Compared against the incoming selection by `decideHoldAction` so
  // a retry can reuse a still-live hold instead of orphaning it (Finding 1).
  HoldParams? _heldParams;
  bool _busy = false;
  bool _quoteLoading = false;
  Timer? _ticker;

  bool _sheetShown = false;
  StateSetter? _sheetSetState;

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _pickDay(DateTime day) {
    DateTime? newFrom = _from;
    DateTime? newTo = _to;
    if (_slotTypeId != null) {
      // A slot occupies exactly one dated line server-side (build_period
      // ignores p_to when a slot type is given), so a slot booking is
      // always a single-day selection.
      newFrom = day;
      newTo = day;
    } else if (_from == null || _to != null) {
      newFrom = day;
      newTo = null;
    } else if (day.isBefore(_from!)) {
      newTo = _from;
      newFrom = day;
    } else {
      newTo = day;
    }
    unawaited(_changeSelection(
      from: newFrom,
      to: newTo,
      guests: _guests,
      slotTypeId: _slotTypeId,
      applyLocalChange: () {
        _from = newFrom;
        _to = newTo;
      },
    ));
  }

  void _onSlotTypeChanged(String? slotTypeId) {
    final newTo = (slotTypeId != null && _from != null) ? _from : _to;
    unawaited(_changeSelection(
      from: _from,
      to: newTo,
      guests: _guests,
      slotTypeId: slotTypeId,
      applyLocalChange: () {
        _slotTypeId = slotTypeId;
        _to = newTo;
      },
    ));
  }

  void _onGuestsChanged(int guests) {
    unawaited(_changeSelection(
      from: _from,
      to: _to,
      guests: guests,
      slotTypeId: _slotTypeId,
      applyLocalChange: () => _guests = guests,
    ));
  }

  /// The Finding-1 fix: applies a dates/guests/slot-type change, first
  /// releasing a live hold that no longer matches (or reusing it if it still
  /// does) via [resolveSelectionChange] BEFORE the local selection state
  /// moves on. Without this, every one of `_pickDay`/`_onSlotTypeChanged`/
  /// `_onGuestsChanged` used to null out `_hold` locally while leaving the
  /// hold row live server-side -- so a customer retrying their own just
  /// -declined dates collided with their own orphaned hold.
  Future<void> _changeSelection({
    required DateTime? from,
    required DateTime? to,
    required int guests,
    required String? slotTypeId,
    required void Function() applyLocalChange,
  }) async {
    final nextParams = (from != null && to != null)
        ? HoldParams(
            unitId: widget.unitId,
            from: from,
            to: to,
            guests: guests,
            slotTypeId: slotTypeId,
          )
        : null;
    final result = await resolveSelectionChange(
      actions: ref.read(bookingActionsProvider),
      currentHold: _hold,
      currentHeldParams: _heldParams,
      nextParams: nextParams,
    );
    if (!mounted) return;
    setState(() {
      applyLocalChange();
      _hold = result.hold;
      _heldParams = result.heldParams;
      // Reusing keeps the quote too -- nothing about the selection actually
      // changed. Every other outcome (none, or a release) invalidates it.
      if (result.action != HoldAction.reuseExisting) {
        _quote = null;
      }
      // The ticker tracks `_hold`'s expiry. If the hold was just released
      // (or there never was one), a live ticker has nothing left to count
      // down -- left running, it would tick down to `_hold == null`,
      // self-cancel, and fire one spurious `_handleFailure(HoldExpired())`
      // up to a second later, potentially clobbering whatever new
      // selection/hold the customer has made in the meantime.
      if (_hold == null) {
        _ticker?.cancel();
        _ticker = null;
      }
    });
    final releaseFailure = result.releaseFailure;
    if (releaseFailure != null && mounted) {
      // Don't leave the UI wedged on a failed release -- the local state was
      // already cleared above so the customer can keep picking dates; the
      // orphaned hold (if the cancel truly didn't land) still expires on its
      // own within 15 minutes.
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not release your previous hold: '
              '${FailureView.messageFor(releaseFailure)}')));
    }
    unawaited(_maybeFetchQuote());
  }

  Future<void> _maybeFetchQuote() async {
    final from = _from, to = _to;
    if (from == null || to == null) return;
    setState(() => _quoteLoading = true);
    try {
      final quote = await ref.read(bookingActionsProvider).quote(
            unitId: widget.unitId,
            from: from,
            to: to,
            guests: _guests,
            slotTypeId: _slotTypeId,
          );
      if (!mounted) return;
      setState(() {
        _quote = quote;
        _quoteLoading = false;
      });
      _showQuoteSheet();
    } on BookingFailure catch (e) {
      if (!mounted) return;
      setState(() => _quoteLoading = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(FailureView.messageFor(e))));
    }
  }

  void _showQuoteSheet() {
    if (_quote == null) return;
    if (_sheetShown) {
      _sheetSetState?.call(() {});
      return;
    }
    _sheetShown = true;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => StatefulBuilder(
        builder: (context, setModalState) {
          _sheetSetState = setModalState;
          // Defensive: a failure can null _quote out from under an
          // already-open sheet while its close animation is still
          // playing. Never force-unwrap here.
          final quote = _quote;
          if (quote == null) return const SizedBox.shrink();
          return SafeArea(
            child: QuoteSheet(quote: quote, busy: _busy, onPay: _pay),
          );
        },
      ),
    ).whenComplete(() {
      _sheetShown = false;
      _sheetSetState = null;
    });
  }

  void _setBusy(bool value) {
    if (!mounted) return;
    setState(() => _busy = value);
    // Gate on `_sheetShown`, not just a `_sheetSetState != null` null-check:
    // the sheet's `StatefulBuilder` keeps reassigning `_sheetSetState` on
    // every rebuild it gets WHILE its pop reverse-animation plays, so the
    // reference can look "live" for several frames after `_handleFailure`
    // has already asked it to close and after `_sheetShown` was set back to
    // false -- right up until the widget is actually removed from the tree
    // and becomes defunct. `_sheetShown` is only ever flipped by
    // `_showQuoteSheet`/`_handleFailure`/`.whenComplete`, never by those
    // rebuilds, so it is the reliable signal for whether reaching through
    // `_sheetSetState` is still safe.
    if (_sheetShown) _sheetSetState?.call(() {});
  }

  void _startHoldTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      final remaining = _hold?.holdRemaining;
      if (remaining == null || remaining == Duration.zero) {
        _ticker?.cancel();
        _ticker = null;
        _handleFailure(const HoldExpired());
        return;
      }
      if (mounted) setState(() {});
    });
  }

  Future<void> _pay() async {
    // Finding 3: without this, two rapid taps can both enter `_pay` before
    // `setState`'s rebuild (next frame, not synchronous) has a chance to
    // disable the button. Harmless against today's mock gateway, but Phase 2
    // swaps in a real Razorpay charge behind this exact call and a second
    // concurrent entry becomes a double-charge.
    if (_busy) return;
    final from = _from, to = _to, quote = _quote;
    if (from == null || to == null || quote == null) return;

    _setBusy(true);
    try {
      final actions = ref.read(bookingActionsProvider);
      final params = HoldParams(
        unitId: widget.unitId,
        from: from,
        to: to,
        guests: _guests,
        slotTypeId: _slotTypeId,
      );
      // Finding 1: reuses a still-live hold that matches `params` exactly
      // (the retry-after-decline path) instead of creating a duplicate,
      // which would collide with the still-live original --
      // `reservations_no_overlap` has no same-customer exemption. Any
      // selection change that no longer matches `_hold` was already
      // released by `_changeSelection` before it reached here.
      final hold = await resolveHoldForPayment(
        actions: actions,
        currentHold: _hold,
        currentHeldParams: _heldParams,
        params: params,
        expectedTotal: quote.total,
      );
      if (!mounted) return;
      setState(() {
        _hold = hold;
        _heldParams = params;
      });
      _startHoldTicker();

      final payment = await ref.read(paymentGatewayProvider).charge(
            reservationId: hold.id,
            amount: quote.total,
          );
      if (!payment.succeeded) {
        throw InvalidState(payment.failureMessage ?? 'Payment failed');
      }

      final confirmed = await actions.confirm(
        reservationId: hold.id,
        paymentRef: payment.reference,
        amount: quote.total,
      );
      _ticker?.cancel();
      if (mounted) context.go('/booking/${confirmed.id}');
    } on BookingFailure catch (e) {
      _handleFailure(e);
    } finally {
      _setBusy(false);
    }
  }

  /// Explicit abandon path for the resume banner's "Cancel hold" action:
  /// calls `cancel_booking` so the held dates free up immediately, rather
  /// than making the customer wait out the 15-minute expiry.
  Future<void> _cancelHold() async {
    final hold = _hold;
    if (hold == null) return;
    _setBusy(true);
    try {
      await ref.read(bookingActionsProvider).cancel(
            reservationId: hold.id,
            reason: 'customer cancelled hold',
          );
      if (!mounted) return;
      _ticker?.cancel();
      _ticker = null;
      setState(() {
        _hold = null;
        _heldParams = null;
        _quote = null;
      });
    } on BookingFailure catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(FailureView.messageFor(e))));
    } finally {
      _setBusy(false);
    }
  }

  void _handleFailure(BookingFailure failure) {
    if (!mounted) return;
    // Finding 2: only pop the sheet if it's actually the thing on top. A
    // failure can fire after the sheet has already closed on its own (the
    // hold-expiry ticker is the case that surfaced this: it can tick to zero
    // after a prior failure already dismissed the sheet) -- an unconditional
    // `maybePop()` would then dismiss BookingScreen itself and throw the
    // customer out of the flow mid-booking.
    if (_sheetShown) {
      Navigator.of(context).maybePop();
      // Mark the sheet closed right away rather than waiting for
      // `showModalBottomSheet`'s returned future to complete (via
      // `.whenComplete` in `_showQuoteSheet`): the popped route's widget can
      // become defunct mid-reverse-animation, before that future actually
      // resolves. Any `_setBusy` call in that window must not reach through
      // a now-stale `_sheetSetState` into a disposed `StatefulBuilder` --
      // the crash this closes was reproduced by tapping "Cancel hold" right
      // after a declined payment closed the sheet.
      _sheetShown = false;
      _sheetSetState = null;
    }
    final next = recoverSelection(
      failure,
      HoldSelection(hold: _hold, quote: _quote, from: _from, to: _to),
    );
    setState(() {
      _hold = next.hold;
      _quote = next.quote;
      _from = next.from;
      _to = next.to;
      // Keep the `_heldParams` invariant (non-null iff `_hold` is non-null)
      // in sync with whatever `recoverSelection` decided.
      if (next.hold == null) _heldParams = null;
    });
    if (failure is UnitUnavailable) {
      ref.invalidate(unitReservationsProvider(widget.unitId));
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(FailureView.messageFor(failure))));
  }

  @override
  Widget build(BuildContext context) {
    final unitAsync = ref.watch(unitByIdProvider(widget.unitId));
    return Scaffold(
      appBar: AppBar(title: Text(unitAsync.value?.name ?? 'Book')),
      body: unitAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => FailureView(
          error: e,
          onRetry: () => ref.invalidate(unitByIdProvider(widget.unitId)),
        ),
        data: (unit) => _buildBody(context, unit),
      ),
    );
  }

  Widget _buildBody(BuildContext context, Unit unit) {
    Widget slotSelector = const SizedBox.shrink();
    if (unit.supportsSlots) {
      final slotTypesAsync = ref.watch(slotTypesProvider(unit.propertyId));
      slotSelector = slotTypesAsync.when(
        loading: () => const SizedBox.shrink(),
        error: (e, _) => FailureView(error: e),
        data: (slotTypes) => Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: _slotSelector(unit, slotTypes),
        ),
      );
    }

    final remaining = _hold?.holdRemaining;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(unit.name, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text('Sleeps ${unit.capacityBase}–${unit.capacityMax}'),
        const SizedBox(height: 16),
        if (remaining != null)
          Container(
            key: const Key('hold-banner'),
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.tertiaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Holding your dates — ${formatHoldRemaining(remaining)}'),
                // The dead-end fix: a live hold has no other way back to
                // payment once the sheet has closed (e.g. after a declined
                // card) -- the calendar shows the customer's own held dates
                // as occupied and disables tapping them, same as it does for
                // everyone else. This reopens the SAME hold/quote, never a
                // new one.
                if (shouldShowResumeHold(hold: _hold, remaining: remaining)) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.tonal(
                          key: const Key('resume-hold-button'),
                          onPressed: _busy ? null : _showQuoteSheet,
                          child: const Text('Resume payment'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          key: const Key('cancel-hold-button'),
                          onPressed: _busy ? null : _cancelHold,
                          child: const Text('Cancel hold'),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        if (remaining != null) const SizedBox(height: 16),
        slotSelector,
        _guestStepper(unit),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              onPressed: () => setState(
                  () => _month = DateTime(_month.year, _month.month - 1)),
            ),
            Text(DateFormat.yMMMM().format(_month)),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed: () => setState(
                  () => _month = DateTime(_month.year, _month.month + 1)),
            ),
          ],
        ),
        AvailabilityCalendar(
          unitId: widget.unitId,
          month: _month,
          selectedStart: _from,
          selectedEnd: _to,
          onDayTap: _pickDay,
        ),
        if (_quoteLoading) ...[
          const SizedBox(height: 16),
          const Center(child: CircularProgressIndicator()),
        ],
      ],
    );
  }

  Widget _guestStepper(Unit unit) => Row(
        children: [
          const Text('Guests'),
          const Spacer(),
          IconButton(
            key: const Key('guests-minus'),
            icon: const Icon(Icons.remove_circle_outline),
            onPressed:
                _guests > 1 ? () => _onGuestsChanged(_guests - 1) : null,
          ),
          Text('$_guests', style: Theme.of(context).textTheme.titleMedium),
          IconButton(
            key: const Key('guests-plus'),
            icon: const Icon(Icons.add_circle_outline),
            onPressed: _guests < unit.capacityMax
                ? () => _onGuestsChanged(_guests + 1)
                : null,
          ),
        ],
      );

  Widget _slotSelector(Unit unit, List<SlotType> slotTypes) {
    final segments = <ButtonSegment<String?>>[
      if (unit.supportsNightly)
        const ButtonSegment(value: null, label: Text('Nightly')),
      for (final s in slotTypes)
        ButtonSegment(value: s.id, label: Text(s.label)),
    ];
    if (segments.isEmpty) return const SizedBox.shrink();
    return SegmentedButton<String?>(
      segments: segments,
      selected: {_slotTypeId},
      onSelectionChanged: (selection) =>
          _onSlotTypeChanged(selection.first),
    );
  }
}
