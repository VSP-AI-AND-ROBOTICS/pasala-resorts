import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/current_resort.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/empty_state.dart';
import '../../data/repositories/attendance_repository.dart';
import '../../data/repositories/profile_directory_repository.dart';

final _dateFormat = DateFormat('d MMM yyyy');
final _timeFormat = DateFormat.jm();

/// `/admin/attendance` -- admin-only, fully read-only: admin never
/// writes attendance, it only ever reads what staff recorded themselves.
/// Defaults to today, filterable by staff member and to any other date.
class AttendanceScreen extends ConsumerStatefulWidget {
  const AttendanceScreen({super.key});

  @override
  ConsumerState<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends ConsumerState<AttendanceScreen> {
  String? _staffId;
  DateTime _date = DateUtils.dateOnly(DateTime.now());

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(_date.year - 1),
      lastDate: DateTime(_date.year + 1),
    );
    if (picked != null) setState(() => _date = DateUtils.dateOnly(picked));
  }

  @override
  Widget build(BuildContext context) {
    final propertyId = ref.watch(currentResortProvider)!.propertyId;
    final filter = (propertyId: propertyId, staffId: _staffId, date: _date);
    final records = ref.watch(attendanceRecordsProvider(filter));
    final profiles = ref.watch(adminProfilesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Attendance')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(Spacing.md),
            child: Row(
              children: [
                Expanded(
                  child: profiles.when(
                    loading: () => const SizedBox.shrink(),
                    error: (_, _) => const SizedBox.shrink(),
                    data: (list) {
                      final staffOrAbove =
                          list.where((p) => p.isStaffOrAbove).toList();
                      return DropdownButtonFormField<String?>(
                        key: const Key('attendance-staff-picker'),
                        initialValue: _staffId,
                        decoration: const InputDecoration(labelText: 'Staff member'),
                        items: [
                          const DropdownMenuItem(value: null, child: Text('All staff')),
                          for (final p in staffOrAbove)
                            DropdownMenuItem(
                              value: p.id,
                              child: Text(p.fullName ?? p.email),
                            ),
                        ],
                        onChanged: (value) => setState(() => _staffId = value),
                      );
                    },
                  ),
                ),
                const SizedBox(width: Spacing.sm),
                TextButton.icon(
                  key: const Key('attendance-date-picker'),
                  onPressed: _pickDate,
                  icon: const Icon(Icons.calendar_today_outlined),
                  label: Text(_dateFormat.format(_date)),
                ),
              ],
            ),
          ),
          Expanded(
            child: AsyncView(
              value: records,
              onRetry: () => ref.invalidate(attendanceRecordsProvider(filter)),
              empty: () => const EmptyState(
                icon: Icons.how_to_reg_outlined,
                title: 'No attendance records',
                message: 'Nobody has checked in for this day yet.',
              ),
              data: (list) => ListView(
                children: [
                  for (final record in list)
                    Padding(
                      key: Key('attendance-row-${record.id}'),
                      padding: const EdgeInsets.symmetric(
                        horizontal: Spacing.md,
                        vertical: Spacing.xs,
                      ),
                      child: Card(
                        child: ListTile(
                          title: Text(record.staffName ?? record.staffId),
                          subtitle: Text(
                            record.isCheckedIn
                                ? 'Checked in at ${_timeFormat.format(record.checkInAt.toLocal())} · '
                                    'Still checked in'
                                : 'Checked in at ${_timeFormat.format(record.checkInAt.toLocal())} · '
                                    'Checked out at ${_timeFormat.format(record.checkOutAt!.toLocal())}',
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
