import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/failure_view.dart';
import '../../data/models/property.dart';
import 'providers.dart';

class BrowseScreen extends ConsumerWidget {
  const BrowseScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final properties = ref.watch(propertiesProvider);

    return properties.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => FailureView(
        error: e,
        onRetry: () => ref.invalidate(propertiesProvider),
      ),
      data: (list) => RefreshIndicator(
        onRefresh: () async => ref.invalidate(propertiesProvider),
        child: ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: list.length,
          itemBuilder: (context, i) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: PropertyCard(
              property: list[i],
              onTap: () => context.go('/property/${list[i].id}'),
            ),
          ),
        ),
      ),
    );
  }
}

class PropertyCard extends StatelessWidget {
  const PropertyCard({super.key, required this.property, this.onTap});

  final Property property;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(property.name,
                    style: Theme.of(context).textTheme.titleLarge),
                if (property.address != null) ...[
                  const SizedBox(height: 4),
                  Text(property.address!,
                      style: Theme.of(context).textTheme.bodyMedium),
                ],
                const SizedBox(height: 8),
                Text('Check-in ${property.checkInTime} · '
                    'Check-out ${property.checkOutTime}'),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final a in property.amenities) Chip(label: Text(a)),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
}
