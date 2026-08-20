import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/errors.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/failure_view.dart';
import '../../data/models/leave_request.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/leave_request_repository.dart';

final _dateFormat = DateFormat('d MMM yyyy');

String _statusLabel(LeaveStatus status) => switch (status) {
      LeaveStatus.pending => 'Pending',
      LeaveStatus.approved => 'Approved',
      LeaveStatus.rejected => 'Rejected',
    };

/// The status chip's tint -- pending reads as a neutral "awaiting a
/// decision" tone, approved as the brand colour, rejected as
/// muted/negative. Mirrors `BookingTile._statusColors`'s convention in
/// `my_bookings_screen.dart`.
(Color background, Color foreground) _statusColors(
  ColorScheme scheme,
  LeaveStatus status,
) =>
    switch (status) {
      LeaveStatus.pending => (scheme.tertiaryContainer, scheme.onTertiaryContainer),
      LeaveStatus.approved => (scheme.primaryContainer, scheme.onPrimaryContainer),
      LeaveStatus.rejected => (scheme.surfaceContainerHigh, scheme.onSurfaceVariant),
    };

/// `/staff/leave` -- the signed-in staff/accountant member's own leave
/// requests, newest first, with a form to submit a new one. No edit, no
/// cancel, no delete -- a submitted request is immutable from the staff
/// side (see the design spec's "Cancellation" decision).
class LeaveScreen extends ConsumerWidget {
  const LeaveScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider).value;
    final staffId = user?.id;
    final filter = (staffId: staffId, status: null);
    final requestsAsync = staffId == null
        ? AsyncValue<List<LeaveRequest>>.data(const [])
        : ref.watch(leaveRequestsProvider(filter));

    return Scaffold(
      appBar: AppBar(title: const Text('Leave Management')),
      body: AsyncView(
        value: requestsAsync,
        onRetry:
            staffId == null ? null : () => ref.invalidate(leaveRequestsProvider(filter)),
        empty: () => const EmptyState(
          icon: Icons.event_busy_outlined,
          title: 'No leave requests yet',
          message: 'Tap + to request time off.',
        ),
        data: (list) {
          final scheme = Theme.of(context).colorScheme;
          final sorted = [...list]
            ..sort((a, b) => b.startDate.compareTo(a.startDate));
          return ListView(
            padding: const EdgeInsets.all(Spacing.md),
            children: [
              for (final request in sorted)
                Card(
                  child: ListTile(
                    title: Text(
                      '${_dateFormat.format(request.startDate)} – '
                      '${_dateFormat.format(request.endDate)}',
                    ),
                    subtitle: request.reason != null && request.reason!.isNotEmpty
                        ? Text(request.reason!)
                        : null,
                    trailing: Builder(
                      builder: (context) {
                        final (background, foreground) =
                            _statusColors(scheme, request.status);
                        return Chip(
                          label: Text(_statusLabel(request.status)),
                          labelStyle: TextStyle(color: foreground),
                          backgroundColor: background,
                          side: BorderSide.none,
                        );
                      },
                    ),
                  ),
                ),
            ],
          );
        },
      ),
      floatingActionButton: staffId == null
          ? null
          : FloatingActionButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => LeaveRequestFormScreen(staffId: staffId),
                ),
              ),
              child: const Icon(Icons.add),
            ),
    );
  }
}

/// Submit-leave form. Always creates a new request via
/// [LeaveRequestRepository.create] -- there is no edit mode, since a
/// submitted request can never be changed by the staff member who made
/// it.
class LeaveRequestFormScreen extends ConsumerStatefulWidget {
  const LeaveRequestFormScreen({super.key, required this.staffId});

  final String staffId;

  @override
  ConsumerState<LeaveRequestFormScreen> createState() =>
      _LeaveRequestFormScreenState();
}

class _LeaveRequestFormScreenState extends ConsumerState<LeaveRequestFormScreen> {
  final _reason = TextEditingController();
  DateTimeRange? _range;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _reason.dispose();
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

  Future<void> _submit() async {
    final range = _range;
    if (range == null) {
      setState(() => _error = 'Pick a date range.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final reason = _reason.text.trim();
      await ref.read(leaveRequestRepositoryProvider).create(
            staffId: widget.staffId,
            range: range,
            reason: reason.isEmpty ? null : reason,
          );
      ref.invalidate(leaveRequestsProvider);
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

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Request leave')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(Spacing.lg),
              children: [
                ListTile(
                  key: const Key('leave-form-date-range'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Date range'),
                  subtitle: Text(
                    _range == null
                        ? 'Required'
                        : '${_dateFormat.format(_range!.start)} – '
                            '${_dateFormat.format(_range!.end)}',
                  ),
                  onTap: _pickRange,
                ),
                const SizedBox(height: Spacing.sm),
                TextField(
                  key: const Key('leave-form-reason'),
                  controller: _reason,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Reason',
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
                  onPressed: _busy ? null : _submit,
                  child: const Text('Submit'),
                ),
              ],
            ),
          ),
        ),
      );
}
