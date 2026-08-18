import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/theme/app_assets.dart';
import 'package:pasala/data/models/unit.dart';
import 'package:pasala/features/browse/property_screen.dart';

void main() {
  group('bookingModeLabel', () {
    test('nightly mode reads Nightly', () {
      expect(bookingModeLabel(BookingMode.nightly), 'Nightly');
    });

    test('slot mode reads Slots', () {
      expect(bookingModeLabel(BookingMode.slot), 'Slots');
    });

    test('both mode reads Nightly or slots', () {
      expect(bookingModeLabel(BookingMode.both), 'Nightly or slots');
    });
  });

  group('unitPhoto', () {
    test('Dallas and Las Vegas share the Dallas/Vegas cottage photo', () {
      expect(unitPhoto('Dallas'), AppAssets.cottagesDallasVegas);
      expect(unitPhoto('Las Vegas'), AppAssets.cottagesDallasVegas);
    });

    test('Boston and Detroit share the Boston/Detroit cottage photo', () {
      expect(unitPhoto('Boston'), AppAssets.cottagesBostonDetroit);
      expect(unitPhoto('Detroit'), AppAssets.cottagesBostonDetroit);
    });

    test('any other unit name falls back to the pool row photo', () {
      expect(unitPhoto('New York'), AppAssets.cottagesPoolRow);
      expect(unitPhoto('Miami'), AppAssets.cottagesPoolRow);
      expect(unitPhoto('Some Future Unit'), AppAssets.cottagesPoolRow);
    });
  });
}
