import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_assets.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/brand_mark.dart';
import '../../core/widgets/hero_backdrop.dart';

/// The Sign In / Sign Up chooser shown after the splash screen. Both
/// existing forms (`LoginScreen`/`SignupScreen`) are reached from here, and
/// both are still independently reachable by deep link -- this screen adds
/// a front door, it doesn't become the only way in.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: HeroBackdrop(
        imageAsset: AppAssets.heroNightAerial,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(Spacing.lg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const BrandMark(
                    size: BrandMarkSize.splash,
                    showWordmark: false,
                  ),
                  const SizedBox(height: Spacing.md),
                  Text(
                    'Pasala Resorts',
                    style: textTheme.headlineMedium
                        ?.copyWith(color: Colors.white),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: Spacing.xs),
                  Text(
                    'A boutique farmhouse getaway',
                    style: textTheme.bodyLarge?.copyWith(color: Colors.white70),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: Spacing.xl),
                  FilledButton(
                    onPressed: () => context.go('/login'),
                    child: const Text('Sign In'),
                  ),
                  const SizedBox(height: Spacing.sm),
                  OutlinedButton(
                    onPressed: () => context.go('/signup'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white),
                    ),
                    child: const Text('Sign Up'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
