import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/current_resort.dart';
import '../../core/errors.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/failure_view.dart';
import '../../data/models/staff_shift.dart';
import '../../data/repositories/resort_member_repository.dart';
import '../../data/repositories/staff_shift_repository.dart';

final _dateFormat = DateFormat('d MMM yyyy');

/// `/admin/staff-shifts` -- admin-only (gated the same way every other
/// `/admin/*` management route is, not the staff-or-above carve-out
/// `/admin/dashboard`/`/admin/reports` get, since assigning a shift is a
/// write action). Lists every shift across every staff/accountant member,
/// filterable by staff member and date range.
class StaffShiftsScreen extends ConsumerStatefulWidget {
  const StaffShiftsScreen({super.key});

  @override
  ConsumerState<StaffShiftsScreen> createState() => _StaffShiftsScreenState();
}

class _StaffShiftsScreenState extends ConsumerState<StaffShiftsScreen> {
  String? _staffId;
  DateTimeRange? _dateRange;

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(DateTime.now().year - 1),
      lastDate: DateTime(DateTime.now().year + 2),
      initialDateRange: _dateRange,
    );
    if (picked != null) setState(() => _dateRange = picked);
  }

  @override
  Widget build(BuildContext context) {
    final propertyId = ref.watch(currentResortProvider)!.propertyId;
    final filter = (
      propertyId: propertyId,
      staffId: _staffId,
      from: _dateRange?.start,
      to: _dateRange?.end,
    );
    final shifts = ref.watch(staffShiftsProvider(filter));
    final profiles = ref.watch(resortMembersProvider(propertyId));

    return Scaffold(
      appBar: AppBar(title: const Text('Staff shifts')),
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
                      return DropdownButtonFormField<String?>(
                        key: const Key('shift-staff-picker'),
                        initialValue: _staffId,
                        decoration: const InputDecoration(labelText: 'Staff member'),
                        items: [
                          const DropdownMenuItem(value: null, child: Text('All staff')),
                          for (final p in list)
                            DropdownMenuItem(
                              value: p.userId,
                              child: Text(p.fullName ?? p.email),
                            ),
                        ],
                        onChanged: (value) => setState(() => _staffId = value),
                      );
                    },
                  ),
                ),
                const SizedBox(width: Spacing.sm),
                IconButton(
                  key: const Key('shift-date-filter'),
                  icon: const Icon(Icons.date_range_outlined),
                  tooltip: 'Filter by date range',
                  onPressed: _pickDateRange,
                ),
                if (_dateRange != null)
                  IconButton(
                    icon: const Icon(Icons.clear),
                    tooltip: 'Clear date filter',
                    onPressed: () => setState(() => _dateRange = null),
                  ),
              ],
            ),
          ),
          Expanded(
            child: AsyncView(
              value: shifts,
              onRetry: () => ref.invalidate(staffShiftsProvider(filter)),
              empty: () => const EmptyState(
                icon: Icons.event_busy_outlined,
                title: 'No shifts assigned yet',
                message: 'Tap + to assign a staff member their first shift.',
              ),
              data: (list) => ListView(
                children: [
                  for (final shift in list)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: Spacing.md,
                        vertical: Spacing.xs,
                      ),
                      child: Card(
                        child: ListTile(
                          title: Text(shift.staffName ?? shift.staffId),
                          subtitle: Text(
                            [
                              _dateFormat.format(shift.shiftDate),
                              '${formatTimeOfDay(shift.startTime)} – '
                                  '${formatTimeOfDay(shift.endTime)}',
                              if (shift.notes != null && shift.notes!.isNotEmpty)
                                shift.notes!,
                            ].join(' · '),
                          ),
                          trailing: PopupMenuButton<String>(
                            onSelected: (value) =>
                                _onMenuSelected(context, filter, shift, value),
                            itemBuilder: (context) => const [
                              PopupMenuItem(value: 'edit', child: Text('Edit')),
                              PopupMenuItem(value: 'delete', child: Text('Delete')),
                            ],
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
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const StaffShiftFormScreen()),
        ),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _onMenuSelected(
    BuildContext context,
    StaffShiftFilter filter,
    StaffShift shift,
    String value,
  ) {
    switch (value) {
      case 'edit':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => StaffShiftFormScreen(existing: shift),
          ),
        );
      case 'delete':
        _delete(context, filter, shift);
    }
  }

  Future<void> _delete(
    BuildContext context,
    StaffShiftFilter filter,
    StaffShift shift,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Delete this shift for ${shift.staffName ?? shift.staffId}?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      await ref.read(staffShiftRepositoryProvider).delete(shift.id);
      ref.invalidate(staffShiftsProvider(filter));
    } on BookingFailure catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(FailureView.messageFor(e))));
      }
    }
  }
}

/// Create/edit form for a [StaffShift]. Creating always assigns a date
/// RANGE (one row per day, via [StaffShiftRepository.createRange]);
/// editing an existing row changes just that one day in place (via
/// [StaffShiftRepository.updateOne]) -- the date-range picker is hidden
/// once [existing] is set, since an existing row is already a single day.
class StaffShiftFormScreen extends ConsumerStatefulWidget {
  const StaffShiftFormScreen({super.key, this.existing});

