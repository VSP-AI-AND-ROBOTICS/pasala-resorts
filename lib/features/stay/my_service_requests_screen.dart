import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/empty_state.dart';
import '../../data/models/service_request.dart';
import '../../data/repositories/service_request_repository.dart';

class MyServiceRequestsScreen extends ConsumerWidget {
  const MyServiceRequestsScreen({super.key, required this.reservationId});

  final String reservationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requestsAsync = ref.watch(myServiceRequestsProvider(reservationId));

    return Scaffold(
      appBar: AppBar(title: const Text('My Service Requests')),
      body: AsyncView(
        value: requestsAsync,
        onRetry: () => ref.invalidate(myServiceRequestsProvider(reservationId)),
        empty: () => const EmptyState(
          icon: Icons.room_service_outlined,
          title: 'No service requests yet',
        ),
        data: (requests) => ListView.builder(
          padding: const EdgeInsets.all(Spacing.md),
          itemCount: requests.length,
          itemBuilder: (context, i) {
            final r = requests[i];
            return Card(
              margin: const EdgeInsets.only(bottom: Spacing.sm),
              child: ListTile(
                title: Text(serviceRequestCategoryLabel(r.category)),
                subtitle: r.description.isEmpty ? null : Text(r.description),
                trailing: Chip(
                  label: Text(serviceRequestStatusLabel(r.status)),
                  side: BorderSide.none,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
