import 'package:flutter_test/flutter_test.dart';
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
}
