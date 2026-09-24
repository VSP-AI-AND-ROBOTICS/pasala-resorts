import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/current_resort.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/async_view.dart';
import '../../data/models/staff_shift.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/staff_shift_repository.dart';

final _dateFormat = DateFormat('EEE, d MMM yyyy');

/// True when [shifts] contains a shift on [day] -- calendar-date equality
/// only, time-of-day ignored. Pure so it's testable without a widget, the
/// same way `statusFor` in `availability_calendar.dart` is.
bool hasShiftOn(DateTime day, List<StaffShift> shifts) =>
    shifts.any((s) => DateUtils.isSameDay(s.shiftDate, day));

/// `/staff/schedules` -- a month calendar of the signed-in staff/
/// accountant member's own shifts. Visually mirrors
/// `AvailabilityCalendar`'s grid (Monday-first, prev/next chevrons) without
/// reusing that widget directly -- it is reservation-shaped and
/// booking-tap oriented, not a fit for "does this day have a shift."
class WorkSchedulesScreen extends ConsumerStatefulWidget {
  const WorkSchedulesScreen({super.key});

  @override
  ConsumerState<WorkSchedulesScreen> createState() =>
      _WorkSchedulesScreenState();
}

class _WorkSchedulesScreenState extends ConsumerState<WorkSchedulesScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  void _showShiftsFor(DateTime day, List<StaffShift> shifts) {
    final dayShifts = shifts
        .where((s) => DateUtils.isSameDay(s.shiftDate, day))
        .toList();
    if (dayShifts.isEmpty) return;
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(_dateFormat.format(day)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final shift in dayShifts) ...[
              Text(
                '${formatTimeOfDay(shift.startTime)} – '
                '${formatTimeOfDay(shift.endTime)}',
              ),
              if (shift.notes != null && shift.notes!.isNotEmpty)
                Text(shift.notes!),
              const SizedBox(height: Spacing.sm),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider).value;
    final staffId = user?.id;
    final propertyId = ref.watch(currentResortProvider)!.propertyId;
    final filter = (propertyId: propertyId, staffId: staffId, from: null, to: null);
    final shiftsAsync = staffId == null
        ? AsyncValue<List<StaffShift>>.data(const [])
        : ref.watch(staffShiftsProvider(filter));
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Work Schedules')),
      body: AsyncView(
        value: shiftsAsync,
        onRetry: staffId == null
            ? null
            : () => ref.invalidate(staffShiftsProvider(filter)),
        data: (shifts) {
          final first = DateTime(_month.year, _month.month, 1);
          final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
          final leadingBlanks = first.weekday - 1;

          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.all(Spacing.md),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.chevron_left),
                        onPressed: () => setState(
                          () =>
                              _month = DateTime(_month.year, _month.month - 1),
                        ),
                      ),
                      Text(
                        DateFormat.yMMMM().format(_month),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      IconButton(
                        icon: const Icon(Icons.chevron_right),
                        onPressed: () => setState(
                          () =>
                              _month = DateTime(_month.year, _month.month + 1),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
                  child: GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 7,
                          mainAxisSpacing: Spacing.xs,
                          crossAxisSpacing: Spacing.xs,
                        ),
                    itemCount: leadingBlanks + daysInMonth,
                    itemBuilder: (context, i) {
                      if (i < leadingBlanks) return const SizedBox.shrink();
                      final day = DateTime(
                        _month.year,
                        _month.month,
                        i - leadingBlanks + 1,
                      );
                      final hasShift = hasShiftOn(day, shifts);

                      return InkWell(
                        key: Key('shift-day-${day.day}'),
                        onTap: hasShift
                            ? () => _showShiftsFor(day, shifts)
                            : null,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: hasShift
                                ? scheme.primaryContainer
                                : scheme.surface,
                            borderRadius: BorderRadius.circular(
                              PasalaTokens.radiusSm,
                            ),
                            border: Border.all(color: scheme.outlineVariant),
                          ),
                          child: Center(child: Text('${day.day}')),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
