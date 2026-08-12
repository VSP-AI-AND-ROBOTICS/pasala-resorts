import 'package:flutter/material.dart';

import '../theme/app_assets.dart';
import '../theme/tokens.dart';

enum BrandMarkSize { splash, appBar }

/// The Pasala Resorts logo mark (emblem + wordmark image), shown in the
/// app shell's app bar, on login/signup, and in the cold-start splash
/// moment. A single place to change if the mark or its accessible label
/// ever changes.
class BrandMark extends StatelessWidget {
  const BrandMark({
    super.key,
    this.size = BrandMarkSize.appBar,
    this.showWordmark = true,
  });

  final BrandMarkSize size;
  final bool showWordmark;

  double get _imageSize => switch (size) {
        BrandMarkSize.splash => 96,
        BrandMarkSize.appBar => 28,
      };

  @override
  Widget build(BuildContext context) {
    final mark = Semantics(
      label: 'Pasala Resorts',
      image: true,
      excludeSemantics: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(PasalaTokens.radiusSm),
        child: Image.asset(
          AppAssets.logoMark,
          width: _imageSize,
          height: _imageSize,
          fit: BoxFit.cover,
        ),
      ),
    );

    if (!showWordmark) return mark;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        mark,
        const SizedBox(width: Spacing.sm),
        Text(
          'Pasala Resorts',
          style: Theme.of(context).textTheme.titleLarge,
          semanticsLabel: '',
        ),
      ],
    );
  }
}
