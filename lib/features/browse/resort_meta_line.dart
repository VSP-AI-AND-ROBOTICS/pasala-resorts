import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/theme/tokens.dart';
import '../../data/models/resort_search.dart';

/// A browse card's summary line: the rating, the distance and the lowest
/// nightly price. Each piece shows only when `search_resorts` returned it.
/// It renders nothing when there is nothing to show, so admin screens
/// that reuse `PropertyCard` without search data look exactly as before.
/// Every piece carries an icon and text; none relies on colour.
class ResortMetaLine extends StatelessWidget {
  const ResortMetaLine({
    super.key,
    this.avgRating,
    this.reviewCount = 0,
    this.distanceKm,
    this.minPrice,
  });

  final double? avgRating;
  final int reviewCount;
  final double? distanceKm;
  final num? minPrice;

  bool get _hasRating => avgRating != null && reviewCount > 0;

  @override
  Widget build(BuildContext context) {
    if (!_hasRating && distanceKm == null && minPrice == null) {
      return const SizedBox.shrink();
    }
    final scheme = Theme.of(context).colorScheme;
    final style = Theme.of(context)
        .textTheme
        .bodyMedium
        ?.copyWith(color: scheme.onSurfaceVariant);

    Widget piece(IconData icon, String text, String semantics) => Semantics(
          label: semantics,
          excludeSemantics: true,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: scheme.onSurfaceVariant),
              const SizedBox(width: Spacing.xs),
              Text(text, style: style),
            ],
          ),
        );

    final rating = avgRating?.toStringAsFixed(1);
    return Padding(
      padding: const EdgeInsets.only(top: Spacing.xs),
      child: Wrap(
        spacing: Spacing.md,
        runSpacing: Spacing.xs,
        children: [
          if (_hasRating)
            piece(
              Icons.star_rounded,
              '$rating ($reviewCount)',
              'Rated $rating out of 5 from $reviewCount '
                  '${reviewCount == 1 ? 'review' : 'reviews'}',
            ),
          if (distanceKm != null)
            piece(
              Icons.near_me_outlined,
              distanceLabel(distanceKm!),
              '${distanceLabel(distanceKm!)} away',
            ),
          if (minPrice != null)
            piece(
              Icons.sell_outlined,
              'from ${formatInr(minPrice!)} / night',
              'from ${formatInr(minPrice!)} per night',
            ),
        ],
      ),
    );
  }
}
