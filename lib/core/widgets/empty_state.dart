import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Shown when a query succeeded and returned nothing. Distinct from an
/// error: nothing is wrong, there is simply nothing yet.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
    this.image,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  /// An optional bundled illustration asset path. When set, it replaces
  /// [icon] entirely rather than sitting alongside it.
  final String? image;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (image != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(PasalaTokens.radiusMd),
                child: Image.asset(
                  image!,
                  width: 160,
                  height: 100,
                  fit: BoxFit.cover,
                ),
              )
            else
              Icon(icon, size: 48, color: scheme.onSurfaceVariant),
            const SizedBox(height: Spacing.md),
            Text(title,
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center),
            if (message != null) ...[
              const SizedBox(height: Spacing.sm),
              Text(
                message!,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: scheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: Spacing.lg),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
