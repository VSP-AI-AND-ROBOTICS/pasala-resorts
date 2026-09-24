import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/failure_view.dart';
import '../../data/models/service_request.dart';
import '../../data/repositories/profile_directory_repository.dart';
import '../../data/repositories/service_request_repository.dart';

/// `/admin/service-requests` -- every request, assignable to any staff
/// member. Mirrors `tasks_screen.dart`'s staff-picker + status shape.
class ServiceRequestsScreen extends ConsumerStatefulWidget {
  const ServiceRequestsScreen({super.key});

  @override
  ConsumerState<ServiceRequestsScreen> createState() => _ServiceRequestsScreenState();
}

class _ServiceRequestsScreenState extends ConsumerState<ServiceRequestsScreen> {
  ServiceRequestStatus? _statusFilter;

  Future<void> _assign(String id, String staffId) async {
    try {
      await ref.read(serviceRequestRepositoryProvider).assign(id: id, staffId: staffId);
      ref.invalidate(serviceRequestsProvider((assignedStaffId: null, status: _statusFilter)));
    } on BookingFailure catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(FailureView.messageFor(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final filter = (assignedStaffId: null, status: _statusFilter);
    final requestsAsync = ref.watch(serviceRequestsProvider(filter));
    final profiles = ref.watch(adminProfilesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Service Requests')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(Spacing.md),
            child: DropdownButtonFormField<ServiceRequestStatus?>(
              initialValue: _statusFilter,
              decoration: const InputDecoration(labelText: 'Status'),
              items: [
                const DropdownMenuItem(value: null, child: Text('All')),
                for (final s in ServiceRequestStatus.values)
                  DropdownMenuItem(value: s, child: Text(serviceRequestStatusLabel(s))),
              ],
              onChanged: (value) => setState(() => _statusFilter = value),
            ),
          ),
          Expanded(
            child: AsyncView(
              value: requestsAsync,
              onRetry: () => ref.invalidate(serviceRequestsProvider(filter)),
              empty: () => const EmptyState(
                icon: Icons.room_service_outlined,
                title: 'No requests match this filter',
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
                          Row(
                            children: [
                              Expanded(
                                child: profiles.when(
                                  loading: () => const SizedBox.shrink(),
                                  error: (_, _) => const SizedBox.shrink(),
                                  data: (list) {
                                    final staffOrAbove = list
                                        .where((p) => p.isStaffOrAbove)
                                        .toList();
                                    return DropdownButtonFormField<String?>(
                                      initialValue: r.assignedStaffId,
                                      decoration: const InputDecoration(labelText: 'Assign to'),
                                      items: [
                                        const DropdownMenuItem(value: null, child: Text('Unassigned')),
                                        for (final p in staffOrAbove)
                                          DropdownMenuItem(
                                              value: p.id, child: Text(p.fullName ?? p.email)),
                                      ],
                                      onChanged: (staffId) =>
                                          staffId == null ? null : _assign(r.id, staffId),
                                    );
                                  },
                                ),
                              ),
                              const SizedBox(width: Spacing.sm),
                              Chip(
                                label: Text(serviceRequestStatusLabel(r.status)),
                                side: BorderSide.none,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
