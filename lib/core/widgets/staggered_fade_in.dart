import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Fades and slides [child] into place, finishing later for higher
/// [index] values so a list's items appear to cascade in rather than pop
/// in all at once. The stagger is capped so a long list doesn't take
/// seconds to finish animating.
class StaggeredFadeIn extends StatelessWidget {
  const StaggeredFadeIn({super.key, required this.index, required this.child});

  final int index;
  final Widget child;

  static const _stepMs = 60;
  static const _maxDelayMs = 480;

  @override
  Widget build(BuildContext context) {
    final delay = Duration(
      milliseconds: (index * _stepMs).clamp(0, _maxDelayMs),
    );
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: PasalaTokens.motionBase + delay,
      curve: Curves.easeOut,
      builder: (context, value, animatedChild) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, (1 - value) * 16),
          child: animatedChild,
        ),
      ),
      child: child,
    );
  }
}
