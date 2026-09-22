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
    // A plain `Center` overflows ("BOTTOM OVERFLOWED BY n PIXELS") whenever
    // this sits inside a bounded space shorter than the icon+title+message
    // content -- e.g. the Reports screen's revenue/occupancy tables, whose
    // filter row and segmented control above eat into the Expanded region
    // this occupies. `LayoutBuilder` + `ConstrainedBox(minHeight: ...)`
    // keeps the usual centered look when there's room, and falls back to
    // scrolling instead of clipping when there isn't.
    //
    // Some callers (working_hours_screen, daily_status_screen) instead
    // place this inside an already-scrollable, height-UNbounded ancestor
    // (a ListView/sliver), where `constraints.maxHeight` is infinite --
    // forcing `minHeight: infinity` there crashes with "BoxConstraints
    // forces an infinite height" instead of just rendering at its natural
    // size, which is exactly what that case needs. Only pin the height
    // when the incoming constraint is actually finite.
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight:
                constraints.hasBoundedHeight ? constraints.maxHeight : 0,
          ),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(Spacing.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (image != null)
                    ClipRRect(
                      borderRadius:
                          BorderRadius.circular(PasalaTokens.radiusMd),
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
          ),
        ),
      ),
    );
  }
}
