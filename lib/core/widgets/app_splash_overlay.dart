import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'brand_mark.dart';

/// A brief branded fade-in shown once per cold start, layered on top of
/// whatever [child] the router first builds. Purely cosmetic — it does
/// not gate on or wait for auth state, so it can never block navigation
/// if a network call is slow.
class AppSplashOverlay extends StatefulWidget {
  const AppSplashOverlay({super.key, required this.child});

  final Widget child;

  @override
  State<AppSplashOverlay> createState() => _AppSplashOverlayState();
}

class _AppSplashOverlayState extends State<AppSplashOverlay> {
  bool _showOverlay = true;
  double _opacity = 1;
  Timer? _fadeTimer;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    _fadeTimer = Timer(PasalaTokens.motionBase, () {
      if (mounted) setState(() => _opacity = 0);
    });
    _hideTimer = Timer(PasalaTokens.motionBase * 2, () {
      if (mounted) setState(() => _showOverlay = false);
    });
  }

  @override
  void dispose() {
    _fadeTimer?.cancel();
    _hideTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_showOverlay)
          IgnorePointer(
            child: AnimatedOpacity(
              opacity: _opacity,
              duration: PasalaTokens.motionBase,
              child: ColoredBox(
                color: Theme.of(context).colorScheme.surface,
                child: const Center(
                  child: BrandMark(
                    size: BrandMarkSize.splash,
                    showWordmark: false,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
