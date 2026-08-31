import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/empty_state.dart';
import '../../data/models/staff_shift.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/staff_shift_repository.dart';

final _dateFormat = DateFormat('EEE, d MMM yyyy');

/// Upcoming-first: drops anything before [today] and sorts the rest by
/// date ascending. Pure so the ordering rule is testable without a
/// widget. `today` itself counts as upcoming -- a shift later this same
/// day is still something the staff member needs to see.
List<StaffShift> upcomingShiftsFrom(List<StaffShift> shifts, DateTime today) {
  final day = DateUtils.dateOnly(today);
  final upcoming = shifts.where((s) => !s.shiftDate.isBefore(day)).toList();
  upcoming.sort((a, b) => a.shiftDate.compareTo(b.shiftDate));
  return upcoming;
}

/// `/staff/time-slots` -- the signed-in staff/accountant member's own
/// upcoming shifts, as a plain chronological list. Same underlying data as
/// `WorkSchedulesScreen`'s calendar; this is the list presentation (see
/// the design spec's "same shift data, two views" decision).
class TimeSlotsScreen extends ConsumerWidget {
  const TimeSlotsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider).value;
    final staffId = user?.id;
    final shiftsAsync = staffId == null
        ? AsyncValue<List<StaffShift>>.data(const [])
        : ref.watch(staffShiftsProvider((staffId: staffId, from: null, to: null)));

    return Scaffold(
      appBar: AppBar(title: const Text('Time Slots')),
      body: AsyncView(
        value: shiftsAsync,
        onRetry: staffId == null
            ? null
            : () => ref.invalidate(
                staffShiftsProvider((staffId: staffId, from: null, to: null))),
        empty: () => const EmptyState(
          icon: Icons.access_time_outlined,
          title: 'No shifts assigned yet',
          message: 'Your admin hasn\'t assigned you a shift yet.',
        ),
        data: (all) {
          final upcoming = upcomingShiftsFrom(all, DateTime.now());
          if (upcoming.isEmpty) {
            return const EmptyState(
              icon: Icons.access_time_outlined,
              title: 'No shifts assigned yet',
              message: 'Your admin hasn\'t assigned you a shift yet.',
            );
          }
          return ListView(
            padding: const EdgeInsets.all(Spacing.md),
            children: [
              for (final shift in upcoming)
                Card(
                  child: ListTile(
                    title: Text(_dateFormat.format(shift.shiftDate)),
                    subtitle: Text(
                      [
                        '${formatTimeOfDay(shift.startTime)} – '
                            '${formatTimeOfDay(shift.endTime)}',
                        if (shift.notes != null && shift.notes!.isNotEmpty)
                          shift.notes!,
                      ].join(' · '),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
