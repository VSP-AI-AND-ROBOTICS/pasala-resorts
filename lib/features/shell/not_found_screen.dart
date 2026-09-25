import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/current_resort.dart';
import '../../core/router.dart';
import '../../core/theme/tokens.dart';
import '../../data/repositories/auth_repository.dart';

/// Shown for an unknown path (`/404`, the router's `errorBuilder`) and by
/// `ResortUnitGuard` for a unit the caller cannot read.
///
/// The title is a level-1 heading so screen readers announce the page (on
/// web it renders as an `<h1>` in the semantics tree, which the E2E suite's
/// `waitForFlutter` also keys off).
///
/// A redirect lands on `/404` outside the shell -- no app bar, no nav --
/// so the screen carries its own way back: the user's landing page, or
/// sign-in when signed out.
class NotFoundScreen extends StatelessWidget {
  const NotFoundScreen({super.key});

  /// Read on tap, not watched: the screen also renders where no user
  /// provider is set up (e.g. a bare widget test).
  void _goHome(BuildContext context) {
    final container = ProviderScope.containerOf(context);
    final user = container.read(currentUserProvider).value;
    context.go(user == null
        ? '/login'
        : landingPathFor(user, container.read(currentResortProvider)));
  }

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
              const SizedBox(height: Spacing.md),
              FilledButton.tonal(
                onPressed: () => _goHome(context),
                child: const Text('Go to my home page'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
