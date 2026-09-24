import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/current_resort.dart';
import '../../core/format.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/empty_state.dart';
import '../../data/models/review.dart';
import '../../data/repositories/review_repository.dart';

/// `/admin/reviews` -- the current resort's guest reviews, newest first.
class AdminReviewsScreen extends ConsumerWidget {
  const AdminReviewsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final propertyId = ref.watch(currentResortProvider)!.propertyId;
    final reviewsAsync = ref.watch(propertyReviewsProvider(propertyId));

    return Scaffold(
      appBar: AppBar(title: const Text('Reviews')),
      body: AsyncView(
        value: reviewsAsync,
        onRetry: () => ref.invalidate(propertyReviewsProvider(propertyId)),
        empty: () => const EmptyState(
          icon: Icons.star_outline,
          title: 'No reviews yet',
          message: 'Guest reviews will appear here after checkout.',
        ),
        data: (reviews) => ListView.builder(
          padding: const EdgeInsets.all(Spacing.md),
          itemCount: reviews.length,
          itemBuilder: (context, i) => Padding(
            padding: const EdgeInsets.only(bottom: Spacing.sm),
            child: _ReviewCard(review: reviews[i]),
          ),
        ),
      ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.review});

  final Review review;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final createdAt = review.createdAt?.toLocal();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.star, color: Colors.amber, size: 20),
                const SizedBox(width: Spacing.xs),
                Text('${review.overallRating}/5',
                    style: textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const Spacer(),
                if (createdAt != null)
                  Text(formatDate(createdAt),
                      style: textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant)),
              ],
            ),
            if (review.feedback.isNotEmpty) ...[
              const SizedBox(height: Spacing.xs),
              Text('"${review.feedback}"',
                  style: textTheme.bodyMedium?.copyWith(
                      fontStyle: FontStyle.italic,
                      color: scheme.onSurfaceVariant)),
            ],
            const SizedBox(height: Spacing.sm),
            Wrap(
              spacing: Spacing.sm,
              runSpacing: Spacing.xs,
              children: [
                _RatingChip(label: 'Farmhouse', value: review.farmhouseRating),
                _RatingChip(
                    label: 'Cleanliness', value: review.cleanlinessRating),
                _RatingChip(label: 'Food', value: review.foodRating),
                _RatingChip(label: 'Service', value: review.serviceRating),
                _RatingChip(
                    label: 'Activities', value: review.activitiesRating),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RatingChip extends StatelessWidget {
  const _RatingChip({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Chip(
      label: Text('$label $value/5'),
      backgroundColor: scheme.surfaceContainerHigh,
      side: BorderSide.none,
      visualDensity: VisualDensity.compact,
    );
  }
}
