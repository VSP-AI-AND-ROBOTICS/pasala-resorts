import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_assets.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/brand_mark.dart';
import '../../core/widgets/hero_backdrop.dart';

/// The app's very first screen. Reuses the cinematic night aerial photo
/// (the same one login/signup use) for a consistent night-time mood across
/// the whole pre-auth flow. Auto-advances to
/// `/welcome` after a brief delay -- a signed-out user never has to tap
/// anything to get past it, and a signed-in user never even sees it, since
/// `redirectFor` (see `core/router.dart`) sends them straight to their
/// landing path before this widget builds.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  static const _autoAdvanceDelay = Duration(milliseconds: 1500);
  late Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(_autoAdvanceDelay, () {
      if (mounted) context.go('/welcome');
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: HeroBackdrop(
        imageAsset: AppAssets.heroNightAerial,
        scrimOpacity: 0.6,
        child: Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: PasalaTokens.motionBase,
            curve: Curves.easeOut,
            builder: _fadeIn,
            child: const BrandMark(size: BrandMarkSize.splash, showWordmark: false),
          ),
        ),
      ),
    );
  }

  static Widget _fadeIn(BuildContext context, double value, Widget? child) =>
      Opacity(opacity: value, child: child);
}
