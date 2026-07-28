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

/// Formats a hold's remaining time for the "Holding your dates — mm:ss
/// left" banner. Pure so the countdown text is testable without a running
/// [Timer].
String formatHoldRemaining(Duration remaining) {
  final clamped = remaining.isNegative ? Duration.zero : remaining;
  final minutes = clamped.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = clamped.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds left';
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
    setState(() {
      if (_slotTypeId != null) {
        // A slot occupies exactly one dated line server-side (build_period
        // ignores p_to when a slot type is given), so a slot booking is
        // always a single-day selection.
        _from = day;
        _to = day;
      } else if (_from == null || _to != null) {
        _from = day;
        _to = null;
      } else if (day.isBefore(_from!)) {
        _to = _from;
        _from = day;
      } else {
        _to = day;
      }
      // Any prior hold/quote was for the old dates; it no longer applies.
      _hold = null;
      _quote = null;
    });
    unawaited(_maybeFetchQuote());
  }

  void _onSlotTypeChanged(String? slotTypeId) {
    setState(() {
      _slotTypeId = slotTypeId;
      if (slotTypeId != null && _from != null) {
        _to = _from;
      }
      _hold = null;
      _quote = null;
    });
    unawaited(_maybeFetchQuote());
  }

  void _onGuestsChanged(int guests) {
    setState(() {
      _guests = guests;
      _hold = null;
      _quote = null;
    });
    unawaited(_maybeFetchQuote());
  }

  Future<void> _maybeFetchQuote() async {
    final from = _from, to = _to;
    if (from == null || to == null) return;
    setState(() => _quoteLoading = true);
    try {
      final quote = await ref.read(bookingRepositoryProvider).quote(
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
          .showSnackBar(SnackBar(content: Text(e.message)));
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
    _sheetSetState?.call(() {});
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
    final from = _from, to = _to, quote = _quote;
    if (from == null || to == null || quote == null) return;

    _setBusy(true);
    try {
      final repo = ref.read(bookingRepositoryProvider);
      // Reuses an existing hold on retry (e.g. the mock gateway failed but
      // the hold is still live) instead of creating a duplicate. This is
      // only safe because every failure that actually invalidates the hold
      // (UnitUnavailable, HoldExpired, QuoteStale) routes through
      // _handleFailure -> recoverSelection, which clears _hold first — so a
      // retry after any of those always creates a fresh hold rather than
      // reusing a dead one.
      final hold = _hold ??= await repo.createHold(
        unitId: widget.unitId,
        from: from,
        to: to,
        guests: _guests,
        slotTypeId: _slotTypeId,
        expectedTotal: quote.total,
      );
      if (!mounted) return;
      setState(() => _hold = hold);
      _startHoldTicker();

      final payment = await ref.read(paymentGatewayProvider).charge(
            reservationId: hold.id,
            amount: quote.total,
          );
      if (!payment.succeeded) {
        throw InvalidState(payment.failureMessage ?? 'Payment failed');
      }

      final confirmed = await repo.confirm(
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

  void _handleFailure(BookingFailure failure) {
    if (!mounted) return;
    Navigator.of(context).maybePop();
    final next = recoverSelection(
      failure,
      HoldSelection(hold: _hold, quote: _quote, from: _from, to: _to),
    );
    setState(() {
      _hold = next.hold;
      _quote = next.quote;
      _from = next.from;
      _to = next.to;
    });
    if (failure is UnitUnavailable) {
      ref.invalidate(unitReservationsProvider(widget.unitId));
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(failure.message)));
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
            child: Text('Holding your dates — ${formatHoldRemaining(remaining)}'),
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
