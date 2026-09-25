import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';

/// Shown for an unknown path (`/404`, the router's `errorBuilder`) and by
/// `ResortUnitGuard` for a unit the caller cannot read.
///
/// The title is a level-1 heading so screen readers announce the page (on
/// web it renders as an `<h1>` in the semantics tree, which the E2E suite's
/// `waitForFlutter` also keys off).
class NotFoundScreen extends StatelessWidget {
  const NotFoundScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(Spacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(
                header: true,
                headingLevel: 1,
                child: Text('Page not found', style: textTheme.headlineSmall),
              ),
              const SizedBox(height: Spacing.sm),
              Text(
                "This page doesn't exist, or you don't have access to it.",
                style: textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
