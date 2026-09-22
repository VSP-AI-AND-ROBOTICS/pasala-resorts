import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/failure_view.dart';
import '../../data/repositories/booking_repository.dart';
import '../calendar/availability_calendar.dart';
import '../calendar/providers.dart';

/// Collapses individually selected days into contiguous ranges, so three
/// adjacent taps produce one reservation row instead of three. The SRS asks
/// for blocking a single date, several dates, and a range through the same
/// gesture: tap days, and adjacent selections collapse automatically.
///
/// Uses real `DateTime` subtraction (`day.difference(previous).inDays`)
/// rather than any day-of-month arithmetic, so a run that crosses a month or
/// year boundary (e.g. 30/31 Jan + 1 Feb) still collapses into a single
/// range -- see the month/year-boundary tests in
/// `test/features/admin/block_selection_test.dart`.
List<DateTimeRange> collapseToRanges(Set<DateTime> days) {
  if (days.isEmpty) return const [];
  final sorted = days.map(DateUtils.dateOnly).toList()..sort();

  final ranges = <DateTimeRange>[];
  var start = sorted.first;
  var previous = sorted.first;

  for (final day in sorted.skip(1)) {
    if (day.difference(previous).inDays == 1) {
      previous = day;
      continue;
    }
    ranges.add(DateTimeRange(start: start, end: previous));
    start = day;
    previous = day;
  }
  ranges.add(DateTimeRange(start: start, end: previous));
  return ranges;
}

/// Admin's date-blocking screen for one unit. Reachable at
/// `/admin/block/:unitId` from `UnitsScreen`'s overflow menu.
///
/// `AvailabilityCalendar`'s `selectedStart`/`selectedEnd` model a single
/// contiguous stay (a booking has one check-in and one check-out), so they
/// cannot express an admin's arbitrary multi-day selection -- three separate
/// taps across a month is not "a range with two endpoints". Rather than
/// change that widget's contract (it is also driven by Task 16's booking
/// flow, where `selectedStart`/`selectedEnd` are load-bearing), this screen
/// keeps the count line above the reason field as the selection feedback and
/// relies on each tapped day turning `DayStatus.blocked` once the block
/// actually lands -- which happens live, without a reload, because
/// `unitReservationsProvider` is realtime. The count line does distinguish
/// "12 days selected" from "3 ranges" so an admin picking dates across a
/// month can sanity-check what they are about to submit before saving.
class BlockDatesScreen extends ConsumerStatefulWidget {
  const BlockDatesScreen({super.key, required this.unitId});
  final String unitId;

  @override
  ConsumerState<BlockDatesScreen> createState() => _BlockDatesScreenState();
}

class _BlockDatesScreenState extends ConsumerState<BlockDatesScreen> {
  final _selected = <DateTime>{};
  final _reason = TextEditingController();
  DateTime _month = DateTime.now();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // The Save button's enabled state depends on the reason text, which
    // TextEditingController does not trigger a rebuild for on its own --
    // without this listener, typing/clearing the reason would not visibly
    // enable/disable the button until some unrelated setState happened.
    _reason.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  bool get _canSave =>
      !_busy && _selected.isNotEmpty && _reason.text.trim().isNotEmpty;

  Future<void> _save() async {
    if (!_canSave) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(blockDatesActionProvider)
          .blockDates(
            unitId: widget.unitId,
            ranges: collapseToRanges(_selected),
            reason: _reason.text.trim(),
          );
      ref.invalidate(unitReservationsProvider(widget.unitId));
      if (mounted) {
        setState(_selected.clear);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Dates blocked')));
      }
    } on BookingFailure catch (e) {
      // A UnitUnavailable here means a real booking is in the way; the
      // admin must cancel it deliberately rather than block over it. The
      // selection and reason are left untouched (nothing is cleared above
      // for this branch) so the admin can drop the conflicting day and
      // retry without re-picking everything.
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(FailureView.messageFor(e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Block dates')),
      body: ListView(
        padding: const EdgeInsets.all(Spacing.md),
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: () => setState(
                  () => _month = DateTime(_month.year, _month.month - 1),
                ),
              ),
              Expanded(
                child: Center(child: Text('${_month.month}/${_month.year}')),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: () => setState(
                  () => _month = DateTime(_month.year, _month.month + 1),
                ),
              ),
            ],
          ),
          AvailabilityCalendar(
            unitId: widget.unitId,
            month: _month,
            onDayTap: (day) => setState(() {
              _selected.contains(day)
                  ? _selected.remove(day)
                  : _selected.add(day);
            }),
          ),
          const SizedBox(height: Spacing.md),
          Text(
            '${_selected.length} days selected · '
            '${collapseToRanges(_selected).length} ranges',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: Spacing.sm),
          TextField(
            key: const Key('block-reason'),
            controller: _reason,
            decoration: const InputDecoration(
              labelText: 'Reason',
              hintText: 'Maintenance, private event, owner stay…',
            ),
          ),
          const SizedBox(height: Spacing.md),
          FilledButton(
            onPressed: _canSave ? _save : null,
            child: const Text('Block selected dates'),
          ),
        ],
      ),
    );
  }
}
