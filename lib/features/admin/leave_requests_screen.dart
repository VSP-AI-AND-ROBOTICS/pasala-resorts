import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/errors.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/failure_view.dart';
import '../../data/models/leave_request.dart';
import '../../data/repositories/leave_request_repository.dart';
import '../../data/repositories/profile_directory_repository.dart';

final _dateFormat = DateFormat('d MMM yyyy');

String _statusLabel(LeaveStatus status) => switch (status) {
      LeaveStatus.pending => 'Pending',
      LeaveStatus.approved => 'Approved',
      LeaveStatus.rejected => 'Rejected',
    };

/// `/admin/leave-requests` -- admin-only (a write action, not the
/// staff-or-above carve-out `/admin/dashboard`/`/admin/reports` get).
/// Defaults to the pending queue (per the approved design); a status
/// filter switches to seeing everything.
class LeaveRequestsScreen extends ConsumerStatefulWidget {
  const LeaveRequestsScreen({super.key});

  @override
  ConsumerState<LeaveRequestsScreen> createState() => _LeaveRequestsScreenState();
}

class _LeaveRequestsScreenState extends ConsumerState<LeaveRequestsScreen> {
  String? _staffId;
  LeaveStatus? _statusFilter = LeaveStatus.pending;

  @override
  Widget build(BuildContext context) {
    final filter = (staffId: _staffId, status: _statusFilter);
    final requests = ref.watch(leaveRequestsProvider(filter));
    final profiles = ref.watch(adminProfilesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Leave requests')),
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
                        key: const Key('leave-staff-picker'),
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
                Expanded(
                  child: DropdownButtonFormField<LeaveStatus?>(
                    key: const Key('leave-status-filter'),
                    initialValue: _statusFilter,
                    decoration: const InputDecoration(labelText: 'Status'),
                    items: const [
                      DropdownMenuItem(value: null, child: Text('All')),
                      DropdownMenuItem(
                        value: LeaveStatus.pending,
                        child: Text('Pending'),
                      ),
                      DropdownMenuItem(
                        value: LeaveStatus.approved,
                        child: Text('Approved'),
                      ),
                      DropdownMenuItem(
                        value: LeaveStatus.rejected,
                        child: Text('Rejected'),
                      ),
                    ],
                    onChanged: (value) => setState(() => _statusFilter = value),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: AsyncView(
              value: requests,
              onRetry: () => ref.invalidate(leaveRequestsProvider(filter)),
              empty: () => EmptyState(
                icon: Icons.event_busy_outlined,
                title: _statusFilter == LeaveStatus.pending
                    ? 'No pending requests'
                    : 'No leave requests',
                message: _statusFilter == LeaveStatus.pending
                    ? 'Nothing needs a decision right now.'
                    : 'No requests match this filter.',
              ),
              data: (list) => ListView(
                children: [
                  for (final request in list)
                    Padding(
                      key: Key('leave-row-${request.id}'),
                      padding: const EdgeInsets.symmetric(
                        horizontal: Spacing.md,
                        vertical: Spacing.xs,
                      ),
                      child: Card(
                        child: ListTile(
                          title: Text(request.staffName ?? request.staffId),
                          subtitle: Text(
                            [
                              '${_dateFormat.format(request.startDate)} – '
                                  '${_dateFormat.format(request.endDate)}',
                              if (request.reason != null &&
                                  request.reason!.isNotEmpty)
                                request.reason!,
                              _statusLabel(request.status),
                            ].join(' · '),
                          ),
                          trailing: request.status == LeaveStatus.pending
                              ? Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      key: Key('approve-${request.id}'),
                                      icon: const Icon(Icons.check_circle_outline),
                                      tooltip: 'Approve',
                                      onPressed: () =>
                                          _decide(filter, request, approved: true),
                                    ),
                                    IconButton(
                                      key: Key('reject-${request.id}'),
                                      icon: const Icon(Icons.cancel_outlined),
                                      tooltip: 'Reject',
                                      onPressed: () =>
                                          _decide(filter, request, approved: false),
                                    ),
                                  ],
                                )
                              : null,
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

  Future<void> _decide(
    LeaveRequestFilter filter,
    LeaveRequest request, {
    required bool approved,
  }) async {
    try {
      await ref
          .read(leaveRequestRepositoryProvider)
          .decide(id: request.id, approved: approved);
      ref.invalidate(leaveRequestsProvider(filter));
    } on BookingFailure catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(FailureView.messageFor(e))));
      }
    }
  }
}
