import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/current_resort.dart';
import '../../core/errors.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/failure_view.dart';
import '../../data/models/attendance_record.dart';
import '../../data/repositories/attendance_repository.dart';
import '../../data/repositories/auth_repository.dart';

final _dateFormat = DateFormat('d MMM yyyy');
final _timeFormat = DateFormat.jm();

/// Today's record among [records], if the staff member has one --
/// date-only comparison via [DateUtils.isSameDay]. Pure so it's testable
/// without a widget.
AttendanceRecord? todayRecordFrom(List<AttendanceRecord> records, DateTime today) {
  for (final record in records) {
    if (DateUtils.isSameDay(record.workDate, today)) return record;
  }
  return null;
}

/// Every record except today's, newest first. Pure for the same reason.
List<AttendanceRecord> pastRecordsFrom(List<AttendanceRecord> records, DateTime today) {
  final past =
      records.where((r) => !DateUtils.isSameDay(r.workDate, today)).toList();
  past.sort((a, b) => b.workDate.compareTo(a.workDate));
  return past;
}

/// `/staff/daily-status` -- one-tap check-in/check-out for today, plus
/// the signed-in staff/accountant member's own history below it. No
/// edit, no correction -- a checkout is final once recorded (see the
/// design spec's "Missed checkout" decision).
class DailyStatusScreen extends ConsumerStatefulWidget {
  const DailyStatusScreen({super.key});

  @override
  ConsumerState<DailyStatusScreen> createState() => _DailyStatusScreenState();
}

class _DailyStatusScreenState extends ConsumerState<DailyStatusScreen> {
  bool _busy = false;

  Future<void> _checkIn(String staffId, AttendanceFilter filter) async {
    setState(() => _busy = true);
    try {
      await ref
          .read(attendanceRepositoryProvider)
          .checkIn(propertyId: filter.propertyId, staffId: staffId);
      ref.invalidate(attendanceRecordsProvider(filter));
    } on BookingFailure catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(FailureView.messageFor(e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _checkOut(String recordId, AttendanceFilter filter) async {
    setState(() => _busy = true);
    try {
      await ref.read(attendanceRepositoryProvider).checkOut(id: recordId);
      ref.invalidate(attendanceRecordsProvider(filter));
    } on BookingFailure catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(FailureView.messageFor(e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider).value;
    final staffId = user?.id;

    // Unlike the read-only Time Slots/Leave screens, this screen's top
    // card needs a real staff id to check in with -- it can't fall back
    // to an empty-list placeholder the way a plain list screen can, so
    // it waits for auth to resolve instead of proceeding with a null id.
    if (staffId == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final propertyId = ref.watch(currentResortProvider)!.propertyId;
    final filter = (propertyId: propertyId, staffId: staffId, date: null);
    final recordsAsync = ref.watch(attendanceRecordsProvider(filter));

    return Scaffold(
      appBar: AppBar(title: const Text('Daily Work Status')),
      body: AsyncView(
        value: recordsAsync,
        onRetry: () => ref.invalidate(attendanceRecordsProvider(filter)),
        data: (all) {
          final today = todayRecordFrom(all, DateTime.now());
          final past = pastRecordsFrom(all, DateTime.now());

          return ListView(
            padding: const EdgeInsets.all(Spacing.md),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(Spacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (today == null) ...[
                        const Text('You have not checked in today.'),
                        const SizedBox(height: Spacing.md),
                        FilledButton(
                          key: const Key('check-in-button'),
                          onPressed: _busy ? null : () => _checkIn(staffId, filter),
                          child: const Text('Check In'),
                        ),
                      ] else if (today.isCheckedIn) ...[
                        Text('Checked in at ${_timeFormat.format(today.checkInAt.toLocal())}'),
                        const SizedBox(height: Spacing.md),
                        FilledButton(
                          key: const Key('check-out-button'),
                          onPressed: _busy ? null : () => _checkOut(today.id, filter),
                          child: const Text('Check Out'),
                        ),
                      ] else ...[
                        Text(
                          'Checked in at ${_timeFormat.format(today.checkInAt.toLocal())} · '
                          'Checked out at ${_timeFormat.format(today.checkOutAt!.toLocal())}',
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: Spacing.lg),
              if (past.isEmpty)
                const EmptyState(
                  icon: Icons.history_outlined,
                  title: 'No history yet',
                  message: 'Past check-ins will show up here.',
                )
              else
                for (final record in past)
                  Card(
                    child: ListTile(
                      title: Text(_dateFormat.format(record.workDate)),
                      subtitle: Text(
                        record.checkOutAt == null
                            ? 'Checked in at ${_timeFormat.format(record.checkInAt.toLocal())} · '
                                'No check-out recorded'
                            : 'Checked in at ${_timeFormat.format(record.checkInAt.toLocal())} · '
                                'Checked out at ${_timeFormat.format(record.checkOutAt!.toLocal())}',
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
