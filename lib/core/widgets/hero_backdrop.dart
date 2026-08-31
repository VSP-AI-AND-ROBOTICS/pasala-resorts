import 'package:flutter/material.dart';

/// A full-bleed image with a bottom-weighted dark scrim, used behind
/// foreground content on login, signup, browse's header, and the booking
/// confirmation screen. Centralises the scrim gradient so it isn't
/// recomputed three times with slightly different numbers.
class HeroBackdrop extends StatelessWidget {
  const HeroBackdrop({
    super.key,
    required this.imageAsset,
    required this.child,
    this.scrimOpacity = 0.55,
  });

  final String imageAsset;
  final Widget child;
  final double scrimOpacity;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(imageAsset, fit: BoxFit.cover),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.0),
                Colors.black.withValues(alpha: scrimOpacity),
              ],
            ),
          ),
        ),
        child,
      ],
    );
  }
}
