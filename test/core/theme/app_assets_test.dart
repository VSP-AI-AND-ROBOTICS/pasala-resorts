import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/theme/app_assets.dart';

void main() {
  test('every declared asset path exists on disk', () {
    const paths = [
      AppAssets.logoMark,
      AppAssets.heroNightAerial,
      AppAssets.heroDayAerial,
      AppAssets.cottagesPoolRow,
      AppAssets.cottagesDallasVegas,
      AppAssets.cottagesBostonDetroit,
      AppAssets.eventStringLights,
      AppAssets.facadeDaytime,
      AppAssets.patioFirepitNight,
      AppAssets.entranceGateNight,
    ];

    for (final path in paths) {
      expect(File(path).existsSync(), isTrue, reason: '$path is missing');
    }
  });
}