  final StaffShift? existing;

  @override
  ConsumerState<StaffShiftFormScreen> createState() => _StaffShiftFormScreenState();
}

class _StaffShiftFormScreenState extends ConsumerState<StaffShiftFormScreen> {
  late final TextEditingController _notes;
  String? _staffId;
  DateTimeRange? _range;
  TimeOfDay _start = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _end = const TimeOfDay(hour: 17, minute: 0);
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _notes = TextEditingController(text: existing?.notes ?? '');
    _staffId = existing?.staffId;
    if (existing != null) {
      _range = DateTimeRange(start: existing.shiftDate, end: existing.shiftDate);
      _start = existing.startTime;
      _end = existing.endTime;
    }
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showDateRangePicker(
      context: context,
      firstDate: today,
      lastDate: DateTime(today.year + 2),
      initialDateRange: _range,
    );
    if (picked != null) setState(() => _range = picked);
  }

  Future<void> _pickStart() async {
    final picked = await showTimePicker(context: context, initialTime: _start);
    if (picked != null) setState(() => _start = picked);
  }

  Future<void> _pickEnd() async {
    final picked = await showTimePicker(context: context, initialTime: _end);
    if (picked != null) setState(() => _end = picked);
  }

  Future<void> _save() async {
    final staffId = _staffId;
    final range = _range;
    if (staffId == null || range == null) {
      setState(() => _error = 'Pick a staff member and a date range.');
      return;
    }
    if (_endBeforeOrEqualStart) {
      setState(() => _error = 'End time must be after start time.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final existing = widget.existing;
      final notes = _notes.text.trim();
      if (existing == null) {
        await ref.read(staffShiftRepositoryProvider).createRange(
              propertyId: ref.read(currentResortProvider)!.propertyId,
              staffId: staffId,
              range: range,
              start: _start,
              end: _end,
              notes: notes.isEmpty ? null : notes,
            );
      } else {
        await ref.read(staffShiftRepositoryProvider).updateOne(StaffShift(
              id: existing.id,
              staffId: staffId,
              shiftDate: range.start,
              startTime: _start,
              endTime: _end,
              notes: notes.isEmpty ? null : notes,
            ));
      }
      ref.invalidate(staffShiftsProvider);
      if (mounted) Navigator.of(context).pop();
    } on BookingFailure catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(FailureView.messageFor(e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool get _endBeforeOrEqualStart =>
      (_end.hour * 60 + _end.minute) <= (_start.hour * 60 + _start.minute);

  @override
  Widget build(BuildContext context) {
    final profiles = ref.watch(
      resortMembersProvider(ref.watch(currentResortProvider)!.propertyId),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? 'Assign shift' : 'Edit shift'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(Spacing.lg),
            children: [
              profiles.when(
                loading: () => const SizedBox.shrink(),
                error: (_, _) => const SizedBox.shrink(),
                data: (list) {
                  return DropdownButtonFormField<String>(
                    key: const Key('shift-form-staff-picker'),
                    initialValue: _staffId,
                    decoration: const InputDecoration(labelText: 'Staff member'),
                    items: [
                      for (final p in list)
                        DropdownMenuItem(value: p.userId, child: Text(p.fullName ?? p.email)),
                    ],
                    onChanged: widget.existing == null
                        ? (value) => setState(() => _staffId = value)
                        : null,
                  );
                },
              ),
              const SizedBox(height: Spacing.md),
              ListTile(
                key: const Key('shift-form-date-range'),
                contentPadding: EdgeInsets.zero,
                title: Text(widget.existing == null ? 'Date range' : 'Date'),
                subtitle: Text(
                  _range == null
                      ? 'Required'
                      : widget.existing == null
                          ? '${_dateFormat.format(_range!.start)} – '
                              '${_dateFormat.format(_range!.end)}'
                          : _dateFormat.format(_range!.start),
                ),
                onTap: widget.existing == null ? _pickRange : null,
              ),
              const SizedBox(height: Spacing.sm),
              ListTile(
                key: const Key('shift-form-start-time'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Start time'),
                subtitle: Text(formatTimeOfDay(_start)),
                onTap: _pickStart,
              ),
              ListTile(
                key: const Key('shift-form-end-time'),
                contentPadding: EdgeInsets.zero,
                title: const Text('End time'),
                subtitle: Text(formatTimeOfDay(_end)),
                onTap: _pickEnd,
              ),
              const SizedBox(height: Spacing.sm),
              TextField(
                key: const Key('shift-form-notes'),
                controller: _notes,
                decoration: const InputDecoration(
                  labelText: 'Notes',
                  helperText: 'Optional',
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: Spacing.sm),
                  child: Text(
                    _error!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
              const SizedBox(height: Spacing.lg),
              FilledButton(
                onPressed: _busy ? null : _save,
                child: const Text('Save'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
