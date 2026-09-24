import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/current_resort.dart';
import '../../core/errors.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/failure_view.dart';
import '../../data/models/service_request.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/service_request_repository.dart';

/// `/staff/service-requests` -- the signed-in staff member's own assigned
/// requests, status-only, mirroring `assigned_tasks_screen.dart`.
class StaffServiceRequestsScreen extends ConsumerWidget {
  const StaffServiceRequestsScreen({super.key});

  Future<void> _updateStatus(WidgetRef ref, BuildContext context,
      ServiceRequestFilter filter, String id, ServiceRequestStatus status) async {
    try {
      await ref.read(serviceRequestRepositoryProvider).updateStatus(id: id, status: status);
      ref.invalidate(serviceRequestsProvider(filter));
    } on BookingFailure catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(FailureView.messageFor(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider).value;
    final staffId = user?.id;
    final propertyId = ref.watch(currentResortProvider)!.propertyId;
    final filter = (propertyId: propertyId, assignedStaffId: staffId, status: null);
    final requestsAsync = staffId == null
        ? const AsyncValue<List<ServiceRequest>>.data([])
        : ref.watch(serviceRequestsProvider(filter));

    return Scaffold(
      appBar: AppBar(title: const Text('My Service Requests')),
      body: AsyncView(
        value: requestsAsync,
        onRetry: staffId == null ? null : () => ref.invalidate(serviceRequestsProvider(filter)),
        empty: () => const EmptyState(
          icon: Icons.room_service_outlined,
          title: 'No requests assigned yet',
        ),
        data: (requests) => ListView.builder(
          padding: const EdgeInsets.all(Spacing.md),
          itemCount: requests.length,
          itemBuilder: (context, i) {
            final r = requests[i];
            return Card(
              margin: const EdgeInsets.only(bottom: Spacing.sm),
              child: Padding(
                padding: const EdgeInsets.all(Spacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(serviceRequestCategoryLabel(r.category),
                        style: Theme.of(context).textTheme.titleMedium),
                    if (r.description.isNotEmpty) Text(r.description),
                    const SizedBox(height: Spacing.sm),
                    DropdownButton<ServiceRequestStatus>(
                      value: r.status,
                      items: [
                        for (final s in ServiceRequestStatus.values)
                          DropdownMenuItem(value: s, child: Text(serviceRequestStatusLabel(s))),
                      ],
                      onChanged: (s) =>
                          s == null ? null : _updateStatus(ref, context, filter, r.id, s),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
