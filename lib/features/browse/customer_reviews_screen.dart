import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/empty_state.dart';
import '../../data/models/review.dart';
import '../../data/repositories/review_repository.dart';

/// `/reviews` -- every guest review, newest first, reachable by any
/// signed-in customer (not just admin/staff) now that `reviews_read`
/// (0044_resort_policies.sql) makes active resorts' reviews public in the
/// app. The property page's own Reviews section links here for the full
/// list.
class CustomerReviewsScreen extends ConsumerWidget {
  const CustomerReviewsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reviewsAsync = ref.watch(allReviewsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Guest Reviews')),
      body: AsyncView(
        value: reviewsAsync,
        onRetry: () => ref.invalidate(allReviewsProvider),
        empty: () => const EmptyState(
          icon: Icons.star_outline,
          title: 'No reviews yet',
          message: 'Be the first to share how your stay went.',
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
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                for (var i = 1; i <= 5; i++)
                  Icon(
                    i <= review.overallRating ? Icons.star : Icons.star_border,
                    size: 18,
                    color: Colors.amber,
                  ),
                const SizedBox(width: Spacing.sm),
                Text(review.customerFirstName ?? 'Guest',
                    style: textTheme.titleSmall),
                const Spacer(),
                if (review.createdAt != null)
                  Text(formatDate(review.createdAt!.toLocal()),
                      style: textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant)),
              ],
            ),
            if (review.feedback.isNotEmpty) ...[
              const SizedBox(height: Spacing.sm),
              Text(review.feedback, style: textTheme.bodyMedium),
            ],
          ],
        ),
      ),
    );
  }
}
