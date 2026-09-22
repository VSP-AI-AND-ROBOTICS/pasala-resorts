import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/features/booking/booking_screen.dart';

void main() {
  group('formatHoldRemaining', () {
    test('formats minutes and seconds, matching the "14:32 left" banner', () {
      expect(formatHoldRemaining(const Duration(minutes: 14, seconds: 32)),
          '14:32 left');
    });

    test('pads single-digit seconds', () {
      expect(
          formatHoldRemaining(const Duration(minutes: 2, seconds: 5)),
          '02:05 left');
    });

    test('pads single-digit minutes', () {
      expect(
          formatHoldRemaining(const Duration(minutes: 9, seconds: 59)),
          '09:59 left');
    });

    test('reaches zero and reads 00:00 left', () {
      expect(formatHoldRemaining(Duration.zero), '00:00 left');
    });

    test('clamps a negative duration to zero rather than showing a minus sign', () {
      expect(formatHoldRemaining(const Duration(seconds: -5)), '00:00 left');
    });

    test('rolls minutes past the ones digit correctly', () {
      expect(
          formatHoldRemaining(const Duration(minutes: 15, seconds: 0)),
          '15:00 left');
    });
  });
}
