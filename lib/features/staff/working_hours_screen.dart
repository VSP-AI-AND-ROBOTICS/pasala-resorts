import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/empty_state.dart';
import '../../data/models/attendance_record.dart';
import '../../data/repositories/attendance_repository.dart';
import '../../data/repositories/auth_repository.dart';

final _dateFormat = DateFormat('d MMM yyyy');

/// Hours worked on [record], or `null` if it has no check-out yet -- an
/// in-progress day has no fixed duration to add to a total, unlike
/// [DailyStatusScreen] which shows an open check-in as its own state.
double? hoursForRecord(AttendanceRecord record) {
  final checkOut = record.checkOutAt;
  if (checkOut == null) return null;
  return checkOut.difference(record.checkInAt).inMinutes / 60.0;
}

/// The Monday (00:00) of the week containing [day].
DateTime startOfWeek(DateTime day) {
  final date = DateUtils.dateOnly(day);
  return date.subtract(Duration(days: date.weekday - 1));
}

/// The 1st of the month containing [day].
DateTime startOfMonth(DateTime day) => DateTime(day.year, day.month);

/// Sum of [hoursForRecord] across every completed record whose `workDate`
/// falls in `[from, to]` inclusive -- an open (not yet checked out) day
/// contributes nothing until it's closed out. Pure so the totals are
/// testable without a widget.
double totalHours(List<AttendanceRecord> records, DateTime from, DateTime to) {
  var total = 0.0;
  for (final record in records) {
    final date = DateUtils.dateOnly(record.workDate);
    if (date.isBefore(from) || date.isAfter(to)) continue;
    total += hoursForRecord(record) ?? 0;
  }
  return total;
}

/// "7h 30m" / "0h" -- never a raw decimal, since a staff member reads
/// hours-and-minutes, not `7.5`.
String formatHours(double hours) {
  final totalMinutes = (hours * 60).round();
  final h = totalMinutes ~/ 60;
  final m = totalMinutes % 60;
  return m == 0 ? '${h}h' : '${h}h ${m}m';
}

/// `/staff/working-hours` -- total hours worked, computed entirely from
/// this member's own attendance records (the same check-in/check-out
/// timestamps `DailyStatusScreen` records) -- no separate hours-tracking
/// data exists or is needed.
class WorkingHoursScreen extends ConsumerWidget {
  const WorkingHoursScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider).value;
    final staffId = user?.id;
    if (staffId == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final filter = (staffId: staffId, date: null);
    final recordsAsync = ref.watch(attendanceRecordsProvider(filter));
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Working Hours')),
      body: AsyncView(
        value: recordsAsync,
        onRetry: () => ref.invalidate(attendanceRecordsProvider(filter)),
        data: (records) {
          final now = DateTime.now();
          final today = DateUtils.dateOnly(now);
          final weekStart = startOfWeek(now);
          final monthStart = startOfMonth(now);

          final completed = records.where((r) => r.checkOutAt != null).toList()
            ..sort((a, b) => b.workDate.compareTo(a.workDate));

          Widget stat(String label, double hours) => Expanded(
                child: Column(
                  children: [
                    Text(formatHours(hours),
                        style: textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    Text(label,
                        style: textTheme.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant)),
                  ],
                ),
              );

          return ListView(
            padding: const EdgeInsets.all(Spacing.md),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(Spacing.md),
                  child: Row(
                    children: [
                      stat('Today', totalHours(records, today, today)),
                      stat('This week', totalHours(records, weekStart, today)),
                      stat('This month', totalHours(records, monthStart, today)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: Spacing.lg),
              if (completed.isEmpty)
                const EmptyState(
                  icon: Icons.schedule_outlined,
                  title: 'No completed days yet',
                  message: 'Hours show up here once a day is checked out.',
                )
              else
                for (final record in completed)
                  Card(
                    margin: const EdgeInsets.only(bottom: Spacing.sm),
                    child: ListTile(
                      title: Text(_dateFormat.format(record.workDate)),
                      trailing: Text(
                        formatHours(hoursForRecord(record)!),
                        style: textTheme.titleSmall,
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
